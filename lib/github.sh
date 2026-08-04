#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    if is_dry_run; then
      dry_run_report "generate an SSH key at $key_path, then check/register it with GitHub"
    else
      local email default_email
      default_email="$(git config -f "$HOME/.gitconfig.local" --get user.email 2>/dev/null || true)"
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
    fi
  else
    log_info "SSH key already exists at $key_path, skipping generation"
  fi

  if [ -f "$key_path.pub" ]; then
    log_info "Public key:"
    cat "$key_path.pub"
    if is_dry_run; then
      dry_run_report "copy the public key to the clipboard"
    else
      pbcopy < "$key_path.pub" 2>/dev/null || true
      log_info "Public key copied to clipboard (if pbcopy is available)"
    fi
  fi

  if ! gh auth status >/dev/null 2>&1; then
    if is_dry_run; then
      dry_run_report "authenticate via a GitHub PAT, then check/register the SSH key with GitHub"
      return 0
    fi
    log_info "No token found — create a classic token at https://github.com/settings/tokens with the \"repo\", \"read:org\", \"gist\", and \"admin:public_key\" scopes"
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
    local key_blob registered_keys
    key_blob="$(awk '{print $2}' "$key_path.pub")"
    registered_keys="$(gh api user/keys --jq '.[].key' 2>/dev/null || true)"
    if [ -n "$key_blob" ] && printf '%s' "$registered_keys" | grep -qF "$key_blob"; then
      log_info "SSH key already registered with GitHub, skipping"
    elif is_dry_run; then
      dry_run_report "upload the SSH key to GitHub via gh ssh-key add"
    else
      if ! gh ssh-key add "$key_path.pub" --title "macup ($(scutil --get ComputerName 2>/dev/null || hostname))"; then
        log_warn "Failed to auto-register SSH key with GitHub — add it manually at https://github.com/settings/keys using the public key printed above"
      fi
    fi
  fi

  return 0
}
