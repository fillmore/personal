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
The script installs the baseline CLI tools via `apt`, and then adds `gh` from the distro or its official apt repository when needed:

1. `apt` package if available
2. otherwise, the official GitHub CLI apt repository

For `fzf`, the script installs the latest official release binary from GitHub into `/usr/local/bin/fzf` instead of relying on the older distro package.

```bash
FZF_VERSION="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p')"
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
curl -fL "https://github.com/junegunn/fzf/releases/latest/download/fzf-${FZF_VERSION}-linux_${ARCH}.tar.gz" -o fzf.tar.gz
tar -xzf fzf.tar.gz fzf
sudo install -m 755 fzf /usr/local/bin/fzf
rm -f fzf fzf.tar.gz
```

For `lsd`, the script also installs the latest official release binary from GitHub into `/usr/local/bin/lsd` instead of relying on the older distro package.

```bash
LSD_VERSION="$(curl -fsSL https://api.github.com/repos/lsd-rs/lsd/releases/latest | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p')"
ARCH=$(uname -m | sed -e 's/x86_64/x86_64-unknown-linux-gnu/' -e 's/aarch64/aarch64-unknown-linux-gnu/' -e 's/armv7l/arm-unknown-linux-gnueabihf/' -e 's/i686/i686-unknown-linux-gnu/')
curl -fL "https://github.com/lsd-rs/lsd/releases/latest/download/lsd-v${LSD_VERSION}-${ARCH}.tar.gz" -o lsd.tar.gz
tar -xzf lsd.tar.gz
sudo install -m 755 "lsd-v${LSD_VERSION}-${ARCH}/lsd" /usr/local/bin/lsd
rm -rf "lsd-v${LSD_VERSION}-${ARCH}" lsd.tar.gz
```

For `zellij`, the script tries the following in order:

1. `apt` package if available
2. fallback to the latest official **prebuilt binary** in `/usr/local/bin/zellij`

This avoids compiling Rust from source.

For `lazygit`, the script tries:

1. `apt install lazygit`
2. fallback to the latest official **prebuilt binary** in `/usr/local/bin/lazygit`

For **Ubuntu 24.04** and similar releases where the distro package may be missing or stale, this fallback follows the official [`jesseduffield/lazygit` Debian and Ubuntu instructions](https://github.com/jesseduffield/lazygit#debian-and-ubuntu) and installs the binary into `/usr/local/bin`.

For `jd`, the script tries:

1. `apt install jd`
2. fallback to the latest official **prebuilt binary** in `/usr/local/bin/jd`

The equivalent manual install on Linux is:

```bash
ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
curl -fL "https://github.com/josephburnett/jd/releases/latest/download/jd-${ARCH}-linux" -o jd
sudo install -m 755 jd /usr/local/bin/jd
rm -f jd
```

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
- On **Linux**, the script expects `sudo` access.
- On **Linux**, including **WSL**, the script keeps fallback-installed tools in `/usr/local/bin` for a system-wide path.
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
