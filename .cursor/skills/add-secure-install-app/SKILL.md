---
name: add-secure-install-app
description: >-
  Add a third-party desktop app or CLI to dotfiles secure-install.sh using the
  existing download, verify, /opt or /usr/local/bin, skip-flag pattern. Use when
  the user asks to add RemNote, Todoist, Nextcloud, Betterbird, Proton Pass,
  Proton Drive, pass-cli, an AppImage, a GitHub release binary, a .deb extract,
  or any new bootstrap app to secure-install.sh.
---

# Add app to secure-install.sh

Edit only `secure-install.sh` unless Fish/env config is explicitly requested. Do not add AUR wrappers when the vendor publishes a direct Linux artifact. Do not use `dpkg` or `rpm` on Artix.

## Workflow

1. Probe the real download (headers, redirects, asset names). Use a browser User-Agent only if the vendor 403s plain curl.
2. Pick **linux x86_64 glibc**. Skip musl, baseline, Windows, macOS, aarch64 unless the user asks.
3. Prefer a **latest resolver** over a versioned URL:
   - redirect or `getloc` / `version.json` / GitHub `releases/latest`
   - parse a table/index and match the platform cell **exactly** (`linux/x64` ≠ `linux/x64-musl`)
4. Verify **before** writing under `/opt` or `/usr/local/bin`:
   - Always: non-empty, size floor (~10 MB for apps), magic (`ELF` or `!<arch>` for `.deb`)
   - If the vendor publishes SHA-256/SHA-512 next to the file: **require it**
   - If they only publish `.asc`: GPG verify in a throwaway `GNUPGHOME`, **pin the fingerprint** in the script
5. Install, add `--skip-<name>`, wire `usage()`, `main` `case`, and the call in `main`.
6. `bash -n secure-install.sh`.

## Where files go

| Kind | Location | PATH symlink | Ownership |
| --- | --- | --- | --- |
| CLI single binary | `/usr/local/bin/<cmd>` | none | root (`install -D -m 755`) |
| AppImage or app tree (Electron, Nextcloud, Betterbird, unpacked `.deb`) | `/opt/<name>/` | `/usr/local/bin/<cmd>` | installing user (`chown` + `chmod u+rwX`) so in-app update can replace files |

Do **not** put CLIs in `/opt`. Do **not** hardcode `/home/<user>`.

Unpacked `.deb`: `bsdtar` the archive, then `data.tar.*`, copy the app directory. Never `dpkg -i`.

## Desktop entries

Write `/usr/share/applications/<name>.desktop`. Electron AppImages: `Exec=... --no-sandbox %U` (user-owned `chrome-sandbox` cannot be setuid). Extract an icon when cheap; otherwise `Icon=<name>`.

## Script shape

Copy an existing installer in this file (Todoist AppImage, Proton Drive CLI, Proton Pass `.deb`, Betterbird tarball, Nextcloud GPG). Required pieces:

- `SKIP_<NAME>=false` and `--skip-<kebab-name>`
- `run_step` for download/install; record `FAIL` and continue unless `--stop-on-error`
- temp files under `"$STATE_DIR"`; delete after successful install
- reuse `download_url_to_file` (add `-A` only for endpoints that need it)

## Do not

- Pin a version in the URL when a latest endpoint exists
- Commit downloaded binaries
- Put secrets, API keys, or machine home paths in the installer
- Install to `/usr/bin` (use `/usr/local/bin`)
- Ask the user to restate these rules; follow this skill
