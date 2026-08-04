#!/usr/bin/env bash

run_dotfiles() {
  local source_dir

  if [ -n "${DOTFILES_REPO:-}" ]; then
    local cache_dir="$HOME/.cache/mac-up/dotfiles-repo"
    if [ -d "$cache_dir/.git" ]; then
      if is_dry_run; then
        dry_run_report "update the dotfiles repo cache at $cache_dir"
      else
        log_info "Updating dotfiles repo cache"
        if ! git -C "$cache_dir" pull --ff-only; then
          log_warn "Failed to update dotfiles repo cache, using existing checkout"
        fi
      fi
    else
      if is_dry_run; then
        dry_run_report "clone dotfiles repo $(_redact_secrets "$DOTFILES_REPO") into $cache_dir"
      else
        log_info "Cloning dotfiles repo: $(_redact_secrets "$DOTFILES_REPO")"
        mkdir -p "$(dirname "$cache_dir")"
        if ! git clone "$DOTFILES_REPO" "$cache_dir"; then
          log_error "Failed to clone dotfiles repo: $(_redact_secrets "$DOTFILES_REPO")"
          return 1
        fi
      fi
    fi
    source_dir="$cache_dir"
  else
    source_dir="$ROOT_DIR/dotfiles"
  fi

  local file target linked_count=0
  for file in "$source_dir"/*; do
    [ -e "$file" ] || continue
    target="$HOME/.$(basename "$file")"

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      if is_dry_run; then
        dry_run_report "link $target -> $file"
        linked_count=$((linked_count + 1))
        continue
      fi
      if ! ln -s "$file" "$target"; then
        log_error "Failed to link $target -> $file"
        continue
      fi
      log_info "Linked $target -> $file"
      linked_count=$((linked_count + 1))
      continue
    fi

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$file" ]; then
      log_info "$target already up to date"
      continue
    fi

    local backup_exists=false
    if [ -e "$target.mac-up-backup" ] || [ -L "$target.mac-up-backup" ]; then
      backup_exists=true
    fi

    if is_dry_run; then
      if [ "$backup_exists" = true ]; then
        log_warn "Skipped $target: backup $target.mac-up-backup already exists"
      else
        dry_run_report "prompt to back up and replace $target"
        linked_count=$((linked_count + 1))
      fi
      continue
    fi

    if ui_confirm "$target already exists. Back it up and replace with symlink?"; then
      if [ "$backup_exists" = true ]; then
        log_warn "Skipped $target: backup $target.mac-up-backup already exists"
        continue
      fi
      if ! mv "$target" "$target.mac-up-backup"; then
        log_error "Failed to back up $target, skipping"
        continue
      fi
      if ! ln -s "$file" "$target"; then
        log_error "Failed to link $target -> $file after backup"
        continue
      fi
      log_info "Backed up and linked $target -> $file"
      linked_count=$((linked_count + 1))
    else
      log_warn "Skipped $target"
    fi
  done

  if [ "$linked_count" -eq 0 ]; then
    log_warn "No dotfiles found to link in $source_dir"
  fi

  if [ -z "${DOTFILES_REPO:-}" ]; then
    local identity_file="$HOME/.gitconfig.local"
    local cur_name cur_email
    cur_name="$(git config -f "$identity_file" --get user.name 2>/dev/null || true)"
    cur_email="$(git config -f "$identity_file" --get user.email 2>/dev/null || true)"

    if [ -n "$cur_name" ] && [ -n "$cur_email" ]; then
      log_info "Git identity already configured in $identity_file, skipping"
    elif is_dry_run; then
      dry_run_report "prompt for and write git identity to $identity_file"
    else
      [ -n "$cur_name" ] || cur_name="$(ui_input "Git user.name" "")"
      [ -n "$cur_email" ] || cur_email="$(ui_input "Git user.email" "")"
      if git config -f "$identity_file" user.name "$cur_name" \
        && git config -f "$identity_file" user.email "$cur_email"; then
        log_info "Wrote git identity to $identity_file"
      else
        log_warn "Failed to write git identity to $identity_file"
      fi
    fi
  fi

  return 0
}
