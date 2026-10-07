#!/usr/bin/env bash
# claude code status line. stdin: the statusLine JSON; stdout: one line:
#   <cwd> <branch> │ <model> <effort> │ ctx <used>% │ 5h <used>% · 7d <used>%
# branch, effort, and each rate-limit window are omitted when absent.
# the quota report is a callback observation; its provider data may be cached.
# --publish-skid-usage enables account-local reporting on the selected host.

IFS=$'\x1f' read -r dir model ctx limits report < <(jq -r '
  def pct: if type == "number" then "\(floor)%" else empty end;
  def instant:
    (tostring | capture("^(?<whole>[0-9]+)(?:\\.(?<fraction>[0-9]+))?(?:[eE](?<exponent>[+-]?[0-9]+))?$")) as $decimal |
    ($decimal.whole + ($decimal.fraction // "")) as $digits |
    (($decimal.whole | length) + (($decimal.exponent // "0") | tonumber)) as $point |
    ($digits[:$point] + ("0" * ([$point - ($digits | length), 0] | max)) |
     sub("^0+"; "")) as $integral |
    ($digits[$point:] | sub("0+$"; "")) as $fraction |
    ($integral | tonumber | todateiso8601 | rtrimstr("Z")) as $whole |
    if $whole | test("^[0-9]{4}-") then
      $whole + (if $fraction == "" then "" else "." + $fraction end) + "Z"
    else error("invalid instant") end;
  def window($received):
    if . == null then null
    elif type != "object" or (.used_percentage | type) != "number"
         or (.used_percentage | isfinite | not) or .used_percentage < 0
    then error("invalid quota")
    elif .resets_at != null and
         ((.resets_at | type) != "number" or (.resets_at | isfinite | not))
    then error("invalid reset")
    elif .resets_at != null and .resets_at <= $received then null
    else {usedPercent: .used_percentage} +
         (if .resets_at == null then {} else
            {resetsAt: (.resets_at | instant)}
          end)
    end;
  def usage:
    now as $received |
    (.rate_limits.five_hour | window($received)) as $five |
    (.rate_limits.seven_day | window($received)) as $seven |
    {schemaVersion: 1, reportedAt: ($received | instant)} +
    (if $five == null then {} else {fiveHour: $five} end) +
    (if $seven == null then {} else {sevenDay: $seven} end) | tojson;
  [ (.workspace.current_dir // ""),
    ([.model.display_name, .effort.level] | map(strings) | join(" ")),
    ("ctx " + (.context_window.used_percentage | pct // "--")),
    ([ ("5h " + (.rate_limits.five_hour.used_percentage | pct)),
       ("7d " + (.rate_limits.seven_day.used_percentage | pct)) ] | join(" · ")),
    (try usage catch "")
  ] | join("")' 2>/dev/null) || exit 0

temporary=''
trap '[[ -z "$temporary" ]] || rm -f -- "$temporary" 2>/dev/null' EXIT
trap 'exit 0' HUP INT TERM
if [[ "${1:-}" == --publish-skid-usage &&
      "${CLAUDE_CONFIG_DIR:-}" == /* && -n "$report" ]]; then
  temporary="$(mktemp "$CLAUDE_CONFIG_DIR/.skidbladnir-usage.XXXXXX" 2>/dev/null)" || temporary=''
  if [[ -n "$temporary" ]]; then
    { printf '%s\n' "$report" > "$temporary" &&
      mv -f -- "$temporary" "$CLAUDE_CONFIG_DIR/skidbladnir-usage.json"; } 2>/dev/null
  fi
fi

branch=''
[[ -z "$dir" ]] || branch="$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null ||
  git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
printf '%s\n' "${dir##*/}${branch:+ $branch} │ $model │ $ctx${limits:+ │ $limits}"
