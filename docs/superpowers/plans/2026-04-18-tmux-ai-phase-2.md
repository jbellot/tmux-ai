# tmux-ai Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship tmux-ai v0.2: a complete opinionated tmux config + a dedicated "agents" session (sidebar on the left, open-ended shell on the right) + a polished popup dashboard with colors and row-jump. Preserves every Phase 1 keybinding, state layer, and hook pipeline.

**Architecture:** A new `tmux.conf` (theme/status/copy-mode/pane ergonomics) becomes the top-level config and sources the existing `tmux-ai.tmux.conf`. Two new bash scripts — `tmux-ai-sidebar` (narrow-pane interactive status) and `tmux-ai-goto-agents` (ensure + switch) — wire the agents session together. Dashboard gets ANSI colors, a box-drawing frame, and keyboard row-selection/jump. `install.sh` gains a `--full` mode that symlinks the user's `~/.tmux.conf` with a timestamped backup.

**Tech Stack:** bash ≥ 4, tmux ≥ 3.2, `jq`, `flock`, `fzf` (optional for sidebar `d` confirmation), `xclip`/`pbcopy` (optional for copy-mode yank). Tests in `bats-core` with `bats-assert` / `bats-support`.

**Spec reference:** `docs/superpowers/specs/2026-04-18-tmux-ai-phase-2-design.md`.

---

## File structure produced by this plan

```
tmux-config/
├── tmux.conf                       NEW — full daily-driver
├── tmux-ai.tmux.conf               KEPT — sourced from tmux.conf
├── bin/
│   ├── tmux-ai                     extended (new `goto` subcommand)
│   ├── tmux-ai-dash                polished (colors, frame, selection, jump)
│   ├── tmux-ai-sidebar             NEW
│   ├── tmux-ai-goto-agents         NEW
│   └── ... (Phase 1 unchanged)
├── lib/                            unchanged
├── adapters/                       unchanged
├── config.toml.example             extended
├── install.sh                      extended (--full mode)
├── tests/
│   ├── bats/
│   │   ├── test_sidebar.bats       NEW
│   │   ├── test_goto_agents.bats   NEW
│   │   ├── test_install_full.bats  NEW
│   │   ├── test_dash.bats          extended (colors, selection)
│   │   ├── test_dispatcher.bats    extended (goto subcommand)
│   │   └── ... (Phase 1 unchanged)
│   └── stubs/
│       └── tmux                    extended (exit-code support)
├── README.md                       extended
└── TESTING.md                      extended
```

Each task is self-contained. Tasks are intentionally ordered by dependency: the tmux stub enhancement (Task 1) unblocks all goto-agents/session tests; `tmux-ai-goto-agents` (Task 4) unblocks the `prefix + g` binding (Task 5); sidebar rendering (Task 6) precedes interactive loop (Task 7); etc.

---

## Task 1: Extend the tmux stub to support canned exit codes

**Why:** `tmux-ai-goto-agents` calls `tmux has-session -t agents` and branches on its exit code (0 = session exists, non-zero = missing). The current stub always exits 0, so goto-agents tests can't distinguish the two cases. We add a `TMUX_STUB_EXITS` file parallel to `TMUX_STUB_RESPONSES` that maps `subcommand -> exit_code`.

**Files:**
- Modify: `tests/stubs/tmux`
- Test: `tests/bats/test_tmux_stub.bats` (extend)

- [ ] **Step 1: Extend the test with a new case for exit codes**

Add this test AT THE END of `tests/bats/test_tmux_stub.bats`:

```bash
@test "tmux stub honours TMUX_STUB_EXITS per subcommand" {
  export TMUX_STUB_EXITS="$BATS_TEST_TMPDIR/tmux_exits"
  echo "has-session::1" > "$TMUX_STUB_EXITS"
  run tmux has-session -t agents
  [ "$status" -eq 1 ]
  # Default subcommand still exits 0
  run tmux list-panes
  assert_success
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_tmux_stub.bats
```

Expected: the new test fails — stub always exits 0.

- [ ] **Step 3: Modify `tests/stubs/tmux`**

Replace the whole stub with this expanded version:

```bash
#!/usr/bin/env bash
# Recording tmux stub for unit tests.
# - Appends each call to $TMUX_STUB_CALLS (one line per call)
# - Emits canned output from $TMUX_STUB_RESPONSES (key "subcmd::output")
# - Exits with canned code from $TMUX_STUB_EXITS (key "subcmd::code")

set -u
calls="${TMUX_STUB_CALLS:-/dev/null}"
responses="${TMUX_STUB_RESPONSES:-/dev/null}"
exits="${TMUX_STUB_EXITS:-/dev/null}"

printf '%s\n' "$*" >> "$calls" 2>/dev/null || true

# Output lookup
if [ -f "$responses" ] && [ $# -gt 0 ]; then
  while IFS= read -r line; do
    key="${line%%::*}"
    rest="${line#*::}"
    if [ "$key" = "$1" ]; then
      printf '%s\n' "$rest"
      break
    fi
  done < "$responses"
fi

# Exit code lookup
if [ -f "$exits" ] && [ $# -gt 0 ]; then
  while IFS= read -r line; do
    key="${line%%::*}"
    rest="${line#*::}"
    if [ "$key" = "$1" ]; then
      exit "$rest"
    fi
  done < "$exits"
fi

exit 0
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_tmux_stub.bats
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add tests/stubs/tmux tests/bats/test_tmux_stub.bats
git commit -m "test(stub): add per-subcommand exit-code support to tmux stub"
```

---

## Task 2: Write the full `tmux.conf`

**Why:** The spec's "full opinionated config" replaces the Phase-1 snippet. This task lays down the base (theme, pane ergonomics, copy mode, status bar, Phase-1 keybindings preserved). Hooks and `prefix + g` land in later tasks that depend on files not yet created.

**Files:**
- Create: `tmux.conf`

- [ ] **Step 1: Write `tmux.conf`**

