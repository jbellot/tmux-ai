#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export TMUX_AI_STATUS_NO_DETECT=1
  # Put the tmux stub in PATH so _hex_opt falls back to hardcoded defaults
  # (stub returns empty for show-options when TMUX_STUB_RESPONSES is unset).
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "tmux-ai status emits empty output when no agents are registered" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}

@test "tmux-ai status emits one segment per non-zero state, in order done/waiting/working/stuck" {
  state_init
  state_register "%1" agent=claude project=a state=done
  state_register "%2" agent=claude project=b state=waiting
  state_register "%3" agent=claude project=c state=working
  state_register "%4" agent=claude project=d state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  # Order: done, waiting, working, stuck. Glyphs have a space before the
  # count to avoid wide-character overlap in some terminals.
  [[ "$output" == *"✓ 1"*"⏸ 1"*"⚙ 1"*"✗ 1"* ]]
}

@test "tmux-ai status uses palette-sourced tmux #[fg=] spans" {
  state_init
  state_register "%1" agent=claude project=a state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#98bb6c]✓ 1"
}

@test "tmux-ai status uses accent color for waiting state" {
  state_init
  state_register "%1" agent=claude project=a state=waiting
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#7e9cd8]⏸ 1"
}

@test "tmux-ai status uses wait color for working state" {
  state_init
  state_register "%1" agent=claude project=a state=working
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#dca561]⚙ 1"
}

@test "tmux-ai status uses stuck color for stuck state" {
  state_init
  state_register "%1" agent=claude project=a state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#e82424]✗ 1"
}

@test "tmux-ai status suppresses zero counts" {
  state_init
  state_register "%1" agent=claude project=a state=done
  state_register "%2" agent=claude project=b state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  # Only the done segment should appear
  assert_output --partial "✓ 2"
  [[ "$output" != *"⏸"* ]]
  [[ "$output" != *"⚙"* ]]
  [[ "$output" != *"✗"* ]]
}

@test "tmux-ai status ignores idle agents" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}
