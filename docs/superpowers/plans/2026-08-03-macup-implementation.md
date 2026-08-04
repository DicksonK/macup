# macup CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `macup` bash CLI (source repo) described in
`docs/superpowers/specs/2026-08-03-macup-design.md`: a gum-driven,
idempotent Mac bootstrap/sync tool with five modules (homebrew, shell,
dotfiles, macos-defaults, github), bats-core tests, and a Homebrew
formula template for the companion tap repo.

**Architecture:** A single entrypoint (`bin/macup`) resolves its real
install location (so it works both as a Homebrew Cellar symlink and as a
local checkout), sources `lib/common.sh` and `lib/menu.sh` for shared
logging/config/TUI helpers, then sources and dispatches to one
`lib/<module>.sh` per module. Each module exposes a single idempotent
`run_<module>()` function that checks live system state before mutating
anything. bats-core tests exercise every module's logic against stub
executables (`brew`, `gh`, `gum`, `git`, `ssh-keygen`, `ssh-add`,
`pbcopy`, `defaults`, `killall`) on `PATH`, with `HOME` redirected to a
temp directory — no real system mutation happens in tests.

**Tech Stack:** bash (`set -euo pipefail`), `gum` (Charmbracelet) for TUI,
Homebrew (`brew bundle`), bats-core for tests.

## Global Constraints

- Distributed via two repos: source `github.com/dicksonk/macup` (this
  plan) and tap `github.com/dicksonk/homebrew-macup` (formula only,
  Task 11).
- `bin/macup` runs with `set -euo pipefail`; each module function traps
  its own errors and returns non-zero rather than letting the whole
  process die mid-module.
- Network-dependent steps (Homebrew install, OMZ install, git
  clone/pull, `gh auth login`) print a clear error and continue to the
  next module rather than retrying silently.
- All destructive-ish actions on existing files (dotfile symlinking over
  a non-symlink target) require explicit `ui_confirm` before proceeding.
- Every module exposes exactly one function, `run_<module>()`, that is
  idempotent: it checks live system state first and only mutates what's
  not already correct.
- Module CLI names `homebrew`, `shell`, `dotfiles`, `macos-defaults`,
  `github` map to `lib/<name_with_underscores>.sh` /
  `run_<name_with_underscores>()`; only `macos-defaults` differs
  (`lib/macos_defaults.sh`, `run_macos_defaults()`).
- bats-core tests live in `tests/`, one file per module plus
  `common.bats`. System-mutating behavior (does `defaults write` really
  change the setting, does OMZ really install) is verified manually on a
  real/VM Mac per the README — never assert it in bats.
- Not a templating dotfiles manager, no per-host profiles, no
  declarative drift-detection tool beyond each module's idempotency
  check, macOS only.

---

## File Structure

```
macup/
├── bin/macup                     # entrypoint (Task 9)
├── lib/
│   ├── common.sh                  # logging, resolve_script_dir, load_config (Tasks 1, 3)
│   ├── menu.sh                    # gum wrappers (Task 2)
│   ├── homebrew.sh                # Task 4
│   ├── shell.sh                   # Task 5
│   ├── dotfiles.sh                # Task 6
│   ├── macos_defaults.sh          # Task 7
│   └── github.sh                  # Task 8
├── Brewfile                       # Task 4
├── dotfiles/{zshrc,p10k.zsh,gitconfig}  # Task 6
├── macup.conf.example            # Task 3
├── packaging/homebrew/macup.rb   # tap formula template (Task 11)
├── tests/
│   ├── test_helper/
│   │   ├── load.bash              # setup/teardown, PATH + HOME sandbox (Task 1)
│   │   └── stubs/{brew,gh,gum,git,ssh-keygen,ssh-add,pbcopy,defaults,killall}  # Task 1
│   ├── common.bats                # Tasks 1, 3
│   ├── menu.bats                   # Task 2
│   ├── homebrew.bats               # Task 4
│   ├── shell.bats                  # Task 5
│   ├── dotfiles.bats               # Task 6
│   ├── macos_defaults.bats         # Task 7
│   ├── github.bats                 # Task 8
│   └── macup.bats                 # Task 9
└── README.md                       # Task 10
```

---

### Task 1: Scaffolding, test harness, `lib/common.sh` (logging + path resolution)

**Files:**
- Create: `tests/test_helper/load.bash`
- Create: `tests/test_helper/stubs/brew`
- Create: `tests/test_helper/stubs/gh`
- Create: `tests/test_helper/stubs/gum`
- Create: `tests/test_helper/stubs/git`
- Create: `tests/test_helper/stubs/ssh-keygen`
- Create: `tests/test_helper/stubs/ssh-add`
- Create: `tests/test_helper/stubs/pbcopy`
- Create: `tests/test_helper/stubs/defaults`
- Create: `tests/test_helper/stubs/killall`
- Create: `lib/common.sh`
- Test: `tests/common.bats`

**Interfaces:**
- Produces: `resolve_script_dir(source_path)` → prints the real
  (symlink-resolved) directory containing `source_path` to stdout.
- Produces: `log_info(msg)`, `log_warn(msg)`, `log_error(msg)` → print a
  styled line to stdout (`log_info`) or stderr (`log_warn`, `log_error`).
- Produces (test infra): `macup_test_setup` — sets `ROOT_DIR` to the
  repo root, `HOME` to a fresh temp dir, prepends
  `tests/test_helper/stubs` to `PATH`, and sets `MACUP_CALL_LOG` to a
  fresh temp file every stub appends its invocation to. `macup_test_teardown`
  removes both temp paths. Every later `.bats` file's `setup()`/`teardown()`
  calls these.

- [ ] **Step 1: Install bats-core if missing**

Run: `brew install bats-core` (only if `bats --version` fails).

- [ ] **Step 2: Create the test-helper stub executables**

