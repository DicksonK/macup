# Skippable Git Identity Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users skip the git `user.name`/`user.email` prompt in the `dotfiles` module, either via a new `--skip-git-identity` CLI flag or by leaving the interactive prompt blank, and stop it from blocking non-interactive runs.

**Architecture:** `lib/dotfiles.sh`'s `run_dotfiles` gains a priority-ordered check (already-configured → skip flag → dry-run → non-interactive-without-flag → interactive prompt) reading a new `MACUP_SKIP_GIT_IDENTITY` env var. `bin/macup` gains CLI parsing for `--skip-git-identity` that sets and exports that env var, matching the existing pattern for `MACUP_DRY_RUN`.

**Tech Stack:** Bash, bats (bats-core) for tests, existing `tests/test_helper/stubs/gum` and `tests/test_helper/stubs/git` fakes.

## Global Constraints

- Follow the existing code style in lib/dotfiles.sh and bin/macup exactly (2-space indent, `local` declarations, `log_info`/`log_warn`/`dry_run_report` helpers from lib/common.sh).
- Every new env var must default safely when unset (`"${VAR:-0}"` pattern), matching `MACUP_DRY_RUN`/`MACUP_NONINTERACTIVE`.
- Do not change behavior for: identity already configured, dry-run message when not skipped, or the `DOTFILES_REPO` early-exit (identity setup never runs when `DOTFILES_REPO` is set).
- Out of scope: lib/github.sh's SSH-key email fallback prompt is untouched.
- Run tests with: `bats tests/dotfiles.bats` and `bats tests/macup.bats` (bats-core must be on PATH; if not installed, run `brew install bats-core` first — do not skip verification).

---

### Task 1: Skip/non-interactive/blank-skip logic in `run_dotfiles`

**Files:**
- Modify: `lib/dotfiles.sh:95-115` (the git identity block inside `run_dotfiles`)
- Test: `tests/dotfiles.bats`

**Interfaces:**
- Consumes: `MACUP_SKIP_GIT_IDENTITY` (new env var, `"1"` or unset/`"0"`), `MACUP_NONINTERACTIVE` (existing env var, already read elsewhere via `${MACUP_NONINTERACTIVE:-0}` convention), `is_dry_run` (existing function in lib/common.sh), `log_info`/`log_warn`/`dry_run_report` (existing, lib/common.sh), `ui_input` (existing, lib/menu.sh).
- Produces: no new function names — behavior change only inside `run_dotfiles`. Later tasks (Task 2) rely on `run_dotfiles` honoring `MACUP_SKIP_GIT_IDENTITY=1` by logging the exact string `"Skipping git identity setup (--skip-git-identity)"` and not writing `~/.gitconfig.local`.

This task changes only `lib/dotfiles.sh` and is tested directly by sourcing the lib and calling `run_dotfiles` (as all existing `tests/dotfiles.bats` tests already do) — no CLI flag exists yet, so tests set `MACUP_SKIP_GIT_IDENTITY`/`MACUP_NONINTERACTIVE` as plain env vars.

- [ ] **Step 1: Write the failing tests**

Add these four tests to `tests/dotfiles.bats`, directly after the existing test `"run_dotfiles re-prompts on a second run when the identity was left empty"` (which ends at line 169 with a closing `}`):

```bash
@test "run_dotfiles skips git identity setup when MACUP_SKIP_GIT_IDENTITY is set" {
  export MACUP_SKIP_GIT_IDENTITY=1
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git identity setup (--skip-git-identity)"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
  ! grep -q "gum input" "$MACUP_CALL_LOG"
}

@test "run_dotfiles warns and skips git identity setup when non-interactive without the skip flag" {
  export MACUP_NONINTERACTIVE=1
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git identity setup: no identity configured and running non-interactively"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
  ! grep -q "gum input" "$MACUP_CALL_LOG"
}

@test "run_dotfiles skips writing git identity when the prompts are left blank" {
  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped git identity setup"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}

@test "run_dotfiles skips writing git identity when only the email prompt is left blank" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped git identity setup"* ]]
  [ -z "$(git config -f "$HOME/.gitconfig.local" --get user.email 2>/dev/null || true)" ]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/dotfiles.bats`
