#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
}

@test "--full creates ~/.tmux.conf symlink to project tmux.conf" {
  "$PROJECT_ROOT/install.sh" --full
  [ -L "$HOME/.tmux.conf" ]
  target=$(readlink "$HOME/.tmux.conf")
  [ "$target" = "$PROJECT_ROOT/tmux.conf" ]
}

@test "--full backs up pre-existing non-symlink .tmux.conf" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  [ "$output" -ge 1 ]
  run bash -c "cat '$HOME'/.tmux.conf.bak.*"
  assert_output --partial "my personal config"
}

@test "--full twice does not create a second backup" {
  echo "original" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  sleep 1
  "$PROJECT_ROOT/install.sh" --full
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  assert_output "1"
}

@test "--uninstall after --full removes symlink and restores backup" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  "$PROJECT_ROOT/install.sh" --uninstall
  [ ! -L "$HOME/.tmux.conf" ]
  run cat "$HOME/.tmux.conf"
  assert_output --partial "my personal config"
}

@test "--uninstall --no-restore removes symlink but leaves backup in place" {
  echo "my personal config" > "$HOME/.tmux.conf"
  "$PROJECT_ROOT/install.sh" --full
  "$PROJECT_ROOT/install.sh" --uninstall --no-restore
  [ ! -e "$HOME/.tmux.conf" ]
  run bash -c "ls '$HOME'/.tmux.conf.bak.* 2>/dev/null | wc -l"
  [ "$output" -ge 1 ]
}
