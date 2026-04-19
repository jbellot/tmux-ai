# tmux-ai — Visual Redesign

**Date:** 2026-04-19
**Scope:** Visual surface only (palette, status bar, window tabs, pane borders,
dash popup, agents-session sidebar). No changes to keybinds, session logic,
agent detection, or install flow.

## Problem

The current `tmux.conf` works but looks dated: hex literals scattered
through the file, a single cool-blue accent carrying no semantic meaning,
an emoji DND indicator (`🔕`) that clashes with the otherwise-text UI, a
declared-but-unreferenced `@tmux-ai-accent` option, and 8-color ANSI in
dash/sidebar that visually drifts from the truecolor status bar.

The goal is a quiet, minimal, palette-driven look that pairs well with
long working sessions and is trivially retheme-able.

## Chosen Direction

- **Aesthetic direction:** Quiet Minimal — single-row, transparent-background
  status bar with plain-Unicode separators.
- **Palette:** Kanagawa Wave.
- **Glyphs:** plain Unicode only (`◉ ◎ ✓ ⏸ ⚙ ✗ ◌ · │`) — no Nerd Font
  assumed, no emoji.
- **Layout:** single row, left-aligned tabs (`status-justify left`).

Alternatives considered and rejected: Modern Flat (Catppuccin pills,
pleasant but busier than desired), Classic Powerline (requires Nerd
Font, feels dense); Rose Pine Moon, Everforest, and the current blue
(rejected at palette step in favor of Kanagawa); centered tabs and
two-row (rejected at layout step in favor of single-row left).

## Semantic Palette

Every color below is exposed as a `@tmux-ai-<role>` tmux option,
overridable by the user *before* sourcing `tmux.conf`.

| Option | Default | Role |
|---|---|---|
| `@tmux-ai-accent` | `#7e9cd8` | session name, active window underline, active pane border, sidebar "waiting-for-you" state, selected-row cursor |
| `@tmux-ai-fg`     | `#dcd7ba` | default foreground, inactive window name, clock |
| `@tmux-ai-dim`    | `#727169` | idle/muted state, footer hints in dash/sidebar |
| `@tmux-ai-sep`    | `#363646` | hard separators (`│`), inactive pane borders |
| `@tmux-ai-ok`     | `#98bb6c` | agent state "ready" / "done" (✓) |
| `@tmux-ai-wait`   | `#dca561` | agent state "working" (⚙) and DND indicator (◌) |
| `@tmux-ai-stuck`  | `#e82424` | agent state "stuck" (✗) and "error" (bold) |

A "waiting for user input" agent state uses `@tmux-ai-accent` (blue),
because that is conceptually "pay attention to this row" — a semantic
match for the accent color.

Today's status bar is effectively monochrome; this design introduces
four *new* semantic colors (ok/wait/stuck/accent-for-waiting) driven by
the existing agent state machine.

## Status-Bar Layout

Single row, justified left. Contents, in order from left edge to right
edge:

```
[◌ ] ◉ <session> │ <tab1> · <tab2> · <tab3>   ✓ N ⏸ N ⚙ N ✗ N │ HH:MM
```

- **DND prefix** (`◌ ` in `@tmux-ai-wait` amber) only when
  `$XDG_RUNTIME_DIR/tmux-ai/dnd.flag` exists.
- **Session name** prefixed by `◉` in bold accent.
- **Window tabs** separated by `·` in `@tmux-ai-sep`. Active window uses
  `fg=@tmux-ai-accent,underscore`; inactive uses `fg=@tmux-ai-fg`. The
  current `*` suffix on the active tab is removed (the underline replaces it).
- **Agent status** rendered by `bin/tmux-ai-status`, which emits
  truecolor `#[fg=...]` spans keyed on counts of each state. When no
  agents are registered, the segment is empty.
- **Clock** in `@tmux-ai-fg`, `%H:%M` 24-hour.

`status-justify` flips from `centre` to `left`. `status-style` stays
`bg=default` (transparent pass-through).

## Window Tabs

```tmux
set -g window-status-format \
  '#[fg=#{@tmux-ai-fg}] #I #W #[fg=#{@tmux-ai-sep}]·'
set -g window-status-current-format \
  '#[fg=#{@tmux-ai-accent},underscore] #I #W #[nounderscore,fg=#{@tmux-ai-sep}]·'
set -g window-status-separator ''
```

## Pane Borders

```tmux
set -g pane-border-lines        single
set -g pane-border-style        'fg=#{@tmux-ai-sep}'
set -g pane-active-border-style 'fg=#{@tmux-ai-accent}'
```

`pane-border-lines single` is explicit (tmux default, but stated so
future overrides like `rounded` are a one-line change).

## Dash Popup & Agents-Session Sidebar

Both `bin/tmux-ai-dash` and `bin/tmux-ai-sidebar` currently use 8-color
ANSI escapes defined at the top of each script. They move to truecolor
`\033[38;2;R;G;Bm` escapes derived from the tmux options.

