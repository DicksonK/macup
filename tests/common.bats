#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
}

teardown() {
  mac_up_test_teardown
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
  mkdir -p "$TEST_HOME/.config/mac-up"
  cat > "$TEST_HOME/.config/mac-up/config" <<'EOF'
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
  [ ! -f "$TEST_HOME/.config/mac-up/config" ]
}

@test "load_config creates the config file from the example when confirmed" {
  export GUM_CONFIRM_EXIT=0

  load_config

  [ -f "$TEST_HOME/.config/mac-up/config" ]
  diff "$TEST_HOME/.config/mac-up/config" "$ROOT_DIR/mac-up.conf.example"
}

@test "load_config skips the create-config prompt when MAC_UP_NONINTERACTIVE is set" {
  export MAC_UP_NONINTERACTIVE=1
  export GUM_CONFIRM_EXIT=1

  load_config

  [ "$DOTFILES_REPO" = "" ]
  [ "$EXTRA_BREWFILE" = "" ]
  [ ! -f "$TEST_HOME/.config/mac-up/config" ]
  ! grep -q "gum confirm" "$MAC_UP_CALL_LOG"
}

@test "init_log_file creates the logs directory and sets MAC_UP_LOG_FILE" {
  init_log_file

  [ -d "$TEST_HOME/.cache/mac-up/logs" ]
  [[ "$MAC_UP_LOG_FILE" == "$TEST_HOME/.cache/mac-up/logs/"*".log" ]]
}

@test "log_info appends a plain-text line to MAC_UP_LOG_FILE with no ANSI escape codes" {
  init_log_file

  log_info "hello there" >/dev/null

  grep -q "\[INFO\] hello there" "$MAC_UP_LOG_FILE"
  ! grep -q $'\033' "$MAC_UP_LOG_FILE"
}

@test "log_warn and log_error append to MAC_UP_LOG_FILE" {
  init_log_file

  log_warn "careful now" 2>/dev/null
  log_error "bad thing happened" 2>/dev/null

  grep -q "\[WARN\] careful now" "$MAC_UP_LOG_FILE"
  grep -q "\[ERROR\] bad thing happened" "$MAC_UP_LOG_FILE"
}

@test "log_info does not fail when MAC_UP_LOG_FILE is unset" {
  unset MAC_UP_LOG_FILE

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

  [ "$MAC_UP_LOG_FILE" = "" ]
}

@test "log_info does not abort the script when a post-init log write fails" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  init_log_file
  touch "$MAC_UP_LOG_FILE"
  chmod 444 "$MAC_UP_LOG_FILE"
  chmod 555 "$(dirname "$MAC_UP_LOG_FILE")"

  run bash -c "set -euo pipefail; source '$ROOT_DIR/lib/common.sh'; MAC_UP_LOG_FILE='$MAC_UP_LOG_FILE'; log_info 'should not abort'"

  chmod 755 "$(dirname "$MAC_UP_LOG_FILE")"
  chmod 644 "$MAC_UP_LOG_FILE"

  [ "$status" -eq 0 ]
  [[ "$output" == *"should not abort"* ]]
  [[ "$output" != *"Permission denied"* ]]
}

@test "init_log_file treats a pre-existing unwritable logs directory as a graceful-degradation case, not a crash" {
  if [ "$(id -u)" = "0" ]; then
    skip "chmod-based permission test doesn't work as root"
  fi
  mkdir -p "$TEST_HOME/.cache/mac-up/logs"
  chmod 555 "$TEST_HOME/.cache/mac-up/logs"

  init_log_file

  chmod 755 "$TEST_HOME/.cache/mac-up/logs"

  [ "$MAC_UP_LOG_FILE" = "" ]
}
