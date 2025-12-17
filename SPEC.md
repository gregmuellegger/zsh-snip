# zsh-snip - Shell Snippet Manager

A lightweight zsh snippet manager using fzf for fuzzy search.

## Overview

Save and retrieve shell commands as snippets. Each snippet is stored as an individual file, making the collection easy to browse, edit, and sync via git.

## Storage

### Location
```
~/.local/share/zsh-snip/
├── git-1
├── git-2
├── docker/
│   ├── cleanup
│   └── run-rm
├── kubectl-1
└── ...
```

Subdirectories are supported for organization.

### File Naming

Files are named `{command}-{id}` where:
- `{command}` is the primary command extracted from the snippet (see extraction rules below)
- `{id}` is an auto-incrementing integer to avoid collisions

**Command extraction rules** (in order):
1. Skip variable assignments: `FOO=bar git push` → `git`
2. Skip `sudo`: `sudo apt install` → `apt`
3. Skip subshell prefixes: `(cd /tmp; make)` → `cd`
4. Use first word otherwise: `git diff | grep foo` → `git`

### File Format

```
# name: <filename - change to rename/move>
# description: <user-provided description>
# created: <ISO 8601 timestamp>
# ---
<command content - may be multiline>
```

The `name` field controls the filename. Edit it to rename or move the snippet (including into subdirectories like `docker/run-rm`).

Example:
```
# name: git-1
# description: Show staged changes excluding vendor
# created: 2025-01-15T14:32:00Z
# ---
git diff --cached | grep -v vendor/
```

Example with subdirectory:
```
# name: docker/cleanup
# description: Remove dangling images
# created: 2025-01-15T14:35:00Z
# ---
docker image prune -f
```

## Keybindings

| Binding | Action |
|---------|--------|
| `CTRL-X CTRL-S` | Save current command line as a new snippet |
| `CTRL-X CTRL-R` | Open fzf to search and select a snippet |

### During fzf selection

| Binding | Action |
|---------|--------|
| `Enter` | Insert selected snippet into command line |
| `CTRL-E` | Open snippet file in `$EDITOR` |
| `ALT-E` | Insert snippet into command line, then open editor on the command (like `fc`) |

## Behavior

### Saving a snippet (CTRL-X CTRL-S)

1. Read current `BUFFER` content
2. If empty, abort
3. Extract trailing comment as description (e.g., `git push # deploy` → description is "deploy")
4. Extract primary command and generate default filename
5. Write snippet file with metadata header
6. Open in `$EDITOR` for user to edit name/description
7. On save, if `# name:` was changed, rename/move file accordingly
8. Confirm with full path: `Saved: ~/.local/zsh-snip/git-3`

### Searching snippets (CTRL-X CTRL-R)

1. Search all snippet files by description and command content
2. Display in fzf:
   - Main pane: filename and description
   - Preview pane (bottom): full command with syntax highlighting (if `bat` available)
3. On selection, insert command into `BUFFER` and position cursor at end

### Editing (CTRL-E during fzf)

Opens the snippet file itself in `$EDITOR`. User can modify description, command, or delete the file entirely.

### Inline editing (ALT-E during fzf)

1. Insert snippet command into `BUFFER`
2. Immediately open `$EDITOR` on the buffer content (similar to `fc` behavior)
3. After editor closes, updated content becomes the new `BUFFER`

## Configuration

Environment variables (all optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `ZSH_SNIP_DIR` | `~/.local/share/zsh-snip` | Snippet storage directory (XDG_DATA_HOME) |
| `ZSH_SNIP_EDITOR` | `$EDITOR` or `vim` | Editor for snippet editing |

## Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| zsh | Yes | Shell integration |
| fzf | Yes | Fuzzy finder |
| bat | No | Syntax highlighting in preview |

## Non-goals

- **Sync**: Users manage their own sync (git, syncthing, etc.)
- **Placeholder/template system**: Use ALT-E for complex command editing
- **Bash support**: zsh only
- **GUI**: Terminal-based only
