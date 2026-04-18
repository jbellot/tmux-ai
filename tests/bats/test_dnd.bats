#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "tmux-ai-dnd toggle creates flag when absent" {
  "$PROJECT_ROOT/bin/tmux-ai-dnd" toggle
  [ -f "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag" ]
}

@test "tmux-ai-dnd toggle removes flag when present" {
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  "$PROJECT_ROOT/bin/tmux-ai-dnd" toggle
  [ ! -f "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag" ]
}

@test "tmux-ai-dnd status reports on/off" {
  run "$PROJECT_ROOT/bin/tmux-ai-dnd" status
  assert_output "off"
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  run "$PROJECT_ROOT/bin/tmux-ai-dnd" status
  assert_output "on"
}
