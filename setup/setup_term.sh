#!/usr/bin/env bash
set -euo pipefail

# ===== config =====
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGINS_DIR="$ZSH_CUSTOM/plugins"
ZSHRC="$HOME/.zshrc"
STARSHIP_CONFIG_FILE="${STARSHIP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml}"
ZELLIJ_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zellij"
ZELLIJ_LAYOUTS_DIR="$ZELLIJ_CONFIG_DIR/layouts"
ZELLIJ_SHELL_WRAPPER="$HOME/.local/bin/zsh-login"
GHOSTTY_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config.ghostty"

# Plugins
AUTOSUGGEST_REPO="https://github.com/zsh-users/zsh-autosuggestions.git"
SYNTAX_HL_REPO="https://github.com/zsh-users/zsh-syntax-highlighting.git"
AUTOCOMPLETE_REPO="https://github.com/marlonrichert/zsh-autocomplete.git"

AUTOSUGGEST_DIR="$PLUGINS_DIR/zsh-autosuggestions"
SYNTAX_HL_DIR="$PLUGINS_DIR/zsh-syntax-highlighting"
AUTOCOMPLETE_DIR="$PLUGINS_DIR/zsh-autocomplete"

log() { printf "\n\033[1;32m==>\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m==>\033[0m %s\n" "$*"; }
die() {
  if [[ "${UI_INTERACTIVE:-0}" -eq 1 ]]; then
    ui_cleanup
  fi
  printf "\n\033[1;31m==>\033[0m %s\n" "$*"
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

UI_INTERACTIVE=0
UI_CURRENT_PHASE=""
declare -a UI_PHASES=()
declare -a UI_PHASE_STATES=()
declare -a UI_LOG_LINES=()
declare -a UI_FRAME_LINES=()
declare -a UI_PREVIOUS_FRAME_LINES=()
UI_LOG_LIMIT=8
UI_WIDTH=79
UI_HEIGHT=24
UI_INNER_WIDTH=77
UI_LOG_WIDTH=75
UI_HORIZONTAL="-----------------------------------------------------------------------------"
UI_RENDER_INITIALIZED=0
UI_RENDER_WIDTH=0
UI_RENDER_HEIGHT=0
UI_CLEANED_UP=0

ui_phase_index() {
  local phase="$1"
  local idx

  for ((idx = 0; idx < ${#UI_PHASES[@]}; idx++)); do
    if [[ "${UI_PHASES[$idx]}" == "$phase" ]]; then
      printf '%s' "$idx"
      return 0
    fi
  done

  return 1
}

ui_phase_state() {
  local phase="$1"
  local idx
  idx="$(ui_phase_index "$phase")" || return 1
  printf '%s' "${UI_PHASE_STATES[$idx]:-pending}"
}

ui_set_phase_state() {
  local phase="$1"
  local state="$2"
  local idx
  idx="$(ui_phase_index "$phase")" || return 1
  UI_PHASE_STATES[$idx]="$state"
}

ui_is_interactive() {
  [[ -t 1 ]] \
    && [[ -n "${TERM:-}" ]] \
    && [[ "${TERM:-}" != "dumb" ]] \
    && [[ -z "${CI:-}" ]]
}

ui_status_marker() {
  local state="${1:-pending}"
  case "$state" in
    done) printf '✓' ;;
    running) printf '→' ;;
    failed) printf '✗' ;;
    *) printf '·' ;;
  esac
}

ui_phase_color() {
  local state="${1:-pending}"
  case "$state" in
    done) printf '\033[32m' ;;
    running) printf '\033[36m' ;;
    failed) printf '\033[31m' ;;
    *) printf '\033[33m' ;;
  esac
}

ui_read_tty_size() {
  have stty || return 1
  [[ -r /dev/tty ]] || return 1
  stty size < /dev/tty 2>/dev/null
}

