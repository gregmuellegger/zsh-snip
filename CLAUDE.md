# Claude Instructions for zsh-snip

## Project Overview

A zsh snippet manager using fzf. Saves shell commands as files with metadata headers.

## Key Technical Details

### This is zsh, not bash
- Shellcheck won't help - it's bash-focused
- Use `zsh -n file.zsh` for basic syntax checking
- Tests are the main validation tool

### EXTENDED_GLOB is enabled
The plugin enables `EXTENDED_GLOB` for features like `[[:space:]]#` (zero-or-more).
This means `#` is special in patterns - escape as `\#` when matching literal `#`:
```zsh
# Wrong - causes "bad pattern" error:
${var%%#*}

# Correct:
${var%%\#*}
```

### zle widget context
Functions bound to keys run as zle widgets with special constraints:
- `$BUFFER` and `$CURSOR` control the command line
- `zle reset-prompt` redraws the prompt
- `zle -M "message"` shows a message below the prompt
- Regular `read` doesn't work well - use `read </dev/tty` with `stty sane`
- Colored output in widgets is tricky - `zle -M` doesn't interpret ANSI escapes

### File format
Snippets have this header structure:
```
# name: <filename>
# description: <optional description>
# args: <argument hints for ctrl-x prompt>
# created: <ISO 8601 timestamp>
# ---
<command content>
```

The `name` field controls the filename - changing it renames the file on save.

The `args` field is optional - when present, ctrl-x prompts for arguments using this as the hint (e.g., `<domain> [port]`). Without it, ctrl-x executes immediately.

Subfolders are supported, so a name of `<dir>/<subdir>/<filename>` should be supported (even if the dir/subdir does not exist yet)

### Storage location
Global snippets use XDG Base Directory spec:
```zsh
${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip
```

Project-local snippets are stored in `.zsh-snip` (configurable via `ZSH_SNIP_LOCAL_PATH`) in the project directory tree. The plugin walks up from `$PWD` to find the nearest `.zsh-snip` directory.

## Testing

Three test suites with increasing integration levels:

### Unit tests (`tests/test_zsh_snip.zsh`)

Tests covering individual functions and CLI interface. Mock `zle` and `bindkey` to source the plugin without terminal:
```zsh
function zle() { :; }
function bindkey() { :; }
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
```

### Integration tests (`tests/test_integration.zsh`)

Tests covering complete workflows with mock fzf. Tests search, save, edit, delete flows by simulating fzf output. Creates temporary directories with test snippets.

### E2E tests (`tests/test_e2e.zsh`)

Tests using tmux to simulate real terminal interaction. Tests actual keybindings (CTRL-X CTRL-S, CTRL-X CTRL-X) and real fzf behavior. Requires tmux and fzf installed.

### Running tests
```zsh
# Run all
zsh tests/test_zsh_snip.zsh
zsh tests/test_integration.zsh
zsh tests/test_e2e.zsh

# Quiet mode (only failures)
QUIET=1 zsh tests/test_zsh_snip.zsh

# Filter specific test
TEST_FILTER="save" zsh tests/test_e2e.zsh
```

## Keybindings

- `CTRL-X CTRL-S` - Save current command as global snippet
- `CTRL-X CTRL-P` - Save current command as project-local snippet
- `CTRL-X CTRL-X` - Search/expand snippets with fzf

During fzf (snippets show `~` prefix for global, `!` for local):
- `Enter` - Replace buffer with snippet
- `CTRL-X` - Execute as anonymous function (prompts for args, adds to history)
- `ALT-X` - Wrap as anonymous function in buffer for manual args
- `CTRL-I` - Insert snippet at cursor position
- `CTRL-E` - Edit snippet file
- `CTRL-N` - Duplicate snippet and edit the copy
- `CTRL-D` - Delete snippet (with confirmation)
- `ALT-E` - Insert and edit inline (like `fc`)

## CLI Interface

The `zsh-snip` function provides programmatic access to snippets:

```zsh
zsh-snip list [filter]      # List snippets (glob pattern filter)
zsh-snip expand <name>      # Output snippet content (no header)
zsh-snip exec <name> [args] # Execute snippet with arguments
```

Options:
- `--user` / `--local` - Filter by scope (local takes precedence by default)
- `--names-only` - (list) Output only names
- `--full-path` - (list) Show absolute paths

Implementation details:
- `_zsh_snip_cli_list()` - Handles listing with deduplication (local wins)
- `_zsh_snip_cli_expand()` - Outputs raw command content
- `_zsh_snip_cli_exec()` - Wraps in anonymous function, adds to history
- `_zsh_snip_cli_resolve()` - Resolves name to filepath with scope handling

## Files

- `zsh-snip.plugin.zsh` - Main plugin
- `tests/test_zsh_snip.zsh` - Unit tests
- `tests/test_integration.zsh` - Integration tests (mock fzf)
- `tests/test_e2e.zsh` - E2E tests (tmux)
- `README.md` - User documentation

## Common Pitfalls

### `vared` doesn't work inside zle widgets
`vared` (zsh's variable editor with readline support) silently exits when called from within a zle widget. This is because the widget is already running zle, and vared tries to take over but conflicts with the existing zle state.

**Workaround:** Use basic `read </dev/tty` instead. This means no arrow keys or CTRL shortcuts - only backspace works. For full editing, put content in `$BUFFER` and let the user edit it there.

### Output doesn't appear from zle widgets
`echo` and command output may not reach the terminal inside a zle widget context.

**Fix:** Redirect explicitly to `/dev/tty`:
```zsh
echo "message" >/dev/tty
eval "$cmd" </dev/tty >/dev/tty 2>&1
```
