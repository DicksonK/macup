#!/usr/bin/env bash

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

macup_test_setup() {
  ROOT_DIR="$(repo_root)"
  export ROOT_DIR
  TEST_HOME="$(mktemp -d)"
  # Resolve to canonical path to match cd -P behavior in resolve_script_dir
  TEST_HOME="$(cd -P "$TEST_HOME" && pwd)"
  export HOME="$TEST_HOME"
  export PATH="$ROOT_DIR/tests/test_helper/stubs:$PATH"
  MACUP_CALL_LOG="$(mktemp)"
  export MACUP_CALL_LOG
}

macup_test_teardown() {
  rm -rf "$TEST_HOME"
  rm -f "$MACUP_CALL_LOG"
}
