#!/usr/bin/env bash
# claude supplies the session fields. skid reads this profile's quota cache locally.

# a directory may contain newlines or shell field separators.
{
  IFS= read -r -d '' dir && IFS= read -r -d '' summary
} < <(python3 -c '
import json
import math
import sys

def fields(value):
    return value if isinstance(value, dict) else {}

data = fields(json.load(sys.stdin))
directory = fields(data.get("workspace")).get("current_dir")
phrase = (fields(data.get("model")).get("display_name"), fields(data.get("effort")).get("level"))
model = " ".join(part for part in phrase if isinstance(part, str))
context = fields(data.get("context_window")).get("used_percentage")
known = type(context) is int or (type(context) is float and math.isfinite(context))
ctx = "ctx " + (f"{math.floor(context)}%" if known else "--")

print(directory if isinstance(directory, str) else "", model + " │ " + ctx, sep="\0", end="\0")
' 2>/dev/null) || exit 0

branch=''
[[ -z "$dir" ]] || branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
line="${dir##*/}${branch:+ $branch} │ $summary"
line="${line//[[:cntrl:]]/ }"
limits="$("$HOME/.local/bin/skid" claude-usage 2>/dev/null)" || limits=''
if [[ ${COLUMNS:-} =~ ^[1-9][0-9]{0,4}$ ]]; then
  # the separators occupy one cell each. count other bytes conservatively.
  LC_ALL=C
  while [[ -n "$limits" ]]; do
    candidate="$line │ $limits"
    width_text="${candidate//│/|}"
    width_text="${width_text//·/.}"
    (( ${#width_text} + 4 <= COLUMNS )) && break
    if [[ "$limits" == *' · '* ]]; then
      limits="${limits% · *}"
    else
      limits=''
    fi
  done
fi
printf '%s\n' "$line${limits:+ │ $limits}"
