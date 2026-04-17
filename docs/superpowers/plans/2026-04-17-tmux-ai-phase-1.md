# tmux-ai Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working MVP of `tmux-ai`: a modular tmux layer that detects Claude Code agent state via hooks + pane monitoring, shows status in the tmux status-line, surfaces a read-only popup dashboard, and emits desktop notifications on `done` / `waiting` / `stuck` events. Includes DND, pane output capture, and the generic fallback adapter. Out of scope for Phase 1: opencode adapter, session templates, fuzzy jump, reconcile, dashboard bulk actions, last-message peek.

**Architecture:** Pure bash; no daemon. State is a single `flock`-protected JSON file under `$XDG_RUNTIME_DIR`, mutated by short-lived hook callbacks and queried by status-line / dashboard scripts. Per-agent adapters isolate Claude-Code-specific knowledge. All components testable in isolation against a stubbed `tmux` binary and a fake claude-code-like binary.

**Tech Stack:** bash ≥ 4, tmux ≥ 3.2, `jq`, `flock`, `fzf`, `libnotify-bin`. Tests in `bats-core` with `bats-assert` / `bats-support`.

**Spec reference:** `docs/superpowers/specs/2026-04-17-tmux-ai-design.md`.

---

## File structure produced by this plan

```
tmux-config/
├── bin/
│   ├── tmux-ai              dispatcher ('tmux-ai spawn claude' etc)
│   ├── tmux-ai-spawn        spawn-agent flow
│   ├── tmux-ai-dash         popup dashboard (read-only in phase 1)
│   ├── tmux-ai-status       status-line renderer
│   ├── tmux-ai-notify       notification emitter + state mutator
│   ├── tmux-ai-detect       pane scanner / stuck detector / auto-detect
│   └── tmux-ai-dnd          DND toggle
├── lib/
│   ├── common.sh            logging, paths, shared helpers
│   ├── state.sh             state registry (jq + flock helpers)
│   ├── config.sh            config loader (.toml → env)
│   └── notify.sh            notification backend helpers
├── adapters/
│   ├── claude.sh            Claude Code adapter
│   └── generic.sh           fallback adapter
├── tmux-ai.tmux.conf        keybindings + status-line snippet
├── config.toml.example      default config
├── install.sh               installer / uninstaller
├── tests/
│   ├── bats/                bats test files
│   └── stubs/               mock tmux + fake-claude
├── docs/
├── README.md
├── TESTING.md
└── .gitignore
```

Each `lib/` file is responsible for one concern so unit tests can exercise them in isolation. `bin/` scripts are thin CLIs wrapping `lib/` functions.

**Runtime-created paths (documented for reference, not created by code):**
- `$XDG_RUNTIME_DIR/tmux-ai/agents.json` — live state
- `$XDG_RUNTIME_DIR/tmux-ai/dnd.flag` — DND toggle
- `$XDG_STATE_HOME/tmux-ai/logs/<project>/<ts>.log` — pane logs
- `$XDG_STATE_HOME/tmux-ai/tmux-ai.log` — error log
- `$XDG_CONFIG_HOME/tmux-ai/config.toml` — user config

---

## Task 1: Repo skeleton, .gitignore, placeholder README

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `bin/` (directory)
- Create: `lib/` (directory)
- Create: `adapters/` (directory)
- Create: `tests/bats/` (directory)
- Create: `tests/stubs/` (directory)

- [ ] **Step 1: Create directories**

```bash
mkdir -p bin lib adapters tests/bats tests/stubs
```

- [ ] **Step 2: Write `.gitignore`**

```
# editor
*.swp
.DS_Store
# runtime state (shouldn't end up in repo, but belt+braces)
*.log
*.corrupt.*
# bats installation
tests/bats-core/
tests/bats-assert/
tests/bats-support/
```

- [ ] **Step 3: Write placeholder `README.md`**

```markdown
# tmux-ai

A modular tmux layer for managing AI coding agents. See
`docs/superpowers/specs/2026-04-17-tmux-ai-design.md` for full design.

Installation and usage docs land in Task 24.
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore README.md
git commit -m "chore: add repo skeleton and placeholder README"
```

---

## Task 2: Install bats test framework as git submodules

**Rationale:** `bats-core` + `bats-assert` + `bats-support` give us `assert_equal`, `assert_output`, `assert_success`, etc. Installing as submodules (vs a package manager) keeps test deps self-contained and pinned.

**Files:**
- Create: `tests/run-tests.sh`
- Create: `.gitmodules` (auto-created by `git submodule add`)

- [ ] **Step 1: Add submodules**

```bash
git submodule add https://github.com/bats-core/bats-core.git tests/bats-core
git submodule add https://github.com/bats-core/bats-assert.git tests/bats-assert
git submodule add https://github.com/bats-core/bats-support.git tests/bats-support
```

- [ ] **Step 2: Write `tests/run-tests.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec tests/bats-core/bin/bats tests/bats "$@"
```

- [ ] **Step 3: Make executable and smoke test**

```bash
chmod +x tests/run-tests.sh
# should find no tests yet but exit cleanly
tests/run-tests.sh || true
```

Expected: exits with "no tests found" message; no crash.

- [ ] **Step 4: Commit**

```bash
git add .gitmodules tests/bats-core tests/bats-assert tests/bats-support tests/run-tests.sh
git commit -m "test: add bats-core, bats-assert, bats-support as submodules"
```

---

## Task 3: `lib/common.sh` — paths, logging, XDG helpers

**Files:**
- Create: `lib/common.sh`
- Test: `tests/bats/test_common.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_common.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "tmux_ai_runtime_dir returns XDG_RUNTIME_DIR/tmux-ai and creates it" {
  run tmux_ai_runtime_dir
  assert_success
  assert_output "$XDG_RUNTIME_DIR/tmux-ai"
  [ -d "$XDG_RUNTIME_DIR/tmux-ai" ]
}

@test "tmux_ai_state_dir creates $XDG_STATE_HOME/tmux-ai" {
  tmux_ai_state_dir >/dev/null
  [ -d "$XDG_STATE_HOME/tmux-ai" ]
}

@test "tmux_ai_log appends timestamped line to tmux-ai.log" {
  tmux_ai_log "hello world"
  run cat "$XDG_STATE_HOME/tmux-ai/tmux-ai.log"
  assert_output --partial "hello world"
}

@test "tmux_ai_log never exits non-zero even if log dir is readonly" {
  mkdir -p "$XDG_STATE_HOME/tmux-ai"
  chmod 0500 "$XDG_STATE_HOME/tmux-ai"
  run tmux_ai_log "boom"
  chmod 0700 "$XDG_STATE_HOME/tmux-ai"  # cleanup
  assert_success
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_common.bats
```

Expected: fails, `lib/common.sh` missing.

- [ ] **Step 3: Implement `lib/common.sh`**

```bash
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
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_common.bats
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/bats/test_common.bats
git commit -m "feat(lib): add common.sh with XDG paths and never-fail logger"
```

---

## Task 4: `lib/state.sh` — flock'd JSON state registry

**Design:** a single `agents.json` object keyed by `pane_id`. Each entry: `{agent, project, cwd, pane, window, session, state, last_byte_ts, turn_started_ts, registered_ts, logfile, adapter}`. Writes go through `_state_with_lock` which flock's a 2-second-timeout. Reads don't lock (rare race, and readers can tolerate a slightly stale view).

**Files:**
- Create: `lib/state.sh`
- Test: `tests/bats/test_state.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_state.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "state_init creates empty agents.json" {
  state_init
  run cat "$(tmux_ai_runtime_dir)/agents.json"
  assert_output '{}'
}

@test "state_register adds a new entry keyed by pane id" {
  state_init
  state_register "%5" agent=claude project=foo cwd=/tmp pane=%5 state=idle
  run jq -r '."%5".agent' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "claude"
  run jq -r '."%5".state' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "idle"
}

@test "state_set updates a single field" {
  state_init
  state_register "%5" agent=claude state=idle
  state_set "%5" state working
  run jq -r '."%5".state' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "working"
}

@test "state_get returns a field" {
  state_init
  state_register "%5" agent=claude state=idle
  run state_get "%5" agent
  assert_output "claude"
}

@test "state_unregister removes an entry" {
  state_init
  state_register "%5" agent=claude
  state_unregister "%5"
  run jq 'has("%5")' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "false"
}

@test "state_list emits each pane id on its own line" {
  state_init
  state_register "%5" agent=claude
  state_register "%7" agent=claude
  run state_list
  assert_line "%5"
  assert_line "%7"
}

@test "corrupt state file is moved aside and rebuilt" {
  state_init
  echo "not json at all" > "$(tmux_ai_runtime_dir)/agents.json"
  state_register "%9" agent=claude
  run jq -r '."%9".agent' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "claude"
  # corrupt file should have been moved aside
  run bash -c 'ls "$(tmux_ai_runtime_dir)"/agents.json.corrupt.* 2>/dev/null | wc -l'
  assert_output "1"
}

@test "concurrent state_register calls don't lose writes" {
  state_init
  for i in $(seq 1 20); do
    state_register "%${i}" agent=claude &
  done
  wait
  run jq 'length' "$(tmux_ai_runtime_dir)/agents.json"
  assert_output "20"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_state.bats
```

