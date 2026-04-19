#!/usr/bin/env bash
# shellcheck disable=SC2148
# Notification backends. Sourced after common.sh and config.sh.

_notify_dnd_active() {
  [ -f "$(tmux_ai_runtime_dir)/dnd.flag" ]
}

_notify_dnd_auto_clear() {
  # Clear DND flag if older than 2 hours.
  local flag
  flag="$(tmux_ai_runtime_dir)/dnd.flag"
  [ -f "$flag" ] || return 0
  local age now
  now=$(date +%s)
  age=$(( now - $(stat -c %Y "$flag" 2>/dev/null || stat -f %m "$flag") ))
  if [ "$age" -gt 7200 ]; then
    rm -f "$flag" 2>/dev/null || true
    tmux_ai_log "dnd: auto-cleared after 2h"
  fi
}

notify_desktop() {
  local title="$1" body="$2"
  _notify_dnd_auto_clear
  _notify_dnd_active && return 0
  [ "$(config_get notifications desktop true)" = "true" ] || return 0
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a tmux-ai "$title" "$body" 2>/dev/null || true
  elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$title" -message "$body" 2>/dev/null || true
  elif command -v osascript >/dev/null 2>&1; then
    # Escape double quotes in title/body to avoid AppleScript injection
    local safe_title safe_body
    safe_title="${title//\"/\\\"}"
    safe_body="${body//\"/\\\"}"
    osascript -e "display notification \"$safe_body\" with title \"$safe_title\"" 2>/dev/null || true
  else
    tmux_ai_log "notify: no desktop backend available"
  fi
  return 0
}

notify_sound() {
  local kind="$1"  # done|waiting|error|stuck
  _notify_dnd_auto_clear
  _notify_dnd_active && return 0
  [ "$(config_get notifications sound false)" = "true" ] || return 0
  # Pick sound file by kind; user can drop their own in
  # $XDG_CONFIG_HOME/tmux-ai/sounds/<kind>.wav
  local snd
  snd="$(tmux_ai_config_dir)/sounds/${kind}.wav"
  [ -f "$snd" ] || return 0
  if command -v paplay >/dev/null 2>&1; then
    paplay "$snd" 2>/dev/null || true
  elif command -v afplay >/dev/null 2>&1; then
    afplay "$snd" 2>/dev/null || true
  fi
  return 0
}

notify_push() {
  local title="$1" body="$2"
  _notify_dnd_auto_clear
  _notify_dnd_active && return 0
  [ "$(config_get notifications push false)" = "true" ] || return 0
  local target
  target="$(config_get notifications push_target '')"
  [ -n "$target" ] || return 0
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -d "$body" -H "Title: $title" "$target" >/dev/null 2>&1 || true
  fi
  return 0
}
