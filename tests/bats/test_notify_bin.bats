#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # no-op notify-send
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  export TMUX_AI_LIB="$PROJECT_ROOT/lib"
}

@test "prompt_submit transitions registered agent to working" {
  # pre-register via state helpers (exercised through the lib)
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=idle project=foo

  run "$PROJECT_ROOT/bin/tmux-ai-notify" prompt_submit "%5"
  assert_success
  run state_get "%5" state
  assert_output "working"
}

@test "stop transitions working agent to done" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5" </dev/null
  run state_get "%5" state
  assert_output "done"
}

# Bug: skills like superpowers/brainstorming ask plain-text questions
# at turn end. Stop fires → state=done, but the user still needs to
# answer. If the last assistant message ends with "?", treat Stop as a
# waiting signal, not a done signal.
@test "stop with transcript ending in '?' transitions to waiting" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  local transcript="$BATS_TEST_TMPDIR/transcript.jsonl"
  cat > "$transcript" <<'EOF'
{"type":"user","message":{"role":"user","content":"hey"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Would you prefer X or Y?"}]}}
EOF

  printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$transcript" \
    | "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"

  run state_get "%5" state
  assert_output "waiting"
}

# Same hook path, non-question ending → stay with current done behavior.
@test "stop with transcript ending in '.' transitions to done" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  local transcript="$BATS_TEST_TMPDIR/transcript.jsonl"
  cat > "$transcript" <<'EOF'
{"type":"user","message":{"role":"user","content":"hey"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All done."}]}}
EOF

  printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$transcript" \
    | "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"

  run state_get "%5" state
  assert_output "done"
}

# A turn whose final assistant block is a tool_use (no text at all) is
# not a question — fall back to done.
@test "stop with transcript containing only tool_use transitions to done" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  local transcript="$BATS_TEST_TMPDIR/transcript.jsonl"
  cat > "$transcript" <<'EOF'
{"type":"user","message":{"role":"user","content":"hey"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"x","name":"Read","input":{}}]}}
EOF

  printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$transcript" \
    | "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"

  run state_get "%5" state
  assert_output "done"
}

# A malformed transcript must NOT break the hook — degrade to the
# previous "done" behavior rather than error out.
@test "stop with malformed transcript degrades to done" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  local transcript="$BATS_TEST_TMPDIR/transcript.jsonl"
  printf '{this is not valid json\n' > "$transcript"

  printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$transcript" \
    | "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"

  run state_get "%5" state
  assert_output "done"
}

# Messages often wrap text in whitespace/newlines after the question
# mark (markdown rendering, signoffs). Detection must tolerate that.
@test "stop with trailing whitespace after '?' still detects question" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  local transcript="$BATS_TEST_TMPDIR/transcript.jsonl"
  # Last text block ends with a real "?" then a trailing newline
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Ready to proceed?\n\n"}]}}' > "$transcript"

  printf '{"transcript_path":"%s","hook_event_name":"Stop"}' "$transcript" \
    | "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"

  run state_get "%5" state
  assert_output "waiting"
}

@test "notification event transitions agent to waiting" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" notification "%5"
  run state_get "%5" state
  assert_output "waiting"
}

# Claude's Notification hook fires not only for mid-turn permission
# prompts but also when the post-turn idle input area renders. That
# second firing arrives AFTER Stop has already set state=done. A naive
# handler overwrites done → waiting and the dashboard wedges.
@test "notification after stop does NOT overwrite done state" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=done project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" notification "%5"
  run state_get "%5" state
  assert_output "done"
}

@test "notification while idle stays idle (session-start notifications)" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=idle project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" notification "%5"
  run state_get "%5" state
  assert_output "idle"
}

# The main bug fix: when Claude asks for tool-permission (Notification
# → waiting) and the user approves, Claude fires PreToolUse just before
# running the tool. Without a hook here, state wedges on "waiting" until
# Stop fires at end of turn. tool_use must transition back to working.
@test "tool_use transitions waiting agent to working" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=waiting project=foo turn_started_ts=100

  "$PROJECT_ROOT/bin/tmux-ai-notify" tool_use "%5"
  run state_get "%5" state
  assert_output "working"
}

# tool_use fires for every tool call, including auto-approved ones
# mid-turn. Running it on an already-working pane must be a no-op,
# not a state flicker.
@test "tool_use on working agent stays working" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=working project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" tool_use "%5"
  run state_get "%5" state
  assert_output "working"
}

# A late/out-of-order PreToolUse arriving after Stop must NOT
# resurrect a finished pane. Same guard pattern as notification.
@test "tool_use after stop does NOT overwrite done state" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=done project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" tool_use "%5"
  run state_get "%5" state
  assert_output "done"
}

# tool_use fires mid-turn, so it must NOT reset turn_started_ts — the
# "elapsed" column in the dashboard would reset on every tool call.
@test "tool_use preserves turn_started_ts" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=waiting project=foo turn_started_ts=1000

  "$PROJECT_ROOT/bin/tmux-ai-notify" tool_use "%5"
  run state_get "%5" turn_started_ts
  assert_output "1000"
}

@test "pane_exited unregisters the pane" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=done project=foo

  "$PROJECT_ROOT/bin/tmux-ai-notify" pane_exited "%5"
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/state.sh'; jq 'has(\"%5\")' \"\$(_state_file)\""
  assert_output "false"
}

@test "unknown event is logged but not fatal" {
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  state_init
  state_register "%5" agent=claude state=idle

  run "$PROJECT_ROOT/bin/tmux-ai-notify" bogus_event "%5"
  assert_success
  run cat "$XDG_STATE_HOME/tmux-ai/tmux-ai.log"
  assert_output --partial "unknown event"
}
