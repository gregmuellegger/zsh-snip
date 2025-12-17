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
# created: <ISO 8601 timestamp>
# ---
<command content>
```

The `name` field controls the filename - changing it renames the file on save.

### Storage location
Uses XDG Base Directory spec:
```zsh
${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip
```

## Testing

Tests mock `zle` and `bindkey` to source the plugin without terminal:
```zsh
function zle() { :; }
function bindkey() { :; }
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
```

Run tests: `zsh tests/test_zsh_snip.zsh`

## Keybindings

- `CTRL-X CTRL-S` - Save current command as snippet
- `CTRL-X CTRL-X` - Search/expand snippets with fzf

During fzf:
- `Enter` - Insert snippet
- `CTRL-E` - Edit snippet file
- `ALT-E` - Insert and edit inline (like `fc`)

## Files

- `zsh-snip.plugin.zsh` - Main plugin
- `tests/test_zsh_snip.zsh` - Test suite
- `SPEC.md` - Detailed specification
- `README.md` - User documentation
