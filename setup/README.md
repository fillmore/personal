# Terminal Setup Script

This folder contains `setup_term.sh`, a bootstrap script for setting up a fresh terminal environment or repairing an existing Zsh configuration.

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
- `jq`
- `lazygit`
- `lsd` (`ls` replacement)
- `yq` (YAML processor)
- `btop` system monitor
- [`starship`](https://starship.rs/) prompt
- [`zellij`](https://zellij.dev/)
- Saved Zellij IDE layout: `zellij --layout ide`, `zjide`, or `zjide <session-name>`
- Zellij opens new panes with a login `zsh`, so aliases from login-shell setup also load there
- [`oh-my-zsh`](https://ohmyz.sh/)
- Zsh plugins:
  - `zsh-autosuggestions`
  - `zsh-autocomplete`
  - `zsh-syntax-highlighting`
- `Ghostty` on macOS
- Ghostty theme defaults, appearance settings, and `font-size = 14`
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

## Repair an existing Zsh setup

If pressing **Up** reports `command not found: _autocomplete__history_lines` or
`_autocomplete__unambiguous`, run:

```bash
bash setup/setup_term.sh --repair-zsh
exec zsh
```

This mode requires Zsh, Perl, Oh My Zsh, and all three plugins to be installed
already. It does **not** install or update packages/plugins, change your default
shell, or rewrite Starship, Zellij, or Ghostty settings.

Both full setup and repair mode:

- Back up existing `.zshrc` and `.zshenv` files beside the originals as
  `.zshrc.setup-term-backup.XXXXXX` and `.zshenv.setup-term-backup.XXXXXX`.
- Remove the three managed plugins from `plugins=(...)` and migrate the old
  conditional/direct `source` blocks, including the earlier manual autocomplete fix.
  Other plugin names, aliases, and user configuration are retained.
- Load autocomplete once, **before** Oh My Zsh initializes completion; load
  autosuggestions afterward and syntax highlighting last.
- Set `skip_global_compinit=1` in `.zshenv` so Ubuntu does not initialize completion
  too early, and preserve autocomplete's arrow-key bindings after Oh My Zsh loads.
- Remove stale `.zcompdump`/`.zcompdump-*` caches and their compiled `.zwc` files,
  plus the autocomplete cache at `${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compdump`.
  An exported `ZSH_COMPDUMP` path is also cleared. Zsh rebuilds these on restart.
- Check the generated files with `zsh -n` before writing the completion changes,
  preserve dotfile symlinks, and produce the same configuration when rerun.

Use a **new shell**, not `source ~/.zshrc`: the old process still has the previous
completion functions and widgets in memory.

The script honors an exported `ZDOTDIR` for `.zshrc`/`.zshenv` and `ZSH_CUSTOM`
for plugin locations. If these are set only inside your dotfiles, pass the same
values in the environment when running setup. Migration supports ordinary
literal plugin arrays and standalone source/compinit commands; dynamic plugin
lists or compound completion commands may require manual cleanup. Unsupported
forms are reported rather than guessed.

---

## CLI installation behavior

### macOS
Uses Homebrew:

```bash
brew install gh jd jq fzf lsd lazygit starship yq zellij btop
```

### Debian / Ubuntu
The script installs the baseline system dependencies with `apt`, then uses Homebrew for the CLI tools so the versions stay consistent with macOS:

```bash
brew install gh jd jq fzf lsd lazygit starship yq zellij
```

That means `fzf`, `gh`, `jd`, `jq`, `lsd`, `lazygit`, `starship`, `yq`, `zellij`, and `btop` all come from Homebrew on Debian/Ubuntu too.

For `btop`, the script installs it via Homebrew so the version stays aligned with macOS.

---

## Files the script updates

- `~/.zshrc`
- `~/.zshenv`
- `~/.config/starship.toml`
- `~/.config/zellij/layouts/ide.kdl`
- `~/.config/zellij/config.kdl`
- `~/.local/bin/zsh-login`
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

## Regression checks

With Python 3, Perl, and Zsh installed:

```bash
bash -n setup/setup_term.sh
python3 -B -m unittest discover -s setup -p 'test_setup_term.py' -v
```

The tests use temporary home directories and stub plugins; they do not install
packages or modify your real dotfiles.

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
