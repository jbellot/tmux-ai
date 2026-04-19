# tmux-ai Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current hex-literal, monochrome tmux UI with a palette-driven Kanagawa Wave design (Quiet Minimal direction, plain-Unicode glyphs, single-row left-aligned tabs), and align the dash popup + agents-session sidebar with the same palette.

**Architecture:** Seven `@tmux-ai-*` tmux options hold the palette. `tmux.conf` references them via `#{@tmux-ai-*}`. A new `load_palette` helper in `lib/state.sh` reads the same options and exposes them as `C_ACCENT`, `C_FG`, etc. to the dash and sidebar bash scripts, which move from 8-color ANSI to truecolor (`\033[38;2;R;G;Bm`). `bin/tmux-ai-status` emits truecolor `#[fg=...]` spans for the four agent states.

**Tech Stack:** bash 5, tmux ≥3.2 (truecolor + `#{E:…}` option expansion), jq, bats for tests.

**Spec reference:** `docs/superpowers/specs/2026-04-19-tmux-visual-design.md`

---

## File Plan

| File | Action | Responsibility |
|---|---|---|
| `lib/state.sh` | Modify | Add `hex_to_truecolor_fg` and `load_palette` helpers |
| `tmux.conf` | Modify | Consolidated palette block + palette-driven status bar, borders, tabs |
| `bin/tmux-ai-status` | Modify | Output truecolor `#[fg=...]` spans per agent-state count |
| `bin/tmux-ai-dash` | Modify | Truecolor ANSI from palette; waiting→accent; DND glyph from 🔕 to ◌ |
| `bin/tmux-ai-sidebar` | Modify | Truecolor ANSI from palette; waiting→accent |
| `tests/bats/test_state.bats` | Modify | Assertions for `hex_to_truecolor_fg`, `load_palette` |
| `tests/bats/test_dash.bats` | Modify | Replace 8-color assertions with truecolor palette assertions |
| `tests/bats/test_sidebar.bats` | Modify | Replace 8-color assertions with truecolor palette assertions |
| `tests/bats/test_status_bin.bats` | Create | Cover the new status-line output format |
| `config.toml.example` | Modify | Expand `@tmux-ai-*` docs to cover all seven options |
| `README.md` | Modify | Add Theming subsection |

The palette helper lives in `lib/state.sh` because dash and sidebar already source it. No new lib file needed — YAGNI.

---

## Task 1: Add `hex_to_truecolor_fg` and `load_palette` helpers to lib/state.sh

**Files:**
- Modify: `lib/state.sh` (append at end of file)
- Test: `tests/bats/test_state.bats` (append)

- [ ] **Step 1: Write the failing test for `hex_to_truecolor_fg`**

Append to `tests/bats/test_state.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bats tests/bats/test_state.bats -f hex_to_truecolor_fg`

Expected: FAIL with `command not found: hex_to_truecolor_fg` (or similar).

- [ ] **Step 3: Implement `hex_to_truecolor_fg` in `lib/state.sh`**

Append to `lib/state.sh`:

```bash
# Convert "#RRGGBB" or "RRGGBB" into a truecolor foreground ANSI escape.
# Used by dash + sidebar (which emit ANSI) to stay in lock-step with the
# status bar (which uses tmux's own #[fg=#hex] syntax). We don't do bg
# escapes because the design leaves background at terminal default.
hex_to_truecolor_fg() {
  local hex="${1#\#}"
  local r g b
  r=$((16#${hex:0:2}))
  g=$((16#${hex:2:2}))
  b=$((16#${hex:4:2}))
  printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/bats/test_state.bats -f hex_to_truecolor_fg`

Expected: 3 passing.

- [ ] **Step 5: Write the failing test for `load_palette`**

Append to `tests/bats/test_state.bats`:

```bash
@test "load_palette with unset options uses Kanagawa Wave defaults" {
  load_palette
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
```

- [ ] **Step 6: Run tests to confirm they fail**

Run: `bats tests/bats/test_state.bats -f load_palette`

Expected: FAIL with `command not found: load_palette`.

- [ ] **Step 7: Implement `load_palette` in `lib/state.sh`**

Append to `lib/state.sh`:

