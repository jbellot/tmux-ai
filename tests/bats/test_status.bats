#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  export TMUX_AI_STATUS_NO_DETECT=1
  # Put the tmux stub in PATH so _hex_opt falls back to hardcoded defaults.
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "status prints empty when no agents registered" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}

@test "status emits palette #[fg=] spans with glyph+count for active states" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#98bb6c]✓ 1"
  assert_output --partial "#[fg=#dca561]⚙ 1"
}

@test "status aggregates counts for many agents" {
  state_init
  state_register "%1" agent=claude project=a state=working
  state_register "%2" agent=claude project=b state=working
  state_register "%3" agent=claude project=c state=waiting
  state_register "%4" agent=claude project=d state=done
  state_register "%5" agent=claude project=e state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "✓ 2"
  assert_output --partial "⏸ 1"
  assert_output --partial "⚙ 2"
}
