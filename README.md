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

On Homebrew versions with tap trust checks, the first `brew install` from
a newly added tap prompts:

```
Error: Refusing to load formula dicksonk/macup/macup from untrusted tap dicksonk/macup.
Run `brew trust --formula dicksonk/macup/macup` or `brew trust dicksonk/macup` to trust it.
```

Run `brew trust dicksonk/macup` once, then retry `brew install macup`.

## Usage

```sh
macup                          # interactive checklist, runs selected modules
macup --all                    # run all modules, non-interactive
macup homebrew dotfiles        # run only the named modules, non-interactive
macup --dotfiles-repo=<url> dotfiles
macup --brewfile=<path> homebrew
macup --dry-run --all          # preview every module's intended actions, no changes made
macup --help
macup --version
```

Modules: `homebrew`, `shell`, `dotfiles`, `macos-defaults`, `github`.

See [docs/USAGE.md](docs/USAGE.md) for walkthroughs of common scenarios
(first run, `--dry-run`, custom dotfiles/Brewfile, GitHub auth, and
more) with example output.

## Configuration

On first run (or on demand), `macup` offers to create
`~/.config/macup/config` from `macup.conf.example`:

```sh
DOTFILES_REPO=              # e.g. git@github.com:you/dotfiles.git — blank uses bundled dotfiles
EXTRA_BREWFILE=             # e.g. /Users/you/Brewfile.personal — blank means bundled Brewfile only
```

`--dotfiles-repo=<url>` and `--brewfile=<path>` override these for a
single run without editing the file.

`macup dotfiles` also manages a per-machine `~/.gitconfig.local` file
(via `git config -f`, never symlinked) for `git config user.name`/
`user.email`. It prompts once, the first time either is unset, and
reuses whatever's already there on later runs. This is separate from —
and never overwrites — the bundled `dotfiles/gitconfig`.

`macup github` requires a GitHub Personal Access Token (classic) with
the `repo`, `read:org`, `gist`, and `admin:public_key` scopes, created
at https://github.com/settings/tokens. It's used for `gh auth login
--with-token`, and the generated SSH key is then auto-uploaded to your
account via `gh ssh-key add`.

`--dry-run` reports what each selected module would do without making
any changes or prompting for input. It can't predict `brew bundle`'s
exact package-by-package plan, so the homebrew module reports the
command it would run generically rather than diffing packages. If
`DOTFILES_REPO` is set and this is the first run (no local clone yet),
it likewise can't preview which files an unfetched external repo
contains.

Every run also writes its `log_info`/`log_warn`/`log_error` output to a
plain-text log at `~/.cache/macup/logs/<timestamp>.log` — one file per
run, path printed at the end of the summary, no rotation or config
needed. Raw subcommand output (`brew`, `git`, `ssh-keygen`, etc.) and
`gum`'s own interactive rendering aren't captured, only macup's own
status lines.

## Development

Run from a local checkout:

```sh
./bin/macup --help
```

The Homebrew formula pulls in `gum`, `git`, and `gh` automatically via
`depends_on`. Running from a local checkout instead, install them yourself
first: `brew install gum git gh`.

### Commit messages

Commits on `main` should use [Conventional Commits](https://www.conventionalcommits.org/)
prefixes — `fix:`, `feat:`, `feat!:` (or a `BREAKING CHANGE:` footer),
`chore:`, `docs:`, `refactor:`, `test:`, etc. — since release-please
parses them to decide the next version: `fix` bumps patch, `feat` bumps
minor, a `!` or `BREAKING CHANGE:` footer bumps major. Other prefixes
(`chore`, `docs`, ...) show up in the changelog but don't bump the
version.

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
- [ ] `ssh-keygen` generates a real, usable key, `gh auth login
      --with-token` completes with a PAT, and the key auto-uploaded
      via `gh ssh-key add` actually shows up under
      https://github.com/settings/keys.
- [ ] `cd` into a directory with a `uv`-created `.venv` prints the
      activation message with the Python version, `cd` out prints the
      deactivation message, and a shell started already inside such a
      directory also prints the activation message on startup.
- [ ] Running `macup shell` sets Terminal.app's default font to MesloLGS
      Nerd Font Mono (may prompt for Automation permission in System
      Settings the first time) and, if iTerm2 is installed, creates an
      iTerm2 dynamic profile with that font and makes it the default —
      Powerlevel10k icons should render correctly afterward in both.

## Cutting a release

Releases are automated via [release-please](https://github.com/googleapis/release-please)
and GitHub Actions:

1. Land Conventional-Commit-prefixed changes on `main` as usual (see
   "Commit messages" above).
2. release-please opens or updates a standing `chore(main): release
   X.Y.Z` pull request tracking the next version, changelog, and bumped
   `VERSION` file.
3. When ready to ship, review and merge that PR. Merging it tags
   `vX.Y.Z`, publishes a GitHub Release with the source tarball, and
   pushes the updated formula (`url`/`sha256`) to both
   `packaging/homebrew/macup.rb` in this repo and `Formula/macup.rb` in
   the [homebrew-macup](https://github.com/dicksonk/homebrew-macup) tap.

No manual tagging, checksum computation, or formula editing needed.

**One-time setup:** the tap-update step needs a fine-grained GitHub PAT
scoped to `contents:write` on `dicksonk/homebrew-macup` only, saved as
a repository secret named `HOMEBREW_TAP_TOKEN` (Settings → Secrets and
variables → Actions) in this repo. Without it, releases still tag and
publish, but the Homebrew tap push step fails.
