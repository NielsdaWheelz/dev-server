#!/usr/bin/env bash
# shellcheck disable=SC2154 # gateway wrapper supplies deployment context.

# the bundle is one signed mechanism; consumers inspect only this contract.
skid_notifications_app_files() {
  printf '%s\n' Contents/Info.plist Contents/MacOS/skid-notifications \
    Contents/Resources/skid.icns Contents/_CodeSignature/CodeResources
}

skid_notifications_validate_app() (
  local app="$1" version="$2" source="$3" stage pin certificate
  [[ "$(uname -s)/$(uname -m)" == Darwin/arm64 ]] || return 1
  python3 - "$app" "$version" "$source" <<'PY' || return 1
from pathlib import Path
import plistlib, stat, sys
app = Path(sys.argv[1])
directories = {".", "Contents", "Contents/MacOS", "Contents/Resources", "Contents/_CodeSignature"}
files = {"Contents/Info.plist", "Contents/MacOS/skid-notifications",
         "Contents/Resources/skid.icns", "Contents/_CodeSignature/CodeResources"}
if app.is_symlink() or not app.is_dir():
    raise SystemExit(1)
entries = {"."} | {str(path.relative_to(app)) for path in app.rglob("*")}
if entries != directories | files:
    raise SystemExit(1)
for name in entries:
    info = (app / name).lstat()
    directory = name in directories
    if not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise SystemExit(1)
    mode = 0o755 if directory or name == "Contents/MacOS/skid-notifications" else 0o644
    if stat.S_IMODE(info.st_mode) != mode:
        raise SystemExit(1)
with (app / "Contents/Info.plist").open("rb") as stream:
    value = plistlib.load(stream)
for key, expected in {"CFBundleIdentifier": "dev.niels.skidbladnir",
                      "CFBundleExecutable": "skid-notifications", "CFBundleIconFile": "skid",
                      "CFBundlePackageType": "APPL",
                      "CFBundleShortVersionString": sys.argv[2][1:],
                      "CFBundleVersion": sys.argv[2][1:], "SkidSourceSHA": sys.argv[3]}.items():
    if value.get(key) != expected:
        raise SystemExit(1)
PY
  pin="$(cat "$(dev_server_assets_dir)/skidbladnir/mac-signing-cert.sha256")" || return 1
  [[ "$pin" =~ ^[0-9a-f]{64}$ ]] || return 1
  codesign --verify --strict "$app" >/dev/null 2>&1 || return 1
  stage="$(mktemp -d /tmp/skid-app-admission.XXXXXX)" || return 1
  # shellcheck disable=SC2064 # bind the private path before function scope unwinds.
  trap "rm -R -- $(printf '%q' "$stage")" EXIT
  codesign --display --extract-certificates="$stage/cert" "$app" >/dev/null 2>&1 || return 1
  certificate="$(dev_server_sha256 "$stage/cert0")" || return 1
  [[ "$certificate" == "$pin" ]] || return 1
  [[ "$("$app/Contents/MacOS/skid-notifications" version)" == "$version $source" ]]
)

skid_notifications_validate_installed_app() (
  local app="$1" values version source
  [[ -d "$app" && ! -L "$app" ]] || return 1
  values="$(python3 - "$app/Contents/Info.plist" <<'PY'
import plistlib, re, sys
try:
    with open(sys.argv[1], "rb") as stream:
        value = plistlib.load(stream)
    version, source = value.get("CFBundleVersion"), value.get("SkidSourceSHA")
    if (not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})", version) or
            not isinstance(source, str) or not re.fullmatch(r"[0-9a-f]{40}", source)):
        raise SystemExit(1)
    print("v" + version + "\t" + source)
except (OSError, ValueError, TypeError, AttributeError):
    raise SystemExit(1)
PY
  )" || return 1
  IFS=$'\t' read -r version source <<<"$values"
  skid_notifications_validate_app "$app" "$version" "$source"
)

