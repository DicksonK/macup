#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  MACUP_BIN="$ROOT_DIR/bin/macup"

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL
  cat > "$MACUP_BREW_PATH_APPLE_SILICON" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit "${BREW_EXIT:-0}"
EOF
  chmod +x "$MACUP_BREW_PATH_APPLE_SILICON"

  DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
  export DEFAULTS_STORE
  export GUM_CONFIRM_EXIT=1
  export GUM_INPUT_RESULT="me@example.com"
  export GH_AUTH_STATUS_EXIT=0
}

teardown() {
  macup_test_teardown
}

@test "macup --help prints usage and exits 0" {
  run "$MACUP_BIN" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: macup"* ]]
}

@test "macup --version prints the VERSION file contents and exits 0" {
  run "$MACUP_BIN" --version

  [ "$status" -eq 0 ]
  [ "$output" = "macup $(cat "$ROOT_DIR/VERSION")" ]
}

@test "macup -v is a shorthand for --version" {
  run "$MACUP_BIN" -v

  [ "$status" -eq 0 ]
  [ "$output" = "macup $(cat "$ROOT_DIR/VERSION")" ]
}

@test "macup -h prints usage and exits 0" {
  run "$MACUP_BIN" -h

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: macup"* ]]
}

@test "macup rejects an unknown argument" {
  run "$MACUP_BIN" --bogus

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "macup runs a single named module non-interactively" {
  run "$MACUP_BIN" homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"succeeded: homebrew"* ]]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "macup --dotfiles-repo overrides DOTFILES_REPO for this run only" {
  run "$MACUP_BIN" --dotfiles-repo=git@github.com:example/dotfiles.git dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/macup/dotfiles-repo" "$MACUP_CALL_LOG"
}

@test "macup -d overrides DOTFILES_REPO for this run only" {
  run "$MACUP_BIN" -d git@github.com:example/dotfiles.git dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/macup/dotfiles-repo" "$MACUP_CALL_LOG"
}

@test "macup -b overrides EXTRA_BREWFILE for this run only" {
  echo 'brew "jq"' > "$TEST_HOME/extra.Brewfile"

  run "$MACUP_BIN" -b "$TEST_HOME/extra.Brewfile" homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$TEST_HOME/extra.Brewfile" "$MACUP_CALL_LOG"
}

@test "macup -d with no value prints an error instead of exiting silently" {
  run "$MACUP_BIN" -d

  [ "$status" -eq 1 ]
  [[ "$output" == *"--dotfiles-repo requires a value"* ]]
}

@test "macup -b with no value prints an error instead of exiting silently" {
  run "$MACUP_BIN" -b

  [ "$status" -eq 1 ]
  [[ "$output" == *"--brewfile requires a value"* ]]
}

@test "macup -a runs every module, same as --all" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run "$MACUP_BIN" -a

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"Running github"* ]]
}

@test "macup --all runs every module and reports failures without aborting" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  export BREW_EXIT=1

  run "$MACUP_BIN" --all

  [ "$status" -eq 1 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"Running shell"* ]]
  [[ "$output" == *"Running dotfiles"* ]]
  [[ "$output" == *"Running macos-defaults"* ]]
  [[ "$output" == *"Running github"* ]]
  [[ "$output" == *"failed: homebrew"* ]]
}

@test "macup --all does not prompt for config creation" {
  run "$MACUP_BIN" --all

  [[ "$output" != *"No config found"* ]]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
}

@test "macup works under macOS's stock bash 3.2 (no mapfile)" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages"

  run /bin/bash "$MACUP_BIN"

  [ "$status" -eq 0 ]
  [[ "$output" != *"mapfile: command not found"* ]]
  [[ "$output" == *"Running homebrew"* ]]
}

@test "macup creates a per-run log file and reports its path in the summary" {
  run "$MACUP_BIN" homebrew

  [ "$status" -eq 0 ]
  log_file="$(ls "$HOME"/.cache/macup/logs/*.log)"
  [ -f "$log_file" ]
  grep -q "succeeded: homebrew" "$log_file"
  grep -q "macup run: macup homebrew" "$log_file"
  [[ "$output" == *"Full log: $log_file"* ]]
}

@test "macup -n is equivalent to --dry-run" {
  run "$MACUP_BIN" -n homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
}

@test "macup --dry-run prints a startup banner and a summary note" {
  run "$MACUP_BIN" --dry-run homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
}

@test "macup --dry-run --all reports intended actions across every module without calling any mutating stub" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run "$MACUP_BIN" --dry-run --all

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"[dry-run] would run: brew bundle"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
  ! grep -q "^brew " "$MACUP_CALL_LOG"
  ! grep -q "ssh-keygen" "$MACUP_CALL_LOG"
  ! grep -q "defaults write" "$MACUP_CALL_LOG"
  ! grep -q "killall" "$MACUP_CALL_LOG"
}

@test "macup --dry-run alone does not prompt for config creation or write a config file" {
  run "$MACUP_BIN" --dry-run

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/macup/config" ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
}

@test "macup redacts credentials embedded in --dotfiles-repo from the run-header log line" {
  run "$MACUP_BIN" --dotfiles-repo=https://oauth2:ghp_secrettoken@github.com/example/dotfiles.git dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"macup run: macup --dotfiles-repo=https://[redacted]@github.com/example/dotfiles.git dotfiles"* ]]
  [[ "$output" != *"ghp_secrettoken"* ]]
  log_file="$(ls "$HOME"/.cache/macup/logs/*.log)"
  ! grep -q "ghp_secrettoken" "$log_file"
}
