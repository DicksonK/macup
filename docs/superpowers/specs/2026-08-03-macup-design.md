# macup: Mac Setup CLI — Design Spec

## Purpose

`macup` is a CLI tool that bootstraps a fresh Mac to a working dev
environment and can be re-run safely to keep an existing Mac in sync. It
installs Homebrew packages, Oh My Zsh + Powerlevel10k, symlinks dotfiles,
applies a curated set of macOS system defaults, and sets up a GitHub SSH
key + `gh` CLI authentication. It's driven by an interactive TUI menu (or
non-interactive flags for automation) and is distributed via Homebrew.

## Non-Goals

- Not a general-purpose dotfiles manager (no templating engine, no
  per-host profiles) — just symlinking a flat set of files into `$HOME`.
- Not a full declarative system-state tool (no drift detection/reporting
  beyond what each module's idempotency check does).
- Does not manage non-macOS platforms.

## Repositories

Two repos are needed to support Homebrew distribution:

- **`github.com/dicksonk/macup`** — the source repo. Contains the CLI
  script, library modules, the default `Brewfile`, default dotfiles, and
  tests.
- **`github.com/dicksonk/homebrew-macup`** — the Homebrew tap. Contains
  a single formula, `Formula/macup.rb`, that installs `macup` from a
  tagged release tarball of the source repo.

This spec and its implementation plan cover the **source repo**
(`macup`). The tap repo's formula is part of the plan's final task but
is a small, separate artifact.

## Directory Structure (source repo)

```
macup/
├── bin/
│   └── macup                  # entrypoint executable (bash)
├── lib/
│   ├── common.sh                # logging, path resolution, confirm/spin wrappers
│   ├── menu.sh                  # gum-backed interactive checklist
│   ├── homebrew.sh              # brew install + brew bundle (default + extra Brewfile)
│   ├── shell.sh                 # Oh My Zsh + Powerlevel10k install
│   ├── dotfiles.sh              # symlink dotfiles (bundled or external repo)
│   ├── macos_defaults.sh        # `defaults write` tweaks
│   └── github.sh                # SSH key + `gh auth login`
├── Brewfile                     # default/bundled package list
├── dotfiles/                    # default dotfiles (.zshrc, .p10k.zsh, .gitconfig, etc.)
├── macup.conf.example           # example config file
├── tests/
│   ├── test_helper/              # bats-core support + mocks for brew/gh/gum
│   ├── common.bats
│   ├── homebrew.bats
│   ├── dotfiles.bats
│   ├── macos_defaults.bats
│   └── github.bats
└── README.md
```

## Distribution & Path Resolution

The Homebrew formula installs the entire tree above into `libexec`, then
creates `bin/macup` as a symlink to `libexec/bin/macup`. The formula
declares `depends_on "git"`, `depends_on "gum"`, `depends_on "gh"` so
those binaries are guaranteed present when `macup` runs.

Because Homebrew's `bin/macup` is a symlink into the Cellar, `bin/macup`
must resolve its **real** location (not the symlink) to find its sibling
`lib/`, `Brewfile`, and `dotfiles/` directories. `lib/common.sh` provides
a `resolve_script_dir` function that follows the symlink chain (standard
`while [ -h "$SOURCE" ]; do ...; done` pattern) so the exact same script
works both when installed via `brew install macup` and when run directly
from a local git clone (`./bin/macup`), without any environment
variables or hardcoded paths.

## TUI (gum)

`gum` (Charmbracelet) provides all interactive UI. `lib/menu.sh` wraps
each gum call behind a plain function so modules never call `gum`
directly:

- `ui_choose_modules` — `gum choose --no-limit` multi-select checklist
  listing the five modules by name/description; returns the selected
  module names.
- `ui_confirm "<prompt>"` — `gum confirm`, returns 0/1.
- `ui_input "<prompt>" ["<default>"]` — `gum input`, returns typed text.
- `ui_spin "<title>" -- <command...>` — `gum spin` wrapping a long-running
  step (e.g. `brew bundle`) with a spinner.
- `ui_log_step "<message>"` — styled status line (`gum style`) printed
  before/after each module runs, used for both interactive and
  non-interactive modes so output is legible either way.

Running `macup` with no arguments launches `ui_choose_modules`, then runs
each selected module in order (homebrew → shell → dotfiles →
macos_defaults → github), printing a summary at the end.

## Modules

Every module exposes one function, `run_<module>()`, that is idempotent:
it checks live system state first and only mutates what's not already
correct. All modules source `lib/common.sh` for logging and the `ui_*`
helpers.

### `homebrew.sh` — `run_homebrew()`
1. If `/opt/homebrew/bin/brew` (Apple Silicon) or `/usr/local/bin/brew`
   (Intel) is missing, install Homebrew via the official install script.
2. Run `brew bundle --file="$SCRIPT_DIR/Brewfile"` — this is inherently
   idempotent (skips already-installed formulae/casks).
3. If `EXTRA_BREWFILE` is set (from config or `--brewfile=` flag) and the
   file exists, run `brew bundle --file="$EXTRA_BREWFILE"` as a second,
   additive pass. If the path is set but doesn't exist, print a warning
   and skip (non-fatal).

### `shell.sh` — `run_shell()`
1. If `$HOME/.oh-my-zsh` doesn't exist, install Oh My Zsh via its
   official unattended install script (`CHSH=no RUNZSH=no` so it doesn't
   fight with dotfiles symlinking or change the shell mid-run).
2. If `$HOME/.oh-my-zsh/custom/themes/powerlevel10k` doesn't exist,
   `git clone --depth=1` the Powerlevel10k repo into that path.

### `dotfiles.sh` — `run_dotfiles()`
1. Determine the source directory:
   - If `DOTFILES_REPO` is set (config or `--dotfiles-repo=` flag),
     clone/pull it into `~/.cache/macup/dotfiles-repo` and use that as
     the source.
   - Otherwise use the bundled `$SCRIPT_DIR/dotfiles/` directory.
2. For every file in the source directory, symlink it into `$HOME` as
   `.{filename}` (e.g. `dotfiles/zshrc` → `~/.zshrc`). For each target:
   - If it doesn't exist, create the symlink.
   - If it already exists and is a symlink pointing at the source file,
     skip it (already correct — log as "up to date").
   - If it exists and is anything else (a regular file, a directory, or
     a symlink pointing elsewhere), ask `ui_confirm` before overwriting;
     on confirmation, move the existing file aside to
     `<target>.macup-backup` before creating the symlink. On decline,
     skip it and log a warning.

### `macos_defaults.sh` — `run_macos_defaults()`
Applies this curated set, each guarded by a `defaults read` check so
already-applied settings are skipped:
- Finder: show all filename extensions, show hidden files, show
  path bar and status bar.
- Keyboard: fast key repeat rate, disable press-and-hold for accent
  chars (so key repeat works in editors).
- Trackpad: enable tap-to-click.
- Screenshots: save location to `~/Screenshots` (created if missing),
  save as PNG.
- Finder/Save dialogs: expand save and print panels by default.

After applying changes, restart affected apps (`Finder`, `SystemUIServer`)
via `killall`, matching standard practice for these settings to take
effect immediately.

### `github.sh` — `run_github()`
1. If no SSH key exists at `~/.ssh/id_ed25519`, prompt (`ui_input`) for
   an email, generate one with `ssh-keygen -t ed25519 -C "<email>"`, add
   it to the ssh-agent and macOS keychain (`ssh-add --apple-use-keychain`).
2. Print the public key and copy it to the clipboard (`pbcopy`) so it can
   be pasted into GitHub.
3. If `gh` is not authenticated (`gh auth status` fails), run
   `gh auth login` interactively (SSH protocol).

## Configuration

`~/.config/macup/config` is a shell-sourced `key=value` file (created
from `macup.conf.example` on first run if missing, via `ui_confirm`):

```sh
DOTFILES_REPO=              # e.g. git@github.com:dicksonk/dotfiles.git — blank uses bundled dotfiles
EXTRA_BREWFILE=             # e.g. /Users/me/Brewfile.personal — blank means bundled Brewfile only
```

CLI flags `--dotfiles-repo=<url>` and `--brewfile=<path>` override the
config file values for a single run without editing the file.

## CLI Interface

```
macup                          # interactive gum checklist, runs selected modules
macup --all                    # run all modules, non-interactive
macup homebrew dotfiles        # run only the named modules, non-interactive
macup --dotfiles-repo=<url> dotfiles
macup --brewfile=<path> homebrew
macup --help
```

Module names accepted as positional args: `homebrew`, `shell`,
`dotfiles`, `macos-defaults`, `github`. Each hyphenated CLI module name
maps to the file `lib/<name-with-underscores>.sh` and function
`run_<name_with_underscores>()` — only `macos-defaults` differs from its
file/function name (`lib/macos_defaults.sh`, `run_macos_defaults()`); all
others are identical strings.

## Error Handling

- `bin/macup` runs with `set -euo pipefail`; each module function traps
  its own errors and returns a non-zero status rather than letting the
  whole process die mid-module, so `macup --all` can report which
  modules succeeded/failed in its end-of-run summary instead of aborting
  on the first failure.
- Network-dependent steps (Homebrew install, OMZ install, git
  clone/pull, `gh auth login`) print a clear error and continue to the
  next module rather than retrying silently.
- All destructive-ish actions on existing files (dotfile symlinking over
  a non-symlink target) require explicit `ui_confirm` before proceeding.

## Testing

bats-core tests live in `tests/`, one file per module plus `common.bats`.
`tests/test_helper/` provides stub executables for `brew`, `gh`, `gum`,
`git`, `ssh-keygen`, `defaults` placed early on `PATH` during tests, so
module logic (idempotency checks, path resolution, config parsing, flag
parsing) is verified without touching the real system. System-mutating
behavior (does `defaults write` actually change the setting, does OMZ
actually install) is verified manually on a real or VM Mac, as noted in
the README.

## Homebrew Formula (tap repo)

`homebrew-macup/Formula/macup.rb`:
- `url` points at a tagged GitHub release tarball of `dicksonk/macup`
  (e.g. `https://github.com/dicksonk/macup/archive/refs/tags/vX.Y.Z.tar.gz`)
  with matching `sha256`.
- `depends_on "git"`, `depends_on "gum"`, `depends_on "gh"`.
- `install` copies `bin/`, `lib/`, `Brewfile`, `dotfiles/` into
  `libexec`, then `bin.install_symlink libexec/"bin/macup"`.
- `test do ... end` block runs `macup --help` and checks for zero exit
  status, per Homebrew formula conventions.

Cutting a new release (tagging the source repo, updating the formula's
`url`/`sha256`) is a manual/documented process in the source repo's
README — not automated as part of this project.