Expected: all fail, `lib/state.sh` missing.

- [ ] **Step 3: Implement `lib/state.sh`**

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2148
# Sourced after lib/common.sh. Manages $XDG_RUNTIME_DIR/tmux-ai/agents.json.

_state_file() { printf '%s/agents.json\n' "$(tmux_ai_runtime_dir)"; }
_state_lock() { printf '%s/agents.json.lock\n' "$(tmux_ai_runtime_dir)"; }

# Move a corrupt state file aside and log. Returns 0 so callers can continue.
_state_recover() {
  local f ts
  f="$(_state_file)"
  ts="$(date +%s)"
  mv "$f" "${f}.corrupt.${ts}" 2>/dev/null || true
  printf '{}' > "$f"
  tmux_ai_log "state: corrupt file moved to ${f}.corrupt.${ts}"
  return 0
}

# Validate state file; recover if broken.
_state_validate() {
  local f
  f="$(_state_file)"
  [ -f "$f" ] || { printf '{}' > "$f"; return 0; }
  jq -e . "$f" >/dev/null 2>&1 || _state_recover
}

# Run a mutation under flock. Usage: _state_with_lock <jq_expr> [--arg k v ...]
_state_with_lock() {
  local lock f
  lock="$(_state_lock)"
  f="$(_state_file)"
  _state_validate
  (
    flock -w 2 9 || { tmux_ai_log "state: lock timeout"; exit 1; }
    local tmp
    tmp="$(mktemp "${f}.XXXXXX")"
    if jq "$@" "$f" > "$tmp" 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log"; then
      mv "$tmp" "$f"
    else
      rm -f "$tmp"
      tmux_ai_log "state: jq mutation failed"
      exit 1
    fi
  ) 9>"$lock"
}

state_init() {
  _state_validate
}

# state_register <pane_id> key=value [key=value ...]
state_register() {
  local pane="$1"; shift
  local args=(--arg p "$pane")
  local set_expr='. + {($p): {}}'
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"
    v="${kv#*=}"
    args+=(--arg "k_$k" "$k" --arg "v_$k" "$v")
    set_expr="$set_expr | .[\$p][\$k_$k] = \$v_$k"
  done
  # Add registered_ts if not explicit
  if [[ " $* " != *" registered_ts="* ]]; then
    args+=(--arg rts "$(date +%s)")
    set_expr="$set_expr | .[\$p].registered_ts = \$rts"
  fi
  _state_with_lock "${args[@]}" "$set_expr"
}

state_set() {
  local pane="$1" key="$2" value="$3"
  _state_with_lock --arg p "$pane" --arg k "$key" --arg v "$value" \
    '.[$p][$k] = $v'
}

state_get() {
  local pane="$1" key="$2" f
  f="$(_state_file)"
  _state_validate
  jq -r --arg p "$pane" --arg k "$key" '.[$p][$k] // ""' "$f"
}

state_unregister() {
  local pane="$1"
  _state_with_lock --arg p "$pane" 'del(.[$p])'
}

state_list() {
  local f
  f="$(_state_file)"
  _state_validate
  jq -r 'keys[]' "$f"
}

state_dump() {
  local f
  f="$(_state_file)"
  _state_validate
  cat "$f"
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_state.bats
```

Expected: 8 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/state.sh tests/bats/test_state.bats
git commit -m "feat(lib): add state registry with flock concurrency and corruption recovery"
```

---

## Task 5: `lib/config.sh` — minimal TOML-ish config loader

**Scope:** We only need simple `[section]`, `key = "value"`, `key = true|false`, `key = 123` lines. Full TOML is overkill; a few-line parser is enough for phase 1.

**Files:**
- Create: `lib/config.sh`
- Test: `tests/bats/test_config.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_config.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_config.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `lib/config.sh`**

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2148
# Minimal TOML-ish config reader. Supports [section], key = value,
# comments (#), and strings/bools/ints. Not a full TOML parser.

_config_file() { printf '%s/config.toml\n' "$(tmux_ai_config_dir)"; }

# config_get <section> <key> <default>
config_get() {
  local section="$1" key="$2" default="$3"
  local file
  file="$(_config_file)"
  [ -f "$file" ] || { printf '%s\n' "$default"; return 0; }

  local in_section=0 line stripped value
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip trailing whitespace
    stripped="${line%"${line##*[![:space:]]}"}"
    # Skip blank and comment lines
    case "$stripped" in ''|'#'*) continue ;; esac
    # Section header
    if [[ "$stripped" =~ ^\[([^]]+)\]$ ]]; then
      if [ "${BASH_REMATCH[1]}" = "$section" ]; then in_section=1; else in_section=0; fi
      continue
    fi
    [ "$in_section" -eq 1 ] || continue
    # key = value
    if [[ "$stripped" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      if [ "${BASH_REMATCH[1]}" = "$key" ]; then
        value="${BASH_REMATCH[2]}"
        # Strip surrounding quotes if present
        if [[ "$value" =~ ^\"(.*)\"$ ]]; then
          value="${BASH_REMATCH[1]}"
        fi
        printf '%s\n' "$value"
        return 0
      fi
    fi
  done < "$file"

  printf '%s\n' "$default"
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_config.bats
```

Expected: 6 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/bats/test_config.bats
git commit -m "feat(lib): add minimal TOML-ish config loader"
```

---

## Task 6: `tests/stubs/tmux` — recording tmux stub

**Purpose:** Tests source this stub onto `PATH` instead of real `tmux`. It records every call to `$TMUX_STUB_CALLS` (one line per call) and returns canned output from `$TMUX_STUB_RESPONSES` (keyed by the first arg). Lets us test scripts that invoke `tmux` without a live server.

**Files:**
- Create: `tests/stubs/tmux`
- Test: `tests/bats/test_tmux_stub.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_tmux_stub.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PATH="$PROJECT_ROOT/tests/stubs:$PATH"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
}

@test "tmux stub records a call" {
  tmux display-message "hello"
  run cat "$TMUX_STUB_CALLS"
  assert_output 'display-message hello'
}

@test "tmux stub returns canned output for a command" {
  echo "list-panes::%5 claude" >> "$TMUX_STUB_RESPONSES"
  run tmux list-panes
  assert_output "%5 claude"
}

