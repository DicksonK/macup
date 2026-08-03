# mac-up

Bootstrap a fresh Mac to a working dev environment, or keep an existing
one in sync. `mac-up` installs Homebrew packages, Oh My Zsh +
Powerlevel10k, symlinks dotfiles, applies a curated set of macOS system
defaults, and sets up a GitHub SSH key + `gh` CLI authentication.

## Install

```sh
brew tap dicksonk/mac-up
brew install mac-up
```

## Usage

```sh
mac-up                          # interactive checklist, runs selected modules
mac-up --all                    # run all modules, non-interactive
mac-up homebrew dotfiles        # run only the named modules, non-interactive
mac-up --dotfiles-repo=<url> dotfiles
mac-up --brewfile=<path> homebrew
mac-up --help
```

Modules: `homebrew`, `shell`, `dotfiles`, `macos-defaults`, `github`.

## Configuration

On first run (or on demand), `mac-up` offers to create
`~/.config/mac-up/config` from `mac-up.conf.example`:

```sh
DOTFILES_REPO=              # e.g. git@github.com:you/dotfiles.git — blank uses bundled dotfiles
EXTRA_BREWFILE=             # e.g. /Users/you/Brewfile.personal — blank means bundled Brewfile only
```

`--dotfiles-repo=<url>` and `--brewfile=<path>` override these for a
single run without editing the file.

`mac-up dotfiles` also manages a per-machine `~/.gitconfig.local` file
(via `git config -f`, never symlinked) for `git config user.name`/
`user.email`. It prompts once, the first time either is unset, and
reuses whatever's already there on later runs. This is separate from —
and never overwrites — the bundled `dotfiles/gitconfig`.

`mac-up github` requires a GitHub Personal Access Token (classic) with
the `repo`, `read:org`, `gist`, and `admin:public_key` scopes, created
at https://github.com/settings/tokens. It's used for `gh auth login
--with-token`, and the generated SSH key is then auto-uploaded to your
account via `gh ssh-key add`.

Every run also writes its `log_info`/`log_warn`/`log_error` output to a
plain-text log at `~/.cache/mac-up/logs/<timestamp>.log` — one file per
run, path printed at the end of the summary, no rotation or config
needed. Raw subcommand output (`brew`, `git`, `ssh-keygen`, etc.) and
`gum`'s own interactive rendering aren't captured, only mac-up's own
status lines.

## Development

Run from a local checkout:

```sh
./bin/mac-up --help
```

The Homebrew formula pulls in `gum`, `git`, and `gh` automatically via
`depends_on`. Running from a local checkout instead, install them yourself
first: `brew install gum git gh`.

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

## Cutting a release

1. Tag the source repo: `git tag vX.Y.Z && git push --tags`.
2. Download the tarball and compute its checksum:
   `curl -sL https://github.com/dicksonk/mac-up/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
3. Update `url` and `sha256` in `packaging/homebrew/mac-up.rb`, copy it to
   `homebrew-mac-up/Formula/mac-up.rb` in the tap repo, and push.
