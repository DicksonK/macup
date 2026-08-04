# Git Identity & GitHub Auth Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `macup` a per-machine git identity (`~/.gitconfig.local`,
never symlinked/tracked) and redesign `github.sh`'s auth flow to use a
GitHub Personal Access Token instead of a browser-based `gh auth login` +
manual key paste, reusing the identity email and auto-uploading the SSH
key via `gh ssh-key add`.

**Architecture:** `run_dotfiles()` gains a post-link step that manages
`~/.gitconfig.local` (only when using the bundled dotfiles, never for an
external `DOTFILES_REPO`). `run_github()` is restructured to read that
file for its SSH-key email default, authenticate via `gh auth login
--with-token` (falling back to a masked prompt for the token), and
auto-register the key with `gh ssh-key add`, checked for idempotency via
`gh api user/keys`. A new `ui_input_secret()` helper in `lib/menu.sh`
provides masked (`gum input --password`) prompting for the token.

**Tech Stack:** bash, `gum`, `gh` CLI, bats-core (unchanged from the base
project).

## Global Constraints

- No change to the "flat symlink, no templating" dotfiles philosophy for
  any file other than gitconfig's identity split.
- The git identity step only applies when `${DOTFILES_REPO:-}` is empty
  (bundled dotfiles) — an external `DOTFILES_REPO` is assumed to manage
  its own git identity, out of scope.
- `~/.gitconfig.local` is a plain file: never a symlink, never tracked by
  any repo (bundled or external).
- No support for GitHub Enterprise or non-github.com hosts.
- `macup` never persists the PAT itself anywhere in its own files — `gh
  auth login --with-token` hands it to gh's own secure credential
  storage. The token is never logged and never passed as a CLI argument
  (only via stdin).
- Auth failure in `run_github()` is the only hard failure (`return 1`);
  SSH key upload failure is non-fatal (`log_warn`, continue, `return 0`
  if nothing else failed).
- Every module remains idempotent, returns 0/1, and never calls `exit`.
- bats-core tests must never touch real system state — all new behavior
  is exercised against stub `git`/`gh`/`gum` executables.

---

## File Structure

```
macup/
├── dotfiles/gitconfig              # bundled content change (Task 2)
├── lib/
│   ├── menu.sh                     # + ui_input_secret() (Task 1)
│   ├── dotfiles.sh                 # + post-link identity step (Task 2)
│   └── github.sh                   # restructured run_github() (Task 3)
└── tests/
    ├── menu.bats                   # + 2 tests (Task 1)
    ├── dotfiles.bats                # + 3 tests (Task 2)
    ├── github.bats                  # modify 1, + 6 tests (Task 3)
    └── test_helper/stubs/
        ├── git                      # + config case (Task 2)
        └── gh                       # + api, ssh-key add cases (Task 3)
```

---

### Task 1: `ui_input_secret()` masked input helper

**Files:**
- Modify: `lib/menu.sh`
- Test: `tests/menu.bats`

**Interfaces:**
- Consumes: `gum` (via `PATH`, same as every other `ui_*` function) — no
  stub changes needed, the existing `gum` stub's generic `input` case
  already handles this.
- Produces: `ui_input_secret(prompt)` → prints the entered secret to
  stdout. Consumed by Task 3's `run_github()` to collect a GitHub
  Personal Access Token without ever echoing it to the terminal.

- [ ] **Step 1: Write the failing tests**

Append to `tests/menu.bats` (after the existing `ui_input returns
GUM_INPUT_RESULT when set` test, before `ui_spin runs the wrapped
command...`):

```bash
@test "ui_input_secret returns GUM_INPUT_RESULT when set" {
  export GUM_INPUT_RESULT="super-secret-token"
  run ui_input_secret "GitHub Personal Access Token"
  [ "$status" -eq 0 ]
  [ "$output" = "super-secret-token" ]
}

@test "ui_input_secret passes --password to gum input" {
  run ui_input_secret "GitHub Personal Access Token"
  [ "$status" -eq 0 ]
  grep -q -- "--password" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/menu.bats`
Expected: FAIL — `ui_input_secret: command not found`.

- [ ] **Step 3: Implement `ui_input_secret` in `lib/menu.sh`**

Append to `lib/menu.sh` (after `ui_input`, before `ui_spin`):

