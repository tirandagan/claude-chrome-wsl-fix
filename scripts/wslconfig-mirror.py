#!/usr/bin/env python3
"""Set networkingMode=Mirrored under [wsl2] in a .wslconfig file, in place.

Keeps every other line and section as it is, replaces an existing
networkingMode line inside [wsl2], adds [wsl2] if missing, and writes CRLF
line endings (it is a Windows file). Exit 0 always prints CHANGED or UNCHANGED.

usage: wslconfig-mirror.py <path-to-.wslconfig>
"""
import os
import re
import sys


def mirror(text: str) -> str:
    out, in_wsl2, done, seen_wsl2 = [], False, False, False
    for ln in text.splitlines():
        m = re.match(r"\s*\[(.+?)\]\s*$", ln)
        if m:
            if in_wsl2 and not done:
                out.append("networkingMode=Mirrored")
                done = True
            in_wsl2 = m.group(1).strip().lower() == "wsl2"
            seen_wsl2 |= in_wsl2
        elif in_wsl2 and re.match(r"\s*networkingMode\s*=", ln, re.I):
            ln, done = "networkingMode=Mirrored", True
        out.append(ln)
    if in_wsl2 and not done:
        out.append("networkingMode=Mirrored")
        done = True
    if not seen_wsl2:
        out += (["", "[wsl2]"] if out else ["[wsl2]"]) + ["networkingMode=Mirrored"]
    return "\n".join(out) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 64
    path = sys.argv[1]
    old = open(path, encoding="utf-8-sig").read() if os.path.exists(path) else ""
    new = mirror(old)
    if new.replace("\r\n", "\n") == old.replace("\r\n", "\n"):
        print("UNCHANGED")
        return 0
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(new)
    print("CHANGED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
