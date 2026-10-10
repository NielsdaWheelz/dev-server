#!/usr/bin/env bash

# Tailscale Serve belongs to the host. each operation owns one exact handler.
gateway_ingress_observe() {
  local port="$1" backend="$2" path="$3" status serve
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ && "$backend" =~ ^[1-9][0-9]{0,4}$ &&
    ( "$path" == /v1 || "$path" == /v1/notifications || "$path" == / ) ]] || return 1

  if declare -F packages_macos_tailscale_cli >/dev/null; then
    gateway_ingress_cli="$(packages_macos_tailscale_cli 2>/dev/null || true)"
  else
    gateway_ingress_cli="$(dev_server_tailscale_cli 2>/dev/null || true)"
  fi
  gateway_ingress_state=''
  if [[ -z "$gateway_ingress_cli" ]]; then
    gateway_ingress_state=missing
    return 0
  fi
  status="$(TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" status --json 2>/dev/null)" || return 1
  ((${#status} <= 65536)) || return 1
  gateway_ingress_hostname="$(printf '%s' "$status" | python3 -c '
import json, re, sys
value = json.load(sys.stdin)
dns = value.get("Self", {}).get("DNSName") if isinstance(value, dict) else None
if value.get("BackendState") != "Running" or not isinstance(dns, str) or not re.fullmatch(r"[a-z0-9][a-z0-9.-]*[a-z0-9]\.", dns):
    raise SystemExit(1)
print(dns[:-1])
' 2>/dev/null || true)"
  if [[ -z "$gateway_ingress_hostname" ]]; then
    gateway_ingress_state=signed-out
    return 0
  fi
  serve="$(TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" serve status --json 2>/dev/null)" || return 1
  ((${#serve} <= 65536)) || return 1
  gateway_ingress_state="$(printf '%s' "$serve" | python3 -c '
import json, sys

def unique(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("duplicate serve key")
        out[key] = value
    return out

value = json.load(sys.stdin, object_pairs_hook=unique)
if not isinstance(value, dict):
    raise SystemExit(1)
tcp, web, funnel = (value.get(name) or {} for name in ("TCP", "Web", "AllowFunnel"))
if not all(isinstance(item, dict) for item in (tcp, web, funnel)):
    raise SystemExit(1)
host, port, backend, path = sys.argv[1:]
origin = host + ":" + port
if funnel.get(origin) is True:
    print("public")
elif tcp.get(port) not in (None, {"HTTPS": True}):
    print("foreign")
else:
    entry = web.get(origin) or {}
    if not isinstance(entry, dict) or not isinstance(entry.get("Handlers", {}), dict):
        raise SystemExit(1)
    handler = entry.get("Handlers", {}).get(path)
    if handler is None:
        print("empty")
    elif handler == {"Proxy": "http://127.0.0.1:" + backend + path} and tcp.get(port) == {"HTTPS": True}:
        print("desired")
    else:
        print("foreign")
' "$gateway_ingress_hostname" "$port" "$backend" "$path")" || return 1
}

gateway_ingress_preflight() {
  local port="$1" backend="$2" path="$3" owner="$4"
  gateway_ingress_observe "$port" "$backend" "$path" ||
    die "could not inspect $owner private Serve boundary"
  case "$gateway_ingress_state" in
  desired | empty) return 0 ;;
  missing) render_result ACTION "$owner.ingress" 'install and sign in to Tailscale'; return 2 ;;
  signed-out) render_result ACTION "$owner.ingress" 'sign in to Tailscale'; return 2 ;;
  foreign) render_result ACTION "$owner.ingress" "resolve the foreign $path handler or HTTPS configuration on port $port"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $owner HTTPS $port" ;;
  *) die "invalid $owner Serve state" ;;
  esac
}

gateway_ingress_apply() {
  local port="$1" backend="$2" path="$3" owner="$4"
  gateway_ingress_observe "$port" "$backend" "$path" ||
    die "could not inspect $owner private Serve boundary"
  case "$gateway_ingress_state" in
  desired) return 0 ;;
  empty) ;;
  missing | signed-out | foreign) gateway_ingress_preflight "$port" "$backend" "$path" "$owner"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $owner HTTPS $port" ;;
  *) die "invalid $owner Serve state" ;;
  esac
  TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" serve --bg --yes "--https=$port" "--set-path=$path" \
    "http://127.0.0.1:$backend$path" >/dev/null || die "could not install $owner Serve handler"
  gateway_ingress_observe "$port" "$backend" "$path" ||
    die "could not verify $owner Serve handler"
  [[ "$gateway_ingress_state" == desired ]] || die "$owner Serve handler differs after apply"
  render_result CHANGED "$owner.ingress" "private HTTPS $port $path mapping installed"
}

gateway_ingress_remove() {
  local port="$1" backend="$2" path="$3" owner="$4"
  gateway_ingress_observe "$port" "$backend" "$path" ||
    die "could not inspect $owner private Serve boundary"
  case "$gateway_ingress_state" in
  empty) return 0 ;;
  missing) render_result ACTION "$owner.ingress" 'install and sign in to Tailscale to inspect the owned handler'; return 2 ;;
  signed-out) render_result ACTION "$owner.ingress" 'sign in to Tailscale to inspect the owned handler'; return 2 ;;
  desired) ;;
  foreign) render_result ACTION "$owner.ingress" "resolve the foreign $path handler or HTTPS configuration on port $port"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $owner HTTPS $port" ;;
  *) die "invalid $owner Serve state" ;;
  esac
  TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" serve "--https=$port" "--set-path=$path" off >/dev/null ||
    die "could not remove $owner Serve handler"
  gateway_ingress_observe "$port" "$backend" "$path" ||
    die "could not verify removal of $owner Serve handler"
  [[ "$gateway_ingress_state" == empty ]] || die "$owner Serve handler persists after removal"
  render_result CHANGED "$owner.ingress" "private HTTPS $port $path mapping removed"
}

skidbladnir_ingress_preflight() { gateway_ingress_preflight 8443 "${dev_server_gateway_port:-7341}" /v1 skidbladnir; }
skidbladnir_ingress_apply() { gateway_ingress_apply 8443 "${dev_server_gateway_port:-7341}" /v1 skidbladnir; }
skidbladnir_ingress_remove() { gateway_ingress_remove 8443 "${dev_server_gateway_port:-7341}" /v1 skidbladnir; }

skidbladnir_notifications_ingress_preflight() {
  gateway_ingress_preflight 8443 7342 /v1/notifications skidbladnir || return $?
  gateway_ingress_preflight 8444 2586 / skidbladnir
}
skidbladnir_notifications_ingress_apply() {
  gateway_ingress_apply 8443 7342 /v1/notifications skidbladnir || return $?
  gateway_ingress_apply 8444 2586 / skidbladnir
}
skidbladnir_notifications_ingress_remove() {
  gateway_ingress_remove 8443 7342 /v1/notifications skidbladnir || return $?
  gateway_ingress_remove 8444 2586 / skidbladnir
}
