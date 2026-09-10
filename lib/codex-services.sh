#!/usr/bin/env bash

codex_services_stage=''
codex_services_host=''
codex_services_changed=0
codex_services_restart=0
codex_services_identity=''

codex_services_cleanup() {
  [[ -n "$codex_services_stage" ]] || return 0
  case "$codex_services_stage" in
  "${TMPDIR:-/tmp}"/codex-services.??????)
    rm -R -- "$codex_services_stage"
    codex_services_stage=''
    ;;
  *) return 1 ;;
  esac
}

codex_services_unit() {
  case "$codex_services_host" in
  macbook) printf '%s/Library/LaunchAgents/dev.niels.codex-shared.%s.plist\n' "$(dev_server_home)" "$1" ;;
  arch) printf '%s/.config/systemd/user/codex-shared@%s.service\n' "$(dev_server_home)" "$1" ;;
  *) return 1 ;;
  esac
}

codex_services_state() {
  local profile="$1" output rc
  case "$codex_services_host" in
  macbook)
    if output="$(launchctl print "gui/$(id -u)/dev.niels.codex-shared.$profile" 2>/dev/null)"; then
      if [[ "$output" == *$'\tstate = running'* ]]; then
        printf 'active\n'
      else
        printf 'inactive\n'
      fi
    else
      rc=$?
      ((rc == 113)) || return 1
      printf 'absent\n'
    fi
    ;;
  arch)
    if output="$(systemctl --user is-active "codex-shared@$profile.service")"; then
      [[ "$output" == active ]] || return 1
    else
      rc=$?
      ((rc == 3 || rc == 4)) || return 1
      case "$output" in
      inactive | failed | unknown) output=absent ;;
      activating | deactivating | reloading) output=active ;;
      *) return 1 ;;
      esac
    fi
    printf '%s\n' "$output"
    ;;
  *) return 1 ;;
  esac
}

codex_services_preflight() {
  local host="$1" restart="$2" profile state any_active=0
  case "$host:$restart" in
  macbook:0 | macbook:1 | arch:0 | arch:1) ;;
  *) die 'invalid workstation Codex service target' ;;
  esac
  codex_services_host="$host"
  codex_services_restart="$restart"
  case "$host" in
  macbook)
    require_cmd launchctl
    if ! launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
      render_result ACTION codex.runtime 'log in to the MacBook desktop, then rerun apply'
      return 2
    fi
    ;;
  arch)
    require_cmd systemctl
    if ! systemctl --user show-environment >/dev/null; then
      render_result ACTION codex.runtime 'start the Arch user session, then rerun apply'
      return 2
    fi
    ;;
  esac
  dev_server_validate_active_sha codex.runtime
  codex_services_stage="$(mktemp -d "${TMPDIR:-/tmp}/codex-services.XXXXXX")" || return 1
  cp "$(dev_server_assets_dir)/codex/profiles.json" "$codex_services_stage/profiles.json" || return 1
  cp "$(dev_server_assets_dir)/codex/codex-shared.py" "$codex_services_stage/codex-shared" || return 1
  python3 "$codex_services_stage/codex-shared" \
    --config "$codex_services_stage/profiles.json" --host "$host" check-discovery || return "$?"
  ai_codex_host launcher >"$codex_services_stage/codex-profile" || return 1
  python3 - "$host" "$(dev_server_home)" "$codex_services_stage" <<'PY' || return 1
import pathlib
import plistlib
import sys

host, home, stage = sys.argv[1:]
for profile in ("personal", "work", "work2"):
    target = pathlib.Path(stage) / ("unit-" + profile)
    if host == "macbook":
        unit = {
            "Label": "dev.niels.codex-shared." + profile,
            "ProgramArguments": ["/opt/homebrew/bin/python3", home + "/.local/libexec/codex-shared",
                                 "--config", home + "/.config/codex-shared/profiles.json",
                                 "--host", host, "server", profile],
            "EnvironmentVariables": {"HOME": home},
            "RunAtLoad": True,
            "KeepAlive": {"SuccessfulExit": False},
            "ThrottleInterval": 10,
            "ExitTimeOut": 15,
            "Umask": 63,
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        }
        target.write_bytes(plistlib.dumps(unit))
    else:
        target.write_text(
            "[Unit]\nDescription=Shared Codex App Server (" + profile + ")\n"
            "StartLimitIntervalSec=30\nStartLimitBurst=3\n\n"
            "[Service]\nType=exec\n"
            "ExecStart=/usr/bin/python3 %h/.local/libexec/codex-shared "
            "--config %h/.config/codex-shared/profiles.json --host arch server " + profile + "\n"
            "Restart=on-failure\nRestartSec=2\nTimeoutStopSec=15\nUMask=0077\n"
            "NoNewPrivileges=true\nStandardOutput=null\nStandardError=null\n\n"
            "[Install]\nWantedBy=default.target\n"
        )
PY
  chmod 0644 "$codex_services_stage/profiles.json" "$codex_services_stage"/unit-* || return 1
  chmod 0755 "$codex_services_stage/codex-shared" "$codex_services_stage/codex-profile" || return 1
  codex_services_identity="$(dev_server_declared_snapshot "$codex_services_stage" \
    profiles.json codex-shared codex-profile unit-personal unit-work unit-work2)" || return 1
  codex_services_changed=0
  if ! dev_server_active_sha_matches codex.runtime "$codex_services_identity" ||
    ! ai_codex_matches "$(ai_codex_host pin)"; then
    codex_services_changed=1
  fi
  for profile in personal work work2; do
    state="$(codex_services_state "$profile")" || die 'could not inspect shared Codex service state'
    [[ "$state" == absent ]] || any_active=1
  done
  if ((codex_services_changed && any_active && restart == 0)); then
    render_result ACTION codex.runtime \
      'finish active turns, then run ./workstation apply --restart-codex to replace shared server inputs'
    return 2
  fi
}

