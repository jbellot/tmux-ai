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

@test "sidebar --render empty state shows the 'no agents' hint" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  assert_output --partial "no agents"
  assert_output --partial "prefix + A"
}

@test "sidebar --render lists one row per agent with project name" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "sidebar --render emits ANSI color for working state" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 33 = yellow in the 8-color palette
  assert_output --partial $'\033[33m'
}

@test "sidebar --render emits ANSI color for done state" {
  state_init
  state_register "%1" agent=claude project=foo state=done
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 32 = green
  assert_output --partial $'\033[32m'
}

@test "sidebar --render emits ANSI color for stuck state" {
  state_init
  state_register "%1" agent=claude project=foo state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 31 = red
  assert_output --partial $'\033[31m'
}

@test "sidebar --render shows cursor on selected row" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  TMUX_AI_SIDEBAR_SELECTED="%2" run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  [[ "$output" == *"▸"*"bar"* ]] || [[ "$output" == *"bar"*"▸"* ]]
}

@test "sidebar --render is byte-identical across two renders of the same state" {
  state_init
  state_register "%1" agent=claude project=foo state=working registered_ts=1000 last_byte_ts=1000
  out1=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  out2=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  [ "$out1" = "$out2" ]
}

@test "sidebar_next_pane returns the pane after the current one" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  state_register "%3" agent=claude project=c state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_next_pane "%1"
  assert_output "%2"
  run sidebar_next_pane "%2"
  assert_output "%3"
  # Wraps to first
  run sidebar_next_pane "%3"
  assert_output "%1"
}

@test "sidebar_prev_pane returns the pane before the current one" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  state_register "%3" agent=claude project=c state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_prev_pane "%2"
  assert_output "%1"
  # Wraps to last
  run sidebar_prev_pane "%1"
  assert_output "%3"
}

@test "sidebar_nth_pane returns the Nth pane (1-indexed)" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_nth_pane 1
  assert_output "%1"
  run sidebar_nth_pane 2
  assert_output "%2"
  # Out of bounds returns empty
  run sidebar_nth_pane 99
  assert_output ""
}
