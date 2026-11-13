"""Kokoro read-aloud daemon.

Keeps the Kokoro model loaded on the GPU and reads text sentence by sentence.
Started on demand by read-aloud (client.py); exits after IDLE_EXIT_SECONDS
without use so it does not hold VRAM all day.

Control comes two ways:
  * a Unix socket for read-aloud (one request per connection, UTF-8):
      SPEAK [source]\\n<text>   read <text>, replacing anything being read; a
                       text read before resumes at the sentence where it stopped;
                       a word or two is said slowly, twice
      APPEND [source]\\n<text>  queue <text> after what is being read
      SAVE                     add the sentence being read to saved-sentences.md
      STOP | PAUSE (toggle) | NEXT | PREV | RESTART (back to sentence 1)
      SPEED <x> | SPEED +<d> | SPEED -<d>     set or step the speed
      VOICE <id>                               e.g. af_heart, bf_emma
      SHADOW | PANEL                           toggle shadowing / the read-along panel
      STATUS                                   JSON state
  * MPRIS (org.mpris.MediaPlayer2.kokoro_reader) while a text is loaded, so
    media keys, headphone buttons and the Omarchy Media bar widget work.
    Next/Previous move by sentence; Rate is the speed.

A second socket, kokoro-reader-events.sock, streams one JSON line per change
(the sentence, each word's start and end in seconds, the position) to the
read-along panel (omarchy-plugin/), which runs its own clock between lines.

Shadowing: after each sentence the reader is silent for about as long as the
sentence took, so the listener can repeat it aloud.

Settings (voice, speed, shadow, panel) persist in
~/.config/kokoro-reader/settings.json; where each text stopped, as a hash of
the text and a sentence number (never the text), in
~/.local/state/kokoro-reader/positions.json.
"""

import asyncio
import hashlib
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
SHADOW_FACTOR = 1.0                # repeat gap = sentence length × this ...
SHADOW_EXTRA = 1.0                 # ... + this many seconds
SLOW_SPEED = 0.7                   # a selection of a word or two is said at this speed ...
SLOW_MAX_WORDS = 3                 # ... (up to this many words), twice
MAX_POSITIONS = 200                # texts whose stopping point is remembered
DEFAULTS = {"voice": "af_heart", "speed": 1.0, "shadow": False, "panel": True}

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.sock")
EVENTS_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader-events.sock")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "kokoro-reader")
SETTINGS_PATH = os.path.join(CONFIG_DIR, "settings.json")
PRONUNCIATIONS_PATH = os.path.join(CONFIG_DIR, "pronunciations.tsv")
DATA_DIR = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "kokoro-reader")
SAVED_PATH = os.path.join(DATA_DIR, "saved-sentences.md")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "kokoro-reader")
POSITIONS_PATH = os.path.join(STATE_DIR, "positions.json")

MPRIS_NAME = "org.mpris.MediaPlayer2.kokoro_reader"
MPRIS_PATH = "/org/mpris/MediaPlayer2"


# --- settings ---------------------------------------------------------------

def load_settings() -> dict:
    try:
        with open(SETTINGS_PATH) as f:
            return {**DEFAULTS, **json.load(f)}
    except (OSError, ValueError):
        return dict(DEFAULTS)


