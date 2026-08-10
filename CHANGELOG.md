# Changelog

## [0.6.1](https://github.com/DicksonK/macup/compare/v0.6.0...v0.6.1) (2026-08-10)


### Bug Fixes

* improve CLI UX polish (input labels, checklist hints, error/warning clarity) ([6b096b1](https://github.com/DicksonK/macup/commit/6b096b1632f6cebaf232b99be824215372724f53))

## [0.6.0](https://github.com/DicksonK/macup/compare/v0.5.1...v0.6.0) (2026-08-10)


### Features

* add --skip-git-identity CLI flag ([1e01c10](https://github.com/DicksonK/macup/commit/1e01c10ceec193e9e53cf8b1c4ad3f3992341d73))
* allow skipping git identity setup via env var and blank input ([7e4387c](https://github.com/DicksonK/macup/commit/7e4387c08535de7dabe8bd04cfe196d5a75eadeb))


### Bug Fixes

* make dry-run report the real non-interactive skip; document --skip-git-identity ([98c8502](https://github.com/DicksonK/macup/commit/98c8502cfc9b0969ddbe53b664a0181b085ac131))

## [0.5.1](https://github.com/DicksonK/macup/compare/v0.5.0...v0.5.1) (2026-08-10)


### Bug Fixes

* don't warn "No dotfiles found" when every target is already linked ([6927573](https://github.com/DicksonK/macup/commit/6927573abe5347f1dab094a6c25485184a31bbcf))

## [0.5.0](https://github.com/DicksonK/macup/compare/v0.4.0...v0.5.0) (2026-08-09)


### Features

* add --brewfile-only to skip the bundled Brewfile ([903f50d](https://github.com/DicksonK/macup/commit/903f50d412e45a48ed06c41bced23a6ad605e336))
* keep sudo credentials alive during brew bundle ([3c4160d](https://github.com/DicksonK/macup/commit/3c4160d70f6004be2e1912773aa9c72c8e1766b2))
* set Nerd Font as Terminal.app/iTerm2 default for Powerlevel10k ([7917774](https://github.com/DicksonK/macup/commit/7917774d678701c657568395ccdbed364b3ad4be))
* support a git-repo-backed extra Brewfile ([f9a6086](https://github.com/DicksonK/macup/commit/f9a6086762cab93e1033225be89f20422a2c8e87))


### Bug Fixes

* Nerd Font terminal config + Homebrew tap trust ([820e807](https://github.com/DicksonK/macup/commit/820e807ff5f6e34e0fa2cd08177de69874646d3a))
* redirect git subprocess stdout to stderr in _resolve_extra_brewfile ([38f6549](https://github.com/DicksonK/macup/commit/38f65495718a03a79ad99cfd95dfc363e1e38f83))
* stop dry-run from sending a live Apple Event, harden tap-trust checks ([bea3ceb](https://github.com/DicksonK/macup/commit/bea3cebf6ef94bc86ebbe0446c3a9820e993b234))
* trust Brewfile-declared Homebrew taps before bundling ([7a2fd01](https://github.com/DicksonK/macup/commit/7a2fd01da9935c722afaac269875f2324f0e18ed))

## [0.4.0](https://github.com/DicksonK/macup/compare/v0.3.0...v0.4.0) (2026-08-05)


### Features

* add bordered banner and accent styling to interactive checklist ([6d1d474](https://github.com/DicksonK/macup/commit/6d1d474e6d482cb1126cd1b100f6fb9fb903703c))
* add bordered banner and accent styling to interactive checklist ([4e56744](https://github.com/DicksonK/macup/commit/4e56744b68cf293438a6a3792285eb1ad347c313))

## [0.3.0](https://github.com/DicksonK/macup/compare/v0.2.2...v0.3.0) (2026-08-05)


### Features

* report Python version on zsh-uv-env activate/deactivate ([c415326](https://github.com/DicksonK/macup/commit/c4153268b6ae797d915505f24a51a5d9b9f842fd))
* report Python version on zsh-uv-env activate/deactivate ([6ac0312](https://github.com/DicksonK/macup/commit/6ac0312e6cd7129aeb9739646ddc9ab63b4b1903))


### Bug Fixes

* guard zsh-uv-env hooks and cover already-active venv on shell start ([7341247](https://github.com/DicksonK/macup/commit/734124774dc9024d0deb991ca01276815a67bda8))

## [0.2.2](https://github.com/DicksonK/macup/compare/v0.2.1...v0.2.2) (2026-08-05)


### Bug Fixes

* show space/enter usage hint on the module checklist ([a798c97](https://github.com/DicksonK/macup/commit/a798c972690e98e7faf6f6d79a0687dd64b38b63))

## [0.2.1](https://github.com/DicksonK/macup/compare/v0.2.0...v0.2.1) (2026-08-04)


### Bug Fixes

* guard formula commit against empty diff, clean up tarball ([473f6b6](https://github.com/DicksonK/macup/commit/473f6b6d16534b3f536d71d4d636c921fbcefc4f))
* report a clear error when -d/-b is given with no value ([376b2c6](https://github.com/DicksonK/macup/commit/376b2c6e5a908dce84c225f8b1c1f2ad5a0cddc9))

## [0.2.0](https://github.com/DicksonK/macup/compare/v0.1.0...v0.2.0) (2026-08-04)


### Features

* add short-flag aliases for CLI options ([15bf56e](https://github.com/DicksonK/macup/commit/15bf56eed351b7840bd08560684b1e9442134221))
* add VERSION file and macup --version flag ([9f7ffcd](https://github.com/DicksonK/macup/commit/9f7ffcd00da571a379a732f107f6e9cf47957b3c))


### Bug Fixes

* make release-please config authoritative and harden release workflow ([9d32c49](https://github.com/DicksonK/macup/commit/9d32c49d7c6274123044e0ec0d1becc84a25035f))
