#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_dir/tests/codex-shared.py"
