#!/usr/bin/env bash

ui_banner() {
  local version box_width=32 term_width left_margin=0
  version="$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "?")"
  term_width="$(tput cols 2>/dev/null || echo 80)"
  if [ "$term_width" -gt "$((box_width + 4))" ]; then
    left_margin=$(( (term_width - box_width - 4) / 2 ))
  fi
  gum style \
    --border rounded \
    --border-foreground 212 \
    --align center \
    --width "$box_width" \
    --margin "1 $left_margin" \
    --padding "1 2" \
    "macup" "Bootstrap your Mac dev setup" "v$version"
}

ui_choose_modules() {
  gum choose --no-limit \
    --header "Select modules (space to toggle, a to toggle all, enter to confirm, esc to cancel):" \
    --header.foreground 212 \
    --cursor.foreground 212 \
    --selected.foreground 212 \
    "homebrew: Install Homebrew packages from the Brewfile" \
    "shell: Install Oh My Zsh + Powerlevel10k, set terminal Nerd Font" \
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
  gum input --header "$prompt" --value "$default"
}

ui_input_secret() {
  local prompt="$1"
  gum input --header "$prompt" --password
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
