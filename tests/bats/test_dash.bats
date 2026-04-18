#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "dash render emits a header row and one line per agent" {
  state_init
  local now; now=$(date +%s)
  state_register "%1" agent=claude project=foo state=working window=main pane_index=1.0 turn_started_ts=$((now-60))
  state_register "%2" agent=claude project=bar state=done    window=main pane_index=1.1 turn_started_ts=$((now-300))
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "STATE"
  assert_output --partial "AGENT"
  assert_output --partial "PROJECT"
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "dash render shows 'no agents' when registry empty" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "no agents"
}
