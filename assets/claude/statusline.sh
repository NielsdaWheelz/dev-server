#!/usr/bin/env bash
# claude code status line. stdin: the statusLine JSON; stdout: one line:
#   <cwd> <branch> │ <model> <effort> │ ctx <used>% │ 5h <used>% · 7d <used>%
# branch, effort, and each rate-limit window are omitted when absent.

IFS=$'\x1f' read -r dir model ctx limits < <(jq -r '
  def pct: if type == "number" then "\(floor)%" else empty end;
  [ (.workspace.current_dir // ""),
    ([.model.display_name, .effort.level] | map(strings) | join(" ")),
    ("ctx " + (.context_window.used_percentage | pct // "--")),
    ([ ("5h " + (.rate_limits.five_hour.used_percentage | pct)),
       ("7d " + (.rate_limits.seven_day.used_percentage | pct)) ] | join(" · "))
  ] | join("")' 2>/dev/null) || exit 0

branch=''
[[ -z "$dir" ]] || branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
printf '%s\n' "${dir##*/}${branch:+ $branch} │ $model │ $ctx${limits:+ │ $limits}"
