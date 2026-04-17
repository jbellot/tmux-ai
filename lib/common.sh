#!/usr/bin/env bash
# shellcheck disable=SC2148
# Sourced by every tmux-ai script. Provides paths and logging.

: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"

tmux_ai_runtime_dir() {
  local d="$XDG_RUNTIME_DIR/tmux-ai"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s\n' "$d"
}

tmux_ai_state_dir() {
  local d="$XDG_STATE_HOME/tmux-ai"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s\n' "$d"
}

tmux_ai_config_dir() {
  local d="$XDG_CONFIG_HOME/tmux-ai"
  mkdir -p "$d" 2>/dev/null || true
  printf '%s\n' "$d"
}

# Never fails: all errors swallowed. That's the contract — a broken log
# path must not cascade into a broken hook.
tmux_ai_log() {
  local msg="$*"
  local logdir="$XDG_STATE_HOME/tmux-ai"
  local logfile="$logdir/tmux-ai.log"
  { mkdir -p "$logdir" 2>/dev/null && \
    printf '%s %s\n' "$(date -Iseconds)" "$msg" >> "$logfile"; } 2>/dev/null || true
  return 0
}
