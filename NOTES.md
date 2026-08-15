# Development notes

Findings about the upstream Anycubic Slicer Next 1.3.96 binary, carried over and adapted from
the sibling [Nix flake project](https://github.com/roccorakete/anycubic-slicer-next)'s
`NOTES.md`. The Nix flake hit every one of these bugs while packaging the exact same `.deb`
for `buildFHSEnv`; this file explains which fixes carry over to Flatpak as-is, which turn out
to be unnecessary here, and which are still open questions to verify once this project has a
working build.

## Bugs found in the Nix flake and their status under Flatpak

### 1. `O_NOATIME` + read-only/root-owned files → `EPERM` on every local resource read

**Nix flake finding:** the app opens its own bundled HTML/CSS/JS/images (under `resources/`)
with the `O_NOATIME` flag. Linux only allows `O_NOATIME` for the file's owner or a
`CAP_FOWNER`-holding process. Nix store paths are owned by `root`; the app runs as a normal
user → every such `open()` failed with `EPERM`, silently, and every embedded WebView showed
blank white.

**Under Flatpak:** likely a non-issue for the common case. `flatpak install --user` (the
default most desktop users and GNOME Software use) installs into `~/.local/share/flatpak/`,
owned by the invoking user — so `/app`'s files inside the sandbox are owned by the same user
running the app, and the `O_NOATIME` check passes. It only reappears for a **system-wide**
`flatpak install` (`/var/lib/flatpak`, root-owned), because bubblewrap doesn't remap UIDs —
whatever owns the file on the host is what the sandboxed process sees too, and a non-root
user has neither matching-owner nor `CAP_FOWNER` in that case.

**Open item:** confirm on a real system-wide install whether this actually breaks anything —
the app might gracefully retry without `O_NOATIME` on `EPERM` (this is the documented/expected
fallback pattern for that flag, since it's just an optimization hint), or it might not. Until
verified, document `--user` installs as the supported path.

### 2. Missing GIO TLS backend → "TLS support is not available"

**Nix flake finding:** `glib-networking`'s GIO module (`libgiognutls.so`) wasn't discoverable
via `GIO_EXTRA_MODULES`, so GIO silently fell back to `GDummyTlsBackend` and every HTTPS
connection (login, cloud sync) failed with that exact message in a popup.

**Under Flatpak:** `org.gnome.Platform` is expected to bundle glib-networking already (it's a
near-universal dependency for GNOME/GTK apps doing HTTPS via GIO) — **unverified**, check with
`flatpak run --command=cat org.gnome.Platform//50 /usr/manifest.json | jq` once buildable
locally. If it turns out to be missing, add `glib-networking` as an ordinary flatpak-builder
module (small, fast meson build) rather than fighting module-path env vars.

### 3. WebKitGTK sandboxing/compositing conflicts with the Nix flake's own `bwrap` sandbox

**Nix flake finding:** WebKitGTK's own internal bubblewrap-based process sandboxing doesn't
nest cleanly inside an ad-hoc `buildFHSEnv` bubblewrap sandbox — repeated
`WebKitWebProcess`/`WebKitNetworkProcess` churn, occasional "Permission denied" trying to
re-exec itself. Required `WEBKIT_DISABLE_COMPOSITING_MODE=1`,
`WEBKIT_DISABLE_DMABUF_RENDERER=1`, `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`,
`GDK_BACKEND=x11`.

**Under Flatpak:** expected to just work. GNOME's own Epiphany (WebKitGTK-based browser)
ships as a Flatpak and uses `flatpak-spawn` to get a fresh Flatpak sandbox for its web-content
subprocesses, cooperating with (rather than nesting inside) Flatpak's own sandboxing — this is
shipped, working behavior on Flathub today, no special env vars documented as required.
**Plan: don't add any of the above env vars preemptively.** Only reach for them if testing
under Flatpak actually reproduces the same symptoms.

### 4. `libWorkbench.so`'s `registerHandler()` is a no-op stub (the big one)

**Nix flake finding, fully applicable here — this is a vendor bug in the binary itself, not
an artifact of Nix packaging:**

- The "Workbench" tab (device/cloud printer management — login, add printer, video monitor)
  stays blank even when every environment-level fix above is applied, and even though the
  exact same HTML renders fine when loaded directly with a standalone WebKitGTK test program.
- `objdump -d` on `libWorkbench.so`: the exported `registerHandler` function is literally
  `endbr64; ret` — 5 bytes, does nothing with its arguments.
- `gdb` breakpoints on `webkit_uri_scheme_request_finish`/`_finish_error` never fire when the
  tab is clicked — the custom `pages://` URI scheme handler (registered elsewhere in the
  closed-source main binary, not in `libWorkbench.so`) never gets a response to serve.
- The *content* is not missing: `libWorkbench.so`'s `.rodata` contains a small header
  (`"Workbench\0" + <md5 hex>\0`) immediately followed by a complete, valid ZIP (starts at the
  `PK\x03\x04` signature) with a full Vue.js SPA — `index.html`,
  `js/src_views_workbench_Workbench_vue.js`, `js/src_views_login_LoginPage_vue.js`,
  `webrtcstreamer.js`, fonts, images of every printer model, etc. `unzip -t` reports zero CRC
  errors.
- The public source at github.com/ANYCUBIC-3D/AnycubicSlicerNext (the OrcaSlicer fork this app
  is built on) contains **no** reference to `Workbench`, `registerHandler`, `pages://`, or
  `webkit_web_context_register_uri_scheme` anywhere — this feature is 100% closed-source,
  layered on top of the public tree at build time, so there's no source to consult.
- `strings` on the main binary turned up `ACNEXT_WORKBENCH_ENV_VAR` (and
  `ACNEXT_HOMEPAGE_ENV_VAR`) — an internal developer/debug override read via `getenv()`.
  Setting it to a `file://` URL pointing at a manually-extracted copy of the embedded SPA
  makes the Workbench tab render perfectly, bypassing the broken `pages://` handler entirely.

**Fix (carries over as-is):** extract the ZIP from `libWorkbench.so` at build time (find the
`PK\x03\x04` offset, don't hard-code a byte count — a future vendor build could change the
header size) into `/app/share/AnycubicSlicerNext/resources/workbench/`, then set
`ACNEXT_WORKBENCH_ENV_VAR=file:///app/share/AnycubicSlicerNext/resources/workbench/index.html`
in the wrapper script.

Very likely shipping *broken for everyone* right now, not just under sandboxed packaging — the
`.deb`'s filename literally starts with `develop_` and has sat unchanged in the vendor's "prod"
APT repo for months. Worth re-checking whether a future upstream version fixes this properly
(making the workaround unnecessary) before spending more effort on it.

### 5. GTK3 backend selection: the app only ever tries X11, never Wayland

**Found while first getting the Flatpak build to actually launch, not predicted by the plan.**

The packaged binary starts, does its single-instance file-lock check, spawns the Pango/
fontconfig thread, then calls `gtk_init_check()` -- which returned `FALSE` every time under
Flatpak on a Wayland session, confirmed with a debugger breakpoint (`$rax == 0` right after
the call). The app's own error-handling path then tries to disconnect a signal handler from
an object that was never constructed because init failed, producing a
`GLib-GObject-CRITICAL: invalid (NULL) pointer instance` / `g_signal_handlers_disconnect_matched`
assertion pair, immediately followed by `exit(-1)`. No window, no crash dump, no useful
message -- just a silent-ish bail. This is *not* a WebKitGTK bug (bug #3 above); it happens
before any WebKit/display-connection code runs at all, confirmed via strace showing zero
`socket()`/`connect()` calls before the exit.

Root cause, found with `GDK_DEBUG=misc`: GDK logs `Trying x11 backend` and nothing else --
this vendor GTK3 build never attempts the Wayland backend, regardless of `GDK_BACKEND`. (The
sibling Nix flake independently arrived at the same conclusion -- its `profile` script forces
`GDK_BACKEND=x11` -- but didn't record *why* it was necessary, just that testing showed it was
needed. This session's debugging fills in the actual mechanism.)

That alone would be harmless (X11-via-Xwayland normally works fine as a fallback on a Wayland
session) except: Flatpak's `--socket=fallback-x11` finish-arg **only grants X11 socket access
when no Wayland socket is available**. On a Wayland session (which is the common case), the
X11 socket is intentionally *not* bind-mounted in, `DISPLAY` stays unset inside the sandbox
(confirmed: empty `/tmp/.X11-unix` and empty `$DISPLAY` inside the sandbox despite the host
having a live Xwayland socket at `/tmp/.X11-unix/X0`), and GTK's only backend has nothing to
connect to.

**Fix:** use the unconditional `--socket=x11` finish-arg instead of `--socket=fallback-x11`,
and set `GDK_BACKEND=x11` explicitly in the wrapper script (belt-and-suspenders --
`--socket=x11` alone was sufficient in testing since the app doesn't try Wayland anyway, but
forcing it matches the Nix flake's proven-working config and documents the intent).

Debugging technique used to nail this down, worth keeping in mind for future issues with this
binary: `flatpak run --user --devel --command=sh <app-id> -c '...'` drops into the app's own
sandbox with the SDK (not just the runtime) mounted, so `gdb`/`strace` are available inside
the exact environment the app actually runs in. `gdb -batch -ex "break gtk_init_check" -ex run
-ex finish -ex "print/x \$rax"` was what confirmed the `FALSE` return.

## Bugs NOT expected to apply under Flatpak

- The hard-coded `/usr/share/AnycubicSlicerNext/resources` path: the Nix flake worked around
  this by making that literal path exist inside a custom FHS sandbox. Flatpak's `/usr` is the
  read-only runtime and can't be extended this way at all — instead this project ELF-patches
  the binary's path string from `/usr/...` to `/app/...` at build time (a lucky equal-length
  substitution — both prefixes are 4 characters). **Verify this patch doesn't break anything**
  (e.g. if the path is also used to derive other paths at runtime in a way a plain string
  substitution doesn't account for) before assuming it "just works" the way the Nix bind-mount
  did.
- `PATH`/`/usr/bin` lookup quirks and the FHS-merge library layout the Nix flake needed
  (`buildFHSEnv`'s rootfs merging multiple packages' `/usr/lib` into one directory) don't
  apply — Flatpak's runtime already provides a normal, complete `/usr` and the app's own libs
  just go in `/app/lib`.

## Useful debugging techniques (from the Nix flake work, still applicable here)

- **`webkit_web_view_get_snapshot()` via a small custom GTK+WebKitGTK test program** is a fast
  way to check "does this exact HTML/JS render correctly at all in this exact environment"
  without needing a full desktop screenshot — write a PNG, read it back.
- **`gdb -p <pid>` attached to the already-running app**, breaking on public WebKitGTK API
  symbols (`webkit_web_view_load_uri`, `webkit_web_context_register_uri_scheme`,
  `webkit_uri_scheme_request_finish[_error]`) reveals real navigation URLs and scheme
  registrations without needing debug symbols in the target.
  - `pgrep -f AnycubicSlicerNext` self-matches your own shell command line if it contains that
    string (e.g. in a heredoc). Use `pgrep -x AnycubicSlicerN` instead (Linux's `comm` field
    truncates to 15 chars).
- **`xdotool` + `xwd`/`convert`** (ImageMagick 7's `import` errored out under the sandbox setup
  used for the Nix work) to screenshot a specific window by ID for fast visual iteration.
- **`objdump -d -M intel`** on a suspiciously tiny/data-heavy `.so` (`readelf -S` showing
  `.text` a few hundred bytes vs. `.rodata` tens of MB) is worth doing early if a "plugin"
  library is involved — it may just be an embedded-data container with a stub loader, not real
  code, as `libWorkbench.so` turned out to be.
- **`grep -abo $'PK\x03\x04' file`** finds the byte offset of an embedded ZIP inside an
  arbitrary binary blob — used both for extracting `libWorkbench.so`'s payload and for the
  equivalent step in this project's flatpak-builder module.
