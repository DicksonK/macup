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

log_info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

log_warn() {
  printf '\033[1;33m==> warning:\033[0m %s\n' "$1" >&2
}

log_error() {
  printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2
}

load_config() {
  local config_dir="$HOME/.config/mac-up"
  local config_file="$config_dir/config"
  local example_file="$ROOT_DIR/mac-up.conf.example"

  DOTFILES_REPO="${DOTFILES_REPO:-}"
  EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"

  if [ ! -f "$config_file" ]; then
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
