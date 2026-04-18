#!/usr/bin/env bash
# shellcheck disable=SC2148
# Claude Code adapter. Generates a per-pane settings.json that wires
# lifecycle hooks to tmux-ai-notify, and exposes register/uninstall.

_claude_settings_dir() {
  local d
  d="$(tmux_ai_runtime_dir)/claude-settings"
  mkdir -p "$d"
  printf '%s\n' "$d"
}

_claude_settings_path() {
  printf '%s/%s.json\n' "$(_claude_settings_dir)" "${1//\//_}"
}

# Print path to the generated settings file on stdout.
claude_register_hooks() {
  local pane="$1"
  local notify
  notify="${TMUX_AI_NOTIFY_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/tmux-ai-notify}"
  local path
  path="$(_claude_settings_path "$pane")"

  jq -n \
    --arg notify "$notify" \
    --arg pane "$pane" '
    {
      hooks: {
        SessionStart:     [{hooks: [{type:"command", command: ($notify + " session_start \"" + $pane + "\"")}]}],
        UserPromptSubmit: [{hooks: [{type:"command", command: ($notify + " prompt_submit \"" + $pane + "\"")}]}],
        Stop:             [{hooks: [{type:"command", command: ($notify + " stop \"" + $pane + "\"")}]}],
        Notification:     [{hooks: [{type:"command", command: ($notify + " notification \"" + $pane + "\"")}]}]
      }
    }' > "$path"

  printf '%s\n' "$path"
}

claude_uninstall_hooks() {
  local pane="$1"
  rm -f "$(_claude_settings_path "$pane")"
}

# parse_state is a no-op for hook-driven adapters; defined for interface
# symmetry with the generic adapter.
claude_parse_state() { return 0; }

# Print the env pairs the spawn command needs.
# Usage: eval "$(claude_spawn_env <pane>)"
claude_spawn_env() {
  local pane="$1"
  local settings
  settings="$(_claude_settings_path "$pane")"
  printf "export CLAUDE_SETTINGS=%q\n" "$settings"
  printf "export TMUX_AI_NOTIFY_BIN=%q\n" "${TMUX_AI_NOTIFY_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/tmux-ai-notify}"
}

claude_spawn_cmd() {
  local cmd
  cmd="$(config_get agents.claude spawn_command claude)"
  printf '%s\n' "$cmd"
}