```tmux
# tmux-ai — full daily-driver config.
#
# This file is the single entrypoint. It sources the agent-layer
# snippet (tmux-ai.tmux.conf) at the bottom.
#
# Users: symlink this from ~/.tmux.conf (via `./install.sh --full`)
#        or source-file it from your own tmux.conf.

# =========================================================================
# Core behaviour
# =========================================================================
set -g prefix C-b
bind C-b send-prefix

set -g mouse on
set -g escape-time 0
set -g history-limit 50000
set -g focus-events on

set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

set -g default-terminal 'tmux-256color'
set -ga terminal-overrides ',*256col*:Tc'
set -ga terminal-features 'xterm-256color:RGB'

# =========================================================================
# Accents / theme
# =========================================================================
set -g @tmux-ai-accent '#82aaff'
set -g @tmux-ai-sidebar-width '32'

# Pane borders
set -g pane-border-style 'fg=#4c4c4c'
set -g pane-active-border-style 'fg=#82aaff'

# Status bar colors
set -g status-style 'bg=default fg=#c0c0c0'
set -g status-left-length 40
set -g status-right-length 80
set -g status-interval 2

# Window tab format
set -g window-status-format '#[fg=#808080] #I:#W '
set -g window-status-current-format '#[fg=#82aaff,bold] #I:#W* '

# Left: [session] with DND-aware 🔕 prefix when active
set -g status-left '#{?#{&&:#{!=:#{e|+:0:#(test -f $XDG_RUNTIME_DIR/tmux-ai/dnd.flag && echo 1 || echo 0)}:0},1},🔕 ,}#[fg=#82aaff,bold]#S #[fg=#4c4c4c]│ '

# Right: agent status segment + 24h clock
set -g status-right ' #(~/.local/bin/tmux-ai status) #[fg=#4c4c4c]│ #[fg=#c0c0c0]%H:%M'

# Center
set -g status-justify centre

# =========================================================================
# Pane / window ergonomics
# =========================================================================
# Splits that keep cwd; original % and " remain available
bind | split-window -h -c '#{pane_current_path}'
bind -   split-window -v -c '#{pane_current_path}'

# Vim-ish pane movement (arrows still work)
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Pane resize
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Reload
bind r source-file ~/.tmux.conf \; display-message 'config reloaded'

# =========================================================================
# Copy mode (vi keys + system clipboard)
# =========================================================================
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi V send -X select-line

# Pick the first available clipboard backend.
if-shell 'command -v pbcopy >/dev/null' \
  "bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'pbcopy'" \
  "if-shell 'command -v xclip >/dev/null' \
     \"bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'xclip -selection clipboard'\" \
     \"bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'cat >/dev/null'\""

# =========================================================================
# Agent layer — source the existing snippet
# =========================================================================
source-file '#{d:current_file}/tmux-ai.tmux.conf'
```

Note the last line uses tmux's `#{d:current_file}` format to resolve the directory of the current config file at load time — keeps the reference portable whether the file is symlinked or sourced.

- [ ] **Step 2: Verify tmux can parse the file**

Outside a tmux session (or in a throwaway test server):

```bash
tmux -L phase2-check -f "$(pwd)/tmux.conf" new-session -d -s test 2>&1 | head -5
tmux -L phase2-check kill-server 2>/dev/null
```

