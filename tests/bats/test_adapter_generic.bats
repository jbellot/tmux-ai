#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # tmux stub that serves canned capture-pane output
  mkdir -p "$BATS_TEST_TMPDIR/path"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/adapters/generic.sh"
  export TMUX_AI_NOTIFY_BIN="$PROJECT_ROOT/bin/tmux-ai-notify"
}

@test "generic_tick transitions idle->working when bytes grow" {
  state_init
  state_register "%5" agent=claude state=idle last_byte_count=100 last_byte_ts=1000
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "working"
}

@test "generic_tick transitions working->done when bytes quiescent past idle_after_seconds" {
  state_init
  local now past
  now=$(date +%s)
  past=$((now - 10))
  state_register "%5" agent=claude state=working last_byte_count=500 last_byte_ts="$past"
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "done"
}

@test "generic_tick transitions working->stuck when quiet past stuck_after_seconds" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[detection]
stuck_after_seconds = 5
idle_after_seconds = 999
EOF
  state_init
  local now past
  now=$(date +%s)
  past=$((now - 10))
  state_register "%5" agent=claude state=working last_byte_count=500 last_byte_ts="$past"
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "stuck"
}