`tests/test_helper/stubs/brew`:
```bash
#!/usr/bin/env bash
echo "brew $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit "${BREW_EXIT:-0}"
```

`tests/test_helper/stubs/gh`:
```bash
#!/usr/bin/env bash
echo "gh $*" >> "${MACUP_CALL_LOG:-/dev/null}"
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  exit "${GH_AUTH_STATUS_EXIT:-1}"
fi
if [ "$1" = "auth" ] && [ "$2" = "login" ]; then
  exit "${GH_AUTH_LOGIN_EXIT:-0}"
fi
exit 0
```

`tests/test_helper/stubs/gum`:
```bash
#!/usr/bin/env bash
echo "gum $*" >> "${MACUP_CALL_LOG:-/dev/null}"
case "$1" in
  choose)
    printf '%s\n' "${GUM_CHOOSE_RESULT:-}"
    ;;
  confirm)
    exit "${GUM_CONFIRM_EXIT:-0}"
    ;;
  input)
    if [ -n "${GUM_INPUT_RESULT:-}" ]; then
      printf '%s\n' "$GUM_INPUT_RESULT"
    else
      for ((i = 2; i <= $#; i++)); do
        if [ "${!i}" = "--value" ]; then
          j=$((i + 1))
          printf '%s\n' "${!j}"
          exit 0
        fi
      done
      printf '\n'
    fi
    ;;
  spin)
    shift
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
    shift
    "$@"
    ;;
  style)
    shift
    echo "$*"
    ;;
esac
```

`tests/test_helper/stubs/git`:
```bash
#!/usr/bin/env bash
echo "git $*" >> "${MACUP_CALL_LOG:-/dev/null}"
case "$1" in
  clone)
    target="${*: -1}"
    mkdir -p "$target/.git"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
```

`tests/test_helper/stubs/ssh-keygen`:
```bash
#!/usr/bin/env bash
echo "ssh-keygen $*" >> "${MACUP_CALL_LOG:-/dev/null}"
prev=""
keypath=""
for arg in "$@"; do
  if [ "$prev" = "-f" ]; then keypath="$arg"; fi
  prev="$arg"
done
if [ -n "$keypath" ]; then
  echo "stub-private-key" > "$keypath"
  echo "stub-public-key" > "$keypath.pub"
fi
exit 0
```

`tests/test_helper/stubs/ssh-add`:
```bash
#!/usr/bin/env bash
echo "ssh-add $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit 0
```

`tests/test_helper/stubs/pbcopy`:
```bash
#!/usr/bin/env bash
echo "pbcopy" >> "${MACUP_CALL_LOG:-/dev/null}"
cat > /dev/null
exit 0
```

`tests/test_helper/stubs/defaults`:
```bash
#!/usr/bin/env bash
STORE="${DEFAULTS_STORE:-$HOME/.defaults-stub-store}"
touch "$STORE"
case "$1" in
  read)
    domain="$2"; key="$3"
    line="$(grep -F "$domain|$key|" "$STORE" || true)"
    if [ -z "$line" ]; then exit 1; fi
    echo "${line##*|}"
    exit 0
    ;;
  write)
    domain="$2"; key="$3"; value="$5"
    grep -vF "$domain|$key|" "$STORE" > "$STORE.tmp" 2>/dev/null || true
    mv "$STORE.tmp" "$STORE"
    echo "$domain|$key|$value" >> "$STORE"
    echo "defaults write $domain $key $value" >> "${MACUP_CALL_LOG:-/dev/null}"
    exit 0
    ;;
esac
```

`tests/test_helper/stubs/killall`:
```bash
#!/usr/bin/env bash
echo "killall $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit 0
```

Make them all executable:
```bash
chmod +x tests/test_helper/stubs/*
```

- [ ] **Step 3: Write `tests/test_helper/load.bash`**

```bash
#!/usr/bin/env bash

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

macup_test_setup() {
  ROOT_DIR="$(repo_root)"
  export ROOT_DIR
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export PATH="$ROOT_DIR/tests/test_helper/stubs:$PATH"
  MACUP_CALL_LOG="$(mktemp)"
  export MACUP_CALL_LOG
}

macup_test_teardown() {
  rm -rf "$TEST_HOME"
  rm -f "$MACUP_CALL_LOG"
}
```

- [ ] **Step 4: Write the failing test for `resolve_script_dir`**

`tests/common.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
}

teardown() {
  macup_test_teardown
}

@test "resolve_script_dir follows a chain of symlinks to the real directory" {
  source "$ROOT_DIR/lib/common.sh"

  local real_dir="$TEST_HOME/real"
  mkdir -p "$real_dir"
  touch "$real_dir/script.sh"
  ln -s "$real_dir/script.sh" "$TEST_HOME/link1.sh"
  ln -s "$TEST_HOME/link1.sh" "$TEST_HOME/link2.sh"

  run resolve_script_dir "$TEST_HOME/link2.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "$real_dir" ]
}

@test "resolve_script_dir on a plain (non-symlink) path returns its directory" {
  source "$ROOT_DIR/lib/common.sh"

  mkdir -p "$TEST_HOME/plain"
  touch "$TEST_HOME/plain/script.sh"

  run resolve_script_dir "$TEST_HOME/plain/script.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_HOME/plain" ]
}

@test "log_info prints the message to stdout" {
  source "$ROOT_DIR/lib/common.sh"

  run log_info "hello there"

  [ "$status" -eq 0 ]
  [[ "$output" == *"hello there"* ]]
}

@test "log_error prints the message to stderr" {
  source "$ROOT_DIR/lib/common.sh"

  log_error "bad thing happened" 2>"$TEST_HOME/stderr.log"

  grep -q "bad thing happened" "$TEST_HOME/stderr.log"
}
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `bats tests/common.bats`
Expected: FAIL — `lib/common.sh: No such file or directory`.

- [ ] **Step 6: Implement `lib/common.sh`**

```bash
#!/usr/bin/env bash

