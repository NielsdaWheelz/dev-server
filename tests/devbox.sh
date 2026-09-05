#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-devbox.XXXXXX")"
tests_run=0

cleanup() {
  case "$fixture" in
  "${TMPDIR:-/tmp}"/dev-server-devbox.*) rm -rf -- "$fixture" ;;
  *) return 1 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'FAIL  devbox: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local path="$1"
  local text="$2"
  local label="$3"
  grep -Fq -- "$text" "$path" || fail "$label: <$text> not found in $path"
}

assert_not_contains() {
  local path="$1"
  local text="$2"
  local label="$3"
  ! grep -Fq -- "$text" "$path" || fail "$label: <$text> found in $path"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected <$expected>, got <$actual>"
}

file_inode() {
  stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

write_executable() {
  local path="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' "$@" >"$path"
  chmod 0755 "$path"
}

extract_rootless_docker_repair() {
  python3 - "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
task = text.index("- name: Repair and verify changed rootless Docker setup\n")
marker = "  ansible.builtin.shell: |\n"
start = text.index(marker, task) + len(marker)
end = text.index("\n  args:\n", start)
lines = text[start:end].splitlines()
assert lines and all(line.startswith("    ") or not line for line in lines)
program = "\n".join(line[4:] if line else line for line in lines) + "\n"
sys.stdout.write(program.replace("{{ base_user_uid.stdout }}", "1000"))
PY
}

make_fake_commands() {
  local bin="$1"

  mkdir -p "$bin"
  cat >"$bin/hcloud" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --context ]]
shift 2
printf 'hcloud' >>"$FAKE_CALLS"
printf ' %q' "$@" >>"$FAKE_CALLS"
printf '\n' >>"$FAKE_CALLS"

case "${1:-} ${2:-}" in
  'server list')
    if [[ -f "$FAKE_STATE/server" ]]; then
      printf '%s\n' '[{"id":101,"name":"dev-server","status":"running","public_net":{"ipv4":{"ip":"203.0.113.10"}}}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  'server-type describe'|'location describe'|'image describe')
    ;;
  'server create')
    user_data=''
    while (($# > 0)); do
      if [[ "$1" == --user-data-from-file ]]; then
        user_data="$2"
        break
      fi
      shift
    done
    [[ -n "$user_data" ]]
    cp "$user_data" "$FAKE_STATE/rendered-cloud-init.yaml"
    : >"$FAKE_STATE/server"
    : >"$FAKE_STATE/attached"
    ;;
  'firewall list')
    if [[ -f "$FAKE_STATE/firewall" ]]; then
      printf '%s\n' '[{"id":201,"name":"dev-server-private"}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  'firewall create')
    : >"$FAKE_STATE/firewall"
    printf '[]\n' >"$FAKE_STATE/rules.json"
    ;;
  'firewall describe')
    FAKE_RULES="$FAKE_STATE/rules.json" python3 - "$FAKE_STATE/attached" <<'PY'
import json
import pathlib
import sys

rules = json.loads(pathlib.Path(__import__('os').environ['FAKE_RULES']).read_text())
applied = ([{"type": "server", "server": {"id": 101}}]
           if pathlib.Path(sys.argv[1]).exists() else [])
print(json.dumps({"id": 201, "name": "dev-server-private",
                  "rules": rules, "applied_to": applied}))
PY
    ;;
  'firewall replace-rules')
    count_file="$FAKE_STATE/rule-count"
    count=0
    [[ ! -f "$count_file" ]] || count="$(cat "$count_file")"
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    python3 -c 'import json, pathlib, sys; data=json.load(sys.stdin); pathlib.Path(sys.argv[1]).write_text(json.dumps(data))' "$FAKE_STATE/rules.json"
    cp "$FAKE_STATE/rules.json" "$FAKE_STATE/rules-$count.json"
    ;;
  'firewall apply-to-resource')
    : >"$FAKE_STATE/attached"
    ;;
  *)
    printf 'unexpected hcloud call: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF

  cat >"$bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tailscale %s\n' "$*" >>"$FAKE_CALLS"
[[ "$*" == 'status --json' ]]
if [[ -f "$FAKE_STATE/server" ]]; then
  if [[ "$FAKE_SCENARIO" == offline ]]; then
    printf '%s\n' '{"BackendState":"Running","Peer":{"node":{"HostName":"dev-server","DNSName":"dev-server.example.ts.net.","Online":false}}}'
  else
    printf '%s\n' '{"BackendState":"Running","Peer":{"node":{"HostName":"dev-server","DNSName":"dev-server.example.ts.net.","Online":true}}}'
  fi
else
  printf '%s\n' '{"BackendState":"Running","Peer":{}}'
fi
EOF

  cat >"$bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh-keygen' >>"$FAKE_CALLS"
printf ' %q' "$@" >>"$FAKE_CALLS"
printf '\n' >>"$FAKE_CALLS"
case "${1:-}" in
  -y)
    case "${3:-}" in
      *dev-server-deploy) printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDEPLOY000000000000000000000000000000 dev-server-deploy' ;;
      *) printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATOR000000000000000000000000000' ;;
    esac
    ;;
  -F)
    [[ "${3:-}" == -f && -f "${4:-}" ]]
    awk -v host="$2" '
      $1 == host {
        printf "# Host %s found\n", host
        print
        found = 1
      }
      END { exit(found ? 0 : 1) }
    ' "$4"
    ;;
  -R) ;;
  *) exit 64 ;;
esac
EOF

  cat >"$bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh' >>"$FAKE_CALLS"
printf ' %q' "$@" >>"$FAKE_CALLS"
printf '\n' >>"$FAKE_CALLS"
if [[ " ${*} " == *' -G '* ]]; then
  printf '%s\n' 'hostname dev-server.example.ts.net'
  exit 0
