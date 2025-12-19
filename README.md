# zsh-snip

A lightweight zsh snippet manager using fzf for fuzzy search.

Highlights:

- Save current prompt, `CTRL-x CTRL-s` (user) or `CTRL-x CTRL-p` (project-local)
- Search snippets with `fzf`
- Store each snippet in a separate file for easy editing
- Supports multi-line snippets
- Project-local snippets via `.zsh-snip` directory

![zsh-snip demo](./demo/demo.gif)

## Installation

Requires [`fzf`](https://github.com/junegunn/fzf) to be installed.

Optionally install [`bat`](https://github.com/sharkdp/bat) for syntax highlighting in preview.

### Oh My Zsh

When you are using [oh-my-zsh](https://ohmyz.sh/), you can add it as plugin:

```zsh
git clone https://github.com/gregmuellegger/zsh-snip ~/.oh-my-zsh/custom/plugins/zsh-snip
```

Then add `zsh-snip` to your plugins in `~/.zshrc`:

```zsh
plugins=(... zsh-snip)
```

### Manual

Or place the file somewhere on the disk and source it in your `.zshrc`:

```zsh
curl -fsSL https://raw.githubusercontent.com/gregmuellegger/zsh-snip/main/zsh-snip.plugin.zsh -o ~/.local/share/zsh-snip.plugin.zsh
echo 'source ~/.local/share/zsh-snip.plugin.zsh' >> ~/.zshrc
source ~/.local/share/zsh-snip.plugin.zsh
```

## Usage

### Save a snippet

Press `Ctrl+X Ctrl+S` to save a user snippet, or `Ctrl+X Ctrl+P` to save a project-local snippet. Your editor opens with the snippet file - edit the name to something memorable, then save and quit.

**Tip:** Add a trailing comment to your command and it becomes the description automatically:

```zsh
docker run --rm -it -v $(pwd):/app node:20 bash  # node shell with current dir mounted
```

Saves as `~/.local/share/zsh-snip/docker-1`

```
# name: docker-1
# description: node shell with current dir mounted
# created: 2025-01-15T14:32:00Z
# ---
docker run --rm -it -v $(pwd):/app node:20 bash
```

You can change the `name:` tag, the file will be renamed to match accordingly.
E.g. change to something like `node-shell` or `docker/node-shell`
(subdirectories supported) - the file is renamed when you save.

### Find a snippet

Press `Ctrl+X Ctrl+X` to search snippets with fzf. Both user and local snippets are shown:
- `~` prefix: user snippets (from `~/.local/share/zsh-snip`)
- `!` prefix: project-local snippets (from `.zsh-snip` in project directory)

**Tip:** Your current command line is used as the initial search query. Type `docker` then `Ctrl+X Ctrl+X` to jump straight to your docker snippets.

| Key | Action |
|-----|--------|
| `Enter` | Replace command line with snippet |
| `Ctrl+X` | Execute snippet as script with arguments (see below) |
| `Alt+X` | Wrap snippet as anonymous function for manual args |
| `Ctrl+I` | Insert snippet at cursor position |
| `Ctrl+E` | Edit snippet file in your editor |
| `Ctrl+N` | Duplicate snippet and edit the copy |
| `Ctrl+D` | Delete snippet (asks for confirmation) |
| `Alt+E` | Insert snippet and open editor to modify before running |

### Execute snippets as scripts

Use `Ctrl+X` to execute a snippet as an anonymous function. The snippet is wrapped in `() { ... }` which allows positional parameters (`$1`, `$2`, etc.) to work.

**Simple snippets (no arguments):** Pressing `Ctrl+X` executes immediately and adds the command to your history:

```zsh
() { # docker/prune: Remove unused containers and images
docker system prune -af
} ""
```

**Snippets with arguments:** Add an `args:` header to prompt for arguments:

```bash
# name: check-ssl
# description: Check SSL certificate for a domain
# args: <domain>
# ---
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
  echo "Usage: check-ssl <domain>"
  return 1
fi
echo "Checking $DOMAIN ..."
echo | openssl s_client -showcerts -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null \
  | openssl x509 -inform pem -noout -text
```

When you select this snippet and press `Ctrl+X`, you'll see a prompt with the args hint:

```
# Check SSL certificate for a domain
check-ssl <domain>: example.com
```

Type your arguments and press Enter. The snippet runs immediately and is added to your history.

**Using `Alt+X`:** If you prefer to see/edit the command before running, `Alt+X` pastes the wrapped function into your command line:

```zsh
() { # check-ssl: Check SSL certificate for a domain
DOMAIN=$1
...
}
```

You can then add arguments and press Enter.

**Note:** Use `return` instead of `exit` in scripts intended for this feature. Using `exit` will close your shell session.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ZSH_SNIP_DIR` | `~/.local/share/zsh-snip` | Where user snippets are stored (respects `$XDG_DATA_HOME`) |
| `ZSH_SNIP_EDITOR` | `$EDITOR` or `vim` | Editor for snippet editing |
| `ZSH_SNIP_LOCAL_PATH` | `.zsh-snip` | Directory name for project-local snippets (set to empty string to disable) |

## Storage

Snippets are stored as individual files in `~/.local/share/zsh-snip/`, making
them easy to browse, edit, and sync via git. Subdirectories are supported for
organization. Hidden files are ignored (i.e. starting with `.`).

```
~/.local/share/zsh-snip/
├── node-shell
├── staged-diff
├── docker/
│   ├── cleanup
│   └── prune-all
├── k8s/
│    └── pods-not-running
└── .git  # ignored, because hidden file
```

## Project-Local Snippets

You can also have project-specific snippets by creating a `.zsh-snip` directory in your project. When searching, zsh-snip looks for this directory from the current working directory up to the root.

Use `Ctrl+X Ctrl+P` to save a snippet locally. If no `.zsh-snip` directory exists, one is created in the current directory.

```
my-project/
├── .zsh-snip/
│   ├── build
│   └── deploy
├── src/
└── package.json
```

This is useful for project-specific commands that don't belong in your user snippets. You can commit `.zsh-snip` to version control to share snippets with your team.

## CLI Interface

For scripting and automation, use the `zsh-snip` command:

```zsh
zsh-snip list [filter]      # List snippets (filter is glob pattern)
zsh-snip path <name>        # Show full path to snippet file
zsh-snip expand <name>      # Output snippet content (no header)
zsh-snip exec <name> [args] # Execute snippet with arguments
```

### Options

| Option | Commands | Description |
|--------|----------|-------------|
| `--user` | all | Only user snippets (`~/.local/share/zsh-snip`) |
| `--local` | all | Only project-local snippets (`.zsh-snip`) |
| `--names-only` | list | Output only snippet names |
| `--full-path` | list | Show full absolute paths |
| `--no-color` | list | Disable colored output |

### Examples

```zsh
# List all snippets
zsh-snip list

# List docker-related snippets
zsh-snip list 'docker*'

# Get snippet content for piping
zsh-snip expand my-snippet | pbcopy

# Execute a snippet with arguments
zsh-snip exec deploy-app prod v1.2.3

# List only local project snippets
zsh-snip list --local --names-only
```

### Scope Behavior

When both user and local snippets have the same name, local takes precedence. Use `--user` or `--local` to be explicit:

```zsh
zsh-snip expand deploy          # Uses local if exists, else user
zsh-snip expand --user deploy   # Always use user snippet
zsh-snip expand --local deploy  # Always use local snippet (error if not found)
```

## Example Snippets

The [`example-snippets/`](./example-snippets) directory contains snippets demonstrating different usage patterns:

| Snippet | Pattern |
|---------|---------|
| `docker/system-df` | Simple one-liner |
| `docker/rm-dangling-images` | Command substitution with `$(...)` |
| `check-ssl-certificate` | Multi-line script with `args:` header for prompting |
| `git-sync` | Chained commands with optional arguments |
| `templates/gitignore-node` | Heredoc template for generating files |

Copy any of these to your snippets directory to use them:

```zsh
cp example-snippets/git-sync ~/.local/share/zsh-snip/
```

## Claude Code Skill

A [Claude Code skill](https://code.claude.com/docs/en/skills) is included that teaches Claude how to create zsh-snip snippets. Install it to let Claude generate snippets on request:

```zsh
mkdir -p ~/.claude/skills/zsh-snip
curl -fsSL https://raw.githubusercontent.com/gregmuellegger/zsh-snip/main/.claude/skills/zsh-snip/SKILL.md \
  -o ~/.claude/skills/zsh-snip/SKILL.md
```

Then ask Claude things like "create a snippet that..." and it will write properly formatted snippets to your snippets directory.