resolve_script_dir() {
  local source="$1"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

log_info() {
  printf '\033[1;34m==>\033[0m %s\n' "$1"
}

log_warn() {
  printf '\033[1;33m==> warning:\033[0m %s\n' "$1" >&2
}

log_error() {
  printf '\033[1;31m==> error:\033[0m %s\n' "$1" >&2
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bats tests/common.bats`
Expected: PASS (4 tests).

- [ ] **Step 8: Commit**

```bash
git add tests/test_helper lib/common.sh tests/common.bats
git commit -m "feat: add test harness, logging, and path resolution"
```

---

### Task 2: `lib/menu.sh` — gum TUI wrappers

**Files:**
- Create: `lib/menu.sh`
- Test: `tests/menu.bats`

**Interfaces:**
- Consumes: none (calls `gum` directly).
- Produces: `ui_choose_modules()` → prints selected module names, one per
  line. `ui_confirm(prompt)` → returns 0 (yes) or 1 (no). `ui_input(prompt,
  [default])` → prints the entered/default text. `ui_spin(title, --,
  cmd...)` → runs `cmd...`, forwarding its exit status. `ui_log_step(msg)`
  → prints a styled status line.

- [ ] **Step 1: Write the failing tests**

`tests/menu.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/menu.sh"
}

teardown() {
  macup_test_teardown
}

@test "ui_choose_modules strips descriptions and returns module names" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages
dotfiles: Symlink dotfiles into \$HOME"

  run ui_choose_modules

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "homebrew" ]
  [ "${lines[1]}" = "dotfiles" ]
}

@test "ui_confirm returns success when gum confirm succeeds" {
  export GUM_CONFIRM_EXIT=0
  run ui_confirm "proceed?"
  [ "$status" -eq 0 ]
}

@test "ui_confirm returns failure when gum confirm fails" {
  export GUM_CONFIRM_EXIT=1
  run ui_confirm "proceed?"
  [ "$status" -eq 1 ]
}

@test "ui_input returns the provided default when no override is set" {
  run ui_input "Email" "me@example.com"
  [ "$status" -eq 0 ]
  [ "$output" = "me@example.com" ]
}

@test "ui_input returns GUM_INPUT_RESULT when set" {
  export GUM_INPUT_RESULT="typed@example.com"
  run ui_input "Email" "me@example.com"
  [ "$output" = "typed@example.com" ]
}

@test "ui_spin runs the wrapped command and forwards its exit status" {
  run ui_spin "Doing thing" -- bash -c 'exit 3'
  [ "$status" -eq 3 ]
}

