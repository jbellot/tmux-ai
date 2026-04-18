#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  source "$PROJECT_ROOT/adapters/claude.sh"
  export TMUX_AI_NOTIFY_BIN="$PROJECT_ROOT/bin/tmux-ai-notify"
}

@test "claude_register_hooks writes a settings file containing the 4 hooks" {
  local settings
  settings="$(claude_register_hooks "%5")"
  [ -f "$settings" ]
  run jq -r '.hooks | keys | sort | join(",")' "$settings"
  assert_output "Notification,SessionStart,Stop,UserPromptSubmit"
}

@test "generated hook command invokes tmux-ai-notify with correct event" {
  local settings
  settings="$(claude_register_hooks "%5")"
  run jq -r '.hooks.Stop[0].hooks[0].command' "$settings"
  assert_output --partial "tmux-ai-notify stop \"%5\""
}

@test "claude_uninstall_hooks removes the settings file" {
  local settings
  settings="$(claude_register_hooks "%5")"
  [ -f "$settings" ]
  claude_uninstall_hooks "%5"
  [ ! -f "$settings" ]
}

@test "end-to-end: fake-claude drives state via injected hooks" {
  state_init
  state_register "%99" agent=claude project=demo cwd="$PWD" state=idle

  # Simulate what spawn would do: register hooks, then launch fake-claude
  # with the settings env + pane env, piping event names.
  local settings
  settings="$(claude_register_hooks "%99")"

  TMUX_PANE="%99" TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
  bash -c '
    echo prompt_submit
    echo stop
  ' | TMUX_PANE="%99" TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
      "$PROJECT_ROOT/tests/stubs/fake-claude"

  run state_get "%99" state
  assert_output "done"

  claude_uninstall_hooks "%99"
}
