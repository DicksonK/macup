#!/usr/bin/env bash

: "${MACUP_BREW_PATH_APPLE_SILICON:=/opt/homebrew/bin/brew}"
: "${MACUP_BREW_PATH_INTEL:=/usr/local/bin/brew}"

run_homebrew() {
  local brew_bin=""
  if [ -x "$MACUP_BREW_PATH_APPLE_SILICON" ]; then
    brew_bin="$MACUP_BREW_PATH_APPLE_SILICON"
  elif [ -x "$MACUP_BREW_PATH_INTEL" ]; then
    brew_bin="$MACUP_BREW_PATH_INTEL"
  fi

  if [ -z "$brew_bin" ]; then
    if is_dry_run; then
      dry_run_report "install Homebrew via the official install script"
    else
      log_info "Homebrew not found, installing"
      if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        log_error "Homebrew installation failed"
        return 1
      fi
      if [ -x "$MACUP_BREW_PATH_APPLE_SILICON" ]; then
        brew_bin="$MACUP_BREW_PATH_APPLE_SILICON"
      else
        brew_bin="$MACUP_BREW_PATH_INTEL"
      fi
    fi
  fi

  if is_dry_run; then
    dry_run_report "run: brew bundle --file=$ROOT_DIR/Brewfile"
  else
    log_info "Running brew bundle with default Brewfile"
    if ! "$brew_bin" bundle --file="$ROOT_DIR/Brewfile"; then
      log_error "brew bundle failed for default Brewfile"
      return 1
    fi
  fi

  if [ -n "${EXTRA_BREWFILE:-}" ]; then
    if [ -f "$EXTRA_BREWFILE" ]; then
      if is_dry_run; then
        dry_run_report "run: brew bundle --file=$EXTRA_BREWFILE"
      else
        log_info "Running brew bundle with extra Brewfile: $EXTRA_BREWFILE"
        if ! "$brew_bin" bundle --file="$EXTRA_BREWFILE"; then
          log_warn "brew bundle failed for extra Brewfile: $EXTRA_BREWFILE"
        fi
      fi
    else
      log_warn "EXTRA_BREWFILE set but not found: $EXTRA_BREWFILE"
    fi
  fi

  return 0
}