def write_json(path: str, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def save_settings(settings: dict):
    write_json(SETTINGS_PATH, settings)


class Positions:
    """Where each text stopped: {text hash: {"index", "count", "time"}}."""

    def __init__(self):
        try:
            with open(POSITIONS_PATH) as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    @staticmethod
    def key(sentences: list) -> str:
        return hashlib.sha256("\n".join(s for s, _ in sentences).encode()).hexdigest()

    def get(self, key: str, count: int) -> int:
        entry = self.data.get(key)
        if entry and entry.get("count") == count and 0 < entry.get("index", 0) < count:
            return entry["index"]
        return 0

    def set(self, key: str, index: int, count: int):
        if index <= 0:
            self.forget(key)
            return
        self.data[key] = {"index": index, "count": count, "time": int(time.time())}
        if len(self.data) > MAX_POSITIONS:
            oldest = sorted(self.data, key=lambda k: self.data[k]["time"])
            for k in oldest[:len(self.data) - MAX_POSITIONS]:
                del self.data[k]
        self._save()

    def forget(self, key: str):
        if self.data.pop(key, None) is not None:
            self._save()

    def _save(self):
        try:
            write_json(POSITIONS_PATH, self.data)
        except OSError as error:
            print(f"saving positions failed: {error}", flush=True)


class Pronunciations:
    """Words Kokoro says wrong, from pronunciations.tsv: word<TAB>respelling.

    The respelling is ordinary letters ("SELL-ig-man") or Kokoro phonemes
    between slashes ("/sˈɛlɪɡmən/"). Each word is replaced with Kokoro's
    "[word](/phonemes/)" markup, which keeps the word itself as the token, so
    the read-along timing still lines up. The file is reread when it changes.
    """

    def __init__(self):
        self.mtime = None
        self.entries: list[tuple[re.Pattern, str]] = []
        self.phonemes: dict[tuple[str, str], str] = {}

    def _load(self):
        try:
            mtime = os.stat(PRONUNCIATIONS_PATH).st_mtime
        except OSError:
            self.mtime, self.entries = None, []
            return
        if mtime == self.mtime:
            return
        entries = []
        with open(PRONUNCIATIONS_PATH, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "\t" not in line:
                    continue
                word, _, say = line.rstrip("\n").partition("\t")
                if word.strip() and say.strip():
                    entries.append((re.compile(rf"(?<![\w\[])({re.escape(word.strip())})(?!\w)", re.IGNORECASE),
                                    say.strip()))
        self.mtime, self.entries = mtime, entries

    def apply(self, sentence: str, pipeline, lang: str) -> str:
        self._load()
        for pattern, say in self.entries:
            if not pattern.search(sentence):
                continue
            if say.startswith("/") and say.endswith("/") and len(say) > 2:
                phonemes = say[1:-1]
            else:
                if (lang, say) not in self.phonemes:
                    self.phonemes[(lang, say)] = pipeline.g2p(say.lower().replace("-", " "))[0].replace(" ", "").strip()
                phonemes = self.phonemes[(lang, say)]
            if phonemes:
                sentence = pattern.sub(lambda m: f"[{m.group(1)}](/{phonemes}/)", sentence)
        return sentence


def is_word_lookup(text: str) -> bool:
    """A selection of a word or two (not a sentence) is a pronunciation lookup."""
    words = text.split()
    return 0 < len(words) <= SLOW_MAX_WORDS and len(text) <= 60 and not re.search(r"[!?…]|\.\s", text)


def clamp_speed(value: float) -> float:
    return round(min(MAX_SPEED, max(MIN_SPEED, value)), 2)


# --- text -------------------------------------------------------------------

ABBREVIATIONS = {"mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr", "vs", "etc", "e.g", "i.e",
                 "cf", "fig", "no", "vol", "pp", "ch", "ed", "eds", "approx", "u.s", "u.k"}
SENTENCE_END = re.compile(r"[.!?…]+[\"”’»)\]]*(?=\s+[\"“‘«(\[]?[A-Z0-9]|\s*$)")


PAGE_NUMBER = re.compile(r"(?i)(page\s+)?\d{1,4}(\s+of\s+\d{1,4})?")
# A page number next to a running header with no lowercase letters: "12 AGENCY", "AGENCY 13".
NUMBERED_HEADER = re.compile(r"\d{1,4}\s+[^a-z\d\n]*[A-Z][^a-z\d\n]*|[^a-z\d\n]*[A-Z][^a-z\d\n]*\s+\d{1,4}")


def strip_page_furniture(text: str) -> str:
    """Drop page numbers and running headers that come along when pages are copied.

    Removes lines that are only a page number, a page number with an
    all-caps header, and short lines without end punctuation that repeat
    (a header on every page). A heading that appears once ("CHAPTER I")
    stays. Texts of one or two lines are left alone, so selecting just
    "1984" still reads it.
    """
    lines = text.replace("\r", "").split("\n")
    if len([line for line in lines if line.strip()]) < 3:
        return text
    stripped = [line.strip() for line in lines]
    counts: dict[str, int] = {}
    for line in stripped:
        if line:
            counts[line] = counts.get(line, 0) + 1

    def furniture(line: str) -> bool:
        if not line:
            return False
        if PAGE_NUMBER.fullmatch(line) or NUMBERED_HEADER.fullmatch(line):
            return True
        return counts[line] > 1 and len(line) <= 60 and not re.search(r"[.!?…:;,\"”’]$", line)

    return "\n".join(line for line, s in zip(lines, stripped) if not furniture(s))


def clean(text: str) -> str:
    """Undo the hard line breaks that PDF and ebook selections carry."""
    text = strip_page_furniture(text.replace("\r", ""))
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


def word_times(sentence: str, tokens: list[tuple[str, float, float]]) -> list[list]:
    """[[word, start, end], ...] for the sentence's whitespace-separated words.

    Kokoro's tokens keep the original spelling ("Dr.", "3:15", "isn't") with
    times in seconds of the generated audio, so each is found in the sentence
    in order and its time given to the word it falls in. Punctuation tokens
    merge into their word; a word with no token (a dash) gets a zero-length
    slot at the previous word's end, so the highlight does not jump.
    """
    spans = [(m.start(), m.end(), m.group()) for m in re.finditer(r"\S+", sentence)]
    times: list[list] = [[None, None] for _ in spans]
    cursor = w = 0
    for text, start, end in tokens:
        text = text.strip()
        if not text or start is None or end is None:
            continue
        at = sentence.find(text, cursor)
        # Accept only a nearby match: a token Kokoro respelled must not pull
        # the cursor onto a later word that happens to contain it.
        if at < 0 or (at - cursor > 3 and re.search(r"\w", sentence[cursor:at])):
            continue
        cursor = at + len(text)
        while w < len(spans) - 1 and spans[w][1] <= at:
            w += 1
        slot = times[w]
        slot[0] = start if slot[0] is None else min(slot[0], start)
        slot[1] = end if slot[1] is None else max(slot[1], end)
    last = 0.0
    out = []
    for (_, _, word), (start, end) in zip(spans, times):
        if start is None:
            start = end = last
        last = end
        out.append([word, round(start, 3), round(end, 3)])
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
        # index -> ((voice, speed), audio, words); words as from word_times()
        self.cache: dict[int, tuple[tuple, np.ndarray, list]] = {}
        self.state = "stopped"          # stopped | playing | paused
        self.finished = False
        self.repeat_left = 0            # samples of shadowing silence still to play
        self.repeat_total = 0
        self.version = 0                # bumped on every change MPRIS or the panel should see
        self.last_used = time.monotonic()
        self.stream = None
        self.positions = Positions()
        self.text_key = ""              # Positions key of the loaded text
        self.source = ""                # window the text came from, for saved sentences
        self.speed_override = None      # slow speed while a word lookup is read
        self.pronunciations = Pronunciations()
        self.listeners = []             # called by the worker after each change

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
        return (self.settings["voice"], self.speed_override or self.settings["speed"])

    def _generate(self, sentence: str, ends_paragraph: bool, key: tuple) -> tuple[np.ndarray, list]:
        voice, speed = key
        chunks, tokens = [], []
        offset = 0.0                    # a very long sentence comes back in several chunks
        pipeline = self.pipeline_for(voice)
        text = self.pronunciations.apply(sentence, pipeline, voice[0])
        for r in pipeline(text, voice=voice, speed=speed, split_pattern=None):
            if r.audio is None:
                continue
            audio = r.audio.numpy()
            for t in r.tokens or []:
                if t.start_ts is not None and t.end_ts is not None:
                    tokens.append((t.text, offset + t.start_ts, offset + t.end_ts))
            chunks.append(audio)
            offset += len(audio) / SAMPLE_RATE
        gap = np.zeros(int(SAMPLE_RATE * (PARAGRAPH_GAP if ends_paragraph else SENTENCE_GAP)), np.float32)
        return np.concatenate([*chunks, gap]).astype(np.float32), word_times(sentence, tokens)

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
                if self.repeat_left:
                    # Shadowing: silence while the listener repeats the sentence.
                    n = min(frames - filled, self.repeat_left)
                    filled += n
                    self.repeat_left -= n
                    if not self.repeat_left:
                        self._advance()
                        moved = True
                    continue
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
                    if self.settings["shadow"]:
                        self.repeat_total = self.repeat_left = int(
                            len(audio) * SHADOW_FACTOR + SHADOW_EXTRA * SAMPLE_RATE)
                    else:
                        self._advance()
                    moved = True
            if moved:
                self.version += 1
                self.cond.notify_all()

    def _advance(self):
        """Move to the next sentence; caller holds self.cond."""
        self.cache.pop(self.index - 1, None)
        self.index += 1
        self.pos = 0
        self.repeat_left = self.repeat_total = 0

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

    def speak(self, text: str, source: str = "") -> int:
        """Read text, resuming where it stopped last time; returns that sentence index.

        A word or two (is_word_lookup) is said slowly, twice, and not remembered.
        """
        lookup = is_word_lookup(text)
        sentences = [(" ".join(text.split()), False), (" ".join(text.split()), True)] if lookup \
            else split_sentences(text)
        if not sentences:
            return 0
        self._close_stream()
        with self.cond:
            self.sentences = sentences
            self.source = source
            self.speed_override = min(SLOW_SPEED, self.settings["speed"]) if lookup else None
            self.text_key = "" if lookup else Positions.key(sentences)
            self.index = self.positions.get(self.text_key, len(sentences)) if self.text_key else 0
            self.pos = self.repeat_left = self.repeat_total = 0
            self.cache.clear()
            self.finished = False
            self.state = "playing"
            self._touch()
            start = self.index
        self._open_stream()
        return start

    def append(self, text: str, source: str = "") -> int:
        """Queue text after what is being read; returns the index of its first sentence.

        With nothing being read (or a word lookup), it is read straight away.
        """
        sentences = split_sentences(text)
        if not sentences:
            return -1
        with self.cond:
            fresh = self.state == "stopped" or self.finished or self.speed_override is not None
            if not fresh:
                start = len(self.sentences)
                self.sentences = self.sentences + sentences
                self.text_key = Positions.key(self.sentences)
                self._touch()
                return start
        self.speak(text, source)
        return 0

    def save_sentence(self) -> str:
        """Append the sentence being read to SAVED_PATH; returns it ("" when nothing is read).

        Within the first second of a sentence, the one before is meant: by the
        time the key is pressed, the sentence that caught the ear has ended.
        """
        with self.cond:
            if self.state == "stopped" or not self.sentences or self.speed_override is not None:
                return ""
            index = min(self.index, len(self.sentences) - 1)
            if not self.repeat_left and self.pos < SAMPLE_RATE and index > 0:
                index -= 1
            sentence = self.sentences[index][0]
            source = self.source
        try:
            with open(SAVED_PATH, encoding="utf-8") as f:
                existing = f.read()
        except OSError:
            existing = "# Saved sentences\n\nSaved while listening with read-aloud (Super+Alt+B).\n"
        if f"- {sentence}\n" in existing.split("## ")[-1]:
            return sentence             # already saved under the latest heading
        heading = f"## {time.strftime('%Y-%m-%d')}" + (f" · {source}" if source else "")
        last_heading = next((line for line in reversed(existing.splitlines()) if line.startswith("## ")), None)
        addition = ("" if existing.endswith("\n") else "\n")
        if last_heading != heading:
            addition += f"\n{heading}\n\n"
        addition += f"- {sentence}\n"
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(SAVED_PATH, "w", encoding="utf-8") as f:
            f.write(existing + addition)
        return sentence

    def stop(self):
        self._close_stream()
        with self.cond:
            self.sentences = []
            self.text_key = ""
            self.speed_override = None
            self.cache.clear()
            self.index = self.pos = self.repeat_left = self.repeat_total = 0
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
                self._advance()
                self._touch()
        if end:
            self.positions.forget(self.text_key)
            self.stop()

    def previous(self):
        with self.cond:
            if self.state == "stopped":
                return
            speed = self.settings["speed"]
            # During the shadowing gap, Previous replays the sentence just heard.
            if (not self.repeat_left and self.pos < RESTART_THRESHOLD * SAMPLE_RATE / speed
                    and self.index > 0):
                self.index -= 1
            self.pos = self.repeat_left = self.repeat_total = 0
            self._touch()

    def restart(self):
        with self.cond:
            if self.state == "stopped":
                return
            self.index = self.pos = self.repeat_left = self.repeat_total = 0
            self._touch()

    def toggle_setting(self, name: str) -> bool:
        with self.cond:
            self.settings[name] = not self.settings[name]
            if name == "shadow" and not self.settings[name] and self.repeat_left:
                self._advance()         # turning it off mid-gap moves straight on
            save_settings(self.settings)
            self._touch()
            return self.settings[name]

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
                    "shadow": self.settings["shadow"], "panel": self.settings["panel"],
                    "sentence": sentence, "index": self.index, "count": len(self.sentences)}

    def snapshot(self) -> dict:
        """Everything the read-along panel draws, with times in seconds.

        phase: "loading" (audio for this sentence not generated yet), "speaking"
        (pos = seconds into the sentence) or "repeat" (shadowing; repeat and
        repeatLeft give the gap's length and what is left of it).
        """
        with self.cond:
            snap = self.status()
            entry = self.cache.get(self.index)
            if self.repeat_left:
                phase = "repeat"
            elif entry is None or entry[0] != self.key():
                phase = "loading"
            else:
                phase = "speaking"
            following = self.index + 1
            snap.update({
                "phase": phase,
                "words": entry[2] if phase != "loading" else [[w, 0, 0] for w in snap["sentence"].split()],
                "pos": round(self.pos / SAMPLE_RATE, 3),
                "repeat": round(self.repeat_total / SAMPLE_RATE, 3),
                "repeatLeft": round(self.repeat_left / SAMPLE_RATE, 3),
                "next": self.sentences[following][0] if following < len(self.sentences) else "",
            })
            return snap

    def _touch(self):
        """Record a change; caller holds self.cond."""
        self.version += 1
        self.last_used = time.monotonic()
        self.cond.notify_all()

    # worker: generate ahead, swap audio after speed/voice changes, publish changes

    def _worker(self):
        published = -1
        saved = (None, None)
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
                place = (self.text_key, self.index)
                count = len(self.sentences)
            if finished:
                self.positions.forget(place[0])     # read to the end: next time starts over
                saved = (None, None)
                self.stop()
                continue
            if place != saved and place[0]:
                self.positions.set(place[0], place[1], count)
                saved = place
            if job:
                index, sentence, ends_paragraph, key = job
                try:
                    audio, words = self._generate(sentence, ends_paragraph, key)
                except Exception as error:  # a bad voice or odd text must not kill the reader
                    print(f"generation failed for sentence {index}: {error}", flush=True)
                    audio = np.zeros(int(SAMPLE_RATE * SENTENCE_GAP), np.float32)
                    words = [[w, 0, 0] for w in sentence.split()]
                self._store(index, key, audio, words)
            if version != published:
                published = version
                for listener in self.listeners:
                    try:
                        listener()
                    except Exception as error:
                        print(f"listener failed: {error}", flush=True)

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

    def _store(self, index: int, key: tuple, audio: np.ndarray, words: list):
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
            self.cache[index] = (key, audio, words)
            if index == self.index:
                self.version += 1       # the panel needs this sentence's new timings
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
    reader.listeners.append(lambda: asyncio.run_coroutine_threadsafe(publish(), loop))


# --- event stream for the read-along panel ----------------------------------

def start_events(reader: Reader):
    """Send reader.snapshot() as one JSON line to every client on each change.

    A client gets the current snapshot as soon as it connects. Sends have a
    short timeout and a client that fails one is dropped, so a stuck panel can
    never hold up reading.
    """
    if os.path.exists(EVENTS_PATH):
        os.unlink(EVENTS_PATH)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(EVENTS_PATH)
    os.chmod(EVENTS_PATH, 0o600)
    server.listen(4)
    clients: list[socket.socket] = []
    lock = threading.Lock()

    def line() -> bytes:
        return (json.dumps(reader.snapshot(), ensure_ascii=False) + "\n").encode()

    def send(conn: socket.socket, data: bytes) -> bool:
        try:
            conn.sendall(data)
            return True
        except OSError:
            conn.close()
            return False

    def accept():
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            conn.settimeout(0.5)
            with lock:
                if send(conn, line()):
                    clients.append(conn)

    def broadcast():
        data = line()
        with lock:
            clients[:] = [c for c in clients if send(c, data)]

    threading.Thread(target=accept, daemon=True).start()
    reader.listeners.append(broadcast)
    return server


# --- socket server ----------------------------------------------------------

def handle(reader: Reader, request: str) -> str:
    command, _, body = request.partition("\n")
    verb, _, arg = command.partition(" ")
    source = " ".join(arg.split())[:120]
    if verb == "SPEAK":
        return json.dumps({**reader.status(), "resumed": reader.speak(body, source)})
    elif verb == "APPEND":
        return json.dumps({**reader.status(), "queuedAt": reader.append(body, source)})
    elif verb == "SAVE":
        return json.dumps({**reader.status(), "saved": reader.save_sentence()})
    elif verb == "RESTART":
        reader.restart()
    elif verb == "SHADOW":
        reader.toggle_setting("shadow")
    elif verb == "PANEL":
        reader.toggle_setting("panel")
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
    events = start_events(reader)
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
        events.close()
        for path in (SOCKET_PATH, EVENTS_PATH):
            if os.path.exists(path):
                os.unlink(path)


if __name__ == "__main__":
    main()
