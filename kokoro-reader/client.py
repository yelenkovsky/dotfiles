"""Client for the Kokoro read-aloud daemon. See ~/.local/bin/read-aloud."""

import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.sock")
LOG_PATH = os.path.expanduser("~/.local/state/kokoro-reader.log")


def notify(message: str):
    subprocess.run(["notify-send", "-a", "Read aloud", "-t", "2500", "Read aloud", message], check=False)


def send(request: str, timeout: float = 5.0) -> str | None:
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(SOCKET_PATH)
            s.sendall(request.encode())
            s.shutdown(socket.SHUT_WR)
            return s.recv(1024).decode()
    except OSError:
        return None


def start_daemon() -> bool:
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "ab") as log:
        subprocess.Popen(
            [sys.executable, os.path.join(HERE, "daemon.py")],
            stdout=log, stderr=log, stdin=subprocess.DEVNULL, start_new_session=True,
        )
    notify("Loading the voice…")
    for _ in range(240):  # first run downloads the model, so allow two minutes
        time.sleep(0.5)
        if send("STATUS") is not None:
            return True
    notify(f"The reader did not start; see {LOG_PATH}")
    return False


def selected_text() -> str:
    for args in (["wl-paste", "--primary", "--no-newline"], ["wl-paste", "--no-newline"]):
        out = subprocess.run(args, capture_output=True, text=True, check=False).stdout
        if out.strip():
            return out
    return ""


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "toggle"

    if action == "stop":
        send("STOP")
        return
    if action == "toggle" and send("STATUS") == "speaking":
        send("STOP")
        return
    if action not in ("toggle", "read"):
        sys.exit(f"usage: read-aloud [toggle|read|stop]  (text can also come on stdin with 'read -')")

    if len(sys.argv) > 2 and sys.argv[2] == "-":
        text = sys.stdin.read()
    else:
        text = selected_text()
    if not text.strip():
        notify("Select some text first.")
        return

    if send("STATUS") is None and not start_daemon():
        sys.exit(1)
    send("SPEAK\n" + text)


if __name__ == "__main__":
    main()
