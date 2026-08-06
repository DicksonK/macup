# Terminal Nerd Font + Homebrew Tap Trust — Design Spec

## Purpose

Two independent, unrelated gaps reported after using `macup`:

1. **Nerd Font not applied.** The Brewfile already installs Nerd Font
   casks (`font-hack-nerd-font`, `font-meslo-lg-nerd-font`), and
   `dotfiles/p10k.zsh` assumes one is active
   (`POWERLEVEL9K_MODE=nerdfont-complete`), but nothing ever sets either
   font as Terminal.app's or iTerm2's actual active font — so
   Powerlevel10k's icons render as broken glyphs until the user manually
   changes their terminal preferences.
2. **Homebrew tap trust silently blocks installs.** Homebrew 6.0
   (2026-06-11) requires taps to be explicitly trusted before their
   formulae/casks are usable; the bundled `Brewfile` taps
   (`databricks/tap`, `homebrew/autoupdate`, `martido/homebrew-graph`)
   are untrusted by default on a fresh machine, so `brew bundle` silently
   skips everything from them with no clear error pointing back to
   `macup`.

(A third reported issue — VS Code extensions from the Brewfile not
installing — is explicitly out of scope for this spec; set aside
pending a reproducible symptom.)

## Non-Goals

- Does not attempt to fix the VS Code extension issue.
- Does not add a general-purpose "which fonts are installed" abstraction
  — the two Nerd Font casks already in the Brewfile are the only fonts
  this spec cares about; font choice (MesloLGS) was already decided.
- Does not rely on Homebrew's `tap "x/y", trusted: true` Brewfile DSL
  keyword — verified directly against the installed Homebrew 6.0.15 that
  this option is currently silently dropped for taps without a custom
  remote URL (a known upstream bug: matches
  `Homebrew/brew#22668`). Tap trust is handled entirely via explicit
  `brew tap`/`brew trust --tap` calls in `lib/homebrew.sh` instead.
- Does not touch `macos_defaults.sh` — despite also using `defaults
  write`, this is scoped to `lib/shell.sh` (font) and `lib/homebrew.sh`
  (tap trust) specifically, matching where the rest of each concern
  already lives.
- Font-configuration failures (e.g. denied Automation permission for
  Terminal.app scripting) are non-fatal — logged as a warning, `shell`
  module still returns success if everything else succeeded. This is
  cosmetic polish, not core functionality.

## Design

### 1. Nerd Font: `lib/shell.sh`

Verified facts (checked directly on a real machine with the Brewfile's
`font-meslo-lg-nerd-font` cask installed, not assumed):

- Registered font family: **`MesloLGS Nerd Font Mono`** (confirmed via
  `system_profiler SPFontsDataType`) — not `MesloLGS NF`, which is a
  different, separately-distributed font from Powerlevel10k's own docs.
