#!/usr/bin/env python3
"""Rewrite the hard-coded /usr/share resource path baked into the AnycubicSlicerNext binary
to /app/share, in place.

Flatpak's /usr is the read-only runtime, not something this app's own resources can be
installed into. /app is where a Flatpak app installs its own files, and it happens to be
exactly the same length as /usr (4 characters), so this is a straight equal-length string
substitution -- no ELF section resizing or offset fixups required.

The vendor binary has used two layouts for that path so far:

  1.3.x: one literal "/usr/share/AnycubicSlicerNext".
  2.0.x: assembled at runtime as "/usr/share/" + <app name> + "/resources", so only a bare,
         NUL-terminated "/usr/share/" literal exists. The linker merged it with an identical
         literal in wxWidgets' MIME-type lookup (next to "mime/globs"), which therefore also
         moves to /app/share -- harmless, see NOTES.md #10.
"""
import sys

# (old, new, expected occurrences or None for "any"), tried in order.
LAYOUTS = [
    (b"/usr/share/AnycubicSlicerNext", b"/app/share/AnycubicSlicerNext", None),
    (b"\0/usr/share/\0", b"\0/app/share/\0", 1),
]
for old, new, _ in LAYOUTS:
    assert len(old) == len(new), "patch only works if old/new are the same length"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-binary>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()

    for old, new, expected in LAYOUTS:
        count = data.count(old)
        if count == 0:
            continue
        if expected is not None and count != expected:
            print(f"error: expected {expected} occurrence(s) of {old!r} in {path}, "
                  f"found {count} -- binary layout changed, patch needs revisiting",
                  file=sys.stderr)
            return 1

        data = data.replace(old, new)
        with open(path, "wb") as f:
            f.write(data)

        print(f"patched {count} occurrence(s) of {old!r} -> {new!r} in {path}")
        return 0

    print(f"error: none of {[old for old, _, _ in LAYOUTS]!r} found in {path}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