@test "ui_log_step prints the message" {
  run ui_log_step "Running homebrew"
  [[ "$output" == *"Running homebrew"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/menu.bats`
Expected: FAIL — `lib/menu.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/menu.sh`**

```bash
#!/usr/bin/env bash

ui_choose_modules() {
  gum choose --no-limit \
    "homebrew: Install Homebrew packages from the Brewfile" \
    "shell: Install Oh My Zsh + Powerlevel10k" \
    "dotfiles: Symlink dotfiles into \$HOME" \
    "macos-defaults: Apply curated macOS system defaults" \
    "github: Set up a GitHub SSH key and gh CLI auth" \
    | sed -E 's/:.*$//'
}

ui_confirm() {
  gum confirm "$1"
}

ui_input() {
  local prompt="$1"
  local default="${2:-}"
  gum input --placeholder "$prompt" --value "$default"
}

ui_spin() {
  local title="$1"
  shift
  if [ "$1" = "--" ]; then
    shift
  fi
  gum spin --title "$title" -- "$@"
}

ui_log_step() {
  gum style --foreground 212 "==> $1"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/menu.bats`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/menu.sh tests/menu.bats
git commit -m "feat: add gum TUI wrapper functions"
```

---

### Task 3: Configuration loading (`load_config`, `macup.conf.example`)

**Files:**
- Modify: `lib/common.sh`
- Create: `macup.conf.example`
- Modify: `tests/common.bats`

**Interfaces:**
- Consumes: `ui_confirm(prompt)` from [[Task 2]] `lib/menu.sh`; `$ROOT_DIR`
  (set by the caller — tests via `macup_test_setup`, production by
  `bin/macup` in [[Task 9]]).
- Produces: `load_config()` — sets (and exports) `DOTFILES_REPO` and
  `EXTRA_BREWFILE` (defaulting to `""`) by sourcing
  `~/.config/macup/config` if present; if absent, offers via
  `ui_confirm` to create it from `$ROOT_DIR/macup.conf.example`.

- [ ] **Step 1: Write `macup.conf.example`**

```sh
# macup configuration
# Uncomment and set values to customize a run. Leave blank/commented to
# use the bundled defaults.

# Git URL of an external dotfiles repo to use instead of the bundled
# dotfiles/ directory (cloned into ~/.cache/macup/dotfiles-repo).
#DOTFILES_REPO=

# Path to an additional Brewfile to run after the bundled Brewfile.
#EXTRA_BREWFILE=
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/common.bats` (add `source "$ROOT_DIR/lib/menu.sh"` to
`setup()` since `load_config` calls `ui_confirm`):

```bash
setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
}
```

```bash
@test "load_config sources an existing config file" {
  mkdir -p "$TEST_HOME/.config/macup"
  cat > "$TEST_HOME/.config/macup/config" <<'EOF'
DOTFILES_REPO=git@github.com:example/dotfiles.git
EXTRA_BREWFILE=/tmp/extra.Brewfile
EOF

  load_config

  [ "$DOTFILES_REPO" = "git@github.com:example/dotfiles.git" ]
  [ "$EXTRA_BREWFILE" = "/tmp/extra.Brewfile" ]
}

@test "load_config defaults to empty values when declined and no file exists" {
  export GUM_CONFIRM_EXIT=1

  load_config

  [ "$DOTFILES_REPO" = "" ]
  [ "$EXTRA_BREWFILE" = "" ]
  [ ! -f "$TEST_HOME/.config/macup/config" ]
}

@test "load_config creates the config file from the example when confirmed" {
  export GUM_CONFIRM_EXIT=0

  load_config

  [ -f "$TEST_HOME/.config/macup/config" ]
  diff "$TEST_HOME/.config/macup/config" "$ROOT_DIR/macup.conf.example"
}
```

- [ ] **Step 3: Run tests to verify the new ones fail**

Run: `bats tests/common.bats`
Expected: FAIL — `load_config: command not found`.

- [ ] **Step 4: Implement `load_config` in `lib/common.sh`**

Append to `lib/common.sh`:
```bash

load_config() {
  local config_dir="$HOME/.config/macup"
  local config_file="$config_dir/config"
  local example_file="$ROOT_DIR/macup.conf.example"

  DOTFILES_REPO="${DOTFILES_REPO:-}"
  EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"

  if [ ! -f "$config_file" ]; then
    if ui_confirm "No config found. Create default config at $config_file?"; then
      mkdir -p "$config_dir"
      cp "$example_file" "$config_file"
    else
      return 0
    fi
  fi

  # shellcheck disable=SC1090
  source "$config_file"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/common.bats`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/common.sh macup.conf.example tests/common.bats
git commit -m "feat: add config file loading"
```

---

### Task 4: `lib/homebrew.sh` — `run_homebrew()`

**Files:**
- Create: `lib/homebrew.sh`
- Create: `Brewfile`
- Test: `tests/homebrew.bats`

**Interfaces:**
- Consumes: `log_info`/`log_warn`/`log_error` from [[Task 1]];
  `$ROOT_DIR`; `EXTRA_BREWFILE` from [[Task 3]] `load_config`.
- Produces: `run_homebrew()` → returns 0 on success, 1 on failure. Exposes
  two overridable path variables (defaulting to the real Homebrew binary
  locations) so tests never touch real system paths:
  `MACUP_BREW_PATH_APPLE_SILICON` (default `/opt/homebrew/bin/brew`),
  `MACUP_BREW_PATH_INTEL` (default `/usr/local/bin/brew`).

- [ ] **Step 1: Write `Brewfile`**

```ruby
tap "homebrew/bundle"

brew "git"
brew "gh"
brew "gum"
brew "bat"
brew "fzf"
brew "ripgrep"
brew "fd"
brew "jq"
brew "wget"
brew "tmux"
brew "neovim"

cask "iterm2"
cask "visual-studio-code"
cask "rectangle"
```

- [ ] **Step 2: Write the failing tests**

`tests/homebrew.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL

  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/homebrew.sh"
}

teardown() {
  macup_test_teardown
}

install_stub_brew() {
  cat > "$MACUP_BREW_PATH_APPLE_SILICON" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit "${BREW_EXIT:-0}"
EOF
  chmod +x "$MACUP_BREW_PATH_APPLE_SILICON"
}

@test "run_homebrew runs brew bundle with the default Brewfile when brew is already installed" {
  install_stub_brew

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew fails when brew bundle fails on the default Brewfile" {
  install_stub_brew
  export BREW_EXIT=1

  run run_homebrew

  [ "$status" -eq 1 ]
}

@test "run_homebrew also runs the extra Brewfile when EXTRA_BREWFILE is set and exists" {
  install_stub_brew
  echo "brew \"jq\"" > "$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "bundle --file=$TEST_HOME/extra.Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew warns and continues when EXTRA_BREWFILE is set but missing" {
  install_stub_brew
  export EXTRA_BREWFILE="$TEST_HOME/does-not-exist.Brewfile"

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA_BREWFILE set but not found"* ]]
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bats tests/homebrew.bats`
Expected: FAIL — `lib/homebrew.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/homebrew.sh`**

```bash
#!/usr/bin/env bash

: "${MACUP_BREW_PATH_APPLE_SILICON:=/opt/homebrew/bin/brew}"
: "${MACUP_BREW_PATH_INTEL:=/usr/local/bin/brew}"

run_homebrew() {
  local brew_bin=""
  if [ -x "$MACUP_BREW_PATH_APPLE_SILICON" ]; then
    brew_bin="$MACUP_BREW_PATH_APPLE_SILICON"
  elif [ -x "$MACUP_BREW_PATH_INTEL" ]; then
    brew_bin="$MACUP_BREW_PATH_INTEL"
  fi

  if [ -z "$brew_bin" ]; then
    log_info "Homebrew not found, installing"
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      log_error "Homebrew installation failed"
      return 1
    fi
    if [ -x "$MACUP_BREW_PATH_APPLE_SILICON" ]; then
      brew_bin="$MACUP_BREW_PATH_APPLE_SILICON"
    else
      brew_bin="$MACUP_BREW_PATH_INTEL"
    fi
  fi

  log_info "Running brew bundle with default Brewfile"
  if ! "$brew_bin" bundle --file="$ROOT_DIR/Brewfile"; then
    log_error "brew bundle failed for default Brewfile"
    return 1
  fi

  if [ -n "${EXTRA_BREWFILE:-}" ]; then
    if [ -f "$EXTRA_BREWFILE" ]; then
      log_info "Running brew bundle with extra Brewfile: $EXTRA_BREWFILE"
      if ! "$brew_bin" bundle --file="$EXTRA_BREWFILE"; then
        log_warn "brew bundle failed for extra Brewfile: $EXTRA_BREWFILE"
      fi
    else
      log_warn "EXTRA_BREWFILE set but not found: $EXTRA_BREWFILE"
    fi
  fi

  return 0
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/homebrew.bats`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/homebrew.sh Brewfile tests/homebrew.bats
git commit -m "feat: add homebrew module"
```

---

### Task 5: `lib/shell.sh` — `run_shell()`

**Files:**
- Create: `lib/shell.sh`
- Test: `tests/shell.bats`

**Interfaces:**
- Consumes: `log_info`/`log_error` from [[Task 1]]; the `git` stub from
  [[Task 1]] for the Powerlevel10k clone path.
- Produces: `run_shell()` → returns 0 on success, 1 on failure.

- [ ] **Step 1: Write the failing tests**

`tests/shell.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/shell.sh"
}

teardown() {
  macup_test_teardown
}

@test "run_shell skips both installs when oh-my-zsh and powerlevel10k already exist" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed"* ]]
  [[ "$output" == *"Powerlevel10k already installed"* ]]
  [ ! -f "$MACUP_CALL_LOG" ] || ! grep -q "git clone" "$MACUP_CALL_LOG"
}

@test "run_shell clones powerlevel10k when oh-my-zsh exists but the theme doesn't" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  grep -q "clone --depth=1" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/shell.bats`
Expected: FAIL — `lib/shell.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/shell.sh`**

```bash
#!/usr/bin/env bash

run_shell() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log_info "Installing Oh My Zsh"
    if ! CHSH=no RUNZSH=no /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
      log_error "Oh My Zsh installation failed"
      return 1
    fi
  else
    log_info "Oh My Zsh already installed, skipping"
  fi

  local p10k_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$p10k_dir" ]; then
    log_info "Cloning Powerlevel10k"
    if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"; then
      log_error "Powerlevel10k clone failed"
      return 1
    fi
  else
    log_info "Powerlevel10k already installed, skipping"
  fi

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/shell.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/shell.sh tests/shell.bats
git commit -m "feat: add shell module (Oh My Zsh + Powerlevel10k)"
```

---

### Task 6: `lib/dotfiles.sh` — `run_dotfiles()` + bundled dotfiles

**Files:**
- Create: `lib/dotfiles.sh`
- Create: `dotfiles/zshrc`
- Create: `dotfiles/p10k.zsh`
- Create: `dotfiles/gitconfig`
- Test: `tests/dotfiles.bats`

**Interfaces:**
- Consumes: `log_info`/`log_warn`/`log_error` from [[Task 1]];
  `ui_confirm` from [[Task 2]]; `$ROOT_DIR`; `DOTFILES_REPO` from
  [[Task 3]] `load_config`; the `git` stub from [[Task 1]].
- Produces: `run_dotfiles()` → returns 0 on success, 1 on failure.

- [ ] **Step 1: Write the bundled default dotfiles**

`dotfiles/zshrc`:
```sh
# macup default .zshrc
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
```

`dotfiles/p10k.zsh`:
```sh
# Minimal Powerlevel10k config. Run `p10k configure` to regenerate a
# full instant-prompt configuration tailored to your terminal.
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vcs)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status root_indicator background_jobs time)
typeset -g POWERLEVEL9K_MODE=nerdfont-complete
```

`dotfiles/gitconfig`:
```ini
[user]
	name =
	email =
[init]
	defaultBranch = main
[pull]
	rebase = false
[core]
	editor = vim
```

- [ ] **Step 2: Write the failing tests**

`tests/dotfiles.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/dotfiles.sh"
}

teardown() {
  macup_test_teardown
}

@test "run_dotfiles symlinks bundled dotfiles into HOME when targets don't exist" {
  run run_dotfiles

  [ "$status" -eq 0 ]
  [ -L "$HOME/.zshrc" ]
  [ "$(readlink "$HOME/.zshrc")" = "$ROOT_DIR/dotfiles/zshrc" ]
}

@test "run_dotfiles skips a target that is already a correct symlink" {
  ln -s "$ROOT_DIR/dotfiles/zshrc" "$HOME/.zshrc"

  run run_dotfiles

  [ "$status" -eq 0 ]
  [[ "$output" == *".zshrc already up to date"* ]]
}

@test "run_dotfiles backs up and replaces an existing regular file when confirmed" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=0

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ -f "$HOME/.zshrc.macup-backup" ]
  [ "$(cat "$HOME/.zshrc.macup-backup")" = "my custom zshrc" ]
  [ -L "$HOME/.zshrc" ]
}

@test "run_dotfiles skips an existing regular file when the user declines" {
  echo "my custom zshrc" > "$HOME/.zshrc"
  export GUM_CONFIRM_EXIT=1

  run run_dotfiles

  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.zshrc" ]
  [ "$(cat "$HOME/.zshrc")" = "my custom zshrc" ]
  [[ "$output" == *"Skipped $HOME/.zshrc"* ]]
}

@test "run_dotfiles clones DOTFILES_REPO and links from the cache when set" {
  export DOTFILES_REPO="git@github.com:example/dotfiles.git"

  run run_dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/macup/dotfiles-repo" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bats tests/dotfiles.bats`
Expected: FAIL — `lib/dotfiles.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/dotfiles.sh`**

```bash
#!/usr/bin/env bash

run_dotfiles() {
  local source_dir

  if [ -n "${DOTFILES_REPO:-}" ]; then
    local cache_dir="$HOME/.cache/macup/dotfiles-repo"
    if [ -d "$cache_dir/.git" ]; then
      log_info "Updating dotfiles repo cache"
      if ! git -C "$cache_dir" pull --ff-only; then
        log_warn "Failed to update dotfiles repo cache, using existing checkout"
      fi
    else
      log_info "Cloning dotfiles repo: $DOTFILES_REPO"
      mkdir -p "$(dirname "$cache_dir")"
      if ! git clone "$DOTFILES_REPO" "$cache_dir"; then
        log_error "Failed to clone dotfiles repo: $DOTFILES_REPO"
        return 1
      fi
    fi
    source_dir="$cache_dir"
  else
    source_dir="$ROOT_DIR/dotfiles"
  fi

  local file target
  for file in "$source_dir"/*; do
    [ -e "$file" ] || continue
    target="$HOME/.$(basename "$file")"

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      ln -s "$file" "$target"
      log_info "Linked $target -> $file"
      continue
    fi

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$file" ]; then
      log_info "$target already up to date"
      continue
    fi

    if ui_confirm "$target already exists. Back it up and replace with symlink?"; then
      mv "$target" "$target.macup-backup"
      ln -s "$file" "$target"
      log_info "Backed up and linked $target -> $file"
    else
      log_warn "Skipped $target"
    fi
  done

  return 0
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/dotfiles.bats`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/dotfiles.sh dotfiles tests/dotfiles.bats
git commit -m "feat: add dotfiles module and bundled default dotfiles"
```

---

### Task 7: `lib/macos_defaults.sh` — `run_macos_defaults()`

**Files:**
- Create: `lib/macos_defaults.sh`
- Test: `tests/macos_defaults.bats`

**Interfaces:**
- Consumes: `log_info` from [[Task 1]]; the `defaults` and `killall`
  stubs from [[Task 1]].
- Produces: `run_macos_defaults()` → returns 0. Internal helper
  `_defaults_apply(domain, key, type, value)` (not called directly by
  other modules).

- [ ] **Step 1: Write the failing tests**

`tests/macos_defaults.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
  export DEFAULTS_STORE
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/macos_defaults.sh"
}

teardown() {
  macup_test_teardown
}

@test "run_macos_defaults writes a setting that isn't already applied" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  grep -q "com.apple.finder|AppleShowAllExtensions|true" "$DEFAULTS_STORE"
  grep -q "defaults write com.apple.finder AppleShowAllExtensions true" "$MACUP_CALL_LOG"
}

@test "run_macos_defaults skips a setting that's already correctly applied" {
  echo "com.apple.finder|AppleShowAllExtensions|true" > "$DEFAULTS_STORE"

  run run_macos_defaults

  [ "$status" -eq 0 ]
  [[ "$output" == *"com.apple.finder AppleShowAllExtensions already set to true, skipping"* ]]
  ! grep -q "defaults write com.apple.finder AppleShowAllExtensions" "$MACUP_CALL_LOG"
}

@test "run_macos_defaults creates the Screenshots directory" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  [ -d "$HOME/Screenshots" ]
}

@test "run_macos_defaults restarts Finder and SystemUIServer" {
  run run_macos_defaults

  [ "$status" -eq 0 ]
  grep -q "killall Finder" "$MACUP_CALL_LOG"
  grep -q "killall SystemUIServer" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/macos_defaults.bats`
Expected: FAIL — `lib/macos_defaults.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/macos_defaults.sh`**

```bash
#!/usr/bin/env bash

_defaults_apply() {
  local domain="$1" key="$2" type="$3" value="$4"
  local current
  current="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  if [ "$current" = "$value" ]; then
    log_info "$domain $key already set to $value, skipping"
    return 0
  fi
  defaults write "$domain" "$key" "-$type" "$value"
  log_info "Set $domain $key = $value"
}

run_macos_defaults() {
  mkdir -p "$HOME/Screenshots"

  _defaults_apply com.apple.finder AppleShowAllExtensions bool true
  _defaults_apply com.apple.finder AppleShowAllFiles bool true
  _defaults_apply com.apple.finder ShowPathbar bool true
  _defaults_apply com.apple.finder ShowStatusBar bool true

  _defaults_apply NSGlobalDomain KeyRepeat int 2
  _defaults_apply NSGlobalDomain ApplePressAndHoldEnabled bool false

  _defaults_apply com.apple.AppleMultitouchTrackpad Clicking bool true

  _defaults_apply com.apple.screencapture location string "$HOME/Screenshots"
  _defaults_apply com.apple.screencapture type string png

  _defaults_apply NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true
  _defaults_apply NSGlobalDomain PMPrintingExpandedStateForPrint bool true

  killall Finder >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/macos_defaults.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/macos_defaults.sh tests/macos_defaults.bats
git commit -m "feat: add macos-defaults module"
```

---

### Task 8: `lib/github.sh` — `run_github()`

**Files:**
- Create: `lib/github.sh`
- Test: `tests/github.bats`

**Interfaces:**
- Consumes: `log_info`/`log_error` from [[Task 1]]; `ui_input` from
  [[Task 2]]; the `ssh-keygen`, `ssh-add`, `pbcopy`, `gh` stubs from
  [[Task 1]].
- Produces: `run_github()` → returns 0 on success, 1 on failure.

- [ ] **Step 1: Write the failing tests**

`tests/github.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/github.sh"
}

teardown() {
  macup_test_teardown
}

@test "run_github generates an SSH key when none exists" {
  export GUM_INPUT_RESULT="me@example.com"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519" ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  grep -q "ssh-keygen" "$MACUP_CALL_LOG"
}

@test "run_github skips key generation when a key already exists" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"SSH key already exists"* ]]
  ! grep -q "ssh-keygen" "$MACUP_CALL_LOG"
}

