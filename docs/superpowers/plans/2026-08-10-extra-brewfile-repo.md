# Extra Brewfile from a Git Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user point their extra Brewfile at a git repo (cloned/pulled automatically, same lifecycle as `DOTFILES_REPO`) instead of only a plain local file path, and let them opt into running *only* the extra Brewfile for a given invocation instead of always stacking it on top of the bundled one.

**Architecture:** A new `_resolve_extra_brewfile` helper in `lib/homebrew.sh` handles the clone/pull and returns the effective file path; `run_homebrew` shadows its `EXTRA_BREWFILE` local with that resolved value once, early, so every existing consumer of `$EXTRA_BREWFILE` (tap-trust extraction, the bundle-execution block) picks it up with zero other changes (Task 1). A new `--brewfile-only`/`-bo` session flag, exported as `MACUP_BREWFILE_ONLY` (mirroring `--dry-run`/`MACUP_DRY_RUN`'s existing pattern), skips the bundled-Brewfile bundle call when set (Task 2). `bin/macup` gets two new flags: `-br|--brewfile-repo=<url>` (mirroring `-d|--dotfiles-repo`) and `-bo|--brewfile-only` (mirroring `-n|--dry-run`).

**Tech Stack:** bash, `git`, bats (existing stub-based test infra — the existing `tests/test_helper/stubs/git` stub already handles `clone`/generic subcommands correctly, no stub changes needed).

## Global Constraints

- Fully backward compatible: when `EXTRA_BREWFILE_REPO` is unset, `EXTRA_BREWFILE` behaves exactly as it does today (a plain local path) — `_resolve_extra_brewfile` must pass it through unchanged in that case. Likewise, when `--brewfile-only` is not passed, both bundle calls run exactly as today.
- When `EXTRA_BREWFILE_REPO` is set, `EXTRA_BREWFILE` is reinterpreted as the relative path within the cloned repo to the Brewfile, defaulting to `Brewfile` (repo root) if `EXTRA_BREWFILE` itself is unset.
- Clone/pull lifecycle mirrors `lib/dotfiles.sh`'s `DOTFILES_REPO` handling exactly: cache dir `~/.cache/macup/brewfile-repo`, `git -C "$cache_dir" pull --ff-only` if `.git` already exists there (falling back to `log_warn` + using the existing checkout on failure, not aborting), `git clone` otherwise. Credentials embedded in the URL are redacted via the existing `_redact_secrets` helper before any log line.
- In `--dry-run` mode, if the repo hasn't been cloned yet, `_resolve_extra_brewfile` reports the clone intent and returns an empty string (can't preview an unfetched repo's contents — same accepted limitation `DOTFILES_REPO` already has). If the repo is already cached from a prior real run, dry-run resolves and previews the real path normally.
- `_resolve_extra_brewfile`'s shadowing inside `run_homebrew` must happen before `_trust_brewfile_taps` is called and before the existing extra-Brewfile bundle block — both already read `$EXTRA_BREWFILE` as an ordinary variable and need no other changes. **Must use the two-step form** — `local _resolved_extra_brewfile; _resolved_extra_brewfile="$(_resolve_extra_brewfile)" || return 1; local EXTRA_BREWFILE="$_resolved_extra_brewfile"` — not a bare `local EXTRA_BREWFILE` followed by `EXTRA_BREWFILE="$(...)"` on the next line: that shadows `EXTRA_BREWFILE` to empty *before* the command substitution runs, so `_resolve_extra_brewfile` would always see an empty value regardless of what the caller set, silently breaking local-path mode. Verified directly (see Step 4).
- `--brewfile-only` is a session-only flag (like `--all`/`--dry-run`), not a persisted `macup.conf.example` config var — "skip the bundled Brewfile just this once" is a per-invocation choice, not something that should silently stick across future runs via a saved config file.
- `--brewfile-only` does NOT change tap-trust scanning — `_untrusted_brewfile_taps` keeps scanning both the bundled and extra Brewfiles regardless, since trusting an unused tap is harmless and scoping it would add complexity for no correctness benefit. Do not touch `_untrusted_brewfile_taps`/`_trust_brewfile_taps` in Task 2.

---

### Task 1: Git-repo-backed `EXTRA_BREWFILE_REPO`

**Files:**
- Modify: `lib/homebrew.sh:4-5` (add `_resolve_extra_brewfile` after the existing `MACUP_BREW_PATH_*` defaults, before `_start_sudo_keepalive`), `lib/homebrew.sh:79-103` (wire into `run_homebrew`, right after `brew_bin` is resolved)
- Modify: `lib/common.sh:65-66` (`load_config`, add `EXTRA_BREWFILE_REPO="${EXTRA_BREWFILE_REPO:-}"` alongside the existing `DOTFILES_REPO`/`EXTRA_BREWFILE` initialization)
- Modify: `bin/macup:37-49` (`usage()`), `bin/macup:94-181` (`main()` — new flag-parsing cases and `cli_brewfile_repo` local, override wiring)
- Modify: `macup.conf.example` (new `EXTRA_BREWFILE_REPO=` commented line)
- Modify: `README.md` (document the new flag/var alongside existing `--brewfile`/`EXTRA_BREWFILE` text)
- Test: `tests/homebrew.bats`, `tests/macup.bats`

**Interfaces:**
- Produces: `_resolve_extra_brewfile` (no args, reads `$EXTRA_BREWFILE`/`$EXTRA_BREWFILE_REPO`, echoes the resolved path or empty string to stdout, non-fatal `return 1` only on clone failure).

- [ ] **Step 1: Write the failing tests**

In `tests/homebrew.bats`, add these tests (after the existing tests, before the final closing of the file):

```bash
@test "_resolve_extra_brewfile passes EXTRA_BREWFILE through unchanged when no repo is set" {
  export EXTRA_BREWFILE="$TEST_HOME/my.Brewfile"

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/my.Brewfile" ]
}

@test "_resolve_extra_brewfile returns empty when neither EXTRA_BREWFILE nor EXTRA_BREWFILE_REPO is set" {
  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "_resolve_extra_brewfile clones EXTRA_BREWFILE_REPO and defaults to Brewfile at its root" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"

  result="$(_resolve_extra_brewfile 2>/dev/null)"

  [ "$result" = "$HOME/.cache/macup/brewfile-repo/Brewfile" ]
  grep -q "clone git@github.com:example/my-brewfiles.git $HOME/.cache/macup/brewfile-repo" "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile uses EXTRA_BREWFILE as the in-repo relative path when both are set" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export EXTRA_BREWFILE="work/Brewfile.personal"

  result="$(_resolve_extra_brewfile 2>/dev/null)"

  [ "$result" = "$HOME/.cache/macup/brewfile-repo/work/Brewfile.personal" ]
}

@test "_resolve_extra_brewfile pulls instead of cloning when the cache already exists" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"

  _resolve_extra_brewfile >/dev/null 2>&1

  grep -q "pull --ff-only" "$MACUP_CALL_LOG"
  ! grep -q "^git clone" "$MACUP_CALL_LOG"
}

@test "_resolve_extra_brewfile reports the clone in dry-run mode and returns empty when not yet cloned" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export MACUP_DRY_RUN=1

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" == *"clone Brewfile repo git@github.com:example/my-brewfiles.git"* ]]
  [ ! -d "$HOME/.cache/macup/brewfile-repo" ]

  result="$(_resolve_extra_brewfile 2>/dev/null)"
  [ "$result" = "" ]
}

@test "_resolve_extra_brewfile resolves the real path in dry-run mode when already cloned" {
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"
  export MACUP_DRY_RUN=1

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" == *"would update the Brewfile repo cache"* ]]
  ! grep -q "pull" "$MACUP_CALL_LOG"

  result="$(_resolve_extra_brewfile 2>/dev/null)"
  [ "$result" = "$HOME/.cache/macup/brewfile-repo/Brewfile" ]
}

@test "_resolve_extra_brewfile redacts embedded credentials when logging a clone" {
  export EXTRA_BREWFILE_REPO="https://oauth2:ghp_secrettoken@github.com/example/my-brewfiles.git"

  run _resolve_extra_brewfile

  [ "$status" -eq 0 ]
  [[ "$output" != *"ghp_secrettoken"* ]]
  # Deliberately NOT asserting $MACUP_CALL_LOG is secret-free here: git
  # clone must receive the real, unredacted URL to authenticate (exactly
  # like the existing DOTFILES_REPO handling in lib/dotfiles.sh), and
  # $MACUP_CALL_LOG records the literal argv passed to the stubbed git —
  # it correctly contains the secret. Redaction applies only to the
  # user-facing log message ($output above), matching the established
  # pattern in tests/dotfiles.bats's analogous DOTFILES_REPO redaction
  # tests, which likewise only assert against $output.
}

@test "run_homebrew trusts taps declared in a cloned extra Brewfile" {
  install_stub_brew
  export EXTRA_BREWFILE_REPO="git@github.com:example/my-brewfiles.git"
  export GUM_CONFIRM_EXIT=0
  # Pre-seed the cache dir with a .git marker so _resolve_extra_brewfile
  # takes the "already cloned" (pull) path rather than clone — this lets
  # us control the Brewfile's content directly rather than depending on
  # what the git stub's `clone` case would put there (it creates an
  # empty target/.git dir with no file content).
  mkdir -p "$HOME/.cache/macup/brewfile-repo"
  echo 'tap "example/extra"' > "$HOME/.cache/macup/brewfile-repo/Brewfile"
  mkdir -p "$HOME/.cache/macup/brewfile-repo/.git"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap example/extra" "$MACUP_CALL_LOG"
}
```

Note on the `_resolve_extra_brewfile` tests above: bats' `run` merges a
command's stdout and stderr together into `$output`, so a log message
(now redirected to stderr per Step 3's `>&2` requirement) still shows up
in `$output` — tests that only need to confirm a log message was printed
use `run` + `$output` normally. But tests that need to verify the
*actual return value* (what a real `$(_resolve_extra_brewfile)` call in
`run_homebrew` would capture) can't rely on `$output` for that, since it
would include the log text too — those instead capture directly with
stderr discarded: `result="$(_resolve_extra_brewfile 2>/dev/null)"`,
then assert on `$result`. Follow this pattern exactly as shown in each
test above — don't collapse them to a single `run` call.

In `tests/macup.bats`, add these tests (near the existing `-d|--dotfiles-repo` tests):

```bash
@test "macup -br overrides EXTRA_BREWFILE_REPO for this run only" {
  run "$MACUP_BIN" -br git@github.com:example/my-brewfiles.git --dry-run homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"clone Brewfile repo git@github.com:example/my-brewfiles.git"* ]]
}

@test "macup -br with no value prints an error instead of exiting silently" {
  run "$MACUP_BIN" -br

  [ "$status" -eq 1 ]
  [[ "$output" == *"--brewfile-repo requires a value"* ]]
}

@test "macup redacts credentials embedded in --brewfile-repo from the run-header log line" {
  run "$MACUP_BIN" --brewfile-repo=https://oauth2:ghp_secrettoken@github.com/example/my-brewfiles.git dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"macup run: macup --brewfile-repo=https://[redacted]@github.com/example/my-brewfiles.git dotfiles"* ]]
  [[ "$output" != *"ghp_secrettoken"* ]]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/homebrew.bats -f "_resolve_extra_brewfile|cloned extra Brewfile"`
Run: `bats tests/macup.bats -f "brewfile-repo|-br"`
Expected: FAIL — `_resolve_extra_brewfile` doesn't exist yet, `-br`/`--brewfile-repo` aren't recognized flags yet (fall through to "Unknown argument").

- [ ] **Step 3: Implement `_resolve_extra_brewfile` in `lib/homebrew.sh`**

After the two existing `: "${MACUP_BREW_PATH_...}"` lines (currently lines 3-4) and before `_start_sudo_keepalive() {` (currently line 6), add:

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

**Every `log_info`/`dry_run_report` call above is redirected to stderr
(`>&2`) — this is required for correctness, not style.** `run_homebrew`
captures this function's return value via
`EXTRA_BREWFILE="$(_resolve_extra_brewfile)"` — command substitution
captures *all* stdout produced during execution, not just a "designated"
final value. `log_info` prints to stdout by default (unlike `log_warn`/
`log_error`, which already redirect to stderr inside their own
definitions). Without `>&2` here, a message like "Cloning Brewfile
repo: ..." would get concatenated into `$EXTRA_BREWFILE` itself,
corrupting the path — the message must stay visible to the user (stderr
still prints normally), it just can't be part of the captured stdout
value. Do not drop these redirects when implementing.

(blank line after, before `_start_sudo_keepalive`.)

- [ ] **Step 4: Wire it into `run_homebrew`**

In `lib/homebrew.sh`, in `run_homebrew`, immediately after the `if [ -z "$brew_bin" ]; then ... fi` block that resolves/installs Homebrew (currently ending at line 102) and before the `local sudo_keepalive_pid=""` line (currently line 104), add:

```bash

  local _resolved_extra_brewfile
  _resolved_extra_brewfile="$(_resolve_extra_brewfile)" || return 1
  local EXTRA_BREWFILE="$_resolved_extra_brewfile"
```

**This exact two-step form is required — do not write it as a bare
`local EXTRA_BREWFILE` followed by `EXTRA_BREWFILE="$(_resolve_extra_brewfile)"`
on the next line.** That ordering shadows `EXTRA_BREWFILE` to empty
*immediately* on the `local` line, before the command substitution on
the following line even runs — so `_resolve_extra_brewfile` would
always see an empty `EXTRA_BREWFILE`, silently breaking local-path mode
for anyone not also using `EXTRA_BREWFILE_REPO`. Verify this yourself
before moving on if you're unsure:

```bash
bash -c '
inner() { echo "sees EXTRA_BREWFILE=[${EXTRA_BREWFILE:-}]"; }
outer() { local EXTRA_BREWFILE; EXTRA_BREWFILE="$(inner)"; echo "result=[$EXTRA_BREWFILE]"; }
export EXTRA_BREWFILE="/path/to/my.Brewfile"
outer
'
```
This prints `result=[sees EXTRA_BREWFILE=[]]` — the value is lost. The
two-step form above (resolving into a differently-named local first)
avoids this. It also isn't simply
`local EXTRA_BREWFILE="$(_resolve_extra_brewfile)"` collapsed onto one
line — combining declare+assign masks the command substitution's exit
status (shellcheck SC2155), silently breaking the required
`|| return 1` clone-failure propagation.

- [ ] **Step 5: Add `EXTRA_BREWFILE_REPO` to `load_config` in `lib/common.sh`**

Change (currently lines 65-66):

```bash
  DOTFILES_REPO="${DOTFILES_REPO:-}"
  EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"
```

to:

```bash
  DOTFILES_REPO="${DOTFILES_REPO:-}"
  EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"
  EXTRA_BREWFILE_REPO="${EXTRA_BREWFILE_REPO:-}"
```

- [ ] **Step 6: Add the `-br|--brewfile-repo` flag to `bin/macup`**

In `usage()`, add a line after the existing `-b, --brewfile=<path>` line (currently line 41):

```
  -b, --brewfile=<path>         Override EXTRA_BREWFILE for this run
  -br, --brewfile-repo=<url>    Override EXTRA_BREWFILE_REPO for this run
```

In `main()`, add `cli_brewfile_repo=""` to the existing locals line (currently line 98):

```bash
  local cli_dotfiles_repo="" cli_brewfile="" cli_brewfile_repo=""
```

Add two new case arms after the existing `--brewfile=*)` case (currently lines 141-144):

```bash
      -br|--brewfile-repo)
        if [ $# -lt 2 ]; then
          log_error "--brewfile-repo requires a value"
          usage
          exit 1
        fi
        cli_brewfile_repo="$2"
        shift 2
        ;;
      --brewfile-repo=*)
        cli_brewfile_repo="${1#--brewfile-repo=}"
        shift
        ;;
```

Add the override line after the existing `EXTRA_BREWFILE` override (currently line 181):

```bash
  [ -n "$cli_brewfile" ] && EXTRA_BREWFILE="$cli_brewfile"
  [ -n "$cli_brewfile_repo" ] && EXTRA_BREWFILE_REPO="$cli_brewfile_repo"
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run: `bats tests/homebrew.bats -f "_resolve_extra_brewfile|cloned extra Brewfile"`
Run: `bats tests/macup.bats -f "brewfile-repo|-br"`
Expected: PASS (9 tests in homebrew.bats, 3 in macup.bats)

- [ ] **Step 8: Update `macup.conf.example` and `README.md`**

In `macup.conf.example`, after the existing `#EXTRA_BREWFILE=` line, add:

```
# Git URL of a repo containing an additional Brewfile, cloned into
# ~/.cache/macup/brewfile-repo. When set, EXTRA_BREWFILE (above) is
# the relative path to the Brewfile *within that repo* instead of a
# local path — defaults to "Brewfile" at the repo's root if left blank.
#EXTRA_BREWFILE_REPO=
```

In `README.md`'s `Usage` section, add a line after the existing `macup --brewfile=<path> homebrew` example:

```sh
macup --brewfile-repo=<url> homebrew
```

In `README.md`'s `Configuration` section, after the existing paragraph explaining `--dotfiles-repo=<url>` and `--brewfile=<path>`, add a short paragraph explaining `EXTRA_BREWFILE_REPO`/`--brewfile-repo=<url>` and how it reinterprets `EXTRA_BREWFILE` as an in-repo relative path, mirroring how `DOTFILES_REPO` is already documented just above it.

- [ ] **Step 9: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (137 existing + 12 new = 149)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 10: Commit**

```bash
git add lib/homebrew.sh lib/common.sh bin/macup macup.conf.example README.md tests/homebrew.bats tests/macup.bats
git commit -m "feat: support a git-repo-backed extra Brewfile"
```

---

### Task 2: `--brewfile-only`/`-bo` flag

Depends on Task 1 being complete (this task's file references assume
Task 1's flag-parsing cases and `_resolve_extra_brewfile` wiring already
exist).

**Files:**
- Modify: `lib/homebrew.sh` (`run_homebrew` — wrap the existing bundled-Brewfile block, add the "nothing to bundle" warning)
- Modify: `bin/macup` (`usage()`, `main()` — new `-bo|--brewfile-only` flag, `MACUP_BREWFILE_ONLY` export mirroring `MACUP_DRY_RUN`)
- Test: `tests/homebrew.bats`, `tests/macup.bats`

**Interfaces:**
- Consumes: `$MACUP_BREWFILE_ONLY` (set by `bin/macup`, read by `lib/homebrew.sh`) — same pattern as the existing `$MACUP_DRY_RUN`/`is_dry_run`.

- [ ] **Step 1: Write the failing tests**

In `tests/homebrew.bats`, add these tests (after the tests Task 1 added):

```bash
@test "run_homebrew skips the bundled Brewfile when MACUP_BREWFILE_ONLY is set" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  echo 'brew "jq"' > "$EXTRA_BREWFILE"
  export MACUP_BREWFILE_ONLY=1

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$EXTRA_BREWFILE" "$MACUP_CALL_LOG"
  ! grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew runs both Brewfiles when MACUP_BREWFILE_ONLY is not set" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  echo 'brew "jq"' > "$EXTRA_BREWFILE"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$EXTRA_BREWFILE" "$MACUP_CALL_LOG"
}

@test "run_homebrew warns when MACUP_BREWFILE_ONLY is set but no extra Brewfile is configured" {
  install_stub_brew
  export MACUP_BREWFILE_ONLY=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"--brewfile-only set but no extra Brewfile configured"* ]]
  ! grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}
```

In `tests/macup.bats`, add this test (near the existing `-n|--dry-run` tests):

```bash
@test "macup -bo sets MACUP_BREWFILE_ONLY and skips the bundled Brewfile" {
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  echo 'brew "jq"' > "$EXTRA_BREWFILE"

  run "$MACUP_BIN" -bo homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$EXTRA_BREWFILE" "$MACUP_CALL_LOG"
  ! grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}
```

**Important — bash/bats `!`-negation gotcha, verified directly:** `set -e`
(which bats test bodies run under) never triggers on a negated (`!`-prefixed)
command, *regardless of what the underlying command actually returns* —
this is documented bash behavior, not a bug. Concretely:
`bash -c 'set -e; ! false; echo "still reached"'` prints "still reached"
and exits 0. This means a non-final `! grep -q ...` line in a test body is
silently a no-op — it can never fail the test by itself, since bats only
evaluates the *last* command's exit status. **Every negated assertion in
this plan's tests must be the final statement in its test body** — the
three tests above are written this way already (negated `grep` last);
preserve that exact ordering when implementing, don't rearrange it back
to a more "natural" reading order with the positive assertion last.

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/homebrew.bats -f "MACUP_BREWFILE_ONLY"`
Run: `bats tests/macup.bats -f "\-bo"`
Expected: FAIL — `MACUP_BREWFILE_ONLY` isn't read anywhere yet, `-bo` isn't a recognized flag yet.

- [ ] **Step 3: Wrap the bundled-Brewfile block in `lib/homebrew.sh`**

In `run_homebrew`, find the existing bundled-Brewfile block (the one Task 1 left untouched, starting with `if is_dry_run; then` / `dry_run_report "run: brew bundle --file=$ROOT_DIR/Brewfile"` and ending with its matching `fi`, immediately followed by the `if [ -n "${EXTRA_BREWFILE:-}" ]; then` block). Wrap it in a new outer condition:

```bash
  if [ "${MACUP_BREWFILE_ONLY:-0}" != "1" ]; then
    if is_dry_run; then
      dry_run_report "run: brew bundle --file=$ROOT_DIR/Brewfile"
    else
      log_info "Running brew bundle with default Brewfile"
      if ! "$brew_bin" bundle --file="$ROOT_DIR/Brewfile"; then
        log_error "brew bundle failed for default Brewfile"
        return 1
      fi
    fi
  fi
```

(Just add the new `if [ "${MACUP_BREWFILE_ONLY:-0}" != "1" ]; then` / `fi` wrapper around the existing block's contents — don't change anything inside it.)

Then, immediately before the existing `if [ -n "${EXTRA_BREWFILE:-}" ]; then` block (the extra-Brewfile bundle block, untouched by this task otherwise), add the sanity warning:

```bash
  if [ "${MACUP_BREWFILE_ONLY:-0}" = "1" ] && [ -z "${EXTRA_BREWFILE:-}" ]; then
    log_warn "--brewfile-only set but no extra Brewfile configured (EXTRA_BREWFILE/EXTRA_BREWFILE_REPO); nothing to bundle"
  fi

```

- [ ] **Step 4: Add the `-bo|--brewfile-only` flag to `bin/macup`**

In `usage()`, add a line after the `-br, --brewfile-repo=<url>` line Task 1 added:

```
  -bo, --brewfile-only          Skip the bundled Brewfile, run only the extra one
```

(Exactly 10 spaces between `-only` and `Skip` — verified programmatically to put the description at column 32, matching every other line in this block.)

In `main()`, add a new `local brewfile_only=false` line alongside the existing `local dry_run=false` line.

Add a new case arm alongside the existing `-n|--dry-run)` case:

```bash
      -bo|--brewfile-only)
        brewfile_only=true
        shift
        ;;
