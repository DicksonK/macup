#!/usr/bin/env bash

ui_choose_modules() {
  gum choose --no-limit \
    "homebrew: Install Homebrew packages from the Brewfile" \
    "shell: Install Oh My Zsh + Powerlevel10k" \
    "dotfiles: Symlink dotfiles into \$HOME" \
    "macos-defaults: Apply curated macOS system defaults" \
    "github: Set up a GitHub SSH key and gh CLI auth" \
    | sed -E 's/:.*$//'
}

ui_confirm() {
  gum confirm "$1"
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"
  gum input --placeholder "$prompt" --value "$default"
}

ui_input_secret() {
  local prompt="$1"
  gum input --placeholder "$prompt" --password
}

ui_spin() {
  local title="$1"
  shift
  if [ "$1" = "--" ]; then
    shift
  fi
  gum spin --title "$title" -- "$@"
}

ui_log_step() {
  gum style --foreground 212 "==> $1"
}
