# Homebrew sudo Keepalive — Design Spec

## Purpose

Some Homebrew casks/formulae need `sudo` mid-install (e.g. PKG-based
installers, casks writing into protected system directories). macOS's
`sudo` credential cache expires after a few minutes, so a long
`brew bundle` run can prompt for the same password more than once. This
spec adds a lightweight background keepalive during `run_homebrew`'s
real (non-dry-run) work so an already-cached `sudo` credential doesn't
expire mid-run — without ever forcing a password prompt for Brewfiles
that don't need `sudo` at all.

## Non-Goals

- Does not proactively prompt for a password (`sudo -v`) before running.
  Most Brewfiles never need `sudo`; forcing a prompt for all of them
  would be presumptuous. This purely *extends* a credential that some
  other step (a cask's own installer, invoked by `brew bundle`) already
  caused to be cached.
- Does not apply to any module besides `homebrew` — no other module in
  this codebase currently shells out to anything that needs `sudo`.
- Does not change `brew bundle`'s own behavior or output in any way —
  purely a background process running alongside it.

## Design

### `lib/homebrew.sh`: `_start_sudo_keepalive` / `_stop_sudo_keepalive`

```bash
_start_sudo_keepalive() {
  ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
  echo $!
}

_stop_sudo_keepalive() {
  local pid="$1"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null || true
}
```

- `sudo -n true` (non-interactive) refreshes the cached credential's
  timestamp if one exists, and silently fails (no prompt, no hang —
  confirmed directly: `sudo -n true` with nothing cached prints "a
  password is required" to stderr and exits 1 immediately) if nothing
  is cached yet. Either way, harmless to call every 60s.
- `kill -0 "$$"` — `$$` inside a `( ... ) &` subshell still refers to
  the *parent* shell's PID (bash doesn't change `$$` for subshells), so
  this is a self-terminating safety net: if the parent `macup` process
  ever dies without running `_stop_sudo_keepalive` (crash, kill -9),
  the loop notices within 60s and exits on its own rather than
  lingering forever.
- **`>/dev/null 2>&1` on the subshell is required, not cosmetic.**
  `_start_sudo_keepalive` is always called via `$(...)` (see the wiring
  below), and command substitution doesn't return until every process
  holding its stdout pipe's write end closes it. Without the redirect,
  the backgrounded infinite loop inherits and holds that pipe open
  forever, so `sudo_keepalive_pid="$(_start_sudo_keepalive)"` hangs
  indefinitely — verified directly (a minimal repro hung; `ps` showed
  the loop still running, reparented to PID 1, minutes later; redirecting
  its output fixed it immediately).
- **`wait "$pid" || true` is required, not optional cleanup.** Because
  the keepalive is started from inside a command-substitution subshell,
  the backgrounded loop is a *grandchild* of the caller, not a direct
  child — and bash's `wait` builtin can only wait on direct children.
  Waiting on a non-child returns exit status 127 every time (confirmed
  via `ps` showing the process's real parent is PID 1, not the caller).
  Under `set -e` (active in `bin/macup` and in bats test bodies), an
  unguarded `wait` here would abort immediately after a successful
  `kill -0` check. `|| true` makes it the best-effort reap it was always
  meant to be, without depending on `wait` actually succeeding.

### `lib/homebrew.sh`: wiring into `run_homebrew`

Right before the existing `_trust_brewfile_taps "$brew_bin"` call
(after Homebrew is confirmed present/installed, covering both the
tap-trust step and both `brew bundle` calls that follow):

```bash
  local sudo_keepalive_pid=""
  if ! is_dry_run; then
    sudo_keepalive_pid="$(_start_sudo_keepalive)"
    trap '_stop_sudo_keepalive "$sudo_keepalive_pid"; trap - RETURN' RETURN
  fi
```

A `trap ... RETURN` set inside a bash function fires whenever
`run_homebrew` returns — success, the early `return 1` after a failed
Homebrew install, or the early `return 1` after a failed default-Brewfile
bundle — so cleanup happens on every exit path without duplicating a
kill call at each `return`.

**`trap - RETURN` at the end of the trap body is required, not
cosmetic — this was the most serious bug found during implementation.**
A `RETURN` trap in bash is *not* automatically scoped to the function
that set it: it stays registered in the shell for the rest of the
script's life and re-fires on **every subsequent function return**,
anywhere. Once `run_homebrew` itself returns and the trap fires once
(correctly), the very next function to return anywhere later in
`bin/macup` re-triggers the *same* trap — but by then
`sudo_keepalive_pid` (a `local` belonging to the already-finished
`run_homebrew`) is out of scope, and referencing it under `bin/macup`'s
`set -u` aborts the entire script with `sudo_keepalive_pid: unbound
variable`. Verified directly: running `bin/macup homebrew` end-to-end
reproduced exactly this crash, and it caused 7 `tests/macup.bats`
failures (every test that calls a function returning after
`run_homebrew` does) until the self-clearing `trap - RETURN` was added.
No existing `trap` usage anywhere else in this codebase to conflict
with.

Dry-run mode never starts the loop — there's no real install happening
to need a cached credential for.

## Testing

- New `tests/test_helper/stubs/sudo` (matching this codebase's
  PATH-shadowing stub convention): logs invocations to
  `$MACUP_CALL_LOG`, exits 0 unless `SUDO_EXIT` is set — keeps tests
  fully isolated from the real system `sudo` binary.
- `tests/homebrew.bats`: direct unit tests for `_start_sudo_keepalive`/
  `_stop_sudo_keepalive` (start returns a PID that's actually running,
  per `kill -0`; stop makes that PID stop existing) — tested in
  isolation rather than through a full `run_homebrew` call, since
  waiting for a real 60s loop cycle inside `run_homebrew` would make
  tests slow/flaky. Plus one `run_homebrew`-level test confirming
  dry-run mode never calls the stubbed `sudo` at all.
