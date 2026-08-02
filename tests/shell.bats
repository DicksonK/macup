#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  source "$ROOT_DIR/lib/common.sh"
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
