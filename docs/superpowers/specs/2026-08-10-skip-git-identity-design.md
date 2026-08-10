# Skippable git identity setup

## Problem

`run_dotfiles` (lib/dotfiles.sh:95-115) prompts for `git user.name`/`user.email`
and writes them to `~/.gitconfig.local` whenever no identity is already
configured there. This prompt runs unconditionally — it does not check
`MACUP_NONINTERACTIVE` — so a non-interactive run (`macup -a`, or
`macup dotfiles`) blocks on a `gum input` prompt with no TTY to answer it, and
there is no flag to opt out. The interactive prompt also has no way to
decline: the user must type something.

## Design

### New CLI flag

`--skip-git-identity` (long-only, no short form). Parsed in `bin/macup`
alongside the other options, sets and exports `MACUP_SKIP_GIT_IDENTITY=1`
(default `0`), following the existing pattern for `MACUP_DRY_RUN` /
`MACUP_NONINTERACTIVE`. Documented in `usage()`.

### Behavior in `run_dotfiles`

Replaces the identity block in lib/dotfiles.sh:95-115. Evaluated in this
order:

1. **Already configured** — `user.name` and `user.email` both present in
   `~/.gitconfig.local` → skip silently (unchanged from today).
2. **`--skip-git-identity` passed** → log info that identity setup was
   skipped via the flag; don't write anything.
3. **Dry run** — report what would happen (identity prompt, or that it would
   be skipped per the flag/non-interactive state).
4. **Non-interactive and no identity configured and flag not passed**
   (`MACUP_NONINTERACTIVE=1`, i.e. `-a`/`--all` or explicit module args) →
   log a warning that git identity setup was skipped because there's no TTY
   to prompt, and mention `--skip-git-identity` (to silence the warning) and
   editing `~/.gitconfig.local` directly as options. Do not call `ui_input`.
5. **Otherwise (interactive)** — prompt for name and email as today, but
   change the placeholder/prompt text to indicate blank input skips setup.
   If either comes back blank, skip writing entirely (no partial identity
   file gets written) and log that identity setup was skipped.

### Out of scope

The SSH-key email fallback prompt in lib/github.sh (falls back to asking for
an email when generating a new SSH key and `~/.gitconfig.local` has none) is
unaffected by this flag.

## Testing

Add/update cases in `tests/` covering:

- `--skip-git-identity` skips even when interactive would otherwise prompt.
- Non-interactive run without the flag and without an existing identity
  skips with a warning instead of blocking on `ui_input`.
- Interactive run where blank input is given skips writing the identity
  file.
- Existing "identity already configured" skip path is unchanged.
