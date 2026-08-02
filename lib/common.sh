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
