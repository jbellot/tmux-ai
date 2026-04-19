#!/usr/bin/env bash
# shellcheck disable=SC2148
# Sourced after lib/common.sh. Manages $XDG_RUNTIME_DIR/tmux-ai/agents.json.

_state_file() { printf '%s/agents.json\n' "$(tmux_ai_runtime_dir)"; }
_state_lock() { printf '%s/agents.json.lock\n' "$(tmux_ai_runtime_dir)"; }

# Move a corrupt state file aside and log. Returns 0 so callers can continue.
_state_recover() {
  local f ts
  f="$(_state_file)"
  ts="$(date +%s)"
  mv "$f" "${f}.corrupt.${ts}" 2>/dev/null || true
  printf '{}' > "$f"
  tmux_ai_log "state: corrupt file moved to ${f}.corrupt.${ts}"
  return 0
}

# Validate state file; recover if broken.
_state_validate() {
  local f
  f="$(_state_file)"
  [ -f "$f" ] || { printf '{}' > "$f"; return 0; }
  jq -e . "$f" >/dev/null 2>&1 || _state_recover
}

# Run a mutation under flock. Usage: _state_with_lock <jq_expr> [--arg k v ...]
_state_with_lock() {
  local lock f
  lock="$(_state_lock)"
  f="$(_state_file)"
  _state_validate
  (
    flock -w 2 9 || { tmux_ai_log "state: lock timeout"; exit 1; }
    local tmp
    tmp="$(mktemp "${f}.XXXXXX")"
    if jq "$@" "$f" > "$tmp" 2>>"$(tmux_ai_state_dir)/tmux-ai.log"; then
      mv "$tmp" "$f"
    else
      rm -f "$tmp"
      tmux_ai_log "state: jq mutation failed"
      exit 1
    fi
  ) 9>"$lock"
}

state_init() {
  _state_validate
}

# state_register <pane_id> key=value [key=value ...]
state_register() {
  local pane="$1"; shift
  local args=(--arg p "$pane")
  local set_expr='. + {($p): {}}'
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"
    v="${kv#*=}"
    args+=(--arg "k_$k" "$k" --arg "v_$k" "$v")
    set_expr="$set_expr | .[\$p][\$k_$k] = \$v_$k"
  done
  # Add registered_ts if not explicit
  if [[ " $* " != *" registered_ts="* ]]; then
    args+=(--arg rts "$(date +%s)")
    set_expr="$set_expr | .[\$p].registered_ts = \$rts"
  fi
  _state_with_lock "${args[@]}" "$set_expr"
}

state_set() {
  local pane="$1" key="$2" value="$3"
  _state_with_lock --arg p "$pane" --arg k "$key" --arg v "$value" \
    '.[$p][$k] = $v'
}

state_get() {
  local pane="$1" key="$2" f
  f="$(_state_file)"
  _state_validate
  jq -r --arg p "$pane" --arg k "$key" '.[$p][$k] // ""' "$f"
}

state_unregister() {
  local pane="$1"
  _state_with_lock --arg p "$pane" 'del(.[$p])'
}

state_list() {
  local f
  f="$(_state_file)"
  _state_validate
  # keys_unsorted preserves JSON insertion order so the navigation order
  # in dash/sidebar lines up with the rendered rows (which use to_entries).
  jq -r 'keys_unsorted[]' "$f"
}

state_dump() {
  local f
  f="$(_state_file)"
  _state_validate
  cat "$f"
}

# Convert "#RRGGBB" or "RRGGBB" into a truecolor foreground ANSI escape.
# Used by dash + sidebar (which emit ANSI) to stay in lock-step with the
# status bar (which uses tmux's own #[fg=#hex] syntax). We don't do bg
# escapes because the design leaves background at terminal default.
hex_to_truecolor_fg() {
  local hex="${1#\#}"
  # Reject anything that isn't exactly 6 hex digits — keeps us quiet on
  # malformed user-supplied @tmux-ai-* options instead of leaking bash
  # arithmetic errors to stderr seven times on every script invocation.
  if [[ ! "$hex" =~ ^[0-9A-Fa-f]{6}$ ]]; then
    return 1
  fi
  printf '\033[38;2;%d;%d;%dm' \
    "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

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
  C_ACCENT=$(hex_to_truecolor_fg "$(_tmux_opt @tmux-ai-accent '#7e9cd8')" \
    || hex_to_truecolor_fg '#7e9cd8')
  C_FG=$(hex_to_truecolor_fg     "$(_tmux_opt @tmux-ai-fg     '#dcd7ba')" \
    || hex_to_truecolor_fg '#dcd7ba')
  C_DIM=$(hex_to_truecolor_fg    "$(_tmux_opt @tmux-ai-dim    '#727169')" \
    || hex_to_truecolor_fg '#727169')
  C_SEP=$(hex_to_truecolor_fg    "$(_tmux_opt @tmux-ai-sep    '#363646')" \
    || hex_to_truecolor_fg '#363646')
  C_OK=$(hex_to_truecolor_fg     "$(_tmux_opt @tmux-ai-ok     '#98bb6c')" \
    || hex_to_truecolor_fg '#98bb6c')
  C_WAIT=$(hex_to_truecolor_fg   "$(_tmux_opt @tmux-ai-wait   '#dca561')" \
    || hex_to_truecolor_fg '#dca561')
  C_STUCK=$(hex_to_truecolor_fg  "$(_tmux_opt @tmux-ai-stuck  '#e82424')" \
    || hex_to_truecolor_fg '#e82424')
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM_ATTR=$'\033[2m'
}
