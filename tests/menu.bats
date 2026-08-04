#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/menu.sh"
}

teardown() {
  macup_test_teardown
}

@test "ui_choose_modules strips descriptions and returns module names" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages
dotfiles: Symlink dotfiles into \$HOME"

  run ui_choose_modules

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "homebrew" ]
  [ "${lines[1]}" = "dotfiles" ]
}

@test "ui_choose_modules shows a header explaining space/enter controls" {
  run ui_choose_modules

  [ "$status" -eq 0 ]
  grep -q -- "--header" "$MACUP_CALL_LOG"
  grep -qi "space" "$MACUP_CALL_LOG"
  grep -qi "enter" "$MACUP_CALL_LOG"
}

@test "ui_confirm returns success when gum confirm succeeds" {
  export GUM_CONFIRM_EXIT=0
  run ui_confirm "proceed?"
  [ "$status" -eq 0 ]
}

@test "ui_confirm returns failure when gum confirm fails" {
  export GUM_CONFIRM_EXIT=1
  run ui_confirm "proceed?"
  [ "$status" -eq 1 ]
}

@test "ui_input returns the provided default when no override is set" {
  run ui_input "Email" "me@example.com"
  [ "$status" -eq 0 ]
  [ "$output" = "me@example.com" ]
}

@test "ui_input returns GUM_INPUT_RESULT when set" {
  export GUM_INPUT_RESULT="typed@example.com"
  run ui_input "Email" "me@example.com"
  [ "$output" = "typed@example.com" ]
}

@test "ui_input_secret returns GUM_INPUT_RESULT when set" {
  export GUM_INPUT_RESULT="super-secret-token"
  run ui_input_secret "GitHub Personal Access Token"
  [ "$status" -eq 0 ]
  [ "$output" = "super-secret-token" ]
}

@test "ui_input_secret passes --password to gum input" {
  run ui_input_secret "GitHub Personal Access Token"
  [ "$status" -eq 0 ]
  grep -q -- "--password" "$MACUP_CALL_LOG"
}

@test "ui_spin runs the wrapped command and forwards its exit status" {
  run ui_spin "Doing thing" -- bash -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "ui_log_step prints the message" {
  run ui_log_step "Running homebrew"
  [[ "$output" == *"Running homebrew"* ]]
}
