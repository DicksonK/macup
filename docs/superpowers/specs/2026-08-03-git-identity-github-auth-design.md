# Git Identity & GitHub Auth Enhancement — Design Spec

## Purpose

Two related gaps in the current `mac-up` implementation:

1. The bundled `dotfiles/gitconfig` ships with blank `user.name`/`user.email`,
   and nothing in `mac-up` ever sets them — a fresh Mac ends up with git
   commits attributed to nobody until the user manually configures git.
2. `github.sh`'s SSH+auth setup requires two manual, browser-dependent
   steps: pasting the generated SSH public key into GitHub's website, and
   completing `gh auth login`'s interactive browser/device-code flow.
   Neither works headlessly, and `gh` CLI can already automate SSH key
   upload once authenticated via a Personal Access Token (PAT).

This spec adds: (a) a per-machine git identity file managed by `mac-up`,
and (b) a token-based, more automatable GitHub auth + SSH key registration
flow that reuses the identity email captured in (a).

## Non-Goals

- No change to the "flat symlink, no templating" dotfiles philosophy for
  any file other than gitconfig's identity split.
- No support for GitHub Enterprise or non-github.com hosts.
- No attempt to auto-detect/parse fine-grained vs classic PAT scopes —
  mac-up just documents the required scope in its prompt.
- Does not persist the PAT itself anywhere in mac-up's own files — `gh
  auth login --with-token` hands the token to gh's own secure credential
  storage.

## 1. Git Identity (`dotfiles/gitconfig` + `lib/dotfiles.sh`)

### Bundled file change

`dotfiles/gitconfig` no longer has a `[user]` section. It gains an
`[include]`:

```
[include]
	path = ~/.gitconfig.local
[init]
	defaultBranch = main
[pull]
	rebase = false
[core]
	editor = vim
```

`~/.gitconfig.local` is a plain file (never a symlink, never tracked by
any repo — bundled or external) that `mac-up` creates/updates directly on
the target machine.

### `run_dotfiles()` addition

After the existing per-file symlink loop, if `${DOTFILES_REPO:-}` is empty
(i.e. using the bundled dotfiles — an external `DOTFILES_REPO` is assumed
to manage its own git identity, out of scope here):

1. Check whether `~/.gitconfig.local` already has both `user.name` and
   `user.email` set:
   ```bash
   git config -f "$HOME/.gitconfig.local" --get user.name >/dev/null 2>&1 \
     && git config -f "$HOME/.gitconfig.local" --get user.email >/dev/null 2>&1
   ```
2. If both are set: `log_info "Git identity already configured in
   $HOME/.gitconfig.local, skipping"`.
3. Otherwise: prompt via `ui_input "Git user.name" ""` and `ui_input "Git
   user.email" ""`, then:
   ```bash
   git config -f "$HOME/.gitconfig.local" user.name "$git_name"
   git config -f "$HOME/.gitconfig.local" user.email "$git_email"
   log_info "Wrote git identity to $HOME/.gitconfig.local"
   ```

This step never introduces a new failure mode for the module — `git
config -f` on a local file is not expected to fail under normal
conditions; if it does (e.g. unwritable `$HOME`), the non-zero exit
surfaces the same way any other command's failure would at the
`run_dotfiles` call site (no special handling needed).

## 2. GitHub Auth Redesign (`lib/github.sh`)

### New masked-input helper (`lib/menu.sh`)

```bash
ui_input_secret() {
  local prompt="$1"
  gum input --placeholder "$prompt" --password
}
```

### `run_github()` restructure

