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
