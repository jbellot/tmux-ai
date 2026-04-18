#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "tmux-ai help lists subcommands" {
  run "$PROJECT_ROOT/bin/tmux-ai" help
  assert_output --partial "spawn"
  assert_output --partial "dash"
  assert_output --partial "dnd"
  assert_output --partial "status"
  assert_output --partial "detect"
  assert_output --partial "list"
  assert_output --partial "log"
}

@test "tmux-ai list prints registered agents" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai" list
  assert_output --partial "%1"
  assert_output --partial "claude"
  assert_output --partial "foo"
}

@test "unknown subcommand exits non-zero with usage" {
  run "$PROJECT_ROOT/bin/tmux-ai" bogus
  [ "$status" -ne 0 ]
  assert_output --partial "usage"
}

@test "tmux-ai log <pane> prints the logfile path" {
  state_init
  state_register "%1" agent=claude project=foo logfile=/tmp/foo.log
  run "$PROJECT_ROOT/bin/tmux-ai" log "%1"
  assert_output --partial "/tmp/foo.log"
}

@test "tmux-ai log with unknown pane exits non-zero" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai" log "%999"
  [ "$status" -ne 0 ]
}
