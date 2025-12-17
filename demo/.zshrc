# Minimal demo shell - no oh-my-zsh or p10k

# Basic interactive shell settings
setopt interactive_comments
setopt prompt_subst
autoload -Uz compinit && compinit
autoload -Uz add-zsh-hook

# Disable flow control so Ctrl-S works for keybindings
stty -ixon 2>/dev/null

# Simple prompt
PROMPT='%F{green}$%f '

# Load fzf
source /usr/share/doc/fzf/examples/key-bindings.zsh 2>/dev/null || true
source /usr/share/doc/fzf/examples/completion.zsh 2>/dev/null || true

# Load the plugin
source /workspaces/snip/zsh-snip.plugin.zsh