```bash
# Read a tmux option with a fallback. Returns the option value, or $2 if
# tmux isn't on PATH / the option is unset. Safe to call outside tmux.
_tmux_opt() {
  local key="$1" default="$2" val
  val=$(tmux show-options -gv "$key" 2>/dev/null || printf '')
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$default"
}

# Populate C_ACCENT, C_FG, C_DIM, C_SEP, C_OK, C_WAIT, C_STUCK with
# truecolor escapes derived from @tmux-ai-<role> options, plus
# C_RESET / C_BOLD / C_DIM_ATTR for convenience.
#
# Defaults are the Kanagawa Wave palette documented in
# docs/superpowers/specs/2026-04-19-tmux-visual-design.md.
load_palette() {
  C_ACCENT=$(hex_to_truecolor_fg "$(_tmux_opt @tmux-ai-accent '#7e9cd8')")
  C_FG=$(hex_to_truecolor_fg     "$(_tmux_opt @tmux-ai-fg     '#dcd7ba')")
  C_DIM=$(hex_to_truecolor_fg    "$(_tmux_opt @tmux-ai-dim    '#727169')")
  C_SEP=$(hex_to_truecolor_fg    "$(_tmux_opt @tmux-ai-sep    '#363646')")
  C_OK=$(hex_to_truecolor_fg     "$(_tmux_opt @tmux-ai-ok     '#98bb6c')")
  C_WAIT=$(hex_to_truecolor_fg   "$(_tmux_opt @tmux-ai-wait   '#dca561')")
  C_STUCK=$(hex_to_truecolor_fg  "$(_tmux_opt @tmux-ai-stuck  '#e82424')")
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM_ATTR=$'\033[2m'
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bats tests/bats/test_state.bats`

Expected: all green (including the two new `load_palette` tests and the three `hex_to_truecolor_fg` tests, plus all pre-existing tests still passing).

- [ ] **Step 9: Commit**

```bash
git add lib/state.sh tests/bats/test_state.bats
git commit -m "$(cat <<'EOF'
feat(state): add hex_to_truecolor_fg + load_palette helpers

Expose the tmux-ai palette to bash scripts as a set of ANSI escape
variables (C_ACCENT, C_FG, C_DIM, C_SEP, C_OK, C_WAIT, C_STUCK) derived
from @tmux-ai-* tmux options with Kanagawa-Wave defaults.
EOF
)"
```

---

## Task 2: Consolidate palette block + palette-driven pane borders in tmux.conf

**Files:**
- Modify: `tmux.conf:28-55` (the "Accents / theme" section)

- [ ] **Step 1: Verify current section with a read**

Run: `sed -n '28,55p' tmux.conf`

Expected: shows the current `@tmux-ai-accent '#82aaff'`, pane-border-style, status-style, window-status-format lines.

- [ ] **Step 2: Replace the palette+borders lines in tmux.conf**

Replace the exact block (tmux.conf lines 28–36) so it reads:

```tmux
# =========================================================================
# Palette — override any @tmux-ai-<role> BEFORE sourcing to retheme.
# Defaults are Kanagawa Wave.
# =========================================================================
set -g @tmux-ai-accent '#7e9cd8'
set -g @tmux-ai-fg     '#dcd7ba'
set -g @tmux-ai-dim    '#727169'
set -g @tmux-ai-sep    '#363646'
set -g @tmux-ai-ok     '#98bb6c'
set -g @tmux-ai-wait   '#dca561'
set -g @tmux-ai-stuck  '#e82424'
set -g @tmux-ai-sidebar-width '32'

# Pane borders — single lines, accent on active only.
set -g pane-border-lines        single
set -g pane-border-style        'fg=#{@tmux-ai-sep}'
set -g pane-active-border-style 'fg=#{@tmux-ai-accent}'
```

The existing status-bar lines (37–55) will be replaced in Task 3; leave them for now.

- [ ] **Step 3: Validate tmux can parse the file**

Run from the repo root:

```bash
tmux -f /dev/null -L tmux-ai-plan-verify start-server \; \
  source-file "$PWD/tmux.conf" \; \
  show-options -g @tmux-ai-accent \; \
  show-options -g pane-active-border-style \; \
  kill-server
```

Expected output (among other lines):

