# Terminal Setup Script

This folder contains `setup_term.sh`, a bootstrap script for setting up a fresh terminal environment on a new machine.

It is designed for:
- **macOS** with `Homebrew`
- **Debian/Ubuntu-style Linux** with `apt`

---

## What it installs and configures

The script sets up:

- `zsh`, `git`, `curl`
- [`starship`](https://starship.rs/) prompt
- [`zellij`](https://zellij.dev/)
- Saved Zellij IDE layout: `zellij --layout ide` or `zjide`
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
brew install zellij
```

### Debian / Ubuntu
The script tries the following in order:

1. `apt` package if available
2. `snap install zellij --classic` if `snap` is installed
3. fallback to the latest official **prebuilt binary** in `~/.local/bin/zellij`

This avoids compiling Rust from source.

---

## Files the script updates

- `~/.zshrc`
- `~/.config/starship.toml`
- `~/.config/zellij/layouts/ide.kdl`
- `~/.config/ghostty/config.ghostty` *(macOS only)*

It also ensures `~/.local/bin` is on your `PATH` when needed.

---

## Notes

- On **macOS**, the script will install `Git` via the Xcode Command Line Tools if needed, and then install `Homebrew` automatically if it is missing.
- On **Linux**, the script expects `sudo` access.
- At the end, the script can optionally set `zsh` as your default shell.
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
