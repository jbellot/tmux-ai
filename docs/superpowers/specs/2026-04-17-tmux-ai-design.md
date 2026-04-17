# tmux-ai — Design Spec

**Date:** 2026-04-17
**Status:** Approved for planning
**Working title:** `tmux-ai`

## 1. Purpose

A modular tmux layer for managing AI coding agents (Claude Code, opencode, extensible to others). Gives the user ambient visibility into agent state across many sessions and projects, reliable notifications when an agent finishes or needs input, and a fast surface for spawning, jumping to, and managing agents.

Keeps the user's existing tmux configuration intact: this is an additive layer sourced from `~/.tmux.conf`, not a replacement tmux distribution.

## 2. Goals & non-goals

### Goals

- Know, at a glance, the state of every agent across every tmux session.
- Get notified reliably when an agent finishes a turn or asks for input, without polling the terminal.
- Spawn and jump between agent panes with low keypress cost.
- Work with Claude Code today, opencode at launch, and be extensible to new CLI agents via a thin adapter.
- Survive tmux restarts cleanly (no stale state, no crashed hooks).
- Never break the user's tmux or the underlying agent.

### Non-goals

- Not a tmux distribution — user keeps their own base config.
- Not a replacement for `tmux-resurrect`, `tmuxinator`, or `tmux-sessionizer`. Intended to coexist.
- No web UI, no cloud component, no telemetry.
- Not attempting to re-spawn agents across tmux restarts (state is ephemeral by design).

## 3. Architecture

### 3.1 Component map

```
┌─────────────────────────────────────────────────────────┐
│  tmux.conf snippet  (source-file from user's config)    │
│   - keybindings, status-line format, pane hooks         │
└───────────────┬─────────────────────────────────────────┘
                │ invokes
                ▼
┌─────────────────────────────────────────────────────────┐
│  bin/   (bash scripts, the CLI surface)                 │
│   - tmux-ai         main dispatcher                     │
│   - tmux-ai-spawn   launch agent in new pane            │
│   - tmux-ai-dash    render popup dashboard              │
│   - tmux-ai-status  render status-line segment          │
│   - tmux-ai-notify  emit notification (called by hooks) │
│   - tmux-ai-detect  scan panes for unregistered agents  │
└───────────────┬─────────────────────────────────────────┘
                │ reads/writes
                ▼
┌─────────────────────────────────────────────────────────┐
│  State                                                  │
│   $XDG_RUNTIME_DIR/tmux-ai/agents.json  (flock'd)       │
│   $XDG_STATE_HOME/tmux-ai/logs/<project>/<ts>.log       │
│   $XDG_CONFIG_HOME/tmux-ai/config.toml  (user settings) │
└───────────────┬─────────────────────────────────────────┘
                │ queried by
                ▼
┌─────────────────────────────────────────────────────────┐
│  adapters/   (per-agent plug-ins)                       │
│   - claude.sh   registers hooks, parses state           │
│   - opencode.sh same, for opencode                      │
│   - generic.sh  tmux-pane-monitor fallback              │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Key choices

- **Language: bash** end-to-end. `jq` for JSON mutation, `flock` for concurrency. No daemon, no long-running Python/Go runtime. Portable install, auditable scripts.
- **State file is a single flock'd JSON** under `$XDG_RUNTIME_DIR/tmux-ai/agents.json` — tmpfs, cleared on reboot (correct behavior for live-agent state).
- **Logs are persistent** under `$XDG_STATE_HOME/tmux-ai/logs/<project>/<timestamp>.log`.
- **No daemon.** All state writes happen in short-lived hook callbacks or on-demand from the dashboard/status-line refresh path (driven by tmux's own `status-interval`).
- **Adapter pattern.** Each supported agent implements 3 functions: `register_hooks`, `parse_state`, `uninstall_hooks`. Adding a new agent = one new `adapters/<name>.sh`.

## 4. Agent lifecycle & detection

### 4.1 State vocabulary

| State | Meaning | Detected by |
|---|---|---|
| `idle` | Agent launched, prompt ready, no active task | Hook (`SessionStart` / prompt ready) or pane quiescent |
| `working` | Agent processing a turn | Hook (`UserPromptSubmit`) or pane byte-rate > threshold |
| `waiting` | Agent asking for user input / approval | Hook (`Notification` for Claude Code) |
| `done` | Turn finished, back to prompt | Hook (`Stop`) or pane quiescent after `working` |
| `error` | Agent exited non-zero / crashed | Pane process died |
| `stuck` | `working` for > N minutes with no output bytes | `tmux-ai-detect` |

### 4.2 Detection strategy — hybrid

- **Preferred path:** agent-native hooks. Accurate and semantic (`done` vs `waiting`).
- **Fallback path:** tmux-level pane monitoring (byte delta via periodic `tmux capture-pane`). Agent-agnostic, heuristic.

Hybrid is used because hooks are reliable where available, but auto-detected agents (user typed `claude` in a random pane) can't retroactively install hooks, and not every agent the user tries will be pre-adapted.

### 4.3 Adapters

**Claude Code adapter** (`adapters/claude.sh`):
- On spawn, injects hook config via `CLAUDE_SETTINGS` env var OR a per-project `.claude/settings.json` merge. Registered hooks:
  - `UserPromptSubmit` → `state = working`
  - `Stop` → `state = done`
  - `Notification` → `state = waiting`
  - `SessionStart` → register in state file
- Each hook invokes `tmux-ai-notify <event> <pane_id> <metadata>`, which mutates `agents.json` and routes notifications per config.
- Pane is spawned with `tmux new-window -n "cc:<project>"`.

**opencode adapter** (`adapters/opencode.sh`):
- Opencode has a hooks/event system; the same three adapter functions are implemented against opencode's config format.
- **Open item:** exact hook event names to be verified at implementation time. If opencode's hook surface is insufficient, we fall back to the generic adapter for opencode until upstream support can be added.

**Generic (fallback) adapter** (`adapters/generic.sh`):
- No hooks. `tmux-ai-detect` (invoked from tmux's `status-interval`, not a daemon) snapshots each registered pane's byte count:
  - Bytes flowing → `working`
  - Quiet for `idle_after_seconds` → `done`/`idle`
  - Quiet while `working` for `stuck_after_seconds` → `stuck`
- Thresholds configurable per agent type.

### 4.4 Registration flow

```
prefix + A  (keybind)
   │
   ▼
