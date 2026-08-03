#!/usr/bin/env bash

run_dotfiles() {
  local source_dir

  if [ -n "${DOTFILES_REPO:-}" ]; then
    local cache_dir="$HOME/.cache/mac-up/dotfiles-repo"
    if [ -d "$cache_dir/.git" ]; then
      log_info "Updating dotfiles repo cache"
      if ! git -C "$cache_dir" pull --ff-only; then
        log_warn "Failed to update dotfiles repo cache, using existing checkout"
      fi
    else
      log_info "Cloning dotfiles repo: $DOTFILES_REPO"
      mkdir -p "$(dirname "$cache_dir")"
      if ! git clone "$DOTFILES_REPO" "$cache_dir"; then
        log_error "Failed to clone dotfiles repo: $DOTFILES_REPO"
        return 1
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

    if ui_confirm "$target already exists. Back it up and replace with symlink?"; then
      if [ -e "$target.mac-up-backup" ] || [ -L "$target.mac-up-backup" ]; then
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

  return 0
}