Expected: no syntax errors. The status bar and clipboard if-shell chains should parse cleanly.

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "feat: add full opinionated tmux.conf with agent layer sourced at bottom"
```

---

## Task 3: Switch install.sh's marker block to source `tmux.conf`

**Why:** Now that `tmux.conf` exists, the default (non-`--full`) install mode should source it instead of `tmux-ai.tmux.conf`.

**Files:**
- Modify: `install.sh`
- Test: `tests/bats/test_install.bats` (extend)

- [ ] **Step 1: Extend the existing test**

Append this test to `tests/bats/test_install.bats`:

```bash
@test "install.sh marker block sources tmux.conf not tmux-ai.tmux.conf" {
  "$PROJECT_ROOT/install.sh"
  run grep -F "source-file $PROJECT_ROOT/tmux.conf" "$HOME/.tmux.conf"
  assert_success
  run grep -F "source-file $PROJECT_ROOT/tmux-ai.tmux.conf" "$HOME/.tmux.conf"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_install.bats
```

Expected: the new test fails. Existing 5 tests still pass.

- [ ] **Step 3: Modify `install.sh`**

Find the line in `do_install()` that currently reads:

```bash
      echo "source-file $PROJECT_DIR/tmux-ai.tmux.conf"
```

and replace it with:

```bash
      echo "source-file $PROJECT_DIR/tmux.conf"
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_install.bats
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/bats/test_install.bats
git commit -m "feat(install): default source-file now points at full tmux.conf"
```

---

## Task 4: `bin/tmux-ai-goto-agents` — ensure + switch

**Role:** Idempotently create the `agents` session with the sidebar layout, optionally switch the client to it.

**Files:**
- Create: `bin/tmux-ai-goto-agents`
- Test: `tests/bats/test_goto_agents.bats`

- [ ] **Step 1: Write `tests/bats/test_goto_agents.bats`**

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_goto_agents.bats
```

Expected: all 5 fail (script missing).

- [ ] **Step 3: Implement `bin/tmux-ai-goto-agents`**

```bash
#!/usr/bin/env bash
# Ensure the `agents` session exists (creating it if not), and optionally
# switch the current client to it.
#
# Usage:
#   tmux-ai-goto-agents            # ensure + switch
#   tmux-ai-goto-agents --ensure   # ensure only
#
# Safe to invoke from tmux hooks (swallows all errors, always exits 0).

set -u

_SELF="$({ readlink -f "$0" 2>/dev/null; } || { realpath "$0" 2>/dev/null; } || echo "$0")"
_BIN_DIR="$(cd "$(dirname "$_SELF")" && pwd)"

ensure_only=0
if [ "${1:-}" = "--ensure" ]; then
  ensure_only=1
fi

ensure_session() {
  if tmux has-session -t agents 2>/dev/null; then
    return 0
  fi
  # Create with sidebar as the initial pane; then split a main pane to the right.
  tmux new-session -d -s agents -n main "$_BIN_DIR/tmux-ai-sidebar" 2>/dev/null || return 0
  tmux split-window -h -t agents:main -c "$HOME" 2>/dev/null || true
  local sidebar_w
  sidebar_w="$(tmux show-options -gv @tmux-ai-sidebar-width 2>/dev/null || true)"
  [ -n "$sidebar_w" ] || sidebar_w=32
  tmux resize-pane -t agents:main.1 -x "$sidebar_w" 2>/dev/null || true
  tmux select-pane -t agents:main.2 2>/dev/null || true
}

main() {
  ensure_session
  if [ "$ensure_only" -eq 0 ]; then
    tmux switch-client -t agents 2>/dev/null || true
  fi
}

{ main; } 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-goto-agents
tests/run-tests.sh tests/bats/test_goto_agents.bats
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-goto-agents tests/bats/test_goto_agents.bats
git commit -m "feat(bin): add tmux-ai-goto-agents for agents-session ensure/switch"
```

---

## Task 5: Add `goto` subcommand + `prefix + g` keybind + session hooks

**Why:** Connects `tmux-ai-goto-agents` to the user via (a) a CLI verb (`tmux-ai goto`) and (b) a tmux keybind. Also wires in the `client-attached` hook for auto-provisioning and the `session-closed` hook for recovery.

**Files:**
- Modify: `bin/tmux-ai`
- Modify: `tmux.conf`
- Test: `tests/bats/test_dispatcher.bats` (extend)

- [ ] **Step 1: Extend `tests/bats/test_dispatcher.bats`**

Modify the existing `tmux-ai help lists subcommands` test to also expect `goto`:

```bash
@test "tmux-ai help lists subcommands" {
  run "$PROJECT_ROOT/bin/tmux-ai" help
  assert_output --partial "spawn"
  assert_output --partial "dash"
  assert_output --partial "dnd"
  assert_output --partial "status"
  assert_output --partial "detect"
  assert_output --partial "list"
  assert_output --partial "log"
  assert_output --partial "goto"
}
```

Append this new test (uses a new `TMUX_AI_BIN_DIR` env override to point the dispatcher at a stubbed directory — we also add that override in Step 3 below):

```bash
@test "tmux-ai goto delegates to tmux-ai-goto-agents with args" {
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat > "$BATS_TEST_TMPDIR/path/tmux-ai-goto-agents" <<'STUB'
#!/usr/bin/env bash
echo "goto-agents called with: $*"
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/tmux-ai-goto-agents"
  TMUX_AI_BIN_DIR="$BATS_TEST_TMPDIR/path" \
    run "$PROJECT_ROOT/bin/tmux-ai" goto --ensure
  assert_output --partial "--ensure"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dispatcher.bats
```

Expected: `help lists subcommands` and the new `goto` test both fail.

- [ ] **Step 3: Modify `bin/tmux-ai`**

**Change 3a (BIN_DIR override).** Near the top of the script, the line currently reads:

```bash
BIN_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
```

Replace with:

```bash
BIN_DIR="${TMUX_AI_BIN_DIR:-$(cd "$(dirname "$_SELF")" && pwd)}"
```

This lets tests point the dispatcher at a stub directory.

**Change 3b (usage text).** In the `usage()` heredoc, update:

Current:
```
  log <pane_id>         Open the agent log for <pane_id> in \$PAGER
  help                  Show this message
```

Change to:
```
  log <pane_id>         Open the agent log for <pane_id> in \$PAGER
  goto [--ensure]       Switch to the "agents" session (create if missing)
  help                  Show this message
```

**Change 3c (dispatch case).**

Current:
```bash
  log)    shift; cmd_log "$@" ;;
  help|-h|--help) usage ;;
```

Change to:
```bash
  log)    shift; cmd_log "$@" ;;
  goto)   shift; exec "$BIN_DIR/tmux-ai-goto-agents" "$@" ;;
  help|-h|--help) usage ;;
```

- [ ] **Step 4: Append agents-session hooks and `prefix + g` keybind to `tmux.conf`**

Open `tmux.conf` and insert this block just above the final `source-file '#{d:current_file}/tmux-ai.tmux.conf'` line:

```tmux
# =========================================================================
# Agents session — auto-provision + jump
# =========================================================================
bind g run-shell '~/.local/bin/tmux-ai goto'

# Provision the agents session in the background on first attach.
set-hook -g client-attached 'run-shell -b "~/.local/bin/tmux-ai goto --ensure"'

# If the user accidentally kills the agents session, recreate it.
set-hook -g session-closed 'run-shell -b "~/.local/bin/tmux-ai goto --ensure"'
```

- [ ] **Step 5: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_dispatcher.bats
```

Expected: 6 passed (5 existing + 1 new).

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-ai tmux.conf tests/bats/test_dispatcher.bats
git commit -m "feat(tmux): add goto subcommand, prefix+g binding, and agents-session hooks"
```

---

## Task 6: `bin/tmux-ai-sidebar` — renderer only (no interactive loop)

**Why:** Split sidebar into "render a frame" (testable, pure) and "interactive loop" (harder to test). Task 6 ships the renderer with a `--render` flag; Task 7 adds the loop.

**Files:**
- Create: `bin/tmux-ai-sidebar`
- Test: `tests/bats/test_sidebar.bats`

- [ ] **Step 1: Write `tests/bats/test_sidebar.bats`**

```bash
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

@test "sidebar --render emits ANSI color for working state" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 33 = yellow in the 8-color palette
  assert_output --partial $'\033[33m'
}

@test "sidebar --render emits ANSI color for done state" {
  state_init
  state_register "%1" agent=claude project=foo state=done
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 32 = green
  assert_output --partial $'\033[32m'
}

@test "sidebar --render emits ANSI color for stuck state" {
  state_init
  state_register "%1" agent=claude project=foo state=stuck
  run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # 31 = red
  assert_output --partial $'\033[31m'
}

@test "sidebar --render shows cursor on selected row" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  TMUX_AI_SIDEBAR_SELECTED="%2" run "$PROJECT_ROOT/bin/tmux-ai-sidebar" --render
  # The cursor glyph ▸ should appear on the bar row, not on foo.
  # Simplest: the line containing 'bar' also contains the cursor marker.
  [[ "$output" == *"▸"*"bar"* ]] || [[ "$output" == *"bar"*"▸"* ]]
}

@test "sidebar --render is byte-identical across two renders of the same state" {
  state_init
  state_register "%1" agent=claude project=foo state=working registered_ts=1000 last_byte_ts=1000
  out1=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  out2=$("$PROJECT_ROOT/bin/tmux-ai-sidebar" --render)
  [ "$out1" = "$out2" ]
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_sidebar.bats
```

Expected: all 7 fail.

- [ ] **Step 3: Implement `bin/tmux-ai-sidebar`** (render only — interactive loop in Task 7)

```bash
#!/usr/bin/env bash
# tmux-ai sidebar — narrow-pane live status view.
# This task (Task 6) ships the renderer only. Interactive loop arrives in Task 7.

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

# ANSI colors — 8-color + bold for max terminal compatibility.
ANSI_RESET=$'\033[0m'
ANSI_DIM=$'\033[2m'
ANSI_BOLD=$'\033[1m'
C_WORK=$'\033[33m'     # yellow
C_WAIT=$'\033[35m'     # magenta
C_DONE=$'\033[32m'     # green
C_STUCK=$'\033[31m'    # red
C_ERROR=$'\033[1;31m'  # red bold
C_IDLE=$'\033[2m'      # dim
C_ACCENT=$'\033[1;34m' # blue bold
C_MUTED=$'\033[2;37m'  # dim white

ICON_WORK="⚙"
ICON_WAIT="⏸"
ICON_DONE="✓"
ICON_STUCK="✗"
ICON_ERROR="!"
ICON_IDLE="·"
CURSOR="▸"
CURSOR_EMPTY=" "

sidebar_width() {
  local w
  w="$(tmux show-options -gv @tmux-ai-sidebar-width 2>/dev/null || true)"
  [ -n "$w" ] || w=32
  printf '%s\n' "$w"
}

color_for() {
  case "$1" in
    working) printf '%s' "$C_WORK" ;;
    waiting) printf '%s' "$C_WAIT" ;;
    done)    printf '%s' "$C_DONE" ;;
    stuck)   printf '%s' "$C_STUCK" ;;
    error)   printf '%s' "$C_ERROR" ;;
    idle|*)  printf '%s' "$C_IDLE" ;;
  esac
}

icon_for() {
  case "$1" in
    working) printf '%s' "$ICON_WORK" ;;
    waiting) printf '%s' "$ICON_WAIT" ;;
    done)    printf '%s' "$ICON_DONE" ;;
    stuck)   printf '%s' "$ICON_STUCK" ;;
    error)   printf '%s' "$ICON_ERROR" ;;
    idle|*)  printf '%s' "$ICON_IDLE" ;;
  esac
}

fmt_elapsed() {
  local start now diff mm ss hh
  start="${1:-0}"
  [ "$start" = "" ] && start=0
  [ "$start" -eq 0 ] && { printf '  -  '; return; }
  now=$(date +%s)
  diff=$((now - start))
  mm=$((diff / 60))
  ss=$((diff % 60))
  if [ "$mm" -ge 100 ]; then
    hh=$((mm / 60))
    mm=$((mm % 60))
    printf '%02d:%02d' "$hh" "$mm"
  else
    printf '%02d:%02d' "$mm" "$ss"
  fi
}

# Truncate a string to N visible chars, adding … if cut.
trunc() {
  local s="$1" n="$2"
  if [ "${#s}" -le "$n" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:$((n - 1))}"
  fi
}

render_empty() {
  local w; w=$(sidebar_width)
  local pad_top=2 pad_center
  pad_center=$(( (w - 10) / 2 ))  # "no agents" is 9 chars
  [ "$pad_center" -lt 0 ] && pad_center=0
  printf '\n\n%*sno agents\n\n' "$pad_center" ""
  pad_center=$(( (w - 19) / 2 ))  # "prefix + A to spawn"
  [ "$pad_center" -lt 0 ] && pad_center=0
  printf '%s%*sprefix + A to spawn%s\n' "$C_MUTED" "$pad_center" "" "$ANSI_RESET"
}

render() {
  state_init
  local file; file="$(_state_file)"
  local count; count=$(jq 'length' "$file" 2>/dev/null || echo 0)
  local selected="${TMUX_AI_SIDEBAR_SELECTED:-}"
  local w; w=$(sidebar_width)

  if [ "$count" -eq 0 ]; then
    render_empty
    return 0
  fi

  # Title strip
  printf '%s%s agents%s\n' "$C_ACCENT" "$count" "$ANSI_RESET"
  printf '%s\n' "$(printf '%*s' "$w" '' | tr ' ' '─')"

  # One row per entry
  local entry pane state project turn icon color cursor proj_col
  # Available width for project name: total - (cursor 1 + space 1 + icon 1 + space 1 + elapsed 5 + space 1) = 10 overhead
  proj_col=$(( w - 10 ))
  [ "$proj_col" -lt 4 ] && proj_col=4

  while IFS= read -r entry; do
    pane=$(echo    "$entry" | jq -r '.key')
    state=$(echo   "$entry" | jq -r '.value.state // "idle"')
    project=$(echo "$entry" | jq -r '.value.project // .key')
    turn=$(echo    "$entry" | jq -r '.value.turn_started_ts // 0')
    icon="$(icon_for "$state")"
    color="$(color_for "$state")"
    if [ "$pane" = "$selected" ]; then
      cursor="$CURSOR"
    else
      cursor="$CURSOR_EMPTY"
    fi
    local project_padded
    project_padded=$(printf '%-*s' "$proj_col" "$(trunc "$project" "$proj_col")")
    printf '%s %s%s%s %s %s\n' \
      "$cursor" \
      "$color" "$icon" "$ANSI_RESET" \
      "$project_padded" \
      "$(fmt_elapsed "$turn")"
  done < <(jq -c 'to_entries[]' "$file")

  # Footer
  printf '\n'
  printf '%s[j/k] move  [Enter] jump%s\n' "$C_MUTED" "$ANSI_RESET"
  printf '%s[d] unreg  [r] refresh%s\n' "$C_MUTED" "$ANSI_RESET"
}

if [ "${1:-}" = "--render" ]; then
  render
  exit 0
fi

# Interactive mode placeholder — Task 7 replaces this.
render
echo
echo "(interactive loop lands in Task 7)"
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-sidebar
tests/run-tests.sh tests/bats/test_sidebar.bats
```

Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-sidebar tests/bats/test_sidebar.bats
git commit -m "feat(bin): add tmux-ai-sidebar renderer with ANSI colors and cursor"
```

---

## Task 7: Sidebar interactive loop (cursor motion + jump)

**Why:** Task 6 shipped the renderer. Now we add the while-loop that polls for keypresses, moves the cursor, jumps to agents, and redraws only when state/cursor changes.

**Files:**
- Modify: `bin/tmux-ai-sidebar`
- Test: `tests/bats/test_sidebar.bats` (extend)

- [ ] **Step 1: Add tests for cursor movement helpers**

Append these tests to `tests/bats/test_sidebar.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_sidebar.bats
```

Expected: 3 new tests fail (functions not defined).

- [ ] **Step 3: Replace the interactive placeholder in `bin/tmux-ai-sidebar`**

Replace the last section of `bin/tmux-ai-sidebar` (the `if [ "${1:-}" = "--render" ]` block and the placeholder below it) with:

```bash
# ========== Helpers used by the interactive loop ==========

# Return pane-id following the given one (wraps).
sidebar_next_pane() {
  local cur="$1" first="" prev="" found=0
  while IFS= read -r p; do
    [ -z "$first" ] && first="$p"
    if [ "$found" -eq 1 ]; then
      printf '%s\n' "$p"
      return 0
    fi
    [ "$p" = "$cur" ] && found=1
    prev="$p"
  done < <(state_list)
  printf '%s\n' "$first"
}

sidebar_prev_pane() {
  local cur="$1" prev="" last=""
  while IFS= read -r p; do
    if [ "$p" = "$cur" ] && [ -n "$prev" ]; then
      printf '%s\n' "$prev"
      return 0
    fi
    prev="$p"
    last="$p"
  done < <(state_list)
  # If cur is first (or absent) wrap to last
  printf '%s\n' "$last"
}

sidebar_nth_pane() {
  local n="$1" i=0
  while IFS= read -r p; do
    i=$((i + 1))
    if [ "$i" -eq "$n" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done < <(state_list)
  return 0
}

sidebar_first_pane() {
  state_list | head -n 1
}

# Jump to the real agent pane via tmux switch-client + select-pane.
sidebar_jump() {
  local pane="$1"
  [ -n "$pane" ] || return 0
  local session window
  session="$(state_get "$pane" session)"
  window="$(state_get "$pane" window)"
  if [ -n "$session" ]; then
    tmux switch-client -t "$session" 2>/dev/null || true
  fi
  tmux select-pane -t "$pane" 2>/dev/null || true
}

# ========== Interactive loop ==========

interactive_loop() {
  # Hide cursor; restore on exit.
  printf '\033[?25l'
  trap 'printf "\033[?25h\033[2J\033[H"; exit' EXIT INT TERM

  # Force full redraw on resize.
  trap 'last_hash=""' WINCH

  printf '\033[2J\033[H'

  local selected last_hash="" frame cur_hash key
  selected="$(sidebar_first_pane)"

  while true; do
    TMUX_AI_SIDEBAR_SELECTED="$selected" \
      frame="$(render)"
    cur_hash="${#frame}:$(printf '%s' "$frame" | cksum)"

    if [ "$cur_hash" != "$last_hash" ]; then
      printf '\033[H%s\033[J' "$frame"
      last_hash="$cur_hash"
    fi

    if read -t 1 -n 1 -s key 2>/dev/null; then
      case "$key" in
        j) selected="$(sidebar_next_pane "$selected")" ;;
        k) selected="$(sidebar_prev_pane "$selected")" ;;
        g) selected="$(sidebar_first_pane)" ;;
        G) selected="$(state_list | tail -n 1)" ;;
        [1-9])
          local nth
          nth="$(sidebar_nth_pane "$key")"
          if [ -n "$nth" ]; then
            selected="$nth"
            sidebar_jump "$selected"
          fi
          ;;
        '')  sidebar_jump "$selected" ;;     # Enter
        r) last_hash="" ;;                   # force redraw
        d)
          if [ -n "$selected" ]; then
            # Minimal confirm: print prompt inline, wait for y/n.
            printf '\033[%d;1HUnregister %s? (y/n) ' "$(tput lines 2>/dev/null || echo 24)" "$selected"
            read -n 1 -s confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
              state_unregister "$selected"
              selected="$(sidebar_first_pane)"
            fi
            last_hash=""
          fi
          ;;
        q) : ;;  # reserved — no-op for now, clears any pending action
      esac
    fi

    # If selected is gone (unregistered elsewhere), fall back to first.
    if [ -n "$selected" ] && [ -z "$(state_get "$selected" agent)" ]; then
      selected="$(sidebar_first_pane)"
      last_hash=""
    fi
  done
}

