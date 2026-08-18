# Dotfiles

Public Fish, Ghostty, Vim, Cursor, and Catppuccin setup for a Linux desktop.

## Install

```bash
git clone https://github.com/yelenkovsky/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh secure-install.sh setup/*.sh
./secure-install.sh --yes   # packages; Catppuccin KDE installer is still interactive
./install.sh                # symlink configs into $HOME
./setup/setup-android-usb.sh  # optional: Android USB udev rules for adb/scrcpy
```

`install.sh` resolves paths from its own directory, so the clone does not have to live at `~/dotfiles`.

On first Catppuccin KDE prompt, choose **Mocha** with the **Flamingo** accent.

## What is linked

| Path | Role |
| --- | --- |
| `.vimrc` | Vim |
| `.gitconfig` | Git identity and `gh` credential helper |
| `.config/fish`, `.config/omf` | Fish + Oh My Fish |
| `.config/starship.toml` | Prompt |
| `.config/ghostty` | Terminal |
| `.config/eza` | `ls` replacement theme |
| `.config/gh/config.yml` | GitHub CLI (no `hosts.yml`) |
| `.config/Cursor/` | Editor settings, keybindings, snippets |
| `.config/kdedefaults`, `nwg-look`, `xsettingsd` | Theme helpers |
| `plasma-themes/Catppuccin.Macchiato` | Plasma look-and-feel (system-wide symlink) |

## Extra setup

- `setup/artix-dinit-audio.sh` — PipeWire on Artix + dinit
- `setup/setup-wireshark.sh` — capture group permissions (does not install Wireshark)
- `setup/setup-android-usb.sh` — Android USB udev rules for `adb` / `fastboot` / `scrcpy` (Artix/dinit; no systemd). Prefers the `android-udev` package, otherwise clones [M0Rf30/android-udev-rules](https://github.com/M0Rf30/android-udev-rules).

After USB setup, log out so the `adbusers` group applies, enable USB debugging on the phone, replug, then `adb devices` or `scrcpy-usb`.

## Updating

These files are the copies that `$HOME` should symlink to. Edit them here (or via the home symlink), then commit in this repository.
