# tmux-ai Phase 2 — Full tmux config + Agents Workspace

**Date:** 2026-04-18
**Status:** Approved for planning
**Working title:** tmux-ai v0.2

## 1. Purpose

Extend tmux-ai from a thin agent-management layer into a complete tmux daily-driver. Ship a full `tmux.conf` (theme, status bar, pane ergonomics, copy mode) with a first-class agent workspace: a dedicated `agents` session that lays out a live sidebar alongside an open-ended main pane. Polish the popup dashboard with colors, box-drawing, and keyboard selection.

Preserves every Phase 1 keybinding, state layer, adapter interface, and hook pipeline — no breaking changes to agent mechanics.

## 2. Goals & non-goals

### Goals

- Replace the minimal Phase 1 `tmux-ai.tmux.conf` snippet with a complete, opinionated `tmux.conf` that serves as a daily driver.
- Provide a persistent, always-findable view of every agent via the `agents` session's sidebar.
- Make jumping to any agent a single keystroke from the sidebar: cursor to row → Enter.
- Visually distinguish agent states (working / waiting / done / stuck / idle) with colors in both the sidebar and the popup dashboard.
- Keep install.sh safely opt-in for the full replacement (explicit `--full` flag, backup of any prior `~/.tmux.conf`).

### Non-goals

