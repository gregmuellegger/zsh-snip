# zsh-snip - Shell Snippet Manager
# Source this file in your .zshrc: source /path/to/zsh-snip.zsh

# Configuration
ZSH_SNIP_DIR="${ZSH_SNIP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip}"
ZSH_SNIP_EDITOR="${ZSH_SNIP_EDITOR:-${EDITOR:-vim}}"

# Ensure snippet directory exists
[[ -d "$ZSH_SNIP_DIR" ]] || mkdir -p "$ZSH_SNIP_DIR"

# Autoload edit-command-line for ALT-E functionality
autoload -Uz edit-command-line
zle -N edit-command-line

# Extract the primary command from a command string
# Skips: variable assignments, sudo, subshell prefixes
_zsh_snip_extract_command() {
  local input="$1"
  local word

  # Remove leading whitespace
  input="${input#"${input%%[![:space:]]*}"}"

  # Process words to find the primary command
  while [[ -n "$input" ]]; do
    # Get first word
    word="${input%% *}"

    # Skip variable assignments (FOO=bar)
    if [[ "$word" == *=* ]]; then
      input="${input#"$word"}"
      input="${input#"${input%%[![:space:]]*}"}"
      continue
    fi

    # Skip sudo
    if [[ "$word" == "sudo" ]]; then
      input="${input#"$word"}"
      input="${input#"${input%%[![:space:]]*}"}"
      continue
    fi

    # Skip subshell prefix - extract first command from inside
    if [[ "$word" == "("* ]]; then
      input="${input#"("}"
      input="${input#"${input%%[![:space:]]*}"}"
      continue
    fi

    # Found the primary command
    echo "$word"
    return
  done

  # Fallback: return "snippet" if nothing found
  echo "snippet"
}

# Find the next available ID for a command prefix
_zsh_snip_next_id() {
  local cmd="$1"
  local max_id=0
  local id
  local file
  local files

  # Use (N) glob qualifier to return empty array if no matches
  files=("$ZSH_SNIP_DIR"/"$cmd"-*(N))

  for file in "${files[@]}"; do
    [[ -e "$file" ]] || continue
    file="${file##*/}"      # basename
    id="${file##"$cmd"-}"   # remove prefix
    if [[ "$id" =~ ^[0-9]+$ ]] && (( id > max_id )); then
      max_id=$id
    fi
  done

  echo $(( max_id + 1 ))
}

# Write a snippet file
_zsh_snip_write() {
  local filepath="$1"
  local name="$2"
  local description="$3"
  local command="$4"
  local timestamp

  timestamp=$(date -Iseconds)

  # Create parent directory if path contains subdirs (e.g., git/add)
  mkdir -p "${filepath%/*}"

  cat > "$filepath" <<EOF
# name: $name
# description: $description
# created: $timestamp
# ---
$command
EOF
}

# Read name from a snippet file
_zsh_snip_read_name() {
  local filepath="$1"
  sed -n 's/^# name: //p' "$filepath"
}

# Open file in editor with cursor at name value (line 1, column 9)
_zsh_snip_edit_at_name() {
  local filepath="$1"
  local editor="${ZSH_SNIP_EDITOR:-${EDITOR:-vim}}"
  local editor_name="${editor##*/}"

  case "$editor_name" in
    vim|nvim|vi)
      "$editor" '+call cursor(1,9)' "$filepath"
      ;;
    nano)
      "$editor" +1,9 "$filepath"
      ;;
    code|code-insiders)
      "$editor" -g "$filepath:1:9"
      ;;
    *)
      "$editor" "$filepath"
      ;;
  esac
}

# Read command content from a snippet file (everything after # ---)
_zsh_snip_read_command() {
  local filepath="$1"
  sed -n '/^# ---$/,$ { /^# ---$/d; p; }' "$filepath"
}

# Read description from a snippet file
_zsh_snip_read_description() {
  local filepath="$1"
  sed -n 's/^# description: //p' "$filepath"
}