fi
known_hosts_file=''
global_known_hosts_file=''
hash_known_hosts=''
host_key_algorithms=''
strict_host_key_checking=''
update_host_keys=''
remote_target=''
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  argument="${arguments[$index]}"
  if [[ "$argument" == -o ]]; then
    index=$((index + 1))
    option="${arguments[$index]:-}"
    case "$option" in
      GlobalKnownHostsFile=*) global_known_hosts_file="${option#*=}" ;;
      HashKnownHosts=*) hash_known_hosts="${option#*=}" ;;
      HostKeyAlgorithms=*) host_key_algorithms="${option#*=}" ;;
      StrictHostKeyChecking=*) strict_host_key_checking="${option#*=}" ;;
      UpdateHostKeys=*) update_host_keys="${option#*=}" ;;
      UserKnownHostsFile=*) known_hosts_file="${option#*=}" ;;
    esac
  elif [[ "$argument" == *@* ]]; then
    remote_target="$argument"
  fi
done
host_key='dev-server ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f'
if [[ "$remote_target" == *@203.0.113.10 &&
  "$strict_host_key_checking" == accept-new ]]; then
  [[ "$global_known_hosts_file" == /dev/null &&
    "$hash_known_hosts" == no &&
    "$host_key_algorithms" == ssh-ed25519 &&
    "$update_host_keys" == no &&
    -n "$known_hosts_file" ]] || exit 64
  if [[ "$FAKE_SCENARIO" != hostkey-no-write ]]; then
    printf '%s\n' "$host_key" >>"$known_hosts_file"
  fi
fi
if [[ -n "$global_known_hosts_file" && "$strict_host_key_checking" == yes ]]; then
  grep -Fqx "$host_key" "$known_hosts_file" || {
    printf '%s\n' 'Host key verification failed.' >&2
    exit 255
  }
  if [[ "$FAKE_SCENARIO" == hostkey-mismatch &&
    "$remote_target" == *@dev-server.example.ts.net ]]; then
    printf '%s\n' 'Host key verification failed.' >&2
    exit 255
  fi
fi
if [[ "$*" == *'cloud-init status --wait'* && "$FAKE_SCENARIO" == new-failure ]]; then
  exit 42
fi
if [[ "$*" == *'tailscale debug prefs'* ]]; then
  if [[ "$FAKE_SCENARIO" == tailscale-ssh ]]; then
    printf '%s\n' '{"RunSSH":true}'
  else
    printf '%s\n' '{"RunSSH":false}'
  fi
fi
if [[ "$*" == *id_ed25519_github.pub* ]]; then
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGITHUB00000000000000000000000000000'
fi
EOF

  cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl %s\n' "$*" >>"$FAKE_CALLS"
printf '%s\n' '198.51.100.7'
EOF

  cat >"$bin/uvx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'uvx %s\n' "$*" >>"$FAKE_CALLS"
if [[ "$FAKE_SCENARIO" == ansible-failure && "$*" != *' --syntax-check '* ]]; then
  printf '%s\n' 'fatal: injected Ansible failure'
  exit 42
fi
if [[ "$FAKE_SCENARIO" == skid-stale && "$*" != *' --syntax-check '* ]]; then
  printf '%s\n' 'DEV_SERVER_SKID_ACTION_CLEAR_STALE_SERVE'
fi
printf '%s\n' 'PLAY RECAP'
printf '%s\n' 'devbox : ok=24 changed=0 unreachable=0 failed=0 skipped=2 rescued=0 ignored=0'
EOF

  cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"$FAKE_CALLS"
case "${1:-}" in
  auth) ;;
  api) printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGITHUB00000000000000000000000000000' ;;
  *) exit 64 ;;
