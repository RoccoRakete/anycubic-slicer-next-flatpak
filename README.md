# anycubic-slicer-next-flatpak

Unofficial Flatpak packaging for [Anycubic Slicer Next](https://github.com/ANYCUBIC-3D/AnycubicSlicer),
distro-independent (works on any Linux with Flatpak support). Anycubic only ships the slicer as
a proprietary `.deb` for Ubuntu 24.04; this project downloads the official package and
repackages it as a Flatpak.

Sibling project: [`anycubic-slicer-next`](https://github.com/roccorakete/anycubic-slicer-next),
a Nix flake doing the same job for NixOS specifically.

**Status:** planning/setup stage — see [PLAN.md](PLAN.md) for the architecture and
[NOTES.md](NOTES.md) for known upstream bugs and how they're worked around. No manifest or CI
workflow exists yet.

## License

The slicer itself is closed-source software by Anycubic. This project contains none of the
slicer's code — it downloads the official `.deb` from Anycubic's CDN at build time.
