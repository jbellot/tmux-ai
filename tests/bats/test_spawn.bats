#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  # split-window returns a pane id
  cat > "$TMUX_STUB_RESPONSES" <<EOF
split-window::%42
EOF
  : > "$TMUX_STUB_CALLS"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "spawn claude creates registry entry and installs hooks" {
  cd "$BATS_TEST_TMPDIR"
  git init -q .
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run state_get "%42" agent
  assert_output "claude"
  # settings file should have been written
  [ -f "$XDG_RUNTIME_DIR/tmux-ai/claude-settings/%42.json" ]
}

@test "spawn sends keys to run the agent command" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run grep -c 'send-keys' "$TMUX_STUB_CALLS"
  # expect at least one send-keys call
  [ "$output" -ge 1 ]
}

@test "spawn sets pipe-pane for log capture" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run grep -c 'pipe-pane' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
}

@test "spawn passes --settings flag with the per-pane file path" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  # The send-keys call should contain "--settings" and reference %42.json
  run grep -F -- '--settings' "$TMUX_STUB_CALLS"
  assert_success
  run grep -F -- '%42.json' "$TMUX_STUB_CALLS"
  assert_success
}

@test "spawn sends a single-line command (no embedded newlines)" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  # The send-keys call for the spawn command should be on one logical line.
  # Find the send-keys line and check it doesn't contain a literal newline
  # inside the quoted command.
  local send_keys_line
  send_keys_line=$(grep 'send-keys' "$TMUX_STUB_CALLS" | grep 'claude' | head -1)
  [ -n "$send_keys_line" ]
  # The stub records one call per line; if send-keys had embedded newlines,
  # it would show as multiple lines. There should be exactly ONE 'send-keys'
  # line containing 'claude'.
  run bash -c "grep -c 'send-keys.*claude' '$TMUX_STUB_CALLS'"
  assert_output "1"
}
