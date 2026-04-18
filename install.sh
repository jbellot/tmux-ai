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
  install|'') do_check || true; do_install ;;
  --check|check) do_check ;;
  --uninstall|uninstall) do_uninstall ;;
  *) echo "usage: install.sh [install|--check|--uninstall]" >&2; exit 2 ;;
esac