if [ "${1:-}" = "--render" ]; then
  render
  exit 0
fi

# Default: run the interactive loop.
interactive_loop
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_sidebar.bats
```

Expected: 10 passed (7 from Task 6 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-sidebar tests/bats/test_sidebar.bats
git commit -m "feat(sidebar): add interactive loop with cursor motion and jump-to-agent"
```

---

## Task 8: Dashboard — ANSI colors in STATE column + box frame

**Why:** First half of the dashboard polish. Leaves selection/jump for Task 9.

**Files:**
- Modify: `bin/tmux-ai-dash`
- Test: `tests/bats/test_dash.bats` (extend)

- [ ] **Step 1: Add color + frame tests**

Append to `tests/bats/test_dash.bats`:

```bash
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
  # Corner glyphs appear
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: 5 new tests fail.

- [ ] **Step 3: Modify `bin/tmux-ai-dash`**

Replace the `render()` function (lines currently from `render() {` to the closing `}`) with this enhanced version. Leave every other line of the file alone:

```bash
# ANSI palette (local to render).
_DASH_RESET=$'\033[0m'
_DASH_DIM=$'\033[2m'
_DASH_ACCENT=$'\033[1;34m'
_DASH_MUTED=$'\033[2;37m'
_dash_color_for() {
  case "$1" in
    working) printf '\033[33m' ;;
    waiting) printf '\033[35m' ;;
    done)    printf '\033[32m' ;;
    stuck)   printf '\033[31m' ;;
    error)   printf '\033[1;31m' ;;
    *)       printf '\033[2m' ;;
  esac
}

