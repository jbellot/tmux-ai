#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PATH="$PROJECT_ROOT/tests/stubs:$PATH"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
}

@test "tmux stub records a call" {
  tmux display-message "hello"
  run cat "$TMUX_STUB_CALLS"
  assert_output 'display-message hello'
}

@test "tmux stub returns canned output for a command" {
  echo "list-panes::%5 claude" >> "$TMUX_STUB_RESPONSES"
  run tmux list-panes
  assert_output "%5 claude"
}

@test "tmux stub returns empty for unknown command with no response" {
  run tmux some-obscure-command
  assert_success
  assert_output ""
}
