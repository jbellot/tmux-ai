#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  touch "$HOME/.tmux.conf"
}

@test "install.sh symlinks all bin scripts into ~/.local/bin" {
  "$PROJECT_ROOT/install.sh"
  [ -L "$HOME/.local/bin/tmux-ai" ]
  [ -L "$HOME/.local/bin/tmux-ai-spawn" ]
  [ -L "$HOME/.local/bin/tmux-ai-dash" ]
  [ -L "$HOME/.local/bin/tmux-ai-status" ]
  [ -L "$HOME/.local/bin/tmux-ai-notify" ]
  [ -L "$HOME/.local/bin/tmux-ai-detect" ]
  [ -L "$HOME/.local/bin/tmux-ai-dnd" ]
}

@test "install.sh appends source-file line with marker to .tmux.conf" {
  "$PROJECT_ROOT/install.sh"
  run grep -c '# >>> tmux-ai >>>' "$HOME/.tmux.conf"
  assert_output "1"
  run grep -c 'source-file' "$HOME/.tmux.conf"
  [ "$output" -ge 1 ]
}

@test "install.sh is idempotent (running twice doesn't duplicate block)" {
  "$PROJECT_ROOT/install.sh"
  "$PROJECT_ROOT/install.sh"
  run grep -c '# >>> tmux-ai >>>' "$HOME/.tmux.conf"
  assert_output "1"
}

@test "install.sh writes config.toml if absent" {
  "$PROJECT_ROOT/install.sh"
  [ -f "$HOME/.config/tmux-ai/config.toml" ]
}

@test "install.sh --uninstall reverses the changes" {
  "$PROJECT_ROOT/install.sh"
  "$PROJECT_ROOT/install.sh" --uninstall
  [ ! -L "$HOME/.local/bin/tmux-ai" ]
  run grep -c '# >>> tmux-ai >>>' "$HOME/.tmux.conf"
  assert_output "0"
}

@test "install.sh marker block sources tmux.conf not tmux-ai.tmux.conf" {
  "$PROJECT_ROOT/install.sh"
  run grep -F "source-file $PROJECT_ROOT/tmux.conf" "$HOME/.tmux.conf"
  assert_success
  run grep -F "source-file $PROJECT_ROOT/tmux-ai.tmux.conf" "$HOME/.tmux.conf"
  [ "$status" -ne 0 ]
}
