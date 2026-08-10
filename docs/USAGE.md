# macup Usage Guide

The README covers installation and a quick flag reference. This guide
walks through common scenarios end-to-end, with example commands and
what you'll actually see on screen.

A note on the transcripts below: `macup`'s own status lines (`==> ...`)
are shown verbatim — that's exactly what `log_info`/`log_warn` print.
Interactive prompts are rendered by [`gum`](https://github.com/charmbracelet/gum)
as styled boxes, not plain text; the transcripts show them as `? <prompt>: <what you'd type>`
for readability, not as literal terminal output.

## Contents

- [First run on a fresh Mac](#first-run-on-a-fresh-mac)
- [Preview before you commit: `--dry-run`](#preview-before-you-commit---dry-run)
- [Non-interactive / scripted setup](#non-interactive--scripted-setup)
- [Running just one or two modules](#running-just-one-or-two-modules)
- [Re-running later to stay in sync](#re-running-later-to-stay-in-sync)
- [Using your own dotfiles repo](#using-your-own-dotfiles-repo)
- [Adding your own Homebrew packages](#adding-your-own-homebrew-packages)
- [Git identity in depth](#git-identity-in-depth)
- [GitHub SSH + auth in depth](#github-ssh--auth-in-depth)
- [Reading the log file](#reading-the-log-file)
- [Flag and module reference](#flag-and-module-reference)

---

## First run on a fresh Mac

```sh
brew tap dicksonk/macup
brew install macup
macup
```

With no flags or module names, `macup` shows an interactive checklist
(five modules: `homebrew`, `shell`, `dotfiles`, `macos-defaults`,
`github`) — space to toggle, enter to confirm. If this is your first
run and `~/.config/macup/config` doesn't exist yet, you'll also be
asked once whether to create it from the bundled example:

```
? No config found. Create default config at ~/.config/macup/config? [y/N]
```

Say yes if you want to persist a custom `DOTFILES_REPO`/`EXTRA_BREWFILE`
across future runs (see [Using your own dotfiles repo](#using-your-own-dotfiles-repo)
and [Adding your own Homebrew packages](#adding-your-own-homebrew-packages)
below) — otherwise it's safe to decline and every module still runs with
its bundled defaults.

Selected modules always run in a fixed order — `homebrew` → `shell` →
`dotfiles` → `macos-defaults` → `github` — regardless of the order you
picked them in, since later modules can depend on earlier ones (see
[Git identity in depth](#git-identity-in-depth)). Say you selected all
five; a full run looks roughly like this:

```
==> Running homebrew
==> Homebrew not found, installing
  [... official Homebrew installer output ...]
? Trust 2 Homebrew tap(s) required by your Brewfile: homebrew/autoupdate martido/homebrew-graph? [y/N]
==> Trusted tap homebrew/autoupdate
==> Trusted tap martido/homebrew-graph
==> Running brew bundle with default Brewfile
  [... brew installs git, gh, gum, bat, fzf, ripgrep, fd, jq, wget, tmux,
       neovim, iterm2, visual-studio-code, rectangle ...]
==> Running shell
==> Installing Oh My Zsh
  [... official Oh My Zsh installer output ...]
==> Cloning Powerlevel10k
==> Set Terminal.app font to MesloLGS Nerd Font Mono
==> Created iTerm2 dynamic profile with MesloLGS Nerd Font Mono and set as default
==> Running dotfiles
==> Linked /Users/you/.zshrc -> /opt/homebrew/opt/macup/libexec/dotfiles/zshrc
==> Linked /Users/you/.p10k.zsh -> /opt/homebrew/opt/macup/libexec/dotfiles/p10k.zsh
==> Linked /Users/you/.gitconfig -> /opt/homebrew/opt/macup/libexec/dotfiles/gitconfig
? Git user.name: Ada Lovelace
? Git user.email: ada@example.com
==> Wrote git identity to /Users/you/.gitconfig.local
==> Running macos-defaults
==> Set com.apple.finder AppleShowAllExtensions = true
  [... one line per setting that wasn't already applied ...]
==> Running github
==> Generating SSH key
Public key:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII... ada@example.com
==> Public key copied to clipboard (if pbcopy is available)
==> No token found — create a classic token at https://github.com/settings/tokens with the "repo", "read:org", "gist", and "admin:public_key" scopes
? GitHub Personal Access Token: ************************************
==> Public key already registered with GitHub, skipping

==> Summary:
==>   succeeded: homebrew shell dotfiles macos-defaults github
==> Full log: /Users/you/.cache/macup/logs/2026-08-04T091530.log
```

Notice the `github` module never asked for an email — it reused
`ada@example.com` from the git identity `dotfiles` had just written a
few steps earlier. That's the module ordering paying off.

Two other things happened in that `homebrew` run worth calling out:

- **Tap trust.** Homebrew versions with tap trust checks refuse to load
  formulae/casks from a tap that hasn't been explicitly trusted, which
  silently breaks `brew bundle` for any custom `tap "..."` line in your
  Brewfile(s). Before bundling, `homebrew` extracts every tap your
  Brewfile(s) declare, checks which aren't yet trusted, and (in an
  interactive run) prompts once to trust all of them in one go. In a
  non-interactive run (`--all` or explicit module names) it can't safely
  prompt, so it logs a warning naming the untrusted taps instead and
  continues — re-run interactively later to trust them.
- **Sudo credentials.** If `brew bundle` needs `sudo` (some casks do) and
  a password prompt caches your credentials, a background refresh loop
  keeps them alive for the rest of the `brew bundle` run so you're not
  asked twice for a single long install. It never forces an initial
  prompt on its own — it only keeps an already-cached credential from
  expiring.

## Preview before you commit: `--dry-run`

Add `--dry-run` to any invocation to see exactly what would happen —
every module still checks real system state (what's installed, what's
already linked, what's already configured), but nothing actually
changes, and no prompt ever blocks the run:

```sh
macup --dry-run --all
```

```
==> Dry run: no changes will be made
==> macup run: macup --dry-run --all
==> Running homebrew
==> [dry-run] would run: brew bundle --file=/opt/homebrew/opt/macup/libexec/Brewfile
==> Running shell
==> Oh My Zsh already installed, skipping
==> Powerlevel10k already installed, skipping
==> Terminal.app font already set to MesloLGS Nerd Font Mono, skipping
==> iTerm2 default profile already set to the macup Nerd Font profile, skipping
==> Running dotfiles
==> /Users/you/.zshrc already up to date
==> [dry-run] would skip git identity setup (non-interactive, no identity configured)
==> Running macos-defaults
==> com.apple.finder AppleShowAllExtensions already set to true, skipping
==> [dry-run] would create /Users/you/Screenshots
==> [dry-run] would restart Finder and SystemUIServer
==> Running github
==> [dry-run] would generate an SSH key at /Users/you/.ssh/id_ed25519, then check/register it with GitHub

==> Summary:
==>   succeeded: homebrew shell dotfiles macos-defaults github
==> (dry run — nothing was actually changed)
==> Full log: /Users/you/.cache/macup/logs/2026-08-04T093012.log
```

Two things `--dry-run` genuinely can't predict, by design: `brew
bundle`'s exact package-by-package plan (it reports the command it
would run, not a package diff — `brew bundle` has no dry-run mode of
its own to delegate to), and the contents of an external `DOTFILES_REPO`
that hasn't been cloned yet (it can report that it *would* clone the
repo, but not which files are inside it).

## Non-interactive / scripted setup

For provisioning scripts, CI images, or just skipping the checklist:

```sh
macup --all                    # every module, no prompts about which to run
macup homebrew dotfiles        # just these two, still non-interactive
```

Passing `--all` or any module name makes the run non-interactive — no
module checklist, and (if no config file exists yet) no "create a
config?" prompt either; it silently proceeds with bundled defaults. If
you need a custom `DOTFILES_REPO`/`EXTRA_BREWFILE` in a non-interactive
run, either create `~/.config/macup/config` ahead of time (by hand, or
by running `macup` interactively once) or pass `--dotfiles-repo=`/
`--brewfile=` on the command line (see below) — both work without any
config file at all.

The `dotfiles` module's git identity prompt is likewise auto-skipped
in this mode (with a warning) if `~/.gitconfig.local` isn't already
configured — there's no TTY to answer it. Pass `--skip-git-identity`
to silence the warning, or preconfigure the identity ahead of time.
See [Git identity in depth](#git-identity-in-depth) for details.

## Running just one or two modules

Modules are independent — each is safe to run alone, any time:

```sh
macup macos-defaults           # just re-apply the curated system settings
macup dotfiles github          # just re-link dotfiles and check GitHub auth
```

`github` in particular is designed to work standalone: it defaults its
SSH key's email to whatever's in `~/.gitconfig.local` if `dotfiles` has
already run at some point, but falls back to asking if not — you don't
have to run modules in any particular combination.

## Re-running later to stay in sync

Every module is idempotent — it checks live system state first and only
changes what's actually missing or different. Re-running `macup --all`
after you've already set everything up mostly just prints "already
..., skipping" lines and finishes in a few seconds:

```
==> Running homebrew
==> Running brew bundle with default Brewfile
  [... brew reports everything already installed ...]
==> Running shell
==> Oh My Zsh already installed, skipping
==> Powerlevel10k already installed, skipping
==> Terminal.app font already set to MesloLGS Nerd Font Mono, skipping
==> iTerm2 default profile already set to the macup Nerd Font profile, skipping
==> Running dotfiles
==> /Users/you/.zshrc already up to date
==> /Users/you/.p10k.zsh already up to date
==> /Users/you/.gitconfig already up to date
==> Git identity already configured in /Users/you/.gitconfig.local, skipping
==> Running macos-defaults
==> com.apple.finder AppleShowAllExtensions already set to true, skipping
  [... one "already set" line per setting ...]
==> Running github
==> SSH key already exists at /Users/you/.ssh/id_ed25519, skipping generation
==> gh already authenticated, skipping
==> SSH key already registered with GitHub, skipping

==> Summary:
==>   succeeded: homebrew shell dotfiles macos-defaults github
==> Full log: /Users/you/.cache/macup/logs/2026-08-04T140203.log
```

This is also why `--dry-run` is safe to run as often as you like — it's
the same idempotency checks, just with the mutating half turned off.

## Using your own dotfiles repo

By default, `dotfiles` symlinks the bundled `.zshrc`/`.p10k.zsh`/
`.gitconfig` from macup's own install directory. Point it at your own
repo instead — a one-off override:

```sh
macup --dotfiles-repo=git@github.com:you/dotfiles.git dotfiles
```

or persist it in `~/.config/macup/config`:

```sh
DOTFILES_REPO=git@github.com:you/dotfiles.git
```

First run clones it into `~/.cache/macup/dotfiles-repo`; later runs
`git pull --ff-only` that same clone instead of re-cloning. Every
top-level file in the repo gets symlinked into `$HOME` as `.<filename>`
— `zshrc` → `~/.zshrc`, `gitconfig` → `~/.gitconfig`, and so on, exactly
like the bundled set. Files whose names already start with a `.` (e.g.
a repo that already contains literal `.zshrc` rather than `zshrc`) won't
match — macup's own convention expects plain filenames and adds the
leading dot itself.

Prefer `git@host:...` (SSH) over an `https://user:token@host/...` URL
if you can — SSH auth is what the `github` module sets up for you, and
credentials embedded in an HTTPS URL, while never logged by macup
(embedded credentials are redacted before any log line), still sit in
your shell history and `~/.config/macup/config` in plain text.

## Adding your own Homebrew packages

The bundled `Brewfile` covers a curated general-purpose set (see the
[README](../README.md) or the repo's `Brewfile` for the exact list).
To layer your own packages on top without forking it:

```sh
macup --brewfile=/Users/you/Brewfile.personal homebrew
```

or persist it:

```sh
EXTRA_BREWFILE=/Users/you/Brewfile.personal
```

`homebrew` always runs the bundled `Brewfile` first, then — if set and
the file exists — runs your `EXTRA_BREWFILE` as a second, additive
`brew bundle` pass. If the path is set but the file's missing, that's a
non-fatal warning (`EXTRA_BREWFILE set but not found: ...`), not a
failure — the bundled install still completes.

If your extra packages live in their own git repo instead of a local
file, point `--brewfile-repo=<url>` (or persisted `EXTRA_BREWFILE_REPO`)
at it:

```sh
macup --brewfile-repo=git@github.com:you/my-brewfiles.git homebrew
```

First run clones it into `~/.cache/macup/brewfile-repo`; later runs
`git pull --ff-only` that same clone, the same caching pattern as
`DOTFILES_REPO`. Once `EXTRA_BREWFILE_REPO` is set, `EXTRA_BREWFILE`
is reinterpreted as a path *within that repo* rather than a local path
— e.g. `EXTRA_BREWFILE=work/Brewfile.personal` resolves to
`~/.cache/macup/brewfile-repo/work/Brewfile.personal` — and defaults to
`Brewfile` at the repo root if left unset.

To skip the bundled `Brewfile` entirely for a run and install only your
own — say, on a machine that shouldn't get the general-purpose set —
add `--brewfile-only`/`-bo`:

```sh
macup --brewfile-repo=git@github.com:you/my-brewfiles.git --brewfile-only homebrew
```

It's a per-invocation flag, not something you persist in the config
file.

## Git identity in depth

`dotfiles` manages one thing beyond symlinking: a per-machine
`~/.gitconfig.local` holding `git config user.name`/`user.email`. It's
a plain file — never symlinked, never part of any repo (bundled or
external) — created via `git config -f`, and included from the bundled
`~/.gitconfig` via:

```ini
[include]
	path = ~/.gitconfig.local
```

The first time either value is unset, you're prompted once:

```
? Git user.name: Ada Lovelace
? Git user.email: ada@example.com
==> Wrote git identity to /Users/you/.gitconfig.local
```

Every later run reuses it silently (`Git identity already configured
..., skipping`). If only one of the two is already set (say you set
`user.name` by hand), you're only prompted for the missing one — the
existing value is preserved, not overwritten.

Leaving either prompt blank now skips writing the identity entirely
(`Skipped git identity setup`) rather than writing a partial identity
with an empty name or email — you'll be re-prompted on the next run.

Pass `--skip-git-identity` to skip the prompt outright, whether or not
you're running interactively:

```
==> Skipping git identity setup (--skip-git-identity)
```

Non-interactive runs (`--all`, or naming modules directly, e.g. `macup
dotfiles`) can't show a prompt — there's no TTY to answer `gum input`
— so if no identity is configured yet and `--skip-git-identity` wasn't
passed, `dotfiles` skips the prompt automatically and logs a warning
instead of hanging:

```
==> Skipping git identity setup: no identity configured and running non-interactively (pass --skip-git-identity to silence this, or configure /Users/you/.gitconfig.local directly)
```

This only applies when using the **bundled** dotfiles (`DOTFILES_REPO`
unset) — an external `DOTFILES_REPO` is assumed to manage its own git
identity however it likes, and `dotfiles` never touches
`~/.gitconfig.local` in that case.

## GitHub SSH + auth in depth

```sh
macup github
```

1. **SSH key.** If `~/.ssh/id_ed25519` doesn't exist, one is generated
   (`ssh-keygen -t ed25519`, no passphrase — a deliberate convenience
   trade-off worth knowing about) using your git identity's email as
   the key comment if `dotfiles` already set one, otherwise you're
   asked. The public key is printed and copied to your clipboard either
   way.
2. **Auth.** If `gh` isn't already authenticated, you're pointed at
   https://github.com/settings/tokens to create a **classic** Personal
   Access Token with the `repo`, `read:org`, `gist`, and
   `admin:public_key` scopes (the first three are `gh`'s own minimum
   requirement for `--with-token` login; the last is needed for the
   next step), then prompted for it with masked input:

   ```
   ==> No token found — create a classic token at https://github.com/settings/tokens with the "repo", "read:org", "gist", and "admin:public_key" scopes
   ? GitHub Personal Access Token: ************************************
   ```

   The token is never echoed, never logged, and never written to any
   macup file — it goes straight to `gh auth login --with-token` over
   stdin, and `gh` takes over storing it securely from there. If you'd
   rather not paste a token, run `gh auth login` yourself first (its own
   interactive browser flow) — `macup github` only prompts when `gh
   auth status` fails.
3. **Registration.** Once authenticated, the SSH key is checked against
   your GitHub account (`gh api user/keys`) and auto-uploaded via `gh
   ssh-key add` if it isn't there yet — no manual "paste your key into
   Settings" step. If the upload fails for any reason (e.g. a token
   without `admin:public_key`), that's a warning, not a failure — the
   public key was already printed and copied above as a fallback.

## Reading the log file

Every run writes its own status lines to
`~/.cache/macup/logs/<timestamp>.log` — one file per run, plain text,
no ANSI color codes, no rotation. The path is printed at the end of
every run's summary. It captures the same `==> ...` lines you saw on
screen (including `[dry-run]` lines), plus a header recording exactly
how it was invoked:

```
[2026-08-04T09:15:30] [INFO] macup run: macup --all
[2026-08-04T09:15:30] [INFO] Running homebrew
[2026-08-04T09:15:31] [INFO] Running brew bundle with default Brewfile
...
```

It does **not** capture raw subcommand output (`brew`'s own install
progress, `git clone`'s progress, etc.) or `gum`'s interactive
rendering — only macup's own status lines, so it stays small and
readable rather than becoming a full terminal transcript. If you're
debugging a run that failed partway through, check the summary's
`failed: ...` line for which module, then re-run just that module
(optionally with `--dry-run` first) to see more.

## Flag and module reference

| Flag | Short | Effect |
|---|---|---|
| `--all` | `-a` | Run all five modules, non-interactively |
| `--dry-run` | `-n` | Preview actions without making any changes or prompting |
| `--dotfiles-repo=<url>` | `-d <url>` | Override `DOTFILES_REPO` for this run only |
| `--brewfile=<path>` | `-b <path>` | Override `EXTRA_BREWFILE` for this run only |
| `--brewfile-repo=<url>` | `-br <url>` | Override `EXTRA_BREWFILE_REPO` for this run only |
| `--brewfile-only` | `-bo` | Skip the bundled `Brewfile`, run only the extra one |
| `--skip-git-identity` |  | Skip prompting for/writing git `user.name`/`user.email` in the `dotfiles` module |
| `--help` | `-h` | Show usage and exit |
| `--version` | `-v` | Print the installed version and exit |

`--dry-run` combines with any of the above (`--dry-run --all`,
`--dry-run --dotfiles-repo=... dotfiles`, or bare `--dry-run` for an
interactive-selection-but-non-mutating preview).

| Module | What it does |
|---|---|
| `homebrew` | Installs Homebrew if missing, trusts any untrusted taps your Brewfile(s) declare, runs `brew bundle` on the default `Brewfile` (unless `--brewfile-only`), then `EXTRA_BREWFILE`/`EXTRA_BREWFILE_REPO` if set |
| `shell` | Installs Oh My Zsh + Powerlevel10k if missing; sets Terminal.app/iTerm2's default font to a Nerd Font for Powerlevel10k's icons |
| `dotfiles` | Symlinks dotfiles (bundled or from `DOTFILES_REPO`) into `$HOME`; manages `~/.gitconfig.local` |
| `macos-defaults` | Applies a curated set of Finder/keyboard/trackpad/screenshot settings |
| `github` | Generates an SSH key, authenticates `gh` via a PAT, and registers the key with GitHub |

Passing any module name(s) as positional arguments (`macup homebrew
github`) runs just those, non-interactively, in the fixed order above
regardless of the order you listed them.
