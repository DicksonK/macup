#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
}

teardown() {
  macup_test_teardown
}

@test "resolve_script_dir follows a chain of symlinks to the real directory" {
  source "$ROOT_DIR/lib/common.sh"

  local real_dir="$TEST_HOME/real"
  mkdir -p "$real_dir"
  touch "$real_dir/script.sh"
  ln -s "$real_dir/script.sh" "$TEST_HOME/link1.sh"
  ln -s "$TEST_HOME/link1.sh" "$TEST_HOME/link2.sh"

  run resolve_script_dir "$TEST_HOME/link2.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "$real_dir" ]
}

@test "resolve_script_dir on a plain (non-symlink) path returns its directory" {
  source "$ROOT_DIR/lib/common.sh"

  mkdir -p "$TEST_HOME/plain"
  touch "$TEST_HOME/plain/script.sh"

  run resolve_script_dir "$TEST_HOME/plain/script.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/plain" ]
}

@test "log_info prints the message to stdout" {
  source "$ROOT_DIR/lib/common.sh"

  run log_info "hello there"

  [ "$status" -eq 0 ]
  [[ "$output" == *"hello there"* ]]
}

@test "log_error prints the message to stderr" {
  source "$ROOT_DIR/lib/common.sh"

  log_error "bad thing happened" 2>"$TEST_HOME/stderr.log"

  grep -q "bad thing happened" "$TEST_HOME/stderr.log"
}

@test "log_warn prints the message to stderr" {
  source "$ROOT_DIR/lib/common.sh"

  log_warn "careful now" 2>"$TEST_HOME/stderr.log"

  grep -q "careful now" "$TEST_HOME/stderr.log"
}

@test "load_config sources an existing config file" {
  mkdir -p "$TEST_HOME/.config/macup"
  cat > "$TEST_HOME/.config/macup/config" <<'EOF'
DOTFILES_REPO=git@github.com:example/dotfiles.git
EXTRA_BREWFILE=/tmp/extra.Brewfile
EOF

  load_config

  [ "$DOTFILES_REPO" = "git@github.com:example/dotfiles.git" ]
  [ "$EXTRA_BREWFILE" = "/tmp/extra.Brewfile" ]
}

@test "load_config defaults to empty values when declined and no file exists" {
  export GUM_CONFIRM_EXIT=1

  load_config

  [ "$DOTFILES_REPO" = "" ]
  [ "$EXTRA_BREWFILE" = "" ]
  [ ! -f "$TEST_HOME/.config/macup/config" ]
}

@test "load_config creates the config file from the example when confirmed" {
  export GUM_CONFIRM_EXIT=0

  load_config

  [ -f "$TEST_HOME/.config/macup/config" ]
  diff "$TEST_HOME/.config/macup/config" "$ROOT_DIR/macup.conf.example"
}

@test "load_config skips the create-config prompt when MACUP_NONINTERACTIVE is set" {
  export MACUP_NONINTERACTIVE=1
  export GUM_CONFIRM_EXIT=1

  load_config

  [ "$DOTFILES_REPO" = "" ]
  [ "$EXTRA_BREWFILE" = "" ]
  [ ! -f "$TEST_HOME/.config/macup/config" ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
}

@test "init_log_file creates the logs directory and sets MACUP_LOG_FILE" {
  init_log_file

  [ -d "$TEST_HOME/.cache/macup/logs" ]
  [[ "$MACUP_LOG_FILE" == "$TEST_HOME/.cache/macup/logs/"*".log" ]]
}

@test "log_info appends a plain-text line to MACUP_LOG_FILE with no ANSI escape codes" {
  init_log_file

  log_info "hello there" >/dev/null

  grep -q "\[INFO\] hello there" "$MACUP_LOG_FILE"
  ! grep -q $'\033' "$MACUP_LOG_FILE"
}

@test "log_warn and log_error append to MACUP_LOG_FILE" {
  init_log_file

  log_warn "careful now" 2>/dev/null
  log_error "bad thing happened" 2>/dev/null

  grep -q "\[WARN\] careful now" "$MACUP_LOG_FILE"
  grep -q "\[ERROR\] bad thing happened" "$MACUP_LOG_FILE"
}

@test "log_info does not fail when MACUP_LOG_FILE is unset" {
  unset MACUP_LOG_FILE

  run log_info "no file yet"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no file yet"* ]]
}

@test "init_log_file degrades gracefully when the log directory can't be created" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  mkdir -p "$TEST_HOME/.cache"
  chmod 555 "$TEST_HOME/.cache"

  init_log_file

  chmod 755 "$TEST_HOME/.cache"

  [ "$MACUP_LOG_FILE" = "" ]
}

