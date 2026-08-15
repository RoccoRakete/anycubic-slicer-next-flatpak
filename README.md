# anycubic-slicer-next-flatpak

Unofficial Flatpak packaging for [Anycubic Slicer Next](https://github.com/ANYCUBIC-3D/AnycubicSlicer),
distro-independent (works on any Linux with Flatpak support). Anycubic only ships the slicer as
a proprietary `.deb` for Ubuntu 24.04; this project downloads the official package and
repackages it as a Flatpak.

Sibling project: [`anycubic-slicer-next-flake`](https://github.com/RoccoRakete/anycubic-slicer-next-flake),
a Nix flake doing the same job for NixOS specifically.

**Status:** builds and runs locally via `flatpak-builder`, and publishes to a hosted, updatable
Flatpak repository via GitHub Actions (see below). See [PLAN.md](PLAN.md) for the architecture
and [NOTES.md](NOTES.md) for known upstream bugs and how they're worked around.

## Installing from the published repo

This repo only hosts the app itself, not the `org.gnome.Platform//50` runtime it depends on --
that comes from Flathub, so Flathub has to be added as a remote too (most desktops already
have it; the command below is a no-op if so):

```sh
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --user --if-not-exists anycubic-slicer-next-flatpak \
  https://roccorakete.github.io/anycubic-slicer-next-flatpak/index.flatpakrepo
flatpak install --user anycubic-slicer-next-flatpak io.github.roccorakete.AnycubicSlicerNext
```

Updates land via the normal `flatpak update` -- no manual re-download needed, unlike the
`.flatpak` bundle route below.

## Building and running locally

```sh
flatpak install --user flathub org.gnome.Sdk//50 org.gnome.Platform//50
flatpak-builder --user --install --force-clean build-dir \
  io.github.roccorakete.AnycubicSlicerNext.yml
flatpak run --user io.github.roccorakete.AnycubicSlicerNext
```

## Building a distributable `.flatpak` bundle

For handing the app to someone directly (no repo hosting, no GitHub Pages/CI) rather than
installing it into your own local `flatpak-builder` output, use `build-bundle.sh`:

```sh
./build-bundle.sh
```

This produces `dist/anycubic-slicer-next.flatpak`, a single file the recipient installs with:

```sh
flatpak install --user anycubic-slicer-next.flatpak
```

The script passes `--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo` to
`flatpak build-bundle` -- **do not drop this flag**. Without it, the bundle has no record of
where `org.gnome.Platform//50`/`org.gnome.Sdk//50` come from, and `flatpak install` fails on
any machine that doesn't already have Flathub configured as a remote (see NOTES.md).

## CI: build, version, and publish

[`build-and-publish.yml`](.github/workflows/build-and-publish.yml) does three things:

- **Version:** on a weekly schedule, `update-anycubic-slicer.sh` checks Anycubic's own apt
  repo for a newer `.deb`. If found, it bumps the manifest's `url`/`sha256` pin, prepends an
  `<release>` entry to the AppStream metadata (version + the `.deb`'s own build date, not
  "today"), commits, tags the commit `vX.Y.ZZ`, and pushes -- which triggers the next step.
- **Build:** on every push to `main` that touches the manifest/patch/wrapper/desktop files (or
  via manual `workflow_dispatch`), installs `flatpak`/`flatpak-builder`/the GNOME 50 SDK fresh
  on a bare runner (rather than depending on a specific prebuilt container tag existing, see
  NOTES.md #7) and builds + signs the repository with
  [`andyholmes/flatter`](https://github.com/andyholmes/flatter).
- **Publish:** uploads the signed repo to GitHub Pages, builds a standalone signed
  `anycubic-slicer-next.flatpak` bundle (same as `build-bundle.sh` produces locally), and
  creates/updates a [GitHub Release](../../releases) tagged `vX.Y.ZZ` with that bundle
  attached -- an alternative for people who'd rather download a file than
  `flatpak remote-add`.

### One-time setup (already done for this repo, documented for reference / key rotation)

1. Generate a signing key: `gpg --batch --passphrase '' --quick-gen-key "<uid>" default default never`
2. Add the exported private key as the `GPG_SIGN_KEY` repo secret:
   `gpg --armor --export-secret-key <fingerprint> | gh secret set GPG_SIGN_KEY`
3. Publish the public key in the repo for manual verification (`signing-key.gpg.asc`):
   `gpg --armor --export <fingerprint> > signing-key.gpg.asc`
4. Enable GitHub Pages with "GitHub Actions" as the source:
   `gh api repos/<owner>/<repo>/pages -X POST -f build_type=workflow`
5. Delete the private key material from local disk once the secret is uploaded -- only the
   `GPG_SIGN_KEY` secret and this repo's `signing-key.gpg.asc` need to persist.

## License

The slicer itself is closed-source software by Anycubic. This project contains none of the
slicer's code — it downloads the official `.deb` from Anycubic's CDN at build time.
