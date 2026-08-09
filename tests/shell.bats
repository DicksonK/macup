#!/usr/bin/env bats

setup() {
  load 'test_helper/load'
  macup_test_setup
  source "$ROOT_DIR/lib/common.sh"
  source "$ROOT_DIR/lib/menu.sh"
  source "$ROOT_DIR/lib/shell.sh"
  export DEFAULTS_STORE="$TEST_HOME/.defaults-stub-store"
}

teardown() {
  macup_test_teardown
}

install_stub_font() {
  mkdir -p "$HOME/Library/Fonts"
  touch "$HOME/Library/Fonts/MesloLGSNerdFontMono-Regular.ttf"
}

@test "run_shell skips all installs when oh-my-zsh, powerlevel10k, and zsh plugins already exist" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed"* ]]
  [[ "$output" == *"Powerlevel10k already installed"* ]]
  [[ "$output" == *"zsh-autosuggestions already installed"* ]]
  [[ "$output" == *"zsh-syntax-highlighting already installed"* ]]
  [[ "$output" == *"zsh-uv-env already installed"* ]]
  [ ! -f "$MACUP_CALL_LOG" ] || ! grep -q "git clone" "$MACUP_CALL_LOG"
}

@test "run_shell clones powerlevel10k when oh-my-zsh exists but the theme doesn't" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
  grep -q "clone --depth=1" "$MACUP_CALL_LOG"
}

@test "run_shell clones zsh-autosuggestions when missing" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]
  grep -q "clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git" "$MACUP_CALL_LOG"
}

@test "run_shell clones zsh-syntax-highlighting when missing" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]
  grep -q "clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git" "$MACUP_CALL_LOG"
}

@test "run_shell clones zsh-uv-env when missing" {
  mkdir -p "$HOME/.oh-my-zsh"

  run run_shell

  [ "$status" -eq 0 ]
  [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env" ]
  grep -q "clone --depth=1 https://github.com/matthiasha/zsh-uv-env.git" "$MACUP_CALL_LOG"
}

@test "run_shell reports what it would do in dry-run mode without installing anything" {
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would install Oh My Zsh via the official install script"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k into $HOME/.oh-my-zsh/custom/themes/powerlevel10k"* ]]
  [[ "$output" == *"[dry-run] would clone zsh-autosuggestions into $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"* ]]
  [[ "$output" == *"[dry-run] would clone zsh-syntax-highlighting into $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"* ]]
  [[ "$output" == *"[dry-run] would clone zsh-uv-env into $HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"* ]]
  [ ! -d "$HOME/.oh-my-zsh" ]
}

@test "run_shell reports the Powerlevel10k clone in dry-run mode when Oh My Zsh already exists" {
  mkdir -p "$HOME/.oh-my-zsh"
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Oh My Zsh already installed, skipping"* ]]
  [[ "$output" == *"[dry-run] would clone Powerlevel10k"* ]]
  [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]
}

@test "run_shell reports Nerd Font config in dry-run mode when iTerm2 is present" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] would set Terminal.app's default font to MesloLGS Nerd Font Mono"* ]]
  [[ "$output" == *"[dry-run] would create iTerm2 dynamic profile 'macup' with MesloLGS Nerd Font Mono and set it as default"* ]]
}

@test "run_shell does not report iTerm2 config in dry-run mode when iTerm2 is absent" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/no-such-iterm.app"
  export MACUP_DRY_RUN=1

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"would set Terminal.app's default font"* ]]
  [[ "$output" != *"iTerm2"* ]]
}

@test "run_shell skips Terminal.app font config when already set to the target font" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/no-such-iterm.app"
  export OSASCRIPT_RESULT="MesloLGSNFM-Regular"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Terminal.app font already set to MesloLGS Nerd Font Mono, skipping"* ]]
  ! grep -q "osascript.*set font name" "$MACUP_CALL_LOG"
}

@test "run_shell sets Terminal.app font and creates the iTerm2 dynamic profile" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"Set Terminal.app font to MesloLGS Nerd Font Mono"* ]]
  grep -q 'set font name of default settings to "MesloLGS Nerd Font Mono"' "$MACUP_CALL_LOG"
  [ -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
  grep -q "MesloLGSNFM-Regular" "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json"
  grep -q 'defaults write com.googlecode.iterm2 Default Bookmark Guid B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10' "$MACUP_CALL_LOG"
  [[ "$output" == *"Created iTerm2 dynamic profile with MesloLGS Nerd Font Mono and set as default"* ]]
}

@test "run_shell skips the iTerm2 profile when Default Bookmark Guid already matches" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  install_stub_font
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"
  echo "com.googlecode.iterm2|Default Bookmark Guid|B2F4C9F0-5C1A-4E9B-9F2C-6D6B1F1A9C10" >> "$DEFAULTS_STORE"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"iTerm2 default profile already set to the macup Nerd Font profile, skipping"* ]]
  [ ! -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
}

@test "run_shell warns and skips font config when the Nerd Font isn't installed" {
  mkdir -p "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-uv-env"
  export MACUP_ITERM_APP_PATH="$TEST_HOME/iTerm.app"
  mkdir -p "$MACUP_ITERM_APP_PATH"

  run run_shell

  [ "$status" -eq 0 ]
  [[ "$output" == *"MesloLGS Nerd Font Mono not installed; run the homebrew module first, then re-run shell"* ]]
  [ ! -f "$MACUP_CALL_LOG" ] || ! grep -q "osascript" "$MACUP_CALL_LOG"
  [ ! -f "$HOME/Library/Application Support/iTerm2/DynamicProfiles/macup.json" ]
}