@test "tmux stub returns empty for unknown command with no response" {
  run tmux some-obscure-command
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_tmux_stub.bats
```

Expected: fails — stub missing.

- [ ] **Step 3: Implement `tests/stubs/tmux`**

```bash
#!/usr/bin/env bash
# Recording tmux stub for unit tests.
# - Appends each call as one space-joined line to $TMUX_STUB_CALLS
# - Emits canned output from $TMUX_STUB_RESPONSES where the first
#   line matches "<subcommand>::<output>"

set -u
calls="${TMUX_STUB_CALLS:-/dev/null}"
responses="${TMUX_STUB_RESPONSES:-/dev/null}"

# Record the call
printf '%s\n' "$*" >> "$calls" 2>/dev/null || true

# Lookup canned response by subcommand (first arg)
if [ -f "$responses" ] && [ $# -gt 0 ]; then
  while IFS= read -r line; do
    key="${line%%::*}"
    rest="${line#*::}"
    if [ "$key" = "$1" ]; then
      printf '%s\n' "$rest"
      exit 0
    fi
  done < "$responses"
fi

exit 0
```

- [ ] **Step 4: Make executable**

```bash
chmod +x tests/stubs/tmux
```

- [ ] **Step 5: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_tmux_stub.bats
```

Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add tests/stubs/tmux tests/bats/test_tmux_stub.bats
git commit -m "test: add recording tmux stub for unit tests"
```

---

## Task 7: `lib/notify.sh` — notification backends

**Files:**
- Create: `lib/notify.sh`
- Test: `tests/bats/test_notify_lib.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_notify_lib.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_notify_lib.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `lib/notify.sh`**

```bash
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
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
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
  local snd="$(tmux_ai_config_dir)/sounds/${kind}.wav"
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
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_notify_lib.bats
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add lib/notify.sh tests/bats/test_notify_lib.bats
git commit -m "feat(lib): add notify backends with DND and config gating"
```

---

## Task 8: `bin/tmux-ai-notify` — event dispatcher

**Role:** Called by agent hooks. Maps a hook event to a state transition + notification. Usage: `tmux-ai-notify <event> <pane_id> [metadata...]`.

**Events handled:** `session_start`, `prompt_submit`, `stop`, `notification`, `pane_exited`, `stuck`.

**Files:**
- Create: `bin/tmux-ai-notify`
- Test: `tests/bats/test_notify_bin.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_notify_bin.bats`:

```bash
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

  "$PROJECT_ROOT/bin/tmux-ai-notify" stop "%5"
  run state_get "%5" state
  assert_output "done"
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_notify_bin.bats
```

Expected: all fail, script missing.

- [ ] **Step 3: Implement `bin/tmux-ai-notify`**

```bash
#!/usr/bin/env bash
# Hook entrypoint. Called by agent adapters on lifecycle events.
# Usage: tmux-ai-notify <event> <pane_id> [k=v ...]
#
# Intentionally swallows errors so a broken hook cannot freeze the agent.

set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/config.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/notify.sh"

main() {
  local event="${1:-}" pane="${2:-}"
  [ -n "$event" ] && [ -n "$pane" ] || { tmux_ai_log "notify: missing args"; return 0; }
  shift 2 || true

  local agent project now
  agent="$(state_get "$pane" agent)"
  project="$(state_get "$pane" project)"
  now="$(date +%s)"

  case "$event" in
    session_start)
      state_set "$pane" state idle
      state_set "$pane" last_byte_ts "$now"
      ;;
    prompt_submit)
      state_set "$pane" state working
      state_set "$pane" turn_started_ts "$now"
      state_set "$pane" last_byte_ts "$now"
      ;;
    stop)
      state_set "$pane" state done
      state_set "$pane" last_byte_ts "$now"
      notify_desktop "${agent:-agent} — done" "${project:-(unknown project)}"
      notify_sound done
      notify_push "${agent:-agent} — done" "${project:-(unknown project)}"
      ;;
    notification)
      state_set "$pane" state waiting
      state_set "$pane" last_byte_ts "$now"
      notify_desktop "${agent:-agent} — needs input" "${project:-(unknown project)}"
      notify_sound waiting
      notify_push "${agent:-agent} — needs input" "${project:-(unknown project)}"
      ;;
    stuck)
      state_set "$pane" state stuck
      notify_desktop "${agent:-agent} — stuck" "${project:-(unknown project)}"
      notify_sound stuck
      ;;
    pane_exited)
      state_unregister "$pane"
      ;;
    *)
      tmux_ai_log "notify: unknown event '$event' for pane $pane"
      ;;
  esac
  return 0
}

{ main "$@"; } 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log" || true
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-notify
tests/run-tests.sh tests/bats/test_notify_bin.bats
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-notify tests/bats/test_notify_bin.bats
git commit -m "feat(bin): add tmux-ai-notify event dispatcher"
```

---

## Task 9: `tests/stubs/fake-claude` — scripted claude-code-like binary

**Purpose:** Lets adapter tests drive the hook pipeline without installing real claude. Reads one word per line from stdin; each word is a hook event name that fires `tmux-ai-notify <event> $TMUX_PANE`.

**Files:**
- Create: `tests/stubs/fake-claude`

- [ ] **Step 1: Write `tests/stubs/fake-claude`**

```bash
#!/usr/bin/env bash
# Scripted fake agent. Reads event names from stdin; for each, invokes
# tmux-ai-notify (path from $TMUX_AI_NOTIFY_BIN) with the pane id
# from $TMUX_PANE.

set -u
: "${TMUX_AI_NOTIFY_BIN:?must be set}"
: "${TMUX_PANE:?must be set}"

# Fire session_start immediately on launch
"$TMUX_AI_NOTIFY_BIN" session_start "$TMUX_PANE"

while IFS= read -r event; do
  [ -n "$event" ] || continue
  "$TMUX_AI_NOTIFY_BIN" "$event" "$TMUX_PANE"
done
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tests/stubs/fake-claude
```

- [ ] **Step 3: Smoke test manually**

```bash
export TMUX_AI_NOTIFY_BIN="$(pwd)/bin/tmux-ai-notify"
export TMUX_PANE="%99"
export XDG_RUNTIME_DIR="/tmp/tmux-ai-smoke-$$"
mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
echo '{"%99":{"agent":"claude","state":"idle","project":"test"}}' > "$XDG_RUNTIME_DIR/tmux-ai/agents.json"
echo prompt_submit | tests/stubs/fake-claude
jq -r '."%99".state' "$XDG_RUNTIME_DIR/tmux-ai/agents.json"
rm -rf "$XDG_RUNTIME_DIR"
```

Expected output: `working`

- [ ] **Step 4: Commit**

```bash
git add tests/stubs/fake-claude
git commit -m "test: add fake-claude stub agent for adapter tests"
```

---

## Task 10: `adapters/claude.sh` — Claude Code adapter

**Responsibility:** `register_hooks` (write a settings.json fragment and `CLAUDE_SETTINGS` env injection), `uninstall_hooks` (reverse), `parse_state` (no-op for hook-driven adapters; present for adapter interface symmetry).

**Hook wiring:** We use the `CLAUDE_SETTINGS` env var which Claude Code reads as a JSON settings overlay. The adapter generates a per-pane settings file under `$XDG_RUNTIME_DIR/tmux-ai/claude-settings/<pane>.json` and points `CLAUDE_SETTINGS` at it in the spawn env.

**Files:**
- Create: `adapters/claude.sh`
- Test: `tests/bats/test_adapter_claude.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_adapter_claude.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_adapter_claude.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `adapters/claude.sh`**

```bash
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
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_adapter_claude.bats
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add adapters/claude.sh tests/bats/test_adapter_claude.bats
git commit -m "feat(adapter): add Claude Code adapter with per-pane hook settings"
```

---

## Task 11: `adapters/generic.sh` — fallback pane-monitor adapter

**Role:** No hooks. Provides `generic_tick <pane>` which computes state transitions based on byte-rate deltas. Called by `tmux-ai-detect`.

**Files:**
- Create: `adapters/generic.sh`
- Test: `tests/bats/test_adapter_generic.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_adapter_generic.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # tmux stub that serves canned capture-pane output
  mkdir -p "$BATS_TEST_TMPDIR/path"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/adapters/generic.sh"
}

@test "generic_tick transitions idle->working when bytes grow" {
  state_init
  state_register "%5" agent=claude state=idle last_byte_count=100 last_byte_ts=1000
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "working"
}

@test "generic_tick transitions working->done when bytes quiescent past idle_after_seconds" {
  state_init
  local now past
  now=$(date +%s)
  past=$((now - 10))
  state_register "%5" agent=claude state=working last_byte_count=500 last_byte_ts="$past"
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "done"
}

@test "generic_tick transitions working->stuck when quiet past stuck_after_seconds" {
  cat > "$XDG_CONFIG_HOME/tmux-ai/config.toml" <<EOF
[detection]
stuck_after_seconds = 5
idle_after_seconds = 999
EOF
  state_init
  local now past
  now=$(date +%s)
  past=$((now - 10))
  state_register "%5" agent=claude state=working last_byte_count=500 last_byte_ts="$past"
  echo "capture-pane::$(printf 'x%.0s' $(seq 1 500))" > "$TMUX_STUB_RESPONSES"
  generic_tick "%5"
  run state_get "%5" state
  assert_output "stuck"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_adapter_generic.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `adapters/generic.sh`**

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2148
# Fallback adapter: byte-rate heuristics from tmux capture-pane.

generic_tick() {
  local pane="$1"
  local now cur_bytes prev_bytes prev_ts cur_state
  now=$(date +%s)

  cur_bytes=$(tmux capture-pane -p -t "$pane" 2>/dev/null | wc -c)
  cur_bytes=${cur_bytes:-0}

  prev_bytes=$(state_get "$pane" last_byte_count)
  prev_ts=$(state_get "$pane" last_byte_ts)
  cur_state=$(state_get "$pane" state)
  prev_bytes=${prev_bytes:-0}
  prev_ts=${prev_ts:-$now}

  local idle_after stuck_after
  idle_after=$(config_get detection idle_after_seconds 5)
  stuck_after=$(config_get detection stuck_after_seconds 180)

  local elapsed_quiet=$((now - prev_ts))

  if [ "$cur_bytes" -gt "$prev_bytes" ]; then
    state_set "$pane" last_byte_count "$cur_bytes"
    state_set "$pane" last_byte_ts "$now"
    if [ "$cur_state" != "working" ] && [ "$cur_state" != "waiting" ]; then
      "$TMUX_AI_NOTIFY_BIN" prompt_submit "$pane" 2>/dev/null || true
    fi
    return 0
  fi

  # bytes quiet
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
```

Note: tests set `TMUX_AI_NOTIFY_BIN` via the setup indirectly — it's also exported inline:

- [ ] **Step 4: Add `TMUX_AI_NOTIFY_BIN` export to test setup**

Edit `tests/bats/test_adapter_generic.bats` `setup()` — add this line before sourcing the adapter:

```bash
  export TMUX_AI_NOTIFY_BIN="$PROJECT_ROOT/bin/tmux-ai-notify"
```

- [ ] **Step 5: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_adapter_generic.bats
```

Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add adapters/generic.sh tests/bats/test_adapter_generic.bats
git commit -m "feat(adapter): add generic pane-monitor fallback adapter"
```

---

## Task 12: `bin/tmux-ai-detect` — scan + stuck loop + auto-detect

**Role:** Called by tmux's `status-interval`. Does three things per tick:
1. Enumerate live panes; auto-register any running `claude|opencode` that isn't in the registry.
2. Run `generic_tick` for every registered pane whose adapter is `generic`.
3. Run stuck check for hook-driven adapters too (their state can go stuck even though hooks are wired — agent could hang mid-turn).

**Files:**
- Create: `bin/tmux-ai-detect`
- Test: `tests/bats/test_detect.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_detect.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  mkdir -p "$BATS_TEST_TMPDIR/path"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  # no-op notify-send
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  : > "$TMUX_STUB_CALLS"
  : > "$TMUX_STUB_RESPONSES"
}

@test "auto-register: unknown pane running claude gets registered with generic adapter" {
  state_init
  # tmux list-panes returns one pane %10 running 'claude' with cwd /tmp
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  run state_get "%10" agent
  assert_output "claude"
  run state_get "%10" adapter
  assert_output "generic"
}

@test "detect skips already-registered panes" {
  state_init
  state_register "%10" agent=claude adapter=claude state=idle last_byte_count=0 last_byte_ts="$(date +%s)"
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  # adapter should still be 'claude', not overwritten
  run state_get "%10" adapter
  assert_output "claude"
}

@test "detect skips panes whose process is not a known agent" {
  state_init
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 vim /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/state.sh'; jq 'length' \"\$(_state_file)\""
  assert_output "0"
}

@test "detect garbage-collects registered panes that no longer exist" {
  state_init
  state_register "%10" agent=claude adapter=claude state=done
  state_register "%11" agent=claude adapter=claude state=idle
  # tmux list-panes only returns %10 — %11 has died
  cat > "$TMUX_STUB_RESPONSES" <<EOF
list-panes::%10 claude /tmp main 1.0 s1
EOF
  "$PROJECT_ROOT/bin/tmux-ai-detect"
  # %11 should be gone
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/state.sh'; jq 'has(\"%11\")' \"\$(_state_file)\""
  assert_output "false"
  # %10 should remain
  run bash -c "source '$PROJECT_ROOT/lib/common.sh'; source '$PROJECT_ROOT/lib/state.sh'; jq 'has(\"%10\")' \"\$(_state_file)\""
  assert_output "true"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_detect.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai-detect`**

```bash
#!/usr/bin/env bash
set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
TMUX_AI_ADAPTERS="${TMUX_AI_ADAPTERS:-$(cd "$(dirname "$0")/../adapters" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/config.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_ADAPTERS/generic.sh"

export TMUX_AI_NOTIFY_BIN="${TMUX_AI_NOTIFY_BIN:-$(cd "$(dirname "$0")" && pwd)/tmux-ai-notify}"

KNOWN_AGENTS_RE='^(claude|opencode)$'

auto_detect() {
  # tmux list-panes -a -F "#{pane_id} #{pane_current_command} #{pane_current_path} #{window_name} #{window_index}.#{pane_index} #{session_name}"
  local line pane cmd cwd win idx sess project
  while IFS=' ' read -r pane cmd cwd win idx sess; do
    [ -n "$pane" ] || continue
    [[ "$cmd" =~ $KNOWN_AGENTS_RE ]] || continue
    # Skip if already registered
    if jq -e --arg p "$pane" 'has($p)' "$(tmux_ai_runtime_dir)/agents.json" >/dev/null 2>&1; then
      continue
    fi
    project="$(basename "$cwd")"
    state_register "$pane" \
      agent="$cmd" \
      project="$project" \
      cwd="$cwd" \
      window="$win" \
      pane_index="$idx" \
      session="$sess" \
      state=idle \
      adapter=generic \
      last_byte_count=0 \
      last_byte_ts="$(date +%s)"
    tmux_ai_log "detect: auto-registered $pane ($cmd in $project)"
  done < <(tmux list-panes -a -F "#{pane_id} #{pane_current_command} #{pane_current_path} #{window_name} #{window_index}.#{pane_index} #{session_name}" 2>/dev/null)
}

tick_all() {
  local pane adapter
  while IFS= read -r pane; do
    [ -n "$pane" ] || continue
    adapter="$(state_get "$pane" adapter)"
    case "$adapter" in
      generic) generic_tick "$pane" ;;
      *) : ;;  # hook-driven adapters update state on their own
    esac
  done < <(state_list)
}

# Remove registry entries for panes tmux no longer knows about.
gc_dead_panes() {
  local live_panes_file tmp pane
  live_panes_file="$(mktemp)"
  tmp="$(mktemp)"
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null > "$live_panes_file" || true
  while IFS= read -r pane; do
    [ -n "$pane" ] || continue
    if ! grep -qxF "$pane" "$live_panes_file"; then
      "$TMUX_AI_NOTIFY_BIN" pane_exited "$pane" 2>/dev/null || true
    fi
  done < <(state_list)
  rm -f "$live_panes_file" "$tmp"
}

main() {
  state_init
  gc_dead_panes
  auto_detect
  tick_all
}

{ main "$@"; } 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log" || true
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-detect
tests/run-tests.sh tests/bats/test_detect.bats
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-detect tests/bats/test_detect.bats
git commit -m "feat(bin): add tmux-ai-detect for auto-register + stuck detection"
```

---

## Task 13: `bin/tmux-ai-status` — status-line renderer

**Role:** Prints a short string to stdout for tmux's `status-right`. Fast (< 50ms) because tmux calls it frequently. Reads state file directly with jq.

**Files:**
- Create: `bin/tmux-ai-status`
- Test: `tests/bats/test_status.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_status.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "status prints empty when no agents registered" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output ""
}

@test "status prints inline icons for <=3 agents" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  state_register "%2" agent=claude project=bar state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "status prints aggregated counters for >3 agents" {
  state_init
  state_register "%1" agent=claude project=a state=working
  state_register "%2" agent=claude project=b state=working
  state_register "%3" agent=claude project=c state=waiting
  state_register "%4" agent=claude project=d state=done
  state_register "%5" agent=claude project=e state=done
  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "AI:"
  assert_output --partial "2"
  assert_output --partial "1"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_status.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai-status`**

```bash
#!/usr/bin/env bash
set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/config.sh"

ICON_WORK="⚙"
ICON_WAIT="⏸"
ICON_DONE="✓"
ICON_STUCK="✗"
ICON_ERROR="!"

icon_for() {
  case "$1" in
    working) printf '%s' "$ICON_WORK" ;;
    waiting) printf '%s' "$ICON_WAIT" ;;
    done)    printf '%s' "$ICON_DONE" ;;
    stuck)   printf '%s' "$ICON_STUCK" ;;
    error)   printf '%s' "$ICON_ERROR" ;;
    *)       printf '·' ;;
  esac
}

