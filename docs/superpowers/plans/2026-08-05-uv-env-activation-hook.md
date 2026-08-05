# zsh-uv-env Activation/Deactivation Message Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the bundled `zsh-uv-env` plugin's post-hook API in `dotfiles/zshrc` so activating a `uv`-managed Python `.venv` prints which Python version got activated, and leaving it prints a deactivation message.

**Architecture:** Two small zsh functions plus two calls to the plugin's own `zsh_uv_add_post_hook_on_activate`/`zsh_uv_add_post_hook_on_deactivate` registration API — no changes to plugin-install logic or any bash module.

**Tech Stack:** zsh, oh-my-zsh, the `zsh-uv-env` plugin (already installed by `lib/shell.sh`, already loaded via `dotfiles/zshrc`'s `plugins=(...)` array).

## Global Constraints

- The new code must go after `source $ZSH/oh-my-zsh.sh` in `dotfiles/zshrc` — the plugin's `zsh_uv_add_post_hook_on_activate`/`_on_deactivate` functions don't exist until oh-my-zsh loads the plugin.
- Use the plugin's documented hook API only (`zsh_uv_add_post_hook_on_activate '<fn-name>'` / `zsh_uv_add_post_hook_on_deactivate '<fn-name>'`) — do not patch or fork the plugin itself.
- No bats test for this — `dotfiles/zshrc` content isn't interpreter-tested by the existing suite (only its symlinking, in `tests/dotfiles.bats`); verification is manual.

---

### Task 1: Add activation/deactivation hooks to `dotfiles/zshrc`

**Files:**
- Modify: `dotfiles/zshrc:122-123` (insert immediately after `source $ZSH/oh-my-zsh.sh`, before the `# Source ~/environment recursively...` block)

**Interfaces:**
- Consumes: `zsh_uv_add_post_hook_on_activate`, `zsh_uv_add_post_hook_on_deactivate` — functions provided by the already-loaded `zsh-uv-env` plugin, each taking one argument (a function name as a string) and calling that function after the plugin's own activate/deactivate logic runs.

- [ ] **Step 1: Insert the hook functions and registrations**

In `dotfiles/zshrc`, immediately after line 122 (`source $ZSH/oh-my-zsh.sh`) and before the blank line + `# Source ~/environment recursively...` comment, insert:

```zsh

# zsh-uv-env: report which Python got activated/deactivated
_macup_uv_env_on_activate() {
    echo "🐍 venv activated: $(python --version 2>&1)"
}

_macup_uv_env_on_deactivate() {
    echo "🐍 venv deactivated"
}

zsh_uv_add_post_hook_on_activate '_macup_uv_env_on_activate'
zsh_uv_add_post_hook_on_deactivate '_macup_uv_env_on_deactivate'
```

- [ ] **Step 2: Syntax-check the file**

Run: `zsh -n dotfiles/zshrc`
Expected: no output (zsh's `-n` flag parses without executing; a syntax error would print a `parse error` message and exit non-zero)

- [ ] **Step 3: Run the full bats suite to confirm no regressions**

Run: `bats tests/`
Expected: all tests still pass (this change doesn't touch anything bats covers, but confirms nothing else broke)

- [ ] **Step 4: Manual verification (not automatable — do this yourself after merging)**

`cd` into a directory containing a `uv`-created `.venv` (or run `uv venv` in a scratch directory first) with the bundled `dotfiles/zshrc` active as `~/.zshrc`. Confirm:
- Entering the directory prints `🐍 venv activated: Python X.Y.Z`
- Leaving the directory (`cd ..` or into a directory without a venv) prints `🐍 venv deactivated`

- [ ] **Step 5: Commit**

```bash
git add dotfiles/zshrc
git commit -m "feat: report Python version on zsh-uv-env activate/deactivate"
```
