#!/usr/bin/env bash
# claude code status line. the optional reset row precedes the usual usage row.

# a directory may contain newlines or shell field separators.
{
  IFS= read -r -d '' dir && IFS= read -r -d '' summary && IFS= read -r -d '' resets
} < <(python3 -c '
import json
import math
import os
import sys
from datetime import datetime, timezone

def fields(value):
    return value if isinstance(value, dict) else {}

def finite_number(value):
    return type(value) is int or (type(value) is float and math.isfinite(value))

def reset_text(value):
    if not finite_number(value):
        return ""
    try:
        local = datetime.fromtimestamp(math.floor(value), timezone.utc).astimezone()
    except (OSError, OverflowError, ValueError):
        return ""
    offset = local.strftime("%z")
    if len(offset) != 5:  # Some historical offsets include seconds.
        return ""
    return f"{local.date().isoformat()} {local:%H:%M:%S} {offset}"

data = fields(json.load(sys.stdin))
directory = fields(data.get("workspace")).get("current_dir")
phrase = (fields(data.get("model")).get("display_name"), fields(data.get("effort")).get("level"))
model = " ".join(part for part in phrase if isinstance(part, str))
context = fields(data.get("context_window")).get("used_percentage")
ctx = "ctx " + (f"{math.floor(context)}%" if finite_number(context) else "--")

limits = fields(data.get("rate_limits"))
amounts = []
resets = []
for key, label in (("seven_day", "7d"), ("five_hour", "5h")):
    window = fields(limits.get(key))
    used = window.get("used_percentage")
    if not finite_number(used) or not 0 <= used <= 100:
        continue
    amounts.insert(0, f"{label} {math.floor(used)}%")  # The usage row lists 5h first.
    stamp = reset_text(window.get("resets_at"))
    if stamp:
        resets.append(f"{label} {stamp}")

columns = os.environ.get("COLUMNS", "")
try:
    width = int(columns) if columns.isascii() and columns.isdecimal() else 0
except ValueError:
    width = 0
if width < 39:
    resets.clear()
elif width < 70:
    del resets[1:]
summary = [model, ctx]
if amounts:
    summary.append(" · ".join(amounts))
print(directory if isinstance(directory, str) else "", " │ ".join(summary),
      " · ".join(resets), sep="\0", end="\0")
' 2>/dev/null) || exit 0

branch=''
[[ -z "$dir" ]] || branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
[[ -z "$resets" ]] || printf 'resets %s\n' "$resets"
printf '%s │ %s\n' "${dir##*/}${branch:+ $branch}" "$summary"
