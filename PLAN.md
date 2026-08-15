# Anycubic Slicer Next – Flatpak Packaging

This document is the architecture plan for this repository, written before any packaging
code existed. It's committed as-is (not rewritten after the fact) so the reasoning behind
the design decisions stays visible.

## Context

There's a sibling project, [`anycubic-slicer-next`](https://github.com/roccorakete/anycubic-slicer-next)
(a Nix flake), which packages the same proprietary Anycubic Slicer Next `.deb` for NixOS via
`buildFHSEnv`. It works, but it's NixOS-only. This repository does the same job as a
**Flatpak** instead, so the packaging is distro-independent — works the same on any Linux
with Flatpak support (Fedora, Debian, Ubuntu, openSUSE, etc.), not just NixOS.

Two research passes (Flatpak manifest conventions for proprietary GTK3/WebKitGTK apps;
GitHub Actions Flatpak build/publish tooling) turned up good news: several of the hacks
required for the Nix/`buildFHSEnv` packaging turn out to be unnecessary or much simpler
under Flatpak:

- **`org.gnome.Platform`//50** already ships a working `webkit2gtk-4.1` + `libsoup-3.0`
  (matching what the binary actually links against) — no from-source WebKitGTK build needed.
- The app's hard-coded absolute resource path, `/usr/share/AnycubicSlicerNext/resources`,
  can't be satisfied the way the Nix flake satisfies it (bind-mounting a real path over a
  read-only one inside a custom FHS sandbox) — Flatpak's `/usr` is the read-only *runtime*,
  not writable by the app at all, ever. **But** `/usr` and `/app` are both exactly 4
  characters, so the fix is a trivial equal-length ELF string patch:
  `/usr/share/AnycubicSlicerNext` → `/app/share/AnycubicSlicerNext`, applied to the binary at
  build time. No bind-mount/sandbox trickery required.
- WebKitGTK's internal bubblewrap-based process sandbox is confirmed (GNOME's own Epiphany
  Flatpak, via `flatpak-spawn`) to nest cleanly inside Flatpak's own sandbox — unlike inside
  the Nix flake's ad-hoc `buildFHSEnv` sandbox, where `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`
  / `WEBKIT_DISABLE_COMPOSITING_MODE=1` / `GDK_BACKEND=x11` were all needed to get a
  functioning WebView at all. Plan is to **not** add these preemptively and only reach for
  them if testing shows an actual problem.
- The `O_NOATIME`-vs-file-ownership issue the Nix flake hit (root-owned Nix store files →
  `EPERM` on every local resource `open()`, silently blanking every embedded WebView) only
  recurs under Flatpak for a **system-wide** install (`/var/lib/flatpak`, root-owned files);
  a normal **`flatpak install --user`** (the common default for desktop users, what GNOME
  Software does) owns `/app`'s files as the invoking user, so the kernel's `O_NOATIME`
  permission check (owner-or-`CAP_FOWNER`) passes and it isn't a problem there. Plan is to
  treat `--user` installs as the primary supported path and note system-wide install as an
  unverified edge case, rather than pre-building the Nix-style cache/bind-mount workaround.
- The `libWorkbench.so`-is-a-stub / `pages://` scheme bug (see the Nix flake's `NOTES.md` for
  the full investigation) is a vendor bug in the binary itself, independent of packaging
  technology — the exact same fix carries over directly: extract the ZIP embedded in
  `libWorkbench.so`'s `.rodata`, point the vendor's own undocumented debug-override env var
  `ACNEXT_WORKBENCH_ENV_VAR` at its `index.html` via a `file://` URL.

## Decisions

- Repo: `anycubic-slicer-next-flatpak` under the `roccorakete` GitHub account.
- Flatpak App ID: **`io.github.roccorakete.AnycubicSlicerNext`** (standard convention for an
  unofficial repackage where we don't control Anycubic's own domain).
