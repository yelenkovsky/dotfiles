"""Client for the Kokoro read-aloud daemon. See read-aloud for usage."""

import hashlib
import json
import os
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.sock")
LAST_PATH = os.path.join(RUNTIME_DIR, "kokoro-reader.last")
LOG_PATH = os.path.expanduser("~/.local/state/kokoro-reader.log")
CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "kokoro-reader")
SETTINGS_PATH = os.path.join(CONFIG_DIR, "settings.json")
DEFAULTS = {"voice": "af_heart", "speed": 1.0}
SPEED_STEP = 0.1
MIN_SPEED, MAX_SPEED = 0.5, 2.0

# English Kokoro voices worth choosing, best first (grades from the model card's VOICES.md).
VOICES = [
    ("af_heart", "Heart", "American · female · best"),
    ("af_bella", "Bella", "American · female"),
    ("af_nicole", "Nicole", "American · female · soft"),
    ("af_aoede", "Aoede", "American · female"),
    ("af_kore", "Kore", "American · female"),
    ("af_sarah", "Sarah", "American · female"),
    ("am_michael", "Michael", "American · male"),
    ("am_fenrir", "Fenrir", "American · male"),
    ("am_puck", "Puck", "American · male"),
    ("bf_emma", "Emma", "British · female"),
    ("bf_isabella", "Isabella", "British · female"),
    ("bm_george", "George", "British · male"),
    ("bm_fable", "Fable", "British · male"),
]

USAGE = """usage: read-aloud [command]
  toggle        read what was selected or copied; stop if nothing new (default)
  read [-]      read the selection (or stdin with -), replacing anything playing
  stop | pause | next | prev
  faster | slower | speed <0.5-2.0>
  voice [id]    pick a voice from a menu, or set one (e.g. bf_emma)
  status"""


# --- helpers ----------------------------------------------------------------

def notify(message: str):
    subprocess.run(["notify-send", "-a", "Read aloud", "-t", "2500", "Read aloud", message], check=False)