esac
EOF

  write_executable "$bin/sleep" ':'
  chmod 0755 "$bin"/*
}

make_case() {
  local name="$1"
  local scenario="$2"
  local case_dir="$fixture/$name"

  mkdir -p \
    "$case_dir/root/lib" \
    "$case_dir/root/secrets" \
    "$case_dir/home/.ssh" \
    "$case_dir/state" \
    "$case_dir/bin"
  cp "$repo_dir/devbox" "$case_dir/root/devbox"
  cp "$repo_dir/cloud-init-devbox.template.yaml" "$case_dir/root/"
  cp "$repo_dir/ansible.cfg" "$case_dir/root/"
  cp "$repo_dir/lib/common.sh" "$repo_dir/lib/remote-devbox.sh" \
    "$repo_dir/lib/dotfiles.sh" "$repo_dir/lib/ai-tools.sh" \
    "$repo_dir/lib/skidbladnir.sh" "$case_dir/root/lib/"
  cp -R "$repo_dir/assets" "$case_dir/root/assets"
  cp -R "$repo_dir/ansible" "$case_dir/root/ansible"
  chmod 0755 "$case_dir/root/devbox"
  printf 'operator-private\n' >"$case_dir/home/.ssh/id_ed25519"
  printf 'deploy-private\n' >"$case_dir/home/.ssh/dev-server-deploy"
  chmod 0600 "$case_dir/home/.ssh/id_ed25519" "$case_dir/home/.ssh/dev-server-deploy"
  printf 'tskey-auth-test-secret\n' >"$case_dir/root/secrets/tailscale-auth-key"
  chmod 0600 "$case_dir/root/secrets/tailscale-auth-key"
  : >"$case_dir/calls"
  make_fake_commands "$case_dir/bin"

  if [[ "$scenario" == existing ]]; then
    : >"$case_dir/state/server"
    : >"$case_dir/state/firewall"
    : >"$case_dir/state/attached"
    cat >"$case_dir/state/rules.json" <<'JSON'
[{"description":"Tailscale direct WireGuard","direction":"in","protocol":"udp","port":"41641","source_ips":["0.0.0.0/0","::/0"]}]
JSON
  fi
  printf '%s\n' "$case_dir"
}

run_apply() {
  local case_dir="$1"
  local scenario="$2"
  local output="$3"

  HOME="$case_dir/home" \
    PATH="$case_dir/bin:/usr/bin:/bin" \
    FAKE_CALLS="$case_dir/calls" \
    FAKE_SCENARIO="$scenario" \
    FAKE_STATE="$case_dir/state" \
    "$case_dir/root/devbox" apply >"$output" 2>&1
}

test_cli_contract() {
  local case_dir output rc
  case_dir="$(make_case cli existing)"
  output="$case_dir/output"

  set +e
  HOME="$case_dir/home" PATH="$case_dir/bin:/usr/bin:/bin" \
    "$case_dir/root/devbox" >"$output" 2>&1
  rc=$?
  set -e
  assert_eq 64 "$rc" 'omitted operation exit'
  assert_contains "$output" 'Usage: ./devbox apply' 'omitted operation help'
  assert_contains "$output" '       ./devbox help' 'omitted operation help surface'

  HOME="$case_dir/home" PATH="$case_dir/bin:/usr/bin:/bin" \
    "$case_dir/root/devbox" help >"$output"
  assert_contains "$output" 'Usage: ./devbox apply' 'help operation'
  assert_contains "$output" '       ./devbox help' 'help operation surface'

  set +e
  HOME="$case_dir/home" PATH="$case_dir/bin:/usr/bin:/bin" \
    "$case_dir/root/devbox" legacy >"$output" 2>&1
  rc=$?
  set -e
  assert_eq 64 "$rc" 'removed operation exit'

  rm "$case_dir/home/.ssh/dev-server-deploy"
  ln -s id_ed25519 "$case_dir/home/.ssh/dev-server-deploy"
  set +e
  run_apply "$case_dir" existing "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'symlinked deployment identity exit'
  assert_contains "$output" 'deployment identity is not a valid private key' \
    'symlinked deployment identity rejection'
  [[ ! -s "$case_dir/calls" ]] ||
    fail 'symlinked deployment identity reached an external system'
  tests_run=$((tests_run + 1))
}

test_existing_server_never_bootstraps() {
  local case_dir output inode calls_before
  case_dir="$(make_case existing existing)"
  output="$case_dir/output"

  run_apply "$case_dir" existing "$output" || {
    sed -n '1,240p' "$output" >&2
    fail 'existing server apply failed'
  }
  assert_not_contains "$case_dir/calls" 'server create' 'existing server creation'
  assert_not_contains "$case_dir/calls" 'replace-rules' 'existing firewall rewrite'
  assert_not_contains "$case_dir/calls" 'curl ' 'existing public-IP lookup'
  assert_not_contains "$case_dir/calls" 'ssh-keygen -R' 'existing host-key reset'
  assert_not_contains "$case_dir/calls" '203.0.113.10' 'existing public SSH'
  assert_contains "$case_dir/calls" 'dev-server.example.ts.net' 'exact tailnet SSH'
  assert_contains "$case_dir/calls" \
    "-i $case_dir/home/.ssh/id_ed25519 niels@dev-server.example.ts.net" \
    'operator SSH key preflight'
  assert_contains "$case_dir/calls" \
    "-i $case_dir/home/.ssh/dev-server-deploy dev-server-deploy@dev-server.example.ts.net" \
    'deployment SSH key preflight'
  assert_contains "$case_dir/home/.ssh/config.d/dev-server" \
    'User niels' 'operator SSH principal'
  assert_contains "$case_dir/home/.ssh/config.d/dev-server" \
    'Host dev-server-deploy' 'deployment SSH alias'
  assert_contains "$case_dir/home/.ssh/config.d/dev-server" \
    'User dev-server-deploy' 'deployment SSH principal'
  assert_contains "$case_dir/home/.ssh/config.d/dev-server" \
    'StrictHostKeyChecking yes' 'strict tailnet host key'
  [[ ! -e "$case_dir/home/.ssh/config" ]] ||
    fail 'apply mutated the operator top-level SSH config'
  ! find "$case_dir/home/.ssh/config.d" -name '.dev-server.candidate.*' | grep -q . ||
    fail 'apply left an SSH include staging file'

  inode="$(file_inode "$case_dir/home/.ssh/config.d/dev-server")"
  : >"$case_dir/calls"
  run_apply "$case_dir" existing "$output" || {
    sed -n '1,240p' "$output" >&2
    fail 'second existing server apply failed'
  }
  assert_eq "$inode" \
    "$(file_inode "$case_dir/home/.ssh/config.d/dev-server")" \
    'second-apply SSH include inode'
  assert_contains "$output" 'UP TO DATE  devbox' 'second-apply summary'
  assert_not_contains "$output" 'PLAY RECAP' 'successful Ansible chatter'
  calls_before="$(grep -Ec 'server create|replace-rules|apply-to-resource|ssh-keygen -R|curl ' "$case_dir/calls" || true)"
  assert_eq 0 "$calls_before" 'second-apply cloud mutation count'
  tests_run=$((tests_run + 1))
}

test_ansible_failure_has_one_terminal_summary() {
  local case_dir output rc
  case_dir="$(make_case ansible-failure existing)"
  output="$case_dir/output"

  set +e
  run_apply "$case_dir" ansible-failure "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'Ansible failure exit'
  assert_contains "$output" 'fatal: injected Ansible failure' \
    'bounded Ansible failure diagnostic'
  assert_contains "$output" 'ERROR  Ubuntu state: Ansible apply failed with exit 42' \
    'Ansible failure result'
  assert_contains "$output" 'ERROR  devbox: 1 error(s)' \
    'Ansible failure terminal summary'
  assert_eq 1 "$(grep -c '^ERROR  devbox:' "$output")" \
    'Ansible failure summary count'
  tests_run=$((tests_run + 1))
}

test_skid_action_is_exact_and_visible() {
  local case_dir output rc
  case_dir="$(make_case skid-action existing)"
  output="$case_dir/output"

  set +e
  run_apply "$case_dir" skid-stale "$output"
  rc=$?
  set -e
  assert_eq 2 "$rc" 'Skíðblaðnir stale Serve action exit'
  assert_contains "$output" \
    "ACTION  tailscale.serve: remove the stale HTTPS 8443 mapping with 'tailscale serve --https=8443 off', then rerun apply" \
    'Skíðblaðnir stale Serve recovery command'
  assert_eq 1 "$(grep -c '^ACTION  tailscale\.serve:' "$output")" \
    'Skíðblaðnir stale Serve action count'
  assert_eq 1 "$(grep -c '^ACTION  devbox:' "$output")" \
    'Skíðblaðnir action summary count'
  assert_not_contains "$output" 'PLAY RECAP' 'successful Ansible chatter'
  tests_run=$((tests_run + 1))
}

test_existing_tailscale_ssh_requires_manual_cutover() {
  local case_dir output rc
  case_dir="$(make_case tailscale-ssh existing)"
  output="$case_dir/output"

  set +e
  run_apply "$case_dir" tailscale-ssh "$output"
  rc=$?
  set -e
  assert_eq 2 "$rc" 'Tailscale SSH cutover action exit'
  assert_contains "$output" 'sudo tailscale set --ssh=false' \
    'Tailscale SSH cutover command'
  assert_not_contains "$case_dir/calls" 'replace-rules' \
    'Tailscale SSH cutover firewall mutation'
  assert_eq 1 "$(grep -c '^uvx .* --syntax-check ' "$case_dir/calls")" \
    'Tailscale SSH cutover syntax preflight count'
  assert_eq 1 "$(grep -c '^uvx ' "$case_dir/calls")" \
    'Tailscale SSH cutover apply suppression'
  tests_run=$((tests_run + 1))
}

test_existing_drift_only_closes_ingress() {
  local case_dir output
  case_dir="$(make_case existing-drift existing)"
  output="$case_dir/output"
  cat >"$case_dir/state/rules.json" <<'JSON'
[{"description":"stale public SSH","direction":"in","protocol":"tcp","port":"22","source_ips":["0.0.0.0/0"]}]
JSON

  run_apply "$case_dir" existing "$output" || {
    sed -n '1,240p' "$output" >&2
    fail 'existing drift repair failed'
  }
  assert_eq 1 "$(cat "$case_dir/state/rule-count")" \
    'existing drift firewall rewrite count'
  python3 - "$case_dir/state/rules-1.json" <<'PY' ||
import json
import pathlib
import sys

rules = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert not any(rule.get("port") in ("22", "80", "443") for rule in rules)
PY
    fail 'existing drift repair installed public ingress'
  assert_not_contains "$case_dir/calls" 'server create' 'existing drift server creation'
  assert_not_contains "$case_dir/calls" 'curl ' 'existing drift public-IP lookup'
  assert_not_contains "$case_dir/calls" 'ssh-keygen -R' 'existing drift host-key reset'
  tests_run=$((tests_run + 1))
}

test_existing_offline_peer_closes_interrupted_bootstrap() {
  local case_dir output rc
  case_dir="$(make_case existing-offline existing)"
  output="$case_dir/output"
  cat >"$case_dir/state/rules.json" <<'JSON'
[{"description":"interrupted bootstrap SSH","direction":"in","protocol":"tcp","port":"22","source_ips":["198.51.100.7/32"]}]
JSON

  set +e
  run_apply "$case_dir" offline "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'offline tailnet peer exit'
  assert_contains "$output" \
    'existing Hetzner devbox has no unique online tailnet node' \
    'offline tailnet peer rejection'
  assert_not_contains "$case_dir/calls" 'ssh ' 'offline peer SSH attempt'
  assert_contains "$case_dir/calls" 'replace-rules' \
    'offline peer fail-safe firewall repair'
  assert_eq 1 "$(cat "$case_dir/state/rule-count")" \
    'offline interrupted-bootstrap closure count'
  if grep -Eq '"port"[[:space:]]*:[[:space:]]*"?(22|80|443)"?' \
    "$case_dir/state/rules.json"; then
    fail 'offline recovery left public bootstrap ingress'
  fi
  tests_run=$((tests_run + 1))
}

test_new_server_closes_both_boundaries() {
  local case_dir output
  case_dir="$(make_case new-success new-success)"
  output="$case_dir/output"

  run_apply "$case_dir" new-success "$output" || {
    sed -n '1,240p' "$output" >&2
    fail 'new server apply failed'
  }
  assert_contains "$case_dir/calls" 'firewall create' 'new firewall create'
  assert_contains "$case_dir/calls" 'server create' 'new server create'
  assert_eq 2 "$(cat "$case_dir/state/rule-count")" 'bootstrap and steady ruleset count'
  python3 - "$case_dir/state/rules-1.json" "$case_dir/state/rules-2.json" <<'PY' ||
import json
import pathlib
import sys

first = json.loads(pathlib.Path(sys.argv[1]).read_text())
last = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert any(rule.get("protocol") == "tcp" and rule.get("port") == "22"
           and rule.get("source_ips") == ["198.51.100.7/32"] for rule in first)
assert not any(rule.get("port") in ("22", "80", "443") for rule in last)
PY
    fail 'new firewall phase rules are not exact'
  assert_contains "$case_dir/calls" 'ufw' 'host bootstrap cleanup'
  assert_contains "$case_dir/calls" 'ssh-keygen -R dev-server' 'new alias host-key reset'
  assert_contains "$case_dir/calls" 'GlobalKnownHostsFile=/dev/null' \
    'new host-key global trust isolation'
  assert_contains "$case_dir/calls" 'HashKnownHosts=no' \
    'new host-key stable alias recording'
  assert_contains "$case_dir/calls" 'HostKeyAlgorithms=ssh-ed25519' \
    'new host-key algorithm boundary'
  assert_contains "$case_dir/calls" 'UpdateHostKeys=no' \
    'new host-key single-record boundary'
  assert_contains "$case_dir/calls" '203.0.113.10' 'public bootstrap transport'
  assert_contains "$case_dir/calls" 'dev-server.example.ts.net' 'tailnet transport'
  assert_contains "$case_dir/calls" 'uvx --from ansible-core==2.19.2' 'pinned Ansible apply'
  assert_contains "$case_dir/calls" 'tailscale status --json' \
    'resolved Tailscale CLI invocation'
  assert_contains "$case_dir/state/rendered-cloud-init.yaml" \
    'name: dev-server-deploy' 'deployment principal rendering'
  assert_contains "$case_dir/state/rendered-cloud-init.yaml" \
    'AAAAC3NzaC1lZDI1NTE5AAAAIDEPLOY' 'deployment public key rendering'
  assert_contains "$case_dir/state/rendered-cloud-init.yaml" \
    'AAAAC3NzaC1lZDI1NTE5AAAAIOPERATOR' 'operator public key rendering'
  assert_not_contains "$case_dir/state/rendered-cloud-init.yaml" '__' 'rendered placeholder'
  assert_eq \
    'dev-server ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4f' \
    "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts")" \
    'promoted verified devbox host key'
  [[ ! -e "$case_dir/root/secrets/devbox-state.env" ]] ||
    fail 'new apply persisted lifecycle state'
  tests_run=$((tests_run + 1))
}

test_new_server_failure_still_closes_ingress() {
  local case_dir known_hosts_inode output rc
  case_dir="$(make_case new-failure new-failure)"
  output="$case_dir/output"
  printf 'preserved-host-key\n' >"$case_dir/home/.ssh/known_hosts"
  printf 'preserved-operator-backup\n' >"$case_dir/home/.ssh/known_hosts.old"
  known_hosts_inode="$(file_inode "$case_dir/home/.ssh/known_hosts")"

  set +e
  run_apply "$case_dir" new-failure "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'injected bootstrap failure exit'
  assert_eq 2 "$(cat "$case_dir/state/rule-count")" 'failure cleanup ruleset count'
  python3 - "$case_dir/state/rules.json" <<'PY' ||
import json
import pathlib
import sys

rules = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert not any(rule.get("port") in ("22", "80", "443") for rule in rules)
PY
    fail 'failure left public cloud ingress'
  assert_contains "$case_dir/calls" 'ufw' 'failure host cleanup'
  assert_contains "$case_dir/calls" '-f ' 'staged known-hosts reset'
  assert_eq 1 "$(grep -c '^uvx .* --syntax-check ' "$case_dir/calls")" \
    'failed bootstrap syntax preflight count'
  assert_eq 1 "$(grep -c '^uvx ' "$case_dir/calls")" \
    'failed bootstrap Ansible apply suppression'
  assert_eq preserved-host-key "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts")" \
    'failed bootstrap known-hosts bytes'
  assert_eq "$known_hosts_inode" \
    "$(file_inode "$case_dir/home/.ssh/known_hosts")" \
    'failed bootstrap known-hosts inode'
  assert_eq preserved-operator-backup \
    "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts.old")" \
    'failed bootstrap operator backup preservation'
  ! find "$case_dir/home/.ssh" -name '.known_hosts.dev-server.*' | grep -q . ||
    fail 'failed bootstrap left a known-hosts candidate'
  tests_run=$((tests_run + 1))
}

test_new_host_key_no_write_preserves_trust() {
  local case_dir known_hosts_inode output rc
  case_dir="$(make_case hostkey-no-write hostkey-no-write)"
  output="$case_dir/output"
  printf 'preserved-host-key\n' >"$case_dir/home/.ssh/known_hosts"
  printf 'preserved-operator-backup\n' >"$case_dir/home/.ssh/known_hosts.old"
  known_hosts_inode="$(file_inode "$case_dir/home/.ssh/known_hosts")"

  set +e
  run_apply "$case_dir" hostkey-no-write "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'missing staged host-key record exit'
  assert_contains "$output" \
    'public bootstrap SSH did not record exactly one valid devbox host key' \
    'missing staged host-key record rejection'
  assert_eq preserved-host-key "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts")" \
    'missing-record known-hosts bytes'
  assert_eq "$known_hosts_inode" \
    "$(file_inode "$case_dir/home/.ssh/known_hosts")" \
    'missing-record known-hosts inode'
  assert_eq preserved-operator-backup \
    "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts.old")" \
    'missing-record operator backup preservation'
  assert_eq 2 "$(cat "$case_dir/state/rule-count")" \
    'missing-record bootstrap and steady ruleset count'
  ! find "$case_dir/home/.ssh" -name '.known_hosts.dev-server.*' | grep -q . ||
    fail 'missing-record failure left a known-hosts candidate'
  assert_eq 1 "$(grep -c '^uvx ' "$case_dir/calls")" \
    'missing-record Ansible apply suppression'
  tests_run=$((tests_run + 1))
}

test_new_host_key_mismatch_preserves_trust() {
  local case_dir known_hosts_inode output rc
  case_dir="$(make_case hostkey-mismatch hostkey-mismatch)"
  output="$case_dir/output"
  printf 'preserved-host-key\n' >"$case_dir/home/.ssh/known_hosts"
  printf 'preserved-operator-backup\n' >"$case_dir/home/.ssh/known_hosts.old"
  known_hosts_inode="$(file_inode "$case_dir/home/.ssh/known_hosts")"

  set +e
  run_apply "$case_dir" hostkey-mismatch "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'cross-transport host-key mismatch exit'
  assert_contains "$output" 'new devbox host key did not match over the tailnet' \
    'cross-transport host-key mismatch rejection'
  assert_eq preserved-host-key "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts")" \
    'mismatch known-hosts bytes'
  assert_eq "$known_hosts_inode" \
    "$(file_inode "$case_dir/home/.ssh/known_hosts")" \
    'mismatch known-hosts inode'
  assert_eq preserved-operator-backup \
    "$(tr -d '\n' <"$case_dir/home/.ssh/known_hosts.old")" \
    'mismatch operator backup preservation'
  assert_eq 2 "$(cat "$case_dir/state/rule-count")" \
    'mismatch bootstrap and steady ruleset count'
  ! find "$case_dir/home/.ssh" -name '.known_hosts.dev-server.*' | grep -q . ||
    fail 'mismatch failure left a known-hosts candidate'
  assert_eq 1 "$(grep -c '^uvx ' "$case_dir/calls")" \
    'mismatch Ansible apply suppression'
  tests_run=$((tests_run + 1))
}

test_known_hosts_symlink_fails_before_external_state() {
  local case_dir output rc referent
  case_dir="$(make_case known-hosts-symlink new-success)"
  output="$case_dir/output"
  referent="$case_dir/known-hosts-referent"
  printf 'preserve\n' >"$referent"
  ln -s "$referent" "$case_dir/home/.ssh/known_hosts"

  set +e
  run_apply "$case_dir" new-success "$output"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'symlinked known-hosts exit'
  assert_contains "$output" 'known-hosts target is not a regular file' \
    'symlinked known-hosts rejection'
  assert_eq preserve "$(tr -d '\n' <"$referent")" \
    'symlinked known-hosts referent preservation'
  [[ ! -s "$case_dir/calls" ]] ||
    fail 'symlinked known-hosts reached an external system'
  tests_run=$((tests_run + 1))
}

test_rootless_docker_repair_lifecycle() {
  local bin case_dir output repair rc unit
  case_dir="$fixture/rootless-docker"
  bin="$case_dir/bin"
  repair="$case_dir/repair"
  mkdir -p "$bin"
  extract_rootless_docker_repair >"$repair"
  chmod 0700 "$repair"
  python3 - "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" <<'PY' ||
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
start = text.index("- name: Repair and verify changed rootless Docker setup\n")
end = text.index("\n- name:", start + 1)
task = text[start:end]
for required in (
        "not rootless_docker_unit.stat.exists or",
        "rootless_docker_context.rc != 0 or",
        "rootless_docker_observed_identity != rootless_docker_active_identity_value",
):
    assert required in task, required
PY
    fail 'fresh or partial Docker setup does not select repair'

  cat >"$bin/fake-command" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name="${0##*/}"
