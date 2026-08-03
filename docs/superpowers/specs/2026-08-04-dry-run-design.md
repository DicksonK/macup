# Dry Run — Design Spec

## Purpose

`mac-up` currently has no way to preview what a run would do without
actually doing it. This spec adds `mac-up --dry-run`: every module still
runs its real, read-only detection/idempotency logic (what's already
installed, what's already linked, what's already configured), but every
actual mutation (installing packages, writing files, symlinking, running
`defaults write`, authenticating, restarting apps) is replaced with a
`[dry-run] would ...` report line instead of being executed. Interactive
prompts are skipped entirely in dry-run mode — the point of a dry run is
a fast, non-interactive preview, and no prompt's answer is needed to
describe what *would* happen.

## Non-Goals

- Does not attempt to predict `brew bundle`'s per-package plan (which
  formulae/casks are already installed vs would be newly installed) —
  reports the intended command (`brew bundle --file=...`) generically,
  not a package-by-package diff. `brew bundle` itself has no built-in
  dry-run mode to delegate to.
- Does not partially simulate GitHub authentication. If `gh` isn't
  already authenticated, dry-run cannot know what a real auth session
  would find registered on the account — it reports the auth step and
  skips the registration check for that run, rather than guessing.
- `--dry-run` does not imply `--all` or non-interactive module
  *selection* — it's orthogonal to `MAC_UP_NONINTERACTIVE`. Running
  `mac-up --dry-run` alone still shows the interactive module checklist;
  only the selected modules' *execution* becomes a preview.

## Design

### `lib/common.sh` additions

```bash
is_dry_run() {
  [ "${MAC_UP_DRY_RUN:-0}" = "1" ]
}

dry_run_report() {
  log_info "[dry-run] would $1"
}
```

`dry_run_report` goes through `log_info`, so dry-run output is captured
by the existing per-run log file (`~/.cache/mac-up/logs/...`) exactly
like any other status line — no special-casing needed there.

### `bin/mac-up` wiring

- New `--dry-run` case in the CLI flag-parsing loop, setting a local
  `dry_run=true` (parallel to the existing `run_all` local), added to
  `usage()`'s options list.
- After the flag-parsing loop (same place `MAC_UP_NONINTERACTIVE` is
  computed and exported today), export `MAC_UP_DRY_RUN` (`1` or `0`)
  based on that local.
- Immediately after `init_log_file` and the run-header log line, if
  dry-run: `log_info "Dry run: no changes will be made"`.
- In `run_selected_modules`'s summary, if dry-run: add
  `log_info "(dry run — nothing was actually changed)"` alongside the
  existing `succeeded:`/`failed:` lines, so the summary can't be
  mistaken for a real run's result.

### Per-module treatment

**Guiding principle:** every module's existing read-only
detection/idempotency check (does the binary/file/theme/setting/key
already exist or match) keeps running for real in dry-run mode — that's
what makes the report accurate. Only the point where the module would
otherwise *mutate* something, or *prompt* for input, gets guarded:

```bash
if is_dry_run; then
  dry_run_report "<description of the action>"
else
  <the real action, unchanged from today>
fi
```

#### `lib/homebrew.sh`

Three mutation points, each wrapped: the curl-piped Homebrew install
(the whole `if [ -z "$brew_bin" ]; then ... fi` install block), the
default `brew bundle --file="$ROOT_DIR/Brewfile"` call, and the optional
`brew bundle --file="$EXTRA_BREWFILE"` call. Because the curl-piped
installer's command substitution `$(curl -fsSL ...)` would otherwise
execute the download as soon as bash evaluates the command line — before
any dry-run check could intervene — the `if is_dry_run ... else ...`
guard must wrap the *entire* install invocation, not just the outer
command, so the `curl` itself never runs in dry-run mode. If Homebrew
isn't installed and this is a dry run, `brew_bin` stays empty; the two
`brew bundle` report points must not depend on `$brew_bin` being set (the
report is just the command string, not an actual invocation of it).

#### `lib/shell.sh`

Same curl-piped-installer principle for Oh My Zsh's install script
(currently already wrapped in `ui_spin`, itself skipped entirely in
dry-run rather than spinning over nothing) and for the Powerlevel10k
`git clone --depth=1 ...` (also currently under `ui_spin`).

#### `lib/dotfiles.sh`

