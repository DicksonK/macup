#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  MAC_UP_BIN="$ROOT_DIR/bin/mac-up"

  MAC_UP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MAC_UP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MAC_UP_BREW_PATH_APPLE_SILICON MAC_UP_BREW_PATH_INTEL
  cat > "$MAC_UP_BREW_PATH_APPLE_SILICON" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "${MAC_UP_CALL_LOG:-/dev/null}"
exit "${BREW_EXIT:-0}"
EOF
  chmod +x "$MAC_UP_BREW_PATH_APPLE_SILICON"

  DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
  export DEFAULTS_STORE
  export GUM_CONFIRM_EXIT=1
  export GUM_INPUT_RESULT="me@example.com"
  export GH_AUTH_STATUS_EXIT=0
}

teardown() {
  mac_up_test_teardown
}

@test "mac-up --help prints usage and exits 0" {
  run "$MAC_UP_BIN" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: mac-up"* ]]
}

@test "mac-up rejects an unknown argument" {
  run "$MAC_UP_BIN" --bogus

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "mac-up runs a single named module non-interactively" {
  run "$MAC_UP_BIN" homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"succeeded: homebrew"* ]]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MAC_UP_CALL_LOG"
}

@test "mac-up --dotfiles-repo overrides DOTFILES_REPO for this run only" {
  run "$MAC_UP_BIN" --dotfiles-repo=git@github.com:example/dotfiles.git dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/mac-up/dotfiles-repo" "$MAC_UP_CALL_LOG"
}

@test "mac-up --all runs every module and reports failures without aborting" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  export BREW_EXIT=1

  run "$MAC_UP_BIN" --all

  [ "$status" -eq 1 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"Running shell"* ]]
  [[ "$output" == *"Running dotfiles"* ]]
  [[ "$output" == *"Running macos-defaults"* ]]
  [[ "$output" == *"Running github"* ]]
  [[ "$output" == *"failed: homebrew"* ]]
}

@test "mac-up --all does not prompt for config creation" {
  run "$MAC_UP_BIN" --all

  [[ "$output" != *"No config found"* ]]
  ! grep -q "gum confirm" "$MAC_UP_CALL_LOG"
}

@test "mac-up works under macOS's stock bash 3.2 (no mapfile)" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages"

  run /bin/bash "$MAC_UP_BIN"

  [ "$status" -eq 0 ]
  [[ "$output" != *"mapfile: command not found"* ]]
  [[ "$output" == *"Running homebrew"* ]]
}

@test "mac-up creates a per-run log file and reports its path in the summary" {
  run "$MAC_UP_BIN" homebrew

  [ "$status" -eq 0 ]
  log_file="$(ls "$HOME"/.cache/mac-up/logs/*.log)"
  [ -f "$log_file" ]
  grep -q "succeeded: homebrew" "$log_file"
  grep -q "mac-up run: mac-up homebrew" "$log_file"
  [[ "$output" == *"Full log: $log_file"* ]]
}

@test "mac-up --dry-run prints a startup banner and a summary note" {
  run "$MAC_UP_BIN" --dry-run homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
}

@test "mac-up --dry-run --all reports intended actions across every module without calling any mutating stub" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run "$MAC_UP_BIN" --dry-run --all

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"[dry-run] would run: brew bundle"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
  ! grep -q "^brew " "$MAC_UP_CALL_LOG"
  ! grep -q "ssh-keygen" "$MAC_UP_CALL_LOG"
  ! grep -q "defaults write" "$MAC_UP_CALL_LOG"
  ! grep -q "killall" "$MAC_UP_CALL_LOG"
}

@test "mac-up --dry-run alone does not prompt for config creation or write a config file" {
  run "$MAC_UP_BIN" --dry-run

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/mac-up/config" ]
  ! grep -q "gum confirm" "$MAC_UP_CALL_LOG"
}
