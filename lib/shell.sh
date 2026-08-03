#!/usr/bin/env bash

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

  local p10k_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$p10k_dir" ]; then
    if is_dry_run; then
      dry_run_report "clone Powerlevel10k into $p10k_dir"
    else
      log_info "Cloning Powerlevel10k"
      if ! ui_spin "Cloning Powerlevel10k" -- git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"; then
        log_error "Powerlevel10k clone failed"
        return 1
      fi
    fi
  else
    log_info "Powerlevel10k already installed, skipping"
  fi

  return 0
}