@test "log_info does not abort the script when a post-init log write fails" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  init_log_file
  touch "$MACUP_LOG_FILE"
  chmod 444 "$MACUP_LOG_FILE"
  chmod 555 "$(dirname "$MACUP_LOG_FILE")"

  run bash -c "set -euo pipefail; source '$ROOT_DIR/lib/common.sh'; MACUP_LOG_FILE='$MACUP_LOG_FILE'; log_info 'should not abort'"

  chmod 755 "$(dirname "$MACUP_LOG_FILE")"
  chmod 644 "$MACUP_LOG_FILE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"should not abort"* ]]
  [[ "$output" != *"Permission denied"* ]]
}

@test "init_log_file treats a pre-existing unwritable logs directory as a graceful-degradation case, not a crash" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  mkdir -p "$TEST_HOME/.cache/macup/logs"
  chmod 555 "$TEST_HOME/.cache/macup/logs"

  init_log_file

  chmod 755 "$TEST_HOME/.cache/macup/logs"

  [ "$MACUP_LOG_FILE" = "" ]
}

@test "is_dry_run returns false when MACUP_DRY_RUN is unset" {
  unset MACUP_DRY_RUN

  run is_dry_run

  [ "$status" -eq 1 ]
}

@test "is_dry_run returns true when MACUP_DRY_RUN=1" {
  export MACUP_DRY_RUN=1

  run is_dry_run

  [ "$status" -eq 0 ]
}

@test "dry_run_report logs a [dry-run]-prefixed message via log_info" {
  run dry_run_report "do the thing"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would do the thing"* ]]
}

@test "load_config skips the create-config prompt in dry-run mode without prompting or writing" {
  export MACUP_DRY_RUN=1
  export GUM_CONFIRM_EXIT=0

  load_config

  [ ! -f "$TEST_HOME/.config/macup/config" ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
}

@test "_redact_secrets masks user:pass@ credentials in an https URL" {
  run _redact_secrets "https://oauth2:ghp_secrettoken@github.com/user/dotfiles.git"

  [ "$status" -eq 0 ]
  [ "$output" = "https://[redacted]@github.com/user/dotfiles.git" ]
}

@test "_redact_secrets masks a bare token@ credential in an https URL" {
  run _redact_secrets "https://ghp_secrettoken@github.com/user/dotfiles.git"

  [ "$status" -eq 0 ]
  [ "$output" = "https://[redacted]@github.com/user/dotfiles.git" ]
}

@test "_redact_secrets leaves a credential-free URL unchanged" {
  run _redact_secrets "https://github.com/user/dotfiles.git"

  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/user/dotfiles.git" ]
}

@test "_redact_secrets leaves an SSH-style git@host URL unchanged" {
  run _redact_secrets "git@github.com:user/dotfiles.git"

  [ "$status" -eq 0 ]
  [ "$output" = "git@github.com:user/dotfiles.git" ]
}

@test "_redact_secrets masks a credentialed URL embedded in a larger string" {
  run _redact_secrets "--dotfiles-repo=https://oauth2:ghp_secrettoken@github.com/user/dotfiles.git dotfiles"

  [ "$status" -eq 0 ]
  [ "$output" = "--dotfiles-repo=https://[redacted]@github.com/user/dotfiles.git dotfiles" ]
}
