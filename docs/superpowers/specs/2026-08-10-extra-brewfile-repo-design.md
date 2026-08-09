# Extra Brewfile from a Git Repo — Design Spec

## Purpose

`DOTFILES_REPO` lets a user point `macup dotfiles` at a git repo instead
of the bundled `dotfiles/` directory, cloned into
`~/.cache/macup/dotfiles-repo` and kept up to date with `git pull`.
`EXTRA_BREWFILE` has no equivalent — it only accepts a plain local file
path. This spec adds the same git-repo lifecycle for the extra Brewfile,
so a user can keep their personal Brewfile in a repo (alongside their
dotfiles repo, or on its own) and have `macup` clone/pull it
automatically instead of maintaining a local file by hand.

## Non-Goals

- Does not change the bundled `$ROOT_DIR/Brewfile`'s behavior at all —
  it always runs first, unconditionally, exactly as today.
- Does not remove or change existing `EXTRA_BREWFILE`-as-local-path
  behavior — when `EXTRA_BREWFILE_REPO` is unset, `EXTRA_BREWFILE`
  behaves identically to how it does today. Fully backward compatible.
- Does not support multiple Brewfiles within the cloned repo in one run
  — `EXTRA_BREWFILE` (when `EXTRA_BREWFILE_REPO` is set) names exactly
  one file's relative path within that repo, defaulting to `Brewfile`
  at its root.
- Does not attempt to preview the eventual bundle contents in
  `--dry-run` when the repo hasn't been cloned yet — same accepted
  limitation `DOTFILES_REPO` already has, documented in the README.

## Design

### `lib/homebrew.sh`: `_resolve_extra_brewfile`

```bash
_resolve_extra_brewfile() {
  if [ -z "${EXTRA_BREWFILE_REPO:-}" ]; then
    printf '%s' "${EXTRA_BREWFILE:-}"
    return 0
  fi

  local cache_dir="$HOME/.cache/macup/brewfile-repo"
  if [ -d "$cache_dir/.git" ]; then
    if is_dry_run; then
      dry_run_report "update the Brewfile repo cache at $cache_dir" >&2
    else
      log_info "Updating Brewfile repo cache" >&2
      if ! git -C "$cache_dir" pull --ff-only; then
        log_warn "Failed to update Brewfile repo cache, using existing checkout"
      fi
    fi
  else
    if is_dry_run; then
      dry_run_report "clone Brewfile repo $(_redact_secrets "$EXTRA_BREWFILE_REPO") into $cache_dir" >&2
      return 0
    fi
    log_info "Cloning Brewfile repo: $(_redact_secrets "$EXTRA_BREWFILE_REPO")" >&2
    mkdir -p "$(dirname "$cache_dir")"
    if ! git clone "$EXTRA_BREWFILE_REPO" "$cache_dir"; then
      log_error "Failed to clone Brewfile repo: $(_redact_secrets "$EXTRA_BREWFILE_REPO")"
      return 1
    fi
  fi

  printf '%s/%s' "$cache_dir" "${EXTRA_BREWFILE:-Brewfile}"
}
```

**Every `log_info`/`dry_run_report` call in this function is redirected
to stderr (`>&2`) — this is required for correctness, not style.** The
function's actual return value (the resolved path) is meant to be
captured via `EXTRA_BREWFILE="$(_resolve_extra_brewfile)"` in
`run_homebrew`. Command substitution captures *all* stdout produced
during a function's execution, not just a "designated" final value —
`log_info` prints to stdout by default (unlike `log_warn`/`log_error`,
which already redirect to stderr inside their own definitions in
`lib/common.sh`). Without the `>&2` here, a log message like "Cloning
Brewfile repo: ..." would get concatenated into `$EXTRA_BREWFILE`
itself, corrupting the very path `run_homebrew` needs — the user-facing
message must stay visible on the terminal (stderr still displays
normally), it just must not be part of the captured stdout value.

- Mirrors `lib/dotfiles.sh`'s `DOTFILES_REPO` clone/pull block exactly
  (same cache-dir-exists check, same `git pull --ff-only` /
  `log_warn`-on-failure fallback, same `_redact_secrets` usage for any
  embedded credentials in the URL).
