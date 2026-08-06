#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  unset XDG_CONFIG_HOME

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL

  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
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

@test "run_homebrew trusts untrusted Brewfile taps after confirmation, before bundling" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=0

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap databricks/tap" "$MACUP_CALL_LOG"
  grep -q "trust --tap homebrew/autoupdate" "$MACUP_CALL_LOG"
  grep -q "trust --tap martido/homebrew-graph" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew skips already-trusted taps without prompting" {
  install_stub_brew
  mkdir -p "$HOME/.homebrew"
  cat > "$HOME/.homebrew/trust.json" <<'EOF'
{"trustedtaps": ["databricks/tap", "homebrew/autoupdate", "martido/homebrew-graph"]}
EOF

  run run_homebrew

  [ "$status" -eq 0 ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
}

@test "run_homebrew does not trust taps when confirmation is declined, but still bundles" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=1

  run run_homebrew

  [ "$status" -eq 0 ]
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew reports untrusted taps in dry-run mode without prompting or trusting" {
  install_stub_brew
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would trust Homebrew tap(s): databricks/tap homebrew/autoupdate martido/homebrew-graph"* ]]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
}

@test "run_homebrew also trusts taps declared in EXTRA_BREWFILE" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=0
  EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE
  cat > "$EXTRA_BREWFILE" <<'EOF'
tap "example/extra"
EOF

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap example/extra" "$MACUP_CALL_LOG"
}

@test "run_homebrew does not prompt to trust taps when MACUP_NONINTERACTIVE is set" {
  install_stub_brew
  export MACUP_NONINTERACTIVE=1
  export GUM_CONFIRM_EXIT=0

  run run_homebrew

  [ "$status" -eq 0 ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}
