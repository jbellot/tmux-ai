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
  jq -r 'keys[]' "$f"
}

state_dump() {
  local f
  f="$(_state_file)"
  _state_validate
  cat "$f"
}
