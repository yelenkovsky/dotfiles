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
PRONUNCIATIONS_PATH = os.path.join(CONFIG_DIR, "pronunciations.tsv")
SAVED_PATH = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
                          "kokoro-reader", "saved-sentences.md")
DEFAULTS = {"voice": "af_heart", "speed": 1.0, "shadow": False, "panel": True}
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

# The keybindings (in dotfiles-private's hypr/bindings.lua), shown by `read-aloud keys`.
# Picking a row in that menu runs its command.
KEYS = [
    ("Super+Alt+R", "Read the selection (PdfCraft: Ctrl+C first) / stop", "toggle"),
    ("Super+Alt+E", "Pause / resume", "pause"),
    ("Super+Alt+W", "Back a sentence (in the shadowing pause: replay)", "prev"),
    ("Super+Alt+T", "Skip a sentence", "next"),
    ("Super+Alt+Shift+W", "Back to the first sentence", "restart"),
    ("Super+Alt+Shift+R", "Add the selection to the end of what is being read", "queue"),
    ("Super+Alt+B", "Save the sentence being read (for flashcards)", "save"),
    ("Super+Alt+Z", "Slower", "slower"),
    ("Super+Alt+X", "Faster", "faster"),
    ("Super+Alt+V", "Choose a voice", "voice"),
    ("Super+Alt+A", "Read-along panel on/off", "panel"),
    ("Super+Alt+D", "Shadowing on/off (pause to repeat each sentence)", "shadow"),
    ("Super+Alt+H", "This list", "keys"),
    ("Saved sentences", "Open the list saved with Super+Alt+B", "saved"),
    ("Media keys", "Play/pause, previous/next sentence", None),
]

USAGE = """usage: read-aloud [command]
  toggle        read what was selected or copied; stop if nothing new (default)
  read [-]      read the selection (or stdin with -), replacing anything playing
  stop | pause | next | prev
  restart       back to the first sentence (a text read before resumes where it stopped)
  queue         add the selection to the end of what is being read
  save          save the sentence being read to saved-sentences.md; saved: open it
  pronounce [word respelling]
                fix how a word is said (e.g. pronounce Seligman SELL-ig-man);
                without arguments, list the fixes
  faster | slower | speed <0.5-2.0>
  voice [id]    pick a voice from a menu, or set one (e.g. bf_emma)
  shadow        shadowing on/off: a pause after each sentence to repeat it aloud
  panel         read-along panel on/off
  keys          menu of the keyboard shortcuts; picking one runs it
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

def source_window() -> str:
    """Title of the focused window (the book, usually), stored with saved sentences."""
    try:
        out = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True,
                             check=False, timeout=2).stdout
        return " ".join(str(json.loads(out).get("title", "")).split())[:120]
    except (OSError, ValueError, subprocess.SubprocessError, AttributeError):
        return ""


def read(text: str, queue: bool = False):
    if not text.strip():
        notify("Select or copy some text first.")
        return
    source = source_window()
    if send("STATUS") is None and not start_daemon():
        sys.exit(1)
    status = send(f"{'APPEND' if queue else 'SPEAK'} {source}\n{text}") or {}
    # Show what is being read, so a selection that an app only half-published
    # (a few letters instead of a paragraph) is obvious rather than silent.
    words = len(text.split())
    preview = " ".join(text.split())[:80]
    message = f"{words} words: “{preview}{'…' if len(preview) == 80 else ''}”"
    if status.get("queuedAt", 0) > 0:
        message = f"Queued from sentence {status['queuedAt'] + 1} of {status['count']}. " + message
    elif status.get("resumed"):
        message += f"\nResuming at sentence {status['resumed'] + 1} of {status['count']} (read-aloud restart: from the top)"
    notify(message)


def save_sentence():
    status = send("SAVE")
    if not status or not status.get("saved"):
        notify("Nothing is being read, so there is no sentence to save.")
        return
    preview = status["saved"][:60]
    osd("󰆓", f"Saved: {preview}{'…' if len(status['saved']) > 60 else ''}")


def open_saved():
    if not os.path.exists(SAVED_PATH):
        notify("No sentences saved yet: press Super+Alt+B while listening.")
        return
    subprocess.Popen(["omarchy-launch-editor", SAVED_PATH], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def pronounce(args: list[str]):
    """Add or replace word<TAB>respelling in pronunciations.tsv, then say the word."""
    if not args:
        print(f"{PRONUNCIATIONS_PATH}:")
        try:
            with open(PRONUNCIATIONS_PATH, encoding="utf-8") as f:
                print(f.read().rstrip() or "(empty)")
        except OSError:
            print("(none yet)")
        return
    if len(args) < 2:
        sys.exit("usage: read-aloud pronounce <word> <respelling or /phonemes/>")
    word, say = args[0].strip(), " ".join(args[1:]).strip()
    try:
        with open(PRONUNCIATIONS_PATH, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = ["# word<TAB>respelling (e.g. SELL-ig-man) or Kokoro phonemes between slashes",
                 "# Added with: read-aloud pronounce <word> <respelling>"]
    lines = [line for line in lines if line.split("\t")[0].lower() != word.lower()]
    lines.append(f"{word}\t{say}")
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(PRONUNCIATIONS_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{word} → {say}")
    read(f"{word}")


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


def show_keys():
    # Menu rows are icon<TAB>name<TAB>description; the pick comes back without the icon.
    rows = [f"{'󰌌' if cmd else '󰝚'}\t{key}\t{label}" for key, label, cmd in KEYS]
    args = ["omarchy-menu-select", "Read aloud", *rows, "--", "--width", "640"]
    picked = subprocess.run(args, capture_output=True, text=True, check=False).stdout.strip()
    command = next((cmd for key, label, cmd in KEYS if picked.startswith(key + "\t")), None)
    if command and command != "keys":
        run(command, [])


def toggle_setting(name: str, on_label: str, off_label: str, icon: str):
    status = send(name.upper())
    if status is None:          # daemon not running: change the saved setting
        settings = load_settings()
        settings[name] = not settings[name]
        save_settings(settings)
        value = settings[name]
    elif "error" in status:
        notify(status["error"])
        return
    else:
        value = status[name]
    osd(icon, on_label if value else off_label)


def main():
    args = sys.argv[1:]
    run(args[0] if args else "toggle", args[1:])


def run(action: str, rest: list[str]):
    args = [action, *rest]
    if action == "toggle":
        toggle()
    elif action == "read":
        read(sys.stdin.read() if args[1:2] == ["-"] else selected_text()[0])
    elif action == "keys":
        show_keys()
    elif action == "queue":
        read(selected_text()[0], queue=True)
    elif action == "save":
        save_sentence()
    elif action == "saved":
        open_saved()
    elif action == "pronounce":
        pronounce(rest)
    elif action == "restart":
        send("RESTART")
    elif action == "shadow":
        toggle_setting("shadow", "Shadowing on: repeat each sentence", "Shadowing off", "󰑖")
    elif action == "panel":
        toggle_setting("panel", "Read-along panel on", "Read-along panel off", "󰈙")
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
