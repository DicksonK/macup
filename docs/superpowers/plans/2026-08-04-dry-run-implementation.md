# Dry Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `mac-up --dry-run`: every module still runs its real,
read-only detection/idempotency logic, but every mutation and every
interactive prompt is replaced with a `[dry-run] would ...` report line.

**Architecture:** Two small helpers in `lib/common.sh`
(`is_dry_run`, `dry_run_report`) plus a `--dry-run` flag in `bin/mac-up`
that exports `MAC_UP_DRY_RUN`. Each of the five modules gets `if
is_dry_run; then dry_run_report "..."; else <real action>; fi` guards at
its specific mutation/prompt points — no shared command wrapper, since
the curl-piped installers (Homebrew, Oh My Zsh) would still execute their
`curl` download if merely passed as arguments to a wrapper function
(bash evaluates command substitutions before the function call), and
interactive prompts aren't "commands" a wrapper could intercept anyway.

**Tech Stack:** bash, bats-core (unchanged from the base project).

## Global Constraints

- Read-only detection/idempotency logic (does the binary/file/theme/
  setting/key already exist or match) always runs for real, even in
  dry-run — that's what makes the report accurate. Only an actual
  mutation or an interactive prompt gets guarded.
- `--dry-run` is orthogonal to `MAC_UP_NONINTERACTIVE`/`--all`/module
  selection — it does not force non-interactive module selection.
- The curl-piped installers (Homebrew's install script, Oh My Zsh's
  install script) must have their *entire* invocation inside the
  `else` branch — never construct the command line (with its
  `$(curl ...)` substitution) unconditionally and only branch on
  executing it, since that would still perform the download.
- If `gh` isn't already authenticated, dry-run reports authentication
  and the SSH-key-registration check as **one combined line** and skips
  the real registration-check block entirely for that run — it cannot
  fake what a real auth session would find registered.
- When an SSH key already exists, printing/copying its public key
  (`cat`, `pbcopy`) is **not** guarded — it's reading an unchanged,
  pre-existing artifact, not a mutation, and runs the same in both modes.
- No new test-stub infrastructure — dry-run tests assert a mutating stub
  command is *absent* from `$MAC_UP_CALL_LOG` while the `[dry-run] would
  ...` line is present in the captured output.
- Every module's existing (non-dry-run) behavior, return-code semantics,
  and log messages are unchanged when `MAC_UP_DRY_RUN` is unset/`0` —
  every pre-existing test in the suite must keep passing untouched.

---

## File Structure

```
mac-up/
├── bin/mac-up               # + --dry-run flag, MAC_UP_DRY_RUN, banner, summary line
├── lib/
│   ├── common.sh              # + is_dry_run(), dry_run_report()
│   ├── homebrew.sh            # dry-run guards (Task 2)
│   ├── shell.sh                # dry-run guards (Task 2)
│   ├── dotfiles.sh             # dry-run guards (Task 3)
│   ├── macos_defaults.sh       # dry-run guards (Task 4)
│   └── github.sh                # dry-run guards (Task 5)
└── tests/
    ├── common.bats               # + 3 tests (Task 1)
    ├── mac_up.bats                # + 1 test (Task 1), + 1 test (Task 6)
    ├── homebrew.bats               # + 3 tests (Task 2)
    ├── shell.bats                  # + 2 tests (Task 2)
    ├── dotfiles.bats                # + 6 tests (Task 3)
    ├── macos_defaults.bats           # + 4 tests (Task 4)
    └── github.bats                    # + 4 tests (Task 5)
```

---

### Task 1: `is_dry_run`/`dry_run_report` helpers + `bin/mac-up` wiring

**Files:**
- Modify: `lib/common.sh`
- Modify: `bin/mac-up`
- Test: `tests/common.bats`
- Test: `tests/mac_up.bats`

**Interfaces:**
- Produces: `is_dry_run()` → returns 0 (true) if `MAC_UP_DRY_RUN=1`, 1
  (false) otherwise. `dry_run_report(description)` → logs `"[dry-run]
  would $description"` via `log_info`. `MAC_UP_DRY_RUN` env var (`1` or
  `0`), exported by `bin/mac-up`, consumed by [[Task 2]] through
  [[Task 5]]'s module guards.