```

Add the export, mirroring the existing `MACUP_DRY_RUN` export block exactly (same location, right after it):

```bash
  if [ "$brewfile_only" = true ]; then
    MACUP_BREWFILE_ONLY=1
  else
    MACUP_BREWFILE_ONLY=0
  fi
  export MACUP_BREWFILE_ONLY
```

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `bats tests/homebrew.bats -f "MACUP_BREWFILE_ONLY"`
Run: `bats tests/macup.bats -f "\-bo"`
Expected: PASS (3 tests in homebrew.bats, 1 in macup.bats)

- [ ] **Step 6: Update `README.md`**

In `README.md`'s `Usage` section, add a line after the `macup --brewfile-repo=<url> homebrew` example Task 1 added:

```sh
macup --brewfile-only homebrew    # run only the extra Brewfile, skip the bundled one
```

Add a short sentence to the `Configuration` section (near the `EXTRA_BREWFILE_REPO` paragraph Task 1 added) noting that `--brewfile-only`/`-bo` skips the bundled Brewfile for that run only — it's not a persisted config setting.

- [ ] **Step 7: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (149 from Task 1 + 4 new = 153)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 8: Commit**

```bash
git add lib/homebrew.sh bin/macup README.md tests/homebrew.bats tests/macup.bats
git commit -m "feat: add --brewfile-only to skip the bundled Brewfile"
```