# The waiter has already stopped. An unregistered direct process may still own
# the socket; refuse replacement rather than treating a public stop as proof.
skid_notifications_stop_app() {
  local utility="$1" app="$2" endpoint="$3"
  if [[ -d "$app" ]]; then
    "$utility" stop "$app" >/dev/null 2>&1 || return 1
  fi
  python3 - "$endpoint" <<'PY'
import errno, socket, sys
with socket.socket(socket.AF_UNIX) as peer:
    peer.settimeout(3)
    try:
        peer.connect(sys.argv[1])
    except OSError as error:
        raise SystemExit(0 if error.errno in (errno.ENOENT, errno.ECONNREFUSED) else 1)
    raise SystemExit(1)
PY
}

# The public app PID, not open's waiter PID, must own a responsive local owner.
# Snapshot validity stays inside that owner; setup may have no producer yet.
skid_notifications_app_ready() {
  local utility="$1" app="$2" endpoint="$3" pid
  pid="$("$utility" status "$app" 2>/dev/null)" || return 1
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  python3 - "$pid" "$endpoint" <<'PY'
import json, socket, subprocess, sys, time
def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError()
        result[key] = value
    return result
def invalid_constant(_):
    raise ValueError()
deadline = time.monotonic() + 3
try:
    result = subprocess.run(['/usr/sbin/lsof', '-nP', '-a', '-p', sys.argv[1], '-U', '-Fn'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3, check=True)
    if ('n' + sys.argv[2]).encode() not in result.stdout.splitlines():
        raise ValueError()
    with socket.socket(socket.AF_UNIX) as peer:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError()
        peer.settimeout(remaining)
        peer.connect(sys.argv[2])
        peer.sendall(b'{"op":"read","args":{}}\n')
        data = bytearray()
        while b'\n' not in data:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError()
            peer.settimeout(remaining)
            part = peer.recv(min(65536, 1048577 - len(data)))
            if not part:
                raise ValueError()
            data.extend(part)
            if len(data) > 1048576:
                raise ValueError()
    response = json.loads(data.decode('utf-8'), object_pairs_hook=unique, parse_constant=invalid_constant)
    if not isinstance(response, dict) or set(response) != {'ok', 'value'} or response['ok'] is not True:
        raise ValueError()
    view = response['value']
    if (not isinstance(view, dict) or not {'deviceSnapshot', 'producerAvailable'} <= set(view) or
            not set(view) <= {'deviceSnapshot', 'producerAvailable', 'currentProducerSnapshot'} or
            not isinstance(view['deviceSnapshot'], dict) or type(view['producerAvailable']) is not bool or
            'currentProducerSnapshot' in view and not isinstance(view['currentProducerSnapshot'], dict) or
            view['producerAvailable'] and 'currentProducerSnapshot' not in view):
        raise ValueError()
except (OSError, ValueError, subprocess.SubprocessError):
    raise SystemExit(1)
PY
}

skid_notifications_install_ntfy() {
  local stage="$1" home="$2" pin values version url checksum archive binary target
  pin="$(dev_server_assets_dir)/skidbladnir/ntfy-release.json"
  dev_server_strict_json_file "$pin" 4096 || return 1
  values="$(python3 - "$pin" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    value = json.load(stream)
expected = {"version": "2.28.0", "url": "https://github.com/binwiederhier/ntfy/releases/download/v2.28.0/ntfy_2.28.0_linux_amd64.tar.gz",
            "sha256": "881a1530e30e01f1dec202c7f41e1664e57edfb7844e73e21e345159ac3ea9b7"}
if value != expected:
    raise SystemExit(1)
print("\t".join(value[key] for key in ("version", "url", "sha256")))
PY
  )" || return 1
  IFS=$'\t' read -r version url checksum <<<"$values"
  target="$home/.local/share/skidbladnir/ntfy-$version"
  if [[ -e "$target" ]]; then
    [[ -d "$target" && ! -L "$target" &&
      -f "$target/archive.sha256" && ! -L "$target/archive.sha256" &&
      "$(cat "$target/archive.sha256")" == "$checksum" &&
      "$(file_mode "$target/ntfy")" == 755 &&
      "$(dev_server_sha256 "$target/ntfy")" == "$(cat "$target/binary.sha256")" ]] || return 1
    printf '%s\n' "$target/ntfy"
    return 0
  fi
  archive="$stage/ntfy.tar.gz"
  dev_server_download "$url" "$archive" || return 1
  [[ "$(dev_server_sha256 "$archive")" == "$checksum" ]] || return 1
  python3 - "$archive" "$stage" <<'PY'
import pathlib, sys, tarfile
with tarfile.open(sys.argv[1], "r:gz") as archive:
    members = [entry for entry in archive if entry.name == "ntfy_2.28.0_linux_amd64/ntfy"]
    if len(members) != 1 or not members[0].isfile():
        raise SystemExit(1)
    data = archive.extractfile(members[0]).read()
    pathlib.Path(sys.argv[2], "ntfy").write_bytes(data)
PY
  binary="$stage/ntfy"
  chmod 0755 "$binary" || return 1
  "$binary" --version | LC_ALL=C grep -Eq '^ntfy version 2\.28\.0([ ,]|$)' || return 1
  mkdir -m 0700 "$stage/ntfy-release" || return 1
  install -m 0755 "$binary" "$stage/ntfy-release/ntfy" || return 1
  printf '%s\n' "$checksum" >"$stage/ntfy-release/archive.sha256"
  dev_server_sha256 "$binary" >"$stage/ntfy-release/binary.sha256" || return 1
  chmod 0600 "$stage/ntfy-release/"*.sha256 || return 1
  mv "$stage/ntfy-release" "$target" || return 1
  printf '%s\n' "$target/ntfy"
}

