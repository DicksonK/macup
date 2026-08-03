#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    local email
    email="$(ui_input "Email for SSH key" "")"
    log_info "Generating SSH key"
    mkdir -p "$HOME/.ssh"
    if ! ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""; then
      log_error "SSH key generation failed"
      return 1
    fi
    ssh-add --apple-use-keychain "$key_path" 2>/dev/null || ssh-add "$key_path"
  else
    log_info "SSH key already exists at $key_path, skipping generation"
  fi

  if [ -f "$key_path.pub" ]; then
    log_info "Public key:"
    cat "$key_path.pub"
    pbcopy < "$key_path.pub" 2>/dev/null || true
    log_info "Public key copied to clipboard (if pbcopy is available)"
  fi

  if ! gh auth status >/dev/null 2>&1; then
    log_info "Authenticating gh CLI"
    if ! gh auth login --git-protocol ssh; then
      log_error "gh auth login failed"
      return 1
    fi
  else
    log_info "gh already authenticated, skipping"
  fi

  return 0
}
