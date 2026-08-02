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

  local file target
  for file in "$source_dir"/*; do
    [ -e "$file" ] || continue
    target="$HOME/.$(basename "$file")"

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      ln -s "$file" "$target"
      log_info "Linked $target -> $file"
      continue
    fi

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$file" ]; then
      log_info "$target already up to date"
      continue
    fi

    if ui_confirm "$target already exists. Back it up and replace with symlink?"; then
      mv "$target" "$target.mac-up-backup"
      ln -s "$file" "$target"
      log_info "Backed up and linked $target -> $file"
    else
      log_warn "Skipped $target"
    fi
  done

  return 0
}