```bash
ui_input_secret() {
  local prompt="$1"
  gum input --placeholder "$prompt" --password
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/menu.bats`
Expected: PASS (9 tests: 7 existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add lib/menu.sh tests/menu.bats
git commit -m "feat: add ui_input_secret masked-input helper"
```

---

### Task 2: Git identity (`~/.gitconfig.local`)

**Files:**
- Modify: `tests/test_helper/stubs/git`
- Modify: `dotfiles/gitconfig`
- Modify: `lib/dotfiles.sh`
- Test: `tests/dotfiles.bats`

**Interfaces:**
- Consumes: `log_info` ([[Task 1]] — actually from the base project's
  `lib/common.sh`), `ui_input` (base project's `lib/menu.sh`), `$ROOT_DIR`,
  `DOTFILES_REPO` (base project's `load_config`) — all pre-existing.
- Produces: `~/.gitconfig.local` (plain file, `user.name`/`user.email`
  keys, written via `git config -f`). Consumed by [[Task 3]]'s
  `run_github()` as its SSH-key email default.

- [ ] **Step 1: Extend the `git` test stub with a `config` case**

Read the current file first (`tests/test_helper/stubs/git`) — it has a
`clone)` case and a `*)` catch-all. Insert a new `config)` case **before**
the `*)` catch-all:

```bash
#!/usr/bin/env bash
echo "git $*" >> "${MACUP_CALL_LOG:-/dev/null}"
case "$1" in
  clone)
    target="${*: -1}"
    mkdir -p "$target/.git"
    exit 0
    ;;
  config)
    shift
    file=""
    if [ "$1" = "-f" ]; then
      shift
      file="$1"
      shift
    fi
    if [ "$1" = "--get" ]; then
      key="$2"
      line="$(grep -F "^$key=" "$file" 2>/dev/null | head -1 || true)"
      if [ -z "$line" ]; then
        exit 1
      fi
      echo "${line#*=}"
      exit 0
    else
      key="$1"
      value="$2"
      touch "$file"
      grep -vF "^$key=" "$file" > "$file.tmp" 2>/dev/null || true
      mv "$file.tmp" "$file" 2>/dev/null || true
      echo "$key=$value" >> "$file"
      exit 0
    fi
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 2: Update the bundled `dotfiles/gitconfig`**

Replace the entire content of `dotfiles/gitconfig` with:

```ini
[include]
	path = ~/.gitconfig.local
[init]
	defaultBranch = main
[pull]
	rebase = false
[core]
	editor = vim
```

- [ ] **Step 3: Write the failing tests**

Append to `tests/dotfiles.bats` (after the last existing test, `run_dotfiles
warns when zero dotfiles were linked from a non-empty source_dir`):

```bash
@test "run_dotfiles prompts for and writes git identity when using bundled dotfiles" {
  export GUM_INPUT_RESULT="Jane Doe"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.name)" = "Jane Doe" ]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.email)" = "Jane Doe" ]
  [[ "$output" == *"Wrote git identity to $HOME/.gitconfig.local"* ]]
}

@test "run_dotfiles skips the git identity prompt when already configured" {
  git config -f "$HOME/.gitconfig.local" user.name "Existing Name"
  git config -f "$HOME/.gitconfig.local" user.email "existing@example.com"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *"Git identity already configured in $HOME/.gitconfig.local, skipping"* ]]
  [ "$(git config -f "$HOME/.gitconfig.local" --get user.name)" = "Existing Name" ]
}

@test "run_dotfiles does not touch git identity when DOTFILES_REPO is set" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.gitconfig.local" ]
}
```

- [ ] **Step 4: Run tests to verify the new ones fail**

Run: `bats tests/dotfiles.bats`
Expected: FAIL — the two bundled-dotfiles tests fail because
`~/.gitconfig.local` is never created (`git config -f ... --get` on a
nonexistent file returns nothing / the stub's `--get` branch exits 1, so
`$(...)` yields an empty string, not `"Jane Doe"`/`"Existing Name"`).

- [ ] **Step 5: Implement the identity step in `lib/dotfiles.sh`**

Insert this block into `run_dotfiles()`, after the `if [ "$linked_count"
-eq 0 ]; then ... fi` block and before the final `return 0`:

```bash
  if [ -z "${DOTFILES_REPO:-}" ]; then
    local identity_file="$HOME/.gitconfig.local"
    if git config -f "$identity_file" --get user.name >/dev/null 2>&1 \
      && git config -f "$identity_file" --get user.email >/dev/null 2>&1; then
      log_info "Git identity already configured in $identity_file, skipping"
    else
      local git_name git_email
      git_name="$(ui_input "Git user.name" "")"
      git_email="$(ui_input "Git user.email" "")"
      git config -f "$identity_file" user.name "$git_name"
      git config -f "$identity_file" user.email "$git_email"
      log_info "Wrote git identity to $identity_file"
    fi
  fi

  return 0
```

(This replaces the existing bare `return 0` at the end of the function —
the new block ends with its own `return 0`.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/dotfiles.bats`
Expected: PASS (12 tests: 9 existing + 3 new).

Note: every existing bundled-dotfiles test (the ones that don't set
`DOTFILES_REPO`) will now also invoke this identity step. Since none of
them set `GUM_INPUT_RESULT`, `ui_input` falls back to its `""` default for
both prompts, so `~/.gitconfig.local` ends up with empty
`user.name`/`user.email` values in those tests — harmless, since none of
their assertions touch that file.

- [ ] **Step 7: Commit**

```bash
git add tests/test_helper/stubs/git dotfiles/gitconfig lib/dotfiles.sh tests/dotfiles.bats
git commit -m "feat: add per-machine git identity via ~/.gitconfig.local"
```

---

### Task 3: GitHub auth redesign (token-based, auto-upload)

**Files:**
- Modify: `tests/test_helper/stubs/gh`
- Modify: `lib/github.sh`
- Test: `tests/github.bats`

**Interfaces:**
- Consumes: `ui_input_secret` ([[Task 1]]); `~/.gitconfig.local`'s
  `user.email`, read via `git config -f ... --get` ([[Task 2]]);
  `log_info`/`log_warn`/`log_error` (base project's `lib/common.sh`).
- Produces: nothing consumed by other tasks (terminal task).

- [ ] **Step 1: Extend the `gh` test stub**

Read the current file first (`tests/test_helper/stubs/gh`). The existing
`auth login)` branch already matches `gh auth login --with-token` (it only
checks `$1`/`$2`), so no change is needed there beyond draining stdin.
Replace the whole file with:

```bash
#!/usr/bin/env bash
echo "gh $*" >> "${MACUP_CALL_LOG:-/dev/null}"
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit "${GH_AUTH_STATUS_EXIT:-1}"
fi
if [ "$1" = "auth" ] && [ "$2" = "login" ]; then
  cat >/dev/null
  exit "${GH_AUTH_LOGIN_EXIT:-0}"
fi
if [ "$1" = "api" ] && [ "$2" = "user/keys" ]; then
  printf '%s\n' "${GH_REGISTERED_KEYS:-}"
  exit 0
fi
if [ "$1" = "ssh-key" ] && [ "$2" = "add" ]; then
  exit "${GH_SSH_KEY_ADD_EXIT:-0}"
fi
exit 0
```

- [ ] **Step 2: Update the existing test that relied on the old browser-based login**

In `tests/github.bats`, the test `run_github logs in with gh when not
already authenticated` currently has no token set up. Under the new
token-based flow, `run_github` will now prompt for a token via
`ui_input_secret` before calling `gh auth login --with-token`; without a
token, it would fail with `status -eq 1` instead of the `0` this test
expects. Update it to:

```bash
@test "run_github logs in with gh when not already authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1
  export GH_AUTH_LOGIN_EXIT=0
  export GUM_INPUT_RESULT="fake-personal-access-token"

  run run_github

  [ "$status" -eq 0 ]
  grep -q "auth login --with-token" "$MACUP_CALL_LOG"
  [[ "$output" == *"github.com/settings/tokens"* ]]
  [[ "$output" == *"admin:public_key"* ]]
}
```

- [ ] **Step 3: Write the remaining failing tests**

Append to `tests/github.bats` (after the last existing test):

```bash
@test "run_github fails with a clear error when no token is provided" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1

  run run_github

  [ "$status" -eq 1 ]
  [[ "$output" == *"No token provided"* ]]
}

@test "run_github uses the git identity email from ~/.gitconfig.local as the SSH key default" {
  git config -f "$HOME/.gitconfig.local" user.email "identity@example.com"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  grep -q "ssh-keygen.*-C identity@example.com" "$MACUP_CALL_LOG"
}

@test "run_github auto-uploads the SSH key when not yet registered with GitHub" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS=""

  run run_github

  [ "$status" -eq 0 ]
  grep -q "ssh-key add" "$MACUP_CALL_LOG"
}