printf '%s %s\n' "$command_name" "$*" >>"$FAKE_CALLS"
case "$command_name" in
  systemctl)
    [[ "$*" == '--user is-active --quiet docker.service' ]] || exit 64
    [[ ! -f "$FAKE_STATE/active" ]] || exit 0
    exit "$FAKE_SERVICE_STATUS"
    ;;
  docker)
    case "$*" in
      '--host unix:///run/user/1000/docker.sock ps -q')
        printf '%s' "${FAKE_CONTAINERS:-}"
        ;;
      '--context=default context inspect rootless')
        [[ -f "$FAKE_STATE/context" ]]
        ;;
      '--host unix:///run/user/1000/docker.sock version')
        [[ -f "$FAKE_STATE/active" ]]
        ;;
      *) exit 64 ;;
    esac
    ;;
  dockerd-rootless-setuptool.sh)
    case "$*" in
      '--force uninstall')
        rm -f -- "$HOME/.config/systemd/user/docker.service" \
          "$FAKE_STATE/active" "$FAKE_STATE/context"
        ;;
      '--force install')
        mkdir -p "$HOME/.config/systemd/user"
        printf 'generated\n' >"$HOME/.config/systemd/user/docker.service"
        : >"$FAKE_STATE/active"
        : >"$FAKE_STATE/context"
        ;;
      *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
