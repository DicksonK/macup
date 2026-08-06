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
  ( while true; do sudo -n true 2>/dev/null; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
  echo $!
}

_stop_sudo_keepalive() {
  local pid="$1"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
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
- `_stop_sudo_keepalive` both kills and `wait`s the PID, so the shell
  doesn't print a stray "Terminated" job-control message after the
  script's own output.

### `lib/homebrew.sh`: wiring into `run_homebrew`

Right before the existing `_trust_brewfile_taps "$brew_bin"` call
(after Homebrew is confirmed present/installed, covering both the
tap-trust step and both `brew bundle` calls that follow):

```bash
  local sudo_keepalive_pid=""
  if ! is_dry_run; then
    sudo_keepalive_pid="$(_start_sudo_keepalive)"
    trap '_stop_sudo_keepalive "$sudo_keepalive_pid"' RETURN
  fi
```

A function-scoped `trap ... RETURN` fires whenever `run_homebrew`
returns — success, the early `return 1` after a failed Homebrew
install, or the early `return 1` after a failed default-Brewfile
bundle — so cleanup happens on every exit path without duplicating a
kill call at each `return`. No existing `trap` usage anywhere else in
this codebase to conflict with.

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
