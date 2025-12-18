# zsh-snip - Shell Snippet Manager
# Source this file in your .zshrc: source /path/to/zsh-snip.zsh

# Configuration
ZSH_SNIP_DIR="${ZSH_SNIP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip}"
ZSH_SNIP_EDITOR="${ZSH_SNIP_EDITOR:-${EDITOR:-vim}}"
ZSH_SNIP_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-.zsh-snip}"

# Ensure snippet directory exists
[[ -d "$ZSH_SNIP_DIR" ]] || mkdir -p "$ZSH_SNIP_DIR"

# Autoload edit-command-line for ALT-E functionality
autoload -Uz edit-command-line
zle -N edit-command-line

# Find local snippet directory by walking up from current directory
# Returns empty string if disabled or not found
_zsh_snip_find_local_dir() {
  # Disabled if ZSH_SNIP_LOCAL_PATH is empty
  [[ -z "$ZSH_SNIP_LOCAL_PATH" ]] && return

  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/$ZSH_SNIP_LOCAL_PATH" ]]; then
      echo "$dir/$ZSH_SNIP_LOCAL_PATH"
      return
    fi
    dir="${dir:h}"
  done
  # Check root as well
  [[ -d "/$ZSH_SNIP_LOCAL_PATH" ]] && echo "/$ZSH_SNIP_LOCAL_PATH"
}

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

