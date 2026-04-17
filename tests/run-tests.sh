#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -eq 0 ]; then
  exec tests/bats-core/bin/bats tests/bats
else
  exec tests/bats-core/bin/bats "$@"
fi
