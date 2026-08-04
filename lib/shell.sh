#!/usr/bin/env bash

_clone_if_missing() {
  local dir="$1" description="$2" repo="$3"
  if [ ! -d "$dir" ]; then
    if is_dry_run; then
      dry_run_report "clone $description into $dir"
    else
      log_info "Cloning $description"
      if ! ui_spin "Cloning $description" -- git clone --depth=1 "$repo" "$dir"; then
        log_error "$description clone failed"
        return 1
      fi
    fi
  else
    log_info "$description already installed, skipping"
  fi
  return 0
}

run_shell() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if is_dry_run; then
      dry_run_report "install Oh My Zsh via the official install script"
    else
      log_info "Installing Oh My Zsh"
      if ! ui_spin "Installing Oh My Zsh" -- env CHSH=no RUNZSH=no /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
        log_error "Oh My Zsh installation failed"
        return 1
      fi
    fi
  else
    log_info "Oh My Zsh already installed, skipping"
  fi

  _clone_if_missing \
    "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" \
    "Powerlevel10k" \
    "https://github.com/romkatv/powerlevel10k.git" || return 1

  _clone_if_missing \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git" || return 1

  _clone_if_missing \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" \
    "zsh-syntax-highlighting" \
    "https://github.com/zsh-users/zsh-syntax-highlighting.git" || return 1

  _clone_if_missing \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env" \
    "zsh-uv-env" \
    "https://github.com/matthiasha/zsh-uv-env.git" || return 1

  return 0
}