- `DOTFILES_REPO` clone/pull (both the `git -C ... pull --ff-only` and
  `git clone` branches) — wrapped, including the `mkdir -p
  "$(dirname "$cache_dir")"` call that currently precedes the clone
  (that's a real mutation too — it's part of the same "set up the
  cache" action, not a separate guard point).
- A target that doesn't exist yet: the `ln -s "$file" "$target"` —
  wrapped.
- A target that exists and doesn't match (needs confirm-and-backup):
  dry-run skips the `ui_confirm` call entirely (no prompt) and reports
  `"prompt to back up and replace $target"` — it does not attempt to
  guess whether the user would say yes or no, since that's an unknowable
  input, not a detectable fact about the filesystem.
- Git identity: if `~/.gitconfig.local` doesn't already have both
  `user.name` and `user.email` set (the existing real check), dry-run
  skips both `ui_input` calls and reports one combined line:
  `"prompt for and write git identity to $identity_file"`. If both are
  already set, the existing `"already configured, skipping"` message is
  unchanged (it's already a report of a no-op, not a mutation).

#### `lib/macos_defaults.sh`

`_defaults_apply`'s single `defaults write "$domain" "$key" "-$type"
"$value"` call is wrapped once inside that shared helper — since every
one of the 11 settings routes through it, this single wrap point covers
all of them, reported as e.g. `"set com.apple.finder
AppleShowAllExtensions = true"` (reusing the same message format the
real path already logs on success). The `current`/`expected` idempotency
comparison above it is unchanged and still runs for real, so an
already-applied setting still reports "already set ..., skipping" in
dry-run too, correctly. The two `killall Finder`/`killall
SystemUIServer` calls at the end are wrapped as one dry-run report
(`"restart Finder and SystemUIServer"`) — no reason to actually restart
Finder for a preview, and doing so would be surprising/unwanted
mid-dry-run. `run_macos_defaults()` also unconditionally runs `mkdir -p
"$HOME/Screenshots"` before any of the above — that's a real filesystem
mutation too (creates the directory if it's genuinely missing) and gets
the same guard, reported as `"create $HOME/Screenshots"`.

#### `lib/github.sh`

- SSH key generation: if `$key_path` doesn't exist, dry-run skips the
  email prompt (the existing `~/.gitconfig.local` default-lookup stays
  real, since it's read-only) and reports one line: `"generate an SSH
  key at $key_path"` — this wrap also covers the `mkdir -p "$HOME/.ssh"`
  and `ssh-add` calls that currently follow `ssh-keygen`, since they're
  all part of the same "create the key" action, not separate guard
  points. The subsequent pubkey-print/clipboard-copy block
  and the registration-check block are both naturally skipped in this
  case, because they're gated on `$key_path.pub` existing — which it
  genuinely doesn't, since dry-run never created it. This is intentional,
  not a gap: reporting a registration status for a key that was never
  generated would be fabricated information.
- The pubkey-print/clipboard-copy block (`cat`, `pbcopy`) is **not**
  guarded when the key already existed before this run — it's reading
  and copying an unchanged, pre-existing artifact, not mutating system
  configuration, so it runs the same in dry-run and real mode. (It's
  naturally skipped in the fresh-key dry-run case above only because the
  file genuinely doesn't exist, not because of an explicit guard here.)
- `gh auth status` — always runs for real (read-only query); this is
  what decides which of the next two cases applies.
- If **not** authenticated: dry-run skips the PAT prompt and the real
  `gh auth login --with-token` call, and reports one combined line
  (`"authenticate via a GitHub PAT, then check/register the SSH key with
  GitHub"`) — the registration-check block is skipped entirely for this
  run (it depends on real authentication having happened; a dry run
  cannot fake that response).
- If already authenticated: the registration check (`gh api user/keys`
  — read-only) still runs for real, since it doesn't need dry-run
  protection. Only the mutating `gh ssh-key add` call at the end is
  wrapped, reporting `"upload the SSH key to GitHub via gh ssh-key add"`.

## Testing

No new stub infrastructure is needed. Every module's existing stub
executables (`brew`, `gh`, `git`, `ssh-keygen`, `defaults`, `killall`)
already log their invocations to `$MAC_UP_CALL_LOG` — a dry-run test
asserts a stub command is *absent* from that log (the mutation never
happened) while the corresponding `[dry-run] would ...` line *is*
present in the captured output. `tests/mac_up.bats` gets a case
confirming `mac-up --dry-run --all` produces zero stub invocations for
every mutating command across all five modules, while still reporting
what each would have done.

## Interfaces Summary (for a future implementation plan)

- Produces: `is_dry_run()`, `dry_run_report(description)` in
  `lib/common.sh`.
- Modifies: `bin/mac-up` (`--dry-run` flag, `MAC_UP_DRY_RUN` export,
  startup banner, summary line).
- Modifies: `run_homebrew()`, `run_shell()`, `run_dotfiles()`,
  `run_macos_defaults()` (specifically `_defaults_apply()`), and
  `run_github()` — each gains `is_dry_run`/`dry_run_report` guards at
  its mutation and prompt points, with no change to their existing
  detection/idempotency logic, return-code semantics, or any other
  behavior when `MAC_UP_DRY_RUN` is unset/`0`.
