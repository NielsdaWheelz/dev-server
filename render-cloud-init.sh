#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="$base_dir/cloud-init-devbox.template.yaml"
output="$base_dir/cloud-init-devbox.yaml"
private_key="$base_dir/secrets/id_ed25519_github"
public_key="$base_dir/secrets/id_ed25519_github.pub"
bash_aliases="$base_dir/bash_aliases"

for path in "$template" "$private_key" "$public_key" "$bash_aliases"; do
  if [[ ! -f "$path" ]]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
done

private_b64="$(base64 -i "$private_key" | tr -d '\n')"
public_b64="$(base64 -i "$public_key" | tr -d '\n')"
bash_aliases_b64="$(base64 -i "$bash_aliases" | tr -d '\n')"

awk \
  -v private_key="$private_b64" \
  -v public_key="$public_b64" \
  -v bash_aliases="$bash_aliases_b64" \
  '{
    gsub("__GITHUB_SSH_PRIVATE_KEY_B64__", private_key)
    gsub("__GITHUB_SSH_PUBLIC_KEY_B64__", public_key)
    gsub("__BASH_ALIASES_B64__", bash_aliases)
    print
  }' "$template" > "$output"

chmod 600 "$output"
echo "rendered $output"
