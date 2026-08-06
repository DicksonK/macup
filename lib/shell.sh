#!/usr/bin/env bash

: "${MACUP_ITERM_APP_PATH:=/Applications/iTerm.app}"

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

  _configure_terminal_font

  return 0
}

_configure_terminal_font() {
  local font_family="MesloLGS Nerd Font Mono"
  local font_ps_name="MesloLGSNFM-Regular"
  local iterm_guid="B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10"
  local font_file="MesloLGSNerdFontMono-Regular.ttf"

  if [ ! -f "$HOME/Library/Fonts/$font_file" ] && [ ! -f "/Library/Fonts/$font_file" ]; then
    log_warn "$font_family not installed; run the homebrew module first, then re-run shell"
    return 0
  fi

  local current_font
  current_font="$(osascript -e 'tell application "Terminal" to get font name of default settings' 2>/dev/null || true)"
  if [ "$current_font" = "$font_ps_name" ]; then
    log_info "Terminal.app font already set to $font_family, skipping"
  elif is_dry_run; then
    dry_run_report "set Terminal.app's default font to $font_family"
  else
    if osascript -e "tell application \"Terminal\" to set font name of default settings to \"$font_family\"" >/dev/null 2>&1; then
      log_info "Set Terminal.app font to $font_family"
    else
      log_warn "Failed to set Terminal.app font (may need Automation permission in System Settings > Privacy & Security)"
    fi
  fi

  if [ -d "$MACUP_ITERM_APP_PATH" ]; then
    local current_guid
    current_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
    if [ "$current_guid" = "$iterm_guid" ]; then
      log_info "iTerm2 default profile already set to the macup Nerd Font profile, skipping"
    elif is_dry_run; then
      dry_run_report "create iTerm2 dynamic profile 'macup' with $font_family and set it as default"
    else
      local profile_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
      mkdir -p "$profile_dir"
      cat > "$profile_dir/macup.json" <<EOF
{
  "Profiles": [
    {
      "Name": "macup",
      "Guid": "$iterm_guid",
      "Normal Font": "$font_ps_name 13"
    }
  ]
}
EOF
      if defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$iterm_guid"; then
        log_info "Created iTerm2 dynamic profile with $font_family and set as default"
      else
        log_warn "Failed to set iTerm2 default profile"
      fi
    fi
  fi
}
