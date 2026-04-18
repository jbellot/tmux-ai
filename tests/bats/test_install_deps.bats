#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  touch "$HOME/.tmux.conf"
}

@test "install --check succeeds when all deps present" {
  run "$PROJECT_ROOT/install.sh" --check
  assert_success
}

@test "install --check reports each missing dep on its own line" {
  # Hide jq by overriding PATH to a minimal shim set
  mkdir -p "$BATS_TEST_TMPDIR/emptypath"
  cp /bin/sh "$BATS_TEST_TMPDIR/emptypath/sh" 2>/dev/null || true
  cp /usr/bin/env "$BATS_TEST_TMPDIR/emptypath/env" 2>/dev/null || cp /bin/env "$BATS_TEST_TMPDIR/emptypath/env" 2>/dev/null || true
  cp /bin/bash "$BATS_TEST_TMPDIR/emptypath/bash" 2>/dev/null || true
  cp /usr/bin/grep "$BATS_TEST_TMPDIR/emptypath/grep" 2>/dev/null || cp /bin/grep "$BATS_TEST_TMPDIR/emptypath/grep" 2>/dev/null || true
  cp /usr/bin/awk "$BATS_TEST_TMPDIR/emptypath/awk" 2>/dev/null || cp /bin/awk "$BATS_TEST_TMPDIR/emptypath/awk" 2>/dev/null || true
  cp /bin/mkdir "$BATS_TEST_TMPDIR/emptypath/mkdir" 2>/dev/null || true

  run env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/emptypath" "$PROJECT_ROOT/install.sh" --check
  # Missing deps should produce non-zero exit and stderr lines
  [ "$status" -ne 0 ]
  assert_output --partial "missing"
}
