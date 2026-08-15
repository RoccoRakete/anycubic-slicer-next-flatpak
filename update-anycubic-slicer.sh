#!/usr/bin/env bash
# Checks Anycubic's own apt repo for a newer AnycubicSlicerNext .deb and, if found,
# rewrites the `url:`/`sha256:` pins in the flatpak manifest. Mirrors the sibling Nix
# flake's update script, just targeting the flatpak-builder manifest instead of a Nix
# fetcher call.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$repo_root/io.github.roccorakete.AnycubicSlicerNext.yml"
packages_url="https://cdn-universe-slicer.anycubic.com/prod/dists/noble/main/binary-amd64/Packages"
cdn_base="https://cdn-universe-slicer.anycubic.com/prod/dists/noble/main/binary-amd64"

packages="$(curl -fsSL "$packages_url")"

filename="$(printf '%s\n' "$packages" | awk -F': ' '/^Filename:/ {print $2; exit}')"
sha256="$(printf '%s\n' "$packages" | awk -F': ' '/^SHA256:/ {print $2; exit}')"
version="$(printf '%s\n' "$packages" | awk -F': ' '/^Version:/ {print $2; exit}')"

if [[ -z "$filename" || -z "$sha256" || -z "$version" ]]; then
  echo "error: couldn't parse Packages index from $packages_url" >&2
  exit 1
fi

deb_basename="$(basename "$filename")"
new_url="$cdn_base/$deb_basename"

current_url="$(awk -F': ' '/^\s+url: https:\/\/cdn-universe-slicer/ {print $2; exit}' "$manifest")"
current_sha256="$(awk -F': ' '/^\s+sha256: /{print $2; exit}' "$manifest")"

if [[ "$current_url" == "$new_url" && "$current_sha256" == "$sha256" ]]; then
  echo "already up to date: $version ($deb_basename)"
  exit 0
fi

echo "updating: $current_url -> $new_url"
echo "          $current_sha256 -> $sha256"

python3 - "$manifest" "$new_url" "$sha256" <<'EOF'
import re
import sys

manifest_path, new_url, new_sha256 = sys.argv[1:4]
with open(manifest_path) as f:
    text = f.read()

text = re.sub(
    r"url: https://cdn-universe-slicer\.anycubic\.com/\S+\.deb",
    f"url: {new_url}",
    text,
    count=1,
)
text = re.sub(
    r"sha256: [0-9a-f]{64}\n(\s+dest-filename: anycubic-slicer-next\.deb)",
    f"sha256: {new_sha256}\n\\1",
    text,
    count=1,
)

with open(manifest_path, "w") as f:
    f.write(text)
EOF

echo "updated to version $version"