Expected: the 4 new tests FAIL (the `MACUP_SKIP_GIT_IDENTITY`/non-interactive tests fail because `run_dotfiles` still prompts and writes; the blank-input tests fail because today a blank prompt writes an *empty* `user.name`/`user.email` entry to `~/.gitconfig.local` instead of skipping — so `[ ! -f "$HOME/.gitconfig.local" ]` and the email-only check fail). All pre-existing tests in the file still PASS.

- [ ] **Step 3: Replace the identity block in `lib/dotfiles.sh`**

Replace the block currently at lib/dotfiles.sh:95-115:

```bash
  if [ -z "${DOTFILES_REPO:-}" ]; then
    local identity_file="$HOME/.gitconfig.local"
    local cur_name cur_email
    cur_name="$(git config -f "$identity_file" --get user.name 2>/dev/null || true)"
    cur_email="$(git config -f "$identity_file" --get user.email 2>/dev/null || true)"

    if [ -n "$cur_name" ] && [ -n "$cur_email" ]; then
      log_info "Git identity already configured in $identity_file, skipping"
    elif is_dry_run; then
      dry_run_report "prompt for and write git identity to $identity_file"
    else
      [ -n "$cur_name" ] || cur_name="$(ui_input "Git user.name" "")"
      [ -n "$cur_email" ] || cur_email="$(ui_input "Git user.email" "")"
      if git config -f "$identity_file" user.name "$cur_name" \
        && git config -f "$identity_file" user.email "$cur_email"; then
        log_info "Wrote git identity to $identity_file"
      else
        log_warn "Failed to write git identity to $identity_file"
      fi
    fi
  fi
```

with:

```bash
  if [ -z "${DOTFILES_REPO:-}" ]; then
    local identity_file="$HOME/.gitconfig.local"
    local cur_name cur_email
    cur_name="$(git config -f "$identity_file" --get user.name 2>/dev/null || true)"
    cur_email="$(git config -f "$identity_file" --get user.email 2>/dev/null || true)"

    if [ -n "$cur_name" ] && [ -n "$cur_email" ]; then
      log_info "Git identity already configured in $identity_file, skipping"
    elif [ "${MACUP_SKIP_GIT_IDENTITY:-0}" = "1" ]; then
      log_info "Skipping git identity setup (--skip-git-identity)"
    elif is_dry_run; then
      dry_run_report "prompt for and write git identity to $identity_file"
    elif [ "${MACUP_NONINTERACTIVE:-0}" = "1" ]; then
      log_warn "Skipping git identity setup: no identity configured and running non-interactively (pass --skip-git-identity to silence this, or configure $identity_file directly)"
    else
      [ -n "$cur_name" ] || cur_name="$(ui_input "Git user.name (leave blank to skip)" "")"
      [ -n "$cur_email" ] || cur_email="$(ui_input "Git user.email (leave blank to skip)" "")"
      if [ -z "$cur_name" ] || [ -z "$cur_email" ]; then
        log_info "Skipped git identity setup"
      elif git config -f "$identity_file" user.name "$cur_name" \
        && git config -f "$identity_file" user.email "$cur_email"; then
        log_info "Wrote git identity to $identity_file"
      else
        log_warn "Failed to write git identity to $identity_file"
      fi
    fi
  fi
```

- [ ] **Step 4: Run the full dotfiles test suite to verify everything passes**

Run: `bats tests/dotfiles.bats`
Expected: PASS — all pre-existing tests plus the 4 new ones. In particular, re-check by eye (bats will confirm) that:
- `"run_dotfiles prompts for and writes git identity when using bundled dotfiles"` still passes (both prompts return `"Jane Doe"`, so neither is blank).
- `"run_dotfiles re-prompts on a second run when the identity was left empty"` still passes (first run now skips without writing anything instead of writing an empty entry, but the assertion only checks the second run's output doesn't say "already configured" — still true).
- `"run_dotfiles logs a warning instead of false success when writing git identity fails"` still passes (both prompts non-blank, so it reaches the `git config` call and fails on the read-only `$HOME`).

If anything fails, read the diff between expected and actual output before changing code — don't guess.

- [ ] **Step 5: Commit**

```bash
git add lib/dotfiles.sh tests/dotfiles.bats
git commit -m "feat: allow skipping git identity setup via env var and blank input"
```

---

### Task 2: `--skip-git-identity` CLI flag in `bin/macup`

