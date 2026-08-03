# Run Log File — Design Spec

## Purpose

`mac-up`'s `log_info`/`log_warn`/`log_error` (in `lib/common.sh`) currently
only print to the terminal — nothing about a run is persisted. This spec
adds a per-run log file so a user (or whoever's helping them debug) can
look back at what a previous `mac-up` run actually did, without having to
have scrolled back in their terminal or re-run with output redirected
manually.

## Non-Goals

- Does not capture raw output from subcommands (`brew bundle`, `git
  clone`, `ssh-keygen`, `curl|sh` installers) or gum's own interactive
  rendering — only mac-up's own `log_info`/`log_warn`/`log_error` calls.
  Gum's interactive widgets (the module checklist, confirm prompts, the
  spinner) write ANSI cursor-control and color escape codes to the
  terminal to render themselves; blindly capturing all stdout/stderr
  would fill the log file with unreadable escape-code noise. Scoping to
  mac-up's own log lines (which are always plain, single-line status
  messages) avoids that entirely.
- No log rotation, retention limit, or cleanup — each run gets its own
  small plain-text file; nothing deletes old ones. This can be revisited
  if log accumulation ever becomes a real problem in practice.
- No configurability (no flag to disable it, no configurable path) — file
  logging is always on and always goes to the same fixed location.

## Design

### Location

`~/.cache/mac-up/logs/`, matching the project's existing cache-namespace
convention (`~/.cache/mac-up/dotfiles-repo` is already used for cached
external dotfiles repos) rather than introducing a new top-level location
like `~/Library/Logs/`.

### Per-run file naming

One file per run, named by start time: `~/.cache/mac-up/logs/<YYYY-MM-DDTHHMMSS>.log`
(e.g. `~/.cache/mac-up/logs/2026-08-04T091530.log`).

### `lib/common.sh` additions

```bash
init_log_file() {
  local log_dir="$HOME/.cache/mac-up/logs"
  if mkdir -p "$log_dir" 2>/dev/null; then
    MAC_UP_LOG_FILE="$log_dir/$(date +%Y-%m-%dT%H%M%S).log"
  else
    MAC_UP_LOG_FILE=""
  fi
}

_log_write() {
  local level="$1" msg="$2"
  if [ -n "${MAC_UP_LOG_FILE:-}" ]; then
    printf '[%s] [%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$level" "$msg" >> "$MAC_UP_LOG_FILE" 2>/dev/null
  fi
}
```

`log_info`/`log_warn`/`log_error` each gain one call to `_log_write` in
addition to their existing `printf` to stdout/stderr:

```bash
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

### Wiring in `bin/mac-up`

`main()` calls `init_log_file` immediately after its CLI flag-parsing
`while` loop finishes — i.e. after `--help`/unknown-argument handling
(both of which `exit` from inside that loop and never reach this point)
but before `load_config`. This means `--help` never creates a log file at
all, while every real run (interactive, `--all`, or named modules) has
one from before the first module-relevant log line is emitted. At the end
of `run_selected_modules`'s summary output, one more line is added:

```bash
log_info "Full log: $MAC_UP_LOG_FILE"
```

guarded so it's skipped if `MAC_UP_LOG_FILE` is empty (directory creation
failed).

### Error handling

If `mkdir -p "$log_dir"` fails (permissions, read-only filesystem,
whatever), `init_log_file` sets `MAC_UP_LOG_FILE=""` and every subsequent
`_log_write` call becomes a silent no-op (guarded by `[ -n
"${MAC_UP_LOG_FILE:-}" ]`). File logging failing never fails a module or
aborts the run — it's purely additive, best-effort persistence on top of
the terminal output that already works today.

## Testing

`tests/common.bats` gets new cases for:

- `init_log_file` creates `~/.cache/mac-up/logs/` and sets
  `MAC_UP_LOG_FILE` to a path matching the `<YYYY-MM-DDTHHMMSS>.log`
  pattern under it.
- After `init_log_file`, calling `log_info`/`log_warn`/`log_error`
  appends a line to `$MAC_UP_LOG_FILE` containing the level and message,
  with no ANSI escape sequences in it (the file content, not the
  terminal output captured by `run`, is asserted).
- Graceful degradation: if `init_log_file` is called with `$HOME` pointed
  at an unwritable location (same `chmod 555` pattern already used
  elsewhere in this test suite), `MAC_UP_LOG_FILE` ends up empty and a
  subsequent `log_info` call doesn't error out (still prints to stdout
  normally, just skips the file write).

`tests/mac_up.bats` gets one addition confirming a real `mac-up` run (via
the stub harness) creates a log file under `$HOME/.cache/mac-up/logs/`
and that the file contains the run's status lines.

## Interfaces Summary (for a future implementation plan)

- Produces: `init_log_file()` and `_log_write(level, msg)` in
  `lib/common.sh`; sets the `MAC_UP_LOG_FILE` variable consumed by all
  three existing `log_*` functions and by `bin/mac-up`'s final summary
  line.
- Modifies: `log_info`, `log_warn`, `log_error` (add the `_log_write`
  call — existing terminal-output behavior and existing call signatures
  are unchanged, so no caller anywhere in the codebase needs to change).
- Modifies: `bin/mac-up`'s `main()` (add the `init_log_file` call and the
  final "Full log: ..." summary line).
