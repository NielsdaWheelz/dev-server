#!/usr/bin/env bash

personal_macos_desktop_deferred=0

personal_macos_validate_declared_inputs() {
  local asset

  for asset in dotfiles/ghostty-macos.config security/workstation-sshd.conf \
    security/macos.pf.conf security/macos-firewall \
    security/com.nielseriknandal.dev-server.firewall.plist; do
    asset="$(dev_server_assets_dir)/$asset"
    [[ -f "$asset" && ! -L "$asset" ]] || die "invalid personal asset: $asset"
  done
}

personal_macos_configure_security() {
  local assets asset target mode result effective desired address
  local label=com.nielseriknandal.dev-server.firewall
  local plist_changed=0
  local loaded=0

  [[ "$(uname -s)" == Darwin ]] || die 'macos security applies only on macos'
  assets="$(dev_server_assets_dir)/security"
  sudo /usr/sbin/sshd -t -f "$assets/workstation-sshd.conf"
  /sbin/pfctl -n -a dev-server -f "$assets/macos.pf.conf" >/dev/null 2>&1
  plutil -lint "$assets/$label.plist" >/dev/null
  if [[ ! -d /usr/local/libexec ]]; then
    sudo mkdir -m 0755 /usr/local/libexec
  fi

  while IFS='|' read -r asset target mode; do
    atomic_install_file_as_root "$assets/$asset" "$target" "$mode" || return 1
    # Assigned by atomic_install_file_as_root.
    # shellcheck disable=SC2154
    case "$dev_server_install_status" in
    INSTALLED | UPDATED)
      render_result "$dev_server_install_status" "$target"
      [[ "$asset" != "$label.plist" ]] || plist_changed=1
      ;;
    UP\ TO\ DATE) ;;
    *) die "invalid security install result: $target" ;;
    esac
  done <<'FILES'
workstation-sshd.conf|/etc/ssh/sshd_config.d/00-dev-server.conf|0644
macos.pf.conf|/etc/pf.anchors/dev-server|0644
macos-firewall|/usr/local/libexec/dev-server-macos-firewall|0755
com.nielseriknandal.dev-server.firewall.plist|/Library/LaunchDaemons/com.nielseriknandal.dev-server.firewall.plist|0644
FILES
  sudo /usr/sbin/sshd -t
  for address in 100.106.186.126 fd7a:115c:a1e0::3438:ba7f; do
    effective="$(sudo /usr/sbin/sshd -T -C "user=nnandal,host=arch,addr=$address" |
      awk '{$1=tolower($1); print}')"
    for desired in 'passwordauthentication no' 'kbdinteractiveauthentication no' \
      'permitrootlogin no' 'pubkeyauthentication yes' 'allowusers nnandal' 'gatewayports no'; do
      grep -Fxq "$desired" <<<"$effective" || die "effective ssh policy differs: $desired"
    done
  done

  result="$(sudo /usr/local/libexec/dev-server-macos-firewall)" ||
    die 'could not activate private macos ingress'
  [[ "$result" != changed ]] || render_result RELOADED macos.firewall
  [[ "$result" == changed || "$result" == unchanged ]] || die 'invalid firewall activation result'

  sudo launchctl print "system/$label" >/dev/null 2>&1 && loaded=1
  if ((loaded && plist_changed)); then
    sudo launchctl bootout "system/$label"
    loaded=0
  fi
  if ((!loaded)); then
    sudo launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
    render_result STARTED "$label"
  fi
  if ! /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -Fq '(State = 1)'; then
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on >/dev/null
    render_result CHANGED macos.application-firewall
  fi
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -Fq '(State = 1)' ||
    die 'macos application firewall is not enabled'
}

personal_macos_apply() {
  local home

  personal_macos_validate_declared_inputs
  personal_macos_configure_security
  home="$(dev_server_home)"
  ensure_directory "$home/Library/Application Support/com.mitchellh.ghostty" 0755 || return 1
  install_managed_file "$(dev_server_assets_dir)/dotfiles/ghostty-macos.config" \
    "$home/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
    0644 desktop.session || return 1
  # Published by the shared atomic installer.
  # shellcheck disable=SC2154
  if [[ "$dev_server_install_status" != 'UP TO DATE' ]]; then
    # Read by workstation_report_deferrals.
    # shellcheck disable=SC2034
    personal_macos_desktop_deferred=1
  fi
}
