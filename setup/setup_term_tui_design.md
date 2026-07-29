# setup_term.sh progress TUI design

## Goal

Add a lightweight terminal UI to `setup/setup_term.sh` so the user can see which setup phase is active, which phases have succeeded, and the most recent shell output without losing the current script behavior in non-interactive environments.

## Constraints

- Keep the script compatible with CI and redirected output.
- Avoid adding new external dependencies.
- Preserve the existing setup flow and shell behavior.
- Minimize risk to existing users who run the script in plain terminals.

## Design

### 1. Interactive detection

The script checks whether it is running in an interactive TTY and not under `CI`:

- `[[ -t 1 ]]`
- `TERM` is not `dumb`
- `CI` is unset

If these conditions are not met, the script remains in the current plain logging mode.

### 2. Phase-based state model

The UI tracks a fixed list of setup phases:

- Installing prerequisites
- Installing Oh My Zsh
- Installing plugins
- Updating ~/.zshrc
- Configuring Starship
- Configuring Zellij
- Configuring Ghostty

Each phase has a state:

- pending
- running
- done
- failed

This makes the UI deterministic and easy to reason about while keeping the script logic simple.

### 3. TUI rendering

When interactive mode is active, the script clears the terminal and redraws a compact status screen:

- title: `setup_term.sh`
- progress count: `done/total`
- per-step status line with a visible marker
- recent output excerpt from the most recent step
- current phase label

The renderer reads the terminal dimensions with `tput` on each refresh. The
outer border and log width expand to the available columns, while the number
of log rows uses and pads the remaining terminal height after the fixed status
rows. Every rendered row is enclosed in an ASCII frame, with horizontal
dividers between the header, phase list, and live output. One terminal row
remains unused to avoid scrolling on the final newline. It falls back to 80
columns by 24 rows when terminal dimensions are unavailable.

A small ASCII/Unicode status marker keeps the UI readable in most terminals, and each state uses a different ANSI color:

- green for `done`
- cyan for `running`
- red for `failed`
- yellow for `pending`

This makes the step state visible at a glance without relying on a full-screen widget system.

### 4. Step execution wrapper

The script introduces a small wrapper that runs a phase function under a captured log stream:

- set the phase to `running`
- render the screen
- execute the phase in the background
- stream the current tail of stdout/stderr into the UI while the step is active
- mark the phase `done` or `failed`
- show the final tail of the captured output in the UI
- render again

This keeps the terminal clean while still surfacing useful failure details and live output for the currently running step.

### 5. Fallback behavior

If the user runs the script in a non-interactive context, the original `log`, `warn`, and `die` behavior remains unchanged. The script still prints plain messages and exits normally.

### 6. Error handling

If a phase fails:

- the phase is marked failed in the UI
- the captured log tail remains visible
- the script exits with the existing `die` messaging to preserve current failure semantics

### 7. Implementation strategy

The script uses a tiny internal abstraction:

- `ui_init()`
- `ui_render()`
- `ui_run_step()`
- `run_step_or_plain()`

This lets the script share one code path for both TTY and non-TTY execution while only adding UI behavior when interactive mode is available.

## Why this design

This approach is intentionally small:

- no external terminal library
- no dependency on `gum`, `dialog`, or `whiptail`
- minimal code churn in the setup flow
- still gives a clear sense of progress during long-running operations like package installation and plugin setup

## Validation

The script is validated with shell syntax checking to ensure the TUI helpers and new wrappers do not break the existing Bash script.