```
run_github():
  1. Determine SSH key email:
     - default = git config -f ~/.gitconfig.local --get user.email
       (if that file exists and has it set)
     - else prompt via ui_input "Email for SSH key" ""
  2. Generate SSH key at ~/.ssh/id_ed25519 if missing (unchanged from
     today, using the email from step 1)
  3. Print public key + pbcopy (unchanged)
  4. If `gh auth status` fails:
     a. log_info instructing the user to create a PAT at
        https://github.com/settings/tokens with the "admin:public_key"
        scope
     b. token = ui_input_secret "GitHub Personal Access Token"
     c. if token is empty: log_error "No token provided"; return 1
     d. printf '%s' "$token" | gh auth login --with-token
     e. if that fails: log_error "gh auth login failed"; return 1
  5. else: log_info "gh already authenticated, skipping"
  6. Check whether the local public key is already registered:
     - registered = gh api user/keys --jq '.[].key' | grep -qF
       "$(awk '{print $2}' ~/.ssh/id_ed25519.pub)"
  7. If not registered:
     - gh ssh-key add ~/.ssh/id_ed25519.pub --title "mac-up ($(scutil
       --get ComputerName 2>/dev/null || hostname))"
     - on failure: log_warn "Failed to auto-register SSH key with
       GitHub — add it manually at https://github.com/settings/keys
       using the public key printed above" (non-fatal — do not return 1
       for this step alone)
  8. else: log_info "SSH key already registered with GitHub, skipping"
  9. return 0 (unless step 4 failed, which already returned 1)
```

### Error handling

- Auth failure (step 4) is the only hard failure in this module —
  returns 1.
- SSH key upload failure (step 7) is a warning, not a failure — the user
  already has the printed/copied public key as a manual fallback.
- The token itself is never logged, never passed as a CLI argument (only
  via stdin to `gh auth login --with-token`), and never written to any
  mac-up-managed file.

## 3. Testing

### `tests/test_helper/stubs/git` extension

Add a `config` case implementing a minimal flat-file key=value store
(mirrors the existing `defaults` stub's pattern) so `git config -f <file>
--get <key>` / `git config -f <file> <key> <value>` behave realistically
for tests without touching real git config:

```bash
config)
  shift
  if [ "$1" = "-f" ]; then shift; file="$1"; shift; fi
  if [ "$1" = "--get" ]; then
    key="$2"
    line="$(grep -F "^$key=" "$file" 2>/dev/null || true)"
    [ -z "$line" ] && exit 1
    echo "${line#*=}"
    exit 0
  else
    key="$1"; value="$2"
    touch "$file"
    grep -vF "^$key=" "$file" > "$file.tmp" 2>/dev/null || true
    mv "$file.tmp" "$file"
    echo "$key=$value" >> "$file"
    exit 0
  fi
  ;;
```

### `tests/test_helper/stubs/gh` extensions

- `auth login --with-token`: reads and discards stdin, exits per
  `${GH_AUTH_LOGIN_EXIT:-0}` (existing var, reused).
- `api user/keys --jq '.[].key'`: prints the contents of
  `${GH_REGISTERED_KEYS:-}` (one key-blob per line; empty by default,
  meaning no keys registered).
- `ssh-key add`: logs the call, exits per `${GH_SSH_KEY_ADD_EXIT:-0}`.

### New/changed test files

- `tests/dotfiles.bats`: add tests for (a) fresh prompt-and-write to
  `~/.gitconfig.local`, (b) idempotent skip when both keys already set,
  (c) skipped entirely when `DOTFILES_REPO` is set.
- `tests/github.bats`: add tests for (a) email defaults from
  `~/.gitconfig.local` when present, (b) falls back to prompt when
  absent, (c) token-based auth path when `gh auth status` fails, (d) SSH
  key auto-upload when not yet registered, (e) skip upload when already
  registered (via `GH_REGISTERED_KEYS`), (f) non-fatal warning when
  upload fails.
- `tests/menu.bats`: add a test for `ui_input_secret`.

## Interfaces Summary (for a future implementation plan)

- Produces: `ui_input_secret(prompt)` in `lib/menu.sh`.
- Modifies: `run_dotfiles()` in `lib/dotfiles.sh` (adds post-loop identity
  step, gated on `DOTFILES_REPO` being unset).
- Modifies: `run_github()` in `lib/github.sh` (reorders to
  auth-before-upload, adds token-based auth path, adds auto-upload step).
- Modifies: `dotfiles/gitconfig` (bundled file content).
- Modifies: `tests/test_helper/stubs/git` and `tests/test_helper/stubs/gh`
  (new subcommand support).
