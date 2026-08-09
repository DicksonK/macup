#!/usr/bin/env bash

: "${MACUP_BREW_PATH_APPLE_SILICON:=/opt/homebrew/bin/brew}"
: "${MACUP_BREW_PATH_INTEL:=/usr/local/bin/brew}"

_resolve_extra_brewfile() {
  if [ -z "${EXTRA_BREWFILE_REPO:-}" ]; then
    printf '%s' "${EXTRA_BREWFILE:-}"
    return 0
  fi

  local cache_dir="$HOME/.cache/macup/brewfile-repo"
  if [ -d "$cache_dir/.git" ]; then
    if is_dry_run; then
      dry_run_report "update the Brewfile repo cache at $cache_dir" >&2
    else
      log_info "Updating Brewfile repo cache" >&2
      if ! git -C "$cache_dir" pull --ff-only >&2; then
        log_warn "Failed to update Brewfile repo cache, using existing checkout"
      fi
    fi
  else
    if is_dry_run; then
      dry_run_report "clone Brewfile repo $(_redact_secrets "$EXTRA_BREWFILE_REPO") into $cache_dir" >&2
      return 0
    fi
    log_info "Cloning Brewfile repo: $(_redact_secrets "$EXTRA_BREWFILE_REPO")" >&2
    mkdir -p "$(dirname "$cache_dir")"
    if ! git clone "$EXTRA_BREWFILE_REPO" "$cache_dir" >&2; then
      log_error "Failed to clone Brewfile repo: $(_redact_secrets "$EXTRA_BREWFILE_REPO")"
      return 1
    fi
  fi

  printf '%s/%s' "$cache_dir" "${EXTRA_BREWFILE:-Brewfile}"
}

_start_sudo_keepalive() {
  ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
  echo $!
}

_stop_sudo_keepalive() {
  local pid="$1"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
}

_untrusted_brewfile_taps() {
  local trust_file="$HOME/.homebrew/trust.json"
  [ -n "${XDG_CONFIG_HOME:-}" ] && trust_file="$XDG_CONFIG_HOME/homebrew/trust.json"

  local -a taps=()
  local tap
  while IFS= read -r tap; do
    [ -n "$tap" ] && taps+=("$tap")
  done < <(
    grep -ohE '^tap[[:space:]]+"[^"]+"' "$ROOT_DIR/Brewfile" "${EXTRA_BREWFILE:-/dev/null}" 2>/dev/null \
      | sed -E 's/^tap[[:space:]]+"([^"]+)"/\1/' \
      | sort -u
  )

  local t
  if [ "${#taps[@]}" -eq 0 ]; then
    return 0
  fi
  for t in "${taps[@]}"; do
    if [ -f "$trust_file" ] && grep -qF "\"$t\"" "$trust_file" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$t"
  done
}

_trust_brewfile_taps() {
  local brew_bin="$1"
  local -a untrusted=()
  local t
  while IFS= read -r t; do
    [ -n "$t" ] && untrusted+=("$t")
  done < <(_untrusted_brewfile_taps)

  if [ "${#untrusted[@]}" -eq 0 ]; then
    return 0
  fi

  if is_dry_run; then
    dry_run_report "trust Homebrew tap(s): ${untrusted[*]}"
    return 0
  fi

  if [ "${MACUP_NONINTERACTIVE:-0}" = "1" ]; then
    log_warn "Taps not trusted (non-interactive run); re-run macup interactively to trust: ${untrusted[*]}"
    return 0
  fi

  if ! ui_confirm "Trust ${#untrusted[@]} Homebrew tap(s) required by your Brewfile: ${untrusted[*]}?"; then
    log_warn "Taps not trusted; brew bundle may skip formulae/casks from: ${untrusted[*]}"
    return 0
  fi

  for t in "${untrusted[@]}"; do
    if "$brew_bin" tap "$t" && "$brew_bin" trust --tap "$t"; then
      log_info "Trusted tap $t"
    else
      log_warn "Failed to trust tap $t"
    fi
  done
}

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

  # Resolve into a differently-named local first, then assign into
  # EXTRA_BREWFILE: `local EXTRA_BREWFILE; EXTRA_BREWFILE="$(_resolve_extra_brewfile)"`
  # would declare-then-shadow EXTRA_BREWFILE to empty *before* the command
  # substitution subshell forks, so _resolve_extra_brewfile would never see
  # a caller-provided EXTRA_BREWFILE (e.g. from config/CLI) at all.
  local _resolved_extra_brewfile
  _resolved_extra_brewfile="$(_resolve_extra_brewfile)" || return 1
  local EXTRA_BREWFILE="$_resolved_extra_brewfile"

  local sudo_keepalive_pid=""
  if ! is_dry_run; then
    sudo_keepalive_pid="$(_start_sudo_keepalive)"
    trap '_stop_sudo_keepalive "$sudo_keepalive_pid"; trap - RETURN' RETURN
  fi

  _trust_brewfile_taps "$brew_bin"

  if [ "${MACUP_BREWFILE_ONLY:-0}" != "1" ]; then
    if is_dry_run; then
      dry_run_report "run: brew bundle --file=$ROOT_DIR/Brewfile"
    else
      log_info "Running brew bundle with default Brewfile"
      if ! "$brew_bin" bundle --file="$ROOT_DIR/Brewfile"; then
        log_error "brew bundle failed for default Brewfile"
        return 1
      fi
    fi
  fi

  if [ "${MACUP_BREWFILE_ONLY:-0}" = "1" ] && [ -z "${EXTRA_BREWFILE:-}" ] && [ -z "${EXTRA_BREWFILE_REPO:-}" ]; then
    log_warn "--brewfile-only set but no extra Brewfile configured (EXTRA_BREWFILE/EXTRA_BREWFILE_REPO); nothing to bundle"
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
