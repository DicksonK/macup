#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/github.sh"
}

teardown() {
  mac_up_test_teardown
}

@test "run_github generates an SSH key when none exists" {
  export GUM_INPUT_RESULT="me@example.com"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519" ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  grep -q "ssh-keygen" "$MAC_UP_CALL_LOG"
}

@test "run_github skips key generation when a key already exists" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"SSH key already exists"* ]]
  ! grep -q "ssh-keygen" "$MAC_UP_CALL_LOG"
}

@test "run_github logs in with gh when not already authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1
  export GH_AUTH_LOGIN_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  grep -q "auth login" "$MAC_UP_CALL_LOG"
}

@test "run_github skips gh login when already authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"gh already authenticated, skipping"* ]]
  ! grep -q "auth login" "$MAC_UP_CALL_LOG"
}
