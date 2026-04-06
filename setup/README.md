# Terminal Setup Script

This folder contains `setup_term.sh`, a bootstrap script for setting up a fresh terminal environment on a new machine.

It is designed for:
- **macOS** with `Homebrew`
- **Debian/Ubuntu-style Linux** with `apt`

---

## What it installs and configures

The script sets up:

- `git`, `curl`
- `fzf`
- `zsh` configuration via `oh-my-zsh` and plugins *(macOS uses the built-in `zsh`)*
- `gh` (GitHub CLI)
- `jd`
- `lazygit`
- `lsd` (`ls` replacement)
- [`starship`](https://starship.rs/) prompt
- [`zellij`](https://zellij.dev/)
- Saved Zellij IDE layout: `zellij --layout ide`, `zjide`, or `zjide <session-name>`
- [`oh-my-zsh`](https://ohmyz.sh/)
- Zsh plugins:
  - `zsh-autosuggestions`
  - `zsh-autocomplete`
  - `zsh-syntax-highlighting`
- `Ghostty` on macOS
- Ghostty theme defaults and appearance settings
- Starship preset: `catppuccin-powerline`

---

## Quick start

### Run from this repo

```bash
bash setup/setup_term.sh
```

### Run after cloning on a new machine

```bash
git clone https://github.com/fillmore/personal.git ~/personal && bash ~/personal/setup/setup_term.sh
```

### One-liner from a raw hosted script

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/fillmore/personal/master/setup/setup_term.sh)"
```

> Run it as your normal user account, **not** with `sudo`. On a fresh macOS install, Homebrew may prompt for your administrator password during setup.

---

## Zellij installation behavior

### macOS
Uses Homebrew:

```bash
brew install gh jd fzf lsd lazygit starship zellij
```

### Debian / Ubuntu
The script installs the baseline system dependencies and `gh` via `apt` (or the official GitHub CLI apt repository), then uses Homebrew for the newer interactive CLI tools:

```bash
brew install fzf jd lsd lazygit starship zellij
```

This keeps `fzf` and `lsd` newer than the distro packages and uses the same Homebrew path as the fallback for `zellij`, `lazygit`, `jd`, and `starship` when needed.

---

## Files the script updates

- `~/.zshrc`
- `~/.config/starship.toml`
- `~/.config/zellij/layouts/ide.kdl`
- `~/.config/ghostty/config.ghostty` *(macOS only)*

It also ensures `~/.local/bin` is on your `PATH` for user-local binaries when needed.

---

## Notes

- On **macOS**, the script will install `Git` via the Xcode Command Line Tools if needed, install `Homebrew` automatically if it is missing, and use the built-in `zsh` instead of installing it.
- On **Linux**, the script expects `sudo` access and may install Homebrew automatically if it is missing.
- On **Linux**, including **WSL**, the script uses Homebrew for the newer CLI tools and adds the appropriate `brew shellenv` lines to `~/.zshrc`.
- On Linux, the script can optionally set `zsh` as your default shell. On macOS, it skips that prompt.
- It is intended to be safe to re-run if you want to refresh the setup.

---

## After running

Open a new terminal or run:

```bash
exec zsh
```

To launch the saved split layout shown in the screenshot style:

```bash
zjide
# or
zellij --layout ide
```

To start it with a named Zellij session (attach if it already exists, otherwise create it with the IDE layout):

```bash
zjide work
```