```
@tmux-ai-accent "#7e9cd8"
pane-active-border-style fg=#7e9cd8
```

The `#{@tmux-ai-accent}` reference should have been resolved. If tmux prints `fg=#{@tmux-ai-accent}` literally, that's a failure — the format string didn't expand. In that case, bracketing with `#{E:@tmux-ai-accent}` forces expansion; update the two border lines to `fg=#{E:@tmux-ai-accent}` / `fg=#{E:@tmux-ai-sep}`.

- [ ] **Step 4: Commit**

```bash
git add tmux.conf
git commit -m "$(cat <<'EOF'
feat(tmux.conf): consolidated palette block + palette-driven pane borders

All seven @tmux-ai-<role> options declared at the top of the visual
section; pane-border-style now references them via #{@tmux-ai-*} rather
than hex literals. No behavior change yet — status bar + tabs still use
the old literals and will be migrated in the next commit.
EOF
)"
```

---

## Task 3: Palette-driven status bar, tabs, and DND indicator in tmux.conf

**Files:**
- Modify: `tmux.conf:37-55` (status-style through status-right, plus window-status-format)

- [ ] **Step 1: Replace the status-bar and window-tab block**

Replace tmux.conf lines 37–55 (everything from `# Status bar colors` up to and including the `set -g status-justify centre` line) with:

```tmux
# =========================================================================
# Status bar — transparent bg, left-aligned tabs, palette-driven colors.
# =========================================================================
set -g status-style        'bg=default fg=#{@tmux-ai-fg}'
set -g status-justify      left
set -g status-left-length  60
set -g status-right-length 60
set -g status-interval     2

# Window tabs — underline + accent for active, plain fg for inactive.
# Dot separator between tabs sits on top of an empty window-status-separator
# so the dot only ever appears between (not around) the tabs.
set -g window-status-format \
  '#[fg=#{@tmux-ai-fg}] #I #W #[fg=#{@tmux-ai-sep}]·'
set -g window-status-current-format \
  '#[fg=#{@tmux-ai-accent},underscore] #I #W #[nounderscore,fg=#{@tmux-ai-sep}]·'
set -g window-status-separator ''

# Left: [◌ ] ◉ <session> │
# The DND prefix is conditional on $XDG_RUNTIME_DIR/tmux-ai/dnd.flag and
# uses the wait-amber so it reads as "heads up, notifications are off".
set -g status-left \
  '#{?#(test -f $XDG_RUNTIME_DIR/tmux-ai/dnd.flag && echo 1),#[fg=#{@tmux-ai-wait}]◌ ,}#[fg=#{@tmux-ai-accent},bold]◉ #S #[fg=#{@tmux-ai-sep}]│ '

# Right: agent status (rendered by tmux-ai status) │ HH:MM
set -g status-right \
  '#(~/.local/bin/tmux-ai status) #[fg=#{@tmux-ai-sep}]│ #[fg=#{@tmux-ai-fg}]%H:%M '
```

Note: the `#(test -f … && echo 1)` shell-eval inside `status-left` is the same pattern the current file uses; we keep it so the DND indicator stays reactive without adding a new hook.

- [ ] **Step 2: Validate tmux parses the new status strings**

Run:

```bash
tmux -f /dev/null -L tmux-ai-plan-verify start-server \; \
  source-file "$PWD/tmux.conf" \; \
  show-options -g status-left \; \
  show-options -g status-right \; \
  show-options -g window-status-current-format \; \
  kill-server
```

Expected: each option prints back with no parser error. (`tmux show-options` returns the raw string, not the expanded one — this only verifies syntax. Visual verification happens in Task 9.)

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "$(cat <<'EOF'
feat(tmux.conf): palette-driven status bar, left-aligned tabs, ◌ DND glyph

Status bar switches to status-justify left, transparent bg, single-row
layout. Window tabs lose the '*' suffix and pick up a subtle underline
on active. The DND indicator changes from 🔕 emoji to ◌ in
@tmux-ai-wait amber, matching the plain-Unicode minimal aesthetic.
All colors reference #{@tmux-ai-*} so the file contains zero hex
literals outside the palette block.
EOF
)"
```

---

## Task 4: Rewrite `bin/tmux-ai-status` output format

**Files:**
- Modify: `bin/tmux-ai-status` (full rewrite of `render`)
- Create: `tests/bats/test_status_bin.bats`

- [ ] **Step 1: Create the bats test file with the failing tests**

Write `tests/bats/test_status_bin.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export TMUX_AI_STATUS_NO_DETECT=1
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "tmux-ai status emits empty output when no agents are registered" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}

