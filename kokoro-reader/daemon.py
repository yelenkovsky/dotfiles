"""Kokoro read-aloud daemon.

Keeps the Kokoro model loaded on the GPU and reads text sentence by sentence.
Started on demand by read-aloud (client.py); exits after IDLE_EXIT_SECONDS
without use so it does not hold VRAM all day.

Control comes two ways:
  * a Unix socket for read-aloud (one request per connection, UTF-8):
      SPEAK\\n<text>   read <text>, replacing anything being read
      STOP | PAUSE (toggle) | NEXT | PREV
      SPEED <x> | SPEED +<d> | SPEED -<d>     set or step the speed
      VOICE <id>                               e.g. af_heart, bf_emma
      STATUS                                   JSON state
  * MPRIS (org.mpris.MediaPlayer2.kokoro_reader) while a text is loaded, so
    media keys, headphone buttons and the Omarchy Media bar widget work.
    Next/Previous move by sentence; Rate is the speed.

Settings (voice, speed) persist in ~/.config/kokoro-reader/settings.json.
"""

import asyncio
import json
import os
import re
import socket
import threading
import time

import numpy as np

# Name the PipeWire stream after the MPRIS Identity. Omarchy's media service
# matches players to their audio streams by name; as "PipeWire ALSA [python3.12]"
# the reader would lose the media keys to any other playing app.
os.environ.setdefault("PIPEWIRE_PROPS", '{ application.name = "Read aloud" }')
import sounddevice as sd  # noqa: E402  (PortAudio must see the variable above)

SAMPLE_RATE = 24000
IDLE_EXIT_SECONDS = 30 * 60
LOOKAHEAD = 3                      # sentences generated ahead of playback
SENTENCE_GAP = 0.12                # seconds of silence between sentences
PARAGRAPH_GAP = 0.45               # ... and after the last sentence of a paragraph
RESTART_THRESHOLD = 2.0            # Previous within this many seconds goes back a sentence
MIN_SPEED, MAX_SPEED = 0.5, 2.0
DEFAULTS = {"voice": "af_heart", "speed": 1.0}

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.sock")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "kokoro-reader")
SETTINGS_PATH = os.path.join(CONFIG_DIR, "settings.json")

MPRIS_NAME = "org.mpris.MediaPlayer2.kokoro_reader"
MPRIS_PATH = "/org/mpris/MediaPlayer2"


# --- settings ---------------------------------------------------------------

def load_settings() -> dict:
    try:
        with open(SETTINGS_PATH) as f:
            return {**DEFAULTS, **json.load(f)}
    except (OSError, ValueError):
        return dict(DEFAULTS)


def save_settings(settings: dict):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = SETTINGS_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2)
    os.replace(tmp, SETTINGS_PATH)


def clamp_speed(value: float) -> float:
    return round(min(MAX_SPEED, max(MIN_SPEED, value)), 2)


# --- text -------------------------------------------------------------------

ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr", "vs", "etc", "e.g", "i.e",
                 "cf", "fig", "no", "vol", "pp", "ch", "ed", "eds", "approx", "u.s", "u.k"}
SENTENCE_END = re.compile(r"[.!?…]+[\"”’»)\]]*(?=\s+[\"“‘«(\[]?[A-Z0-9]|\s*$)")


def clean(text: str) -> str:
    """Undo the hard line breaks that PDF and ebook selections carry."""
    text = text.replace("\r", "")
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)      # re-join hyphenated words
    text = re.sub(r"\n{2,}", "\n", text)               # paragraph break -> one newline
    text = re.sub(r"(?<!\n)\n(?!\n)(?=[a-z,;])", " ", text)  # mid-sentence wraps
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def split_sentences(text: str) -> list[tuple[str, bool]]:
    """Return (sentence, ends_paragraph) pairs."""
    out = []
    for para in clean(text).split("\n"):
        para = para.strip()
        start = 0
        for m in SENTENCE_END.finditer(para):
            words = para[start:m.start()].split()
            last = words[-1].lower() if words else ""
            if m.group() == "." and (last in ABBREVIATIONS or re.fullmatch(r"[a-z]", last)):
                continue                                # "Dr. Smith", "Martin E. P. Seligman"
            sentence = para[start:m.end()].strip()
            if sentence:
                out.append((sentence, False))
            start = m.end()
        rest = para[start:].strip()
        if rest:
            out.append((rest, False))
        if out:
            out[-1] = (out[-1][0], True)
    return out