render() {
  state_init
  local file count threshold
  file="$(_state_file)"
  count=$(jq 'length' "$file" 2>/dev/null || echo 0)
  threshold=$(config_get status inline_threshold 3)

  [ "$count" -eq 0 ] && return 0

  if [ "$count" -le "$threshold" ]; then
    # inline: "⚙ foo ⏸ bar ✓ baz"
    local out=""
    while IFS= read -r entry; do
      local project state
      project=$(echo "$entry" | jq -r '.project // "?"')
      state=$(echo "$entry"   | jq -r '.state // "idle"')
      out="${out}$(icon_for "$state") ${project} "
    done < <(jq -c '.[]' "$file")
    printf '%s' "${out% }"
  else
    # aggregated: "AI: 2⚙ 1⏸ 3✓"
    local w wa d s
    w=$(jq  '[.[] | select(.state=="working")] | length' "$file")
    wa=$(jq '[.[] | select(.state=="waiting")] | length' "$file")
    d=$(jq  '[.[] | select(.state=="done")] | length'    "$file")
    s=$(jq  '[.[] | select(.state=="stuck")] | length'   "$file")
    local parts=()
    [ "$w"  -gt 0 ] && parts+=("${w}${ICON_WORK}")
    [ "$wa" -gt 0 ] && parts+=("${wa}${ICON_WAIT}")
    [ "$d"  -gt 0 ] && parts+=("${d}${ICON_DONE}")
    [ "$s"  -gt 0 ] && parts+=("${s}${ICON_STUCK}")
    printf 'AI: %s' "${parts[*]}"
  fi
}

