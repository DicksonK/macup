# CI Tests + Automated Versioned Releases — Design Spec

## Purpose

`macup` has bats tests and a `packaging/homebrew/macup.rb` formula, but
both are exercised entirely by hand: tests via `bats tests/` on a
developer's machine, and releases via the manual "Cutting a release"
checklist in the README (tag, compute sha256, hand-edit the formula,
copy it into the separate `homebrew-macup` tap repo, push). This spec
adds GitHub Actions automation for both: CI that runs tests and lint on
every push/PR, and a Conventional-Commits-driven release pipeline that
bumps the version, tags, publishes a GitHub Release, and updates the
Homebrew tap without manual steps.

## Non-Goals

- Does not change module behavior, dry-run behavior, or any existing
  `lib/*.sh` logic — this is CI/release tooling only, plus one small
  CLI addition (`--version`) needed to expose the version this
  automation now tracks.
- Does not attempt to fix or replace the existing bats/shellcheck setup
  — both already pass cleanly locally and are wired into CI as-is.
- Does not add branch protection rules, required-status-check
  configuration, or repo settings changes — those are configured in
  GitHub's UI/settings by the user, not in workflow YAML.
- Does not eliminate the PAT/secret step: `HOMEBREW_TAP_TOKEN` (a
  fine-grained PAT scoped to `contents:write` on `dicksonk/homebrew-macup`
  only) must be created and added as a repo secret by the user before
  the tap-update job can run. This spec documents exactly what to
  create; it can't create the secret itself.

## Design

### 1. `VERSION` file + `macup --version`

- New file `VERSION` at repo root, containing a single line: `0.1.0`
  (matching the existing `v0.1.0` tag — no leading `v`, no trailing
  newline complexity beyond a normal text file).
- `bin/macup` gains a `--version` flag (alongside the existing `--help`
  case in the flag-parsing loop): prints `macup $(cat "$ROOT_DIR/VERSION")`
  and exits 0. Added to `usage()`'s options list.
- This file becomes the single source of truth for "what version is
  this" — release-please's `generic` extra-file updater (below) rewrites
  it in the same commit that bumps the release-please manifest, so it
  never drifts from the tag/release version.

### 2. `.github/workflows/test.yml` — CI

Triggers: `push` (any branch) and `pull_request` (targeting `main`).

- **`test` job** — matrix `os: [macos-13, macos-latest]`. Steps: `brew
  install bats-core`, then `bats tests/`. Mirrors the README's existing
  "Tests" section exactly, just running on GitHub's runners instead of
  a developer machine.
- **`lint` job** — runs on `ubuntu-latest` (no need for a Mac runner
  just to lint shell syntax). Installs `shellcheck` (preinstalled on
  `ubuntu-latest`, or via `apt-get install -y shellcheck` as a fallback),
  runs `shellcheck bin/macup lib/*.sh`. Both currently pass with zero
  warnings, so this job starts green.

Both jobs run independently (no `needs:` between them) so a lint
failure doesn't block seeing test results and vice versa.

### 3. `release-please-config.json` + `.release-please-manifest.json`

Standard release-please "simple" strategy config:

```json
// release-please-config.json
{
  "release-type": "simple",
  "packages": {
    ".": {
      "extra-files": [
        { "type": "generic", "path": "VERSION" }
      ]
    }
  }
}
```

```json
// .release-please-manifest.json
{ ".": "0.1.0" }
```

Seeding the manifest at `0.1.0` means the first automated release
computes its bump from commits made *after* the existing `v0.1.0` tag,
not from the beginning of history.

### 4. `.github/workflows/release-please.yml` — versioning & release

Trigger: `push` to `main`.

**Job `release-please`** (`permissions: contents: write, pull-requests:
write`): runs `googleapis/release-please-action@v4` with
`release-type: simple`, reading the config/manifest above.

Behavior (this is release-please's standard, unmodified flow — no
custom gating needed, since the PR-merge step already **is** the manual
review point):

- Commits landing on `main` with Conventional Commit prefixes
  (`feat:`, `fix:`, `feat!:`/`BREAKING CHANGE:`, etc.) cause
  release-please to open or update a standing
  `chore(main): release X.Y.Z` PR containing the computed version bump,
  updated `VERSION` file, and generated `CHANGELOG.md` entry. Nothing
  is tagged or released yet — this PR just sits there accumulating
  changes until merged.
- When that PR is merged, the **same workflow run** (triggered by that
  merge, since it's a push to `main`) detects the release-please commit,
  creates git tag `vX.Y.Z`, and publishes a GitHub Release with the
  source tarball — replacing the README's manual
  `git tag vX.Y.Z && git push --tags` step. The action exposes
  `release_created: true` and the new `tag_name` as job outputs for the
  next job to consume.

**Job `update-homebrew-tap`** (`needs: release-please`, `if:
${{ needs.release-please.outputs.release_created }}`):

1. Download the tarball for the new tag
   (`https://github.com/dicksonk/macup/archive/refs/tags/${TAG}.tar.gz`)
   and compute its sha256 via `shasum -a 256` — same command the README
   documents doing by hand today.
2. Regenerate `packaging/homebrew/macup.rb` in this repo (`url` and
   `sha256` lines) from the new tag/checksum, commit and push directly
   to `main` (`git-auto-commit-action` or a plain `git commit && git
   push` step using the default `GITHUB_TOKEN`) — replacing the
   README's manual "update `url` and `sha256`" step. A `chore:` commit
   message is used so it doesn't itself trigger a new release-please PR.
3. Checkout `dicksonk/homebrew-macup` in a separate step using
   `secrets.HOMEBREW_TAP_TOKEN`, write the same formula content to
   `Formula/macup.rb`, commit and push — replacing the README's manual
   "copy it to `homebrew-macup/Formula/macup.rb` ... and push" step.

**Required manual setup (one-time, done by the user in GitHub's UI,
not by this automation):**

- Create a fine-grained PAT scoped to `contents:write` on
  `dicksonk/homebrew-macup` only.
- Add it as a repository secret named `HOMEBREW_TAP_TOKEN` under
  `macup`'s Settings → Secrets and variables → Actions.
- No secret is needed for the `release-please` job itself — it uses the
  default `GITHUB_TOKEN`, which already has `contents`/`pull-requests`
  write access within the same repo.

### 5. README updates

- Replace the "Cutting a release" section's three manual steps with a
  description of the automated flow: merge Conventional-Commit-prefixed
  changes to `main`, review/merge the resulting release-please PR when
  ready to ship, and the tag/release/tap-update happen automatically.
- Add a short "Commit messages" note under "Development" documenting the
  Conventional Commits prefixes (`feat:`, `fix:`, `chore:`, `docs:`,
  etc.) and their version-bump effect (`fix` → patch, `feat` → minor,
  `feat!`/`BREAKING CHANGE:` → major), since these now have a functional
  effect on release automation rather than being just a style
  convention.
- Add `--version` to the `Usage` section's option list.

## Testing

- Existing bats suite is unaffected; no new bash logic beyond the
  `--version` flag, which gets a bats test in `tests/macup.bats`
  (asserts `macup --version` prints `macup ` followed by the `VERSION`
  file's contents and exits 0) alongside the existing `--help` test.
- Workflow YAML correctness is verified by pushing to a branch and
  observing real Actions runs (`test.yml` on the first PR that adds
  these files; `release-please.yml` behavior confirmed once merged to
  `main`, since release-please requires `main` to actually exist as its
  target branch) — not unit-testable locally beyond `actionlint` if
  available.