# --- reader -----------------------------------------------------------------

class Reader:
    """Sentence queue, generation worker and audio output.

    All state below is guarded by self.cond. The audio callback only copies
    samples out of self.cache; the worker thread generates audio and publishes
    state changes to MPRIS, outside the lock.
    """

    def __init__(self):
        import torch
        from kokoro import KPipeline

        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.settings = load_settings()
        self._kpipeline = KPipeline
        self.pipelines = {}
        self.pipeline_lock = threading.Lock()
        self.pipeline_for(self.settings["voice"])  # load the model now, not on first read
        threading.Thread(target=self._preload_voices, daemon=True).start()

        self.cond = threading.Condition()
        self.sentences: list[tuple[str, bool]] = []
        self.index = 0
        self.pos = 0
        self.cache: dict[int, tuple[tuple, np.ndarray]] = {}
        self.state = "stopped"          # stopped | playing | paused
        self.finished = False
        self.version = 0                # bumped on every change MPRIS should see
        self.last_used = time.monotonic()
        self.stream = None
        self.on_change = lambda: None   # set by the MPRIS side

        threading.Thread(target=self._worker, daemon=True).start()

    # pipelines

    def pipeline_for(self, voice: str):
        lang = voice[0]                 # a = American, b = British
        with self.pipeline_lock:
            if lang not in self.pipelines:
                model = next(iter(self.pipelines.values())).model if self.pipelines else True
                pipeline = self._kpipeline(lang_code=lang, model=model, device=self.device,
                                           repo_id="hexgrad/Kokoro-82M")
                self.pipelines[lang] = pipeline
            pipeline = self.pipelines[lang]
            pipeline.load_voice(voice)  # raises if the voice does not exist
        return pipeline

    def _preload_voices(self):
        """Load every downloaded English voice (and the British G2P) in the background.

        A voice's first use otherwise costs ~4 s: a Hugging Face round trip for
        its file, plus building the British pipeline for the first bf_/bm_ voice.
        setup/kokoro-reader.sh downloads the voices the menu offers.
        """
        import glob
        from huggingface_hub.constants import HF_HUB_CACHE

        pattern = os.path.join(HF_HUB_CACHE, "models--hexgrad--Kokoro-82M", "snapshots", "*", "voices", "*.pt")
        voices = sorted({os.path.basename(p)[:-3] for p in glob.glob(pattern)})
        for voice in voices:
            if voice[:2] in ("af", "am", "bf", "bm"):
                try:
                    self.pipeline_for(voice)
                except Exception as error:
                    print(f"preloading {voice} failed: {error}", flush=True)

    def key(self) -> tuple:
        return (self.settings["voice"], self.settings["speed"])

    def _generate(self, sentence: str, ends_paragraph: bool, key: tuple) -> np.ndarray:
        voice, speed = key
        chunks = [r.audio.numpy() for r in self.pipeline_for(voice)(sentence, voice=voice, speed=speed,
                                                                      split_pattern=None)
                  if r.audio is not None]
        gap = np.zeros(int(SAMPLE_RATE * (PARAGRAPH_GAP if ends_paragraph else SENTENCE_GAP)), np.float32)
        return np.concatenate([*chunks, gap]).astype(np.float32)

    # audio

    def _callback(self, outdata, frames, _time, _status):
        out = outdata[:, 0]
        out.fill(0)
        with self.cond:
            if self.state != "playing":
                return
            filled = 0
            moved = False
            while filled < frames:
                if self.index >= len(self.sentences):
                    self.finished = True
                    self.cond.notify_all()
                    raise sd.CallbackStop
                entry = self.cache.get(self.index)
                if entry is None:
                    break               # still generating: play silence
                audio = entry[1]
                n = min(frames - filled, len(audio) - self.pos)
                out[filled:filled + n] = audio[self.pos:self.pos + n]
                filled += n
                self.pos += n
                if self.pos >= len(audio):
                    self.cache.pop(self.index - 1, None)
                    self.index += 1
                    self.pos = 0
                    moved = True
            if moved:
                self.version += 1
                self.cond.notify_all()

    def _open_stream(self):
        if self.stream is None:
            self.stream = sd.OutputStream(samplerate=SAMPLE_RATE, channels=1, dtype="float32",
                                          blocksize=1024, callback=self._callback)
        if not self.stream.active:
            self.stream.start()

    def _close_stream(self):
        stream, self.stream = self.stream, None
        if stream is not None:
            stream.abort()
            stream.close()

    # commands (called from the socket thread and the MPRIS loop)

    def speak(self, text: str):
        sentences = split_sentences(text)
        if not sentences:
            return
        self._close_stream()
        with self.cond:
            self.sentences = sentences
            self.index = self.pos = 0
            self.cache.clear()
            self.finished = False
            self.state = "playing"
            self._touch()
        self._open_stream()

    def stop(self):
        self._close_stream()
        with self.cond:
            self.sentences = []
            self.cache.clear()
            self.index = self.pos = 0
            self.finished = False
            self.state = "stopped"
            self._touch()

    def play(self):
        with self.cond:
            if self.state != "paused":
                return
            self.state = "playing"
            self._touch()
        self._open_stream()

    def pause(self):
        with self.cond:
            if self.state != "playing":
                return
            self.state = "paused"
            self._touch()
        # Release the audio device while paused; the callback already outputs silence.
        if self.stream is not None:
            self.stream.abort()

    def play_pause(self):
        if self.state == "playing":
            self.pause()
        else:
            self.play()

    def next(self):
        with self.cond:
            if self.state == "stopped":
                return
            if self.index + 1 >= len(self.sentences):
                end = True
            else:
                end = False
                self.index += 1
                self.pos = 0
                self._touch()
        if end:
            self.stop()

    def previous(self):
        with self.cond:
            if self.state == "stopped":
                return
            speed = self.settings["speed"]
            if self.pos < RESTART_THRESHOLD * SAMPLE_RATE / speed and self.index > 0:
                self.index -= 1
            self.pos = 0
            self._touch()

    def set_speed(self, value: float) -> float:
        with self.cond:
            self.settings["speed"] = clamp_speed(value)
            save_settings(self.settings)
            self._touch()
            return self.settings["speed"]

    def set_voice(self, voice: str) -> str:
        self.pipeline_for(voice)        # validate before switching
        with self.cond:
            self.settings["voice"] = voice
            save_settings(self.settings)
            self._touch()
            return voice

    def status(self) -> dict:
        with self.cond:
            sentence = self.sentences[self.index][0] if self.index < len(self.sentences) else ""
            return {"state": self.state, "voice": self.settings["voice"], "speed": self.settings["speed"],
                    "sentence": sentence, "index": self.index, "count": len(self.sentences)}

    def _touch(self):
        """Record a change; caller holds self.cond."""
        self.version += 1
        self.last_used = time.monotonic()
        self.cond.notify_all()

    # worker: generate ahead, swap audio after speed/voice changes, publish changes

    def _worker(self):
        published = -1
        while True:
            with self.cond:
                job = None
                while True:
                    if self.finished:
                        break
                    job = self._next_job()
                    if job or self.version != published:
                        break
                    self.cond.wait()
                finished = self.finished
                version = self.version
            if finished:
                self.stop()
                continue
            if job:
                index, sentence, ends_paragraph, key = job
                try:
                    audio = self._generate(sentence, ends_paragraph, key)
                except Exception as error:  # a bad voice or odd text must not kill the reader
                    print(f"generation failed for sentence {index}: {error}", flush=True)
                    audio = np.zeros(int(SAMPLE_RATE * SENTENCE_GAP), np.float32)
                self._store(index, key, audio)
            if version != published:
                published = version
                self.on_change()

    def _next_job(self):
        """First sentence from the current one on whose audio is missing or stale."""
        if self.state == "stopped":
            return None
        key = self.key()
        for i in range(self.index, min(self.index + LOOKAHEAD, len(self.sentences))):
            entry = self.cache.get(i)
            if entry is None or entry[0] != key:
                return (i, *self.sentences[i], key)
        return None

    def _store(self, index: int, key: tuple, audio: np.ndarray):
        with self.cond:
            if key != self.key() or index >= len(self.sentences):
                return                  # settings changed or text replaced meanwhile
            old = self.cache.get(index)
            if index == self.index and old is not None and self.pos:
                if old[0][0] == key[0]:
                    # New speed: carry on from the same point in the sentence.
                    self.pos = int(self.pos * len(audio) / len(old[1]))
                else:
                    self.pos = 0        # new voice: restart the sentence
            self.cache[index] = (key, audio)
            # Keep the previous sentence (for a quick replay) and the lookahead only.
            for i in [i for i in self.cache if i < self.index - 1 or i >= self.index + LOOKAHEAD]:
                del self.cache[i]
            self.cond.notify_all()