@test "run_github skips upload when the SSH key is already registered with GitHub" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS="AAAAtest"

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"already registered with GitHub, skipping"* ]]
  ! grep -q "ssh-key add" "$MACUP_CALL_LOG"
}

@test "run_github warns but does not fail when SSH key upload fails" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "ssh-ed25519 AAAAtest existing@example.com" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0
  export GH_REGISTERED_KEYS=""
  export GH_SSH_KEY_ADD_EXIT=1

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to auto-register SSH key"* ]]
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bats tests/github.bats`
Expected: FAIL — `run_github` doesn't yet prompt for a token, doesn't yet
read `~/.gitconfig.local`, and doesn't yet call `gh api`/`gh ssh-key add`.

- [ ] **Step 5: Implement the restructured `run_github()` in `lib/github.sh`**

Replace the entire content of `lib/github.sh` with:

```bash
#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    local email default_email=""
    if git config -f "$HOME/.gitconfig.local" --get user.email >/dev/null 2>&1; then
      default_email="$(git config -f "$HOME/.gitconfig.local" --get user.email)"
    fi
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
    log_info "No token found — create one at https://github.com/settings/tokens with the \"admin:public_key\" scope"
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
    local key_blob
    key_blob="$(awk '{print $2}' "$key_path.pub")"
    if gh api user/keys --jq '.[].key' 2>/dev/null | grep -qF "$key_blob"; then
      log_info "SSH key already registered with GitHub, skipping"
    else
      if ! gh ssh-key add "$key_path.pub" --title "macup ($(scutil --get ComputerName 2>/dev/null || hostname))"; then
        log_warn "Failed to auto-register SSH key with GitHub — add it manually at https://github.com/settings/keys using the public key printed above"
      fi
    fi
  fi

  return 0
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats tests/github.bats`
Expected: PASS (9 tests: 4 existing, one of which was updated in Step 2,
plus 5 new).

Note: the existing `ssh-keygen` test stub writes the single-word content
`stub-public-key` as the `.pub` file (no space-separated fields), so
`awk '{print $2}'` yields an empty `key_blob` for tests that let the stub
generate a fresh key rather than pre-populating a realistic multi-field
`.pub` file. Combined with the `gh` stub's `api user/keys` case (which
prints `${GH_REGISTERED_KEYS:-}` followed by a newline even when unset),
an empty `key_blob` will spuriously "match" via `grep -qF ""`, treating
the key as already registered and skipping upload. This only affects
tests using the ssh-keygen-generated stub key (i.e. `run_github generates
an SSH key when none exists` and `run_github skips key generation when a
key already exists`) — neither asserts anything about the upload step, so
this is a disclosed stub-fidelity limitation, not a functional defect:
real `ssh-keygen` always produces a proper `ssh-ed25519 AAAA... comment`
line.

- [ ] **Step 7: Run the full test suite**

Run: `bats tests/`
Expected: PASS (all files, all tests — 58 tests total: 48 from the base
project + 2 (Task 1) + 3 (Task 2) + 5 net new in Task 3, with 1 existing
test modified in place).

- [ ] **Step 8: Commit**

```bash
git add tests/test_helper/stubs/gh lib/github.sh tests/github.bats
git commit -m "feat: redesign github auth to use a PAT and auto-upload the SSH key"
```

---

## Self-Review Notes

- **Spec coverage:** §1 Git Identity → Task 2 (bundled file change,
  `run_dotfiles()` step, idempotency check, `DOTFILES_REPO` gating). §2
  GitHub Auth Redesign → Task 3 (masked-input helper is Task 1; token
  flow, email-default reuse, auto-upload with idempotency, non-fatal
  upload-failure handling all in Task 3). §3 Testing → stub extensions in
  Tasks 2 and 3, all six named test scenarios from the spec covered
  (fresh write, idempotent skip, `DOTFILES_REPO` skip for identity;
  email-default, token auth, auto-upload, skip-when-registered, non-fatal
  warning for github.sh) plus the masked-input test from Task 1.
- **Placeholder scan:** no TODOs; every step has complete, runnable code
  and an expected result.
- **Type/name consistency:** `ui_input_secret`, `git config -f
  "$HOME/.gitconfig.local"`, `GH_REGISTERED_KEYS`,
  `GH_SSH_KEY_ADD_EXIT` are used identically across every task and test
  that references them.
