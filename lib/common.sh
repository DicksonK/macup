#!/usr/bin/env bash

resolve_script_dir() {
  local source="$1"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

init_log_file() {
  local log_dir="$HOME/.cache/macup/logs" candidate
  if mkdir -p "$log_dir" 2>/dev/null; then
    candidate="$log_dir/$(date +%Y-%m-%dT%H%M%S).log"
    if : 2>/dev/null >> "$candidate"; then
      MACUP_LOG_FILE="$candidate"
      return 0
    fi
  fi
  MACUP_LOG_FILE=""
}

_log_write() {
  local level="$1" msg="$2"
  if [ -n "${MACUP_LOG_FILE:-}" ]; then
    printf '[%s] [%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$level" "$msg" 2>/dev/null >> "$MACUP_LOG_FILE" || true
  fi
}

log_info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
  _log_write INFO "$1"
}

log_warn() {
  printf '\033[1;33m==> warning:\033[0m %s\n' "$1" >&2
  _log_write WARN "$1"
}

log_error() {
  printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2
  _log_write ERROR "$1"
}

is_dry_run() {
  [ "${MACUP_DRY_RUN:-0}" = "1" ]
}

_redact_secrets() {
  printf '%s' "$1" | sed -E 's#(https?://)[^@[:space:]/]+@#\1[redacted]@#g'
}

dry_run_report() {
  log_info "[dry-run] would $1"
}

load_config() {
  local config_dir="$HOME/.config/macup"
  local config_file="$config_dir/config"
  local example_file="$ROOT_DIR/macup.conf.example"

  DOTFILES_REPO="${DOTFILES_REPO:-}"
  EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"

  if [ ! -f "$config_file" ]; then
    if [ "${MACUP_NONINTERACTIVE:-0}" = "1" ]; then
      return 0
    fi
    if is_dry_run; then
      dry_run_report "prompt to create a default config at $config_file"
      return 0
    fi
    if ui_confirm "No config found. Create default config at $config_file?"; then
      mkdir -p "$config_dir"
      cp "$example_file" "$config_file"
    else
      return 0
    fi
  fi

  # shellcheck disable=SC1090
  source "$config_file"
}