def osd(icon: str, message: str):
    """Omarchy's on-screen display (the volume pop-up); a notification elsewhere."""
    try:
        subprocess.run(["omarchy-osd", "-i", icon, "-m", message, "-d", "1200"],
                       check=True, capture_output=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        notify(message)


def send(request: str, timeout: float = 10.0) -> dict | None:
    """Send a request to the daemon; None when it is not running."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(SOCKET_PATH)
            s.sendall(request.encode())
            s.shutdown(socket.SHUT_WR)
            data = b""
            while chunk := s.recv(65536):
                data += chunk
    except OSError:
        return None
    try:
        return json.loads(data)
    except ValueError:
        return {"error": data.decode(errors="replace")}


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


def load_settings() -> dict:
    try:
        with open(SETTINGS_PATH) as f:
            return {**DEFAULTS, **json.load(f)}
    except (OSError, ValueError):
        return dict(DEFAULTS)


def save_settings(settings: dict):
    """Used only while the daemon is not running; otherwise the daemon owns the file."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2)


def voice_label(voice_id: str) -> str:
    for vid, name, desc in VOICES:
        if vid == voice_id:
            return f"{name} ({desc.split(' · ')[0]})"
    return voice_id


# --- selection --------------------------------------------------------------

def paste(*args: str) -> str:
    return subprocess.run(["wl-paste", "--no-newline", *args], capture_output=True, text=True, check=False).stdout


def digest(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def selected_text() -> tuple[str, bool]:
    """Pick whichever of the clipboard and the primary selection changed last.

    Some apps (PdfCraft, many Electron apps) never set the primary selection,
    so a highlight there leaves stale text from another window; Ctrl+C in those
    apps updates the clipboard instead. Apps that do set it (browsers, GTK/Qt)
    work with a highlight alone. The digests of what was there at the previous
    read show which one is new; when both or neither changed, the clipboard
    wins, because copying is the deliberate act. Returns (text, is_new).
    """
    clipboard, primary = paste(), paste("--primary")
    try:
        with open(LAST_PATH) as f:
            last_clipboard, last_primary = f.read().split()
    except (OSError, ValueError):
        last_clipboard = last_primary = ""
    with open(LAST_PATH, "w") as f:
        f.write(f"{digest(clipboard)} {digest(primary)}")

    clipboard_new = bool(clipboard.strip()) and digest(clipboard) != last_clipboard
    primary_new = bool(primary.strip()) and digest(primary) != last_primary
    if primary_new and not clipboard_new:
        return primary, True
    if clipboard.strip():
        return clipboard, clipboard_new
    return primary, primary_new


# --- commands ---------------------------------------------------------------

def read(text: str):
    if not text.strip():
        notify("Select or copy some text first.")
        return
    if send("STATUS") is None and not start_daemon():
        sys.exit(1)
    send("SPEAK\n" + text)
    # Show what is being read, so a selection that an app only half-published
    # (a few letters instead of a paragraph) is obvious rather than silent.
    words = len(text.split())
    preview = " ".join(text.split())[:80]
    notify(f"{words} words: “{preview}{'…' if len(preview) == 80 else ''}”")


def toggle():
    """Read new text; with nothing new, stop if reading, else read again."""
    text, is_new = selected_text()
    status = send("STATUS")
    if not is_new and status and status.get("state") != "stopped":
        send("STOP")
        return
    read(text)


def set_speed(request: str):
    status = send(f"SPEED {request}")
    if status is None:          # daemon not running: change the saved setting
        settings = load_settings()
        current = settings["speed"]
        value = current + float(request) if request[:1] in "+-" else float(request)
        settings["speed"] = round(min(MAX_SPEED, max(MIN_SPEED, value)), 2)
        save_settings(settings)
        speed = settings["speed"]
    elif "error" in status:
        notify(status["error"])
        return
    else:
        speed = status["speed"]
    osd("󰓅", f"Speed {speed:g}×")


def set_voice(voice_id: str | None):
    current = (send("STATUS") or load_settings()).get("voice", DEFAULTS["voice"])
    if voice_id is None:
        rows = [f"{'󰄬' if vid == current else '󰗋'}\t{name}\t{desc}" for vid, name, desc in VOICES]
        selected = [f"{name}\t{desc}" for vid, name, desc in VOICES if vid == current]
        args = ["omarchy-menu-select", "Voice", *rows, "--", "--width", "420"]
        if selected:
            args += ["--selected", selected[0]]
        picked = subprocess.run(args, capture_output=True, text=True, check=False).stdout.strip()
        if not picked:
            return
        name = picked.split("\t")[0]
        voice_id = next((vid for vid, n, _ in VOICES if n == name), None)
        if voice_id is None:
            return

    status = send(f"VOICE {voice_id}")
    if status is None:
        settings = load_settings()
        settings["voice"] = voice_id
        save_settings(settings)
    elif "error" in status:
        notify(f"Voice {voice_id}: {status['error']}")
        return
    osd("󰗋", voice_label(voice_id))
    if status is None or status.get("state") == "stopped":
        name = voice_label(voice_id).split(" (")[0]
        read(f"Hello, I'm {name}. This is how I sound.")


def main():
    args = sys.argv[1:]
    action = args[0] if args else "toggle"

    if action == "toggle":
        toggle()
    elif action == "read":
        read(sys.stdin.read() if args[1:2] == ["-"] else selected_text()[0])
    elif action in ("stop", "pause", "next", "prev"):
        status = send(action.upper())
        if status and action == "pause" and status.get("state") != "stopped":
            playing = status["state"] == "playing"
            osd("media-play" if playing else "media-pause", "Reading" if playing else "Paused")
    elif action == "faster":
        set_speed(f"+{SPEED_STEP}")
    elif action == "slower":
        set_speed(f"-{SPEED_STEP}")
    elif action == "speed" and len(args) == 2:
        set_speed(args[1])
    elif action == "voice":
        set_voice(args[1] if len(args) > 1 else None)
    elif action == "status":
        print(json.dumps(send("STATUS") or {"state": "not running", **load_settings()}, indent=2))
    else:
        sys.exit(USAGE)


if __name__ == "__main__":
    main()
