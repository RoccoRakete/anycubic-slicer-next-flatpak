#!/usr/bin/env bash
# Regression test for update-anycubic-slicer.sh: runs it offline against fixture Packages
# indexes (one per .deb naming scheme Anycubic has used so far) on a scratch copy of the
# manifest + appdata, and checks the resulting pins and <release> entry.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# $1 = .deb filename as it appears in the Packages index, $2 = expected release date
check() {
  local deb="$1" expected_date="$2"
  local work sha
  work="$(mktemp -d)"
  sha="$(printf '%064d' 0 | tr 0 a)"
  cp "$repo_root/update-anycubic-slicer.sh" \
     "$repo_root/io.github.roccorakete.AnycubicSlicerNext.yml" \
     "$repo_root/io.github.roccorakete.AnycubicSlicerNext.appdata.xml" "$work/"
  cat > "$work/Packages" <<EOF
Package: anycubicslicernext
Version: 9.9.99
Filename: pool/main/a/anycubicslicernext/$deb
SHA256: $sha
EOF

  if ! PACKAGES_URL="file://$work/Packages" "$work/update-anycubic-slicer.sh" > "$work/log" 2>&1; then
    echo "FAIL [$deb]: script exited non-zero:"; sed 's/^/  /' "$work/log"
    failures=$((failures + 1))
  elif ! grep -q "url: .*/$deb\$" "$work/io.github.roccorakete.AnycubicSlicerNext.yml" \
    || ! grep -q "sha256: $sha\$" "$work/io.github.roccorakete.AnycubicSlicerNext.yml"; then
    echo "FAIL [$deb]: manifest url/sha256 pin not updated"
    failures=$((failures + 1))
  elif ! grep -q "<release version=\"9.9.99\" date=\"$expected_date\"/>" "$work/io.github.roccorakete.AnycubicSlicerNext.appdata.xml"; then
    echo "FAIL [$deb]: expected <release version=\"9.9.99\" date=\"$expected_date\"/>, got:"
    grep '<release ' "$work/io.github.roccorakete.AnycubicSlicerNext.appdata.xml" | sed 's/^/  /'
    failures=$((failures + 1))
  else
    echo "ok   [$deb] -> $expected_date"
  fi
  rm -rf "$work"
}

# Used up to 1.3.x: date as its own `_YYYYMMDD_` field.
check develop_AnycubicSlicerNext-1.3.96_20260319_224609-Ubuntu_24_04_3_LTS.deb 2026-03-19
# Since 2.0.x: a single `-YYYYMMDDhhmmss` timestamp.
check AnycubicSlicerNext_linux-v2.0.0.5-20260913065625.deb 2026-09-13
# Unknown scheme: must fall back to today instead of aborting.
check AnycubicSlicerNext_linux-v3.deb "$(date -u +%Y-%m-%d)"

exit "$failures"
