#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  mac_up_test_setup
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
