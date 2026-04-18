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
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  # no-op notify-send
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
}

@test "auto-register: unknown pane running claude gets registered with generic adapter" {
  state_init
  # tmux list-panes returns one pane %10 running 'claude' with cwd /tmp
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  run state_get "%10" agent
  assert_output "claude"
  run state_get "%10" adapter
  assert_output "generic"
}

@test "detect skips already-registered panes" {
  state_init
  state_register "%10" agent=claude adapter=claude state=idle last_byte_count=0 last_byte_ts="$(date +%s)"
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  # adapter should still be 'claude', not overwritten
  run state_get "%10" adapter
  assert_output "claude"
}

@test "detect skips panes whose process is not a known agent" {
  state_init
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 vim /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  local state_file
  state_file="$(tmux_ai_runtime_dir)/agents.json"
  run bash -c "jq 'length' '$state_file'"
  assert_output "0"
}

@test "detect garbage-collects registered panes that no longer exist" {
  state_init
  state_register "%10" agent=claude adapter=claude state=done
  state_register "%11" agent=claude adapter=claude state=idle
  # tmux list-panes only returns %10 — %11 has died
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  local state_file
  state_file="$(tmux_ai_runtime_dir)/agents.json"
  # %11 should be gone
  run bash -c "jq 'has(\"%11\")' '$state_file'"
  assert_output "false"
  # %10 should remain
  run bash -c "jq 'has(\"%10\")' '$state_file'"
  assert_output "true"
}