- PostScript name of the regular weight: **`MesloLGSNFM-Regular`**
  (confirmed via `fc-scan --format %{postscriptname}` — do not assume
  this matches the `.ttf` filename convention; it doesn't).
- Terminal.app's AppleScript `set font name of default settings to
  "<family name>"` accepts the **family** name as input and resolves it
  correctly — confirmed by setting it live and reading back
  (`get font name of default settings` then returns the **PostScript**
  name, `MesloLGSNFM-Regular`). Change was reverted after verification.

```bash
: "${MACUP_ITERM_APP_PATH:=/Applications/iTerm.app}"

_configure_terminal_font() {
  local font_family="MesloLGS Nerd Font Mono"
  local font_ps_name="MesloLGSNFM-Regular"
  local iterm_guid="B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10"

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

Called at the end of `run_shell`, after all existing plugin-clone steps
— font config is meaningless before Oh My Zsh/Powerlevel10k exist, but
doesn't actually depend on their install succeeding, so it always runs
(matches this function's non-fatal philosophy: even if a plugin clone
failed, still try to fix the font).

**Why a Dynamic Profile + `Default Bookmark Guid` pointer, not a direct
rewrite of iTerm2's live default profile:** iTerm2's actual default
profile lives inside an array of dicts in a large, live preferences
plist, keyed by a runtime-assigned GUID. Patching one entry inside that
array safely (without either corrupting other user customizations or
racing a running iTerm2 process that might overwrite the file on next
quit) requires plist-to-JSON-to-plist round-tripping and quitting the
app first — a fundamentally riskier operation than anything else in this
codebase does (`macos_defaults.sh` only ever writes single scalar keys).
A Dynamic Profile is iTerm2's own documented, hot-reloaded mechanism for
exactly this; combined with `Default Bookmark Guid`, new windows use it
by default — the same practical outcome, additively.

**Why Terminal.app gets its live default modified directly:** Terminal
exposes `font name of default settings` directly via its own AppleScript
dictionary — a single, safe, well-supported write, no plist surgery
needed.

**Automation permission caveat:** the first time `osascript` sends
Terminal.app an Apple Event from outside itself, macOS may prompt for
Automation permission (System Settings → Privacy & Security →
Automation). If denied, `_configure_terminal_font` logs a warning and
continues — non-fatal, matching this feature's cosmetic-polish status.
This needs a new item in `README.md`'s manual verification checklist,
since it's real system-mutating, permission-gated behavior bats can't
exercise.

### 2. Homebrew tap trust: `lib/homebrew.sh`

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

Called from `run_homebrew` right after `brew_bin` is resolved (installed
or freshly-installed), before the first `brew bundle` call — so tapped
formulae/casks are actually usable by the time `brew bundle` processes
them. `EXTRA_BREWFILE` is included, matching `run_homebrew`'s existing
handling of both Brewfiles.

**Why not the `trusted: true` Brewfile DSL keyword:** verified directly
(see Non-Goals) that it's currently a silent no-op for the bundled
Brewfile's taps on the installed Homebrew version. The `Brewfile`'s
`tap "user/repo"` lines are left as plain, undecorated tap declarations
— adding a currently-inert `trusted: true` would be misleading. This
comment doesn't need to live in the Brewfile itself (Brewfiles aren't
meant to carry prose); it lives here and in the implementation's
commit message.

**Why one confirm prompt, not silent auto-trust, and not skipped under
`--all`:** matches this codebase's existing precedent for essential
first-time setup with no safe default (`lib/dotfiles.sh`'s git-identity
prompt runs regardless of `MACUP_NONINTERACTIVE`) — unlike the
config-creation prompt in `lib/common.sh`, which is genuinely optional
and skipped non-interactively. Trusting the taps your own Brewfile
declares is a precondition for the tool doing its actual job under
`--all`, not an optional convenience — so it always prompts once, then
is silently skipped on every later run once trusted (idempotent, via the
`trust.json` check).

## Testing

- `tests/shell.bats`: new tests for `_configure_terminal_font` /
  `run_shell`'s font-config step — dry-run reporting (Terminal.app and
  iTerm2 present via `MACUP_ITERM_APP_PATH` pointed at a fake dir under
  `$TEST_HOME`), already-configured skip (stub `osascript` returns the
  target PostScript name; fake `defaults` store pre-seeded with the
  target GUID), and the real-write path (asserts the dynamic profile
  JSON file is created with correct content, `defaults write` called
  with the right GUID, `osascript` invoked with the right family name).
  Requires a new `tests/test_helper/stubs/osascript` stub (same generic
  `echo "$* " >> $MACUP_CALL_LOG; exit ${OSASCRIPT_EXIT:-0}` pattern as
  the existing `killall`/`ssh-keygen` stubs), plus an `OSASCRIPT_RESULT`
  env var the stub echoes back for `get font name of default settings`
  calls (mirroring `GUM_INPUT_RESULT`'s pattern in the `gum` stub).
- `tests/homebrew.bats`: new tests for `_trust_brewfile_taps` /
  `run_homebrew`'s trust step — tap extraction from both Brewfiles,
  already-trusted skip (fake `trust.json` in `$TEST_HOME/.homebrew/`),
  confirm-and-trust path (`brew tap`+`brew trust --tap` both called per
  untrusted tap), decline path (`ui_confirm` returns failure, taps not
  trusted, module still succeeds), dry-run reporting.
- `README.md`: add a manual verification checklist item for the
  Automation-permission-gated Terminal.app font change (bats can't
  exercise a real permission prompt).