tmux-ai spawn claude           ← user picks agent
   │
   ▼
 adapter.register_hooks()      ← writes hook config, sets env
   │
   ▼
 tmux split-window ...          ← pane opens running agent
   │
   ▼
 agent starts → SessionStart hook fires
   │
   ▼
 tmux-ai-notify session_start <pane>  ← registry entry created
```

**Auto-detect path:** `tmux-ai-detect` runs on each `status-interval` tick, enumerates panes, matches `pane_current_command` against known agent executables, registers any unknown-but-matching panes against the generic adapter. Hooks cannot be injected after launch, so auto-detected agents always use heuristic detection.

## 5. User-facing surface

### 5.1 Keybindings (configurable, defaults shown)

| Binding | Action |
|---|---|
| `prefix + A` | Spawn-agent menu: choose agent (claude/opencode) and target — **new pane in this session** (quick) or **new project session with layout** (feature 1). |
| `prefix + a` | Toggle dashboard popup |
| `prefix + j` | Jump-to-agent (fzf picker across sessions, jumps to pane) |
| `prefix + D` | Toggle Do-Not-Disturb |
| `prefix + L` | Open current pane's agent log in `$PAGER` |

**"Current project dir" is defined as:** the git top-level of the invoking pane's cwd (`git -C "$PWD" rev-parse --show-toplevel`); if the pane is not inside a git repo, falls back to the pane's cwd. This definition is used wherever the spec says "project dir".

### 5.2 Status-line segment

User appends `#(tmux-ai-status)` to their `status-right`:

- **≤ 3 agents:** inline icon + short project tag per agent, e.g. `⚙ foo ⏸ bar ✓ baz`.
- **> 3 agents:** aggregated counters — `AI: 2⚙ 1⏸ 3✓` (working / waiting / done-unacked). Threshold configurable.
- **Per-window tab prefix:** optional `window-status-format` override to prefix the window name with the current agent icon (e.g. `⚙ cc:foo`).
- **Colors:** working=yellow, waiting=magenta (attention), done=green, stuck=red, error=red-bold.
- **Mouse-click jump:** supported when `mouse on` is set in tmux config. Documented as optional.

