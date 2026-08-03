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
  export GUM_INPUT_RESULT="fake-personal-access-token"

  run run_github

  [ "$status" -eq 0 ]
  grep -q "auth login --with-token" "$MAC_UP_CALL_LOG"
  [[ "$output" == *"github.com/settings/tokens"* ]]
  [[ "$output" == *"admin:public_key"* ]]
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

@test "run_github fails with a clear error when no token is provided" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1

  run run_github

  [ "$status" -eq 1 ]
  [[ "$output" == *"No token provided"* ]]
}

@test "run_github uses the git identity email from ~/.gitconfig.local as the SSH key default" {
  git config -f "$HOME/.gitconfig.local" user.email "identity@example.com"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  grep -q "ssh-keygen.*-C identity@example.com" "$MAC_UP_CALL_LOG"
}

@test "run_github auto-uploads the SSH key when not yet registered with GitHub" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS=""

  run run_github

  [ "$status" -eq 0 ]
  grep -q "ssh-key add" "$MAC_UP_CALL_LOG"
}

@test "run_github skips upload when the SSH key is already registered with GitHub" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS="AAAAtest"

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"already registered with GitHub, skipping"* ]]
  ! grep -q "ssh-key add" "$MAC_UP_CALL_LOG"
}

@test "run_github warns but does not fail when SSH key upload fails" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS=""
  export GH_SSH_KEY_ADD_EXIT=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to auto-register SSH key"* ]]
}
