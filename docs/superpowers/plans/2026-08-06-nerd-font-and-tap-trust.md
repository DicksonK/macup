# Terminal Nerd Font + Homebrew Tap Trust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two reported gaps: (1) Powerlevel10k icons render broken because nothing sets a Nerd Font as Terminal.app's/iTerm2's active font despite the fonts already being installed via the Brewfile; (2) `brew bundle` silently skips formulae/casks from the Brewfile's custom taps because Homebrew 6.0's tap-trust requirement isn't satisfied.

**Architecture:** Two independent, unrelated fixes in two existing modules — `lib/shell.sh` gets a new `_configure_terminal_font` function (AppleScript for Terminal.app, an iTerm2 Dynamic Profile + `Default Bookmark Guid` pointer for iTerm2), `lib/homebrew.sh` gets a new `_trust_brewfile_taps`/`_untrusted_brewfile_taps` pair that runs `brew tap`+`brew trust --tap` before `brew bundle`.

**Tech Stack:** bash, `osascript` (Terminal.app AppleScript), `defaults` (iTerm2 prefs), Homebrew 6.0 (`brew trust`), bats (existing stub-based test infra).

## Global Constraints

- Font family for Terminal.app: `MesloLGS Nerd Font Mono` (verified registered name — not `MesloLGS NF`). PostScript name of the regular weight: `MesloLGSNFM-Regular` (verified via `fc-scan`, does not match the `.ttf` filename convention — do not guess this from the filename).
- `_configure_terminal_font` checks the font is actually installed before doing anything — `[ -f "$HOME/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf" ] || [ -f "/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf" ]` (the `.ttf` filename this time, which does match Homebrew's cask install layout — confirmed via `find`, distinct from the PostScript name above). If missing, `log_warn` and return early — do not use `fc-list`/`fc-scan` for this check; those come from Homebrew's `fontconfig` package, not guaranteed present on a fresh Mac.
- iTerm2's default profile is never rewritten directly (the live prefs plist has runtime-assigned GUIDs in an array — too fragile to patch safely). Use a Dynamic Profile JSON at `$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json` with fixed GUID `B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10`, plus `defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string <that GUID>`.
- iTerm2 presence is checked via `$MACUP_ITERM_APP_PATH` (default `/Applications/iTerm.app`), a new override variable following the existing `MACUP_BREW_PATH_APPLE_SILICON`-style pattern so it's testable.
- Font-configuration failures are non-fatal (`log_warn`, continue) — this is cosmetic polish, not core functionality.
- Do NOT use the Homebrew `tap "x/y", trusted: true` Brewfile DSL keyword — verified directly that it's currently a silent no-op on the installed Homebrew 6.0.15 for taps without a custom remote URL. Trust is handled entirely via explicit `brew tap`/`brew trust --tap` shell calls.
- The tap-trust confirmation prompt (`ui_confirm`) always runs when there are untrusted taps to trust — regardless of `MACUP_NONINTERACTIVE`/`--all` — matching the existing precedent in `lib/dotfiles.sh`'s git-identity prompt (essential setup with no safe default), not the optional config-creation prompt in `lib/common.sh` (which IS skipped non-interactively).
- Tap trust state is checked via `$HOME/.homebrew/trust.json` (or `$XDG_CONFIG_HOME/homebrew/trust.json` if set) for idempotency — already-trusted taps are silently excluded from the prompt on repeat runs.

---

### Task 1: Nerd Font terminal configuration (`lib/shell.sh`)

**Files:**
- Modify: `lib/shell.sh:56-57` (append `_configure_terminal_font` function + call at end of `run_shell`, right before the final `return 0`)
- Create: `tests/test_helper/stubs/osascript`
- Modify: `tests/shell.bats` (new tests)
- Modify: `README.md:130-134` (new manual verification checklist item, inserted after the existing zsh-uv-env item and before `## Cutting a release`)

**Interfaces:**
- Produces: `_configure_terminal_font` (no args) — called once at the end of `run_shell`, no return value depended upon by callers (non-fatal by design).
- Consumes: `is_dry_run`, `dry_run_report`, `log_info`, `log_warn` (from `lib/common.sh`, already sourced by every module).

- [ ] **Step 1: Write the `osascript` test stub**

Create `tests/test_helper/stubs/osascript`:

```bash
#!/usr/bin/env bash
echo "osascript $*" >> "${MACUP_CALL_LOG:-/dev/null}"
case "$*" in
  *"get font name"*)
    printf '%s\n' "${OSASCRIPT_RESULT:-}"
    ;;
esac
exit "${OSASCRIPT_EXIT:-0}"
```

```bash
chmod +x tests/test_helper/stubs/osascript
```

In `tests/shell.bats`'s `setup()` function, add `export DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"` as the last line (this variable is not currently exported there — one of the new tests in the next step writes directly into it to pre-seed the fake `defaults` store):

```bash
setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/shell.sh"
  export DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
}
```

- [ ] **Step 2: Write the failing tests**

In `tests/shell.bats`, add an `install_stub_font` helper function (after
`setup()`/`teardown()`, before the first `@test`, matching the existing
`install_stub_brew`-style helper convention used in `tests/homebrew.bats`):

```bash
install_stub_font() {
  mkdir -p "$HOME/Library/Fonts"
  touch "$HOME/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf"
}
```

Then add these tests (after the existing tests, before the final closing
of the file). Every test that expects `_configure_terminal_font` to get
past the new font-existence check calls `install_stub_font` first; the
one new "not installed" test deliberately does not:

```bash
@test "run_shell warns and skips font config when the Nerd Font isn't installed" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"MesloLGS Nerd Font Mono not installed; run the homebrew module first, then re-run shell"* ]]
  [ ! -f "$MACUP_CALL_LOG" ] || ! grep -q "osascript" "$MACUP_CALL_LOG"
  [ ! -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
}

@test "run_shell reports Nerd Font config in dry-run mode when iTerm2 is present" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would set Terminal.app's default font to MesloLGS Nerd Font Mono"* ]]
  [[ "$output" == *"[dry-run] would create iTerm2 dynamic profile 'macup' with MesloLGS Nerd Font Mono and set it as default"* ]]
}

@test "run_shell does not report iTerm2 config in dry-run mode when iTerm2 is absent" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/no-such-iterm.app"
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"would set Terminal.app's default font"* ]]
  [[ "$output" != *"iTerm2"* ]]
}

@test "run_shell skips Terminal.app font config when already set to the target font" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/no-such-iterm.app"
  export OSASCRIPT_RESULT="MesloLGSNFM-Regular"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Terminal.app font already set to MesloLGS Nerd Font Mono, skipping"* ]]
  ! grep -q "osascript.*set font name" "$MACUP_CALL_LOG"
}

@test "run_shell sets Terminal.app font and creates the iTerm2 dynamic profile" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Set Terminal.app font to MesloLGS Nerd Font Mono"* ]]
  grep -q 'set font name of default settings to "MesloLGS Nerd Font Mono"' "$MACUP_CALL_LOG"
  [ -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
  grep -q "MesloLGSNFM-Regular" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json"
  grep -q 'defaults write com.googlecode.iterm2 Default Bookmark Guid B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10' "$MACUP_CALL_LOG"
  [[ "$output" == *"Created iTerm2 dynamic profile with MesloLGS Nerd Font Mono and set as default"* ]]
}

@test "run_shell skips the iTerm2 profile when Default Bookmark Guid already matches" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"
  echo "com.googlecode.iterm2|Default Bookmark Guid|B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10" >> "$DEFAULTS_STORE"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"iTerm2 default profile already set to the macup Nerd Font profile, skipping"* ]]
  [ ! -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
}
```

Note: this test file's `grep -q 'defaults write com.googlecode.iterm2
Default Bookmark Guid ...'` assertions have no quotes around the
multi-word key — the `defaults` stub logs `$key` unquoted (verified
directly against the stub's actual behavior, not guessed).

Note: the second-to-last test writes directly into `$DEFAULTS_STORE`
using the same `domain|key|value` format the
`tests/test_helper/stubs/defaults` stub reads/writes (see that file for
the exact format) — this is why `setup()` was updated in Step 1 to
export it.

- [ ] **Step 3: Run the new tests to verify they fail**

Run: `bats tests/shell.bats -f "Nerd Font|Terminal.app|iTerm2"`
Expected: FAIL — `_configure_terminal_font` doesn't exist yet, `MACUP_ITERM_APP_PATH` isn't read anywhere, no `osascript`/dynamic-profile logic exists in `lib/shell.sh` yet.

- [ ] **Step 4: Implement `_configure_terminal_font` in `lib/shell.sh`**

At the top of `lib/shell.sh` (after the shebang line, before `_clone_if_missing`), add:

```bash
: "${MACUP_ITERM_APP_PATH:=/Applications/iTerm.app}"
```

Replace the end of `lib/shell.sh` (currently lines 55-57: the blank line, `return 0`, and closing `}`) with:

```bash

  _configure_terminal_font

  return 0
}

_configure_terminal_font() {
  local font_family="MesloLGS Nerd Font Mono"
  local font_ps_name="MesloLGSNFM-Regular"
  local font_file="MesloLGSNerdFontMono-Regular.ttf"
  local iterm_guid="B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10"

  if [ ! -f "$HOME/Library/Fonts/$font_file" ] && [ ! -f "/Library/Fonts/$font_file" ]; then
    log_warn "$font_family not installed; run the homebrew module first, then re-run shell"
    return 0
  fi

  local current_font
  current_font="$(osascript -e 'tell application "Terminal" to get font name of default settings' 2>/dev/null || true)"
  if [ "$current_font" = "$font_ps_name" ]; then
    log_info "Terminal.app font already set to $font_family, skipping"
  elif is_dry_run; then
    dry_run_report "set Terminal.app's default font to $font_family"
  else
    if osascript -e "tell application \"Terminal\" to set font name of default settings to \"$font_family\"" >/dev/null 2>&1; then
      log_info "Set Terminal.app font to $font_family"
    else
      log_warn "Failed to set Terminal.app font (may need Automation permission in System Settings > Privacy & Security)"
    fi
  fi

  if [ -d "$MACUP_ITERM_APP_PATH" ]; then
    local current_guid
    current_guid="$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null || true)"
    if [ "$current_guid" = "$iterm_guid" ]; then
      log_info "iTerm2 default profile already set to the macup Nerd Font profile, skipping"
    elif is_dry_run; then
      dry_run_report "create iTerm2 dynamic profile 'macup' with $font_family and set it as default"
    else
      local profile_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
      mkdir -p "$profile_dir"
      cat > "$profile_dir/macup.json" <<EOF
{
  "Profiles": [
    {
      "Name": "macup",
      "Guid": "$iterm_guid",
      "Normal Font": "$font_ps_name 13"
    }
  ]
}
EOF
      if defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$iterm_guid"; then
        log_info "Created iTerm2 dynamic profile with $font_family and set as default"
      else
        log_warn "Failed to set iTerm2 default profile"
      fi
    fi
  fi
}
```

(`_configure_terminal_font` is defined after `run_shell` here, matching
this file's existing convention of `_clone_if_missing` being defined
*before* `run_shell` — either ordering works in bash since the whole
file is sourced before any function is called, but keep the diff
minimal: append the new function at the end of the file rather than
reordering existing code.)

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `bats tests/shell.bats -f "Nerd Font|Terminal.app|iTerm2"`
Expected: PASS (6 tests)

- [ ] **Step 6: Add the README manual verification checklist item**

In `README.md`, after the existing `zsh-uv-env` checklist item (ending
`...also prints the activation message on startup.` at line 134) and
before the `## Cutting a release` heading, add:

```markdown
- [ ] Running `macup shell` sets Terminal.app's default font to MesloLGS
      Nerd Font Mono (may prompt for Automation permission in System
      Settings the first time) and, if iTerm2 is installed, creates an
      iTerm2 dynamic profile with that font and makes it the default —
      Powerlevel10k icons should render correctly afterward in both.
```

- [ ] **Step 7: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (123 existing + 6 new = 129)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 8: Commit**

```bash
git add lib/shell.sh tests/test_helper/stubs/osascript tests/shell.bats README.md
git commit -m "feat: set Nerd Font as Terminal.app/iTerm2 default for Powerlevel10k"
```

---

### Task 2: Homebrew tap trust (`lib/homebrew.sh`)

**Files:**
- Modify: `lib/homebrew.sh:6` (add `_trust_brewfile_taps`/`_untrusted_brewfile_taps`, call the former from `run_homebrew` right after `brew_bin` is resolved, before the first `brew bundle` call)
- Modify: `tests/homebrew.bats` (new tests)

**Interfaces:**
- Produces: `_trust_brewfile_taps <brew_bin>` — called once from `run_homebrew`, non-fatal (never causes `run_homebrew` to fail on its own).
- Consumes: `is_dry_run`, `dry_run_report`, `log_info`, `log_warn`, `ui_confirm` (from `lib/common.sh`/`lib/menu.sh`, already sourced), `$ROOT_DIR`, `$EXTRA_BREWFILE`.

- [ ] **Step 1: Write the failing tests**

First, in `tests/homebrew.bats`'s `setup()`, add `unset XDG_CONFIG_HOME`
right after `macup_test_setup` (defensive: `_untrusted_brewfile_taps`
respects `$XDG_CONFIG_HOME` if set, and the new tests assume the
`$HOME/.homebrew/trust.json` fallback path — this guards against the
test-running environment happening to have `XDG_CONFIG_HOME` set to
something else):

```bash
setup() {
  load 'test_helper/load'
  macup_test_setup
  unset XDG_CONFIG_HOME

  MACUP_BREW_PATH_APPLE_SILICON="$TEST_HOME/brew-apple"
  MACUP_BREW_PATH_INTEL="$TEST_HOME/brew-intel"
  export MACUP_BREW_PATH_APPLE_SILICON MACUP_BREW_PATH_INTEL

  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/homebrew.sh"
}
```

Then add these tests (the real `$ROOT_DIR/Brewfile`
already declares `tap "databricks/tap"`, `tap "homebrew/autoupdate"`, and
`tap "martido/homebrew-graph"` — these tests rely on that real content,
matching how existing tests in this file already assert against the
real bundled `Brewfile`'s path):

```bash
@test "run_homebrew trusts untrusted Brewfile taps after confirmation, before bundling" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=0

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap databricks/tap" "$MACUP_CALL_LOG"
  grep -q "trust --tap homebrew/autoupdate" "$MACUP_CALL_LOG"
  grep -q "trust --tap martido/homebrew-graph" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew skips already-trusted taps without prompting" {
  install_stub_brew
  mkdir -p "$HOME/.homebrew"
  cat > "$HOME/.homebrew/trust.json" <<'EOF'
{"trustedtaps": ["databricks/tap", "homebrew/autoupdate", "martido/homebrew-graph"]}
EOF

  run run_homebrew

  [ "$status" -eq 0 ]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
}

@test "run_homebrew does not trust taps when confirmation is declined, but still bundles" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=1

  run run_homebrew

  [ "$status" -eq 0 ]
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
  grep -q "bundle --file=$ROOT_DIR/Brewfile" "$MACUP_CALL_LOG"
}

@test "run_homebrew reports untrusted taps in dry-run mode without prompting or trusting" {
  install_stub_brew
  export MACUP_DRY_RUN=1

  run run_homebrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would trust Homebrew tap(s): databricks/tap homebrew/autoupdate martido/homebrew-graph"* ]]
  ! grep -q "gum confirm" "$MACUP_CALL_LOG"
  ! grep -q "trust --tap" "$MACUP_CALL_LOG"
}

@test "run_homebrew also trusts taps declared in EXTRA_BREWFILE" {
  install_stub_brew
  export GUM_CONFIRM_EXIT=0
  EXTRA_BREWFILE="$TEST_HOME/extra.Brewfile"
  export EXTRA_BREWFILE
  cat > "$EXTRA_BREWFILE" <<'EOF'
tap "example/extra"
EOF

  run run_homebrew

  [ "$status" -eq 0 ]
  grep -q "trust --tap example/extra" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/homebrew.bats -f "trust"`
Expected: FAIL — `_trust_brewfile_taps` doesn't exist yet, `run_homebrew` never calls `brew trust`.

- [ ] **Step 3: Implement `_trust_brewfile_taps` in `lib/homebrew.sh`**

At the top of `lib/homebrew.sh`, after the two existing `: "${MACUP_BREW_PATH_...}"` lines and before `run_homebrew() {`, add:

```bash
_untrusted_brewfile_taps() {
  local trust_file="$HOME/.homebrew/trust.json"
  [ -n "${XDG_CONFIG_HOME:-}" ] && trust_file="$XDG_CONFIG_HOME/homebrew/trust.json"

  local -a taps=()
  local tap
  while IFS= read -r tap; do
    [ -n "$tap" ] && taps+=("$tap")
  done < <(
    grep -ohE '^tap[[:space:]]+"[^"]+"' "$ROOT_DIR/Brewfile" "${EXTRA_BREWFILE:-/dev/null}" 2>/dev/null \
      | sed -E 's/^tap[[:space:]]+"([^"]+)"/\1/' \
      | sort -u
  )

  local t
  for t in "${taps[@]}"; do
    if [ -f "$trust_file" ] && grep -q "\"$t\"" "$trust_file" 2>/dev/null; then
      continue
    fi
    printf '%s\n' "$t"
  done
}

_trust_brewfile_taps() {
  local brew_bin="$1"
  local -a untrusted=()
  local t
  while IFS= read -r t; do
    [ -n "$t" ] && untrusted+=("$t")
  done < <(_untrusted_brewfile_taps)

  if [ "${#untrusted[@]}" -eq 0 ]; then
    return 0
  fi

  if is_dry_run; then
    dry_run_report "trust Homebrew tap(s): ${untrusted[*]}"
    return 0
  fi

  if ! ui_confirm "Trust ${#untrusted[@]} Homebrew tap(s) required by your Brewfile: ${untrusted[*]}?"; then
    log_warn "Taps not trusted; brew bundle may skip formulae/casks from: ${untrusted[*]}"
    return 0
  fi

  for t in "${untrusted[@]}"; do
    if "$brew_bin" tap "$t" && "$brew_bin" trust --tap "$t"; then
      log_info "Trusted tap $t"
    else
      log_warn "Failed to trust tap $t"
    fi
  done
}
```

Then in `run_homebrew`, immediately after the `if [ -z "$brew_bin" ]; then ... fi` block that resolves/installs Homebrew (currently ending at line 29) and before the `if is_dry_run; then dry_run_report "run: brew bundle...` block (currently starting at line 31), add:

```bash

  _trust_brewfile_taps "$brew_bin"
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `bats tests/homebrew.bats -f "trust"`
Expected: PASS (5 tests)

- [ ] **Step 5: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (129 from Task 1 + 5 new = 134)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 6: Commit**

```bash
git add lib/homebrew.sh tests/homebrew.bats
git commit -m "fix: trust Brewfile-declared Homebrew taps before bundling"
```
