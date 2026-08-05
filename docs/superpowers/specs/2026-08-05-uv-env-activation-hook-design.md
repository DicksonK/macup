# zsh-uv-env Activation/Deactivation Message — Design Spec

## Purpose

The bundled `dotfiles/zshrc` loads the `zsh-uv-env` plugin (auto-activates a
`uv`-managed Python `.venv` on `cd`), but gives no visible feedback about
which Python got activated, or that a venv was deactivated when leaving a
project directory. This spec wires up the plugin's own post-hook API to
print that feedback.

## Non-Goals

- Does not modify `lib/shell.sh`'s plugin-install logic — `zsh-uv-env`
  itself is already installed by the `shell` module; this only adds
  config that assumes it's present.
- Does not add bats coverage — `dotfiles/zshrc`'s content is not
  interpreter-tested by the existing suite (only its symlinking is,
  in `tests/dotfiles.bats`); real hook behavior requires a live zsh +
  oh-my-zsh + the plugin loaded, which is exactly the kind of
  system-mutating behavior the README's "Manual verification checklist"
  already covers by hand rather than via bats stubs.

## Design

In `dotfiles/zshrc`, after `source $ZSH/oh-my-zsh.sh` (plugin functions
must be loaded before they can be referenced) and before the closing
commented-out sections, add:

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

Uses the plugin's documented hook API (`zsh_uv_add_post_hook_on_activate`/
`_on_deactivate`, which take a function name and call it after the
plugin's own activate/deactivate logic runs) rather than patching the
plugin itself. `python --version` is used unqualified since activation
puts the venv's `bin/` first on `PATH`.

## Testing

No automated test added (see Non-Goals). Manual verification: `cd` into
a directory containing a `uv`-created `.venv`, confirm the activation
message prints with the venv's Python version; `cd` out, confirm the
deactivation message prints.

## Known Limitations

- `cd`ing directly from one venv directory into a different venv
  directory (not via a non-venv directory in between) does not print
  the deactivation message for the old venv — only the new activation
  message prints. This is existing `zsh-uv-env` plugin behavior (its
  internal venv-switch path doesn't call its deactivate-hooks path),
  not something introduced or fixable here; see Non-Goals.
