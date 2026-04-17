#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/config.sh"
}

@test "config_get returns default when no config file exists" {
  run config_get notifications desktop true
  assert_output "true"
}

@test "config_get reads a boolean" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[notifications]
desktop = false
EOF
  run config_get notifications desktop true
  assert_output "false"
}

@test "config_get reads an integer" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[detection]
stuck_after_seconds = 180
EOF
  run config_get detection stuck_after_seconds 60
  assert_output "180"
}

@test "config_get reads a quoted string" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[agents.claude]
spawn_command = "claude --continue"
EOF
  run config_get agents.claude spawn_command claude
  assert_output "claude --continue"
}

@test "config_get returns default for missing section" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[other]
x = 1
EOF
  run config_get notifications desktop true
  assert_output "true"
}

@test "config_get ignores comment lines" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[notifications]
# desktop = true
desktop = false
EOF
  run config_get notifications desktop true
  assert_output "false"
}