esac
EOF
  chmod 0755 "$bin/fake-command"
  ln -s fake-command "$bin/systemctl"
  ln -s fake-command "$bin/docker"
  ln -s fake-command "$bin/dockerd-rootless-setuptool.sh"

  case_dir="$fixture/rootless-partial"
  unit="$case_dir/home/.config/systemd/user/docker.service"
  mkdir -p "${unit%/*}" "$case_dir/state"
  printf 'partial\n' >"$unit"
  output="$(env HOME="$case_dir/home" PATH="$bin:/usr/bin:/bin" \
    FAKE_CALLS="$case_dir/calls" FAKE_STATE="$case_dir/state" \
    FAKE_SERVICE_STATUS=3 bash "$repair")"
  assert_eq DEV_SERVER_DOCKER_REPAIRED "$output" 'partial Docker setup repair'
  assert_eq generated "$(tr -d '\n' <"$unit")" 'partial Docker unit replacement'
  assert_eq 1 "$(grep -c '^dockerd-rootless-setuptool.sh --force uninstall$' "$case_dir/calls")" \
    'partial Docker uninstall count'
  assert_eq 1 "$(grep -c '^dockerd-rootless-setuptool.sh --force install$' "$case_dir/calls")" \
    'partial Docker install count'

  case_dir="$fixture/rootless-first-install"
  mkdir -p "$case_dir/home" "$case_dir/state"
  output="$(env HOME="$case_dir/home" PATH="$bin:/usr/bin:/bin" \
    FAKE_CALLS="$case_dir/calls" FAKE_STATE="$case_dir/state" \
    FAKE_SERVICE_STATUS=4 bash "$repair")"
  assert_eq DEV_SERVER_DOCKER_REPAIRED "$output" 'missing Docker setup install'
  ! grep -q ' --force uninstall$' "$case_dir/calls" ||
    fail 'missing Docker setup was unnecessarily uninstalled'

  case_dir="$fixture/rootless-busy"
  mkdir -p "$case_dir/home" "$case_dir/state"
  output="$(env HOME="$case_dir/home" PATH="$bin:/usr/bin:/bin" \
    FAKE_CALLS="$case_dir/calls" FAKE_STATE="$case_dir/state" \
    FAKE_SERVICE_STATUS=0 FAKE_CONTAINERS=container-id bash "$repair")"
  assert_eq DEV_SERVER_DOCKER_DEFERRED "$output" 'busy Docker setup deferral'
  ! grep -q '^dockerd-rootless-setuptool.sh ' "$case_dir/calls" ||
    fail 'busy Docker setup was mutated'

  case_dir="$fixture/rootless-unknown"
  unit="$case_dir/home/.config/systemd/user/docker.service"
  mkdir -p "${unit%/*}" "$case_dir/state"
  printf 'preserve\n' >"$unit"
  set +e
  env HOME="$case_dir/home" PATH="$bin:/usr/bin:/bin" \
    FAKE_CALLS="$case_dir/calls" FAKE_STATE="$case_dir/state" \
    FAKE_SERVICE_STATUS=4 bash "$repair" >"$case_dir/output" 2>&1
  rc=$?
  set -e
  assert_eq 1 "$rc" 'unknown existing Docker service state exit'
  assert_eq preserve "$(tr -d '\n' <"$unit")" \
    'unknown Docker service state preservation'
  ! grep -q '^dockerd-rootless-setuptool.sh ' "$case_dir/calls" ||
    fail 'unknown Docker service state was mutated'
  tests_run=$((tests_run + 1))
}