- **The dry-run-and-not-yet-cloned branch returns early with an empty
  string** (via `return 0` right after the `dry_run_report` call) —
  this is the "can't preview an unfetched repo's contents" limitation,
  matching `DOTFILES_REPO`'s existing documented gap. An empty return
  means the caller's `[ -n "${EXTRA_BREWFILE:-}" ]` check (see below)
  evaluates false for that run, so no second `dry_run_report` about
  bundling gets printed — accurate, since we don't actually know if
  the file will exist yet.
- When the cache already exists (a previous real run cloned it), even
  in dry-run mode this returns the real resolved path, since we
  genuinely do know it — consistent with how `_configure_terminal_font`
  and other idempotency checks in this codebase read real state before
  branching on dry-run.

### `lib/homebrew.sh`: wiring into `run_homebrew`

Immediately after `brew_bin` is resolved (before the sudo-keepalive
block and before `_trust_brewfile_taps`), shadow `EXTRA_BREWFILE` with
its resolved value for the rest of the function:

```bash
  local EXTRA_BREWFILE
  EXTRA_BREWFILE="$(_resolve_extra_brewfile)" || return 1
```

Bash's dynamic scoping means every function `run_homebrew` calls after
this point (`_trust_brewfile_taps` → `_untrusted_brewfile_taps`, and
the existing `if [ -n "${EXTRA_BREWFILE:-}" ]` bundle block further
down) sees this shadowed value transparently — **no changes needed to
`_untrusted_brewfile_taps`, `_trust_brewfile_taps`, or the existing
bundle-execution block**, since they already just read `$EXTRA_BREWFILE`
as an ordinary variable. This is why the resolution happens once, early,
rather than threading a new parameter through every function.

Tap-trust extraction and the extra-Brewfile `brew bundle` call
therefore both automatically operate on the *resolved* (possibly
repo-cloned) path with zero additional wiring.

### `bin/macup`: new `--brewfile-repo`/`-br` flag

Mirrors the existing `--brewfile`/`-b` and `--dotfiles-repo`/`-d`
flag-parsing cases exactly (both the space-separated `-br <url>` form
and the `--brewfile-repo=<url>` form), setting a new
`cli_brewfile_repo` local that overrides `EXTRA_BREWFILE_REPO` for that
run only — same pattern as `cli_dotfiles_repo`/`cli_brewfile` today.

### `macup.conf.example` / `README.md`

New commented-out `EXTRA_BREWFILE_REPO=` line in `macup.conf.example`,
documented the same way `DOTFILES_REPO` already is. README's `Usage`
and `Configuration` sections get the new flag/var documented alongside
the existing `--brewfile`/`EXTRA_BREWFILE` text.

## Testing

- `tests/homebrew.bats`: new tests for `_resolve_extra_brewfile` —
  plain-path passthrough when `EXTRA_BREWFILE_REPO` unset (existing
  behavior, regression guard), clone-on-first-use, pull-on-subsequent-use,
  dry-run-not-yet-cloned returns empty + reports clone intent,
  dry-run-already-cloned returns the real resolved path, default
  `Brewfile` filename when `EXTRA_BREWFILE` itself is unset but the repo
  is set, custom relative filename when both are set, credential
  redaction in the clone/pull log lines (mirroring the existing
  `tests/macup.bats` redaction test for `--dotfiles-repo`).
- `tests/homebrew.bats`: one integration-level test confirming
  `run_homebrew` end-to-end picks up taps declared in a *cloned* extra
  Brewfile (not just a local-path one) — proves the shadowing wiring
  actually connects tap-trust to the resolved path, not just the
  bundle-execution call.
- `tests/macup.bats`: new tests for `-br`/`--brewfile-repo` flag parsing
  (mirroring the existing `--dotfiles-repo`/`-d` tests), including the
  "requires a value" error case matching `-d`/`-b`'s existing pattern.

**Testing note on the stdout/stderr split above:** bats' `run` merges a
command's stdout and stderr together into `$output`, so tests that need
to verify the *actual return value* (what a real `$(_resolve_extra_brewfile)`
call would capture) cannot rely on `$output` alone — a log message would
still show up there even after being redirected to stderr in the real
function. Those tests capture the return value directly instead:
`result="$(_resolve_extra_brewfile 2>/dev/null)"`, discarding stderr
explicitly, then assert on `$result`. Tests that only need to confirm a
log message was printed still use `run` + `$output` normally.
