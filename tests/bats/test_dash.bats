#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "dash render emits a header row and one line per agent" {
  state_init
  local now; now=$(date +%s)
  state_register "%1" agent=claude project=foo state=working window=main pane_index=1.0 turn_started_ts=$((now-60))
  state_register "%2" agent=claude project=bar state=done    window=main pane_index=1.1 turn_started_ts=$((now-300))
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "STATE"
  assert_output --partial "AGENT"
  assert_output --partial "PROJECT"
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "dash render shows 'no agents' when registry empty" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "no agents"
}

@test "dash render uses ANSI color for working state" {
  state_init
  state_register "%1" agent=claude project=foo state=working turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial $'\033[33m'
}

@test "dash render uses ANSI color for stuck state" {
  state_init
  state_register "%1" agent=claude project=foo state=stuck turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial $'\033[31m'
}

@test "dash render draws a unicode box frame" {
  state_init
  state_register "%1" agent=claude project=foo state=done
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "─"
}

@test "dash header shows agent count" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "2 agents"
}

@test "dash header shows DND indicator when flag present" {
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "DND"
}

@test "dash --render shows selection cursor on first row by default" {
  state_init
  state_register "%1" agent=claude project=foo state=working turn_started_ts="$(date +%s)"
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "▸"
}

@test "dash --render moves cursor via TMUX_AI_DASH_SELECTED env" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  TMUX_AI_DASH_SELECTED="%2" run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  [[ "$output" == *"▸"*"bar"* ]] || [[ "$output" == *"bar"*"▸"* ]]
}

# Pressing Enter on a row must leave the client on that exact pane.
# Targeting the session alone lands on whatever window/pane that
# session had last, not the registered agent's pane.
@test "dash_jump switches client using the pane id" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"

  state_init
  state_register "%7" agent=claude project=foo session=other-session
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/bin/tmux-ai-dash"
  dash_jump "%7"
  run grep -cF 'switch-client -t %7' "$TMUX_STUB_CALLS"
  assert_output "1"
}
