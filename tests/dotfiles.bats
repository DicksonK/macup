#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/dotfiles.sh"
}

teardown() {
  mac_up_test_teardown
}

@test "run_dotfiles symlinks bundled dotfiles into HOME when targets don't exist" {
  run run_dotfiles

  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$ROOT_DIR/dotfiles/zshrc" ]
}

@test "run_dotfiles skips a target that is already a correct symlink" {
  ln -s "$ROOT_DIR/dotfiles/zshrc" "$HOME/.zshrc"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *".zshrc already up to date"* ]]
}

@test "run_dotfiles backs up and replaces an existing regular file when confirmed" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=0

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ -f "$HOME/.zshrc.mac-up-backup" ]
  [ "$(cat "$HOME/.zshrc.mac-up-backup")" = "my custom zshrc" ]
  [ -L "$HOME/.zshrc" ]
}

@test "run_dotfiles skips overwrite when a backup file already exists" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  echo "previous backup contents" > "$HOME/.zshrc.mac-up-backup"
  export GUM_CONFIRM_EXIT=0

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc.mac-up-backup")" = "previous backup contents" ]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  [[ "$output" == *"backup $HOME/.zshrc.mac-up-backup already exists"* ]]
}

@test "run_dotfiles logs an error and continues when the backup mv fails" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=0
  chmod 555 "$HOME"

  run run_dotfiles

  chmod 755 "$HOME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to back up $HOME/.zshrc"* ]]
}

@test "run_dotfiles logs an error and continues when a fresh symlink fails" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  chmod 555 "$HOME"

  run run_dotfiles

  chmod 755 "$HOME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to link $HOME/.zshrc"* ]]
}

@test "run_dotfiles skips an existing regular file when the user declines" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.zshrc" ]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  [[ "$output" == *"Skipped $HOME/.zshrc"* ]]
}

@test "run_dotfiles clones DOTFILES_REPO and links from the cache when set" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/mac-up/dotfiles-repo" "$MAC_UP_CALL_LOG"
}

@test "run_dotfiles warns when zero dotfiles were linked from a non-empty source_dir" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"No dotfiles found to link in"* ]]
}

@test "run_dotfiles prompts for and writes git identity when using bundled dotfiles" {
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.name)" = "Jane Doe" ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.email)" = "Jane Doe" ]
  [[ "$output" == *"Wrote git identity to $HOME/.gitconfig.local"* ]]
}

@test "run_dotfiles skips the git identity prompt when already configured" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"
  git config -f "$HOME/.gitconfig.local" user.email "existing@example.com"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Git identity already configured in $HOME/.gitconfig.local, skipping"* ]]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.name)" = "Existing Name" ]
}

@test "run_dotfiles preserves an already-set name and only prompts for the missing email" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"
  export GUM_INPUT_RESULT="new@example.com"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.name)" = "Existing Name" ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.email)" = "new@example.com" ]
}

@test "run_dotfiles re-prompts on a second run when the identity was left empty" {
  run run_dotfiles
  [ "$status" -eq 0 ]

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" != *"Git identity already configured"* ]]
}

@test "run_dotfiles logs a warning instead of false success when writing git identity fails" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  export GUM_INPUT_RESULT="Jane Doe"
  chmod 555 "$HOME"

  run run_dotfiles

  chmod 755 "$HOME"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to write git identity"* ]]
  [[ "$output" != *"Wrote git identity"* ]]
}

@test "run_dotfiles does not touch git identity when DOTFILES_REPO is set" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.gitconfig.local" ]
}
