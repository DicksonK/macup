#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
  export DEFAULTS_STORE
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/macos_defaults.sh"
}

teardown() {
  mac_up_test_teardown
}

@test "run_macos_defaults writes a setting that isn't already applied" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  grep -q "com.apple.finder|AppleShowAllExtensions|1" "$DEFAULTS_STORE"
  grep -q "defaults write com.apple.finder AppleShowAllExtensions true" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults skips a setting that's already correctly applied" {
  echo "com.apple.finder|AppleShowAllExtensions|1" > "$DEFAULTS_STORE"

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.finder AppleShowAllExtensions already set to true, skipping"* ]]
  ! grep -q "defaults write com.apple.finder AppleShowAllExtensions" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults recognizes an already-applied boolean setting on a second run" {
  run_macos_defaults
  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.finder AppleShowAllExtensions already set to true, skipping"* ]]
}

@test "run_macos_defaults returns non-zero when a defaults write fails" {
  export DEFAULTS_WRITE_EXIT=1

  run run_macos_defaults

  [ "$status" -eq 1 ]
}

@test "run_macos_defaults creates the Screenshots directory" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  [ -d "$HOME/Screenshots" ]
}

@test "run_macos_defaults restarts Finder and SystemUIServer" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  grep -q "killall Finder" "$MAC_UP_CALL_LOG"
  grep -q "killall SystemUIServer" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults reports settings in dry-run mode without writing them" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would set com.apple.finder AppleShowAllExtensions = true"* ]]
  ! grep -q "defaults write" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults reports the Screenshots directory creation in dry-run mode without creating it" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would create $HOME/Screenshots"* ]]
  [ ! -d "$HOME/Screenshots" ]
}

@test "run_macos_defaults reports the Finder/SystemUIServer restart in dry-run mode without restarting" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would restart Finder and SystemUIServer"* ]]
  ! grep -q "killall" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults still skips an already-applied setting in dry-run mode" {
  echo "com.apple.finder|AppleShowAllExtensions|1" > "$DEFAULTS_STORE"
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.finder AppleShowAllExtensions already set to true, skipping"* ]]
}
