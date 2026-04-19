# tmux-ai

A modular tmux layer for managing AI coding agents. Phase 1 supports
Claude Code; opencode and multi-agent workflow features arrive in
Phase 2.

## What you get

- **Status-line indicators** — see every agent's state across sessions
  without leaving the current pane.
- **Popup dashboard** (`prefix + a`) — full table of every registered
  agent with state, project, window/pane, and elapsed time.
- **Desktop notifications** when an agent finishes a turn or needs
  input. `prefix + D` toggles Do-Not-Disturb.
- **Per-pane log capture** — every agent pane tees its output to
  `~/.local/state/tmux-ai/logs/<project>/<ts>.log`.
- **Stuck detection** — agents that have been "working" for more than
  `stuck_after_seconds` (default 180s) without output get flagged.

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

## Usage

| Keybind | Action |
|---|---|
| `prefix + A` | Spawn `claude` in a new pane, registered with hooks |
| `prefix + a` | Open popup dashboard |
| `prefix + D` | Toggle Do-Not-Disturb |
| `prefix + L` | Open the log file of the current pane in `$PAGER` |

CLI (also available as symlinked binaries):

    tmux-ai spawn claude    # also bound to prefix + A
    tmux-ai dash            # also bound to prefix + a
    tmux-ai list            # print the registry as a table
    tmux-ai dnd toggle      # also bound to prefix + D
    tmux-ai status          # what the status-line renders
    tmux-ai detect          # run one detect tick (debugging)
    tmux-ai log <pane_id>   # open log in $PAGER

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

## Config

`~/.config/tmux-ai/config.toml` (see `config.toml.example`). All
settings have sane defaults; the file is optional.

### Theming

The visual surface (status bar, pane borders, dash popup, sidebar) is
driven by seven `@tmux-ai-*` tmux options. The defaults are the
Kanagawa Wave palette. To retheme, set any of them *before* sourcing
`tmux.conf`:

    set -g @tmux-ai-accent '#f7768e'
    set -g @tmux-ai-stuck  '#ff0000'
    source-file ~/path/to/tmux-ai/tmux.conf

See `config.toml.example` for the full list of roles with defaults.

## Troubleshooting

- **No desktop notifications**: check `notify-send` runs from inside a
  tmux pane. On some Linux DEs tmux's server is detached from the user
  DBus. Workaround: `export DBUS_SESSION_BUS_ADDRESS` in your shell
  rc, then restart the tmux server.
- **Status-line shows nothing**: confirm `tmux-ai list` shows agents.
  If empty, the hook pipeline isn't firing - check
  `~/.local/state/tmux-ai/tmux-ai.log`.
- **Hook errors don't bubble up**: by design. Every hook failure is
  logged silently to the log file above.

## Testing

    tests/run-tests.sh

See `TESTING.md` for the manual smoke checklist.

## License

TBD by author.