- [ ] **Step 1: Write the failing tests for the helpers**

Append to `tests/common.bats` (after the last existing test, `init_log_file
treats a pre-existing unwritable logs directory as a graceful-degradation
case, not a crash`):

```bash
@test "is_dry_run returns false when MAC_UP_DRY_RUN is unset" {
  unset MAC_UP_DRY_RUN

  run is_dry_run

  [ "$status" -eq 1 ]
}

@test "is_dry_run returns true when MAC_UP_DRY_RUN=1" {
  export MAC_UP_DRY_RUN=1

  run is_dry_run

  [ "$status" -eq 0 ]
}

@test "dry_run_report logs a [dry-run]-prefixed message via log_info" {
  run dry_run_report "do the thing"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would do the thing"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/common.bats`
Expected: FAIL — `is_dry_run: command not found`.

- [ ] **Step 3: Implement the helpers in `lib/common.sh`**

Insert between the existing `log_error` function and `load_config`:

```bash
is_dry_run() {
  [ "${MAC_UP_DRY_RUN:-0}" = "1" ]
}

dry_run_report() {
  log_info "[dry-run] would $1"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/common.bats`
Expected: PASS (19 tests: 16 existing + 3 new).

- [ ] **Step 5: Write the failing `bin/mac-up` test**

Append to `tests/mac_up.bats` (after the last existing test, `mac-up
creates a per-run log file and reports its path in the summary`):

```bash
@test "mac-up --dry-run prints a startup banner and a summary note" {
  run "$MAC_UP_BIN" --dry-run homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `bats tests/mac_up.bats`
Expected: FAIL — no `--dry-run` flag exists yet, so it's rejected as an
unknown argument.

- [ ] **Step 7: Wire `--dry-run` into `bin/mac-up`**

In `usage()`, add the new option (after `--all`):

```
  --all                     Run all modules, non-interactive
  --dry-run                 Preview actions without making changes
```

In `main()`, add `local dry_run=false` alongside the existing `local
run_all=false`:

```bash
main() {
  local invocation="$*"
  local run_all=false
  local dry_run=false
  local cli_dotfiles_repo="" cli_brewfile=""
  local -a modules=()
```

Add a `--dry-run` case to the flag-parsing loop (after the `--all` case):

```bash
      --all)
        run_all=true
        shift
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
```

After the existing `MAC_UP_NONINTERACTIVE` computation/export block (and
before `load_config`), add the `MAC_UP_DRY_RUN` computation/export and
the startup banner:

```bash
  if [ "$run_all" = true ] || [ "${#modules[@]}" -gt 0 ]; then
    MAC_UP_NONINTERACTIVE=1
  else
    MAC_UP_NONINTERACTIVE=0
  fi
  export MAC_UP_NONINTERACTIVE

  if [ "$dry_run" = true ]; then
    MAC_UP_DRY_RUN=1
  else
    MAC_UP_DRY_RUN=0
  fi
  export MAC_UP_DRY_RUN

  if is_dry_run; then
    log_info "Dry run: no changes will be made"
  fi

  load_config
```

In `run_selected_modules`, add the dry-run summary note (after the
`succeeded`/`failed` lines, before the `MAC_UP_LOG_FILE` line):

```bash
  if [ "${#failed[@]}" -gt 0 ]; then
    log_warn "  failed: ${failed[*]}"
  fi
  if is_dry_run; then
    log_info "(dry run — nothing was actually changed)"
  fi
  if [ -n "${MAC_UP_LOG_FILE:-}" ]; then
    log_info "Full log: $MAC_UP_LOG_FILE"
  fi
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bats tests/mac_up.bats`
Expected: PASS (9 tests: 8 existing + 1 new).

- [ ] **Step 9: Run the full suite**

Run: `bats tests/`
Expected: PASS (73 tests: 69 existing + 3 (common.bats) + 1
(mac_up.bats)).

- [ ] **Step 10: Commit**

```bash
git add lib/common.sh bin/mac-up tests/common.bats tests/mac_up.bats
git commit -m "feat: add dry-run helpers and CLI wiring"
```

---

### Task 2: `lib/homebrew.sh` + `lib/shell.sh` dry-run guards

**Files:**
- Modify: `lib/homebrew.sh`
- Modify: `lib/shell.sh`
- Test: `tests/homebrew.bats`
- Test: `tests/shell.bats`

**Interfaces:**
- Consumes: `is_dry_run()`, `dry_run_report()` ([[Task 1]]).
- Produces: nothing new consumed by other tasks — `run_homebrew()` and
  `run_shell()`'s signatures and return-code semantics are unchanged.

- [ ] **Step 1: Write the failing tests for `lib/homebrew.sh`**

Append to `tests/homebrew.bats` (after the last existing test, `run_homebrew
warns and continues when EXTRA_BREWFILE is set but missing`):

```bash
@test "run_homebrew reports it would install Homebrew in dry-run mode when brew is missing" {
  export MAC_UP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would install Homebrew via the official install script"* ]]
}

