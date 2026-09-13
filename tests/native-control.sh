#!/usr/bin/env bash
# shellcheck disable=SC2034 # Shared-library configuration is consumed by sourced functions.
# Hermetic installer boundary: no download, provider, service, or tmux invocation.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
# shellcheck source=lib/common.sh
source "$repo/lib/common.sh"
# shellcheck source=lib/skidbladnir.sh
source "$repo/lib/skidbladnir.sh"
dev_server_home_dir="$fixture/home"
mkdir -p "$dev_server_home_dir"
for platform in macos arch devbox; do
  output="$fixture/$platform.json"
  skidbladnir_render_host_config "$platform" "$(skidbladnir_host_config_source "$platform")" "$output"
  python3 - "$output" "$platform" "$dev_server_home_dir" <<'PY'
import json, sys
value=json.load(open(sys.argv[1]))
for profile in value['profiles']:
    if profile['provider'] == 'Codex':
        endpoint=profile.get('nativeEndpoint')
        expected=(f"unix:///run/codex-shared-{profile['key']}/app-server.sock" if sys.argv[2]=='devbox' else f"unix://{sys.argv[3]}/.local/run/codex-shared/{profile['key']}/app-server.sock")
        assert endpoint == expected, 'generated host config did not inherit the authoritative shared endpoint'
    else:
        assert 'nativeEndpoint' not in profile
PY
done
printf 'PASS native control endpoint projection\n'
# Fake only dependency tools; execute the actual installer and wrapper publishing.
mkdir -p "$fixture/assets/skidbladnir"
dev_server_assets_root="$fixture/assets"
printf '%s\n' '{"repository":"https://github.com/NielsdaWheelz/llm-calling.git","revision":"1111111111111111111111111111111111111111"}' >"$fixture/assets/skidbladnir/native-control.json"
export NATIVE_TEST_CALLS="$fixture/calls" NATIVE_TEST_UV="$fixture/uv" NATIVE_TEST_FAIL=0
cat >"$fixture/uv" <<'UV'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == --version ]]; then printf 'uv 0.11.28\n'; exit; fi
printf '%s\n' "$*" >>"$NATIVE_TEST_CALLS"
[[ "$*" == "sync --project "*" --python 3.12.13 --frozen --extra claude-sdk --no-dev" ]]
[[ "$NATIVE_TEST_FAIL" != 1 ]] || exit 1
mkdir -p "$3/.venv/bin"
printf '#!/bin/sh\nexit 0\n' >"$3/.venv/bin/provider-runtime-control"
chmod 0755 "$3/.venv/bin/provider-runtime-control"
UV
chmod 0755 "$fixture/uv"
python3() {
  if [[ "${1:-} ${2:-}" == '-m venv' ]]; then
    mkdir -p "$3/bin"
    cat >"$3/bin/python" <<'PIP'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '-m pip --disable-pip-version-check install --quiet --upgrade uv==0.11.28' ]]
printf 'bootstrap uv==0.11.28\n' >>"$NATIVE_TEST_CALLS"
cp "$NATIVE_TEST_UV" "$(dirname "$0")/uv"
PIP
    chmod 0755 "$3/bin/python"
  else
    command python3 "$@"
  fi
}
git() {
  case "$1" in
  clone) mkdir -p "$5/.git" ;;
  -C)
    case "$3" in
    fetch) : ;;
    checkout) printf '%s\n' "$6" >"$2/.git/head" ;;
    rev-parse) cat "$2/.git/head" ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}
skidbladnir_install_native_control
skidbladnir_install_native_control
[[ "$(wc -l <"$fixture/calls" | tr -d ' ')" == 2 ]]
old_wrapper="$(cat "$dev_server_home_dir/.local/bin/provider-runtime-control")"
[[ "$old_wrapper" == *'/1111111111111111111111111111111111111111/.venv/bin/provider-runtime-control'* ]]
printf '%s\n' '{"repository":"https://github.com/NielsdaWheelz/llm-calling.git","revision":"2222222222222222222222222222222222222222"}' >"$fixture/assets/skidbladnir/native-control.json"
export NATIVE_TEST_FAIL=1
if skidbladnir_install_native_control >/dev/null 2>&1; then
  printf 'FAIL failed frozen sync admitted a native helper\n' >&2
  exit 1
fi
[[ "$(cat "$dev_server_home_dir/.local/bin/provider-runtime-control")" == "$old_wrapper" ]]
printf 'PASS frozen native installer, repeat apply, failed upgrade preserves helper\n'
