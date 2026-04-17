#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  export NOTIFY_SEND_STUB_LOG="$BATS_TEST_TMPDIR/notify_log"
  : > "$NOTIFY_SEND_STUB_LOG"

  # Put a notify-send stub on PATH that logs invocations
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NOTIFY_SEND_STUB_LOG"
STUB
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"

  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/config.sh"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/notify.sh"

  # Ensure runtime dir exists so DND flag tests can touch into it
  tmux_ai_runtime_dir >/dev/null
}

@test "notify_desktop calls notify-send with title and body" {
  notify_desktop "title" "body"
  run cat "$NOTIFY_SEND_STUB_LOG"
  assert_output --partial "title"
  assert_output --partial "body"
}

@test "notify_desktop is a no-op when DND flag present" {
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  notify_desktop "title" "body"
  run wc -l < "$NOTIFY_SEND_STUB_LOG"
  assert_output "0"
}

@test "notify_desktop is a no-op when desktop=false in config" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[notifications]
desktop = false
EOF
  notify_desktop "title" "body"
  run wc -l < "$NOTIFY_SEND_STUB_LOG"
  assert_output "0"
}

@test "notify_desktop succeeds silently when notify-send missing" {
  export PATH="/nonexistent-only"
  run notify_desktop "title" "body"
  assert_success
}