{
  render
  # Kick a detect tick in the background so stuck detection + GC run on
  # every status-interval without a separate daemon. Suppressed in tests
  # via TMUX_AI_STATUS_NO_DETECT.
  if [ -z "${TMUX_AI_STATUS_NO_DETECT:-}" ]; then
    "$(dirname "$0")/tmux-ai-detect" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
} 2>>"$XDG_STATE_HOME/tmux-ai/tmux-ai.log" || true
exit 0
```

- [ ] **Step 4: Update test to suppress background detect**

In `tests/bats/test_status.bats` `setup()`, add:

```bash
  export TMUX_AI_STATUS_NO_DETECT=1
```

- [ ] **Step 5: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-status
tests/run-tests.sh tests/bats/test_status.bats
```

Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-ai-status tests/bats/test_status.bats
git commit -m "feat(bin): add tmux-ai-status renderer; kicks detect on every tick"
```

---

## Task 14: `bin/tmux-ai-dnd` — DND toggle

**Files:**
- Create: `bin/tmux-ai-dnd`
- Test: `tests/bats/test_dnd.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_dnd.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$PROJECT_ROOT/lib/common.sh"
}

@test "tmux-ai-dnd toggle creates flag when absent" {
  "$PROJECT_ROOT/bin/tmux-ai-dnd" toggle
  [ -f "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag" ]
}

@test "tmux-ai-dnd toggle removes flag when present" {
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  "$PROJECT_ROOT/bin/tmux-ai-dnd" toggle
  [ ! -f "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag" ]
}

@test "tmux-ai-dnd status reports on/off" {
  run "$PROJECT_ROOT/bin/tmux-ai-dnd" status
  assert_output "off"
  mkdir -p "$XDG_RUNTIME_DIR/tmux-ai"
  touch "$XDG_RUNTIME_DIR/tmux-ai/dnd.flag"
  run "$PROJECT_ROOT/bin/tmux-ai-dnd" status
  assert_output "on"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dnd.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai-dnd`**

```bash
#!/usr/bin/env bash
set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"

flag="$(tmux_ai_runtime_dir)/dnd.flag"
case "${1:-toggle}" in
  on)     touch "$flag" ;;
  off)    rm -f "$flag" ;;
  toggle) [ -f "$flag" ] && rm -f "$flag" || touch "$flag" ;;
  status) [ -f "$flag" ] && echo on || echo off ;;
  *) echo "usage: tmux-ai-dnd on|off|toggle|status" >&2; exit 2 ;;
esac
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-dnd
tests/run-tests.sh tests/bats/test_dnd.bats
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-dnd tests/bats/test_dnd.bats
git commit -m "feat(bin): add tmux-ai-dnd toggle"
```

---

## Task 15: `bin/tmux-ai-spawn` — launch agent in new pane

**Role:** Create a new pane in the current window (or split the current pane), register it, install the adapter hooks, then `send-keys` the agent command. Sets `pipe-pane` for log capture (feature 4 in-scope for Phase 1).

**Files:**
- Create: `bin/tmux-ai-spawn`
- Test: `tests/bats/test_spawn.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_spawn.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cp "$PROJECT_ROOT/tests/stubs/tmux" "$BATS_TEST_TMPDIR/path/tmux"
  export TMUX_STUB_CALLS="$BATS_TEST_TMPDIR/tmux_calls"
  export TMUX_STUB_RESPONSES="$BATS_TEST_TMPDIR/tmux_responses"
  # split-window returns a pane id
  cat > "$TMUX_STUB_RESPONSES" <<EOF
split-window::%42
EOF
  : > "$TMUX_STUB_CALLS"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "spawn claude creates registry entry and installs hooks" {
  cd "$BATS_TEST_TMPDIR"
  git init -q .
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run state_get "%42" agent
  assert_output "claude"
  # settings file should have been written
  [ -f "$XDG_RUNTIME_DIR/tmux-ai/claude-settings/%42.json" ]
}

@test "spawn sends keys to run the agent command" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run grep -c 'send-keys' "$TMUX_STUB_CALLS"
  # expect at least one send-keys call
  [ "$output" -ge 1 ]
}

@test "spawn sets pipe-pane for log capture" {
  cd "$BATS_TEST_TMPDIR"
  "$PROJECT_ROOT/bin/tmux-ai-spawn" claude
  run grep -c 'pipe-pane' "$TMUX_STUB_CALLS"
  [ "$output" -ge 1 ]
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_spawn.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai-spawn`**

```bash
#!/usr/bin/env bash
set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
TMUX_AI_ADAPTERS="${TMUX_AI_ADAPTERS:-$(cd "$(dirname "$0")/../adapters" && pwd)}"
TMUX_AI_NOTIFY_BIN="${TMUX_AI_NOTIFY_BIN:-$(cd "$(dirname "$0")" && pwd)/tmux-ai-notify}"
export TMUX_AI_NOTIFY_BIN
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/config.sh"

project_dir() {
  local d
  d="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  printf '%s\n' "$d"
}

log_path_for() {
  local project="$1"
  local dir
  dir="$(tmux_ai_state_dir)/logs/$project"
  mkdir -p "$dir"
  printf '%s/%s.log\n' "$dir" "$(date +%Y%m%d-%H%M%S)"
}

main() {
  local agent="${1:-claude}"
  case "$agent" in
    claude)
      # shellcheck source=/dev/null
      source "$TMUX_AI_ADAPTERS/claude.sh"
      local adapter_name="claude"
      local spawn_cmd; spawn_cmd="$(claude_spawn_cmd)"
      ;;
    *)
      echo "unknown agent: $agent" >&2
      exit 2
      ;;
  esac

  local pdir project pane settings logfile env_str
  pdir="$(project_dir)"
  project="$(basename "$pdir")"

  # Create the pane first so we know its id
  pane=$(tmux split-window -h -c "$pdir" -P -F '#{pane_id}' 2>/dev/null || echo "")
  [ -n "$pane" ] || { echo "failed to create pane" >&2; exit 1; }

  # Register in state
  state_init
  state_register "$pane" \
    agent="$agent" \
    project="$project" \
    cwd="$pdir" \
    adapter="$adapter_name" \
    state=idle \
    last_byte_count=0 \
    last_byte_ts="$(date +%s)"

  # Install hooks
  settings="$(claude_register_hooks "$pane")"
  env_str="$(claude_spawn_env "$pane")"

  # Start log capture
  logfile="$(log_path_for "$project")"
  state_set "$pane" logfile "$logfile"
  tmux pipe-pane -o -t "$pane" "cat >> '$logfile'" 2>/dev/null || true

  # Launch the agent with env set
  # Use send-keys so the env takes effect in the pane's shell
  tmux send-keys -t "$pane" "$env_str clear; $spawn_cmd" C-m 2>/dev/null || true

  tmux_ai_log "spawn: pane=$pane agent=$agent project=$project"
  echo "$pane"
}

main "$@"
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-spawn
tests/run-tests.sh tests/bats/test_spawn.bats
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-spawn tests/bats/test_spawn.bats
git commit -m "feat(bin): add tmux-ai-spawn for registered agent panes"
```

---

## Task 16: `bin/tmux-ai-dash` — read-only popup dashboard

**Scope for Phase 1:** read-only table rendered into `tmux display-popup -E`. Keybinds inside popup: `q` quit, `Enter` attach to selected agent. No bulk actions (deferred to Phase 2).

**Files:**
- Create: `bin/tmux-ai-dash`
- Test: `tests/bats/test_dash.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_dash.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
}

@test "dash render emits a header row and one line per agent" {
  state_init
  local now; now=$(date +%s)
  state_register "%1" agent=claude project=foo state=working window=main pane_index=1.0 turn_started_ts=$((now-60))
  state_register "%2" agent=claude project=bar state=done    window=main pane_index=1.1 turn_started_ts=$((now-300))
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "STATE"
  assert_output --partial "AGENT"
  assert_output --partial "PROJECT"
  assert_output --partial "foo"
  assert_output --partial "bar"
}

@test "dash render shows 'no agents' when registry empty" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "no agents"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai-dash`**

```bash
#!/usr/bin/env bash
set -u
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$(dirname "$0")/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"

fmt_elapsed() {
  local start now diff mm ss
  start="${1:-0}"
  [ "$start" -eq 0 ] && { printf '  -  '; return; }
  now=$(date +%s)
  diff=$((now - start))
  mm=$((diff / 60))
  ss=$((diff % 60))
  printf '%02d:%02d' "$mm" "$ss"
}

