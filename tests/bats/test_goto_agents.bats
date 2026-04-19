#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  export TMUX_STUB_EXITS="$BATS_TEST_TMPDIR/tmux_exits"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
  : > "$TMUX_STUB_EXITS"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
}

@test "goto-agents creates session when absent" {
  echo "has-session::1" > "$TMUX_STUB_EXITS"
  "$PROJECT_ROOT/bin/tmux-ai-goto-agents" --ensure
  run grep -c 'new-session' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
  run grep -c 'split-window' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
}

@test "goto-agents is a no-op when session already exists" {
  echo "has-session::0" > "$TMUX_STUB_EXITS"
  "$PROJECT_ROOT/bin/tmux-ai-goto-agents" --ensure
  run grep -c 'new-session' "$TMUX_STUB_CALLS"
  assert_output "0"
}

@test "goto-agents --ensure never calls switch-client" {
  echo "has-session::1" > "$TMUX_STUB_EXITS"
  "$PROJECT_ROOT/bin/tmux-ai-goto-agents" --ensure
  run grep -c 'switch-client' "$TMUX_STUB_CALLS"
  assert_output "0"
}

@test "goto-agents without --ensure calls switch-client after creating" {
  echo "has-session::1" > "$TMUX_STUB_EXITS"
  "$PROJECT_ROOT/bin/tmux-ai-goto-agents"
  run grep -c 'switch-client' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
}

@test "goto-agents without --ensure calls switch-client when session already exists" {
  echo "has-session::0" > "$TMUX_STUB_EXITS"
  "$PROJECT_ROOT/bin/tmux-ai-goto-agents"
  run grep -c 'switch-client' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
  run grep -c 'new-session' "$TMUX_STUB_CALLS"
  assert_output "0"
}