test_static_boundary_contract() {
  local deployed_dotfiles deployed_skid expected_dotfiles expected_skid marker production
  production="$fixture/production"
  printf '%s\n' \
    "$repo_dir/devbox" \
    "$repo_dir/lib/remote-devbox.sh" \
    "$repo_dir/cloud-init-devbox.template.yaml" \
    >"$production"
  git -C "$repo_dir" ls-files -z ansible |
    while IFS= read -r -d '' path; do
      printf '%s/%s\n' "$repo_dir" "$path"
    done >>"$production"
  while IFS= read -r path; do
    if grep -Eqi 'devbox-state|STATE_BOOTSTRAP|doctor|converge|curl[^|]*\|[[:space:]]*(ba)?sh|@latest' "$path"; then
      fail "legacy state or mutable installer remains: $path"
    fi
  done <"$production"
  assert_contains "$repo_dir/ansible/inventory/devbox.yml" \
    'ansible_host: dev-server-deploy' 'Ansible deployment alias'
  assert_contains "$repo_dir/ansible/roles/security/handlers/main.yml" \
    'Validate SSH before reload' 'SSH validation handler'
  assert_contains "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" \
    'DEV_SERVER_DOCKER_DEFERRED' 'busy Docker deferral'
  assert_contains "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" \
    'active/docker.sha256' 'Docker activation identity'
  assert_contains "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" \
    'systemctl --user is-active --quiet docker.service' 'rootless Docker state observation'
  assert_not_contains "$repo_dir/ansible/roles/rootless_docker/tasks/main.yml" \
    'rc not in [0, 1]' 'ambiguous Docker observation success'
  assert_contains "$repo_dir/ansible/roles/security/tasks/main.yml" \
    'active/ssh.sha256' 'SSH activation identity'
  assert_contains "$repo_dir/ansible/roles/base/tasks/main.yml" \
    'DEV_SERVER_TMUX_DEFERRED' 'busy tmux deferral'
  assert_contains "$repo_dir/ansible/roles/base/tasks/main.yml" \
    'mode: "0750"' 'private devbox home mode'
  assert_contains "$repo_dir/ansible/roles/ai_tools/tasks/main.yml" \
    'ssh-keygen -y -f /home/{{ devbox_user }}/.ssh/id_ed25519_github | awk' \
    'canonical GitHub public-key derivation'
  assert_contains "$repo_dir/ansible/playbooks/tasks/remote-preflight.yml" \
    '(home, 0o750)' 'private devbox home preflight'
  assert_contains "$repo_dir/ansible/playbooks/apply.yml" \
    'DEV_SERVER_REBOOT_DEFERRED' 'pending reboot deferral'
  assert_not_contains "$repo_dir/ansible/roles/base/tasks/main.yml" \
    'unattended-upgrades.service' 'maintenance one-shot activation'
  assert_not_contains "$repo_dir/cloud-init-devbox.template.yaml" \
    '--ssh' 'Tailscale SSH transport interposition'
  for marker in \
    DEV_SERVER_SKID_ACTION_INSTALL_TAILSCALE \
    DEV_SERVER_SKID_ACTION_SIGN_IN_TAILSCALE \
    DEV_SERVER_SKID_ACTION_CLEAR_STALE_SERVE; do
    assert_eq 2 \
      "$(grep -c "$marker" "$repo_dir/ansible/roles/skidbladnir/tasks/main.yml")" \
      "Skíðblaðnir callback bridge for $marker"
  done
  deployed_dotfiles="$(
    sed -n \
      '/^- name: Install exact dotfile assets$/,/^- name: Install explicit AI profile wrapper$/p' \
      "$repo_dir/ansible/roles/workspace_assets/tasks/main.yml" |
      sed -n 's/^    - //p'
  )"
  expected_dotfiles="$(printf '%s\n' \
    gitconfig gitignore_global p10k.zsh tmux.conf zsh_helpers zshenv zshrc)"
  assert_eq "$expected_dotfiles" "$deployed_dotfiles" \
    'exact remote dotfile asset closure'
  deployed_skid="$(
    sed -n '/^- name: Install exact Skíðblaðnir assets$/,$p' \
      "$repo_dir/ansible/roles/workspace_assets/tasks/main.yml" |
      sed -n 's/^    - path: //p'
  )"
  expected_skid="$(printf '%s\n' \
    release-pin.json \
    host-config-devbox.json \
    agent-hooks-devbox.json \
    skidbladnir.service \
    skidbladnir-launch \
    skid-notify-linux \
    claude-agent-identity/.claude-plugin/plugin.json \
    claude-agent-identity/hooks/hooks.json \
    claude-agent-identity/bin/agent-hook)"
  assert_eq "$expected_skid" "$deployed_skid" \
    'exact remote Skíðblaðnir asset closure'
  tests_run=$((tests_run + 1))
}