# --- MPRIS ------------------------------------------------------------------

def start_mpris(reader: Reader):
    """Run the D-Bus side on its own asyncio loop in a thread."""
    from dbus_next import BusType, Variant
    from dbus_next.aio import MessageBus
    from dbus_next.service import PropertyAccess, ServiceInterface, dbus_property, method

    loop = asyncio.new_event_loop()

    class Root(ServiceInterface):
        def __init__(self):
            super().__init__("org.mpris.MediaPlayer2")

        @method()
        def Raise(self): pass

        @method()
        def Quit(self): reader.stop()

        @dbus_property(access=PropertyAccess.READ)
        def CanQuit(self) -> "b": return True

        @dbus_property(access=PropertyAccess.READ)
        def CanRaise(self) -> "b": return False

        @dbus_property(access=PropertyAccess.READ)
        def HasTrackList(self) -> "b": return False

        @dbus_property(access=PropertyAccess.READ)
        def Identity(self) -> "s": return "Read aloud"

        @dbus_property(access=PropertyAccess.READ)
        def DesktopEntry(self) -> "s": return ""   # no .desktop file; Identity is the label

        @dbus_property(access=PropertyAccess.READ)
        def SupportedUriSchemes(self) -> "as": return []

        @dbus_property(access=PropertyAccess.READ)
        def SupportedMimeTypes(self) -> "as": return []

    class Player(ServiceInterface):
        def __init__(self):
            super().__init__("org.mpris.MediaPlayer2.Player")

        @method()
        def Next(self): reader.next()

        @method()
        def Previous(self): reader.previous()

        @method()
        def Pause(self): reader.pause()

        @method()
        def PlayPause(self): reader.play_pause()

        @method()
        def Stop(self): reader.stop()

        @method()
        def Play(self): reader.play()

        @method()
        def Seek(self, offset: "x"): pass

        @method()
        def SetPosition(self, track: "o", position: "x"): pass

        @method()
        def OpenUri(self, uri: "s"): pass

        @dbus_property(access=PropertyAccess.READ)
        def PlaybackStatus(self) -> "s": return reader.state.capitalize()

        @dbus_property()
        def Rate(self) -> "d": return reader.settings["speed"]

        @Rate.setter
        def Rate(self, value: "d"): reader.set_speed(value)

        @dbus_property()
        def Volume(self) -> "d": return 1.0

        @Volume.setter
        def Volume(self, value: "d"): pass

        @dbus_property(access=PropertyAccess.READ)
        def Metadata(self) -> "a{sv}": return metadata()

        @dbus_property(access=PropertyAccess.READ)
        def Position(self) -> "x": return 0

        @dbus_property(access=PropertyAccess.READ)
        def MinimumRate(self) -> "d": return MIN_SPEED

        @dbus_property(access=PropertyAccess.READ)
        def MaximumRate(self) -> "d": return MAX_SPEED

        @dbus_property(access=PropertyAccess.READ)
        def CanGoNext(self) -> "b": return reader.state != "stopped"

        @dbus_property(access=PropertyAccess.READ)
        def CanGoPrevious(self) -> "b": return reader.state != "stopped"

        @dbus_property(access=PropertyAccess.READ)
        def CanPlay(self) -> "b": return reader.state != "stopped"

        @dbus_property(access=PropertyAccess.READ)
        def CanPause(self) -> "b": return reader.state != "stopped"

        @dbus_property(access=PropertyAccess.READ)
        def CanSeek(self) -> "b": return False

        @dbus_property(access=PropertyAccess.READ)
        def CanControl(self) -> "b": return True

    def metadata() -> dict:
        s = reader.status()
        if not s["count"]:
            return {"mpris:trackid": Variant("o", "/org/mpris/MediaPlayer2/TrackList/NoTrack")}
        return {
            "mpris:trackid": Variant("o", f"/org/kokoro_reader/sentence/{s['index']}"),
            "xesam:title": Variant("s", s["sentence"]),
            "xesam:artist": Variant("as", [f"Read aloud · {s['index'] + 1}/{s['count']} · {s['speed']:g}×"]),
            "xesam:album": Variant("s", s["voice"]),
        }

    player = Player()
    state = {"bus": None, "owned": False}

    async def setup():
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
        bus.export(MPRIS_PATH, Root())
        bus.export(MPRIS_PATH, player)
        state["bus"] = bus

    async def publish():
        bus = state["bus"]
        if bus is None:
            return
        active = reader.state != "stopped"
        # Own the MPRIS name only while a text is loaded, so an idle reader
        # never shows up in the bar or takes the media keys from Spotify.
        if active and not state["owned"]:
            await bus.request_name(MPRIS_NAME)
            state["owned"] = True
        player.emit_properties_changed({
            "PlaybackStatus": reader.state.capitalize(), "Metadata": metadata(),
            "Rate": reader.settings["speed"], "CanGoNext": active, "CanGoPrevious": active,
            "CanPlay": active, "CanPause": active,
        })
        if not active and state["owned"]:
            await bus.release_name(MPRIS_NAME)
            state["owned"] = False

    def run():
        asyncio.set_event_loop(loop)
        loop.run_until_complete(setup())
        loop.run_forever()

    threading.Thread(target=run, daemon=True).start()
    reader.on_change = lambda: asyncio.run_coroutine_threadsafe(publish(), loop)


