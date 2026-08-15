#!/usr/bin/env bash
# Checks Anycubic's own apt repo for a newer AnycubicSlicerNext .deb and, if found,
# rewrites the `url:`/`sha256:` pins in the flatpak manifest. Mirrors the sibling Nix
# flake's update script, just targeting the flatpak-builder manifest instead of a Nix
# fetcher call.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$repo_root/io.github.roccorakete.AnycubicSlicerNext.yml"
appdata="$repo_root/io.github.roccorakete.AnycubicSlicerNext.appdata.xml"
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

# The .deb filename embeds a build timestamp, e.g.
# develop_AnycubicSlicerNext-1.3.96_20260319_224609-Ubuntu_24_04_3_LTS.deb -- use its date
# as the AppStream release date rather than "today" (today is when CI happened to run,
# not when the vendor actually shipped this build).
release_date="$(printf '%s\n' "$deb_basename" | grep -oE '_[0-9]{8}_' | head -1 | tr -d '_')"
if [[ -n "$release_date" ]]; then
  release_date="${release_date:0:4}-${release_date:4:2}-${release_date:6:2}"
else
  release_date="$(date -u +%Y-%m-%d)"
fi

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

# Prepend a <release> entry to the AppStream metadata -- this is what feeds "flatpak update"
# changelogs and the version history GNOME Software/Discover show. Skip it if this exact
# version is already the newest entry (re-running the script twice for the same version,
# e.g. a manual test, shouldn't duplicate it).
python3 - "$appdata" "$version" "$release_date" <<'EOF'
import re
import sys

appdata_path, version, release_date = sys.argv[1:4]
with open(appdata_path) as f:
    text = f.read()

existing = re.search(r'<release version="([^"]+)"', text)
if existing and existing.group(1) == version:
    print(f"appdata.xml already lists version {version} as newest, leaving releases as-is")
else:
    new_entry = f'    <release version="{version}" date="{release_date}"/>\n'
    text = text.replace("  <releases>\n", "  <releases>\n" + new_entry, 1)
    with open(appdata_path, "w") as f:
        f.write(text)
    print(f"appdata.xml: added release {version} ({release_date})")
EOF

echo "updated to version $version"
