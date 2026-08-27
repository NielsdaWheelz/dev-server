#!/usr/bin/env bash

skidbladnir_invite_manifest_valid() {
  local manifest="$1"
  local owner
  [[ -f "$manifest" && ! -L "$manifest" && "$(skidbladnir_file_mode "$manifest" 2>/dev/null)" == 600 ]] || return 1
  case "$(uname -s)" in
  Darwin) owner="$(stat -f '%u' "$manifest" 2>/dev/null)" ;;
  *) owner="$(stat -c '%u' "$manifest" 2>/dev/null)" ;;
  esac
  [[ "$owner" == "$(id -u)" ]] || return 1
  jq -e '
    type == "object" and keys == ["Arch", "DevServer", "Local"] and
    all(.[]; type == "string" and test("^https://[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+:8443/$")) and
    ([.[]] | unique | length) == 3
  ' "$manifest" >/dev/null 2>&1
}

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
  printf '%s' "$response" | jq -e --arg platform "$platform" '
    type == "object" and keys == ["expiresAt", "machine", "pairingInviteToken"] and
    (.pairingInviteToken | type == "string" and test("^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$")) and
    (.expiresAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]+)?Z$")) and
    (.machine | type == "object" and keys == ["handle", "platform"] and
      (.handle | type == "string" and test("^mh-[0-9a-f]{32}$")) and
      .platform == $platform)
  ' >/dev/null 2>&1
}

skidbladnir_invite_capture() {
  local target="$1"
  local local_binary="$2"
  local status
  set +e
  skidbladnir_invite_call "$target" "$local_binary"
  status=$?
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
  local payload payload_bytes

  require_cmd jq
  require_cmd qrencode
  require_cmd ssh
  skidbladnir_invite_manifest_valid "$manifest" ||
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

  payload="$(printf '%s\n%s\n%s\n' "$arch_result" "$devbox_result" "$local_result" |
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
    ' "$manifest" -)"
  printf '%s' "$payload" | jq -e '
    (.machines | map(.machineHandle) | unique | length) == 3 and
    (.machines | map(.pairingInviteToken) | unique | length) == 3
  ' >/dev/null || die "fleet invitation responses are not unique"
  payload_bytes="$(LC_ALL=C printf '%s' "$payload" | wc -c | tr -d '[:space:]')"
  ((payload_bytes <= 4096)) || die "fleet invitation exceeds the 4096-byte QR limit"

  printf '%s\n' 'Fleet invite ready. It expires in 5 minutes and works once. On the phone, open Skíðblaðnir and tap Connect.'
  printf '%s' "$payload" | qrencode -t ANSIUTF8
)