### 5.3 Popup dashboard

```
┌─ tmux-ai — 4 agents ─────────────────────────────────────────┐
│  STATE   AGENT     PROJECT         WIN:PANE   ELAPSED  LAST  │
│                                                              │
│  ⏸ wait  claude    foo-api         main:1.0   04:12    "Sh…  │
│  ⚙ work  claude    bar-frontend    bar:0.1    00:47    "Upd  │
│  ✓ done  opencode  foo-api         main:1.1   12:03    "Don  │
│  ✗ stuck claude    legacy-service  old:2.0    28:45    "Run  │
│                                                              │
│  [Enter] attach  [k] kill  [r] restart  [l] log  [q] quit    │
└──────────────────────────────────────────────────────────────┘
```

- Rendered via `tmux display-popup -E` by `tmux-ai-dash`.
- 1-second refresh loop while popup is open.
- "Last" column = last non-empty line from `tmux capture-pane -p | grep -v '^\s*$' | tail -n 1`, truncated.
- Arrow keys select; `Space` multi-selects for bulk actions.

### 5.4 Notification channels

| Channel | Default | Notes |
|---|---|---|
| Desktop toast (`notify-send`) | **on** | Title = `agent (project)`, body = event. macOS uses `osascript`/`terminal-notifier`. |
| Status-line + window flash | **on** | In-terminal only, non-interruptive. |
| Sound (`paplay` / `afplay`) | **off** | Distinct cues per event class. |
| Push (ntfy.sh / Pushover) | **off** | Target URL in config. Useful when AFK. |

Do-Not-Disturb mode suppresses desktop, sound, and push, but leaves status-line and dashboard updating.

### 5.5 Config file

Location: `$XDG_CONFIG_HOME/tmux-ai/config.toml`.

```toml
[notifications]
desktop = true
status_line = true
sound = false
push = false
# push_target = "ntfy.sh/yourtopic"

[detection]
stuck_after_seconds = 180
idle_after_seconds = 5

[agents.claude]
spawn_command = "claude"
# extra_args = []

[agents.opencode]
spawn_command = "opencode"

[dnd]
# keybind sets/clears a flag file; scripts respect it
```

## 6. Feature modules (v1 scope)

| # | Feature | Implementation summary |
|---|---|---|
| 1 | **Project session templates** | Selected from the `prefix + A` menu's "new project session" option. Reads the project dir (defined in §5.1), creates `tmux new-session -s <reponame>` with a 3-pane layout: editor left 60%, agent top-right, terminal bottom-right. Hard-coded layout script, no templating engine. The agent pane is spawned through the same path as the "new pane in this session" option, so registration and hooks are identical. |
| 2 | **Quick-attach / fuzzy jump** | `tmux-ai jump` pipes `agents.json` through `fzf` (preview = last 20 pane lines), selection runs `tmux switch-client` + `select-pane`. |
| 3 | **tmux-resurrect-aware** | On tmux start, `tmux-ai reconcile` compares `agents.json` against live panes. Missing panes → marked `error`, retained 1h for UI visibility, then purged. Does NOT re-spawn agents — tmux-resurrect handles layouts, not live CLI state. |
| 4 | **Pane output capture** | At spawn time: `tmux pipe-pane -o -t <pane> "cat >> $LOGFILE"`. Path recorded in registry. One file per spawn, gzipped after pane close. |
| 5 | **Stuck detection** | `tmux-ai-detect` tick: if `state=working` and last-byte-timestamp older than `stuck_after_seconds` → transition to `stuck`, fire one notification. Re-entry policy: if state later returns to `working` and becomes stuck again, that is a **new** stuck episode and notifies again. Staying continuously in `stuck` does not re-fire. |
| 7 | **Last-message peek** | Dashboard runs `tmux capture-pane -p | grep -v '^\s*$' | tail -n 1` per row. Cheap at 1Hz for < 20 agents. |
| 9 | **Do-Not-Disturb** | `prefix + D` toggles `$XDG_RUNTIME_DIR/tmux-ai/dnd.flag`. `tmux-ai-notify` checks flag before emitting desktop/sound/push. Auto-clears after 2h to prevent perma-silence. |
| 12 | **Bulk actions in dashboard** | Multi-select in popup → `k` kills (`tmux send-keys C-c`, then close pane after grace period), `r` restarts (kill + respawn via stored adapter/cwd), `l` tails log. |

