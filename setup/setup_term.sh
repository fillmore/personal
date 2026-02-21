#!/usr/bin/env bash
set -euo pipefail

# ===== config =====
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGINS_DIR="$ZSH_CUSTOM/plugins"
ZSHRC="$HOME/.zshrc"

# Plugins
AUTOSUGGEST_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
SYNTAX_HL_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
AUTOCOMPLETE_REPO="https://github.com/marlonrichert/zsh-autocomplete.git"

AUTOSUGGEST_DIR="$PLUGINS_DIR/zsh-autosuggestions"
SYNTAX_HL_DIR="$PLUGINS_DIR/zsh-syntax-highlighting"
AUTOCOMPLETE_DIR="$PLUGINS_DIR/zsh-autocomplete"

log() { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m==>\033[0m %s\n" "$*"; }
die() { printf "\n\033[1;31m==>\033[0m %s\n" "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  else
    echo "unknown"
  fi
}

install_packages() {
  local os
  os="$(detect_os)"

  case "$os" in
    macos)
      if ! have brew; then
        die "Homebrew not found. Install it first: https://brew.sh/"
      fi
      log "Installing packages via brew..."
      brew update
      brew install zsh git curl starship || true
      ;;
    debian)
      log "Installing packages via apt..."
      sudo apt-get update -y
      sudo apt-get install -y zsh git curl
      # Prefer distro package if available; fall back to official installer
      if sudo apt-get install -y starship; then
        true
      else
        warn "starship not available via apt on this system; installing via official script..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y
      fi
      ;;
    *)
      die "Unsupported OS. Please install zsh, git, curl, and starship manually and re-run."
      ;;
  esac
}

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    log "Oh My Zsh already installed."
    return
  fi

  log "Installing Oh My Zsh..."
  # RUNZSH=no prevents auto-switch into zsh; CHSH=no avoids changing default shell without asking.
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

git_clone_or_update() {
  local repo="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    log "Updating $(basename "$dir")..."
    git -C "$dir" pull --ff-only
  else
    log "Cloning $(basename "$dir")..."
    mkdir -p "$(dirname "$dir")"
    git clone --depth 1 "$repo" "$dir"
  fi
}

ensure_plugins_in_zshrc() {
  [[ -f "$ZSHRC" ]] || touch "$ZSHRC"

  # Ensure ZSH is set (Oh My Zsh sets this, but keep safe)
  if ! grep -qE '^export ZSH=' "$ZSHRC" && ! grep -qE '^ZSH=' "$ZSHRC"; then
    warn "ZSH path not found in ~/.zshrc. Adding default."
    printf '\nexport ZSH="$HOME/.oh-my-zsh"\n' >> "$ZSHRC"
  fi

  # Ensure plugins line exists and includes ours.
  if grep -qE '^[[:space:]]*plugins=\(' "$ZSHRC"; then
    log "Updating plugins list in ~/.zshrc..."
    for p in zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting; do
      if ! perl -0777 -ne 'exit !(m/^[ \t]*plugins=\((?:.|\n)*?\b'"$p"'\b(?:.|\n)*?\)/m)' "$ZSHRC"; then
        perl -i -0777 -pe 's/^[ \t]*plugins=\(((?:.|\n)*?)\)/plugins=($1 '"$p"')/m' "$ZSHRC"
      fi
    done
  else
    log "No plugins=(...) line found. Adding one."
    printf '\nplugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting)\n' >> "$ZSHRC"
  fi

  # Ensure syntax-highlighting is sourced LAST (recommended by plugin)
  if ! grep -qE 'zsh-syntax-highlighting\.zsh' "$ZSHRC"; then
    log "Ensuring zsh-syntax-highlighting is sourced near the end of ~/.zshrc..."
    cat >> "$ZSHRC" <<'EOF'

# Ensure syntax highlighting loads (keep this near the end of ~/.zshrc)
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
EOF
  fi
}

ensure_starship_in_zshrc() {
  [[ -f "$ZSHRC" ]] || touch "$ZSHRC"

  if ! have starship; then
    warn "starship command not found; skipping starship init."
    return
  fi

  if grep -qE 'starship init zsh' "$ZSHRC"; then
    log "Starship already initialized in ~/.zshrc."
    return
  fi

  log "Adding Starship init to ~/.zshrc..."
  cat >> "$ZSHRC" <<'EOF'

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF
}

offer_set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  [[ -n "$zsh_path" ]] || return

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    log "Default shell is already zsh."
    return
  fi

  echo
  read -r -p "Set zsh as your default shell? (y/N) " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    log "Setting default shell to $zsh_path"
    if [[ "$(detect_os)" == "macos" ]]; then
      if ! grep -qF "$zsh_path" /etc/shells; then
        warn "$zsh_path not found in /etc/shells; adding it (requires sudo)."
        echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
      fi
    fi
    chsh -s "$zsh_path" || warn "chsh failed. You may need to run it manually: chsh -s $zsh_path"
  else
    warn "Skipping default shell change."
  fi
}

main() {
  log "Installing prerequisites..."
  install_packages

  log "Installing Oh My Zsh..."
  install_oh_my_zsh

  log "Installing/Updating plugins..."
  git_clone_or_update "$AUTOSUGGEST_REPO" "$AUTOSUGGEST_DIR"
  git_clone_or_update "$AUTOCOMPLETE_REPO" "$AUTOCOMPLETE_DIR"
  git_clone_or_update "$SYNTAX_HL_REPO" "$SYNTAX_HL_DIR"

  log "Updating ~/.zshrc..."
  ensure_plugins_in_zshrc
  ensure_starship_in_zshrc

  log "Done."
  echo "Next: start a new terminal, or run: exec zsh"
  offer_set_default_shell
}

main "$@"