# Read first line of command, truncated for display
_zsh_snip_read_command_preview() {
  local filepath="$1"
  local max_len="${2:-50}"
  local first_line
  first_line=$(sed -n '/^# ---$/,$ { /^# ---$/d; p; q; }' "$filepath")
  if (( ${#first_line} > max_len )); then
    echo "${first_line[1,$max_len]}..."
  else
    echo "$first_line"
  fi
}

# Extract trailing comment from a single-line command (e.g., "git commit # amend" -> "amend")
# If comment contains "name: desc", returns just "desc"
# Only works for one-liners to avoid matching # in heredocs/scripts
# Note: Requires a char before #, so "# comment" (comment-only line) returns empty - intentional
_zsh_snip_extract_trailing_comment() {
  local input="$1"
  local comment

  # Only extract from one-liners
  [[ "$input" == *$'\n'* ]] && return

  # Match # followed by text at end of line, but not inside quotes
  # Simple approach: just look for last # not preceded by backslash
  if [[ "$input" =~ [^\\]#[[:space:]]*(.+)$ ]]; then
    comment="${match[1]}"
    # If comment has "name: description" format, return just the description
    if [[ "$comment" == *:* ]]; then
      echo "${comment#*: }"
    else
      echo "$comment"
    fi
  fi
}

# Extract name from trailing comment (e.g., "git commit # myname: desc" -> "myname")
# Returns empty if no name: prefix in comment or if multi-line
# Note: Requires a char before #, so "# name: desc" returns empty - intentional
_zsh_snip_extract_trailing_name() {
  local input="$1"
  local comment

  # Only extract from one-liners
  [[ "$input" == *$'\n'* ]] && return

  if [[ "$input" =~ [^\\]#[[:space:]]*(.+)$ ]]; then
    comment="${match[1]}"
    # If comment has "name: description" format, return the name part
    if [[ "$comment" == *:* ]]; then
      echo "${comment%%:*}"
    fi
  fi
}

# Slugify a string for use as filename (remove/replace invalid chars)
_zsh_snip_slugify() {
  local input="$1"
  # Replace spaces and problematic chars with dashes, keep alphanumeric, dash, underscore, slash
  echo "$input" | tr -cs 'a-zA-Z0-9_/-' '-' | sed 's/^-//;s/-$//'
}

# Save current buffer as snippet (CTRL-X CTRL-S)
_zsh_snip_save() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  local buffer="$BUFFER"
  local cmd
  local id
  local default_name
  local filepath
  local command_to_save
  local description
  local new_name
  local new_path

  # Abort if buffer is empty
  if [[ -z "${buffer// /}" ]]; then
    zle -M "zsh-snip: Nothing to save"
    return 1
  fi

  # Extract name and description from trailing comment if present (one-liners only)
  local comment_name=$(_zsh_snip_extract_trailing_name "$buffer")
  description=$(_zsh_snip_extract_trailing_comment "$buffer")
  command_to_save="$buffer"
  if [[ -n "$description" || -n "$comment_name" ]]; then
    # Remove only the trailing comment (from last #, not first)
    # Using % (shortest match from end) instead of %% (longest match)
    command_to_save="${buffer%\#*}"
    # Trim trailing whitespace (# means zero-or-more in EXTENDED_GLOB)
    command_to_save="${command_to_save%%[[:space:]]#}"
  fi

  # Generate default filename - use comment name if provided, otherwise extract from command
  if [[ -n "$comment_name" ]]; then
    # Slugify name to ensure valid filename
    comment_name=$(_zsh_snip_slugify "$comment_name")
    # Check if name exists, add number if collision
    if [[ -e "$ZSH_SNIP_DIR/$comment_name" ]]; then
      id=$(_zsh_snip_next_id "$comment_name")
      default_name="$comment_name-$id"
    else
      default_name="$comment_name"
    fi
  else
    cmd=$(_zsh_snip_extract_command "$buffer")
    # Slugify to handle edge cases (e.g., commands with special chars)
    cmd=$(_zsh_snip_slugify "$cmd")
    [[ -z "$cmd" ]] && cmd="snippet"
    id=$(_zsh_snip_next_id "$cmd")
    default_name="$cmd-$id"
  fi
  filepath="$ZSH_SNIP_DIR/$default_name"

  # Write snippet and open in editor, cursor at start of name value
  _zsh_snip_write "$filepath" "$default_name" "$description" "$command_to_save"
  _zsh_snip_edit_at_name "$filepath"

  # Check if name was changed in editor
  new_name=$(_zsh_snip_read_name "$filepath")
  if [[ -n "$new_name" && "$new_name" != "$default_name" ]]; then
    new_path="$ZSH_SNIP_DIR/$new_name"
    if [[ -e "$new_path" ]]; then
      echo "Error: '$new_name' already exists, keeping as '$default_name'"
    else
      # Create parent directory if name contains subdirs (e.g., docker/run-rm)
      [[ "$new_name" == */* ]] && mkdir -p "${new_path%/*}"
      mv "$filepath" "$new_path"
      filepath="$new_path"
    fi
  fi

  zle reset-prompt
  zle -M "Saved: $filepath"
}

# Insert text at cursor position in BUFFER
# Modifies global BUFFER and CURSOR variables
_zsh_snip_insert_at_cursor() {
  local text="$1"
  BUFFER="${BUFFER:0:$CURSOR}${text}${BUFFER:$CURSOR}"
  CURSOR=$((CURSOR + ${#text}))
}

# Search and select snippet (CTRL-X CTRL-R)
_zsh_snip_search() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  # Check fzf is available
  if ! command -v fzf &>/dev/null; then
    zle -M "zsh-snip: fzf is required but not found"
    return 1
  fi

  local selected
  local key
  local filepath
  local command
  local preview_cmd
  local fzf_output
  local snip_dir="$ZSH_SNIP_DIR"

  # Build preview command - expand snip_dir now since fzf runs in subprocess
  if command -v bat &>/dev/null; then
    preview_cmd="bat --style=plain --color=always --language=bash '${snip_dir}/'{1}"
  else
    preview_cmd="cat '${snip_dir}/'{1}"
  fi

  # Check if any snippets exist (search recursively for subdirs)
  local files=("$snip_dir"/**/*(N.))
  if (( ${#files[@]} == 0 )); then
    zle -M "zsh-snip: No snippets found"
    return 1
  fi

  # Generate list: filename<tab>description<tab>command_preview
  # Use column for auto-alignment based on actual content widths
  # Scale column widths based on terminal width
  local term_width=${COLUMNS:-80}
  local desc_width=$(( term_width / 4 ))        # 25% for description
  local cmd_width=$(( term_width / 3 ))         # 33% for command preview
  (( desc_width < 20 )) && desc_width=20
  (( cmd_width < 30 )) && cmd_width=30

  fzf_output=$(
    for f in "${files[@]}"; do
      [[ -f "$f" ]] || continue
      # Get relative path from snip_dir (handles subdirs)
      local name="${f#$snip_dir/}"
      # Skip dotfiles and files in dotdirs (e.g., .git/)
      [[ "$name" == .* || "$name" == */.* ]] && continue
      local desc=$(_zsh_snip_read_description "$f")
      local cmd_preview=$(_zsh_snip_read_command_preview "$f" "$cmd_width")
      # Truncate description
      if (( ${#desc} > desc_width )); then
        desc="${desc[1,$((desc_width - 1))]}…"
      fi
      # Use | as delimiter for column, then convert to tab for fzf
      printf '%s|%s|%s\n' "$name" "$desc" "$cmd_preview"
    done | column -t -s '|' -o $'\t' | fzf \
      --delimiter='\t' \
      --preview="$preview_cmd" \
      --preview-window=top:50% \
      --expect=ctrl-e,alt-e,ctrl-i \
      --header="ctrl-e: edit file | alt-e: edit inline | ctrl-i: insert at cursor" \
      --prompt="Snippet> "
  )

  # Parse fzf output: line 1 is key pressed, line 2 is selection
  key="${fzf_output%%$'\n'*}"
  selected="${fzf_output#*$'\n'}"
  selected="${selected%%$'\t'*}"  # Get filename before tab
  selected="${selected%%[[:space:]]#}"  # Trim trailing whitespace

  if [[ -z "$selected" ]]; then
    zle reset-prompt
    return
  fi

  filepath="$snip_dir/$selected"
  command=$(_zsh_snip_read_command "$filepath")

  case "$key" in
    ctrl-e)
      # Edit the snippet file
      "$ZSH_SNIP_EDITOR" "$filepath"
      # Check if name was changed in editor
      local new_name=$(_zsh_snip_read_name "$filepath")
      if [[ -n "$new_name" && "$new_name" != "$selected" ]]; then
        local new_path="$snip_dir/$new_name"
        if [[ -e "$new_path" ]]; then
          echo "Error: '$new_name' already exists, keeping as '$selected'"
        else
          # Create parent directory if name contains subdirs
          [[ "$new_name" == */* ]] && mkdir -p "${new_path%/*}"
          mv "$filepath" "$new_path"
          filepath="$new_path"
        fi
      fi
      # Fill edited command into buffer
      command=$(_zsh_snip_read_command "$filepath")
      BUFFER="$command"
      CURSOR=$#BUFFER
      ;;
    alt-e)
      # Insert into buffer and edit inline
      BUFFER="$command"
      CURSOR=$#BUFFER
      zle reset-prompt
      # Use zle edit-command-line to edit buffer (like fc)
      zle edit-command-line
      ;;
    ctrl-i)
      # Insert at cursor position without replacing buffer
      _zsh_snip_insert_at_cursor "$command"
      ;;
    *)
      # Replace buffer with snippet
      BUFFER="$command"
      CURSOR=$#BUFFER
      ;;
  esac

  zle reset-prompt
}

# Register widgets and keybindings
zle -N _zsh_snip_save
zle -N _zsh_snip_search

bindkey '^X^S' _zsh_snip_save
bindkey '^X^X' _zsh_snip_search