### Deferred to later versions

- Cost/usage tracking (feature 6) — Claude Code output format is not stable enough.
- Approval with action buttons (feature 8) — libnotify action support is inconsistent across DEs.
- SSH notification forwarding (feature 10) — significant scope (local daemon / SSH ControlMaster).

### Explicitly skipped

- Broadcast prompt (feature 11) — rarely useful, easy to build later if needed.

## 7. Installation & portability

### 7.1 Install flow

`./install.sh`:

1. Symlinks `bin/*` into `$HOME/.local/bin` (or `$TMUX_AI_PREFIX/bin`).
2. Appends one `source-file ~/path/to/tmux-ai.tmux.conf` line to user's `~/.tmux.conf`, guarded by a marker comment so it is idempotent.
3. Writes default `config.toml` if absent.
4. Prints — does not execute — the claude-code hook-install command. User's `~/.claude/settings.json` is user-owned; we do not modify it silently.

### 7.2 Dependencies

`bash ≥ 4`, `tmux ≥ 3.2`, `jq`, `flock`, `fzf`, `libnotify-bin` (for `notify-send`).

`install.sh` checks these and reports missing ones with install hints for common distros.

### 7.3 Uninstall

`./install.sh --uninstall` reverses each step and prints the hook-removal command.

### 7.4 Platforms

- **Linux:** primary target.
- **macOS:** supported; `notify-send` swapped for `osascript` (or `terminal-notifier` if installed), detected at runtime.
- **WSL:** treated as Linux.

## 8. Error handling

- **Never break tmux or the agent.** Every script exits 0 on its own errors and logs to `$XDG_STATE_HOME/tmux-ai/tmux-ai.log`.
- **Hook failures are silent-but-logged.** Hook scripts wrap logic as `{ ... ; } 2>> "$LOG" || true`.
- **State file corruption:** JSON parse error → move aside as `agents.json.corrupt.<timestamp>`, start fresh, log a single recovery toast.
- **Concurrent writes:** every mutation of `agents.json` goes through `flock` with a 2-second timeout.
- **Missing dependencies at runtime:** script prints one actionable error line to stderr and exits 0 (not 1) to avoid cascading tmux-config errors.

## 9. Testing

- **Unit level:** `bats` test suite per script. `tmux` stubbed with a recording script that returns canned responses.
- **Adapter tests:** a fake claude-code-like binary that fires hook events on stdin commands. End-to-end state-transition coverage.
- **Integration:** tests run against a real tmux server on a custom socket (`tmux -L tmux-ai-test`) so CI never touches a user's tmux. Dashboard rendering is snapshot-tested by `tmux capture-pane`.
- **Manual smoke checklist** in `TESTING.md`, to be run before any change to the Claude Code hook path (highest blast radius).

## 10. Open items to resolve during implementation

1. **opencode hook event names** — verify against current opencode docs. If insufficient, fall back to generic adapter for opencode in v1.
2. **`notify-send` from inside tmux** — some Linux setups sandbox the tmux server process from DBus; may need `DISPLAY` / `DBUS_SESSION_BUS_ADDRESS` passthrough captured at attach time.
3. **Window-status-format override** — optional and documented; the aggregated `status-right` segment works regardless.

## 11. Directory layout (final)

```
tmux-config/
├── bin/
│   ├── tmux-ai
│   ├── tmux-ai-spawn
│   ├── tmux-ai-dash
│   ├── tmux-ai-status
│   ├── tmux-ai-notify
│   └── tmux-ai-detect
├── adapters/
│   ├── claude.sh
│   ├── opencode.sh
│   └── generic.sh
├── tmux-ai.tmux.conf           # keybindings + status-line snippet
├── config.toml.example
├── install.sh
├── tests/
│   ├── bats/
│   └── fixtures/
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-17-tmux-ai-design.md  # this file
├── README.md
└── TESTING.md
```