# Generate a duplicate name for a snippet (docker-1 → docker-2)
_zsh_snip_duplicate_name() {
  local name="$1"
  local base
  local dir=""

  # Handle subdirectory: extract dir and filename
  if [[ "$name" == */* ]]; then
    dir="${name%/*}/"
    name="${name##*/}"
  fi

  # Strip trailing -N to get base name
  if [[ "$name" =~ ^(.+)-[0-9]+$ ]]; then
    base="${match[1]}"
  else
    base="$name"
  fi

  # Find next available ID
  local max_id=0
  local id
  local file
  local files

  files=("$ZSH_SNIP_DIR"/"$dir""$base"-*(N))

  for file in "${files[@]}"; do
    [[ -e "$file" ]] || continue
    file="${file##*/}"      # basename
    id="${file##"$base"-}"  # remove prefix
    if [[ "$id" =~ ^[0-9]+$ ]] && (( id > max_id )); then
      max_id=$id
    fi
  done

  echo "${dir}${base}-$(( max_id + 1 ))"
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

# Read args from a snippet file
_zsh_snip_read_args() {
  local filepath="$1"
  sed -n 's/^# args: //p' "$filepath"
}

# Wrap command in anonymous function syntax for execution
# Args: command [name] [description]
# Output: () { # name: description\n<command>\n}
_zsh_snip_wrap_anon_func() {
  local command="$1"
  local name="$2"
  local description="$3"
  # Strip trailing newline to avoid doubling
  command="${command%$'\n'}"

  # Build the opening line with name and/or description
  if [[ -n "$name" && -n "$description" ]]; then
    printf '() { # %s: %s\n' "$name" "$description"
  elif [[ -n "$name" ]]; then
    printf '() { # %s\n' "$name"
  elif [[ -n "$description" ]]; then
    printf '() { # %s\n' "$description"
  else
    printf '() {\n'
  fi

  # Add command and closing
  printf '%s\n} ' "$command"
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

# Search and select snippet (CTRL-X CTRL-X)
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
  local global_dir="$ZSH_SNIP_DIR"
  local local_dir=$(_zsh_snip_find_local_dir)
  # Pre-fill fzf query with current buffer content
  local initial_query="$BUFFER"

  # Build preview command using field 4 (full path)
  if command -v bat &>/dev/null; then
    preview_cmd="bat --style=plain --color=always --language=bash {4}"
  else
    preview_cmd="cat {4}"
  fi

  # Loop to allow returning to fzf after delete
  while true; do
    # Gather snippets from both global and local directories
    local global_files=("$global_dir"/**/*(N.))
    local local_files=()
    [[ -n "$local_dir" ]] && local_files=("$local_dir"/**/*(N.))

    if (( ${#global_files[@]} == 0 && ${#local_files[@]} == 0 )); then
      zle -M "zsh-snip: No snippets found"
      break
    fi

    # Scale column widths based on terminal width
    local term_width=${COLUMNS:-80}
    local desc_width=$(( term_width / 4 ))        # 25% for description
    local cmd_width=$(( term_width / 3 ))         # 33% for command preview
    (( desc_width < 20 )) && desc_width=20
    (( cmd_width < 30 )) && cmd_width=30

    # Generate list: prefix+name[US]description[US]preview[US]fullpath
    # Using ASCII unit separator (\x1f) to avoid conflicts with | in content
    local US=$'\x1f'
    fzf_output=$(
      {
        # Global snippets (prefix: ~)
        for f in "${global_files[@]}"; do
          [[ -f "$f" ]] || continue
          local name="${f#$global_dir/}"
          [[ "$name" == .* || "$name" == */.* ]] && continue
          local desc=$(_zsh_snip_read_description "$f")
          local cmd_preview=$(_zsh_snip_read_command_preview "$f" "$cmd_width")
          if (( ${#desc} > desc_width )); then
            desc="${desc[1,$((desc_width - 1))]}…"
          fi
          printf '~ %s%s%s%s%s%s%s\n' "$name" "$US" "$desc" "$US" "$cmd_preview" "$US" "$f"
        done
        # Local snippets (prefix: !)
        for f in "${local_files[@]}"; do
          [[ -f "$f" ]] || continue
          local name="${f#$local_dir/}"
          [[ "$name" == .* || "$name" == */.* ]] && continue
          local desc=$(_zsh_snip_read_description "$f")
          local cmd_preview=$(_zsh_snip_read_command_preview "$f" "$cmd_width")
          if (( ${#desc} > desc_width )); then
            desc="${desc[1,$((desc_width - 1))]}…"
          fi
          printf '! %s%s%s%s%s%s%s\n' "$name" "$US" "$desc" "$US" "$cmd_preview" "$US" "$f"
        done
      } | column -t -s $'\x1f' -o $'\t' | fzf \
        --delimiter='\t' \
        --with-nth=1,2,3 \
        --preview="$preview_cmd" \
        --preview-window=top:50% \
        --expect=ctrl-e,alt-e,ctrl-i,ctrl-n,ctrl-d,ctrl-x,alt-x \
        --header="ctrl-x: exec | alt-x: wrap | ctrl-e: edit | alt-e: inline | ctrl-i: insert | ctrl-n: dup | ctrl-d: del" \
        --prompt="Snippet> " \
        --query="$initial_query" \
        --print-query
    )

    # Parse fzf output: line 1 is query, line 2 is key pressed, line 3 is selection
    # Capture query for next iteration (preserves search filter after edit/delete)
    initial_query="${fzf_output%%$'\n'*}"
    local rest="${fzf_output#*$'\n'}"
    key="${rest%%$'\n'*}"
    selected="${rest#*$'\n'}"

    if [[ -z "$selected" ]]; then
      break
    fi

    # Extract display name (field 1) and full path (field 4)
    local display_name="${selected%%$'\t'*}"
    display_name="${display_name%%[[:space:]]#}"  # Trim trailing whitespace
    # Get field 4 (full path) - split by tab and get last field
    filepath="${selected##*$'\t'}"
    command=$(_zsh_snip_read_command "$filepath")
    # Get the base directory for this snippet
    local snip_dir
    if [[ "$display_name" == "~ "* ]]; then
      snip_dir="$global_dir"
    else
      snip_dir="$local_dir"
    fi
    # Strip prefix from display name for operations
    selected="${display_name#[~!] }"

    case "$key" in
      ctrl-e)
        # Edit the snippet file, then return to fzf
        "$ZSH_SNIP_EDITOR" "$filepath"
        # Check if name was changed in editor
        local new_name=$(_zsh_snip_read_name "$filepath")
        if [[ -n "$new_name" && "$new_name" != "$selected" ]]; then
          local new_path="$snip_dir/$new_name"
          if [[ -e "$new_path" ]]; then
            echo "Error: '$new_name' already exists, keeping as '$selected'"
          else
            [[ "$new_name" == */* ]] && mkdir -p "${new_path%/*}"
            mv "$filepath" "$new_path"
          fi
        fi
        continue
        ;;
      ctrl-d)
        # Delete snippet with confirmation, then return to fzf
        zle reset-prompt
        echo -n "Delete '$selected'? [y/N] "
        local response
        read -k 1 response </dev/tty
        echo
        if [[ "$response" == [yY] ]]; then
          rm "$filepath"
        fi
        continue
        ;;
      ctrl-n)
        # Duplicate snippet and open editor
        local dup_name=$(_zsh_snip_duplicate_name "$selected")
        local dup_path="$snip_dir/$dup_name"
        local desc=$(_zsh_snip_read_description "$filepath")
        [[ "$dup_name" == */* ]] && mkdir -p "${dup_path%/*}"
        _zsh_snip_write "$dup_path" "$dup_name" "$desc" "$command"
        "$ZSH_SNIP_EDITOR" "$dup_path"
        # Check if name was changed in editor
        local new_name=$(_zsh_snip_read_name "$dup_path")
        if [[ -n "$new_name" && "$new_name" != "$dup_name" ]]; then
          local new_path="$snip_dir/$new_name"
          if [[ -e "$new_path" ]]; then
            echo "Error: '$new_name' already exists, keeping as '$dup_name'"
          else
            [[ "$new_name" == */* ]] && mkdir -p "${new_path%/*}"
            mv "$dup_path" "$new_path"
            dup_path="$new_path"
          fi
        fi
        command=$(_zsh_snip_read_command "$dup_path")
        BUFFER="$command"
        CURSOR=$#BUFFER
        break
        ;;
      alt-e)
        # Insert into buffer and edit inline
        BUFFER="$command"
        CURSOR=$#BUFFER
        zle reset-prompt
        zle edit-command-line
        break
        ;;
      ctrl-i)
        # Insert at cursor position without replacing buffer
        _zsh_snip_insert_at_cursor "$command"
        break
        ;;
      alt-x)
        # Wrap in anonymous function and place in buffer for manual args
        local desc=$(_zsh_snip_read_description "$filepath")
        local wrapped=$(_zsh_snip_wrap_anon_func "$command" "$selected" "$desc")
        BUFFER="$wrapped"
        CURSOR=$#BUFFER
        break
        ;;
      ctrl-x)
        # Execute as anonymous function, prompt for args only if args: header exists
        local desc=$(_zsh_snip_read_description "$filepath")
        local args_hint=$(_zsh_snip_read_args "$filepath")
        local wrapped=$(_zsh_snip_wrap_anon_func "$command" "$selected" "$desc")
        if [[ -n "$args_hint" ]]; then
          # Prompt for args, then execute directly
          zle reset-prompt
          stty sane </dev/tty
          [[ -n "$desc" ]] && echo "# $desc" >/dev/tty
          echo -n "$selected $args_hint: " >/dev/tty
          local args
          read -r args </dev/tty
          local full_cmd="${wrapped}${args:-\"\"}"
          print -s "$full_cmd"
          eval "$full_cmd" </dev/tty >/dev/tty 2>&1
        else
          # No args needed - put in buffer and execute via accept-line
          BUFFER="${wrapped}\"\""
          CURSOR=$#BUFFER
          zle reset-prompt
          zle accept-line
        fi
        break
        ;;
      *)
        # Replace buffer with snippet
        BUFFER="$command"
        CURSOR=$#BUFFER
        break
        ;;
    esac
  done

  zle reset-prompt
}

# Save current buffer as local/project snippet (CTRL-X CTRL-P)
_zsh_snip_save_local() {
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

  # Determine local snippet directory
  local local_dir=$(_zsh_snip_find_local_dir)
  if [[ -z "$local_dir" ]]; then
    # Create .zsh-snip in current directory
    local_dir="$PWD/$ZSH_SNIP_LOCAL_PATH"
    mkdir -p "$local_dir"
  fi

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
    command_to_save="${buffer%\#*}"
    command_to_save="${command_to_save%%[[:space:]]#}"
  fi

  # Generate default filename
  if [[ -n "$comment_name" ]]; then
    comment_name=$(_zsh_snip_slugify "$comment_name")
    if [[ -e "$local_dir/$comment_name" ]]; then
      id=$(_zsh_snip_next_id "$comment_name")
      default_name="$comment_name-$id"
    else
      default_name="$comment_name"
    fi
  else
    cmd=$(_zsh_snip_extract_command "$buffer")
    cmd=$(_zsh_snip_slugify "$cmd")
    [[ -z "$cmd" ]] && cmd="snippet"
    id=$(_zsh_snip_next_id "$cmd")
    default_name="$cmd-$id"
  fi
  filepath="$local_dir/$default_name"

  # Write snippet and open in editor
  _zsh_snip_write "$filepath" "$default_name" "$description" "$command_to_save"
  _zsh_snip_edit_at_name "$filepath"

  # Check if name was changed in editor
  new_name=$(_zsh_snip_read_name "$filepath")
  if [[ -n "$new_name" && "$new_name" != "$default_name" ]]; then
    new_path="$local_dir/$new_name"
    if [[ -e "$new_path" ]]; then
      echo "Error: '$new_name' already exists, keeping as '$default_name'"
    else
      [[ "$new_name" == */* ]] && mkdir -p "${new_path%/*}"
      mv "$filepath" "$new_path"
      filepath="$new_path"
    fi
  fi

  zle reset-prompt
  zle -M "Saved (local): $filepath"
}

# Register widgets and keybindings
zle -N _zsh_snip_save
zle -N _zsh_snip_save_local
zle -N _zsh_snip_search

bindkey '^X^S' _zsh_snip_save
bindkey '^X^P' _zsh_snip_save_local
bindkey '^X^X' _zsh_snip_search
