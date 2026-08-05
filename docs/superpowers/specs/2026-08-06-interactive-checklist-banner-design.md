# Interactive Checklist Banner + Styling — Design Spec

## Purpose

`macup`'s interactive module checklist (`gum choose`, bare `macup` invocation
with no flags/modules) currently has no visual identity beyond a plain
`--header` line. This spec adds a centered, bordered banner (title,
subtitle, version — reading the same `VERSION` file `macup --version`
already uses) printed above the checklist, plus matching accent-color
styling on the checklist itself, so the interactive experience reads as
one polished screen rather than a bare list.

## Non-Goals

- Does not attempt a literal border *around* the interactive list itself.
  `gum choose`/`gum filter` (the versions available, gum 0.17.0 and
  current upstream as of this writing) have no `--border`/`--align`
  flags — those exist only on `gum style`, which renders static text,
  not `gum choose`'s live Bubble Tea widget. The banner is a separate,
  static, bordered block that sits *above* the list; it does not enclose
  it.
- Does not restyle `ui_confirm`, `ui_input`, or `ui_input_secret` — only
  the module checklist and its accompanying banner. Those prompts keep
  gum's defaults; restyling them wasn't asked for and isn't touched here.
- Does not change `ui_log_step`'s existing `--foreground 212` styling —
  the banner and checklist reuse that same color (212) rather than
  introducing a new palette, so output stays visually consistent.
- Does not fall back to a non-terminal-width-aware layout: on a terminal
  narrower than the banner's fixed width, the banner left-aligns
  (margin computed as 0) rather than overflowing or erroring.

## Design

### `lib/menu.sh`: new `ui_banner` function

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
```

- Reads `$ROOT_DIR/VERSION` the same way `bin/macup`'s `--version` flag
  does (`ROOT_DIR` is already exported by `bin/macup` before any `lib/*.sh`
  file is sourced) — single source of truth, no hardcoded version string.
- `box_width=32` is a fixed content width chosen to comfortably fit the
  longest line ("Bootstrap your Mac dev setup", 29 chars) with padding;
  not computed from content because `gum style --width` needs a fixed
  value up front and the three lines are known/static.
- Centering math: `tput cols` for terminal width, falling back to `80`
  if `tput` fails (e.g. non-terminal `stdin`, matching the pattern
  already used for `GUM_*` env var fallbacks elsewhere in this codebase).
  `+4` accounts for the border+padding gum adds around the `--width`
  content box. If the terminal is too narrow for that plus any positive
  margin, `left_margin` stays `0` (left-aligned, no error, no overflow
  math going negative).

### `lib/menu.sh`: `ui_choose_modules` styling

Add matching accent-color flags to the existing `gum choose` call (header
text, cursor, and selected-item color all use 212, matching the banner's
border and `ui_log_step`'s existing color):

```bash
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

(`--header.foreground` already defaults to `99` per `gum choose --help`;
this just aligns it with the rest of macup's palette instead of gum's
own default.)

### `bin/macup`: call `ui_banner` before the interactive checklist only

In `main()`, immediately before the existing block that invokes
`ui_choose_modules` (the `if [ "${#modules[@]}" -eq 0 ]; then ... done <
<(ui_choose_modules)` block — this only runs when no `--all` flag and no
module names were given, i.e. genuinely interactive mode), add a call to
`ui_banner`:

```bash
  if [ "${#modules[@]}" -eq 0 ]; then
    ui_banner
    modules=()
    while IFS= read -r line; do
```

Critically, `ui_banner` is called as a **plain statement**, not inside
the `<(ui_choose_modules)` process substitution — `ui_banner`'s `gum
style` output must never enter the pipe that `sed`-parses module names,
or it would corrupt the parsed module list. Keeping it a separate
statement writing directly to the real stdout (the terminal), executed
*before* the substitution shell starts, avoids that entirely — no
redirection tricks needed.

`--all` and named-module (`macup homebrew`, etc.) invocations never reach
this block, so the banner only ever appears for genuinely interactive
runs, matching its purpose.

## Testing

- `tests/menu.bats`: new test(s) for `ui_banner` — asserts `gum style` is
  invoked with `--border rounded` and that the call log / output
  contains the literal string `macup` and the current `VERSION` file's
  content (reusing the same `$ROOT_DIR/VERSION` pattern the existing
  `--version` bats test in `tests/macup.bats` already reads).
- `tests/macup.bats`: 
  - one new test confirming the banner appears for a bare interactive
    invocation (`GUM_CHOOSE_RESULT` set, run `macup` with no args —
    same pattern as the existing "works under macOS's stock bash 3.2"
    test — asserting `$output` contains the banner's `gum style` stub
    marker).
  - one new test confirming `macup --all` does **not** show the banner
    (mirrors the existing "does not prompt for config creation" test's
    negative-assertion style: `! grep -q "gum style" "$MACUP_CALL_LOG"`
    — module-name-only assertion needs care since `ui_log_step` also
    calls `gum style`, so the assertion checks for the banner's specific
    `--border rounded` flag rather than any `gum style` call).
