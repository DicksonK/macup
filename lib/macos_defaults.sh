#!/usr/bin/env bash

_defaults_apply() {
  local domain="$1" key="$2" type="$3" value="$4"
  local current
  current="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  if [ "$current" = "$value" ]; then
    log_info "$domain $key already set to $value, skipping"
    return 0
  fi
  defaults write "$domain" "$key" "-$type" "$value"
  log_info "Set $domain $key = $value"
}

run_macos_defaults() {
  mkdir -p "$HOME/Screenshots"

  _defaults_apply com.apple.finder AppleShowAllExtensions bool true
  _defaults_apply com.apple.finder AppleShowAllFiles bool true
  _defaults_apply com.apple.finder ShowPathbar bool true
  _defaults_apply com.apple.finder ShowStatusBar bool true

  _defaults_apply NSGlobalDomain KeyRepeat int 2
  _defaults_apply NSGlobalDomain ApplePressAndHoldEnabled bool false

  _defaults_apply com.apple.AppleMultitouchTrackpad Clicking bool true

  _defaults_apply com.apple.screencapture location string "$HOME/Screenshots"
  _defaults_apply com.apple.screencapture type string png

  _defaults_apply NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true
  _defaults_apply NSGlobalDomain PMPrintingExpandedStateForPrint bool true

  killall Finder >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true

  return 0
}
