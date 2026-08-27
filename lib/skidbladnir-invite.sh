#!/usr/bin/env bash

skidbladnir_invite_manifest_snapshot() (
  set -euo pipefail
  umask 077
  local manifest="$1"
  local descriptor
  local owner
  local size
  local opened_identity
  local path_identity
  local canonical
  [[ -f "$manifest" && ! -L "$manifest" &&
    "$(skidbladnir_file_mode "$manifest" 2>/dev/null)" == 600 ]] || return 1
  exec 9<"$manifest"
  case "$(uname -s)" in
  Darwin)
    descriptor=/dev/fd/9
    owner="$(stat -f '%u' "$descriptor" 2>/dev/null)"
    size="$(stat -f '%z' "$descriptor" 2>/dev/null)"
    opened_identity="$(stat -f '%i' "$descriptor" 2>/dev/null)"
    path_identity="$(stat -f '%i' "$manifest" 2>/dev/null)"
    ;;
  *)
    descriptor=/proc/self/fd/9
    owner="$(stat -c '%u' "$descriptor" 2>/dev/null)"
    size="$(stat -c '%s' "$descriptor" 2>/dev/null)"
    opened_identity="$(stat -c '%i' "$descriptor" 2>/dev/null)"
    path_identity="$(stat -c '%i' "$manifest" 2>/dev/null)"
    ;;
  esac
  [[ -f "$descriptor" && -f "$manifest" && ! -L "$manifest" &&
    "$owner" == "$(id -u)" && "$size" =~ ^[1-9][0-9]{0,3}$ &&
    "$size" -le 4096 && "$opened_identity" == "$path_identity" ]] || return 1
  canonical="$(jq --stream -nce '
    reduce inputs as $item (
      {paths: [], value: null};
      if ($item | length) == 2 then
        .paths += [($item[0] | @json)] |
        .value = (.value | setpath($item[0]; $item[1]))
      else . end
    ) |
    (.paths | sort) as $paths |
    if $paths == ["[\"Arch\"]", "[\"DevServer\"]", "[\"Local\"]"] and
      (.value | type == "object" and keys == ["Arch", "DevServer", "Local"] and
        all(.[]; type == "string" and test("^https://[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+:8443/$")) and
        ([.[]] | unique | length) == 3)
    then .value else error("invalid origins") end
  ' <&9 2>/dev/null)" || return 1
  [[ -f "$manifest" && ! -L "$manifest" &&
    "$(skidbladnir_file_mode "$manifest" 2>/dev/null)" == 600 ]] || return 1
  case "$(uname -s)" in
  Darwin) path_identity="$(stat -f '%i' "$manifest" 2>/dev/null)" ;;
  *) path_identity="$(stat -c '%i' "$manifest" 2>/dev/null)" ;;
  esac
  [[ "$opened_identity" == "$path_identity" ]] || return 1
  printf '%s\n' "$canonical"
)

skidbladnir_invite_call() {
  local target="$1"
  local local_binary="$2"
  case "$target" in
  Local)
    "$local_binary" pairing-invite create
    ;;
  DevServer)
    ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 dev-server \
      '$HOME/.local/bin/skidbladnir pairing-invite create'
    ;;
  Arch)
    ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 arch \
      '$HOME/.local/bin/skidbladnir pairing-invite create'
    ;;
  *)
    die "unsupported fleet command target: $target"
    ;;
  esac
}