# --- socket server ----------------------------------------------------------

def handle(reader: Reader, request: str) -> str:
    command, _, body = request.partition("\n")
    verb, _, arg = command.partition(" ")
    if verb == "SPEAK":
        reader.speak(body)
    elif verb == "STOP":
        reader.stop()
    elif verb == "PAUSE":
        reader.play_pause()
    elif verb == "NEXT":
        reader.next()
    elif verb == "PREV":
        reader.previous()
    elif verb == "SPEED":
        current = reader.settings["speed"]
        value = current + float(arg) if arg[:1] in "+-" else float(arg)
        reader.set_speed(value)
    elif verb == "VOICE":
        reader.set_voice(arg.strip())
    elif verb != "STATUS":
        return json.dumps({"error": f"unknown command {verb}"})
    return json.dumps(reader.status())


def main():
    reader = Reader()
    start_mpris(reader)
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o600)
    server.listen(4)
    server.settimeout(60)
    print(f"kokoro-reader ready on {SOCKET_PATH} ({reader.device})", flush=True)

    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                if reader.state == "stopped" and time.monotonic() - reader.last_used > IDLE_EXIT_SECONDS:
                    break
                continue
            with conn:
                data = b""
                while chunk := conn.recv(65536):
                    data += chunk
                try:
                    reply = handle(reader, data.decode("utf-8", errors="replace"))
                except Exception as error:
                    reply = json.dumps({"error": str(error)})
                try:
                    conn.sendall(reply.encode())
                except OSError:
                    pass
    finally:
        reader.stop()
        server.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)


if __name__ == "__main__":
    main()