- Distribution: a **real, updatable Flatpak repository** hosted on GitHub Pages, built with
  [`andyholmes/flatter`](https://github.com/andyholmes/flatter) — not just a one-off `.flatpak`
  bundle. Requires a GPG signing key (private key → GitHub Actions secret; public key +
  generated `.flatpakrepo` file → published alongside the repo) so users get normal
  `flatpak remote-add` + `flatpak update` behavior instead of manually re-downloading a file
  for every update.

## Implementation order

**Step 0 (first, before any manifest/CI work):** commit this plan (`PLAN.md`) and the
carried-over/adapted findings (`NOTES.md`) to the new repo, so there's a documented paper
trail of the architecture decisions and known pitfalls before any packaging code exists.
Only after that's committed do the manifest, patch script, wrapper script, and CI workflow
get written.

## Repository layout

```
anycubic-slicer-next-flatpak/
├── io.github.roccorakete.AnycubicSlicerNext.yml          # flatpak-builder manifest
├── io.github.roccorakete.AnycubicSlicerNext.appdata.xml  # AppStream metadata (required by Flatpak/flatter)
├── io.github.roccorakete.AnycubicSlicerNext.desktop      # desktop entry (Exec=anycubic-slicer-next)
├── patches/
│   └── patch-resource-path.py       # equal-length ELF string patch /usr→/app, run as a build-command
├── update-anycubic-slicer.sh        # same role as in the Nix flake: bump version/date/hash in the manifest
├── .github/workflows/
│   └── build-and-publish.yml        # flatpak-builder build → flatter → GitHub Pages deploy
├── README.md
├── PLAN.md                          # this file
└── NOTES.md                         # carried-over + Flatpak-specific findings
```

## Manifest design (`io.github.roccorakete.AnycubicSlicerNext.yml`)

- `runtime: org.gnome.Platform`, `runtime-version: "50"`, `sdk: org.gnome.Sdk`.
- `command: anycubic-slicer-next` (a thin wrapper script, see below).
- `finish-args` (modeled on PrusaSlicer's real, accepted Flathub manifest — a close domain
  analog): `--share=network`, `--share=ipc`, `--socket=wayland`, `--socket=fallback-x11`,
  `--socket=pulseaudio`, `--device=all`, `--filesystem=home`, `--filesystem=/run/media`,
  `--filesystem=/media`, `--filesystem=xdg-run/gvfs`.
- `add-extensions`: `org.freedesktop.Platform.ffmpeg-full` (or its current renamed successor —
  check what's current at implementation time) for the `gstreamer1.0-libav`-equivalent codec
  need (video monitor feature).
- One module, `buildsystem: simple`, `sources: [{ type: file, url: <same CDN URL as the Nix
  flake>, sha256: <pinned>, dest-filename: anycubic-slicer-next.deb }]`, with `build-commands`:
  1. `ar x anycubic-slicer-next.deb && tar xf data.tar.*` — unpack the `.deb` payload (same
     `ar`/`tar` approach as the Nix flake's `unpackPhase`, no `dpkg` needed).
  2. Run the ELF patch script on `usr/bin/AnycubicSlicerNext` to rewrite the resource path.
  3. `install -Dm755 usr/bin/AnycubicSlicerNext /app/bin/AnycubicSlicerNext`; copy
     `usr/lib/*.so` straight into `/app/lib/` (it's on the default sandbox `ld.so` search
     path, same reasoning as why dumping them in `buildFHSEnv`'s merged `/usr/lib` worked —
     these libs have no RPATH); copy `usr/share/AnycubicSlicerNext` to
     `/app/share/AnycubicSlicerNext`.
  4. Extract the ZIP embedded in `libWorkbench.so` (`grep -abo $'PK\x03\x04'` to find the
     offset, `tail -c +N`, `unzip`) into `/app/share/AnycubicSlicerNext/resources/workbench/`
     — identical technique to the Nix flake's `installPhase`.
  5. Install the desktop file, AppStream metainfo, and icons (`resources/images/*`) to their
     standard Flatpak-expected locations under `/app/share/`.
  6. Install a small wrapper script as `/app/bin/anycubic-slicer-next` (the `command:`
     target) that sets
     `ACNEXT_WORKBENCH_ENV_VAR=file:///app/share/AnycubicSlicerNext/resources/workbench/index.html`
     and `exec`s the real binary — same purpose as the Nix flake's `profile` env vars, just
     via a wrapper script instead of a `buildFHSEnv` `profile`.

## GitHub Actions workflow

- Runs in `ghcr.io/flathub-infra/flatpak-github-actions:gnome-50` (pre-baked runtime image —
  avoids a slow/space-hungry fresh SDK pull) with `--privileged` (needed for bubblewrap).
- Step 1: `flatpak/flatpak-github-actions/flatpak-builder@v6` to build the app into a local
  repo (cache the `.flatpak-builder` state dir via its built-in `cache-key` input).
- Step 2: `andyholmes/flatter` action, pointed at the manifest, with GPG signing enabled
  (secret holding the private key) and `upload-pages-artifact: true`.
- Step 3: `actions/deploy-pages` to publish to GitHub Pages.
- Trigger: on push to `main` (rebuild latest) and optionally on a schedule/manual dispatch for
  picking up upstream `.deb` updates (paired with `update-anycubic-slicer.sh`, mirroring the
  Nix flake's update script).
- Add an explicit disk-cleanup step before the build (remove preinstalled Android
  SDK/.NET/etc.) since GNOME runtime + WebKitGTK + the ~130 MB `.deb` payload can get close to
  the ~14 GB guaranteed free space on standard runners.

## Verification (to run once implemented)

1. `flatpak-builder --user --install --force-clean build-dir io.github.roccorakete.AnycubicSlicerNext.yml`
   locally to build and install for testing before touching CI.
2. `flatpak run io.github.roccorakete.AnycubicSlicerNext` — confirm it starts, confirm the
   Home tab (network/TLS-dependent content) and the Workbench tab (the
   `ACNEXT_WORKBENCH_ENV_VAR` fix) both render actual content, not blank white — reusing the
   same manual click-and-inspect approach used to debug the Nix build.
3. If TLS/login fails ("TLS support is not available" equivalent), confirm whether
   `org.gnome.Platform`//50 actually bundles glib-networking; add it as an extra module if not.
4. Confirm the GitHub Actions workflow produces a working GitHub Pages Flatpak repo end to
   end: `flatpak remote-add --user anycubic-slicer-next <pages-url>/index.flatpakrepo` on a
   clean machine/VM, then `flatpak install` and `flatpak run`.
5. Document the `--user`-install recommendation (and the untested system-wide-install
   `O_NOATIME` risk) in this repo's README/NOTES.md.