# all secret generation and rendering stays inside a private directory/process.
skid_notifications_render_devbox() (
  set +x
  local home="$1" stage="$2" ntfy="$3" hostname="$4" config="$1/.config/skidbladnir/notifications"
  python3 - "$home" "$stage" "$ntfy" "$hostname" "$config" <<'PY'
import json, os, pathlib, re, secrets, subprocess, sys
home, stage, ntfy, hostname, config = sys.argv[1:]
stage, config = pathlib.Path(stage), pathlib.Path(config)
secret_path = config / "credentials.json"
try:
    if secret_path.exists():
        if secret_path.is_symlink() or secret_path.stat().st_mode & 0o777 != 0o600:
            raise ValueError()
        secret = json.loads(secret_path.read_text())
        if set(secret) != {"publisherToken", "publisherHash", "phonePassword", "phoneHash"}:
            raise ValueError()
    else:
        def password_hash(password):
            result = subprocess.run([ntfy, "user", "hash"], input=(password + "\n") * 2,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
            return result.stdout.strip()
        publisher_password = secrets.token_urlsafe(32)
        phone_password = secrets.token_urlsafe(32)
        token = subprocess.run([ntfy, "token", "generate"], text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, check=True).stdout.strip()
        secret = {"publisherToken": token, "publisherHash": password_hash(publisher_password),
                  "phonePassword": phone_password, "phoneHash": password_hash(phone_password)}
    if (not all(isinstance(item, str) for item in secret.values()) or
            not re.fullmatch(r"tk_[-_A-Za-z0-9]{29}", secret["publisherToken"]) or
            not re.fullmatch(r"[A-Za-z0-9_-]{43}", secret["phonePassword"]) or
            not all(re.fullmatch(r"\$2[aby]\$10\$[A-Za-z0-9./]{53}", secret[key])
                    for key in ("publisherHash", "phoneHash"))):
        raise ValueError()
    state = f"{home}/.local/state/skidbladnir/ntfy"
    server = {"base-url": f"https://{hostname}:8444", "listen-http": "127.0.0.1:2586",
              "auth-file": state + "/auth.db", "auth-default-access": "deny-all",
              "auth-users": ["skid-publisher:" + secret["publisherHash"] + ":user",
                             "skid-phone:" + secret["phoneHash"] + ":user"],
              "auth-access": ["skid-publisher:up*:write-only", "skid-phone:up*:read-only"],
              "auth-tokens": ["skid-publisher:" + secret["publisherToken"] + ":skid"],
              "cache-file": state + "/cache.db", "cache-duration": "12h", "behind-proxy": True,
              "firebase-key-file": "", "upstream-base-url": "", "enable-signup": False,
              "enable-login": False, "log-level": "error"}
    observer = {"clientConfig": f"{home}/.config/skidbladnir/client.json",
                "bearerFile": f"{home}/.config/skidbladnir/bearer",
                "machineHandleFile": f"{home}/.config/skidbladnir/machine-handle",
                "listen": "127.0.0.1:7342", "ntfyPublisherCredentialFile": str(config / "publisher-token")}
    for name, value in (("credentials.json", secret), ("ntfy.yml", server), ("observer.json", observer)):
        (stage / name).write_text(json.dumps(value, indent=2) + "\n")
        (stage / name).chmod(0o600)
    (stage / "publisher-token").write_text(secret["publisherToken"] + "\n")
    (stage / "publisher-token").chmod(0o600)
except (OSError, ValueError, subprocess.SubprocessError):
    raise SystemExit("private notification configuration is invalid")
PY
)

skid_notifications_apply() {
  local output status=0 line subject detail
  if output="$(skid_notifications_apply_owned "$1")"; then
    :
  else
    status=$?
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    detail="${line#*  }"
    subject="${detail%%: *}"
    if [[ "$subject" == "$detail" ]]; then
      render_result "${line%%  *}" "$subject"
    else
      render_result "${line%%  *}" "$subject" "${detail#*: }"
    fi
  done <<<"$output"
  return "$status"
}

skid_notifications_apply_owned() (
  set +x
  local platform="$1" home share config state stage unit target name current identity client_identity previous='' hostname ntfy app version source job app_changed=0 changed=0 ready=1
  case "$platform" in macos | devbox) ;; arch) return 0 ;; *) return 1 ;; esac
  home="$(dev_server_home)"
  share="$home/.local/share/skidbladnir"
  config="$home/.config/skidbladnir/notifications"
  state="$home/.local/state/skidbladnir"
  current="$share/current"
  dev_server_reconcile_directory "$config" 0700 || return 1
  dev_server_acquire_lock "$share/.notifications.apply.lock" 8 notifications
  if [[ "$platform" == macos ]]; then
    dev_server_reconcile_directory "$home/Applications" 0755 || return 1
    stage="$(mktemp -d "$home/Applications/.skid-notifications.XXXXXX")" || return 1
  else
    stage="$(mktemp -d "$config/.apply.XXXXXX")" || return 1
  fi
  chmod 0700 "$stage" || return 1
  # shellcheck disable=SC2064 # bind the private path before function scope unwinds.
  trap "rm -R -- $(printf '%q' "$stage")" EXIT
  if [[ "$platform" == macos ]]; then
    version="$(jq -er '.version' "$current/release.json")" || return 1
    source="$(jq -er '.sourceSha' "$current/release.json")" || return 1
    skid_notifications_validate_app "$current/Skid.app" "$version" "$source" ||
      die 'native notification app admission failed'
    app="$home/Applications/Skid.app"
    if [[ -e "$app" || -L "$app" ]]; then
      skid_notifications_validate_installed_app "$app" || die 'installed native notification app is not an owned signed bundle'
      while IFS= read -r unit; do
        if ! cmp -s "$app/$unit" "$current/Skid.app/$unit"; then
          app_changed=1
          break
        fi
      done < <(skid_notifications_app_files)
    else
      app_changed=1
    fi
    python3 - "$(dev_server_assets_dir)/skidbladnir/dev.niels.skid-notifications.plist" "$stage/unit" "$home" "$dev_server_fleet_label_prefix" <<'PY' || return 1