test_remote_managed_state_preflight_contract() {
  python3 - \
    "$repo_dir/ansible/playbooks/apply.yml" \
    "$repo_dir/ansible/playbooks/tasks/remote-preflight.yml" <<'PY' ||
import pathlib
import sys

playbook = pathlib.Path(sys.argv[1]).read_text()
gate = pathlib.Path(sys.argv[2]).read_text()
name = "    - name: Validate all existing remote managed state before mutation"
start = playbook.index(name)
roles = playbook.index("\n  roles:", start)
assert start < roles
assert "ansible.builtin.import_tasks: tasks/remote-preflight.yml" in playbook[start:roles]

required = {
    "/var/lib/dev-server/active/ssh.sha256": "root SSH activation journal",
    'active / "docker.sha256"': "user Docker activation journal",
    'active / "skid.runtime.sha256"': "Skidbladnir runtime activation journal",
    'active / "skid.unit.sha256"': "Skidbladnir unit activation journal",
    'config / "machine-handle"': "Skidbladnir machine credential",
    'config / "bearer"': "Skidbladnir bearer credential",
    'config / "android-signing.p12"': "Android signing key credential",
    'config / "android-signing.properties"': "Android signing properties credential",
    'config / "android-signing.password"': "Android signing password credential",
    'share / "current"': "Skidbladnir current pointer",
    'share / "previous"': "Skidbladnir previous pointer",
    'home / ".local/bin/skidbladnir"': "Skidbladnir command link",
    'systemd_user / "skidbladnir.service"': "Skidbladnir service unit",
    'systemd_user / "docker.service"': "Docker service unit",
    'home / ".config/docker/daemon.json"': "Docker configuration topology",
    'home / ".ssh/id_ed25519_github"': "GitHub private identity",
    'home / ".ssh/id_ed25519_github.pub"': "GitHub public identity",
    'home / ".ssh/config"': "GitHub SSH client policy",
    'home / ".zsh/fzf-tab"': "fzf-tab public plugin link",
    'home / ".zsh/powerlevel10k"': "powerlevel10k public plugin link",
    'home / ".tmux/plugins/tpm"': "tpm public plugin link",
    'home / ".tmux/plugins/tmux-resurrect"': "tmux-resurrect public plugin link",
    'home / ".tmux/plugins/tmux-continuum"': "tmux-continuum public plugin link",
}
for fragment, label in required.items():
    assert fragment in gate, label

for invariant in (
        "os.path.lexists", "os.lstat", '"O_NOFOLLOW"', "st_nlink != 1",
        'rb"[0-9a-f]{64}\\n"', 'rb"mh-[0-9a-f]{32}\\n"',
        'generation_target.fullmatch', "runtime_active and not current",
        "units / unit_active", "unowned Git plugin root",
        '[0-9a-f]{40}', '"symlink": stat.S_ISLNK',
        'os.path.lexists(github_private) != os.path.lexists(github_public)',
        "changed_when: false"):
    assert invariant in gate, invariant

for mutator in (
        "ansible.builtin.apt:", "ansible.builtin.copy:",
        "ansible.builtin.file:", "ansible.builtin.get_url:",
        "ansible.builtin.systemd_service:", "ansible.builtin.user:",
        "os.chmod(", "os.chown(", "os.link(", "os.mkdir(", "os.makedirs(",
        "os.remove(", "os.rename(", "os.replace(", "os.symlink(", "os.unlink(",
        ".write_bytes(", ".write_text("):
    assert mutator not in gate, mutator

marker = "/usr/bin/python3 - <<'PY'\n"
program_start = gate.index(marker) + len(marker)
program_end = gate.index("\n    PY", program_start)
program = gate[program_start:program_end]
program = "\n".join(
    line[4:] if line.startswith("    ") else line
    for line in program.splitlines()
)
compile(program, "remote-managed-state-preflight", "exec")
PY
    fail 'remote managed-state preflight contract is incomplete'
  tests_run=$((tests_run + 1))
}

