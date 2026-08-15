# anycubic-slicer-next-flatpak

Unofficial Flatpak packaging for [Anycubic Slicer Next](https://github.com/ANYCUBIC-3D/AnycubicSlicer),
distro-independent (works on any Linux with Flatpak support). Anycubic only ships the slicer as
a proprietary `.deb` for Ubuntu 24.04; this project downloads the official package and
repackages it as a Flatpak.

Sibling project: [`anycubic-slicer-next`](https://github.com/roccorakete/anycubic-slicer-next),
a Nix flake doing the same job for NixOS specifically.

**Status:** builds and runs locally via `flatpak-builder`. See [PLAN.md](PLAN.md) for the
architecture and [NOTES.md](NOTES.md) for known upstream bugs and how they're worked around.
The GitHub Actions publish workflow hasn't been exercised in CI yet (needs a GPG signing key
secret configured on the repo first).

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

## License

The slicer itself is closed-source software by Anycubic. This project contains none of the
slicer's code — it downloads the official `.deb` from Anycubic's CDN at build time.
