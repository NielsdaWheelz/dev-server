#!/usr/bin/env bash

run_ansible_playbook() {
  require_cmd uvx
  uvx --from ansible-core==2.19.2 ansible-playbook "$@"
}

quote_remote_args() {
  local quoted="" arg escaped

  for arg in "$@"; do
    printf -v escaped '%q' "$arg"
    quoted+="$escaped "
  done
  printf '%s' "$quoted"
}