@test "run_github logs in with gh when not already authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=1
  export GH_AUTH_LOGIN_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  grep -q "auth login" "$MACUP_CALL_LOG"
}

@test "run_github skips gh login when already authenticated" {
  mkdir -p "$HOME/.ssh"
  echo "existing-key" > "$HOME/.ssh/id_ed25519"
  echo "existing-key.pub" > "$HOME/.ssh/id_ed25519.pub"
  export GH_AUTH_STATUS_EXIT=0

  run run_github

  [ "$status" -eq 0 ]
  [[ "$output" == *"gh already authenticated, skipping"* ]]
  ! grep -q "auth login" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/github.bats`
Expected: FAIL — `lib/github.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/github.sh`**

```bash
#!/usr/bin/env bash

run_github() {
  local key_path="$HOME/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    local email
    email="$(ui_input "Email for SSH key" "")"
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
    log_info "Authenticating gh CLI"
    if ! gh auth login --git-protocol ssh; then
      log_error "gh auth login failed"
      return 1
    fi
  else
    log_info "gh already authenticated, skipping"
  fi

  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/github.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/github.sh tests/github.bats
git commit -m "feat: add github module (SSH key + gh auth)"
```

---

### Task 9: `bin/macup` — entrypoint, CLI parsing, module dispatch

**Files:**
- Create: `bin/macup`
- Test: `tests/macup.bats`

**Interfaces:**
- Consumes: everything produced by Tasks 1–8: `resolve_script_dir`,
  `log_info`/`log_warn`/`log_error`, `load_config` ([[Task 1]],
  [[Task 3]] `lib/common.sh`); `ui_choose_modules`, `ui_log_step`
  ([[Task 2]] `lib/menu.sh`); `run_homebrew` ([[Task 4]]); `run_shell`
  ([[Task 5]]); `run_dotfiles` ([[Task 6]]); `run_macos_defaults`
  ([[Task 7]]); `run_github` ([[Task 8]]).
- Produces: the `macup` executable itself — no other task depends on
  its internals.

- [ ] **Step 1: Write the failing tests**

`tests/macup.bats`:
```bash
#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  MACUP_BIN="$ROOT_DIR/bin/macup"

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL
  cat > "$MACUP_BREW_PATH_APPLE_SILICON" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "${MACUP_CALL_LOG:-/dev/null}"
exit 0
EOF
  chmod +x "$MACUP_BREW_PATH_APPLE_SILICON"

  DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
  export DEFAULTS_STORE
  export GUM_CONFIRM_EXIT=1
  export GUM_INPUT_RESULT="me@example.com"
  export GH_AUTH_STATUS_EXIT=0
}

teardown() {
  macup_test_teardown
}

@test "macup --help prints usage and exits 0" {
  run "$MACUP_BIN" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: macup"* ]]
}

@test "macup rejects an unknown argument" {
  run "$MACUP_BIN" --bogus

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]]
}