render() {
  state_init
  local file; file="$(_state_file)"
  local count; count=$(jq 'length' "$file" 2>/dev/null || echo 0)

  if [ "$count" -eq 0 ]; then
    echo "tmux-ai — no agents registered"
    echo
    echo "[q] quit"
    return 0
  fi

  printf '%-7s  %-8s  %-15s  %-12s  %-8s\n' "STATE" "AGENT" "PROJECT" "WIN:PANE" "ELAPSED"
  printf '%s\n' "-----------------------------------------------------------------"

  while IFS= read -r entry; do
    local state agent project win pane_idx turn
    state=$(echo   "$entry" | jq -r '.value.state // "?"')
    agent=$(echo   "$entry" | jq -r '.value.agent // "?"')
    project=$(echo "$entry" | jq -r '.value.project // "?"')
    win=$(echo     "$entry" | jq -r '.value.window // "?"')
    pane_idx=$(echo "$entry" | jq -r '.value.pane_index // "?"')
    turn=$(echo    "$entry" | jq -r '.value.turn_started_ts // 0')
    printf '%-7s  %-8s  %-15s  %-12s  %-8s\n' \
      "$state" "$agent" "$project" "$win:$pane_idx" "$(fmt_elapsed "$turn")"
  done < <(jq -c 'to_entries[]' "$file")

  echo
  echo "[Enter] attach  [q] quit   (refresh: 1s)"
}

# --render: just emit one frame and exit (used by tests)
if [ "${1:-}" = "--render" ]; then
  render
  exit 0
fi

# Interactive mode: open display-popup that runs this script on a refresh loop
# The popup script watches for a keypress and, on Enter, reads the selected
# pane id from $POPUP_SELECTION (set by a tiny fzf-style picker).
# Phase 1 keeps this minimal: just refresh-loop rendering; Enter opens an
# fzf menu to pick a pane and switch-client to it.

interactive_loop() {
  while true; do
    clear
    render
    # Read with 1s timeout; any keypress exits the loop
    if read -t 1 -n 1 -s key; then
      case "$key" in
        q|Q) exit 0 ;;
        '')  # Enter
          local pane
          pane=$(state_list | fzf --height=40% --prompt='attach> ') || exit 0
          [ -n "$pane" ] && tmux switch-client -t "$pane" 2>/dev/null
          exit 0
          ;;
      esac
    fi
  done
}

if [ -n "${TMUX:-}" ]; then
  tmux display-popup -E "$0 --loop"
elif [ "${1:-}" = "--loop" ]; then
  interactive_loop
else
  render
fi
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai-dash
tests/run-tests.sh tests/bats/test_dash.bats
```

Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai-dash tests/bats/test_dash.bats
git commit -m "feat(bin): add read-only popup dashboard (Phase 1)"
```

---

## Task 17: `bin/tmux-ai` — main dispatcher

**Role:** Friendly CLI facade. `tmux-ai spawn claude` → `tmux-ai-spawn claude`. `tmux-ai dash` → `tmux-ai-dash`. `tmux-ai dnd toggle` → `tmux-ai-dnd toggle`. Also `tmux-ai status`, `tmux-ai detect`, `tmux-ai list`, `tmux-ai help`.

**Files:**
- Create: `bin/tmux-ai`
- Test: `tests/bats/test_dispatcher.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_dispatcher.bats`:

```bash
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
}

@test "tmux-ai help lists subcommands" {
  run "$PROJECT_ROOT/bin/tmux-ai" help
  assert_output --partial "spawn"
  assert_output --partial "dash"
  assert_output --partial "dnd"
  assert_output --partial "status"
  assert_output --partial "detect"
  assert_output --partial "list"
  assert_output --partial "log"
}

@test "tmux-ai log <pane> prints the logfile path" {
  state_init
  state_register "%1" agent=claude project=foo logfile=/tmp/foo.log
  run "$PROJECT_ROOT/bin/tmux-ai" log "%1"
  assert_output --partial "/tmp/foo.log"
}

@test "tmux-ai log with unknown pane exits non-zero" {
  state_init
  run "$PROJECT_ROOT/bin/tmux-ai" log "%999"
  [ "$status" -ne 0 ]
}

@test "tmux-ai list prints registered agents" {
  state_init
  state_register "%1" agent=claude project=foo state=working
  run "$PROJECT_ROOT/bin/tmux-ai" list
  assert_output --partial "%1"
  assert_output --partial "claude"
  assert_output --partial "foo"
}

@test "unknown subcommand exits non-zero with usage" {
  run "$PROJECT_ROOT/bin/tmux-ai" bogus
  [ "$status" -ne 0 ]
  assert_output --partial "usage"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_dispatcher.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `bin/tmux-ai`**

```bash
#!/usr/bin/env bash
set -u
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
TMUX_AI_LIB="${TMUX_AI_LIB:-$(cd "$BIN_DIR/../lib" && pwd)}"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/common.sh"
# shellcheck source=/dev/null
source "$TMUX_AI_LIB/state.sh"

usage() {
  cat <<EOF
usage: tmux-ai <command> [args]

Commands:
  spawn <agent>         Launch agent in a new pane (phase 1: agent=claude)
  dash                  Open the popup dashboard
  dnd [on|off|toggle]   Do-Not-Disturb toggle
  status                Emit status-line segment (for tmux status-right)
  detect                Run a detect tick (stuck + auto-register)
  list                  Print registered agents as a table
  log <pane_id>         Open the agent log for <pane_id> in \$PAGER
  help                  Show this message
EOF
}

cmd_log() {
  local pane="${1:-}"
  [ -n "$pane" ] || { echo "usage: tmux-ai log <pane_id>" >&2; exit 2; }
  state_init
  local logfile
  logfile="$(state_get "$pane" logfile)"
  if [ -z "$logfile" ]; then
    echo "no log registered for pane $pane" >&2
    exit 1
  fi
  # Print the path first (used by tests and useful to the user), then pager.
  echo "$logfile"
  if [ -t 1 ] && [ -f "$logfile" ]; then
    "${PAGER:-less}" "$logfile"
  fi
}

cmd_list() {
  state_init
  local file; file="$(_state_file)"
  local count; count=$(jq 'length' "$file" 2>/dev/null || echo 0)
  if [ "$count" -eq 0 ]; then
    echo "(no agents registered)"
    return 0
  fi
  printf '%-8s  %-8s  %-15s  %s\n' "PANE" "AGENT" "PROJECT" "STATE"
  jq -r 'to_entries[] | [.key, .value.agent, .value.project, .value.state] | @tsv' "$file" \
    | awk -F'\t' '{printf "%-8s  %-8s  %-15s  %s\n", $1, $2, $3, $4}'
}

case "${1:-help}" in
  spawn)  shift; exec "$BIN_DIR/tmux-ai-spawn"  "$@" ;;
  dash)   shift; exec "$BIN_DIR/tmux-ai-dash"   "$@" ;;
  dnd)    shift; exec "$BIN_DIR/tmux-ai-dnd"    "$@" ;;
  status) shift; exec "$BIN_DIR/tmux-ai-status" "$@" ;;
  detect) shift; exec "$BIN_DIR/tmux-ai-detect" "$@" ;;
  list)   cmd_list ;;
  log)    shift; cmd_log "$@" ;;
  help|-h|--help) usage ;;
  *) echo "usage: tmux-ai <command>; tmux-ai help for details" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x bin/tmux-ai
tests/run-tests.sh tests/bats/test_dispatcher.bats
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-ai tests/bats/test_dispatcher.bats
git commit -m "feat(bin): add tmux-ai dispatcher with log subcommand"
```

---

## Task 18: `tmux-ai.tmux.conf` — keybindings + status-line snippet

**Files:**
- Create: `tmux-ai.tmux.conf`

- [ ] **Step 1: Write the file**

```tmux
# tmux-ai — source this file from your ~/.tmux.conf
#   source-file ~/path/to/tmux-ai/tmux-ai.tmux.conf

# --- Paths (override if installed elsewhere) -----------------------------
# TMUX_AI_BIN default resolves to ~/.local/bin (after install.sh)
# Users with a non-default install set @tmux-ai-bin below.
set -g @tmux-ai-bin '~/.local/bin'

# --- Keybindings ---------------------------------------------------------
bind A run-shell '#{@tmux-ai-bin}/tmux-ai spawn claude'
bind a run-shell '#{@tmux-ai-bin}/tmux-ai dash'
bind D run-shell '#{@tmux-ai-bin}/tmux-ai dnd toggle'
# Open the log file of the current pane in $PAGER (or less).
bind L run-shell '#{@tmux-ai-bin}/tmux-ai log #{pane_id}'

# --- Status-line segment -------------------------------------------------
# Append " #(#{@tmux-ai-bin}/tmux-ai status)" to your status-right.
# For brand-new users we set a sane default; users with their own
# status-right should merge this manually.
set -g status-interval 2
set-option -ag status-right ' #(#{@tmux-ai-bin}/tmux-ai status)'

# --- Periodic detect tick ------------------------------------------------
# status-interval triggers format rebuild; hook our detect on the
# session-window-changed AND status-refresh events (lightest available).
set-hook -g client-session-changed 'run-shell -b "#{@tmux-ai-bin}/tmux-ai detect"'
```

- [ ] **Step 2: Commit**

```bash
git add tmux-ai.tmux.conf
git commit -m "feat: add tmux.conf snippet with keybindings and status segment"
```

---

## Task 19: `config.toml.example` — documented defaults

**Files:**
- Create: `config.toml.example`

- [ ] **Step 1: Write the file**

```toml
# tmux-ai config — copy to $XDG_CONFIG_HOME/tmux-ai/config.toml to override.

