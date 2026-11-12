"""Kokoro read-aloud daemon.

Keeps the Kokoro model loaded on the GPU and reads text sent over a Unix
socket. Started on demand by ~/.local/bin/read-aloud; exits after
IDLE_EXIT_SECONDS without use so it does not hold VRAM all day.

Protocol (one request per connection, UTF-8):
  "SPEAK\n<text>"  stop anything playing, then read <text>
  "STOP"           stop playing
  "STATUS"         reply "speaking" or "idle"
"""

import os
import re
import socket
import subprocess
import threading
import time

VOICE = os.environ.get("KOKORO_VOICE", "af_heart")
SPEED = float(os.environ.get("KOKORO_SPEED", "1.0"))
LANG = os.environ.get("KOKORO_LANG", "a")  # a = American English, b = British
IDLE_EXIT_SECONDS = 30 * 60
SAMPLE_RATE = 24000

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.sock")


def clean(text: str) -> str:
    """Undo the hard line breaks that PDF and ebook selections carry."""
    text = text.replace("\r", "")
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)      # re-join hyphenated words
    text = re.sub(r"\n{2,}", "\n", text)               # paragraph break -> one newline
    text = re.sub(r"(?<!\n)\n(?!\n)(?=[a-z,;])", " ", text)  # mid-sentence wraps
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


class Reader:
    def __init__(self):
        from kokoro import KPipeline
        import torch

        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.pipeline = KPipeline(lang_code=LANG, device=device, repo_id="hexgrad/Kokoro-82M")
        self.pipeline.load_voice(VOICE)
        self.lock = threading.Lock()
        self.cancel = threading.Event()
        self.player = None
        self.worker = None
        self.last_used = time.monotonic()

    def speaking(self) -> bool:
        return self.worker is not None and self.worker.is_alive()

    def stop(self):
        with self.lock:
            self.cancel.set()
            if self.player and self.player.poll() is None:
                self.player.kill()
            worker = self.worker
        if worker:
            worker.join(timeout=5)

    def speak(self, text: str):
        self.stop()
        self.last_used = time.monotonic()
        self.cancel = threading.Event()
        self.worker = threading.Thread(target=self._run, args=(clean(text), self.cancel), daemon=True)
        self.worker.start()

    def _run(self, text: str, cancel: threading.Event):
        # mpv plays raw float32 samples from stdin, so audio starts with the
        # first sentence while later ones are still being generated.
        player = subprocess.Popen(
            ["mpv", "--no-video", "--really-quiet", "--no-terminal", "--demuxer=rawaudio",
             "--demuxer-rawaudio-format=floatle", f"--demuxer-rawaudio-rate={SAMPLE_RATE}",
             "--demuxer-rawaudio-channels=1", "--cache=no", "-"],
            stdin=subprocess.PIPE,
        )
        with self.lock:
            self.player = player
        try:
            for result in self.pipeline(text, voice=VOICE, speed=SPEED, split_pattern=r"\n+"):
                if cancel.is_set():
                    break
                if result.audio is None:
                    continue
                player.stdin.write(result.audio.numpy().astype("float32").tobytes())
                player.stdin.flush()
            player.stdin.close()
            while player.poll() is None and not cancel.is_set():
                time.sleep(0.1)
        except (BrokenPipeError, ValueError):
            pass
        finally:
            if player.poll() is None:
                player.kill()
            self.last_used = time.monotonic()


def main():
    reader = Reader()
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o600)
    server.listen(4)
    server.settimeout(60)
    print(f"kokoro-reader ready on {SOCKET_PATH}", flush=True)

    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                if not reader.speaking() and time.monotonic() - reader.last_used > IDLE_EXIT_SECONDS:
                    break
                continue
            with conn:
                data = b""
                while chunk := conn.recv(65536):
                    data += chunk
                request = data.decode("utf-8", errors="replace")
                command, _, body = request.partition("\n")
                if command == "SPEAK" and body.strip():
                    reader.speak(body)
                    reply = "ok"
                elif command == "STOP":
                    reader.stop()
                    reply = "ok"
                elif command == "STATUS":
                    reply = "speaking" if reader.speaking() else "idle"
                else:
                    reply = "unknown command"
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