ui_update_dimensions() {
  local columns=""
  local rows=""
  local fixed_rows
  local tty_size=""

  tty_size="$(ui_read_tty_size || true)"
  if [[ "$tty_size" =~ ^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]*$ ]]; then
    read -r rows columns <<< "$tty_size"
  fi

  if ! [[ "$columns" =~ ^[1-9][0-9]*$ ]] && have tput; then
    columns="$(tput cols 2>/dev/null || true)"
  fi

  if ! [[ "$rows" =~ ^[1-9][0-9]*$ ]] && have tput; then
    rows="$(tput lines 2>/dev/null || true)"
  fi

  [[ "$columns" =~ ^[1-9][0-9]*$ ]] || columns="${COLUMNS:-80}"
  [[ "$rows" =~ ^[1-9][0-9]*$ ]] || rows="${LINES:-24}"
  [[ "$columns" =~ ^[1-9][0-9]*$ ]] || columns=80
  [[ "$rows" =~ ^[1-9][0-9]*$ ]] || rows=24

  (( columns < 4 )) && columns=4
  (( rows < 1 )) && rows=1

  UI_WIDTH=$((columns - 1))
  UI_HEIGHT="$rows"
  UI_INNER_WIDTH=$((UI_WIDTH - 2))
  (( UI_INNER_WIDTH < 1 )) && UI_INNER_WIDTH=1
  UI_LOG_WIDTH=$((UI_INNER_WIDTH - 2))
  (( UI_LOG_WIDTH < 1 )) && UI_LOG_WIDTH=1

  fixed_rows=$((9 + ${#UI_PHASES[@]}))
  UI_LOG_LIMIT=$((UI_HEIGHT - fixed_rows - 1))
  (( UI_LOG_LIMIT < 1 )) && UI_LOG_LIMIT=1

  printf -v UI_HORIZONTAL '%*s' "$UI_INNER_WIDTH" ''
  UI_HORIZONTAL="${UI_HORIZONTAL// /-}"
}

ui_frame_add_border() {
  UI_FRAME_LINES+=("+$UI_HORIZONTAL+")
}

ui_frame_add_row() {
  local plain="$1"
  local rendered="${2:-$1}"
  local visible_length="${#plain}"
  local padding
  local padding_text=""

  if (( visible_length > UI_INNER_WIDTH )); then
    plain="${plain:0:$UI_INNER_WIDTH}"
    rendered="$plain"
    visible_length="${#plain}"
  fi

  padding=$((UI_INNER_WIDTH - visible_length))
  printf -v padding_text '%*s' "$padding" ''
  UI_FRAME_LINES+=("|${rendered}${padding_text}|")
}

ui_build_frame() {
  local total="${#UI_PHASES[@]}"
  local done=0
  local phase state marker
  local line row

  ui_update_dimensions
  UI_FRAME_LINES=()

  for phase in "${UI_PHASES[@]}"; do
    state="$(ui_phase_state "$phase")"
    if [[ "$state" == "done" ]]; then
      ((done += 1))
    fi
  done

  ui_frame_add_border
  ui_frame_add_row "setup_term.sh" $'\033[1;36msetup_term.sh\033[0m'
  ui_frame_add_row "Progress: [$done/$total]"
  ui_frame_add_border

  for phase in "${UI_PHASES[@]}"; do
    state="$(ui_phase_state "$phase")"
    marker="$(ui_status_marker "$state")"
    ui_frame_add_row "  $marker $phase" \
      "  $(ui_phase_color "$state")$marker $phase"$'\033[0m'
  done

  ui_frame_add_border
  ui_frame_add_row "Recent output:"
  for ((row = 0; row < UI_LOG_LIMIT; row++)); do
    if (( row < ${#UI_LOG_LINES[@]} )); then
      line="${UI_LOG_LINES[$row]}"
      ui_frame_add_row "  ${line:0:$UI_LOG_WIDTH}"
    elif (( row == 0 )); then
      ui_frame_add_row "  waiting for task output..."
    else
      ui_frame_add_row ""
    fi
  done

  ui_frame_add_row ""
  ui_frame_add_row "Current: ${UI_CURRENT_PHASE:-idle}"
  ui_frame_add_border
}

ui_draw_full_frame() {
  local idx

  printf '\033[2J\033[H'
  for ((idx = 0; idx < ${#UI_FRAME_LINES[@]}; idx++)); do
    printf '\033[%d;1H\033[2K%s' "$((idx + 1))" "${UI_FRAME_LINES[$idx]}"
  done

  UI_RENDER_INITIALIZED=1
}

ui_draw_changed_rows() {
  local current_count="${#UI_FRAME_LINES[@]}"
  local previous_count="${#UI_PREVIOUS_FRAME_LINES[@]}"
  local max_count="$current_count"
  local idx current previous

  if (( previous_count > max_count )); then
    max_count="$previous_count"
  fi

  for ((idx = 0; idx < max_count; idx++)); do
    current="${UI_FRAME_LINES[$idx]-}"
    previous="${UI_PREVIOUS_FRAME_LINES[$idx]-}"
    if [[ "$current" != "$previous" ]]; then
      printf '\033[%d;1H\033[2K%s' "$((idx + 1))" "$current"
    fi
  done
}

ui_remember_frame() {
  UI_PREVIOUS_FRAME_LINES=("${UI_FRAME_LINES[@]}")
  UI_RENDER_WIDTH="$UI_WIDTH"
  UI_RENDER_HEIGHT="$UI_HEIGHT"
}

ui_init() {
  if ! ui_is_interactive; then
    return 1
  fi

  UI_INTERACTIVE=1
  UI_PHASES=(
    "Installing prerequisites"
    "Installing Oh My Zsh"
    "Installing plugins"
    "Updating ~/.zshrc"
    "Configuring Starship"
    "Configuring Zellij"
    "Configuring Ghostty"
  )

  UI_PHASE_STATES=()
  for phase in "${UI_PHASES[@]}"; do
    UI_PHASE_STATES+=("pending")
  done

  UI_FRAME_LINES=()
  UI_PREVIOUS_FRAME_LINES=()
  UI_RENDER_INITIALIZED=0
  UI_RENDER_WIDTH=0
  UI_RENDER_HEIGHT=0
  UI_CLEANED_UP=0

  trap 'ui_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  printf '\033[?1049h\033[?25l'
  ui_render
}

ui_cleanup() {
  [[ "$UI_INTERACTIVE" -eq 1 ]] || return 0
  [[ "$UI_CLEANED_UP" -eq 0 ]] || return 0

  UI_CLEANED_UP=1
  UI_INTERACTIVE=0
  printf '\033[0m\033[?25h\033[?1049l'
}

ui_read_key() {
  [[ -r /dev/tty ]] || return 1
  IFS= read -r -n 1 -s < /dev/tty
}

ui_wait_for_key() {
  [[ "$UI_INTERACTIVE" -eq 1 ]] || return 0

  UI_CURRENT_PHASE="Complete - press any key to continue"
  ui_render
  ui_read_key || true
}

ui_render() {
  [[ "$UI_INTERACTIVE" -eq 1 ]] || return 0

  ui_build_frame

  if (( ! UI_RENDER_INITIALIZED )) \
    || (( UI_WIDTH != UI_RENDER_WIDTH )) \
    || (( UI_HEIGHT != UI_RENDER_HEIGHT )); then
    ui_draw_full_frame
  else
    ui_draw_changed_rows
  fi

  ui_remember_frame
}

ui_is_password_prompt() {
  local line="${1:-}"

  [[ "$line" =~ [Pp]assword ]] || [[ "$line" =~ [Pp]assphrase ]]
}

ui_redact_password_prompt() {
  printf '%s' "[password prompt hidden]"
}

ui_read_tty_secret() {
  local secret=""

  [[ -r /dev/tty ]] || return 1
  IFS= read -r -s secret < /dev/tty || return 1
  printf '\n' > /dev/tty
  printf '%s' "$secret"
}

run_sudo() {
  local password=""

  if (( UI_INTERACTIVE )); then
    UI_CURRENT_PHASE="Waiting for password..."
    ui_render
    printf '\n\033[1;33m==>\033[0m Enter your sudo password to continue.\n' > /dev/tty
    IFS= read -r -s password < /dev/tty || return 1
    printf '\n' > /dev/tty
    printf '%s\n' "$password" | sudo -S -p '' "$@"
    return
  fi

  sudo "$@"
}

ui_store_log_excerpt() {
  local log_file="$1"
  local line

  ui_update_dimensions
  UI_LOG_LINES=()

  if [[ ! -f "$log_file" ]]; then
    UI_LOG_LINES+=("waiting for output...")
    return
  fi

  while IFS= read -r line; do
    line="${line//$'\r'/}"
    if [[ -n "${line//[[:space:]]/}" ]]; then
      if ui_is_password_prompt "$line"; then
        UI_CURRENT_PHASE="Waiting for password..."
        line="$(ui_redact_password_prompt)"
      fi
      UI_LOG_LINES+=("$line")
    fi
  done < <(tail -n "$UI_LOG_LIMIT" "$log_file")

  if (( ${#UI_LOG_LINES[@]} == 0 )); then
    UI_LOG_LINES+=("waiting for output...")
  fi
}

ui_run_step() {
  local phase="$1"
  shift
  local log_file
  local pid
  local rc

  UI_CURRENT_PHASE="$phase"
  ui_set_phase_state "$phase" "running"
  ui_render

  log_file="$(mktemp)"
  "$@" >"$log_file" 2>&1 &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    ui_store_log_excerpt "$log_file"
    ui_render
    sleep 0.15
  done

  wait "$pid"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    ui_set_phase_state "$phase" "done"
  else
    ui_set_phase_state "$phase" "failed"
  fi

  ui_store_log_excerpt "$log_file"
  rm -f "$log_file"

  ui_render
  return "$rc"
}

run_step_or_plain() {
  local phase="$1"
  shift

  if (( UI_INTERACTIVE )); then
    ui_run_step "$phase" "$@"
  else
    log "$phase"
    "$@"
  fi
}

eval_brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
  fi
}

install_brew_packages() {
  log "Installing packages via brew: $*"
  brew install "$@"
}

detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  else
    echo "unknown"
  fi
}

ensure_git_on_macos() {
  if have git; then
    return
  fi

  warn "Git not found. Installing Xcode Command Line Tools..."
  xcode-select --install || true

  if ! have git; then
    die "Git is still unavailable. Complete the Command Line Tools installation, then re-run this script."
  fi
}

ensure_homebrew() {
  eval_brew_shellenv

  if have brew; then
    return
  fi

  log "Homebrew not found. Installing Homebrew..."
  warn "Run this script as your normal user account, not with sudo."

  if [[ "$(detect_os)" == "macos" ]]; then
    log "Homebrew may prompt for your macOS administrator password..."
    run_sudo -v || die "Administrator access is required to install Homebrew on macOS. Re-run this script from an admin account."
  fi

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  eval_brew_shellenv

  have brew || die "Homebrew installation failed. Install it manually from https://brew.sh/ and re-run."
}

install_packages() {
  local os
  os="$(detect_os)"

  case "$os" in
    macos)
      ensure_git_on_macos
      ensure_homebrew
      log "Installing packages via brew..."
      brew update
      install_brew_packages git curl fzf gh jd jq lsd lazygit starship yq zellij btop
      brew install --cask ghostty || warn "Ghostty install failed; try manually: brew install --cask ghostty"
      ;;
    debian)
      log "Installing packages via apt..."
      run_sudo apt-get update -y
      run_sudo apt-get install -y zsh git curl build-essential procps file
      ensure_homebrew
      log "Refreshing Homebrew formulas..."
      brew update
      log "Installing CLI tools via Homebrew so versions stay consistent across platforms..."
      install_brew_packages fzf gh jd jq lsd lazygit starship yq zellij btop
      ;;
    *)
      die "Unsupported OS. Please install zsh, git, curl, Homebrew, fzf, gh, jd, jq, lsd, lazygit, yq, starship, zellij, and btop manually and re-run."
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
    if grep -qE '^[[:space:]]*plugins=\(' "$ZSHRC"; then
      perl -0pi -e 's@(^[ \t]*plugins=\()@export ZSH="\$HOME/.oh-my-zsh"\n\n$1@m' "$ZSHRC"
    else
      printf '\nexport ZSH="$HOME/.oh-my-zsh"\n' >> "$ZSHRC"
    fi
  fi

  if ! grep -qF 'brew shellenv' "$ZSHRC"; then
    log "Ensuring Homebrew is available in future zsh sessions..."
    cat >> "$ZSHRC" <<'EOF'

# Homebrew
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi
EOF
  fi

  if ! grep -qF '/home/linuxbrew/.linuxbrew/bin/brew' "$ZSHRC" && ! grep -qF '$HOME/.linuxbrew/bin/brew' "$ZSHRC"; then
    log "Ensuring Linuxbrew is available in future zsh sessions..."
    cat >> "$ZSHRC" <<'EOF'

# Linuxbrew
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi
EOF
  fi

  if ! grep -qF '$HOME/.local/bin' "$ZSHRC"; then
    log "Ensuring ~/.local/bin is on PATH in ~/.zshrc..."
    cat >> "$ZSHRC" <<'EOF'

# User-local binaries
export PATH="$HOME/.local/bin:$PATH"
EOF
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

  if ! grep -qE '^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh' "$ZSHRC"; then
    log "Ensuring Oh My Zsh is initialized in ~/.zshrc..."
    perl -0pi -e 's@(^[ \t]*plugins=\((?:.|\n)*?\)[ \t]*(?:#[^\r\n]*)?)(\r?\n|\z)@$1$2\nsource "\$ZSH/oh-my-zsh.sh"\n@m' "$ZSHRC"
  fi

  grep -qE '^[[:space:]]*(source|\.)[[:space:]]+.*oh-my-zsh\.sh' "$ZSHRC" \
    || die "Failed to add Oh My Zsh initialization to ~/.zshrc."

  # Ensure custom plugins are sourced from ~/.zshrc as well.
  if ! grep -qE 'zsh-autosuggestions(\.plugin)?\.zsh' "$ZSHRC"; then
    log "Ensuring zsh-autosuggestions is sourced in ~/.zshrc..."
    cat >> "$ZSHRC" <<'EOF'

# Ensure autosuggestions loads
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
EOF
  fi

  if ! grep -qE 'zsh-autocomplete(\.plugin)?\.zsh' "$ZSHRC"; then
    log "Ensuring zsh-autocomplete is sourced in ~/.zshrc..."
    cat >> "$ZSHRC" <<'EOF'

# Ensure autocomplete loads
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
fi
EOF
  fi

  # Keep syntax-highlighting sourced LAST (recommended by plugin)
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

  if perl -0ne 'exit !(m/\n# Starship prompt\nif command -v starship >\/dev\/null 2>&1; then\n  eval "\$\(starship init zsh\)"\nfi\n?/s)' "$ZSHRC" \
    && ! grep -qE '^[[:space:]]*eval "\$\((/opt/homebrew/bin/|/usr/local/bin/|/home/linuxbrew/.linuxbrew/bin/)?starship init zsh\)"[[:space:]]*$' "$ZSHRC"; then
    log "Starship already initialized in ~/.zshrc."
    return
  fi

  if grep -qE '^[[:space:]]*eval "\$\((/opt/homebrew/bin/|/usr/local/bin/|/home/linuxbrew/.linuxbrew/bin/)?starship init zsh\)"[[:space:]]*$' "$ZSHRC"; then
    log "Normalizing Starship init in ~/.zshrc..."
    perl -0pi -e 's/\n?# Starship prompt\nif command -v starship >\/dev\/null 2>&1; then\n  eval "\$\(starship init zsh\)"\nfi\n?/\n/g; s/\n?eval "\$\((?:\/opt\/homebrew\/bin\/|\/usr\/local\/bin\/|\/home\/linuxbrew\/\.linuxbrew\/bin\/)?starship init zsh\)"\n?/\n/g;' "$ZSHRC"
  else
    log "Adding Starship init to ~/.zshrc..."
  fi

  cat >> "$ZSHRC" <<'EOF'

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
EOF

  if ! have starship; then
    warn "starship command not found in the current shell; it will activate in new shells once Homebrew is on PATH."
  fi
}

ensure_starship_config() {
  if ! have starship; then
    warn "starship command not found; skipping Starship preset configuration."
    return
  fi

  mkdir -p "$(dirname "$STARSHIP_CONFIG_FILE")"

  local tmp
  tmp="$(mktemp)"

  log "Setting Starship preset to catppuccin-powerline..."
  starship preset catppuccin-powerline --force -o "$tmp"

  if grep -qE '^[[:space:]]*add_newline[[:space:]]*=' "$tmp"; then
    perl -0pi -e 's/^[ \t]*add_newline[ \t]*=.*/add_newline = true/m' "$tmp"
  else
    perl -0pi -e 'BEGIN { local $/; $_ = <>; print "add_newline = true\n\n$_"; exit }' "$tmp"
  fi

  # Force the prompt line-break on, even if the preset defines it differently.
  if grep -qE '^\[line_break\]' "$tmp"; then
    perl -0pi -e 's/(\[line_break\]\n(?:[^\[]*?))disabled[ \t]*=[ \t]*(true|false)/${1}disabled = false/s' "$tmp"
  else
    cat >> "$tmp" <<'EOF'

[line_break]
disabled = false
EOF
  fi

  mv "$tmp" "$STARSHIP_CONFIG_FILE"
  log "Starship config written to $STARSHIP_CONFIG_FILE"
}

ensure_zellij_layout() {
  mkdir -p "$ZELLIJ_LAYOUTS_DIR"

  cat > "$ZELLIJ_LAYOUTS_DIR/ide.kdl" <<'EOF'
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=2 borderless=true {
            plugin location="zellij:status-bar"
        }
    }

    tab name="IDE" focus=true {
        pane split_direction="vertical" {
            pane name="main" size="50%" focus=true
            pane split_direction="horizontal" size="50%" {
                pane name="top-right"
                pane name="bottom-right"
            }
        }
    }
}
EOF

  log "Zellij IDE layout written to $ZELLIJ_LAYOUTS_DIR/ide.kdl"
}

ensure_zellij_login_shell() {
  local zsh_path
  local zellij_config_file="$ZELLIJ_CONFIG_DIR/config.kdl"

  if [[ "$(detect_os)" == "macos" && -x /bin/zsh ]]; then
    zsh_path="/bin/zsh"
  else
    zsh_path="$(command -v zsh || true)"
  fi
  [[ -n "$zsh_path" ]] || return

  mkdir -p "$(dirname "$ZELLIJ_SHELL_WRAPPER")" "$ZELLIJ_CONFIG_DIR"

  cat > "$ZELLIJ_SHELL_WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$zsh_path" -l "\$@"
EOF
  chmod +x "$ZELLIJ_SHELL_WRAPPER"

  [[ -f "$zellij_config_file" ]] || touch "$zellij_config_file"

  if grep -qE '^[[:space:]]*default_shell[[:space:]]+' "$zellij_config_file"; then
    perl -0pi -e 's|^[ \t]*default_shell[ \t]+.*$|default_shell "'"$ZELLIJ_SHELL_WRAPPER"'"|m' "$zellij_config_file"
  elif grep -qE '^[[:space:]]*//[[:space:]]*default_shell[[:space:]]+' "$zellij_config_file"; then
    perl -0pi -e 's|^[ \t]*//[ \t]*default_shell[ \t]+.*$|default_shell "'"$ZELLIJ_SHELL_WRAPPER"'"|m' "$zellij_config_file"
  else
    printf '\ndefault_shell "%s"\n' "$ZELLIJ_SHELL_WRAPPER" >> "$zellij_config_file"
  fi

  log "Configured Zellij to open new panes with login zsh."
}

ensure_zellij_alias() {
  [[ -f "$ZSHRC" ]] || touch "$ZSHRC"

  if grep -qF 'zjide() {' "$ZSHRC"; then
    log "Zellij IDE helper already present in ~/.zshrc."
    return
  fi

  if grep -qF "alias zjide='zellij --layout ide'" "$ZSHRC"; then
    log "Upgrading zjide alias to a session-aware helper in ~/.zshrc..."
    perl -0pi -e "s@\n# Zellij IDE layout\nalias zjide='zellij --layout ide'\n@@g" "$ZSHRC"
  fi

  log "Adding zjide helper to ~/.zshrc..."
  cat >> "$ZSHRC" <<'EOF'

# Zellij IDE layout helper
unalias zjide 2>/dev/null
zjide() {
  if [ "$#" -gt 0 ]; then
    if zellij list-sessions 2>/dev/null | awk '{print $1}' | grep -Fqx -- "$1"; then
      zellij attach "$1"
    else
      zellij --session "$1" --new-session-with-layout ide
    fi
  else
    zellij --layout ide
  fi
}
EOF
}

install_plugins() {
  git_clone_or_update "$AUTOSUGGEST_REPO" "$AUTOSUGGEST_DIR"
  git_clone_or_update "$AUTOCOMPLETE_REPO" "$AUTOCOMPLETE_DIR"
  git_clone_or_update "$SYNTAX_HL_REPO" "$SYNTAX_HL_DIR"
}

configure_zsh_shell() {
  ensure_plugins_in_zshrc
  ensure_zellij_alias
}

configure_starship() {
  ensure_starship_in_zshrc
  ensure_starship_config
}

configure_zellij() {
  ensure_zellij_layout
  ensure_zellij_login_shell
}

configure_ghostty() {
  ensure_ghostty_config
}

upsert_ghostty_setting() {
  local key="$1"
  local value="$2"

  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$GHOSTTY_CONFIG_FILE"; then
    perl -0pi -e 's/^[ \t]*'"$key"'[ \t]*=.*/'"$key"' = '"$value"'/m' "$GHOSTTY_CONFIG_FILE"
  else
    printf '%s = %s\n' "$key" "$value" >> "$GHOSTTY_CONFIG_FILE"
  fi
}

ensure_ghostty_config() {
  local os
  os="$(detect_os)"

  if [[ "$os" != "macos" ]]; then
    return
  fi

  mkdir -p "$(dirname "$GHOSTTY_CONFIG_FILE")"
  [[ -f "$GHOSTTY_CONFIG_FILE" ]] || touch "$GHOSTTY_CONFIG_FILE"

  if ! grep -qF '# Ghostty theme and appearance' "$GHOSTTY_CONFIG_FILE"; then
    printf '\n# Ghostty theme and appearance\n' >> "$GHOSTTY_CONFIG_FILE"
  fi

  upsert_ghostty_setting "font-size" "14"
  upsert_ghostty_setting "theme" "TokyoNight"
  upsert_ghostty_setting "background-opacity" "0.92"
  upsert_ghostty_setting "background-blur" "20"
  upsert_ghostty_setting "window-padding-x" "12"
  upsert_ghostty_setting "window-padding-y" "10"
  upsert_ghostty_setting "window-theme" "dark"
  upsert_ghostty_setting "macos-titlebar-style" "transparent"

  log "Ghostty theme and appearance configured in $GHOSTTY_CONFIG_FILE"
}

offer_set_default_shell() {
  local zsh_path
  if [[ "$(detect_os)" == "macos" && -x /bin/zsh ]]; then
    zsh_path="/bin/zsh"
  else
    zsh_path="$(command -v zsh || true)"
  fi
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
        printf '%s\n' "$zsh_path" | run_sudo tee -a /etc/shells >/dev/null
      fi
    fi
    chsh -s "$zsh_path" || warn "chsh failed. You may need to run it manually: chsh -s $zsh_path"
  else
    warn "Skipping default shell change."
  fi
}

main() {
  ui_init || true

  run_step_or_plain "Installing prerequisites" install_packages || die "Prerequisite installation failed."
  run_step_or_plain "Installing Oh My Zsh" install_oh_my_zsh || die "Oh My Zsh installation failed."
  run_step_or_plain "Installing plugins" install_plugins || die "Plugin installation failed."
  run_step_or_plain "Updating ~/.zshrc" configure_zsh_shell || die "Shell configuration failed."
  run_step_or_plain "Configuring Starship" configure_starship || die "Starship configuration failed."
  run_step_or_plain "Configuring Zellij" configure_zellij || die "Zellij configuration failed."
  run_step_or_plain "Configuring Ghostty" configure_ghostty || die "Ghostty configuration failed."

  if (( UI_INTERACTIVE )); then
    UI_CURRENT_PHASE="Complete"
    ui_set_phase_state "Installing prerequisites" "done"
    ui_set_phase_state "Installing Oh My Zsh" "done"
    ui_set_phase_state "Installing plugins" "done"
    ui_set_phase_state "Updating ~/.zshrc" "done"
    ui_set_phase_state "Configuring Starship" "done"
    ui_set_phase_state "Configuring Zellij" "done"
    ui_set_phase_state "Configuring Ghostty" "done"
    UI_LOG_LINES=("Setup complete. Start a new terminal or run: exec zsh")
    ui_wait_for_key
    ui_cleanup
  fi

  log "Done."
  echo "Next: start a new terminal, or run: exec zsh"
  offer_set_default_shell
}

main "$@"