@test "run_homebrew reports the default bundle in dry-run mode without calling brew" {
  install_stub_brew
  export MAC_UP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would run: brew bundle --file=$ROOT_DIR/Brewfile"* ]]
  [ ! -s "$MAC_UP_CALL_LOG" ] || ! grep -q "brew" "$MAC_UP_CALL_LOG"
}

@test "run_homebrew reports the extra Brewfile bundle in dry-run mode without running it" {
  install_stub_brew
  echo "brew \"jq\"" > "$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  export MAC_UP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would run: brew bundle --file=$TEST_HOME/extra.Brewfile"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/homebrew.bats`
Expected: FAIL — `MAC_UP_DRY_RUN` has no effect yet, so the real
(stubbed) `brew` gets called and the dry-run messages never print.

- [ ] **Step 3: Implement the guards in `lib/homebrew.sh`**

Replace the entire content of `lib/homebrew.sh` with:

```bash
#!/usr/bin/env bash

: "${MAC_UP_BREW_PATH_APPLE_SILICON:=/opt/homebrew/bin/brew}"
: "${MAC_UP_BREW_PATH_INTEL:=/usr/local/bin/brew}"

run_homebrew() {
  local brew_bin=""
  if [ -x "$MAC_UP_BREW_PATH_APPLE_SILICON" ]; then
    brew_bin="$MAC_UP_BREW_PATH_APPLE_SILICON"
  elif [ -x "$MAC_UP_BREW_PATH_INTEL" ]; then
    brew_bin="$MAC_UP_BREW_PATH_INTEL"
  fi

  if [ -z "$brew_bin" ]; then
    if is_dry_run; then
      dry_run_report "install Homebrew via the official install script"
    else
      log_info "Homebrew not found, installing"
      if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        log_error "Homebrew installation failed"
        return 1
      fi
      if [ -x "$MAC_UP_BREW_PATH_APPLE_SILICON" ]; then
        brew_bin="$MAC_UP_BREW_PATH_APPLE_SILICON"
      else
        brew_bin="$MAC_UP_BREW_PATH_INTEL"
      fi
    fi
  fi

  if is_dry_run; then
    dry_run_report "run: brew bundle --file=$ROOT_DIR/Brewfile"
  else
    log_info "Running brew bundle with default Brewfile"
    if ! "$brew_bin" bundle --file="$ROOT_DIR/Brewfile"; then
      log_error "brew bundle failed for default Brewfile"
      return 1
    fi
  fi

  if [ -n "${EXTRA_BREWFILE:-}" ]; then
    if [ -f "$EXTRA_BREWFILE" ]; then
      if is_dry_run; then
        dry_run_report "run: brew bundle --file=$EXTRA_BREWFILE"
      else
        log_info "Running brew bundle with extra Brewfile: $EXTRA_BREWFILE"
        if ! "$brew_bin" bundle --file="$EXTRA_BREWFILE"; then
          log_warn "brew bundle failed for extra Brewfile: $EXTRA_BREWFILE"
        fi
      fi
    else
      log_warn "EXTRA_BREWFILE set but not found: $EXTRA_BREWFILE"
    fi
  fi

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/homebrew.bats`
Expected: PASS (7 tests: 4 existing + 3 new).

- [ ] **Step 5: Write the failing tests for `lib/shell.sh`**

Append to `tests/shell.bats` (after the last existing test, `run_shell
clones powerlevel10k when oh-my-zsh exists but the theme doesn't`):

```bash
@test "run_shell reports what it would do in dry-run mode without installing anything" {
  export MAC_UP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would install Oh My Zsh via the official install script"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k into $HOME/.oh-my-zsh/custom/themes/powerlevel10k"* ]]
  [ ! -d "$HOME/.oh-my-zsh" ]
}

@test "run_shell reports the Powerlevel10k clone in dry-run mode when Oh My Zsh already exists" {
  mkdir -p "$HOME/.oh-my-zsh"
  export MAC_UP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed, skipping"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k"* ]]
  [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
}
```

- [ ] **Step 6: Run to verify they fail**

Run: `bats tests/shell.bats`
Expected: FAIL — no dry-run guards exist yet.

- [ ] **Step 7: Implement the guards in `lib/shell.sh`**

Replace the entire content of `lib/shell.sh` with:

```bash
#!/usr/bin/env bash

run_shell() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if is_dry_run; then
      dry_run_report "install Oh My Zsh via the official install script"
    else
      log_info "Installing Oh My Zsh"
      if ! ui_spin "Installing Oh My Zsh" -- env CHSH=no RUNZSH=no /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
        log_error "Oh My Zsh installation failed"
        return 1
      fi
    fi
  else
    log_info "Oh My Zsh already installed, skipping"
  fi

  local p10k_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$p10k_dir" ]; then
    if is_dry_run; then
      dry_run_report "clone Powerlevel10k into $p10k_dir"
    else
      log_info "Cloning Powerlevel10k"
      if ! ui_spin "Cloning Powerlevel10k" -- git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"; then
        log_error "Powerlevel10k clone failed"
        return 1
      fi
    fi
  else
    log_info "Powerlevel10k already installed, skipping"
  fi

  return 0
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bats tests/shell.bats`
Expected: PASS (4 tests: 2 existing + 2 new).

- [ ] **Step 9: Run the full suite**

Run: `bats tests/`
Expected: PASS (78 tests: 73 + 3 (homebrew.bats) + 2 (shell.bats)).

- [ ] **Step 10: Commit**

```bash
git add lib/homebrew.sh lib/shell.sh tests/homebrew.bats tests/shell.bats
git commit -m "feat: add dry-run guards to homebrew and shell modules"
```

---

### Task 3: `lib/dotfiles.sh` dry-run guards

**Files:**
- Modify: `lib/dotfiles.sh`
- Test: `tests/dotfiles.bats`

**Interfaces:**
- Consumes: `is_dry_run()`, `dry_run_report()` ([[Task 1]]).
- Produces: nothing new consumed by other tasks — `run_dotfiles()`'s
  signature and return-code semantics are unchanged.

**Known, accepted limitation (not a bug to fix):** if `DOTFILES_REPO` is
set and this is the first run (cache not yet cloned), dry-run skips the
clone, so `source_dir` points at a directory that doesn't exist on disk.
The per-file loop then finds nothing to iterate (bash's non-dotglob `*`
glob on a missing directory matches nothing), and the pre-existing "No
dotfiles found to link in $source_dir" warning fires. This is a little
imprecise (files may well exist in the real, uncloned repo) but harmless
(no mutation) and unavoidable without actually cloning — accept it as-is.

- [ ] **Step 1: Write the failing tests**

Append to `tests/dotfiles.bats` (after the last existing test, `run_dotfiles
does not touch git identity when DOTFILES_REPO is set`):

```bash
@test "run_dotfiles reports fresh links in dry-run mode without creating them" {
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would link $HOME/.zshrc -> $ROOT_DIR/dotfiles/zshrc"* ]]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -L "$HOME/.zshrc" ]
}

@test "run_dotfiles reports the confirm-and-backup prompt in dry-run mode without prompting or mutating" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would prompt to back up and replace $HOME/.zshrc"* ]]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  ! grep -q "gum confirm" "$MAC_UP_CALL_LOG"
}

@test "run_dotfiles reports the DOTFILES_REPO clone in dry-run mode without cloning" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would clone dotfiles repo git@github.com:example/dotfiles.git"* ]]
  [ ! -d "$HOME/.cache/mac-up/dotfiles-repo" ]
}

@test "run_dotfiles reports the DOTFILES_REPO pull in dry-run mode without pulling" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"
  mkdir -p "$HOME/.cache/mac-up/dotfiles-repo/.git"
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would update the dotfiles repo cache"* ]]
  ! grep -q "pull" "$MAC_UP_CALL_LOG"
}

@test "run_dotfiles reports the git identity prompt in dry-run mode without prompting or writing" {
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would prompt for and write git identity to $HOME/.gitconfig.local"* ]]
  [ ! -f "$HOME/.gitconfig.local" ]
}

@test "run_dotfiles still reports already-configured git identity in dry-run mode" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"
  git config -f "$HOME/.gitconfig.local" user.email "existing@example.com"
  export MAC_UP_DRY_RUN=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Git identity already configured in $HOME/.gitconfig.local, skipping"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/dotfiles.bats`
Expected: FAIL — no dry-run guards exist yet.

- [ ] **Step 3: Implement the guards in `lib/dotfiles.sh`**

Replace the entire content of `lib/dotfiles.sh` with:

```bash
#!/usr/bin/env bash

run_dotfiles() {
  local source_dir

  if [ -n "${DOTFILES_REPO:-}" ]; then
    local cache_dir="$HOME/.cache/mac-up/dotfiles-repo"
    if [ -d "$cache_dir/.git" ]; then
      if is_dry_run; then
        dry_run_report "update the dotfiles repo cache at $cache_dir"
      else
        log_info "Updating dotfiles repo cache"
        if ! git -C "$cache_dir" pull --ff-only; then
          log_warn "Failed to update dotfiles repo cache, using existing checkout"
        fi
      fi
    else
      if is_dry_run; then
        dry_run_report "clone dotfiles repo $DOTFILES_REPO into $cache_dir"
      else
        log_info "Cloning dotfiles repo: $DOTFILES_REPO"
        mkdir -p "$(dirname "$cache_dir")"
        if ! git clone "$DOTFILES_REPO" "$cache_dir"; then
          log_error "Failed to clone dotfiles repo: $DOTFILES_REPO"
          return 1
        fi
      fi
    fi
    source_dir="$cache_dir"
  else
    source_dir="$ROOT_DIR/dotfiles"
  fi

  local file target linked_count=0
  for file in "$source_dir"/*; do
    [ -e "$file" ] || continue
    target="$HOME/.$(basename "$file")"

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      if is_dry_run; then
        dry_run_report "link $target -> $file"
        linked_count=$((linked_count + 1))
        continue
      fi
      if ! ln -s "$file" "$target"; then
        log_error "Failed to link $target -> $file"
        continue
      fi
      log_info "Linked $target -> $file"
      linked_count=$((linked_count + 1))
      continue
    fi

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$file" ]; then
      log_info "$target already up to date"
      continue
    fi

    if is_dry_run; then
      dry_run_report "prompt to back up and replace $target"
      linked_count=$((linked_count + 1))
      continue
    fi

    if ui_confirm "$target already exists. Back it up and replace with symlink?"; then
      if [ -e "$target.mac-up-backup" ] || [ -L "$target.mac-up-backup" ]; then
        log_warn "Skipped $target: backup $target.mac-up-backup already exists"
        continue
      fi
      if ! mv "$target" "$target.mac-up-backup"; then
        log_error "Failed to back up $target, skipping"
        continue
      fi
      if ! ln -s "$file" "$target"; then
        log_error "Failed to link $target -> $file after backup"
        continue
      fi
      log_info "Backed up and linked $target -> $file"
      linked_count=$((linked_count + 1))
    else
      log_warn "Skipped $target"
    fi
  done

  if [ "$linked_count" -eq 0 ]; then
    log_warn "No dotfiles found to link in $source_dir"
  fi

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

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/dotfiles.bats`
Expected: PASS (21 tests: 15 existing + 6 new).

- [ ] **Step 5: Run the full suite**

Run: `bats tests/`
Expected: PASS (84 tests: 78 + 6).

- [ ] **Step 6: Commit**

```bash
git add lib/dotfiles.sh tests/dotfiles.bats
git commit -m "feat: add dry-run guards to dotfiles module"
```

---

### Task 4: `lib/macos_defaults.sh` dry-run guards

**Files:**
- Modify: `lib/macos_defaults.sh`
- Test: `tests/macos_defaults.bats`

**Interfaces:**
- Consumes: `is_dry_run()`, `dry_run_report()` ([[Task 1]]).
- Produces: nothing new consumed by other tasks — `run_macos_defaults()`'s
  signature and return-code semantics are unchanged.

- [ ] **Step 1: Write the failing tests**

Append to `tests/macos_defaults.bats` (after the last existing test,
`run_macos_defaults restarts Finder and SystemUIServer`):

```bash
@test "run_macos_defaults reports settings in dry-run mode without writing them" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would set com.apple.finder AppleShowAllExtensions = true"* ]]
  ! grep -q "defaults write" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults reports the Screenshots directory creation in dry-run mode without creating it" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would create $HOME/Screenshots"* ]]
  [ ! -d "$HOME/Screenshots" ]
}

@test "run_macos_defaults reports the Finder/SystemUIServer restart in dry-run mode without restarting" {
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would restart Finder and SystemUIServer"* ]]
  ! grep -q "killall" "$MAC_UP_CALL_LOG"
}

@test "run_macos_defaults still skips an already-applied setting in dry-run mode" {
  echo "com.apple.finder|AppleShowAllExtensions|1" > "$DEFAULTS_STORE"
  export MAC_UP_DRY_RUN=1

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.finder AppleShowAllExtensions already set to true, skipping"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/macos_defaults.bats`
Expected: FAIL — no dry-run guards exist yet.

- [ ] **Step 3: Implement the guards in `lib/macos_defaults.sh`**

Replace the entire content of `lib/macos_defaults.sh` with:

```bash
#!/usr/bin/env bash

_defaults_apply() {
  local domain="$1" key="$2" type="$3" value="$4"
  local current
  current="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  local expected="$value"
  if [ "$type" = "bool" ]; then
    case "$value" in
      true) expected=1 ;;
      false) expected=0 ;;
    esac
  fi
  if [ "$current" = "$expected" ]; then
    log_info "$domain $key already set to $value, skipping"
    return 0
  fi
  if is_dry_run; then
    dry_run_report "set $domain $key = $value"
    return 0
  fi
  if ! defaults write "$domain" "$key" "-$type" "$value"; then
    log_error "Failed to set $domain $key"
    return 1
  fi
  log_info "Set $domain $key = $value"
}

run_macos_defaults() {
  local failed=0
  if is_dry_run; then
    dry_run_report "create $HOME/Screenshots"
  else
    mkdir -p "$HOME/Screenshots"
  fi

  _defaults_apply com.apple.finder AppleShowAllExtensions bool true || failed=1
  _defaults_apply com.apple.finder AppleShowAllFiles bool true || failed=1
  _defaults_apply com.apple.finder ShowPathbar bool true || failed=1
  _defaults_apply com.apple.finder ShowStatusBar bool true || failed=1

  _defaults_apply NSGlobalDomain KeyRepeat int 2 || failed=1
  _defaults_apply NSGlobalDomain ApplePressAndHoldEnabled bool false || failed=1

  _defaults_apply com.apple.AppleMultitouchTrackpad Clicking bool true || failed=1

  _defaults_apply com.apple.screencapture location string "$HOME/Screenshots" || failed=1
  _defaults_apply com.apple.screencapture type string png || failed=1

  _defaults_apply NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true || failed=1
  _defaults_apply NSGlobalDomain PMPrintingExpandedStateForPrint bool true || failed=1

  if is_dry_run; then
    dry_run_report "restart Finder and SystemUIServer"
  else
    killall Finder >/dev/null 2>&1 || true
    killall SystemUIServer >/dev/null 2>&1 || true
  fi

  return "$failed"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/macos_defaults.bats`
Expected: PASS (10 tests: 6 existing + 4 new).

- [ ] **Step 5: Run the full suite**

Run: `bats tests/`
Expected: PASS (88 tests: 84 + 4).

- [ ] **Step 6: Commit**

```bash
git add lib/macos_defaults.sh tests/macos_defaults.bats
git commit -m "feat: add dry-run guards to macos-defaults module"
```

---

### Task 5: `lib/github.sh` dry-run guards

**Files:**
- Modify: `lib/github.sh`
- Test: `tests/github.bats`

**Interfaces:**
- Consumes: `is_dry_run()`, `dry_run_report()` ([[Task 1]]).
- Produces: nothing new consumed by other tasks — `run_github()`'s
  signature and return-code semantics are unchanged.

**Note on the auth/registration coupling:** when `gh` isn't already
authenticated, the dry-run branch reports one combined line and
`return 0`s immediately — this deliberately skips the pubkey-registration
check block entirely for that run (it depends on real authentication
having happened, which a dry run cannot fake). This is a direct
consequence of the plan's global constraint on this exact point — do not
try to make the registration check "work" in this branch.

- [ ] **Step 1: Write the failing tests**

Append to `tests/github.bats` (after the last existing test, `run_github
warns but does not fail when SSH key upload fails`):

```bash
@test "run_github reports SSH key generation in dry-run mode without generating a key" {
  export MAC_UP_DRY_RUN=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would generate an SSH key at $HOME/.ssh/id_ed25519"* ]]
  [ ! -f "$HOME/.ssh/id_ed25519" ]
}

@test "run_github reports auth+registration as one combined line in dry-run mode when not authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1
  export MAC_UP_DRY_RUN=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would authenticate via a GitHub PAT, then check/register the SSH key with GitHub"* ]]
  ! grep -q "auth login" "$MAC_UP_CALL_LOG"
  ! grep -q "api user/keys" "$MAC_UP_CALL_LOG"
  ! grep -q "ssh-key add" "$MAC_UP_CALL_LOG"
}

@test "run_github reports the ssh-key upload in dry-run mode when already authenticated but not registered" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS=""
  export MAC_UP_DRY_RUN=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would upload the SSH key to GitHub via gh ssh-key add"* ]]
  ! grep -q "ssh-key add" "$MAC_UP_CALL_LOG"
}

@test "run_github still reports an already-registered key in dry-run mode" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS="AAAAtest"
  export MAC_UP_DRY_RUN=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"SSH key already registered with GitHub, skipping"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/github.bats`
Expected: FAIL — no dry-run guards exist yet.

- [ ] **Step 3: Implement the guards in `lib/github.sh`**

Replace the entire content of `lib/github.sh` with:

```bash
#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    if is_dry_run; then
      dry_run_report "generate an SSH key at $key_path"
    else
      local email default_email
      default_email="$(git config -f "$HOME/.gitconfig.local" --get user.email 2>/dev/null || true)"
      if [ -n "$default_email" ]; then
        email="$default_email"
      else
        email="$(ui_input "Email for SSH key" "")"
      fi
      log_info "Generating SSH key"
      mkdir -p "$HOME/.ssh"
      if ! ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""; then
        log_error "SSH key generation failed"
        return 1
      fi
      ssh-add --apple-use-keychain "$key_path" 2>/dev/null || ssh-add "$key_path"
    fi
  else
    log_info "SSH key already exists at $key_path, skipping generation"
  fi

  if [ -f "$key_path.pub" ]; then
    log_info "Public key:"
    cat "$key_path.pub"
    pbcopy < "$key_path.pub" 2>/dev/null || true
    log_info "Public key copied to clipboard (if pbcopy is available)"
  fi

  if ! gh auth status >/dev/null 2>&1; then
    if is_dry_run; then
      dry_run_report "authenticate via a GitHub PAT, then check/register the SSH key with GitHub"
      return 0
    fi
    log_info "No token found — create a classic token at https://github.com/settings/tokens with the \"repo\", \"read:org\", \"gist\", and \"admin:public_key\" scopes"
    local token
    token="$(ui_input_secret "GitHub Personal Access Token")"
    if [ -z "$token" ]; then
      log_error "No token provided"
      return 1
    fi
    if ! printf '%s' "$token" | gh auth login --with-token; then
      log_error "gh auth login failed"
      return 1
    fi
  else
    log_info "gh already authenticated, skipping"
  fi

  if [ -f "$key_path.pub" ]; then
    local key_blob registered_keys
    key_blob="$(awk '{print $2}' "$key_path.pub")"
    registered_keys="$(gh api user/keys --jq '.[].key' 2>/dev/null || true)"
    if [ -n "$key_blob" ] && printf '%s' "$registered_keys" | grep -qF "$key_blob"; then
      log_info "SSH key already registered with GitHub, skipping"
    elif is_dry_run; then
      dry_run_report "upload the SSH key to GitHub via gh ssh-key add"
    else
      if ! gh ssh-key add "$key_path.pub" --title "mac-up ($(scutil --get ComputerName 2>/dev/null || hostname))"; then
        log_warn "Failed to auto-register SSH key with GitHub — add it manually at https://github.com/settings/keys using the public key printed above"
      fi
    fi
  fi

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/github.bats`
Expected: PASS (13 tests: 9 existing + 4 new).

- [ ] **Step 5: Run the full suite**

Run: `bats tests/`
Expected: PASS (92 tests: 88 + 4).

- [ ] **Step 6: Commit**

```bash
git add lib/github.sh tests/github.bats
git commit -m "feat: add dry-run guards to github module"
```

---

### Task 6: End-to-end dry-run integration test

**Files:**
- Test: `tests/mac_up.bats`

**Interfaces:**
- Consumes: everything from [[Task 1]] through [[Task 5]] — this task
  adds no production code, only a cross-module regression test.

- [ ] **Step 1: Write the test**

Append to `tests/mac_up.bats` (after the last existing test, `mac-up
--dry-run prints a startup banner and a summary note`):

```bash
@test "mac-up --dry-run --all reports intended actions across every module without calling any mutating stub" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run "$MAC_UP_BIN" --dry-run --all

  [ "$status" -eq 0 ]
  [[ "$output" == *"Dry run: no changes will be made"* ]]
  [[ "$output" == *"[dry-run] would run: brew bundle"* ]]
  [[ "$output" == *"(dry run — nothing was actually changed)"* ]]
  ! grep -q "^brew " "$MAC_UP_CALL_LOG"
  ! grep -q "ssh-keygen" "$MAC_UP_CALL_LOG"
  ! grep -q "defaults write" "$MAC_UP_CALL_LOG"
  ! grep -q "killall" "$MAC_UP_CALL_LOG"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats tests/mac_up.bats`
Expected: FAIL if any task 1-5 guard was missed or misapplied — this
test is the cross-module safety net. If Tasks 1-5 were all implemented
correctly, this may already pass on the first run; if so, treat that as
confirmation rather than a problem (skip re-stating RED/GREEN — just
run it once and confirm PASS).

- [ ] **Step 3: Run tests to verify it passes**

Run: `bats tests/mac_up.bats`
Expected: PASS (10 tests: 9 existing + 1 new).

- [ ] **Step 4: Run the full suite**

Run: `bats tests/`
Expected: PASS (93 tests: 92 + 1).

- [ ] **Step 5: Commit**

```bash
git add tests/mac_up.bats
git commit -m "test: add end-to-end dry-run integration test"
```

---

## Self-Review Notes

- **Spec coverage:** `lib/common.sh` helpers + `bin/mac-up` wiring →
  Task 1. Per-module treatment (homebrew, shell, dotfiles,
  macos-defaults, github) → Tasks 2-5, each matching the spec's exact
  per-module description including the curl-piped-installer guard
  placement, the confirm/prompt-skipping behavior, the
  `_defaults_apply`/`killall`/`mkdir` wrap points, and the github
  auth/registration coupling. Testing approach (no new stubs, presence/
  absence assertions against `$MAC_UP_CALL_LOG`) → every task's tests,
  plus Task 6's cross-module check.
- **Placeholder scan:** no TODOs; every step has complete, runnable code
  and an expected result.
- **Type/name consistency:** `is_dry_run`, `dry_run_report`,
  `MAC_UP_DRY_RUN` are used identically across every task and test that
  references them. Dry-run report message wording matches between each
  module's implementation and its corresponding test assertions exactly.