import pathlib, plistlib, sys
value = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
def replace(item):
    if isinstance(item, dict): return {key: replace(value) for key, value in item.items()}
    if isinstance(item, list): return [replace(value) for value in item]
    if isinstance(item, str): return item.replace("@ROOT@", sys.argv[3]).replace("@FLEET_LABEL_PREFIX@", sys.argv[4])
    return item
pathlib.Path(sys.argv[2]).write_bytes(plistlib.dumps(replace(value)))
PY
    target="$home/Library/LaunchAgents/$dev_server_fleet_label_prefix.skid-notifications.plist"
    name="$dev_server_fleet_label_prefix.skid-notifications"
    if [[ -e "$home/.config/skidbladnir/client.json" || -L "$home/.config/skidbladnir/client.json" ]]; then
      client_identity="$(dev_server_sha256 "$home/.config/skidbladnir/client.json")" || return 1
    else
      client_identity=absent
    fi
    identity="$(printf '%s\n%s\n%s\n' "$(basename "$(cd "$current" && pwd -P)")" \
      "$(dev_server_sha256 "$stage/unit")" "$client_identity" | dev_server_sha256_stream)" || return 1
    previous="$(gateway_active_identity "$state/notification-app.sha256" 2>/dev/null || true)"
    [[ "$identity" == "$previous" ]] || changed=1
    ((app_changed == 0)) || changed=1
    if ((changed)); then
      dev_server_stop_service macos "$name" || die 'could not stop native notification app'
      skid_notifications_stop_app "$current/Skid.app/Contents/MacOS/skid-notifications" "$app" "$state/notifications.sock" ||
        die 'native notification app still owns the installation'
    fi
    if ((app_changed)); then
      cp -Rp "$current/Skid.app" "$stage/Skid.app" || return 1
      skid_notifications_validate_app "$stage/Skid.app" "$version" "$source" || die 'staged native notification app admission failed'
      if [[ -d "$app" ]]; then mv "$app" "$stage/previous.app" || return 1; fi
      if ! mv "$stage/Skid.app" "$app"; then
        if [[ -d "$stage/previous.app" ]] && ! mv "$stage/previous.app" "$app"; then
          trap - EXIT
          die 'native notification app replacement failed; installation stage retained'
        fi
        return 1
      fi
    fi
    atomic_install_file "$stage/unit" "$target" 0644 || return 1
    launchctl enable "gui/$(id -u)/$name" || return 1
    job="$(dev_server_service_state macos "$name")" || return 1
    if [[ "$job" != active ]]; then
      "$app/Contents/MacOS/skid-notifications" register "$app" || die 'native notification app registration failed'
      case "$job" in
      absent) launchctl bootstrap "gui/$(id -u)" "$target" || return 1 ;;
      inactive) launchctl kickstart -k "gui/$(id -u)/$name" || return 1 ;;
      *) return 1 ;;
      esac
      changed=1
    fi
    for ((ready=0; ready<10; ready++)); do
      if [[ "$(dev_server_service_state macos "$name")" == active ]] &&
        skid_notifications_app_ready "$current/Skid.app/Contents/MacOS/skid-notifications" "$app" "$state/notifications.sock"; then break; fi
      sleep 1
    done
    ((ready < 10)) || die 'native notification app did not become available'
    printf '%s\n' "$identity" >"$stage/app.sha256"
    atomic_install_file "$stage/app.sha256" "$state/notification-app.sha256" 0600 || return 1
    ((changed == 0)) || render_result CHANGED skid.notifications 'native login app active'
    return 0
  fi
  [[ "$(uname -s)/$(uname -m)" == Linux/x86_64 ]] || return 1
  dev_server_reconcile_directory "$state/ntfy" 0700 || return 1
  hostname="$("$(dev_server_tailscale_cli)" status --json | jq -er '.Self.DNSName | rtrimstr(".")')" || return 1
  [[ "$hostname" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] || return 1
  ntfy="$(skid_notifications_install_ntfy "$stage" "$home")" || die 'pinned ntfy admission failed'
  skid_notifications_render_devbox "$home" "$stage" "$ntfy" "$hostname" || return 1
  for unit in credentials.json publisher-token ntfy.yml observer.json; do
    atomic_install_file "$stage/$unit" "$config/$unit" 0600 || return 1
    [[ "$dev_server_install_status" == 'UP TO DATE' ]] || changed=1
  done
  for unit in skid-ntfy.service skid-notification-observer.service; do
    atomic_install_file "$(dev_server_assets_dir)/skidbladnir/$unit" "$home/.config/systemd/user/$unit" 0644 || return 1
    [[ "$dev_server_install_status" == 'UP TO DATE' ]] || changed=1
  done
  systemctl --user daemon-reload || return 1
  systemctl --user enable skid-ntfy.service skid-notification-observer.service >/dev/null || return 1
  if ((changed)) || [[ "$(dev_server_service_state devbox skid-ntfy.service)" != active ]]; then
    systemctl --user restart skid-ntfy.service || return 1
    changed=1
  fi
  for ((ready=0; ready<10; ready++)); do
    if curl --noproxy '*' -fsS --max-time 1 http://127.0.0.1:2586/v1/health 2>/dev/null | jq -e '.healthy == true' >/dev/null; then break; fi
    sleep 1
  done
  ((ready < 10)) || die 'private ntfy did not become healthy'
  if [[ ! -f "$home/.config/skidbladnir/client.json" ]]; then
    render_result ACTION skid.notifications 'provision fleet notification client configuration, then reapply devbox'
    return 2
  fi
  identity="$(printf '%s\n%s\n%s\n' "$(basename "$(cd "$current" && pwd -P)")" \
    "$(dev_server_sha256 "$config/observer.json")" "$(dev_server_sha256 "$home/.config/skidbladnir/client.json")" | dev_server_sha256_stream)"
  previous="$(gateway_active_identity "$state/notification-observer.sha256" 2>/dev/null || true)"
  if ((changed)) || [[ "$identity" != "$previous" || "$(dev_server_service_state devbox skid-notification-observer.service)" != active ]]; then
    systemctl --user restart skid-notification-observer.service || return 1
    changed=1
  fi
  for ((ready=0; ready<10; ready++)); do
    if [[ "$(dev_server_service_state devbox skid-notification-observer.service)" == active ]] &&
      skidbladnir_authenticated_get "$home" 7342 /v1/notifications/state 1048576 |
        jq -e '.schema == 1 and (.epoch | type == "string") and (.revision | type == "number")' >/dev/null; then break; fi
    sleep 1
  done
  ((ready < 10)) || die 'notification observer did not become healthy'
  printf '%s\n' "$identity" >"$stage/observer.sha256"
  atomic_install_file "$stage/observer.sha256" "$state/notification-observer.sha256" 0600 || return 1
  ((changed == 0)) || render_result CHANGED skid.notifications 'private ntfy and observer active'
  return 0
)