@test "tmux-ai status emits one segment per non-zero state, in order done/waiting/working/stuck" {
  state_init
  state_register "%1" agent=claude project=a state=done
  state_register "%2" agent=claude project=b state=waiting
  state_register "%3" agent=claude project=c state=working
  state_register "%4" agent=claude project=d state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  # Order: done, waiting, working, stuck
  [[ "$output" == *"●1"*"◐1"*"◑1"*"▲1"* ]]
}

@test "tmux-ai status uses palette-sourced tmux #[fg=] spans" {
  state_init
  state_register "%1" agent=claude project=a state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#98bb6c]●1"
}

@test "tmux-ai status uses accent color for waiting state" {
  state_init
  state_register "%1" agent=claude project=a state=waiting
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#7e9cd8]◐1"
}

@test "tmux-ai status uses wait color for working state" {
  state_init
  state_register "%1" agent=claude project=a state=working
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#dca561]◑1"
}

@test "tmux-ai status uses stuck color for stuck state" {
  state_init
  state_register "%1" agent=claude project=a state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "#[fg=#e82424]▲1"
}

@test "tmux-ai status suppresses zero counts" {
  state_init
  state_register "%1" agent=claude project=a state=done
  state_register "%2" agent=claude project=b state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  # Only the done segment should appear
  assert_output --partial "●2"
  [[ "$output" != *"◐"* ]]
  [[ "$output" != *"◑"* ]]
  [[ "$output" != *"▲"* ]]
}

@test "tmux-ai status ignores idle agents" {
  state_init
  state_register "%1" agent=claude project=a state=idle
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bats tests/bats/test_status_bin.bats`

Expected: tests fail because the current output uses `⚙ foo ⏸ bar ✓ baz` inline format, not `#[fg=...]●N`.

- [ ] **Step 3: Rewrite `bin/tmux-ai-status`**

Replace the body of `bin/tmux-ai-status` (keep the sourcing block at the top; replace from the `ICON_*` definitions through the end of `render`) with:

```bash
#!/usr/bin/env bash
set -u
_SELF="$({ readlink -f "$0" 2>/dev/null; } || { realpath "$0" 2>/dev/null; } || echo "$0")"
_BIN_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$_BIN_DIR/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/config.sh"

# Glyphs (plain Unicode — no Nerd Font assumed).
GLYPH_DONE='●'
GLYPH_WAIT='◐'   # waiting for user input
GLYPH_WORK='◑'   # working (turn in flight)
GLYPH_STUCK='▲'

# Read a tmux option (hex) with a fallback — used to build #[fg=#hex] spans
# directly, since this script outputs tmux format syntax, not ANSI.
_hex_opt() {
  local key="$1" default="$2" val
  val=$(tmux show-options -gv "$key" 2>/dev/null || printf '')
  [ -n "$val" ] && printf '%s' "$val" || printf '%s' "$default"
}

render() {
  state_init
  local file; file="$(_state_file)"
  local count; count=$(jq 'length' "$file" 2>/dev/null || echo 0)
  [ "$count" -eq 0 ] && return 0

  local d w wa s
  d=$(jq  '[.[] | select(.state=="done")]    | length' "$file")
  wa=$(jq '[.[] | select(.state=="waiting")] | length' "$file")
  w=$(jq  '[.[] | select(.state=="working")] | length' "$file")
  s=$(jq  '[.[] | select(.state=="stuck")]   | length' "$file")

  local col_ok col_accent col_wait col_stuck
  col_ok=$(_hex_opt     @tmux-ai-ok     '#98bb6c')
  col_accent=$(_hex_opt @tmux-ai-accent '#7e9cd8')
  col_wait=$(_hex_opt   @tmux-ai-wait   '#dca561')
  col_stuck=$(_hex_opt  @tmux-ai-stuck  '#e82424')

  local out=""
  [ "$d"  -gt 0 ] && out+="#[fg=${col_ok}]${GLYPH_DONE}${d} "
  [ "$wa" -gt 0 ] && out+="#[fg=${col_accent}]${GLYPH_WAIT}${wa} "
  [ "$w"  -gt 0 ] && out+="#[fg=${col_wait}]${GLYPH_WORK}${w} "
  [ "$s"  -gt 0 ] && out+="#[fg=${col_stuck}]${GLYPH_STUCK}${s} "

  printf '%s' "${out% }"
}

mkdir -p "$XDG_STATE_HOME/tmux-ai" 2>/dev/null || true
{
  render
  if [ -z "${TMUX_AI_STATUS_NO_DETECT:-}" ]; then
    "$_BIN_DIR/tmux-ai-detect" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
} 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log" || true
exit 0
```

Note: this removes the old `inline` vs `aggregated` rendering (the `inline_threshold` config key in TOML). The aggregated form is now the only form — simpler, no config branching. That's a deliberate scope decision: the design commits to aggregated glyph+count output.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/bats/test_status_bin.bats`

Expected: 8 passing.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-status tests/bats/test_status_bin.bats
git commit -m "$(cat <<'EOF'
feat(status): palette-driven tmux #[fg=] spans with new glyph set

Rewrites render() to emit one segment per non-zero agent state in a
fixed order (done, waiting-for-input, working, stuck) using glyphs
● ◐ ◑ ▲ and #[fg=#hex] spans derived from @tmux-ai-* options. Idle
agents and zero counts produce no output. Drops the inline/aggregated
threshold branch — aggregated is now the only form.
EOF
)"
```

---

## Task 5: Update `bin/tmux-ai-dash` to truecolor palette + new DND glyph

**Files:**
- Modify: `bin/tmux-ai-dash:22-36` (ANSI palette + `_dash_color_for`) and `:46` (DND line)
- Modify: `tests/bats/test_dash.bats` (update color assertions)

- [ ] **Step 1: Update the dash tests**

In `tests/bats/test_dash.bats`, replace the two ANSI-color tests:

```bash
@test "dash render uses truecolor wait color for working state" {
  state_init
  state_register "%1" agent=claude project=foo state=working turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # @tmux-ai-wait default #dca561 → 220;165;97
  assert_output --partial $'\033[38;2;220;165;97m'
}