[notifications]
# Desktop toast via notify-send (Linux) or osascript (macOS).
desktop = true
# In-terminal status-line + window flash.
status_line = true
# Sound cues (per-event wavs in $XDG_CONFIG_HOME/tmux-ai/sounds/<event>.wav).
sound = false
# Push to ntfy.sh / Pushover URL.
push = false
# push_target = "https://ntfy.sh/your-topic"

[detection]
# How long a pane must be quiet before we call an active turn 'done'.
idle_after_seconds = 5
# How long 'working' without output before we flag 'stuck'.
stuck_after_seconds = 180

[status]
# Status-line switches from inline icons to aggregated counters above this.
inline_threshold = 3

[agents.claude]
# Override the command used to spawn claude. Useful for custom wrappers.
spawn_command = "claude"
```

- [ ] **Step 2: Commit**

```bash
git add config.toml.example
git commit -m "docs: add documented default config.toml.example"
```

---

## Task 20: `install.sh` — symlink + tmux.conf marker

**Files:**
- Create: `install.sh`
- Test: `tests/bats/test_install.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_install.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_install.bats
```

Expected: all fail.

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
PREFIX="${TMUX_AI_PREFIX:-$HOME/.local}"
BIN_DEST="$PREFIX/bin"
TMUX_CONF="$HOME/.tmux.conf"

BIN_SCRIPTS=(
  tmux-ai
  tmux-ai-spawn
  tmux-ai-dash
  tmux-ai-status
  tmux-ai-notify
  tmux-ai-detect
  tmux-ai-dnd
)

MARKER_BEGIN='# >>> tmux-ai >>>'
MARKER_END='# <<< tmux-ai <<<'

do_install() {
  mkdir -p "$BIN_DEST" "$XDG_CONFIG_HOME/tmux-ai"

  # Symlink bins
  for s in "${BIN_SCRIPTS[@]}"; do
    ln -sf "$PROJECT_DIR/bin/$s" "$BIN_DEST/$s"
  done

  # Write config.toml if absent
  if [ ! -f "$XDG_CONFIG_HOME/tmux-ai/config.toml" ]; then
    cp "$PROJECT_DIR/config.toml.example" "$XDG_CONFIG_HOME/tmux-ai/config.toml"
  fi

  # Append sourcing block to ~/.tmux.conf (idempotent via marker)
  touch "$TMUX_CONF"
  if ! grep -qF "$MARKER_BEGIN" "$TMUX_CONF"; then
    {
      echo ""
      echo "$MARKER_BEGIN"
      echo "source-file $PROJECT_DIR/tmux-ai.tmux.conf"
      echo "$MARKER_END"
    } >> "$TMUX_CONF"
  fi

  cat <<EOF
tmux-ai installed.

To finish Claude Code integration, the spawn wrapper injects hooks via
CLAUDE_SETTINGS per-pane — nothing to add to your ~/.claude/settings.json.

Reload tmux: tmux source-file ~/.tmux.conf
EOF
}

do_uninstall() {
  for s in "${BIN_SCRIPTS[@]}"; do
    rm -f "$BIN_DEST/$s"
  done

  if [ -f "$TMUX_CONF" ] && grep -qF "$MARKER_BEGIN" "$TMUX_CONF"; then
    # Remove the block between markers (inclusive)
    local tmp; tmp="$(mktemp)"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
      $0==b {skip=1; next}
      $0==e {skip=0; next}
      !skip
    ' "$TMUX_CONF" > "$tmp"
    mv "$tmp" "$TMUX_CONF"
  fi

  echo "tmux-ai uninstalled. Your config.toml was left in place."
}

case "${1:-install}" in
  install|'') do_install ;;
  --uninstall|uninstall) do_uninstall ;;
  *) echo "usage: install.sh [install|--uninstall]" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x install.sh
tests/run-tests.sh tests/bats/test_install.bats
```

Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/bats/test_install.bats
git commit -m "feat: add install.sh with idempotent tmux.conf marker block"
```

---

## Task 21: Dependency check in install.sh

**Files:**
- Modify: `install.sh`
- Test: `tests/bats/test_install_deps.bats`

- [ ] **Step 1: Write the failing test**

`tests/bats/test_install_deps.bats`:

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.local/bin" "$HOME/.config"
  touch "$HOME/.tmux.conf"
}

@test "install --check succeeds when all deps present" {
  run "$PROJECT_ROOT/install.sh" --check
  assert_success
}

@test "install --check reports each missing dep on its own line" {
  # Hide jq by overriding PATH to a minimal shim set
  mkdir -p "$BATS_TEST_TMPDIR/emptypath"
  cp /bin/sh "$BATS_TEST_TMPDIR/emptypath/sh" 2>/dev/null || true
  cp /usr/bin/env "$BATS_TEST_TMPDIR/emptypath/env" 2>/dev/null || cp /bin/env "$BATS_TEST_TMPDIR/emptypath/env" 2>/dev/null || true
  cp /bin/bash "$BATS_TEST_TMPDIR/emptypath/bash" 2>/dev/null || true
  cp /usr/bin/grep "$BATS_TEST_TMPDIR/emptypath/grep" 2>/dev/null || cp /bin/grep "$BATS_TEST_TMPDIR/emptypath/grep" 2>/dev/null || true
  cp /usr/bin/awk "$BATS_TEST_TMPDIR/emptypath/awk" 2>/dev/null || cp /bin/awk "$BATS_TEST_TMPDIR/emptypath/awk" 2>/dev/null || true
  cp /bin/mkdir "$BATS_TEST_TMPDIR/emptypath/mkdir" 2>/dev/null || true

  run env -i HOME="$HOME" PATH="$BATS_TEST_TMPDIR/emptypath" "$PROJECT_ROOT/install.sh" --check
  # Missing deps should produce non-zero exit and stderr lines
  [ "$status" -ne 0 ]
  assert_output --partial "missing"
}
```

- [ ] **Step 2: Run to verify failure**

```bash
tests/run-tests.sh tests/bats/test_install_deps.bats
```

Expected: fails (no `--check` flag).

- [ ] **Step 3: Modify `install.sh` — add the check function**

Add near the top of `install.sh` after `BIN_SCRIPTS=(...)`:

```bash
DEPS=(bash tmux jq flock fzf)

do_check() {
  local missing=()
  for d in "${DEPS[@]}"; do
    command -v "$d" >/dev/null 2>&1 || missing+=("$d")
  done
  # notify-send OR osascript OR terminal-notifier satisfies the desktop dep
  if ! command -v notify-send >/dev/null 2>&1 \
    && ! command -v osascript >/dev/null 2>&1 \
    && ! command -v terminal-notifier >/dev/null 2>&1; then
    missing+=("notify-send|osascript|terminal-notifier")
  fi
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "all dependencies satisfied"
    return 0
  fi
  echo "missing dependencies:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  echo >&2
  echo "Install hints:" >&2
  echo "  Debian/Ubuntu: sudo apt install jq util-linux fzf libnotify-bin tmux" >&2
  echo "  Fedora:        sudo dnf install jq util-linux fzf libnotify tmux" >&2
  echo "  macOS (brew):  brew install jq fzf tmux terminal-notifier" >&2
  return 1
}
```

And extend the `case` block:

```bash
case "${1:-install}" in
  install|'') do_check || true; do_install ;;
  --check|check) do_check ;;
  --uninstall|uninstall) do_uninstall ;;
  *) echo "usage: install.sh [install|--check|--uninstall]" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run tests to verify pass**

```bash
tests/run-tests.sh tests/bats/test_install_deps.bats
```

Expected: 2 passed. (The second test is best-effort — if your bats setup can't strip PATH, it may still find `jq` and pass trivially. That's acceptable.)

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/bats/test_install_deps.bats
git commit -m "feat(install): add --check dependency scan with install hints"
```

---

## Task 22: End-to-end integration test

**Purpose:** Prove the full hook → state → notify pipeline works with the fake-claude binary driving real tmux-ai scripts on the filesystem.

**Files:**
- Create: `tests/bats/test_e2e.bats`

- [ ] **Step 1: Write the test**

