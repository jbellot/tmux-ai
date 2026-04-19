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

# state_list drives cursor navigation and numeric-jump in the dashboard
# and sidebar. Those views render rows in object-insertion order
# (`to_entries`), so state_list must match — otherwise initial cursor
# lands mid-list and numeric keys select the wrong row.
@test "state_list preserves insertion order (matches render order)" {
  state_init
  state_register "%9" agent=claude
  state_register "%1" agent=claude
  state_register "%5" agent=claude
  run state_list
  [ "${lines[0]}" = "%9" ]
  [ "${lines[1]}" = "%1" ]
  [ "${lines[2]}" = "%5" ]
}

@test "corrupt state file is moved aside and rebuilt" {
  state_init
  echo "not json at all" > "$(tmux_ai_runtime_dir)/agents.json"
  state_register "%9" agent=claude
  run jq -r '."%9".agent' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "claude"
  # corrupt file should have been moved aside
  run bash -c "ls '$(tmux_ai_runtime_dir)'/agents.json.corrupt.* 2>/dev/null | wc -l"
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

@test "hex_to_truecolor_fg converts #RRGGBB to 38;2;R;G;Bm escape" {
  run hex_to_truecolor_fg '#7e9cd8'
  assert_output $'\033[38;2;126;156;216m'
}

@test "hex_to_truecolor_fg accepts bare 'RRGGBB' too" {
  run hex_to_truecolor_fg '98bb6c'
  assert_output $'\033[38;2;152;187;108m'
}

@test "hex_to_truecolor_fg is lenient on lowercase and uppercase" {
  run hex_to_truecolor_fg '#DCA561'
  assert_output $'\033[38;2;220;165;97m'
}

@test "load_palette with unset options uses Kanagawa Wave defaults" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  # Stub tmux to simulate no options set (all queries return empty).
  cat >"$BATS_TEST_TMPDIR/path/tmux" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/tmux"
  PATH="$BATS_TEST_TMPDIR/path:$PATH" load_palette
  [ "$C_ACCENT" = $'\033[38;2;126;156;216m' ]
  [ "$C_FG"     = $'\033[38;2;220;215;186m' ]
  [ "$C_DIM"    = $'\033[38;2;114;113;105m' ]
  [ "$C_SEP"    = $'\033[38;2;54;54;70m' ]
  [ "$C_OK"     = $'\033[38;2;152;187;108m' ]
  [ "$C_WAIT"   = $'\033[38;2;220;165;97m' ]
  [ "$C_STUCK"  = $'\033[38;2;232;36;36m' ]
  [ "$C_RESET"  = $'\033[0m' ]
  [ "$C_BOLD"   = $'\033[1m' ]
  [ "$C_DIM_ATTR" = $'\033[2m' ]
}

@test "load_palette honors a tmux-provided @tmux-ai-accent override" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  # Stub tmux to return our override for one specific option.
  cat >"$BATS_TEST_TMPDIR/path/tmux" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "show-options" ] && [ "$3" = "@tmux-ai-accent" ]; then
  printf '#ff0000\n'
  exit 0
fi
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/tmux"
  PATH="$BATS_TEST_TMPDIR/path:$PATH" load_palette
  [ "$C_ACCENT" = $'\033[38;2;255;0;0m' ]
}

@test "hex_to_truecolor_fg rejects malformed input with non-zero exit and no output" {
  run hex_to_truecolor_fg "not a hex"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "hex_to_truecolor_fg rejects short hex cleanly" {
  run hex_to_truecolor_fg "#7e9cd"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "load_palette falls back to Kanagawa defaults when a user override is malformed" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat >"$BATS_TEST_TMPDIR/path/tmux" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "show-options" ] && [ "$3" = "@tmux-ai-accent" ]; then
  printf 'not-a-hex\n'
  exit 0
fi
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/tmux"
  PATH="$BATS_TEST_TMPDIR/path:$PATH" load_palette
  # Falls back to the Kanagawa default #7e9cd8 → 126;156;216
  [ "$C_ACCENT" = $'\033[38;2;126;156;216m' ]
}