- No change to the hook pipeline, state registry, adapter interface, or the `--settings` spawn mechanism.
- No bulk actions in the dashboard (still deferred, originally from Phase 1's feature 12).
- No opencode adapter (still deferred).
- No main-pane auto-tailing of selected agent's log (deferred to v0.3).
- No plugin manager (TPM) integration.
- No Wayland clipboard (`wl-copy`) support in this phase; `xclip` / `pbcopy` only.

## 3. Architecture

### 3.1 What's new, what changes, what stays

```
tmux-config/
├── tmux.conf                   NEW  full daily-driver config
├── tmux-ai.tmux.conf           KEPT now sourced from tmux.conf (unchanged)
├── bin/
│   ├── tmux-ai                 unchanged
│   ├── tmux-ai-spawn           unchanged
│   ├── tmux-ai-dash            POLISHED colors, box frame, selection, jump
│   ├── tmux-ai-status          unchanged
│   ├── tmux-ai-notify          unchanged
│   ├── tmux-ai-detect          unchanged
│   ├── tmux-ai-dnd             unchanged
│   ├── tmux-ai-sidebar         NEW narrow-pane interactive status
│   └── tmux-ai-goto-agents     NEW ensure + switch-to agents session
├── lib/                        unchanged (common/state/config/notify)
├── adapters/                   unchanged
├── install.sh                  EXTENDED new --full mode with backup
├── config.toml.example         EXTENDED new @tmux-ai-accent, @tmux-ai-sidebar-width
├── tests/bats/                 + test_sidebar.bats + test_goto_agents.bats + test_install_full.bats
└── docs/
```

### 3.2 Key design choices

- **No new runtime state.** The sidebar and dashboard both read the existing `agents.json`. No new persistent stores.
- **Hash-skip rendering** applied to both sidebar and dashboard, inherited from the Phase 1 dashboard flicker fix.
- **`agents` session is a view, not a workspace.** Because spawn behavior is L1 (spawn in current window), the `agents` session exists only to show and launch into agents. Agents do not live there.
- **Single accent color** threads the whole visual design, configurable via `@tmux-ai-accent` tmux option so future themes can override.

## 4. Full tmux config (`tmux.conf`)

### 4.1 Core behavior

```tmux
set -g prefix C-b                          # keep default
set -g mouse on
set -g escape-time 0                       # vim-friendly
set -g history-limit 50000
set -g focus-events on
set -g base-index 1                        # windows start at 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g default-terminal 'tmux-256color'
set -ga terminal-overrides ',*256col*:Tc'  # TrueColor
set -ga terminal-features 'xterm-256color:RGB'
```

### 4.2 Theme and accents

- `@tmux-ai-accent` default `#82aaff` — cool blue. User override via `set -g @tmux-ai-accent '#<hex>'` before sourcing.
- Active pane border: accent color.
- Inactive pane border: muted gray `#4c4c4c`.
- Active window tab: accent foreground, bold.
- Inactive window tab: `#808080` foreground.

### 4.3 Pane and window ergonomics

| Binding | Action | Notes |
|---|---|---|
| `prefix + \|` | Split vertical, keep cwd | New binding |
| `prefix + -` | Split horizontal, keep cwd | New binding |
| `prefix + %`, `prefix + "` | Default splits | Preserved |
| `prefix + h/j/k/l` | Move between panes | New binding |
| Default arrows | Move between panes | Preserved |
| `prefix + H/J/K/L` | Resize pane by 5 cells | New binding |
| `prefix + z` | Zoom pane | Default, no change |
| `prefix + r` | Reload `~/.tmux.conf` | New binding |

### 4.4 Copy mode

```tmux
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi V send -X select-line
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "<clipboard-cmd>"
```

Actual concrete tmux.conf snippet (resolved at config load):

```tmux
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi V send -X select-line

# Pick the first available clipboard backend. if-shell chains short-circuit
# — the first command whose shell test exits 0 wins.
if-shell 'command -v pbcopy >/dev/null' \
  "bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'pbcopy'" \
  "if-shell 'command -v xclip >/dev/null' \
     \"bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'xclip -selection clipboard'\" \
     \"bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'cat >/dev/null'\""
```

Order of preference: `pbcopy` (macOS) → `xclip` (X11) → tmux buffer only. Wayland (`wl-copy`) deferred as stated in §2.

### 4.5 Status bar

Layout:
```
[session] | 1:foo 2:bar* 3:baz |          | AI: 2⚙ 1⏸ 3✓ | 14:32
```

- `status-interval 2`
- `status-left`: session name (in accent); DND-aware prefix (`🔕` when active).
- `status-right`: `#(tmux-ai status) | %H:%M`.
- Center: window list, active window highlighted with accent + `*`.

### 4.6 Agent-session auto-boot

```tmux
set-hook -g client-attached 'run-shell -b "tmux-ai-goto-agents --ensure"'
```

Creates the `agents` session in the background on first attach (fast after that — the hook short-circuits if session exists). Does NOT switch.

### 4.7 Phase 1 keybindings preserved

| Binding | Action |
|---|---|
| `prefix + A` | Spawn claude in current window (unchanged L1 behavior) |
| `prefix + a` | Popup dashboard |
| `prefix + D` | DND toggle |
| `prefix + L` | Current pane's log in `$PAGER` |
| `prefix + g` | **NEW** — go to agents session |

## 5. Agents session

### 5.1 Layout

```
┌─ agents:main ────────────────────────────────────────────────┐
│ sidebar (32 cols)        │  main pane                        │
│                          │                                   │
│ ▸ ⚙ foo-api      04:12   │  $                                │
│   ⏸ bar-frontend 00:47   │  (user shell — do what you like)  │
│   ✓ legacy-svc   12:03   │                                   │
│   ✗ old-batch    28:45   │                                   │
│                          │                                   │
│ [j/k] move  [Enter] jump │                                   │
│ [d] unreg  [r] refresh   │                                   │
└──────────────────────────┴───────────────────────────────────┘
```

### 5.2 Session creation

Handled by `bin/tmux-ai-goto-agents`:
- `--ensure`: idempotent creation, no switch. Safe from `run-shell -b` hooks.
- default (no flag): ensure + `tmux switch-client -t agents`.

Creation steps (idempotent; exits 0 without action if session already exists):

1. `tmux has-session -t agents 2>/dev/null` → if 0, exit.
2. Create session with the sidebar in the initial pane:
   ```
   tmux new-session -d -s agents -n main 'tmux-ai-sidebar'
   ```
   (Let tmux size the session from the attaching client; the `-x -y` overrides were an earlier false start.)
3. Split off the main (right) pane from the sidebar:
   ```
   tmux split-window -h -t agents:main -c "$HOME"
   ```
4. Resize the sidebar to its configured width:
   ```
   sidebar_w=$(tmux show-options -gv @tmux-ai-sidebar-width 2>/dev/null || echo 32)
   tmux resize-pane -t agents:main.1 -x "$sidebar_w"
   ```
5. Select the main pane so the user lands in a usable shell when they switch to the session:
   ```
   tmux select-pane -t agents:main.2
   ```

### 5.3 Session-closed recovery

Hook:
```tmux
set-hook -g session-closed 'run-shell -b "tmux-ai-goto-agents --ensure"'
```
If user accidentally `prefix + &` the agents session, a background recreate fires. Idempotent.

## 6. Sidebar (`bin/tmux-ai-sidebar`)

### 6.1 Responsibilities

- Render a narrow-column live view of all registered agents.
- Handle interactive keys in its own pane (no global tmux binds needed for cursor motion).
- Issue `tmux switch-client` + `select-pane` on `Enter` to jump to the real agent pane.
- Redraw only when state changes (hash-skip), with low-priority 60s heartbeat for elapsed freshness.

### 6.2 Rendering

- Width: `@tmux-ai-sidebar-width` option, default 32.
- Truncate overlong projects to fit. Elapsed format `MM:SS` (switches to `HH:MM` after 99 minutes).
- ANSI palette applied to state icon:
  - working → yellow
  - waiting → magenta (attention)
  - done → green
  - stuck → red
  - idle → dim
  - error → red+bold
- Cursor: `▸` prefix on the selected row, accent foreground.
- Footer: two lines of help text, dim gray.

### 6.3 Key handling (in-pane, not tmux-bound)

| Key | Action |
|---|---|
| `j` / `↓` | Move cursor down |
| `k` / `↑` | Move cursor up |
| `g` | Jump cursor to first |
| `G` | Jump cursor to last |
| `1..9` | Set cursor to Nth row and jump |
| `Enter` | Jump to selected agent (switch-client + select-pane) |
| `d` | Unregister selected (confirm with `y`/`n`) |
| `r` | Force refresh now |
| `q` | Clear pending action (NOT quit — sidebar is persistent) |

Selection persists across redraws by tracking the cursor's pane_id (not index), so state changes don't jump the cursor around unpredictably.

### 6.4 Rendering loop

Pseudocode:
```
cursor_pane_id = <first agent or null>
last_hash = ""
loop:
    frame = render(state, cursor_pane_id)
    h = cksum(frame)
    if h != last_hash:
        paint_in_place(frame)
        last_hash = h
    try read -t 1 -n 1 -s key
        handle(key)
    on SIGWINCH: reset last_hash (force full redraw)
```

### 6.5 Empty state

```
     no agents

  prefix + A to spawn
```
Centered vertically.

## 7. Dashboard polish (`bin/tmux-ai-dash`)

### 7.1 Visual changes

- Unicode box frame around the table.
- Header line shows `tmux-ai — 4 agents` plus `🔕 DND on` when active.
- STATE column gains ANSI color (same palette as sidebar).
- Selection cursor `▸` on the leftmost column.
- Footer: `[j/k] select  [Enter] jump  [q] quit`.

### 7.2 Interaction changes

- `j`/`k` or arrow keys move the cursor within the popup.
- `Enter` → switch-client/select-pane to the selected agent, popup closes.
- `q` / `Q` / `Esc` → close without jumping (same as today).
- Digits `1..9` jump by row number.

### 7.3 Preserved from Phase 1

- Hash-skip redraws, hidden cursor, ANSI cursor-home + erase-to-end.
- `--render` one-shot mode for tests.
- Popup geometry `-w 90% -h 60%`.

## 8. `tmux-ai-goto-agents`

Minimal new binary.

```
Usage:
  tmux-ai-goto-agents            # ensure + switch
  tmux-ai-goto-agents --ensure   # ensure only, never switch
```

Logic:
1. If `tmux has-session -t agents` returns 0: switch (unless `--ensure`); exit.
2. Else: create session with the layout from §5.2.
3. If not `--ensure`: `tmux switch-client -t agents`.
4. Always exit 0 (swallow errors; this runs from hooks too).

## 9. install.sh changes

### 9.1 New `--full` mode

```
./install.sh            # additive, default (Phase-1 compatible)
./install.sh --full     # symlink ~/.tmux.conf → project/tmux.conf
./install.sh --uninstall
./install.sh --check    # unchanged
```

`--full` flow:
1. If `~/.tmux.conf` exists and is NOT a symlink to our `tmux.conf`: back up to `~/.tmux.conf.bak.<YYYYMMDD-HHMMSS>`.
2. Remove existing `~/.tmux.conf` (after backup).
3. `ln -s <project>/tmux.conf ~/.tmux.conf`.
4. Print a one-liner reminder to reload (`tmux source-file ~/.tmux.conf` or restart tmux).

### 9.2 Default mode — what changes

Previously (Phase 1) the marker block sourced `tmux-ai.tmux.conf`. Now the marker block sources `tmux.conf` (the full file), which internally sources `tmux-ai.tmux.conf`. Users on Phase 1 who upgrade: re-running `./install.sh` detects the existing marker block and rewrites it with the new `source-file` path.

### 9.3 `--uninstall` changes

- Standard symlink/marker-block reversal, as Phase 1.
- **New:** if `~/.tmux.conf` is our symlink, remove the symlink, then — if a `~/.tmux.conf.bak.*` file exists — restore the **most recent** backup in place. Always automatic (no flag required). If the user wants to keep the symlink state for debugging, they can use `--uninstall --no-restore` to skip the backup-restore step.

### 9.4 `--check` additions

- Warn if neither `xclip` / `wl-copy` / `pbcopy` is present — exit still 0; this only degrades copy-mode yanking, doesn't break core.

## 10. Tests

### 10.1 New suites

- `tests/bats/test_sidebar.bats`
  - Empty-state render (partial match on "no agents")
  - Single-agent render with correct icon and project
  - Multi-agent render with cursor on first row by default
  - Cursor persists across redraws when the selected pane_id still exists
  - Cursor moves to the first row when the previously-selected pane is GC'd
  - ANSI color codes present for each state (grep for `\033[` sequences; specific color per state)
  - Hash-skip: same frame rendered twice produces identical bytes

- `tests/bats/test_goto_agents.bats`
  - Creates `agents` session when absent (detectable via tmux stub recording `new-session`)
  - No-op when session already present (`has-session` succeeds, no `new-session` call)
  - `--ensure` never invokes `switch-client`
  - Default (no flag) DOES invoke `switch-client`

- `tests/bats/test_install_full.bats`
  - `--full` backs up existing `~/.tmux.conf` with `.bak.<ts>` suffix
  - Symlink targets our project's `tmux.conf`
  - Second `--full` run does NOT create an additional backup if current symlink is already correct
  - `--uninstall` after `--full` removes the symlink and restores the most-recent backup
  - `--uninstall --no-restore` removes the symlink but leaves the backup in place (no restore)

### 10.2 Extensions to existing suites

- `test_dash.bats`: new tests for colored STATE column, cursor motion, jump-on-enter (via stub recording `switch-client` + `select-pane`).

### 10.3 Manual smoke checklist

Phase-2 additions to `TESTING.md`:
- Fresh tmux start → `prefix + g` → lands in `agents` session with sidebar on left.
- Spawn agent via `prefix + A` from another session → within 2s appears in sidebar.
- Sidebar `Enter` on the agent → jumps to the agent's real pane in its origin session.
- Sidebar `d` + `y` → agent disappears from sidebar.
- Dashboard `prefix + a` → colored rows, `Enter` jumps and closes popup.
- `./install.sh --full` on a machine with an existing `.tmux.conf` → backup file created, symlink installed, tmux reloads without errors.

## 11. Error handling

- Same contract as Phase 1: every bin script exits 0 on its own errors. Hook-called scripts wrap `main` in `{ ... ; } 2>>log || true`.
- `tmux-ai-goto-agents --ensure` is safe in hook context: no TTY needed, all tmux calls use `-t agents` and tolerate non-existence.
- Sidebar's in-pane read loop has a `SIGWINCH` trap to force full redraw on resize.
- Dashboard selection cursor falls back to "no selection" if the cursor's pane_id disappears mid-frame.

## 12. Open items to resolve during implementation

- **Color escape sequences in captured pane output.** The sidebar and dashboard emit ANSI color codes. Agent panes separately use `pipe-pane` for log capture (Phase 1 feature 4). The sidebar/dashboard do NOT use `pipe-pane`, so this shouldn't overlap — but verify that no spawn code accidentally wires up `pipe-pane` for the sidebar pane. If it does, strip ANSI in the pipe target (`sed -r 's/\x1b\[[0-9;]*m//g' >> log`).
- **Sidebar SIGWINCH behavior.** Bash's `read -t 1 -n 1 -s` inside a `trap SIGWINCH` block: confirm the trap fires promptly even when `read` is blocking. If not, shorten the read timeout to 200ms and ignore the SIGWINCH trap.
- **`prefix + r` reload reliability when `~/.tmux.conf` is a symlink.** Verify `source-file ~/.tmux.conf` re-resolves the symlink correctly on every call. (It should; tmux reads the target each time.)

## 13. Directory layout after Phase 2

```
tmux-config/
├── tmux.conf                       NEW
├── tmux-ai.tmux.conf               kept (sourced from tmux.conf)
├── bin/
│   ├── tmux-ai                     unchanged
│   ├── tmux-ai-spawn               unchanged
│   ├── tmux-ai-dash                polished
│   ├── tmux-ai-status              unchanged
│   ├── tmux-ai-notify              unchanged
│   ├── tmux-ai-detect              unchanged
│   ├── tmux-ai-dnd                 unchanged
│   ├── tmux-ai-sidebar             NEW
│   └── tmux-ai-goto-agents         NEW
├── lib/                            unchanged
├── adapters/                       unchanged
├── config.toml.example             extended
├── install.sh                      extended
├── tests/
│   ├── bats/
│   │   ├── ... (existing 14)
│   │   ├── test_sidebar.bats       NEW
│   │   ├── test_goto_agents.bats   NEW
│   │   └── test_install_full.bats  NEW
│   └── stubs/                      unchanged
├── docs/
│   └── superpowers/
│       ├── specs/
│       │   ├── 2026-04-17-tmux-ai-design.md      (Phase 1)
│       │   └── 2026-04-18-tmux-ai-phase-2-design.md  (this)
│       └── plans/
│           └── 2026-04-17-tmux-ai-phase-1.md
├── README.md                       extended
└── TESTING.md                      extended
```
