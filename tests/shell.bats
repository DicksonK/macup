#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/shell.sh"
}

teardown() {
  mac_up_test_teardown
}

@test "run_shell skips both installs when oh-my-zsh and powerlevel10k already exist" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed"* ]]
  [[ "$output" == *"Powerlevel10k already installed"* ]]
  [ ! -f "$MAC_UP_CALL_LOG" ] || ! grep -q "git clone" "$MAC_UP_CALL_LOG"
}

@test "run_shell clones powerlevel10k when oh-my-zsh exists but the theme doesn't" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  grep -q "clone --depth=1" "$MAC_UP_CALL_LOG"
}

@test "run_shell reports what it would do in dry-run mode without installing anything" {
  export MAC_UP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would install Oh My Zsh via the official install script"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k into $HOME/.oh-my-zsh/custom/themes/powerlevel10k"* ]]
  [ ! -d "$HOME/.oh-my-zsh" ]
}

@test "run_shell reports the Powerlevel10k clone in dry-run mode when Oh My Zsh already exists" {
  mkdir -p "$HOME/.oh-my-zsh"
  export MAC_UP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed, skipping"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k"* ]]
  [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
}
