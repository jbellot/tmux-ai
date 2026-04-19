#!/usr/bin/env bash
# shellcheck disable=SC2148
# Fallback adapter: content-hash heuristics from tmux capture-pane.

generic_tick() {
  local pane="$1"
  local now cur_hash prev_hash prev_ts cur_state
  now=$(date +%s)

  local _pane_content
  _pane_content=$(tmux capture-pane -p -t "$pane" 2>/dev/null)
  # CRC32 of the visible pane content. Detects spinner frames (same length,
  # different glyphs) and survives re-renders that shrink the visible area —
  # both of which a byte-length compare misses for TUI agents like claude.
  cur_hash=$(printf '%s' "$_pane_content" | cksum | awk '{print $1}')

  prev_hash=$(state_get "$pane" last_content_hash)
  prev_ts=$(state_get "$pane" last_byte_ts)
  cur_state=$(state_get "$pane" state)
  prev_ts=${prev_ts:-$now}

  local idle_after stuck_after
  idle_after=$(config_get detection idle_after_seconds 5)
  stuck_after=$(config_get detection stuck_after_seconds 180)

  local elapsed_quiet=$((now - prev_ts))

  if [ "$cur_hash" != "$prev_hash" ]; then
    state_set "$pane" last_content_hash "$cur_hash"
    state_set "$pane" last_byte_ts "$now"
    if [ "$cur_state" != "working" ] && [ "$cur_state" != "waiting" ]; then
      "$TMUX_AI_NOTIFY_BIN" prompt_submit "$pane" 2>/dev/null || true
    fi
    return 0
  fi

  # content hash unchanged → no activity this tick
  case "$cur_state" in
    working)
      if [ "$elapsed_quiet" -ge "$stuck_after" ]; then
        "$TMUX_AI_NOTIFY_BIN" stuck "$pane" 2>/dev/null || true
      elif [ "$elapsed_quiet" -ge "$idle_after" ]; then
        "$TMUX_AI_NOTIFY_BIN" stop "$pane" 2>/dev/null || true
      fi
      ;;
    stuck)
      # stay stuck; don't re-fire
      :
      ;;
  esac
  return 0
}
