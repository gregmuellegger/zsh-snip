# zsh-snip

A lightweight zsh snippet manager using fzf for fuzzy search.

Highlights:

- Save current prompt, `CTRL-x CTRL-s`
- Search snippets with `fzf`
- Store each snippet in a separate file for easy editing
- Supports multi-line snippets

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

Or place the file somehwere on the disk and source it in your `.zshrc`:

```zsh
curl -fsSL https://raw.githubusercontent.com/gregmuellegger/zsh-snip/main/zsh-snip.plugin.zsh -o ~/.local/share/zsh-snip.plugin.zsh
echo 'source ~/.local/share/zsh-snip.plugin.zsh' >> ~/.zshrc
source ~/.local/share/zsh-snip.plugin.zsh
```

## Usage

### Save a snippet

Press `Ctrl+X Ctrl+S` to save the current command line. Your editor opens with the snippet file - edit the name to something memorable, then save and quit.

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

Press `Ctrl+X Ctrl+X` to search snippets with fzf. The snippets are searched through by name and description.

| Key | Action |
|-----|--------|
| `Enter` | Insert snippet into command line |
| `Ctrl+E` | Edit snippet file in your editor |
| `Alt+E` | Insert snippet and open editor to modify before running |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ZSH_SNIP_DIR` | `~/.local/share/zsh-snip` | Where snippets are stored (respects `$XDG_DATA_HOME`) |
| `ZSH_SNIP_EDITOR` | `$EDITOR` or `vim` | Editor for snippet editing |

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