skidbladnir_invite_response_valid() {
  local response="$1"
  local platform="$2"
  local response_bytes
  local observed_paths
  local now_epoch
  local validated
  response_bytes="$(LC_ALL=C printf '%s' "$response" | wc -c | tr -d '[:space:]')"
  [[ "$response_bytes" =~ ^[1-9][0-9]{0,3}$ && "$response_bytes" -le 4096 ]] || return 1
  observed_paths="$(printf '%s' "$response" |
    jq --stream -er 'select(length == 2) | .[0] | @json' |
    LC_ALL=C sort)" || return 1
  [[ "$observed_paths" == $'["expiresAt"]\n["machine","handle"]\n["machine","platform"]\n["pairingInviteToken"]' ]] || return 1
  now_epoch="$(date -u '+%s')" || return 1
  [[ "$now_epoch" =~ ^[1-9][0-9]*$ ]] || return 1
  validated="$(printf '%s' "$response" | jq -ce \
    --arg platform "$platform" --argjson now "$now_epoch" '
    type == "object" and keys == ["expiresAt", "machine", "pairingInviteToken"] and
    (.pairingInviteToken | type == "string" and test("^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$")) and
    (.expiresAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?Z$")) and
    ((.expiresAt | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $expiry |
      $expiry > $now and $expiry <= ($now + 300)) and
    (.machine | type == "object" and keys == ["handle", "platform"] and
      (.handle | type == "string" and test("^mh-[0-9a-f]{32}$")) and
      .platform == $platform)
  ' 2>/dev/null)" || return 1
  [[ "$validated" == true ]]
}

skidbladnir_invite_capture() {
  local target="$1"
  local local_binary="$2"
  local status
  local -a pipeline_status
  set +e
  skidbladnir_invite_call "$target" "$local_binary" | LC_ALL=C head -c 4097
  pipeline_status=("${PIPESTATUS[@]}")
  status="${pipeline_status[0]}"
  [[ "${pipeline_status[1]}" == 0 ]] || status=65
  printf 'skidbladnir-invite-status:%d\n' "$status"
}

skidbladnir_invite() (
  set +x
  local manifest="$1"
  local local_binary="$2"
  local arch_result="" devbox_result="" local_result=""
  local arch_completion="" devbox_completion="" local_completion=""
  local arch_extra="" devbox_extra="" local_extra=""
  local arch_status=0 devbox_status=0 local_status=0
  local manifest_snapshot payload payload_bytes

  require_cmd jq
  require_cmd qrencode
  require_cmd ssh
  manifest_snapshot="$(skidbladnir_invite_manifest_snapshot "$manifest")" ||
    die "fleet origins manifest must be a strict, user-owned mode-0600 file: $manifest"

  exec 3< <(skidbladnir_invite_capture Arch "$local_binary" 2>/dev/null)
  exec 4< <(skidbladnir_invite_capture DevServer "$local_binary" 2>/dev/null)
  exec 5< <(skidbladnir_invite_capture Local "$local_binary" 2>/dev/null)
  IFS= read -r arch_result <&3 || arch_status=65
  IFS= read -r devbox_result <&4 || devbox_status=65
  IFS= read -r local_result <&5 || local_status=65
  IFS= read -r arch_completion <&3 || arch_status=65
  IFS= read -r devbox_completion <&4 || devbox_status=65
  IFS= read -r local_completion <&5 || local_status=65
  if IFS= read -r arch_extra <&3 || [[ -n "$arch_extra" ]]; then arch_status=65; fi
  if IFS= read -r devbox_extra <&4 || [[ -n "$devbox_extra" ]]; then devbox_status=65; fi
  if IFS= read -r local_extra <&5 || [[ -n "$local_extra" ]]; then local_status=65; fi
  exec 3<&- 4<&- 5<&-
  if ((arch_status == 0)) && [[ "$arch_completion" =~ ^skidbladnir-invite-status:([0-9]+)$ ]]; then
    arch_status="${BASH_REMATCH[1]}"
  else
    arch_status=65
  fi
  if ((devbox_status == 0)) && [[ "$devbox_completion" =~ ^skidbladnir-invite-status:([0-9]+)$ ]]; then
    devbox_status="${BASH_REMATCH[1]}"
  else
    devbox_status=65
  fi
  if ((local_status == 0)) && [[ "$local_completion" =~ ^skidbladnir-invite-status:([0-9]+)$ ]]; then
    local_status="${BASH_REMATCH[1]}"
  else
    local_status=65
  fi

  if ((arch_status != 0 || devbox_status != 0 || local_status != 0)) ||
    ! skidbladnir_invite_response_valid "$arch_result" Linux ||
    ! skidbladnir_invite_response_valid "$devbox_result" Linux ||
    ! skidbladnir_invite_response_valid "$local_result" Darwin; then
    die "Couldn't create the whole fleet invite. Nothing was displayed. Run ./skidbladnir invite again."
  fi

  payload="$(printf '%s\n%s\n%s\n%s\n' \
    "$manifest_snapshot" "$arch_result" "$devbox_result" "$local_result" |
    jq -sc '
      .[0] as $origins |
      .[1] as $arch |
      .[2] as $devbox |
      .[3] as $local |
      {
        kind: "skidbladnir.fleet-invite.v1",
        machines: [
          {label: "Arch", origin: $origins.Arch, machineHandle: $arch.machine.handle, pairingInviteToken: $arch.pairingInviteToken},
          {label: "Devbox", origin: $origins.DevServer, machineHandle: $devbox.machine.handle, pairingInviteToken: $devbox.pairingInviteToken},
          {label: "MacBook", origin: $origins.Local, machineHandle: $local.machine.handle, pairingInviteToken: $local.pairingInviteToken}
        ]
      }
    ')"
  printf '%s' "$payload" | jq -e '
    (.machines | map(.machineHandle) | unique | length) == 3 and
    (.machines | map(.pairingInviteToken) | unique | length) == 3
  ' >/dev/null || die "fleet invitation responses are not unique"
  payload_bytes="$(LC_ALL=C printf '%s' "$payload" | wc -c | tr -d '[:space:]')"
  ((payload_bytes <= 4096)) || die "fleet invitation exceeds the 4096-byte QR limit"

  printf '%s\n' 'Fleet invite ready. It expires in 5 minutes and works once. On the phone, open Skíðblaðnir and tap Connect.'
  printf '%s' "$payload" | qrencode -t ANSIUTF8
)
