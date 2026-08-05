# Interactive Checklist Banner + Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a centered, bordered banner (title/subtitle/version) above `macup`'s interactive module checklist, and restyle the checklist itself to match, so the interactive screen (bare `macup`, no flags/modules) reads as one polished, branded screen instead of a bare list.

**Architecture:** A new `ui_banner` function in `lib/menu.sh` (a `gum style` bordered box, centered via a `tput cols` computation), called as a plain statement from `bin/macup`'s `main()` immediately before the existing interactive-checklist block — never inside the `<(ui_choose_modules)` process substitution, since that would corrupt the parsed module list. `ui_choose_modules` itself gets matching accent-color flags added to its existing `gum choose` call.

**Tech Stack:** bash, `gum` (0.17.0+), `tput`, bats (existing stub-based test infra in `tests/`).

## Global Constraints

- `gum choose` has no `--border`/`--align` flags (only `gum style` does) — the banner is a separate static block above the list, not a literal border around it. Do not attempt to make `gum choose` itself bordered.
- Banner and checklist reuse the existing accent color `212` (already used by `ui_log_step`) — no new color introduced.
- `ui_banner` reads the version from `$ROOT_DIR/VERSION` (same file/pattern `bin/macup`'s `--version` flag already reads) — never hardcode a version string.
- `ui_confirm`, `ui_input`, `ui_input_secret` are untouched — only `ui_choose_modules` and the new `ui_banner` are in scope.
- The banner must only appear for genuinely interactive runs (bare `macup`, no `--all`, no module names) — never for `--all` or named-module non-interactive invocations.

---

### Task 1: Add `ui_banner`, style the checklist, wire it into `bin/macup`

**Files:**
- Modify: `lib/menu.sh:1-12` (add `ui_banner`, add styling flags to `ui_choose_modules`)
- Modify: `bin/macup:187-192` (call `ui_banner` before the interactive-checklist block)
- Test: `tests/menu.bats` (new tests for `ui_banner`)
- Test: `tests/macup.bats` (new tests for banner appearing/not-appearing per invocation mode)

**Interfaces:**
- Produces: `ui_banner` (no args, no return value used) — callable from `bin/macup` or any future caller; reads `$ROOT_DIR/VERSION` and writes a styled box directly to stdout via `gum style`.

- [ ] **Step 1: Write the failing tests**

In `tests/menu.bats`, add these two tests (after the existing `ui_choose_modules` tests, e.g. after the `"ui_choose_modules shows a header explaining space/enter controls"` test):

```bash
@test "ui_banner prints a bordered box with the title and current version" {
  run ui_banner

  [ "$status" -eq 0 ]
  grep -q -- "--border rounded" "$MACUP_CALL_LOG"
  [[ "$output" == *"macup"* ]]
  [[ "$output" == *"$(cat "$ROOT_DIR/VERSION")"* ]]
}

@test "ui_choose_modules uses the macup accent color" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages"

  run ui_choose_modules

  [ "$status" -eq 0 ]
  grep -q -- "--cursor.foreground 212" "$MACUP_CALL_LOG"
  grep -q -- "--selected.foreground 212" "$MACUP_CALL_LOG"
}
```

In `tests/macup.bats`, add these two tests (near the existing `"macup works under macOS's stock bash 3.2 (no mapfile)"` test, which already exercises the bare-interactive path with `GUM_CHOOSE_RESULT` set):

```bash
@test "macup shows the banner before the interactive checklist" {
  export GUM_CHOOSE_RESULT="homebrew: Install Homebrew packages"

  run "$MACUP_BIN"

  [ "$status" -eq 0 ]
  grep -q -- "--border rounded" "$MACUP_CALL_LOG"
}

@test "macup --all does not show the banner" {
  run "$MACUP_BIN" --all

  [ "$status" -eq 0 ]
  ! grep -q -- "--border rounded" "$MACUP_CALL_LOG"
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/menu.bats tests/macup.bats -f "banner|accent color"`
Expected: FAIL — `ui_banner` doesn't exist yet (`command not found`), `ui_choose_modules` has no `--cursor.foreground`/`--selected.foreground` flags yet, and `bin/macup` never calls anything with `--border rounded`.

- [ ] **Step 3: Add `ui_banner` and style `ui_choose_modules` in `lib/menu.sh`**

Replace the current `ui_choose_modules` function (lines 3-12) with:

```bash
ui_banner() {
  local version box_width=32 term_width left_margin=0
  version="$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "?")"
  term_width="$(tput cols 2>/dev/null || echo 80)"
  if [ "$term_width" -gt "$((box_width + 4))" ]; then
    left_margin=$(( (term_width - box_width - 4) / 2 ))
  fi
  gum style \
    --border rounded \
    --border-foreground 212 \
    --align center \
    --width "$box_width" \
    --margin "1 $left_margin" \
    --padding "1 2" \
    "macup" "Bootstrap your Mac dev setup" "v$version"
}

ui_choose_modules() {
  gum choose --no-limit \
    --header "Select modules (space to toggle, enter to confirm):" \
    --header.foreground 212 \
    --cursor.foreground 212 \
    --selected.foreground 212 \
    "homebrew: Install Homebrew packages from the Brewfile" \
    "shell: Install Oh My Zsh + Powerlevel10k" \
    "dotfiles: Symlink dotfiles into \$HOME" \
    "macos-defaults: Apply curated macOS system defaults" \
    "github: Set up a GitHub SSH key and gh CLI auth" \
    | sed -E 's/:.*$//'
}
```

- [ ] **Step 4: Wire `ui_banner` into `bin/macup`'s interactive path**

In `bin/macup`, change (currently lines 187-192):

```bash
  if [ "${#modules[@]}" -eq 0 ]; then
    modules=()
    while IFS= read -r line; do
      [ -n "$line" ] && modules+=("$line")
    done < <(ui_choose_modules)
  fi
```

to:

```bash
  if [ "${#modules[@]}" -eq 0 ]; then
    ui_banner
    modules=()
    while IFS= read -r line; do
      [ -n "$line" ] && modules+=("$line")
    done < <(ui_choose_modules)
  fi
```

(`ui_banner` is a plain statement here, not inside the `<(...)` process substitution — its output must never enter the pipe that gets `sed`-parsed into module names.)

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `bats tests/menu.bats tests/macup.bats -f "banner|accent color"`
Expected: PASS (4 tests)

- [ ] **Step 6: Run the full suite and shellcheck to check for regressions**

Run: `bats tests/` — expected: all tests pass (119 existing + 4 new = 123)
Run: `shellcheck bin/macup lib/*.sh` — expected: no output

- [ ] **Step 7: Commit**

```bash
git add lib/menu.sh bin/macup tests/menu.bats tests/macup.bats
git commit -m "feat: add bordered banner and accent styling to interactive checklist"
```