@test "macup runs a single named module non-interactively" {
  run "$MACUP_BIN" homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"succeeded: homebrew"* ]]
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "macup --dotfiles-repo overrides DOTFILES_REPO for this run only" {
  run "$MACUP_BIN" --dotfiles-repo=git@github.com:example/dotfiles.git dotfiles

  [ "$status" -eq 0 ]
  grep -q "clone git@github.com:example/dotfiles.git $HOME/.cache/macup/dotfiles-repo" "$MACUP_CALL_LOG"
}

@test "macup --all runs every module and reports failures without aborting" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  export BREW_EXIT=1

  run "$MACUP_BIN" --all

  [ "$status" -eq 1 ]
  [[ "$output" == *"Running homebrew"* ]]
  [[ "$output" == *"Running shell"* ]]
  [[ "$output" == *"Running dotfiles"* ]]
  [[ "$output" == *"Running macos-defaults"* ]]
  [[ "$output" == *"Running github"* ]]
  [[ "$output" == *"failed: homebrew"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/macup.bats`
Expected: FAIL — `bin/macup: No such file or directory`.

- [ ] **Step 3: Implement `bin/macup`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Locate this script's real directory, resolving any symlinks (e.g. the
# Homebrew Cellar symlink), before lib/common.sh exists to do it for us.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export ROOT_DIR

# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/menu.sh
source "$ROOT_DIR/lib/menu.sh"
# shellcheck source=lib/homebrew.sh
source "$ROOT_DIR/lib/homebrew.sh"
# shellcheck source=lib/shell.sh
source "$ROOT_DIR/lib/shell.sh"
# shellcheck source=lib/dotfiles.sh
source "$ROOT_DIR/lib/dotfiles.sh"
# shellcheck source=lib/macos_defaults.sh
source "$ROOT_DIR/lib/macos_defaults.sh"
# shellcheck source=lib/github.sh
source "$ROOT_DIR/lib/github.sh"

ALL_MODULES=(homebrew shell dotfiles macos-defaults github)

usage() {
  cat <<'EOF'
Usage: macup [options] [module...]

Options:
  --all                     Run all modules, non-interactive
  --dotfiles-repo=<url>     Override DOTFILES_REPO for this run
  --brewfile=<path>         Override EXTRA_BREWFILE for this run
  --help                    Show this help

Modules: homebrew shell dotfiles macos-defaults github

With no options or modules, launches an interactive checklist.
EOF
}

module_function_name() {
  case "$1" in
    macos-defaults) echo "run_macos_defaults" ;;
    *) echo "run_$1" ;;
  esac
}

run_selected_modules() {
  local -a modules=("$@")
  local -a succeeded=() failed=()
  local module fn

  for module in "${modules[@]}"; do
    fn="$(module_function_name "$module")"
    ui_log_step "Running $module"
    if "$fn"; then
      succeeded+=("$module")
    else
      failed+=("$module")
    fi
  done

  echo
  log_info "Summary:"
  if [ "${#succeeded[@]}" -gt 0 ]; then
    log_info "  succeeded: ${succeeded[*]}"
  fi
  if [ "${#failed[@]}" -gt 0 ]; then
    log_warn "  failed: ${failed[*]}"
    return 1
  fi
  return 0
}

main() {
  local run_all=false
  local cli_dotfiles_repo="" cli_brewfile=""
  local -a modules=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --all)
        run_all=true
        shift
        ;;
      --dotfiles-repo=*)
        cli_dotfiles_repo="${1#--dotfiles-repo=}"
        shift
        ;;
      --brewfile=*)
        cli_brewfile="${1#--brewfile=}"
        shift
        ;;
      homebrew|shell|dotfiles|macos-defaults|github)
        modules+=("$1")
        shift
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  load_config

  [ -n "$cli_dotfiles_repo" ] && DOTFILES_REPO="$cli_dotfiles_repo"
  [ -n "$cli_brewfile" ] && EXTRA_BREWFILE="$cli_brewfile"

  if [ "$run_all" = true ]; then
    modules=("${ALL_MODULES[@]}")
  fi

  if [ "${#modules[@]}" -eq 0 ]; then
    mapfile -t modules < <(ui_choose_modules)
  fi

  if [ "${#modules[@]}" -eq 0 ]; then
    log_warn "No modules selected, nothing to do"
    exit 0
  fi

  run_selected_modules "${modules[@]}"
}

main "$@"
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x bin/macup
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/macup.bats`
Expected: PASS (5 tests).

- [ ] **Step 6: Run the full test suite**

Run: `bats tests/`
Expected: PASS (all files, all tests).

- [ ] **Step 7: Commit**

```bash
git add bin/macup tests/macup.bats
git commit -m "feat: add macup entrypoint with CLI parsing and module dispatch"
```

---

### Task 10: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write `README.md`**

```markdown
# macup

Bootstrap a fresh Mac to a working dev environment, or keep an existing
one in sync. `macup` installs Homebrew packages, Oh My Zsh +
Powerlevel10k, symlinks dotfiles, applies a curated set of macOS system
defaults, and sets up a GitHub SSH key + `gh` CLI authentication.

## Install

```sh
brew tap dicksonk/macup
brew install macup
```

## Usage

```sh
macup                          # interactive checklist, runs selected modules
macup --all                    # run all modules, non-interactive
macup homebrew dotfiles        # run only the named modules, non-interactive
macup --dotfiles-repo=<url> dotfiles
macup --brewfile=<path> homebrew
macup --help
```

Modules: `homebrew`, `shell`, `dotfiles`, `macos-defaults`, `github`.

## Configuration

On first run (or on demand), `macup` offers to create
`~/.config/macup/config` from `macup.conf.example`:

```sh
DOTFILES_REPO=              # e.g. git@github.com:you/dotfiles.git — blank uses bundled dotfiles
EXTRA_BREWFILE=             # e.g. /Users/you/Brewfile.personal — blank means bundled Brewfile only
```

`--dotfiles-repo=<url>` and `--brewfile=<path>` override these for a
single run without editing the file.

## Development

Run from a local checkout:

```sh
./bin/macup --help
```

### Tests

```sh
brew install bats-core
bats tests/
```

Tests exercise module logic (idempotency checks, path resolution, config
and flag parsing) against stub `brew`/`gh`/`gum`/`git`/`ssh-keygen`/
`defaults`/`killall` executables — no real system state is touched.

### Manual verification checklist

The following system-mutating behavior is not covered by bats and should
be verified by hand on a real or VM Mac before a release:

- [ ] Homebrew installs from scratch on a machine with no `brew`.
- [ ] Oh My Zsh and Powerlevel10k install from scratch.
- [ ] `defaults write` calls actually change Finder/keyboard/trackpad/
      screenshot behavior, and `killall Finder`/`SystemUIServer` applies
      them immediately.
- [ ] `ssh-keygen` generates a real, usable key and `gh auth login`
      completes.

## Cutting a release

1. Tag the source repo: `git tag vX.Y.Z && git push --tags`.
2. Download the tarball and compute its checksum:
   `curl -sL https://github.com/dicksonk/macup/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
3. Update `url` and `sha256` in `packaging/homebrew/macup.rb`, copy it to
   `homebrew-macup/Formula/macup.rb` in the tap repo, and push.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 11: Homebrew tap formula template

**Files:**
- Create: `packaging/homebrew/macup.rb`

**Interfaces:**
- Consumes: nothing (static template, copied manually into the separate
  `homebrew-macup` tap repo per the README's release process).
- Produces: nothing consumed by other tasks in this repo.

- [ ] **Step 1: Write `packaging/homebrew/macup.rb`**

```ruby
class Macup < Formula
  desc "Bootstrap and keep a Mac dev environment in sync"
  homepage "https://github.com/dicksonk/macup"
  url "https://github.com/dicksonk/macup/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_TARBALL_SHA256"
  license "MIT"

  depends_on "git"
  depends_on "gum"
  depends_on "gh"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/macup"
  end

  test do
    system "#{bin}/macup", "--help"
  end
end
```

- [ ] **Step 2: Verify it's syntactically valid Ruby**

Run: `ruby -c packaging/homebrew/macup.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add packaging/homebrew/macup.rb
git commit -m "feat: add homebrew tap formula template"
```

---

## Self-Review Notes

- **Spec coverage:** Purpose/modules → Tasks 4–8. TUI → Task 2.
  Distribution & path resolution → Tasks 1, 9. Configuration → Task 3.
  CLI interface → Task 9. Error handling (non-aborting summary, network
  errors continue, `ui_confirm` before destructive action) → Tasks 4–9.
  Testing → Tasks 1–9 (bats throughout) + README manual checklist (Task
  10). Homebrew formula → Task 11.
- **Placeholder scan:** no TODOs; every step has runnable code and an
  expected result.
- **Type/name consistency:** `run_<module>()` names, `ui_*` signatures,
  `MACUP_BREW_PATH_*` override vars, and `MACUP_CALL_LOG`/`TEST_HOME`
  test-helper variables are used identically across every task that
  references them.
