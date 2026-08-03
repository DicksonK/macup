#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    local email default_email=""
    if git config -f "$HOME/.gitconfig.local" --get user.email >/dev/null 2>&1; then
      default_email="$(git config -f "$HOME/.gitconfig.local" --get user.email)"
    fi
    if [ -n "$default_email" ]; then
      email="$default_email"
    else
      email="$(ui_input "Email for SSH key" "")"
    fi
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
    log_info "No token found — create one at https://github.com/settings/tokens with the \"admin:public_key\" scope"
    local token
    token="$(ui_input_secret "GitHub Personal Access Token")"
    if [ -z "$token" ]; then
      log_error "No token provided"
      return 1
    fi
    if ! printf '%s' "$token" | gh auth login --with-token; then
      log_error "gh auth login failed"
      return 1
    fi
  else
    log_info "gh already authenticated, skipping"
  fi

  if [ -f "$key_path.pub" ]; then
    local key_blob
    key_blob="$(awk '{print $2}' "$key_path.pub")"
    if gh api user/keys --jq '.[].key' 2>/dev/null | grep -qF "$key_blob"; then
      log_info "SSH key already registered with GitHub, skipping"
    else
      if ! gh ssh-key add "$key_path.pub" --title "mac-up ($(scutil --get ComputerName 2>/dev/null || hostname))"; then
        log_warn "Failed to auto-register SSH key with GitHub — add it manually at https://github.com/settings/keys using the public key printed above"
      fi
    fi
  fi

  return 0
}