```bash
#!/usr/bin/env bats

load '../bats-support/load'
load '../bats-assert/load'

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  mkdir -p "$XDG_CONFIG_HOME/tmux-ai"
  # silent notify-send
  mkdir -p "$BATS_TEST_TMPDIR/path"
  cat > "$BATS_TEST_TMPDIR/path/notify-send" <<'S'
#!/usr/bin/env bash
exit 0
S
  chmod +x "$BATS_TEST_TMPDIR/path/notify-send"
  export PATH="$BATS_TEST_TMPDIR/path:$PATH"
  source "$PROJECT_ROOT/lib/common.sh"
  source "$PROJECT_ROOT/lib/state.sh"
  export TMUX_AI_NOTIFY_BIN="$PROJECT_ROOT/bin/tmux-ai-notify"
}

@test "full lifecycle: register -> prompt_submit -> stop" {
  state_init
  state_register "%77" agent=claude project=e2e state=idle cwd="$PWD"

  TMUX_PANE="%77" \
  TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
  "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "prompt_submit"

  run state_get "%77" state
  assert_output "working"

  TMUX_PANE="%77" \
  TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
  "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "stop"

  run state_get "%77" state
  assert_output "done"
}

@test "status renders after full lifecycle" {
  state_init
  state_register "%77" agent=claude project=e2e state=idle

  TMUX_PANE="%77" TMUX_AI_NOTIFY_BIN="$TMUX_AI_NOTIFY_BIN" \
    "$PROJECT_ROOT/tests/stubs/fake-claude" <<< "prompt_submit"

  run "$PROJECT_ROOT/bin/tmux-ai-status"
  assert_output --partial "e2e"
}

@test "dash renders the live agent" {
  state_init
  state_register "%77" agent=claude project=e2e state=working turn_started_ts="$(date +%s)"
  run "$PROJECT_ROOT/bin/tmux-ai-dash" --render
  assert_output --partial "e2e"
  assert_output --partial "working"
}
```

- [ ] **Step 2: Run to verify pass (every component in place already)**

```bash
tests/run-tests.sh tests/bats/test_e2e.bats
```

Expected: 3 passed.

- [ ] **Step 3: Commit**

```bash
git add tests/bats/test_e2e.bats
git commit -m "test(e2e): add end-to-end lifecycle integration tests"
```

---

## Task 23: README with install + usage

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace README with usage doc**

```markdown
# tmux-ai

A modular tmux layer for managing AI coding agents. Phase 1 supports
Claude Code; opencode and multi-agent workflow features arrive in
Phase 2.

## What you get

- **Status-line indicators** — see every agent's state across sessions
  without leaving the current pane.
- **Popup dashboard** (`prefix + a`) — full table of every registered
  agent with state, project, window/pane, and elapsed time.
- **Desktop notifications** when an agent finishes a turn or needs
  input. `prefix + D` toggles Do-Not-Disturb.
- **Per-pane log capture** — every agent pane tees its output to
  `~/.local/state/tmux-ai/logs/<project>/<ts>.log`.
- **Stuck detection** — agents that have been "working" for more than
  `stuck_after_seconds` (default 180s) without output get flagged.

## Install

Requires: `bash`, `tmux ≥ 3.2`, `jq`, `flock`, `fzf`, and a desktop
notification binary (`notify-send` on Linux, `osascript` on macOS).

```bash
git clone https://github.com/you/tmux-config ~/src/tmux-ai
cd ~/src/tmux-ai
./install.sh --check     # dependency scan; prints install hints
./install.sh             # symlinks bin, writes config.toml, appends tmux source-file
tmux source-file ~/.tmux.conf
```

Uninstall: `./install.sh --uninstall`.

## Usage

| Keybind | Action |
|---|---|
| `prefix + A` | Spawn `claude` in a new pane, registered with hooks |
| `prefix + a` | Open popup dashboard |
| `prefix + D` | Toggle Do-Not-Disturb |

CLI (also available as symlinked binaries):

```
tmux-ai spawn claude    # also bound to prefix + A
tmux-ai dash            # also bound to prefix + a
tmux-ai list            # print the registry as a table
tmux-ai dnd toggle      # also bound to prefix + D
tmux-ai status          # what the status-line renders
tmux-ai detect          # run one detect tick (debugging)
```

## Config

`~/.config/tmux-ai/config.toml` (see `config.toml.example`). All
settings have sane defaults; the file is optional.

## Troubleshooting

- **No desktop notifications**: check `notify-send` runs from inside a
  tmux pane. On some Linux DEs tmux's server is detached from the user
  DBus. Workaround: `export DBUS_SESSION_BUS_ADDRESS` in your shell
  rc, then restart the tmux server.
- **Status-line shows nothing**: confirm `tmux-ai list` shows agents.
  If empty, the hook pipeline isn't firing — check
  `~/.local/state/tmux-ai/tmux-ai.log`.
- **Hook errors don't bubble up**: by design. Every hook failure is
  logged silently to the log file above.

## Testing

```bash
tests/run-tests.sh
```

See `TESTING.md` for the manual smoke checklist.

## License

TBD by author.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: write README with install, usage, and troubleshooting"
```

---

## Task 24: `TESTING.md` — manual smoke checklist

**Files:**
- Create: `TESTING.md`

- [ ] **Step 1: Write the file**

```markdown
# TESTING

Automated tests cover the state/hook pipeline in isolation. Before
merging anything that touches the Claude Code hook path, run the
manual smoke checklist below — that path has the highest blast radius.

## Automated

```bash
tests/run-tests.sh             # all suites
tests/run-tests.sh tests/bats/test_state.bats   # single suite
```

## Manual smoke checklist

Requires a live tmux session and an installed `claude` binary.

- [ ] `./install.sh --check` reports all deps satisfied.
- [ ] `./install.sh` completes without error.
- [ ] `tmux source-file ~/.tmux.conf` succeeds.
- [ ] Press `prefix + A` → a new pane opens in your current window
      with `claude` running.
- [ ] `tmux-ai list` shows the new pane registered as `claude` with
      state `idle`.
- [ ] Type a prompt in the claude pane → `tmux-ai list` shows
      `state=working` within 2 seconds.
- [ ] Wait for claude to finish → desktop notification fires, state
      returns to `done`.
- [ ] Press `prefix + a` → dashboard popup shows the agent.
- [ ] Press `prefix + D` → start a new turn → **no** desktop
      notification fires.
- [ ] Press `prefix + D` again → DND off; notifications resume.
- [ ] Kill the claude pane → within 2 seconds `tmux-ai list` drops it
      (pane_exited or detect garbage-collects).
- [ ] Confirm a log file appeared under
      `~/.local/state/tmux-ai/logs/<project>/`.
- [ ] Check `~/.local/state/tmux-ai/tmux-ai.log` — no unexpected
      errors.

## Uninstall check

- [ ] `./install.sh --uninstall` completes.
- [ ] Grep `~/.tmux.conf` for `tmux-ai` → no matches.
- [ ] `tmux-ai` not on PATH.
```

- [ ] **Step 2: Commit**

```bash
git add TESTING.md
git commit -m "docs: add TESTING.md with manual smoke checklist"
```

---

## Task 25: Final full test run

- [ ] **Step 1: Run the complete suite**

```bash
tests/run-tests.sh
```

Expected: all tests across all `.bats` files pass.

- [ ] **Step 2: Manual dry-run of install script in an isolated HOME**

```bash
export ISOTEST="/tmp/tmux-ai-isotest-$$"
mkdir -p "$ISOTEST/.local/bin" "$ISOTEST/.config"
touch "$ISOTEST/.tmux.conf"
HOME="$ISOTEST" ./install.sh --check
HOME="$ISOTEST" ./install.sh
ls -la "$ISOTEST/.local/bin/tmux-ai"*
grep -A2 'tmux-ai' "$ISOTEST/.tmux.conf"
HOME="$ISOTEST" ./install.sh --uninstall
rm -rf "$ISOTEST"
```

Expected: symlinks appear, tmux.conf gains a block, uninstall cleanly removes everything.

- [ ] **Step 3: Tag the phase 1 milestone**

```bash
git tag -a phase-1-mvp -m "tmux-ai Phase 1 MVP — Claude Code + core dashboard/notify"
```

- [ ] **Step 4: Ship-check — no uncommitted changes, no stray debugging**

```bash
git status
# expected: working tree clean
```

---

## What's next (Phase 2)

Written as a separate plan after Phase 1 ships:

- opencode adapter (verify hook event names against current opencode docs)
- Feature 1: project session templates (new session w/ 3-pane layout)
- Feature 2: fuzzy jump via fzf across all registered agents
- Feature 3: tmux-resurrect reconciliation on startup
- Feature 7: last-message peek column in dashboard
- Feature 12: bulk actions (kill/restart/tail) in dashboard
- macOS `osascript` notification polish and testing
- **Status-line theming**: tmux `#[fg=yellow]` / `#[fg=magenta]` / etc colors per state (spec §5.2). Phase 1 ships plain text icons; colors are a trivial follow-up once the wiring is proven in real use.
- **Per-window tab prefix** via optional `window-status-format` override (spec §5.2; documented as opt-in).
- Integration tests driving a real tmux server on a custom socket (`tmux -L tmux-ai-test`) to complement the pure-stub unit tests.
