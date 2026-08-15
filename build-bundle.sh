#!/usr/bin/env bash
# Builds a single, distributable dist/anycubic-slicer-next.flatpak bundle -- for handing the
# app to someone directly, as opposed to `flatpak-builder --install` (local testing) or the
# CI workflow (a hosted, updatable repo). See README.md and NOTES.md #6.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

manifest="io.github.roccorakete.AnycubicSlicerNext.yml"
app_id="io.github.roccorakete.AnycubicSlicerNext"
dist_dir="dist"

mkdir -p "$dist_dir"

flatpak-builder --disable-rofiles-fuse --repo="$dist_dir/repo" --force-clean build-dir "$manifest"

# --runtime-repo embeds the Flathub flatpakrepo URL in the bundle's metadata so that
# `flatpak install` on a machine without Flathub configured can still resolve
# org.gnome.Platform//50 / org.gnome.Sdk//50 instead of failing outright.
flatpak build-bundle \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  "$dist_dir/repo" "$dist_dir/anycubic-slicer-next.flatpak" \
  "$app_id" master

echo "built: $dist_dir/anycubic-slicer-next.flatpak"