skid_notifications_remove() {
  local platform="$1" home name unit config state app
  case "$platform" in macos | devbox) ;; arch) return 0 ;; *) return 1 ;; esac
  home="$(dev_server_home)"
  config="$home/.config/skidbladnir/notifications"
  state="$home/.local/state/skidbladnir"
  if [[ "$platform" == macos ]]; then
    app="$home/Applications/Skid.app"
    if [[ -e "$app" || -L "$app" ]]; then
      skid_notifications_validate_installed_app "$app" || die 'installed native notification app is not an owned signed bundle'
    fi
    name="$dev_server_fleet_label_prefix.skid-notifications"
    dev_server_stop_service macos "$name" || die 'could not stop native notification app'
    skid_notifications_stop_app "$app/Contents/MacOS/skid-notifications" "$app" "$state/notifications.sock" ||
      die 'native notification app still owns the installation'
    launchctl disable "gui/$(id -u)/$name" || return 1
    unit="$home/Library/LaunchAgents/$name.plist"
    [[ ! -e "$unit" || ( -f "$unit" && ! -L "$unit" ) ]] || return 1
    rm -f -- "$unit" "$state/notification-app.sha256" || return 1
    [[ ! -d "$app" ]] || rm -R -- "$app" || return 1
  else
    for name in skid-notification-observer.service skid-ntfy.service; do
      dev_server_stop_service devbox "$name" || die 'could not stop private notification service'
      unit="$home/.config/systemd/user/$name"
      [[ ! -e "$unit" || ( -f "$unit" && ! -L "$unit" ) ]] || return 1
      [[ ! -e "$unit" ]] || systemctl --user disable "$name" >/dev/null 2>&1 || return 1
      rm -f -- "$unit" || return 1
    done
    rm -f -- "$config/observer.json" "$config/ntfy.yml" "$state/notification-observer.sha256" || return 1
    systemctl --user daemon-reload || return 1
  fi
  render_result CHANGED skid.notifications 'notification services removed; private identity and readiness memory retained'
}