codex_services_install() {
  local home profile state target
  home="$(dev_server_home)"
  if ((codex_services_changed)); then
    if ((codex_services_restart)); then
      for profile in personal work work2; do
        state="$(codex_services_state "$profile")" || return 1
        [[ "$state" != absent ]] || continue
        case "$codex_services_host" in
        macbook) launchctl bootout "gui/$(id -u)/dev.niels.codex-shared.$profile" || return 1 ;;
        arch) systemctl --user stop "codex-shared@$profile.service" || return 1 ;;
        esac
      done
    fi
    rm -f -- "$(dev_server_active_dir)/codex.runtime.sha256" || return 1
  fi
  for target in "$home/.config" "$home/.local" "$home/.local/libexec" "$home/.local/share"; do
    ensure_directory "$target" 0755 || return 1
  done
  for target in "$home/.config/codex-shared" "$home/.local/run" \
    "$home/.local/run/codex-shared" "$home/.local/share/codex-shared" \
    "$home/.local/share/codex-shared/empty"; do
    ensure_directory "$target" 0700 || return 1
  done
  for profile in personal work work2; do
    ensure_directory "$home/.local/run/codex-shared/$profile" 0700 || return 1
    target="$(codex_services_unit "$profile")" || return 1
    ensure_directory "$(dirname "$(dirname "$target")")" 0755 || return 1
    ensure_directory "$(dirname "$target")" 0755 || return 1
    install_managed_file "$codex_services_stage/unit-$profile" "$target" 0644 codex.runtime || return 1
  done
  install_managed_file "$codex_services_stage/profiles.json" \
    "$home/.config/codex-shared/profiles.json" 0644 codex.runtime || return 1
  install_managed_file "$codex_services_stage/codex-shared" \
    "$home/.local/libexec/codex-shared" 0755 codex.runtime || return 1
  dev_server_prepare_active_dir
}

codex_services_activate() {
  local profile state enabled target rc discovery
  discovery="$(python3 "$(dev_server_home)/.local/libexec/codex-shared" \
    --config "$(dev_server_home)/.config/codex-shared/profiles.json" \
    --host "$codex_services_host" install-discovery)" || return "$?"
  if [[ -n "$discovery" ]]; then
    record_change codex.runtime
    render_result CHANGED codex.runtime 'native discovery links installed'
  fi
  if [[ "$codex_services_host" == arch ]] && ((codex_services_changed)); then
    systemctl --user daemon-reload || return 1
  fi
  for profile in personal work work2; do
    state="$(codex_services_state "$profile")" || return 1
    case "$codex_services_host" in
    macbook)
      target="gui/$(id -u)/dev.niels.codex-shared.$profile"
      enabled="$(launchctl print-disabled "gui/$(id -u)")" || return 1
      if [[ "$enabled" == *"\"dev.niels.codex-shared.$profile\" => disabled"* ]]; then
        launchctl enable "$target" || return 1
        render_result CHANGED codex.runtime "enabled $profile"
      fi
      case "$state" in
      absent) launchctl bootstrap "gui/$(id -u)" "$(codex_services_unit "$profile")" || return 1 ;;
      inactive) launchctl kickstart "$target" || return 1 ;;
      esac
      ;;
    arch)
      target="codex-shared@$profile.service"
      if systemctl --user is-enabled --quiet "$target"; then
        :
      else
        rc=$?
        ((rc == 1)) || return 1
        systemctl --user enable "$target" || return 1
        render_result CHANGED codex.runtime "enabled $profile"
      fi
      if [[ "$state" != active ]]; then
        systemctl --user start "$target" || return 1
      fi
      ;;
    esac
    python3 - "$(dev_server_home)/.local/run/codex-shared/$profile/app-server.sock" <<'PY' || return 1
import os
import pathlib
import socket
import stat
import sys
import time

path = pathlib.Path(sys.argv[1])
deadline = time.monotonic() + 10
while True:
    try:
        parent = path.parent.lstat()
        item = path.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or not stat.S_ISSOCK(item.st_mode)
                or parent.st_uid != os.getuid() or item.st_uid != os.getuid()
                or stat.S_IMODE(parent.st_mode) != 0o700
                or stat.S_IMODE(item.st_mode) not in (0o600, 0o700)):
            raise SystemExit("ERROR  shared Codex socket ownership or permissions differ")
        # Native bind publishes owner-only 0700 before its asynchronous chmod.
        # It is a startup prefix, not readiness or permission to activate.
        if stat.S_IMODE(item.st_mode) == 0o600:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(1)
                client.connect(str(path))
            break
    except (FileNotFoundError, ConnectionRefusedError, TimeoutError):
        pass
    if time.monotonic() >= deadline:
        raise SystemExit("ERROR  shared Codex socket did not become available")
    time.sleep(0.1)
PY
    [[ "$(codex_services_state "$profile")" == active ]] || return 1
    if [[ "$state" != active ]]; then
      render_result STARTED codex.runtime "$profile"
    fi
  done
  dev_server_record_active_sha codex.runtime "$codex_services_identity"
}
