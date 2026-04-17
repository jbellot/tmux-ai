#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec tests/bats-core/bin/bats tests/bats "$@"
