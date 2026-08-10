#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/dotfiles.sh"
}

teardown() {
  macup_test_teardown
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

@test "run_dotfiles does not warn 'No dotfiles found' when every target is already up to date" {
  for file in "$ROOT_DIR"/dotfiles/*; do
    ln -s "$file" "$HOME/.$(basename "$file")"
  done

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" != *"No dotfiles found"* ]]
}

@test "run_dotfiles backs up and replaces an existing regular file when confirmed" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=0

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ -f "$HOME/.zshrc.macup-backup" ]
  [ "$(cat "$HOME/.zshrc.macup-backup")" = "my custom zshrc" ]
  [ -L "$HOME/.zshrc" ]
}

@test "run_dotfiles skips overwrite when a backup file already exists" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  echo "previous backup contents" > "$HOME/.zshrc.macup-backup"
  export GUM_CONFIRM_EXIT=0

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.zshrc.macup-backup")" = "previous backup contents" ]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  [[ "$output" == *"backup $HOME/.zshrc.macup-backup already exists"* ]]
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
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/macup/dotfiles-repo" "$MACUP_CALL_LOG"
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

@test "run_dotfiles skips git identity setup when MACUP_SKIP_GIT_IDENTITY is set" {
  export MACUP_SKIP_GIT_IDENTITY=1
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git identity setup (--skip-git-identity)"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
  ! grep -q "gum input" "$MACUP_CALL_LOG"
}

@test "run_dotfiles warns and skips git identity setup when non-interactive without the skip flag" {
  export MACUP_NONINTERACTIVE=1
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git identity setup: no identity configured and running non-interactively"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
  ! grep -q "gum input" "$MACUP_CALL_LOG"
}

@test "run_dotfiles skips writing git identity when the prompts are left blank" {
  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped git identity setup"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}

@test "run_dotfiles skips writing git identity when only the email prompt is left blank" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped git identity setup"* ]]
  [ -z "$(git config -f "$HOME/.gitconfig.local" --get user.email 2>/dev/null || true)" ]
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

@test "run_dotfiles reports fresh links in dry-run mode without creating them" {
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would link $HOME/.zshrc -> $ROOT_DIR/dotfiles/zshrc"* ]]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -L "$HOME/.zshrc" ]
}

@test "run_dotfiles reports the confirm-and-backup prompt in dry-run mode without prompting or mutating" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would prompt to back up and replace $HOME/.zshrc"* ]]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
}

@test "run_dotfiles reports the DOTFILES_REPO clone in dry-run mode without cloning" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would clone dotfiles repo git@github.com:example/dotfiles.git"* ]]
  [ ! -d "$HOME/.cache/macup/dotfiles-repo" ]
}

@test "run_dotfiles reports the DOTFILES_REPO pull in dry-run mode without pulling" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"
  mkdir -p "$HOME/.cache/macup/dotfiles-repo/.git"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would update the dotfiles repo cache"* ]]
  ! grep -q "pull" "$MACUP_CALL_LOG"
}

@test "run_dotfiles reports the git identity prompt in dry-run mode without prompting or writing" {
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would prompt for and write git identity to $HOME/.gitconfig.local"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}

@test "run_dotfiles reports the non-interactive git identity skip in dry-run mode" {
  export MACUP_DRY_RUN=1
  export MACUP_NONINTERACTIVE=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would skip git identity setup (non-interactive, no identity configured)"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}

@test "run_dotfiles still reports already-configured git identity in dry-run mode" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"
  git config -f "$HOME/.gitconfig.local" user.email "existing@example.com"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Git identity already configured in $HOME/.gitconfig.local, skipping"* ]]
}

@test "run_dotfiles reports the existing backup in dry-run mode instead of a bogus overwrite prompt" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  echo "previous backup contents" > "$HOME/.zshrc.macup-backup"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"backup $HOME/.zshrc.macup-backup already exists"* ]]
  [[ "$output" != *"would prompt to back up and replace $HOME/.zshrc"* ]]
}

@test "run_dotfiles redacts embedded credentials from DOTFILES_REPO when logging a successful clone" {
  export DOTFILES_REPO="https://oauth2:ghp_secrettoken@github.com/example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"https://[redacted]@github.com/example/dotfiles.git"* ]]
  [[ "$output" != *"ghp_secrettoken"* ]]
}

@test "run_dotfiles redacts embedded credentials from DOTFILES_REPO when logging a failed clone" {
  export DOTFILES_REPO="https://oauth2:ghp_secrettoken@github.com/example/dotfiles.git"
  export GIT_CLONE_EXIT=1

  run run_dotfiles

  [ "$status" -eq 1 ]
  [[ "$output" == *"https://[redacted]@github.com/example/dotfiles.git"* ]]
  [[ "$output" != *"ghp_secrettoken"* ]]
}

@test "run_dotfiles redacts embedded credentials from DOTFILES_REPO when reporting a dry-run clone" {
  export DOTFILES_REPO="https://oauth2:ghp_secrettoken@github.com/example/dotfiles.git"
  export MACUP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"https://[redacted]@github.com/example/dotfiles.git"* ]]
  [[ "$output" != *"ghp_secrettoken"* ]]
}
