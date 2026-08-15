#!/usr/bin/env python3
"""Rewrite the hard-coded /usr/share/AnycubicSlicerNext resource path baked into the
AnycubicSlicerNext binary to /app/share/AnycubicSlicerNext, in place.

Flatpak's /usr is the read-only runtime, not something this app's own resources can be
installed into. /app is where a Flatpak app installs its own files, and it happens to be
exactly the same length as /usr (4 characters), so this is a straight equal-length string
substitution -- no ELF section resizing or offset fixups required.
"""
import sys

OLD = b"/usr/share/AnycubicSlicerNext"
NEW = b"/app/share/AnycubicSlicerNext"
assert len(OLD) == len(NEW), "patch only works if old/new are the same length"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-binary>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()

    count = data.count(OLD)
    if count == 0:
        print(f"error: {OLD!r} not found in {path}", file=sys.stderr)
        return 1

    data = data.replace(OLD, NEW)

    with open(path, "wb") as f:
        f.write(data)

    print(f"patched {count} occurrence(s) of {OLD!r} -> {NEW!r} in {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
