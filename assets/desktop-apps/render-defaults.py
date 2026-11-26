"""Overlay one group's site defaults, retaining unrelated settings and comments."""

from pathlib import Path
import sys


def render(current, defaults):
    header, *entries = defaults.splitlines()
    wanted = dict(entry.split("=", 1) for entry in entries)
    seen = set()
    result = []
    in_group = False
    found_group = False
    for line in current.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_group:
                result.extend(f"{k}={v}" for k, v in wanted.items() if k not in seen)
                seen.update(wanted)
            in_group = stripped == header
            found_group |= in_group
        key, equals, _ = line.partition("=")
        if in_group and equals and key.strip() in wanted:
            key = key.strip()
            line = f"{key}={wanted[key]}"
            seen.add(key)
        result.append(line)
    if not found_group:
        if result and result[-1]:
            result.append("")
        result.append(header)
    result.extend(f"{k}={v}" for k, v in wanted.items() if k not in seen)
    return "\n".join(result) + "\n"


if __name__ == "__main__":
    existing, declared = map(Path, sys.argv[1:])
    sys.stdout.write(render(existing.read_text() if existing.exists() else "", declared.read_text()))
