#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "tmux_ai_runtime_dir returns XDG_RUNTIME_DIR/tmux-ai and creates it" {
  run tmux_ai_runtime_dir
  assert_success
  assert_output "$XDG_RUNTIME_DIR/tmux-ai"
  [ -d "$XDG_RUNTIME_DIR/tmux-ai" ]
}

@test "tmux_ai_state_dir creates \$XDG_STATE_HOME/tmux-ai" {
  tmux_ai_state_dir >/dev/null
  [ -d "$XDG_STATE_HOME/tmux-ai" ]
}

@test "tmux_ai_log appends timestamped line to tmux-ai.log" {
  tmux_ai_log "hello world"
  run cat "$XDG_STATE_HOME/tmux-ai/tmux-ai.log"
  assert_output --partial "hello world"
}

@test "tmux_ai_log never exits non-zero even if log dir is readonly" {
  mkdir -p "$XDG_STATE_HOME/tmux-ai"
  chmod 0500 "$XDG_STATE_HOME/tmux-ai"
  run tmux_ai_log "boom"
  chmod 0700 "$XDG_STATE_HOME/tmux-ai"  # cleanup
  assert_success
}
