#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"

  # Install a no-op tmux stub on PATH so load_palette falls back to
  # hardcoded Kanagawa defaults instead of reading the user's live tmux.
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat >"$BATS_TEST_TMPDIR/path/tmux" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"

  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "sidebar --render empty state shows the 'no agents' hint" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  assert_output --partial "no agents"
  assert_output --partial "prefix + A"
}

@test "sidebar --render lists one row per agent with project name" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "sidebar --render emits truecolor wait color for working state" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # @tmux-ai-wait default #dca561 → 220;165;97
  assert_output --partial $'\033[38;2;220;165;97m'
}

@test "sidebar --render emits truecolor ok color for done state" {
  state_init
  state_register "%1" agent=claude project=foo state=done
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # @tmux-ai-ok default #98bb6c → 152;187;108
  assert_output --partial $'\033[38;2;152;187;108m'
}

@test "sidebar --render emits truecolor stuck color for stuck state" {
  state_init
  state_register "%1" agent=claude project=foo state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # @tmux-ai-stuck default #e82424 → 232;36;36
  assert_output --partial $'\033[38;2;232;36;36m'
}

@test "sidebar --render uses accent color for waiting state" {
  state_init
  state_register "%1" agent=claude project=foo state=waiting
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # @tmux-ai-accent default #7e9cd8 → 126;156;216
  assert_output --partial $'\033[38;2;126;156;216m'
}

@test "sidebar --render shows cursor on selected row" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  TMUX_AI_SIDEBAR_SELECTED="%2" run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  [[ "$output" == *"▸"*"bar"* ]] || [[ "$output" == *"bar"*"▸"* ]]
}

@test "sidebar --render is byte-identical across two renders of the same state" {
  state_init
  state_register "%1" agent=claude project=foo state=working registered_ts=1000 last_byte_ts=1000
  out1=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  out2=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  [ "$out1" = "$out2" ]
}

@test "sidebar_next_pane returns the pane after the current one" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  state_register "%3" agent=claude project=c state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_next_pane "%1"
  assert_output "%2"
  run sidebar_next_pane "%2"
  assert_output "%3"
  # Wraps to first
  run sidebar_next_pane "%3"
  assert_output "%1"
}

@test "sidebar_prev_pane returns the pane before the current one" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  state_register "%3" agent=claude project=c state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_prev_pane "%2"
  assert_output "%1"
  # Wraps to last
  run sidebar_prev_pane "%1"
  assert_output "%3"
}

@test "sidebar_nth_pane returns the Nth pane (1-indexed)" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  state_register "%2" agent=claude project=b state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_nth_pane 1
  assert_output "%1"
  run sidebar_nth_pane 2
  assert_output "%2"
  # Out of bounds returns empty
  run sidebar_nth_pane 99
  assert_output ""
}

# Nth/first pane must line up with the displayed rows, even when pane
# ids aren't in lexicographic order (e.g. %9 registered before %1).
@test "sidebar_nth_pane follows insertion order, not lexicographic" {
  state_init
  state_register "%9" agent=claude project=first state=idle
  state_register "%1" agent=claude project=second state=idle
  state_register "%5" agent=claude project=third state=idle
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  run sidebar_nth_pane 1
  assert_output "%9"
  run sidebar_first_pane
  assert_output "%9"
}

# sidebar_jump must target the pane id directly so tmux resolves
# session+window+pane in one shot. Using a session name alone leaves
# the client on the session's previously-active window/pane — the user
# wanted the agent, not "somewhere in its session".
@test "sidebar_jump switches client using the pane id" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"

  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/config.sh"

  state_init
  state_register "%7" agent=claude project=foo session=other-session
  source "$PROJECT_ROOT/bin/tmux-ai-sidebar"
  sidebar_jump "%7"
  run grep -cF 'switch-client -t %7' "$TMUX_STUB_CALLS"
  assert_output "1"
}
