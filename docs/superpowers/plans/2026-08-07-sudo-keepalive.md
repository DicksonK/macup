# Homebrew sudo Keepalive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent `sudo` credential expiry from prompting for the same password more than once during a long `brew bundle` run, without ever forcing an upfront password prompt for Brewfiles that don't need `sudo` at all.

**Architecture:** A background subshell loop in `lib/homebrew.sh` (`_start_sudo_keepalive`/`_stop_sudo_keepalive`), started/stopped around `run_homebrew`'s real (non-dry-run) work via a function-scoped `trap ... RETURN`.

**Tech Stack:** bash, `sudo -n`, bats (existing stub-based test infra).

## Global Constraints

- Never call `sudo -v` or otherwise force a password prompt — only `sudo -n true` (non-interactive, refreshes an already-cached credential, silently no-ops if nothing is cached).
- The keepalive only runs during real (non-dry-run) execution — dry-run mode never starts it.
- Cleanup uses a function-scoped `trap ... RETURN` in `run_homebrew` so it fires on every exit path (success or either of the two early `return 1`s), not a manual kill duplicated at each return site.
- `$$` inside the `( ... ) &` subshell refers to the parent `macup` process (bash does not rebind `$$` in subshells) — this is what makes `kill -0 "$$" || exit` a correct self-termination check if the parent ever dies without calling `_stop_sudo_keepalive`.

---

### Task 1: Add sudo keepalive to `lib/homebrew.sh`

**Files:**
- Modify: `lib/homebrew.sh:4-5` (add helper functions after the existing `MACUP_BREW_PATH_*` defaults, before `_untrusted_brewfile_taps`), `lib/homebrew.sh:93` (wire into `run_homebrew`, right before the existing `_trust_brewfile_taps "$brew_bin"` line)
- Create: `tests/test_helper/stubs/sudo`
- Modify: `tests/homebrew.bats` (new tests)

**Interfaces:**
- Produces: `_start_sudo_keepalive` (no args, echoes the background process's PID to stdout), `_stop_sudo_keepalive <pid>` (no output).

- [ ] **Step 1: Write the `sudo` test stub**

Create `tests/test_helper/stubs/sudo`:

```bash
#!/usr/bin/env bash
echo "sudo $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit "${SUDO_EXIT:-0}"
```

```bash
chmod +x tests/test_helper/stubs/sudo
```

- [ ] **Step 2: Write the failing tests**

In `tests/homebrew.bats`, add these tests (after the existing tests, before the final closing of the file):

```bash
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
```

- [ ] **Step 3: Run the new tests to verify they fail**

Run: `bats tests/homebrew.bats -f "sudo_keepalive|sudo keepalive"`
Expected: FAIL — `_start_sudo_keepalive`/`_stop_sudo_keepalive` don't exist yet, so the first test errors; the second test can't yet distinguish (no keepalive exists to *not* start, so it may pass vacuously — that's fine, it becomes a real regression guard once Step 4 lands).

- [ ] **Step 4: Implement in `lib/homebrew.sh`**

After the two existing `: "${MACUP_BREW_PATH_...}"` lines (currently lines 3-4) and before `_untrusted_brewfile_taps() {` (currently line 6), add:

```bash
_start_sudo_keepalive() {
  ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  echo $!
}

_stop_sudo_keepalive() {
  local pid="$1"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}
```

Then in `run_homebrew`, immediately before the existing `_trust_brewfile_taps "$brew_bin"` line (currently line 93), add:

```bash
  local sudo_keepalive_pid=""
  if ! is_dry_run; then
    sudo_keepalive_pid="$(_start_sudo_keepalive)"
    trap '_stop_sudo_keepalive "$sudo_keepalive_pid"' RETURN
  fi

```

(blank line after, before the existing `_trust_brewfile_taps "$brew_bin"` call — no other changes to that line or anything after it).

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `bats tests/homebrew.bats -f "sudo_keepalive|sudo keepalive"`
Expected: PASS (2 tests)

- [ ] **Step 6: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (135 existing + 2 new = 137)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 7: Commit**

```bash
git add lib/homebrew.sh tests/test_helper/stubs/sudo tests/homebrew.bats
git commit -m "feat: keep sudo credentials alive during brew bundle"
```