**Files:**
- Modify: `bin/macup:33-51` (usage text) and `bin/macup:96-199` (`main`: flag parsing + export block)
- Test: `tests/macup.bats`

**Interfaces:**
- Consumes: `MACUP_SKIP_GIT_IDENTITY` behavior from Task 1 (`run_dotfiles` in lib/dotfiles.sh already reads this env var and logs `"Skipping git identity setup (--skip-git-identity)"` when it's `"1"`).
- Produces: nothing further downstream — this is the last task.

- [ ] **Step 1: Write the failing tests**

Add these two tests to `tests/macup.bats`, directly after the test `"macup -h prints usage and exits 0"` (ends at line 55 with `}`):

```bash
@test "macup --help documents --skip-git-identity" {
  run "$MACUP_BIN" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"--skip-git-identity"* ]]
}
```

Add this test directly after the test `"macup --dotfiles-repo overrides DOTFILES_REPO for this run only"` (ends around line 78 with `}`):

```bash
@test "macup --skip-git-identity skips the git identity prompt" {
  run "$MACUP_BIN" --skip-git-identity dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping git identity setup (--skip-git-identity)"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/macup.bats`
Expected: both new tests FAIL — `--skip-git-identity` isn't a recognized flag yet, so `macup --help` won't mention it, and `macup --skip-git-identity dotfiles` will exit 1 with `"Unknown argument: --skip-git-identity"`.

- [ ] **Step 3: Add the flag to `usage()`**

In `bin/macup`, in the `usage()` heredoc (bin/macup:33-51), change:

```
  -bo, --brewfile-only          Skip the bundled Brewfile, run only the extra one
  -v, --version                 Print the installed version and exit
```

to:

```
  -bo, --brewfile-only          Skip the bundled Brewfile, run only the extra one
  --skip-git-identity           Skip prompting for/writing git user.name and user.email
  -v, --version                 Print the installed version and exit
```

- [ ] **Step 4: Parse the flag and export the env var in `main()`**

In `bin/macup`, add a new local flag next to the existing ones. Change:

```bash
main() {
  local invocation="$*"
  local run_all=false
  local dry_run=false
  local brewfile_only=false
  local cli_dotfiles_repo="" cli_brewfile="" cli_brewfile_repo=""
  local -a modules=()
```

to:

```bash
main() {
  local invocation="$*"
  local run_all=false
  local dry_run=false
  local brewfile_only=false
  local skip_git_identity=false
  local cli_dotfiles_repo="" cli_brewfile="" cli_brewfile_repo=""
  local -a modules=()
```

Then add a case arm. Change:

```bash
      -bo|--brewfile-only)
        brewfile_only=true
        shift
        ;;
      homebrew|shell|dotfiles|macos-defaults|github)
```

to:

```bash
      -bo|--brewfile-only)
        brewfile_only=true
        shift
        ;;
      --skip-git-identity)
        skip_git_identity=true
        shift
        ;;
      homebrew|shell|dotfiles|macos-defaults|github)
```

Then export the env var alongside the other `MACUP_*` exports. Change:

```bash
  if [ "$brewfile_only" = true ]; then
    MACUP_BREWFILE_ONLY=1
  else
    MACUP_BREWFILE_ONLY=0
  fi
  export MACUP_BREWFILE_ONLY

  if is_dry_run; then
```

to:

```bash
  if [ "$brewfile_only" = true ]; then
    MACUP_BREWFILE_ONLY=1
  else
    MACUP_BREWFILE_ONLY=0
  fi
  export MACUP_BREWFILE_ONLY

  if [ "$skip_git_identity" = true ]; then
    MACUP_SKIP_GIT_IDENTITY=1
  else
    MACUP_SKIP_GIT_IDENTITY=0
  fi
  export MACUP_SKIP_GIT_IDENTITY

  if is_dry_run; then
```

- [ ] **Step 5: Run the full macup test suite to verify everything passes**

Run: `bats tests/macup.bats`
Expected: PASS — all pre-existing tests plus the 2 new ones.

- [ ] **Step 6: Run the whole test suite once more**

Run: `bats tests/`
Expected: PASS, no regressions in any `.bats` file.

- [ ] **Step 7: Commit**

```bash
git add bin/macup tests/macup.bats
git commit -m "feat: add --skip-git-identity CLI flag"
```