render() {
  state_init
  local file; file="$(_state_file)"
  local count; count=$(jq 'length' "$file" 2>/dev/null || echo 0)

  # Header
  local dnd_txt=""
  if [ -f "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag" ]; then
    dnd_txt="  ${_DASH_ACCENT}🔕 DND on${_DASH_RESET}"
  fi

  if [ "$count" -eq 0 ]; then
    printf '%stmux-ai — no agents registered%s%s\n\n' "$_DASH_ACCENT" "$_DASH_RESET" "$dnd_txt"
    printf '%s[q] quit%s\n' "$_DASH_MUTED" "$_DASH_RESET"
    return 0
  fi

  # Top of frame
  printf '%s┌─ tmux-ai — %d agents%s%s ─' "$_DASH_ACCENT" "$count" "$_DASH_RESET" "$dnd_txt"
  local i
  for i in $(seq 1 40); do printf '─'; done
  printf '┐\n'

  # Column header
  printf '│  %-7s  %-8s  %-15s  %-12s  %-8s │\n' "STATE" "AGENT" "PROJECT" "WIN:PANE" "ELAPSED"
  printf '├──────────────────────────────────────────────────────────────┤\n'

  # Rows
  local entry state agent project win pane_idx turn color
  while IFS= read -r entry; do
    state=$(echo    "$entry" | jq -r '.value.state // "?"')
    agent=$(echo    "$entry" | jq -r '.value.agent // "?"')
    project=$(echo  "$entry" | jq -r '.value.project // "?"')
    win=$(echo      "$entry" | jq -r '.value.window // "?"')
    pane_idx=$(echo "$entry" | jq -r '.value.pane_index // "?"')
    turn=$(echo     "$entry" | jq -r '.value.turn_started_ts // 0')
    color="$(_dash_color_for "$state")"
    printf '│  %s%-7s%s  %-8s  %-15s  %-12s  %-8s │\n' \
      "$color" "$state" "$_DASH_RESET" \
      "$agent" "$project" "$win:$pane_idx" "$(fmt_elapsed "$turn")"
  done < <(jq -c 'to_entries[]' "$file")

  # Bottom
  printf '└'
  for i in $(seq 1 62); do printf '─'; done
  printf '┘\n'

  # Footer
  printf '\n%s[j/k] select  [Enter] jump  [q] quit%s\n' "$_DASH_MUTED" "$_DASH_RESET"
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: 7 passed (2 original + 5 new).

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-dash tests/bats/test_dash.bats
git commit -m "feat(dash): add ANSI colors, box frame, and DND indicator"
```

---

## Task 9: Dashboard — selection cursor + jump on Enter

**Why:** The popup's `interactive_loop` currently falls through to an fzf picker on Enter. We replace it with in-place row selection that highlights a row and jumps to the selected agent.

**Files:**
- Modify: `bin/tmux-ai-dash`
- Test: `tests/bats/test_dash.bats` (extend)

- [ ] **Step 1: Add selection-cursor test**

Append to `tests/bats/test_dash.bats`:

```bash
@test "dash --render shows selection cursor on first row by default" {
  state_init
  state_register "%1" agent=claude project=foo state=working turn_started_ts="$(date +%s)"
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # The cursor glyph ▸ should appear on the first data line
  assert_output --partial "▸"
}

@test "dash --render moves cursor via TMUX_AI_DASH_SELECTED env" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  TMUX_AI_DASH_SELECTED="%2" run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  # ▸ should be on the bar line
  [[ "$output" == *"▸"*"bar"* ]] || [[ "$output" == *"bar"*"▸"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: 2 new tests fail.

- [ ] **Step 3: Modify render() to honor `TMUX_AI_DASH_SELECTED`**

Replace the row-printing block inside `render()` to include a cursor column:

Change this line in the column header:
```bash
  printf '│  %-7s  %-8s  %-15s  %-12s  %-8s │\n' "STATE" "AGENT" "PROJECT" "WIN:PANE" "ELAPSED"
```
to:
```bash
  printf '│ %s %-7s  %-8s  %-15s  %-12s  %-8s │\n' " " "STATE" "AGENT" "PROJECT" "WIN:PANE" "ELAPSED"
```

Inside the `while IFS= read -r entry` loop, change the row-print line from:
```bash
    printf '│  %s%-7s%s  %-8s  %-15s  %-12s  %-8s │\n' \
      "$color" "$state" "$_DASH_RESET" \
      "$agent" "$project" "$win:$pane_idx" "$(fmt_elapsed "$turn")"
```

to (adding a selector read + prefix glyph):
```bash
    local pane cursor
    pane=$(echo "$entry" | jq -r '.key')
    if [ "$pane" = "${TMUX_AI_DASH_SELECTED:-}" ]; then
      cursor="▸"
    elif [ -z "${TMUX_AI_DASH_SELECTED:-}" ]; then
      # Default selection = first row; detect by checking if we haven't emitted a cursor yet.
      if [ -z "${_dash_cursor_emitted:-}" ]; then
        cursor="▸"
        _dash_cursor_emitted=1
      else
        cursor=" "
      fi
    else
      cursor=" "
    fi
    printf '│ %s %s%-7s%s  %-8s  %-15s  %-12s  %-8s │\n' \
      "$cursor" "$color" "$state" "$_DASH_RESET" \
      "$agent" "$project" "$win:$pane_idx" "$(fmt_elapsed "$turn")"
```

Also at the top of `render()`, reset the cursor-emitted flag:
```bash
render() {
  local _dash_cursor_emitted=""
  state_init
  ...
```

- [ ] **Step 4: Replace `interactive_loop` to track selection and jump**

Replace the entire `interactive_loop()` function in `bin/tmux-ai-dash` with:

```bash
interactive_loop() {
  printf '\033[?25l'
  trap 'printf "\033[?25h\033[2J\033[H"; exit' EXIT INT TERM

  printf '\033[2J\033[H'

  local selected last_hash="" frame cur_hash key
  selected="$(state_list | head -n 1)"

  while true; do
    TMUX_AI_DASH_SELECTED="$selected" \
      frame="$(render)"
    cur_hash="${#frame}:$(printf '%s' "$frame" | cksum)"

    if [ "$cur_hash" != "$last_hash" ]; then
      printf '\033[H%s\033[J' "$frame"
      last_hash="$cur_hash"
    fi

    if read -t 1 -n 1 -s key 2>/dev/null; then
      case "$key" in
        q|Q) exit 0 ;;
        j)
          # next pane (no wrap — cursor stays on last if at end)
          local next
          next="$(state_list | awk -v cur="$selected" '{if (prev==cur) {print; exit} prev=$0}')"
          [ -n "$next" ] && selected="$next"
          ;;
        k)
          local prev
          prev="$(state_list | awk -v cur="$selected" '{if ($0==cur) {print last; exit} last=$0}')"
          [ -n "$prev" ] && selected="$prev"
          ;;
        [1-9])
          local nth
          nth="$(state_list | sed -n "${key}p")"
          [ -n "$nth" ] && selected="$nth"
          ;;
        '')  # Enter
          if [ -n "$selected" ]; then
            local session; session="$(state_get "$selected" session)"
            [ -n "$session" ] && tmux switch-client -t "$session" 2>/dev/null
            tmux select-pane -t "$selected" 2>/dev/null
          fi
          exit 0
          ;;
      esac
    fi
  done
}
```

- [ ] **Step 5: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: 9 passed (7 from Task 8 + 2 new).

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-ai-dash tests/bats/test_dash.bats
git commit -m "feat(dash): add selection cursor and jump-on-Enter (no fzf needed)"
```

---

## Task 10: `install.sh --full` with timestamped backup

**Files:**
- Modify: `install.sh`
- Test: `tests/bats/test_install_full.bats`

- [ ] **Step 1: Write `tests/bats/test_install_full.bats`**

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
}

@test "--full creates ~/.tmux.conf symlink to project tmux.conf" {
  "$PROJECT_ROOT/install.sh" --full
  [ -L "$HOME/.tmux.conf" ]
  target=$(readlink "$HOME/.tmux.conf")
  [ "$target" = "$PROJECT_ROOT/tmux.conf" ]
}

@test "--full backs up pre-existing non-symlink .tmux.conf" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  # A backup file should exist
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  [ "$output" -ge 1 ]
  # The backup contains the original content
  run bash -c "cat '$HOME'/.tmux.conf.bak.*"
  assert_output --partial "my personal config"
}

@test "--full twice does not create a second backup" {
  echo "original" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  sleep 1  # ensure a new timestamp would differ
  "$PROJECT_ROOT/install.sh" --full
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  assert_output "1"
}

@test "--uninstall after --full removes symlink and restores backup" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  "$PROJECT_ROOT/install.sh" --uninstall
  [ ! -L "$HOME/.tmux.conf" ]
  run cat "$HOME/.tmux.conf"
  assert_output --partial "my personal config"
}

@test "--uninstall --no-restore removes symlink but leaves backup in place" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  "$PROJECT_ROOT/install.sh" --uninstall --no-restore
  [ ! -e "$HOME/.tmux.conf" ]
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  [ "$output" -ge 1 ]
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_install_full.bats
```

Expected: all 5 fail.

- [ ] **Step 3: Modify `install.sh` to add `--full`, backup, and restore logic**

Add these helpers near the top of the script, right after the `DEPS=(...)` line (or after `MARKER_END=...` if that's clearer in the existing layout):

```bash
do_full_install() {
  mkdir -p "$BIN_DEST" "$XDG_CONFIG_HOME/tmux-ai"

  # Symlink bins (same as do_install).
  for s in "${BIN_SCRIPTS[@]}"; do
    ln -sf "$PROJECT_DIR/bin/$s" "$BIN_DEST/$s"
  done

  # Write config.toml if absent.
  if [ ! -f "$XDG_CONFIG_HOME/tmux-ai/config.toml" ]; then
    cp "$PROJECT_DIR/config.toml.example" "$XDG_CONFIG_HOME/tmux-ai/config.toml"
  fi

  # Backup + symlink ~/.tmux.conf.
  local target="$PROJECT_DIR/tmux.conf"
  if [ -L "$TMUX_CONF" ]; then
    # If the symlink already points at our target, nothing to do.
    local cur; cur="$(readlink "$TMUX_CONF")"
    if [ "$cur" = "$target" ]; then
      echo "tmux-ai: ~/.tmux.conf already symlinked to $target"
    else
      rm -f "$TMUX_CONF"
      ln -s "$target" "$TMUX_CONF"
    fi
  elif [ -f "$TMUX_CONF" ]; then
    local ts; ts="$(date +%Y%m%d-%H%M%S)"
    mv "$TMUX_CONF" "${TMUX_CONF}.bak.${ts}"
    ln -s "$target" "$TMUX_CONF"
    echo "tmux-ai: backed up existing ~/.tmux.conf to ~/.tmux.conf.bak.${ts}"
  else
    ln -s "$target" "$TMUX_CONF"
  fi

  echo "tmux-ai installed (full mode). Reload: tmux source-file ~/.tmux.conf"
}

do_full_uninstall() {
  # Remove symlinked bins.
  for s in "${BIN_SCRIPTS[@]}"; do
    rm -f "$BIN_DEST/$s"
  done

  # If ~/.tmux.conf is our symlink, remove it.
  local restored=0
  if [ -L "$TMUX_CONF" ]; then
    rm -f "$TMUX_CONF"
    # Restore most-recent backup unless --no-restore.
    if [ "${1:-}" != "--no-restore" ]; then
      local latest
      latest="$(ls -1t "${TMUX_CONF}".bak.* 2>/dev/null | head -n 1)"
      if [ -n "$latest" ]; then
        mv "$latest" "$TMUX_CONF"
        echo "tmux-ai: restored $latest to ~/.tmux.conf"
        restored=1
      fi
    fi
  fi

  # Also clean the marker block (Phase-1 compatibility path).
  if [ "$restored" -eq 0 ] && [ -f "$TMUX_CONF" ] && grep -qF "$MARKER_BEGIN" "$TMUX_CONF"; then
    local tmp; tmp="$(mktemp)"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip
    ' "$TMUX_CONF" > "$tmp"
    mv "$tmp" "$TMUX_CONF"
  fi

  echo "tmux-ai uninstalled."
}
```

Now update the dispatch `case` at the bottom of `install.sh`. Current:

```bash
case "${1:-install}" in
  install|'') do_check || true; do_install ;;
  --check|check) do_check ;;
  --uninstall|uninstall) do_uninstall ;;
  *) echo "usage: install.sh [install|--check|--uninstall]" >&2; exit 2 ;;
esac
```

Replace with:

```bash
case "${1:-install}" in
  install|'') do_check || true; do_install ;;
  --full|full) do_check || true; do_full_install ;;
  --check|check) do_check ;;
  --uninstall|uninstall)
    shift || true
    # Route to the right uninstaller based on current state.
    if [ -L "$TMUX_CONF" ]; then
      do_full_uninstall "${1:-}"
    else
      do_uninstall
    fi
    ;;
  *) echo "usage: install.sh [install|--full|--check|--uninstall [--no-restore]]" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_install.bats tests/bats/test_install_full.bats
```

Expected: 6 + 5 = 11 passed.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/bats/test_install_full.bats
git commit -m "feat(install): add --full mode with timestamped backup and auto-restore on uninstall"
```

---

## Task 11: Extend `config.toml.example` with new tmux-option shims

**Why:** Document the two new tmux options users can override (`@tmux-ai-accent`, `@tmux-ai-sidebar-width`). These are tmux `set` options, not TOML keys — so we just document them in a comment block at the bottom of the example file.

**Files:**
- Modify: `config.toml.example`

- [ ] **Step 1: Append documentation block to `config.toml.example`**

Add this block at the end of the file:

```toml

# -------------------------------------------------------------------------
# tmux-only options (set via `set -g @option 'value'` in your tmux.conf)
# These are not TOML — they're documented here for discoverability.
# -------------------------------------------------------------------------
# @tmux-ai-accent          Accent color used in sidebar/dashboard/status.
#                          Default: '#82aaff' (cool blue).
#                          Example: set -g @tmux-ai-accent '#f7768e'
#
# @tmux-ai-sidebar-width   Sidebar width in columns in the agents session.
#                          Default: 32. Example: set -g @tmux-ai-sidebar-width '40'
```

- [ ] **Step 2: Verify the file parses cleanly for existing keys**

```bash
# Quick sanity: the existing config_get still reads known sections.
source lib/common.sh
source lib/config.sh
XDG_CONFIG_HOME="$(pwd)" mkdir -p ./tmux-ai && cp config.toml.example ./tmux-ai/config.toml
XDG_CONFIG_HOME="$(pwd)" config_get notifications desktop false
# Expected output: true
rm -rf ./tmux-ai
```

- [ ] **Step 3: Commit**

```bash
git add config.toml.example
git commit -m "docs: document @tmux-ai-accent and @tmux-ai-sidebar-width tmux options"
```

---

## Task 12: Extend README and TESTING.md for Phase 2

**Files:**
- Modify: `README.md`
- Modify: `TESTING.md`

- [ ] **Step 1: Add a Phase-2 section to `README.md`**

Replace the "Install" section content with:

```markdown
## Install

Requires: `bash`, `tmux >= 3.2`, `jq`, `flock`, `fzf`, and a desktop
notification binary (`notify-send` on Linux, `osascript` on macOS).
Optional: `xclip` (Linux) or `pbcopy` (macOS) for copy-mode yank to
system clipboard.

Two install modes:

    # Additive mode: source our tmux.conf from your own ~/.tmux.conf
    ./install.sh --check       # dep scan
    ./install.sh               # symlinks bin/*, appends source-file block to ~/.tmux.conf

    # Full mode: symlink ~/.tmux.conf → our tmux.conf (backing up any existing one)
    ./install.sh --full

Reload tmux to pick up changes:

    tmux source-file ~/.tmux.conf

Uninstall (restores most-recent backup in full mode):

    ./install.sh --uninstall
    ./install.sh --uninstall --no-restore   # keep symlink removed, don't restore
```

Add a new section after the "Usage" section:

```markdown
## Agents session

`prefix + g` switches to the `agents` session (auto-created on first
tmux attach). The session has a narrow sidebar on the left showing
every registered agent, and an open shell on the right for you to use
however you like.

Inside the sidebar pane:

- `j` / `k` — move cursor up/down
- `1..9` — jump by row number
- `Enter` — switch to the selected agent's real pane
- `d` + `y` — unregister the selected agent
- `r` — force refresh

Agents themselves still live in whatever session/window you spawn them
from (`prefix + A` stays in the current window). The sidebar is a live
monitor + teleport hub, not a workspace.
```

- [ ] **Step 2: Add a Phase-2 section to `TESTING.md`**

Append this block to the end of `TESTING.md`:

```markdown
## Phase 2 smoke checklist

Run after any Phase-2 change. Requires a live tmux session.

- [ ] `./install.sh --full` on a machine with an existing `~/.tmux.conf`
      creates a `~/.tmux.conf.bak.<timestamp>` and symlinks the conf.
- [ ] Restart tmux server and attach; within ~1s the `agents` session
      appears in `tmux ls` (created by the `client-attached` hook).
- [ ] `prefix + g` switches to the agents session. Left pane is the
      sidebar at 32 cols; right pane is a shell.
- [ ] `prefix + A` from any other session spawns an agent there.
      Within ~2s the sidebar lists the new agent with its project name.
- [ ] Press `j` in the sidebar → cursor moves down. `Enter` →
      current client switches to the agent's real session/pane.
- [ ] `d` in the sidebar prompts to unregister; `y` confirms; agent
      row disappears.
- [ ] `prefix + a` popup shows the same agents with a box frame,
      colored STATE column, a selection cursor on the first row.
- [ ] Popup `j`/`k` moves cursor; `Enter` jumps and closes popup.
- [ ] `./install.sh --uninstall` removes the symlink and restores the
      timestamped backup.
```

- [ ] **Step 3: Commit**

```bash
git add README.md TESTING.md
git commit -m "docs: document Phase 2 — agents session, full install mode, smoke checklist"
```

---

## Task 13: Final full-suite test run + milestone tag

- [ ] **Step 1: Run the complete suite**

```bash
tests/run-tests.sh
```

Expected: all tests across all bats files pass. Count should be ≥ 90 (67 from Phase 1 + ~23 new from this plan).

- [ ] **Step 2: Isolated install-mode smoke**

```bash
ISOTEST="/tmp/tmux-ai-p2-isotest-$$"
mkdir -p "$ISOTEST/.local/bin" "$ISOTEST/.config"
echo "original user config" > "$ISOTEST/.tmux.conf"

HOME="$ISOTEST" ./install.sh --full
ls -la "$ISOTEST/.tmux.conf"           # expect symlink → $(pwd)/tmux.conf
ls "$ISOTEST"/.tmux.conf.bak.*          # expect timestamped backup exists

HOME="$ISOTEST" ./install.sh --uninstall
cat "$ISOTEST/.tmux.conf"               # expect "original user config"

rm -rf "$ISOTEST"
```

Expected: backup appears, symlink installs, uninstall restores original.

- [ ] **Step 3: Tag the Phase 2 milestone**

```bash
git tag -a phase-2-mvp -m "tmux-ai Phase 2 — full tmux config + agents session + polished dashboard"
```

- [ ] **Step 4: Ship-check**

```bash
git status
```

Expected: clean working tree.

```bash
git log --oneline $(git describe --tags --abbrev=0 phase-1-mvp)..HEAD
```

Expected: a clean list of the Task 1–12 commits plus any fixup commits.

---

## What's next (Phase 3, if ever)

- Feature 1 from Phase 1 plan: project session templates (new session with pre-baked editor + agent + terminal layout).
- Feature 2: fuzzy-jump across all agents (may live in sidebar `/` search).
- Feature 3: tmux-resurrect reconciliation on startup.
- Feature 7: last-message peek column in dashboard.
- Feature 12: bulk actions (kill / restart / tail) from dashboard.
- opencode adapter.
- Main pane in agents session auto-tails the selected agent's log.
- Wayland clipboard (`wl-copy`) fallback in `tmux.conf` copy-mode.