A new helper in `lib/state.sh` reads the palette once per invocation
and exposes shell variables:

```sh
# lib/state.sh
load_palette() {
  C_ACCENT=$(_palette_ansi "@tmux-ai-accent" "#7e9cd8")
  C_FG=$(_palette_ansi     "@tmux-ai-fg"     "#dcd7ba")
  C_DIM=$(_palette_ansi    "@tmux-ai-dim"    "#727169")
  C_SEP=$(_palette_ansi    "@tmux-ai-sep"    "#363646")
  C_OK=$(_palette_ansi     "@tmux-ai-ok"     "#98bb6c")
  C_WAIT=$(_palette_ansi   "@tmux-ai-wait"   "#dca561")
  C_STUCK=$(_palette_ansi  "@tmux-ai-stuck"  "#e82424")
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM_ATTR=$'\033[2m'
}
# _palette_ansi takes (option, hex_default), runs `tmux show-options -gv`,
# falls back to the default if unset, converts #RRGGBB → \033[38;2;R;G;Bm.
```

Each state renderer maps to one of these variables:

| State (key) | Symbol | Variable |
|---|---|---|
| done / ready | `✓` | `C_OK` |
| working | `⚙` | `C_WAIT` |
| waiting (user input) | `⏸` | `C_ACCENT` |
| stuck | `✗` | `C_STUCK` |
| error | `!` | `C_STUCK` + `C_BOLD` |
| idle | `·` | `C_DIM` |

The `waiting` ⇢ magenta mapping is explicitly replaced with
`waiting` ⇢ accent-blue. Magenta is not in the Kanagawa palette and
conceptually "needs your attention" aligns with the accent.

The project already requires tmux ≥3.2 and truecolor terminals (the
existing status bar uses truecolor), so no 8-color fallback is
implemented.

## File Organization

`tmux.conf` reorganized so the palette block sits at the top of the
visual section and all color references downstream go through
`#{@tmux-ai-*}`. No more hex literals anywhere in `tmux.conf`.

Section order:
1. Core behaviour
2. **Palette** (new, consolidated)
3. **Status bar** (references palette, not literals)
4. Window tabs
5. Pane borders
6. Pane / window ergonomics
7. Copy mode
8. Agent layer (unchanged)

## `bin/tmux-ai-status` Output Format

Today emits plain text. New format emits truecolor spans, one per
non-zero semantic state, in this order: done, waiting-for-input,
working, stuck.

```
 #[fg=#98bb6c]✓ 2 #[fg=#7e9cd8]⏸ 1 #[fg=#dca561]⚙ 1 #[fg=#e82424]✗ 1
```

| Symbol | State | Color |
|---|---|---|
| `✓` | done / ready | `@tmux-ai-ok` |
| `⏸` | waiting for user input | `@tmux-ai-accent` |
| `⚙` | working | `@tmux-ai-wait` |
| `✗` | stuck | `@tmux-ai-stuck` |

Empty output when no agents. Counts are suppressed when zero
(`✓ 0` never renders). Idle agents don't contribute a segment.
A single space between glyph and count prevents wide-character overlap
on terminals that render geometric glyphs in two cells.

## Documentation

- `config.toml.example`: the existing `@tmux-ai-accent` reference block
  expands to list all seven palette options with hex defaults and a
  one-line example of overriding a single role.
- `README.md`: new three-line **Theming** subsection under *Config*,
  pointing to the reference block and the Kanagawa-Wave default.

## Tests to Update

- `tests/bats/test_notify_bin.bats` — asserts on notify color strings if any.
- `tests/bats/test_dash.bats` — asserts on dash rendered output / colors.
- `tests/bats/test_sidebar.bats` — asserts on sidebar rendered output / colors.
- `tests/bats/test_state.bats` — covers the new `load_palette` helper.

Where existing assertions checked literal `\033[33m` etc., they now
check the truecolor equivalents. A shared test helper computes
`$EXPECTED_OK_COLOR` etc. from the same defaults, so if we later swap
palettes the tests still pass.

## Non-Goals

- New keybindings or removed keybindings.
- Changes to agent detection, spawn, or registry.
- Changes to install flow or `install.sh`.
- Nerd Font glyphs anywhere.
- 256-color or 8-color fallback paths.
- Theming plugins or a theme-switching command.

## Acceptance

The redesign ships when:

1. `tmux.conf` contains zero hex literals outside the palette block.
2. All seven `@tmux-ai-*` options, when overridden before sourcing,
   propagate to status bar, pane borders, dash, and sidebar.
3. Dash and sidebar render identical hex codes to the status bar for
   each state.
4. Existing test suite passes with updated color assertions.
5. The three scenarios rendered in the brainstorming preview (normal
   work, DND + stuck agent, agents session) match reality in a real
   tmux session.
