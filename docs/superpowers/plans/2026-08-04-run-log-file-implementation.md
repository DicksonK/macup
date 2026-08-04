# Run Log File Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every `macup` run's `log_info`/`log_warn`/`log_error`
output to a per-run plain-text log file under `~/.cache/macup/logs/`, so
a user can review what happened after the fact.

**Architecture:** `lib/common.sh` gains `init_log_file()` (sets up the
logs directory and a per-run `MACUP_LOG_FILE` path) and an internal
`_log_write()` helper that the three existing `log_*` functions each call
in addition to their current terminal output. `bin/macup` calls
`init_log_file` once, right after CLI flag parsing, and prints the log
path in its end-of-run summary.

**Tech Stack:** bash (unchanged from the base project).

## Global Constraints

- Only `log_info`/`log_warn`/`log_error` calls are captured — never raw
  subcommand output (`brew`, `git`, `ssh-keygen`, etc.) and never gum's
  own interactive rendering (`ui_choose_modules`, `ui_confirm`,
  `ui_input`, `ui_spin`, `ui_log_step` are all out of scope; they never
  call the log functions and must not be changed).
- No log rotation, retention limit, or cleanup — one file per run,
  nothing deletes old ones.
- No configurability — file logging is always on, always at
  `~/.cache/macup/logs/<YYYY-MM-DDTHHMMSS>.log`.
- File logging is best-effort and must never fail a module or the run:
  if the logs directory can't be created, `MACUP_LOG_FILE` is left
  empty and every subsequent log call silently skips the file write.
- `--help` and unknown-argument runs (both `exit` from inside
  `main()`'s CLI flag-parsing loop) never create a log file.
- Existing `log_*` call signatures (`log_info(msg)` etc.) are unchanged —
  no caller anywhere in the codebase needs to change.

---

## File Structure

```
macup/
├── bin/macup          # + init_log_file call, + "Full log:" summary line
├── lib/common.sh        # + init_log_file(), + _log_write(), log_* call it
└── tests/
    ├── common.bats       # + 5 tests
    └── macup.bats        # + 1 test
```

---

### Task 1: Per-run log file

**Files:**
- Modify: `lib/common.sh`
- Modify: `bin/macup`
- Test: `tests/common.bats`
- Test: `tests/macup.bats`

**Interfaces:**
- Consumes: nothing new — `HOME` (already used throughout the codebase).
- Produces: `init_log_file()` → sets (module-global) `MACUP_LOG_FILE` to
  a path under `~/.cache/macup/logs/`, or to `""` if the directory
  couldn't be created. `_log_write(level, msg)` → internal helper, not
  called directly by anything outside `lib/common.sh`. No other task or
  module needs to call either function directly — `log_info`/`log_warn`/
  `log_error` already do, transparently.

- [ ] **Step 1: Write the failing tests for `init_log_file` and `_log_write`**

Append to `tests/common.bats` (after the last existing test,
`load_config skips the create-config prompt when MACUP_NONINTERACTIVE is
set`):

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/common.bats`
Expected: FAIL — `init_log_file: command not found`.

- [ ] **Step 3: Implement `init_log_file`, `_log_write`, and update `log_*` in `lib/common.sh`**

Insert `init_log_file` and `_log_write` after `resolve_script_dir` and
before the existing `log_info` function, then modify the three `log_*`
functions to call `_log_write`:

```bash
init_log_file() {
  local log_dir="$HOME/.cache/macup/logs"
  if mkdir -p "$log_dir" 2>/dev/null; then
    MACUP_LOG_FILE="$log_dir/$(date +%Y-%m-%dT%H%M%S).log"
  else
    MACUP_LOG_FILE=""
  fi
}

_log_write() {
  local level="$1" msg="$2"
  if [ -n "${MACUP_LOG_FILE:-}" ]; then
    printf '[%s] [%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$level" "$msg" >> "$MACUP_LOG_FILE" 2>/dev/null
  fi
}

log_info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
  _log_write INFO "$1"
}

log_warn() {
  printf '\033[1;33m==> warning:\033[0m %s\n' "$1" >&2
  _log_write WARN "$1"
}

log_error() {
  printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2
  _log_write ERROR "$1"
}
```

(`load_config`, later in the file, is unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/common.bats`
Expected: PASS (14 tests: 9 existing + 5 new).

- [ ] **Step 5: Write the failing end-to-end test**

Append to `tests/macup.bats` (after the last existing test, `macup
works under macOS's stock bash 3.2 (no mapfile)`):

```bash
@test "macup creates a per-run log file and reports its path in the summary" {
  run "$MACUP_BIN" homebrew

  [ "$status" -eq 0 ]
  log_file="$(ls "$HOME"/.cache/macup/logs/*.log)"
  [ -f "$log_file" ]
  grep -q "succeeded: homebrew" "$log_file"
  [[ "$output" == *"Full log: $log_file"* ]]
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `bats tests/macup.bats`
Expected: FAIL — no log file is created yet, and the summary never prints
a "Full log:" line.

- [ ] **Step 7: Wire `init_log_file` and the summary line into `bin/macup`**

In `main()`, insert `init_log_file` as the first statement immediately
after the CLI flag-parsing `while` loop's closing `done`, before the
`if [ "$run_all" = true ] || [ "${#modules[@]}" -gt 0 ]; then` block:

```bash
  init_log_file

  if [ "$run_all" = true ] || [ "${#modules[@]}" -gt 0 ]; then
```

In `run_selected_modules`, replace the summary's tail —

```bash
  if [ "${#failed[@]}" -gt 0 ]; then
    log_warn "  failed: ${failed[*]}"
    return 1
  fi
  return 0
```

— with:

```bash
  if [ "${#failed[@]}" -gt 0 ]; then
    log_warn "  failed: ${failed[*]}"
  fi
  if [ -n "${MACUP_LOG_FILE:-}" ]; then
    log_info "Full log: $MACUP_LOG_FILE"
  fi

  if [ "${#failed[@]}" -gt 0 ]; then
    return 1
  fi
  return 0
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bats tests/macup.bats`
Expected: PASS (8 tests: 7 existing + 1 new).

- [ ] **Step 9: Run the full test suite**

Run: `bats tests/`
Expected: PASS (all files, all tests — 67 tests total: 61 from the base
project + 5 (Task 1, common.bats) + 1 (Task 1, macup.bats)).

- [ ] **Step 10: Commit**

```bash
git add lib/common.sh bin/macup tests/common.bats tests/macup.bats
git commit -m "feat: add per-run log file"
```

---

## Self-Review Notes

- **Spec coverage:** Location, per-run naming, `lib/common.sh` additions,
  `bin/macup` wiring (including the exact `--help`-never-logs placement
  decision), error handling, and testing are all covered by this single
  task — the spec's scope is small enough that splitting it further would
  fragment one cohesive, independently-testable change.
- **Placeholder scan:** no TODOs; every step has complete, runnable code
  and an expected result.
- **Type/name consistency:** `MACUP_LOG_FILE`, `init_log_file`, and
  `_log_write` are used identically in `lib/common.sh`, `bin/macup`, and
  both test files.