@test "dash render uses truecolor stuck color for stuck state" {
  state_init
  state_register "%1" agent=claude project=foo state=stuck turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # @tmux-ai-stuck default #e82424 → 232;36;36
  assert_output --partial $'\033[38;2;232;36;36m'
}

@test "dash render uses accent color for waiting state (replaces magenta)" {
  state_init
  state_register "%1" agent=claude project=foo state=waiting turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # @tmux-ai-accent default #7e9cd8 → 126;156;216
  assert_output --partial $'\033[38;2;126;156;216m'
}
```

Replace the existing `dash render uses ANSI color for working state` and `...for stuck state` tests in place; add the new `accent color for waiting` test.

Also update the DND assertion:

```bash
@test "dash header shows DND indicator when flag present" {
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # New DND glyph: ◌ (replaces 🔕)
  assert_output --partial "◌ DND"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bats tests/bats/test_dash.bats`

Expected: the three color tests fail (looking for truecolor sequences, finding 8-color), and the DND test fails (looking for ◌, finding 🔕).

- [ ] **Step 3: Update `bin/tmux-ai-dash`**

Replace lines 22–36 of `bin/tmux-ai-dash` (from `# ANSI palette (local to render).` through the end of `_dash_color_for() { … }`) with:

```bash
# Truecolor palette — driven by @tmux-ai-* options via load_palette.
load_palette
_DASH_RESET="$C_RESET"
_DASH_DIM="$C_DIM_ATTR"
_DASH_ACCENT="${C_ACCENT}${C_BOLD}"
_DASH_MUTED="$C_DIM"
_dash_color_for() {
  case "$1" in
    working) printf '%s' "$C_WAIT"  ;;
    waiting) printf '%s' "$C_ACCENT" ;;
    done)    printf '%s' "$C_OK"    ;;
    stuck)   printf '%s' "$C_STUCK" ;;
    error)   printf '%s%s' "$C_STUCK" "$C_BOLD" ;;
    *)       printf '%s' "$C_DIM_ATTR" ;;
  esac
}
```

And on the DND header line (previously ~line 46):

```bash
dnd_txt="  ${_DASH_ACCENT}◌ DND on${_DASH_RESET}"
```

(Change the emoji `🔕` to the plain-Unicode `◌`. The accent-bold styling stays so it stands out.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/bats/test_dash.bats`

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-dash tests/bats/test_dash.bats
git commit -m "$(cat <<'EOF'
feat(dash): truecolor palette + waiting-as-accent + ◌ DND glyph

Dash popup now pulls colors from load_palette so they match the status
bar exactly. The waiting state moves from magenta to the accent color
because "needs your attention" is conceptually the accent role in the
Kanagawa palette, and magenta doesn't exist in that palette anyway.
DND header switches from 🔕 to ◌ for aesthetic consistency with the
plain-Unicode status bar.
EOF
)"
```

---

## Task 6: Update `bin/tmux-ai-sidebar` to truecolor palette

**Files:**
- Modify: `bin/tmux-ai-sidebar:17-28` (ANSI palette block) and `:46-55` (`color_for`)
- Modify: `tests/bats/test_sidebar.bats` (update color assertions)

- [ ] **Step 1: Update the sidebar tests**

In `tests/bats/test_sidebar.bats`, replace the three ANSI color tests with:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `bats tests/bats/test_sidebar.bats`

Expected: four color tests fail.

- [ ] **Step 3: Update `bin/tmux-ai-sidebar`**

Replace lines 17–28 of `bin/tmux-ai-sidebar` (from `# ANSI colors — 8-color …` through `C_MUTED=$'\033[2;37m'`) with:

```bash
# Truecolor palette — driven by @tmux-ai-* options via load_palette.
load_palette
ANSI_RESET="$C_RESET"
ANSI_DIM="$C_DIM_ATTR"
ANSI_BOLD="$C_BOLD"
C_WORK="$C_WAIT"
C_WAIT_STATE="$C_ACCENT"
C_DONE="$C_OK"
# C_STUCK already set by load_palette
C_ERROR="${C_STUCK}${C_BOLD}"
C_IDLE="$C_DIM_ATTR"
# C_ACCENT already set by load_palette
C_MUTED="$C_DIM"
```

Replace `color_for` (lines 46–55) with:

```bash
color_for() {
  case "$1" in
    working) printf '%s' "$C_WORK" ;;
    waiting) printf '%s' "$C_WAIT_STATE" ;;
    done)    printf '%s' "$C_DONE" ;;
    stuck)   printf '%s' "$C_STUCK" ;;
    error)   printf '%s' "$C_ERROR" ;;
    idle|*)  printf '%s' "$C_IDLE" ;;
  esac
}
```

The variable renames (`C_WAIT` → `C_WAIT_STATE`) are needed because `load_palette` already exports `C_WAIT` as the amber "wait" palette role — which is exactly the role we want for `working` in this script. The existing `C_WAIT` in the old script meant "waiting for user input" (magenta). We resolve the naming collision by using `C_WAIT_STATE` for the state variable.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/bats/test_sidebar.bats`

Expected: all passing.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-sidebar tests/bats/test_sidebar.bats
git commit -m "$(cat <<'EOF'
feat(sidebar): truecolor palette aligned with status bar

Sidebar now sources load_palette and maps states to the same hex codes
as the status bar. Resolves the naming collision between the palette's
"wait" role (amber, now used for working state) and the old state key
"waiting" (now on the accent color for user-input-needed rows).
EOF
)"
```

---

## Task 7: Expand docs — `config.toml.example` and README Theming

**Files:**
- Modify: `config.toml.example` (tmux-only-options block at the end)
- Modify: `README.md` (add Theming subsection under Config)

- [ ] **Step 1: Expand `config.toml.example`**

Replace the existing tmux-only-options block at the end of `config.toml.example` (lines 28-37) with:

```
# -------------------------------------------------------------------------
# tmux-only options (set via `set -g @option 'value'` in your tmux.conf)
# These are not TOML — they're documented here for discoverability.
# -------------------------------------------------------------------------
#
# The palette below drives the status bar, pane borders, dash popup, and
# agents-session sidebar. Override a role BEFORE sourcing tmux.conf:
#
#   set -g @tmux-ai-accent '#f7768e'   # Tokyo Night pink instead of Kanagawa blue
#
# @tmux-ai-accent          Accent: session name, active tab, active
#                          pane border, "waiting for input" rows.
#                          Default: '#7e9cd8' (Kanagawa wave-blue)
# @tmux-ai-fg              Default foreground (inactive tabs, clock).
#                          Default: '#dcd7ba'
# @tmux-ai-dim             Muted text (footer hints, idle rows).
#                          Default: '#727169'
# @tmux-ai-sep             Hard separators and inactive pane borders.
#                          Default: '#363646'
# @tmux-ai-ok              Agent state "ready/done" (●).
#                          Default: '#98bb6c'
# @tmux-ai-wait            Agent state "working" (◑) and DND glyph (◌).
#                          Default: '#dca561'
# @tmux-ai-stuck           Agent state "stuck" (▲) and "error".
#                          Default: '#e82424'
#
# @tmux-ai-sidebar-width   Agents-session sidebar width in columns.
#                          Default: 32. Example: set -g @tmux-ai-sidebar-width '40'
```

- [ ] **Step 2: Add Theming subsection to README**

Find the `## Config` section in `README.md` and add the following after its existing paragraph:

```markdown
### Theming

The visual surface (status bar, pane borders, dash popup, sidebar) is
driven by seven `@tmux-ai-*` tmux options. The defaults are the
Kanagawa Wave palette. To retheme, set any of them *before* sourcing
`tmux.conf`:

    set -g @tmux-ai-accent '#f7768e'
    set -g @tmux-ai-stuck  '#ff0000'
    source-file ~/path/to/tmux-ai/tmux.conf

See `config.toml.example` for the full list of roles with defaults.
```

- [ ] **Step 3: Commit**

```bash
git add config.toml.example README.md
git commit -m "$(cat <<'EOF'
docs: document all seven @tmux-ai-* palette options

Expands the tmux-options block in config.toml.example to cover every
role in the Kanagawa palette with its default and what it drives.
Adds a Theming subsection to README pointing readers to the reference.
EOF
)"
```

---

## Task 8: Clean up remaining 8-color references (notify, adapters) if any

**Files:**
- Audit: `bin/tmux-ai-notify`, `adapters/generic.sh`, `bin/tmux-ai-spawn`

- [ ] **Step 1: Grep for any remaining 8-color ANSI or `C_WAIT=$'\\033[35m'` patterns**

Run from the repo root:

```bash
grep -rn $'\033\[3[0-9]m\|\033\[1;3[0-9]m' bin/ adapters/ lib/ || echo "none found"
```

Expected: "none found", or the only remaining hits are in test files (which are fine — they assert on what scripts emit).

- [ ] **Step 2: If any non-test file still hardcodes 8-color ANSI**

Replace them the same way as Tasks 5 and 6: source `lib/state.sh`, call `load_palette`, use the `C_*` variables. Add/update a bats test asserting the truecolor codes, then commit separately:

```bash
git commit -m "feat(<script>): migrate remaining 8-color ANSI to load_palette"
```

- [ ] **Step 3: If nothing found, skip to Task 9 without a commit.**

---

## Task 9: Full smoke test in a real tmux server

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `tests/run-tests.sh`

Expected: all green.

- [ ] **Step 2: Source the new config in a throwaway tmux server and attach**

Run (in a terminal with truecolor support):

```bash
tmux -L tmux-ai-smoke -f tmux.conf new-session -d -s demo
tmux -L tmux-ai-smoke set-environment -g PATH "$PWD/bin:$PATH"
tmux -L tmux-ai-smoke attach -t demo
```

From inside the attached session:

1. Open three windows (`prefix + c` twice). Confirm tabs render as `1 bash ·  2 bash ·  3 bash` with the current window underlined + accent blue and inactives in `#dcd7ba`. No `*` suffix anywhere.
2. Confirm left side shows `◉ demo │` in accent bold. No 🔕.
3. Confirm right side shows `14:37` (current time) with a subtle `│` before it. Empty space before the clock because no agents are registered.
4. Split a pane (`prefix + |`). Confirm the active pane border is `#7e9cd8` and inactive is `#363646`.
5. `prefix + D` (toggle DND). Confirm a `◌` in `#dca561` appears to the left of the session name.
6. Register a fake working agent for smoke purposes:

   ```bash
   source lib/common.sh
   source lib/state.sh
   state_init
   state_register "%1" agent=claude project=smoke state=working \
     turn_started_ts=$(($(date +%s)-30))
   ```

   Wait up to 2 seconds (status-interval). Confirm the right side now shows `◑1` in amber between the agent-status placeholder and the clock.
7. `state_set "%1" state done`. Confirm it turns into `●1` in green within 2s.
8. `state_set "%1" state waiting`. Confirm `◐1` in accent blue.
9. `state_set "%1" state stuck`. Confirm `▲1` in red.
10. `prefix + a` (dash popup). Confirm the dash header row is `#7e9cd8` bold, the single row state cell is colored per the same palette, and the `◌ DND on` footer reads in accent if DND is still on.
11. `prefix + g` (agents session). Confirm the sidebar row uses the same palette colors as the dash.
12. Kill the smoke server:

    ```bash
    tmux -L tmux-ai-smoke kill-server
    ```

- [ ] **Step 3: Visual comparison with the design preview**

Open `.superpowers/brainstorm/*/content/preview.html` in a browser. Confirm the real-tmux render matches the three scenarios (normal, DND+stuck, agents session) in:
- Glyph choice
- Color placement
- Relative spacing / separator density

If anything is off, capture a terminal screenshot and open a follow-up TODO — don't fix in this plan.

- [ ] **Step 4: No commit — just confirm the branch is clean of verification artifacts**

Run: `git status`

Expected: no uncommitted changes (other than the pre-existing Phase 2 changes that were already on the branch before this plan).

---

## Self-Review

**Spec coverage:**
- Semantic palette (7 roles) → Task 1 (helpers) + Task 2 (tmux.conf block). ✓
- Status-bar layout (status-justify left, ◉ prefix, DND ◌, window tabs) → Task 3. ✓
- Window tabs (underline active, no `*` suffix) → Task 3. ✓
- Pane borders (palette-driven, single lines) → Task 2. ✓
- Dash popup truecolor + waiting→accent + ◌ DND glyph → Task 5. ✓
- Sidebar truecolor + waiting→accent → Task 6. ✓
- `bin/tmux-ai-status` new output format → Task 4. ✓
- File organization (palette block at top, no hex literals downstream) → Task 2 + Task 3. ✓
- `config.toml.example` expanded → Task 7. ✓
- README Theming section → Task 7. ✓
- Tests updated (state, dash, sidebar, status) → Tasks 1, 4, 5, 6. ✓
- Non-goals (keybinds, install, Nerd Font) → none of these tasks touch them. ✓
- Acceptance criteria (zero hex literals in tmux.conf outside palette, overrides propagate, dash/sidebar match status bar, tests pass, scenarios match preview) → verified in Task 9. ✓
- Remaining 8-color cleanup (notify, adapters) → Task 8 audit. ✓

**Placeholder scan:** no TBDs, no "handle edge cases" hand-waves, every code step shows the code.

**Type consistency:**
- `load_palette` exports `C_ACCENT`, `C_FG`, `C_DIM`, `C_SEP`, `C_OK`, `C_WAIT`, `C_STUCK`, `C_RESET`, `C_BOLD`, `C_DIM_ATTR` — referenced consistently in Tasks 5 and 6.
- `hex_to_truecolor_fg` signature `(hex_string) → escape` — used consistently in Task 1's tests and in `load_palette`.
- Glyph constants `GLYPH_DONE ● / GLYPH_WAIT ◐ / GLYPH_WORK ◑ / GLYPH_STUCK ▲` match the spec's "Status Output Format" table.
- One naming collision deliberately resolved in Task 6: `load_palette`'s `C_WAIT` (amber, palette role) vs sidebar's old `C_WAIT` (magenta, state for "waiting for input"). The state variable is renamed to `C_WAIT_STATE` and explicitly flagged in the task.
