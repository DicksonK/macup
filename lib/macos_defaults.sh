#!/usr/bin/env bash

_defaults_apply() {
  local domain="$1" key="$2" type="$3" value="$4"
  local current
  current="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  local expected="$value"
  if [ "$type" = "bool" ]; then
    case "$value" in
      true) expected=1 ;;
      false) expected=0 ;;
    esac
  fi
  if [ "$current" = "$expected" ]; then
    log_info "$domain $key already set to $value, skipping"
    return 0
  fi
  if is_dry_run; then
    dry_run_report "set $domain $key = $value"
    return 0
  fi
  if ! defaults write "$domain" "$key" "-$type" "$value"; then
    log_error "Failed to set $domain $key"
    return 1
  fi
  log_info "Set $domain $key = $value"
}

run_macos_defaults() {
  local failed=0
  if is_dry_run; then
    dry_run_report "create $HOME/Screenshots"
  else
    mkdir -p "$HOME/Screenshots"
  fi

  # Show all filename extensions in Finder
  _defaults_apply com.apple.finder AppleShowAllExtensions bool true || failed=1
  # Show hidden files in Finder
  _defaults_apply com.apple.finder AppleShowAllFiles bool true || failed=1
  # Show the full path bar at the bottom of Finder windows
  _defaults_apply com.apple.finder ShowPathbar bool true || failed=1
  # Show the status bar (item/disk space count) in Finder windows
  _defaults_apply com.apple.finder ShowStatusBar bool true || failed=1

  # Speed up key repeat rate (lower value = faster repeat)
  _defaults_apply NSGlobalDomain KeyRepeat int 2 || failed=1
  # Disable the press-and-hold accent character popup, so held keys repeat instead
  _defaults_apply NSGlobalDomain ApplePressAndHoldEnabled bool false || failed=1

  # Enable tap-to-click on the trackpad
  _defaults_apply com.apple.AppleMultitouchTrackpad Clicking bool true || failed=1

  # Save screenshots to ~/Screenshots instead of the Desktop
  _defaults_apply com.apple.screencapture location string "$HOME/Screenshots" || failed=1
  # Save screenshots as PNG
  _defaults_apply com.apple.screencapture type string png || failed=1

  # Expand the save dialog panel by default
  _defaults_apply NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true || failed=1
  # Expand the print dialog panel by default
  _defaults_apply NSGlobalDomain PMPrintingExpandedStateForPrint bool true || failed=1

  if is_dry_run; then
    dry_run_report "restart Finder and SystemUIServer"
  else
    killall Finder >/dev/null 2>&1 || true
    killall SystemUIServer >/dev/null 2>&1 || true
  fi

  return "$failed"
}
