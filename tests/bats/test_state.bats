#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "state_init creates empty agents.json" {
  state_init
  run cat "$(tmux_ai_runtime_dir)/agents.json"
  assert_output '{}'
}

@test "state_register adds a new entry keyed by pane id" {
  state_init
  state_register "%5" agent=claude project=foo cwd=/tmp pane=%5 state=idle
  run jq -r '."%5".agent' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "claude"
  run jq -r '."%5".state' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "idle"
}

@test "state_set updates a single field" {
  state_init
  state_register "%5" agent=claude state=idle
  state_set "%5" state working
  run jq -r '."%5".state' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "working"
}

@test "state_get returns a field" {
  state_init
  state_register "%5" agent=claude state=idle
  run state_get "%5" agent
  assert_output "claude"
}

@test "state_unregister removes an entry" {
  state_init
  state_register "%5" agent=claude
  state_unregister "%5"
  run jq 'has("%5")' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "false"
}

@test "state_list emits each pane id on its own line" {
  state_init
  state_register "%5" agent=claude
  state_register "%7" agent=claude
  run state_list
  assert_line "%5"
  assert_line "%7"
}

@test "corrupt state file is moved aside and rebuilt" {
  state_init
  echo "not json at all" > "$(tmux_ai_runtime_dir)/agents.json"
  state_register "%9" agent=claude
  run jq -r '."%9".agent' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "claude"
  # corrupt file should have been moved aside
  run bash -c 'ls "$(tmux_ai_runtime_dir)"/agents.json.corrupt.* 2>/dev/null | wc -l'
  assert_output "1"
}

@test "concurrent state_register calls don't lose writes" {
  state_init
  for i in $(seq 1 20); do
    state_register "%${i}" agent=claude &
  done
  wait
  run jq 'length' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "20"
}
