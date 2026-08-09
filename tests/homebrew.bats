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

@test "_start_sudo_keepalive starts a background process that _stop_sudo_keepalive can stop" {
  pid="$(_start_sudo_keepalive)"

  kill -0 "$pid"

  _stop_sudo_keepalive "$pid"

  run kill -0 "$pid"
  [ "$status" -ne 0 ]
}

@test "run_homebrew does not start the sudo keepalive in dry-run mode" {
  install_stub_brew
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [ ! -f "$MACUP_CALL_LOG" ] || ! grep -q "^sudo " "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile passes EXTRA_BREWFILE through unchanged when no repo is set" {
  export EXTRA_BREWFILE="$TEST_HOME/my.Brewfile"

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/my.Brewfile" ]
}

@test "_resolve_extra_brewfile returns empty when neither EXTRA_BREWFILE nor EXTRA_BREWFILE_REPO is set" {
  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_resolve_extra_brewfile clones EXTRA_BREWFILE_REPO and defaults to Brewfile at its root" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"

  result="$(_resolve_extra_brewfile 2>/dev/null)"

  [ "$result" = "$HOME/.cache/macup/brewfile-repo/Brewfile" ]
  grep -q "clone git@github.com:example/my-brewfiles.git $HOME/.cache/macup/brewfile-repo" "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile uses EXTRA_BREWFILE as the in-repo relative path when both are set" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export EXTRA_BREWFILE="work/Brewfile.personal"

  result="$(_resolve_extra_brewfile 2>/dev/null)"

  [ "$result" = "$HOME/.cache/macup/brewfile-repo/work/Brewfile.personal" ]
}

@test "_resolve_extra_brewfile pulls instead of cloning when the cache already exists" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"

  _resolve_extra_brewfile >/dev/null 2>&1

  grep -q "pull --ff-only" "$MACUP_CALL_LOG"
  ! grep -q "^git clone" "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile reports the clone in dry-run mode and returns empty when not yet cloned" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export MACUP_DRY_RUN=1

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" == *"clone Brewfile repo git@github.com:example/my-brewfiles.git"* ]]
  [ ! -d "$HOME/.cache/macup/brewfile-repo" ]

  result="$(_resolve_extra_brewfile 2>/dev/null)"
  [ "$result" = "" ]
}

@test "_resolve_extra_brewfile resolves the real path in dry-run mode when already cloned" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"
  export MACUP_DRY_RUN=1

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" == *"would update the Brewfile repo cache"* ]]

  result="$(_resolve_extra_brewfile 2>/dev/null)"
  [ "$result" = "$HOME/.cache/macup/brewfile-repo/Brewfile" ]
  ! grep -q "pull" "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile redacts embedded credentials when logging a clone" {
  export EXTRA_BREWFILE_REPO="https://oauth2:ghp_secrettoken@github.com/example/my-brewfiles.git"

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" != *"ghp_secrettoken"* ]]
  # Note: intentionally not asserting on $MACUP_CALL_LOG here, unlike the
  # other tests in this file. $MACUP_CALL_LOG records the literal argv of
  # every stubbed command invocation, including `git clone`'s target URL
  # -- and `git clone` must receive the real, unredacted URL to actually
  # authenticate (mirrors lib/dotfiles.sh's DOTFILES_REPO handling and
  # tests/dotfiles.bats's analogous redaction tests, which also only
  # assert against $output, never $MACUP_CALL_LOG, for this exact
  # reason). Only $output (i.e. what log_info/dry_run_report print) and
  # the real macup log file are expected to be redacted -- see
  # tests/macup.bats's "redacts credentials ... from the run-header log
  # line" test for that coverage.
}

@test "_resolve_extra_brewfile returns a clean path with no stray output when pulling" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"

  result="$(_resolve_extra_brewfile 2>/dev/null)"

  [ "$result" = "$HOME/.cache/macup/brewfile-repo/Brewfile" ]
  [ "$(printf '%s' "$result" | wc -l)" -eq 0 ]
}

@test "run_homebrew trusts taps declared in a cloned extra Brewfile" {
  install_stub_brew
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export GUM_CONFIRM_EXIT=0
  # Pre-seed the cache dir with a .git marker so _resolve_extra_brewfile
  # takes the "already cloned" (pull) path rather than clone — this lets
  # us control the Brewfile's content directly rather than depending on
  # what the git stub's `clone` case would put there (it creates an
  # empty target/.git dir with no file content).
  mkdir -p "$HOME/.cache/macup/brewfile-repo"
  echo 'tap "example/extra"' > "$HOME/.cache/macup/brewfile-repo/Brewfile"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap example/extra" "$MACUP_CALL_LOG"
}

@test "run_homebrew skips the bundled Brewfile when MACUP_BREWFILE_ONLY is set" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  echo 'brew "jq"' > "$EXTRA_BREWFILE"
  export MACUP_BREWFILE_ONLY=1

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$EXTRA_BREWFILE" "$MACUP_CALL_LOG"
  ! grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew runs both Brewfiles when MACUP_BREWFILE_ONLY is not set" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  echo 'brew "jq"' > "$EXTRA_BREWFILE"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$EXTRA_BREWFILE" "$MACUP_CALL_LOG"
}

@test "run_homebrew warns when MACUP_BREWFILE_ONLY is set but no extra Brewfile is configured" {
  install_stub_brew
  export MACUP_BREWFILE_ONLY=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"--brewfile-only set but no extra Brewfile configured"* ]]
  ! grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew does not warn about nothing to bundle when EXTRA_BREWFILE_REPO is configured but not yet cloned in dry-run" {
  install_stub_brew
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export MACUP_DRY_RUN=1
  export MACUP_BREWFILE_ONLY=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" != *"nothing to bundle"* ]]
}
