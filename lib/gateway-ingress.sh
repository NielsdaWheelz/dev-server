#!/usr/bin/env bash

# Tailscale Serve belongs to the host. Each gateway owns only /v1 on its own
# HTTPS port; other handlers and other ports are outside this installer's scope.
gateway_ingress_observe() {
  local product="$1" port="$2" backend="$3" status serve

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
host, port, backend = sys.argv[1:]
origin = host + ":" + port
if funnel.get(origin) is True:
    print("public")
elif tcp.get(port) not in (None, {"HTTPS": True}):
    print("foreign")
else:
    entry = web.get(origin) or {}
    if not isinstance(entry, dict) or not isinstance(entry.get("Handlers", {}), dict):
        raise SystemExit(1)
    handler = entry.get("Handlers", {}).get("/v1")
    if handler is None:
        print("empty")
    elif handler == {"Proxy": "http://127.0.0.1:" + backend + "/v1"} and tcp.get(port) == {"HTTPS": True}:
        print("desired")
    else:
        print("foreign")
' "$gateway_ingress_hostname" "$port" "$backend")" || return 1
}

gateway_ingress_preflight() {
  local product="$1" port="$2" backend="$3"
  gateway_ingress_observe "$product" "$port" "$backend" ||
    die "could not inspect $product private Serve boundary"
  case "$gateway_ingress_state" in
  desired | empty) return 0 ;;
  missing) render_result ACTION "$product.ingress" 'install and sign in to Tailscale'; return 2 ;;
  signed-out) render_result ACTION "$product.ingress" 'sign in to Tailscale'; return 2 ;;
  foreign) render_result ACTION "$product.ingress" "resolve the foreign /v1 handler or HTTPS configuration on port $port"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $product HTTPS $port" ;;
  *) die "invalid $product Serve state" ;;
  esac
}

gateway_ingress_apply() {
  local product="$1" port="$2" backend="$3"
  gateway_ingress_observe "$product" "$port" "$backend" ||
    die "could not inspect $product private Serve boundary"
  case "$gateway_ingress_state" in
  desired) return 0 ;;
  empty) ;;
  missing | signed-out | foreign) gateway_ingress_preflight "$product" "$port" "$backend"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $product HTTPS $port" ;;
  *) die "invalid $product Serve state" ;;
  esac
  TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" serve --bg --yes "--https=$port" --set-path=/v1 \
    "http://127.0.0.1:$backend/v1" >/dev/null || die "could not install $product Serve handler"
  gateway_ingress_observe "$product" "$port" "$backend" ||
    die "could not verify $product Serve handler"
  [[ "$gateway_ingress_state" == desired ]] || die "$product Serve handler differs after apply"
  render_result CHANGED "$product.ingress" "private HTTPS $port /v1 mapping installed"
}

gateway_ingress_remove() {
  local product="$1" port="$2" backend="$3"
  gateway_ingress_observe "$product" "$port" "$backend" ||
    die "could not inspect $product private Serve boundary"
  case "$gateway_ingress_state" in
  empty) return 0 ;;
  missing) render_result ACTION "$product.ingress" 'install and sign in to Tailscale to inspect the owned handler'; return 2 ;;
  signed-out) render_result ACTION "$product.ingress" 'sign in to Tailscale to inspect the owned handler'; return 2 ;;
  desired) ;;
  foreign) render_result ACTION "$product.ingress" "resolve the foreign /v1 handler or HTTPS configuration on port $port"; return 2 ;;
  public) die "public Tailscale exposure is enabled on $product HTTPS $port" ;;
  *) die "invalid $product Serve state" ;;
  esac
  TAILSCALE_BE_CLI=1 "$gateway_ingress_cli" serve "--https=$port" --set-path=/v1 off >/dev/null ||
    die "could not remove $product Serve handler"
  gateway_ingress_observe "$product" "$port" "$backend" ||
    die "could not verify removal of $product Serve handler"
  [[ "$gateway_ingress_state" == empty ]] || die "$product Serve handler persists after removal"
  render_result CHANGED "$product.ingress" "private HTTPS $port /v1 mapping removed"
}

skidbladnir_ingress_preflight() { gateway_ingress_preflight skidbladnir 8443 "${dev_server_gateway_port:-7341}"; }
skidbladnir_ingress_apply() { gateway_ingress_apply skidbladnir 8443 "${dev_server_gateway_port:-7341}"; }
skidbladnir_ingress_remove() { gateway_ingress_remove skidbladnir 8443 "${dev_server_gateway_port:-7341}"; }
herdr_mobile_ingress_preflight() { gateway_ingress_preflight herdr-mobile 8444 "${dev_server_mobile_gateway_port:-7342}"; }
herdr_mobile_ingress_apply() { gateway_ingress_apply herdr-mobile 8444 "${dev_server_mobile_gateway_port:-7342}"; }
herdr_mobile_ingress_remove() { gateway_ingress_remove herdr-mobile 8444 "${dev_server_mobile_gateway_port:-7342}"; }
