#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # silent notify-send
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  export TMUX_AI_NOTIFY_BIN="$PROJECT_ROOT/bin/tmux-ai-notify"
}

@test "full lifecycle: register -> prompt_submit -> stop" {
  state_init
  state_register "%77" agent=claude project=e2e state=idle cwd="$PWD"

  TMUX_PANE="%77" \
  TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
  "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "prompt_submit"

  run state_get "%77" state
  assert_output "working"

  TMUX_PANE="%77" \
  TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
  "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "stop"

  run state_get "%77" state
  assert_output "done"
}

@test "status renders after full lifecycle" {
  state_init
  state_register "%77" agent=claude project=e2e state=idle
  export TMUX_AI_STATUS_NO_DETECT=1

  TMUX_PANE="%77" TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
    "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "prompt_submit"

  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "e2e"
}

@test "dash renders the live agent" {
  state_init
  state_register "%77" agent=claude project=e2e state=working turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "e2e"
  assert_output --partial "working"
}
