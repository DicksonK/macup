#!/usr/bin/env bash

run_shell() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh"
    if ! CHSH=no RUNZSH=no /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
      log_error "Oh My Zsh installation failed"
      return 1
    fi
  else
    log_info "Oh My Zsh already installed, skipping"
  fi

  local p10k_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$p10k_dir" ]; then
    log_info "Cloning Powerlevel10k"
    if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"; then
      log_error "Powerlevel10k clone failed"
      return 1
    fi
  else
    log_info "Powerlevel10k already installed, skipping"
  fi

  return 0
}
