#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL

  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/homebrew.sh"
}

teardown() {
  macup_test_teardown
}

install_stub_brew() {
  cat > "$MACUP_BREW_PATH_APPLE_SILICON" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit "${BREW_EXIT:-0}"
EOF
  chmod +x "$MACUP_BREW_PATH_APPLE_SILICON"
}

@test "run_homebrew runs brew bundle with the default Brewfile when brew is already installed" {
  install_stub_brew

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew fails when brew bundle fails on the default Brewfile" {
  install_stub_brew
  export BREW_EXIT=1

  run run_homebrew

  [ "$status" -eq 1 ]
}

@test "run_homebrew also runs the extra Brewfile when EXTRA_BREWFILE is set and exists" {
  install_stub_brew
  echo "brew \"jq\"" > "$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$TEST_HOME/extra.Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew warns and continues when EXTRA_BREWFILE is set but missing" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/does-not-exist.Brewfile"

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA_BREWFILE set but not found"* ]]
}

@test "run_homebrew reports it would install Homebrew in dry-run mode when brew is missing" {
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would install Homebrew via the official install script"* ]]
}

@test "run_homebrew reports the default bundle in dry-run mode without calling brew" {
  install_stub_brew
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would run: brew bundle --file=$ROOT_DIR/Brewfile"* ]]
  [ ! -s "$MACUP_CALL_LOG" ] || ! grep -q "brew" "$MACUP_CALL_LOG"
}

@test "run_homebrew reports the extra Brewfile bundle in dry-run mode without running it" {
  install_stub_brew
  echo "brew \"jq\"" > "$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would run: brew bundle --file=$TEST_HOME/extra.Brewfile"* ]]
}
