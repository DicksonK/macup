# CI Tests + Automated Versioned Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions automation so `macup` runs its bats/shellcheck/actionlint checks on every push/PR, and so releases (version bump, git tag, GitHub Release, Homebrew tap update) happen via Conventional-Commits-driven release-please instead of the manual checklist in the README.

**Architecture:** Three independent CI jobs (`test`, `lint`, `actionlint`) in one workflow gate every push/PR. A second workflow runs `googleapis/release-please-action` on every push to `main`; when it merges a standing release PR and creates a GitHub Release, a dependent job computes the new tarball's sha256 and pushes the regenerated Homebrew formula to both this repo and the separate `homebrew-macup` tap repo.

**Tech Stack:** GitHub Actions, bats-core, shellcheck, actionlint, release-please, bash.

## Global Constraints

- `VERSION` file at repo root holds a bare version string with no leading `v` (e.g. `0.1.0`), matching the existing `v0.1.0` git tag.
- release-please `release-type` is `simple`, manifest seeded at `0.1.0`.
- Homebrew tap repo is `dicksonk/homebrew-macup`; its push step reads a secret named exactly `HOMEBREW_TAP_TOKEN` (created manually by the user — not part of this plan's code changes).
- Conventional Commit prefixes drive version bumps: `fix:` → patch, `feat:` → minor, `feat!:`/`BREAKING CHANGE:` footer → major; other prefixes (`chore:`, `docs:`, etc.) don't bump the version.
- No changes to existing module logic in `lib/*.sh` — this plan only touches `bin/macup`'s flag parsing, adds new top-level config/workflow files, and updates docs.

---

### Task 1: `VERSION` file + `macup --version`

**Files:**
- Create: `VERSION`
- Modify: `bin/macup:33-48` (`usage()`), `bin/macup:102-105` (flag-parsing loop, right after the `-h|--help` case)
- Test: `tests/macup.bats` (new test added after the existing `"macup --help prints usage and exits 0"` test at line 34)

Note: `bin/macup` currently has short-flag aliases for every option (`-a`,
`-n`, `-d`, `-b`, `-h`) — `--version` gets a `-v` alias for consistency.

**Interfaces:**
- Produces: `VERSION` file at repo root containing a single line, no trailing content beyond the version string — this is what Task 3's release-please config and Task 5's README both reference by exact filename `VERSION`.

- [ ] **Step 1: Write the failing test**

In `tests/macup.bats`, insert this test immediately after the `"macup --help prints usage and exits 0"` test (after line 34, before the `"macup rejects an unknown argument"` test):

```bash
@test "macup --version prints the VERSION file contents and exits 0" {
  run "$MACUP_BIN" --version

  [ "$status" -eq 0 ]
  [ "$output" = "macup $(cat "$ROOT_DIR/VERSION")" ]
}

@test "macup -v is a shorthand for --version" {
  run "$MACUP_BIN" -v

  [ "$status" -eq 0 ]
  [ "$output" = "macup $(cat "$ROOT_DIR/VERSION")" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/macup.bats -f "macup --version"`
Expected: FAIL (either `VERSION` file missing, or `--version` falls through to the `Unknown argument` case and exits 1)

- [ ] **Step 3: Create the VERSION file**

Create `VERSION` at the repo root with exactly this content:

```
0.1.0
```

- [ ] **Step 4: Add the `--version`/`-v` flag to `bin/macup`**

In `bin/macup`, add a case immediately after the existing `-h|--help)` case (currently lines 102-105):

```bash
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        echo "macup $(cat "$ROOT_DIR/VERSION")"
        exit 0
        ;;
      -a|--all)
```

In `usage()`, add a `--version` line to the options list (after `-b, --brewfile=<path>`, before `-h, --help`), matching the existing column alignment (description starts at the same column on every line):

```
Options:
  -a, --all                     Run all modules, non-interactive
  -n, --dry-run                 Preview actions without making changes
  -d, --dotfiles-repo=<url>     Override DOTFILES_REPO for this run
  -b, --brewfile=<path>         Override EXTRA_BREWFILE for this run
  -v, --version                 Print the installed version and exit
  -h, --help                    Show this help
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bats tests/macup.bats -f "macup --version"`
Expected: PASS

- [ ] **Step 6: Run the full suite to check for regressions**

Run: `bats tests/`
Expected: all tests pass (109 existing + 2 new = 111)

- [ ] **Step 7: Commit**

```bash
git add VERSION bin/macup tests/macup.bats
git commit -m "feat: add VERSION file and macup --version flag"
```

---

### Task 2: `.github/workflows/test.yml` — CI

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: `tests/` (bats suite), `bin/macup` + `lib/*.sh` (shellcheck targets) — both already exist and pass cleanly.
- Produces: nothing consumed by later tasks — this workflow is self-contained.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/test.yml`:

```yaml
name: test

on:
  push:
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-13, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - name: Install bats-core
        run: brew install bats-core

      - name: Run tests
        run: bats tests/

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck

      - name: Run shellcheck
        run: shellcheck bin/macup lib/*.sh

  actionlint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download actionlint
        run: bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)

      - name: Run actionlint
        run: ./actionlint -color
```

- [ ] **Step 2: Validate YAML syntax locally**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/test.yml")' && echo VALID`
Expected: `VALID` (ruby ships with macOS by default; this only checks the file parses as YAML, not GitHub Actions semantics)

- [ ] **Step 3: Install actionlint locally and lint the file**

Run:
```bash
brew install actionlint
actionlint .github/workflows/test.yml
```
Expected: no output (actionlint prints nothing on success). If it reports issues, fix them in the file from Step 1 before continuing.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add test, lint, and actionlint workflow"
```

---

### Task 3: release-please config + manifest

**Files:**
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`

**Interfaces:**
- Consumes: `VERSION` (Task 1) — referenced by exact filename `VERSION` in the `extra-files` entry.
- Produces: the config/manifest pair that Task 4's `release-please.yml` workflow points `googleapis/release-please-action` at (implicitly, by file convention — the action reads these files from the repo root by default with no explicit path input needed).

- [ ] **Step 1: Write `release-please-config.json`**

```json
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

- [ ] **Step 2: Write `.release-please-manifest.json`**

```json
{
  ".": "0.1.0"
}
```

- [ ] **Step 3: Validate JSON syntax**

Run: `python3 -m json.tool release-please-config.json >/dev/null && python3 -m json.tool .release-please-manifest.json >/dev/null && echo VALID`
Expected: `VALID`

- [ ] **Step 4: Commit**

```bash
git add release-please-config.json .release-please-manifest.json
git commit -m "chore: add release-please config and manifest"
```

---

### Task 4: `.github/workflows/release-please.yml` — versioning & release

**Files:**
- Create: `.github/workflows/release-please.yml`

**Interfaces:**
- Consumes: `release-please-config.json` / `.release-please-manifest.json` (Task 3, read implicitly by `googleapis/release-please-action`), `packaging/homebrew/macup.rb` (existing file, whose `url`/`sha256` lines this workflow rewrites via `sed`).
- Produces: nothing consumed by later tasks in this repo — the `update-homebrew-tap` job's second step pushes to the external `dicksonk/homebrew-macup` repo, outside this plan's scope to verify locally.

- [ ] **Step 1: Write the workflow file**

Create `.github/workflows/release-please.yml`:

```yaml
name: release-please

on:
  push:
    branches: [main]

jobs:
  release-please:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
    steps:
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          release-type: simple

  update-homebrew-tap:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created }}
    runs-on: ubuntu-latest
    permissions:
      contents: write
    env:
      TAG: ${{ needs.release-please.outputs.tag_name }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main

      - name: Compute release tarball checksum
        id: checksum
        run: |
          curl -sL "https://github.com/dicksonk/macup/archive/refs/tags/${TAG}.tar.gz" -o release.tar.gz
          echo "sha256=$(shasum -a 256 release.tar.gz | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"

      - name: Update packaging/homebrew/macup.rb
        run: |
          sed -i \
            -e "s|url \".*\"|url \"https://github.com/dicksonk/macup/archive/refs/tags/${TAG}.tar.gz\"|" \
            -e "s|sha256 \".*\"|sha256 \"${{ steps.checksum.outputs.sha256 }}\"|" \
            packaging/homebrew/macup.rb

      - name: Commit formula update
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add packaging/homebrew/macup.rb
          git commit -m "chore: update packaging/homebrew/macup.rb for ${TAG}"
          git push

      - name: Push updated formula to homebrew-macup tap
        env:
          GH_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
        run: |
          git clone "https://x-access-token:${GH_TOKEN}@github.com/dicksonk/homebrew-macup.git" tap
          cp packaging/homebrew/macup.rb tap/Formula/macup.rb
          cd tap
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Formula/macup.rb
          if git diff --cached --quiet; then
            echo "No changes to push"
          else
            git commit -m "chore: update macup to ${TAG}"
            git push
          fi
```

- [ ] **Step 2: Validate YAML syntax locally**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/release-please.yml")' && echo VALID`
Expected: `VALID`

- [ ] **Step 3: Lint with actionlint**

Run: `actionlint .github/workflows/release-please.yml`
Expected: no output. If it flags the `sed`/`git` inline scripts (via its shellcheck integration), fix them in the file from Step 1 before continuing.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release-please.yml
git commit -m "ci: add release-please and homebrew tap update workflow"
```

---

### Task 5: README updates

**Files:**
- Modify: `README.md:34` (Usage section example list), `README.md:83-93` (Development section intro), `README.md:121-127` (Cutting a release section)

- [ ] **Step 1: Add `--version` to the Usage examples**

In the `## Usage` code block, after the `macup --help` line (line 34):

```sh
macup --help
macup --version
```

- [ ] **Step 2: Add a "Commit messages" subsection under Development**

In `README.md`, after the paragraph ending `install them yourself first: \`brew install gum git gh\`.` (end of line 93) and before the `### Tests` heading (line 95), insert:

```markdown

### Commit messages

Commits on `main` should use [Conventional Commits](https://www.conventionalcommits.org/)
prefixes — `fix:`, `feat:`, `feat!:` (or a `BREAKING CHANGE:` footer),
`chore:`, `docs:`, `refactor:`, `test:`, etc. — since release-please
parses them to decide the next version: `fix` bumps patch, `feat` bumps
minor, a `!` or `BREAKING CHANGE:` footer bumps major. Other prefixes
(`chore`, `docs`, ...) show up in the changelog but don't bump the
version.
```

- [ ] **Step 3: Replace the "Cutting a release" section**

Replace the entire `## Cutting a release` section (lines 121-127) with:

```markdown
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
```

- [ ] **Step 4: Run the full test suite to confirm no regressions**

Run: `bats tests/`
Expected: all 111 tests pass (README changes don't affect test behavior, but this confirms nothing else broke)

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document --version, commit message convention, and automated releases"
```

---

## Manual Setup Required After This Plan Is Merged

This is **not** a plan task (it's a GitHub UI action, not a code change), but the
`update-homebrew-tap` job in Task 4 will fail without it:

1. Create a fine-grained GitHub PAT scoped to `contents:write` on the
   `dicksonk/homebrew-macup` repository only.
2. In the `macup` repo: Settings → Secrets and variables → Actions → New
   repository secret, named exactly `HOMEBREW_TAP_TOKEN`, value = that PAT.

No secret is needed for the `release-please` job itself — it uses the
default `GITHUB_TOKEN`.