test_ufw_ingress_boundary_contract() {
  local path

  for path in \
    "$repo_dir/ansible/roles/security/tasks/main.yml" \
    "$repo_dir/ansible/playbooks/apply.yml"; do
    assert_contains "$path" "[[ \"\$rule\" == *'ALLOW IN'* ]]" \
      'all inbound UFW allows are inspected'
    assert_contains "$path" "[[ \"\$target\" != *'on tailscale0'* ]]" \
      'tailnet is the sole UFW inbound exception'
    if grep -Eq '\(22\|80\|443\)|22/tcp|80,443/tcp' "$path"; then
      fail "literal-port UFW boundary remains in $path"
    fi
  done
  assert_contains "$repo_dir/ansible/roles/security/tasks/main.yml" \
    'ufw --force reset' 'inactive persisted UFW rule reset'
  python3 - "$repo_dir/ansible/roles/security/tasks/main.yml" <<'PY' ||
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()
reset = text.index("ufw --force reset")
enable = text.index("ufw --force enable")
assert reset < enable
PY
    fail 'inactive UFW reset does not precede enablement'
  tests_run=$((tests_run + 1))
}

test_cli_contract
test_existing_server_never_bootstraps
test_ansible_failure_has_one_terminal_summary
test_skid_action_is_exact_and_visible
test_existing_tailscale_ssh_requires_manual_cutover
test_existing_drift_only_closes_ingress
test_existing_offline_peer_closes_interrupted_bootstrap
test_new_server_closes_both_boundaries
test_new_server_failure_still_closes_ingress
test_new_host_key_no_write_preserves_trust
test_new_host_key_mismatch_preserves_trust
test_known_hosts_symlink_fails_before_external_state
test_rootless_docker_repair_lifecycle
test_static_boundary_contract
test_remote_managed_state_preflight_contract
test_ufw_ingress_boundary_contract

printf 'devbox: %d contract groups passed\n' "$tests_run"
