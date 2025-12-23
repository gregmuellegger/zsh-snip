# zsh-snip - Shell Snippet Manager
# Source this file in your .zshrc: source /path/to/zsh-snip.zsh

# Configuration
ZSH_SNIP_DIR="${ZSH_SNIP_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh-snip}"
ZSH_SNIP_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-.zsh-snip}"
# ZSH_SNIP_YANK_CMD - auto-detected if unset, set empty to disable
# ZSH_SNIP_DEBUG_TIMING - set to 1 to show timing diagnostics

# Timing helper - outputs elapsed time in ms if debugging enabled
# Usage: _zsh_snip_timing_start; ...; _zsh_snip_timing_end "label"
_zsh_snip_timing_start() {
  [[ -n "$ZSH_SNIP_DEBUG_TIMING" ]] || return 0
  typeset -g _zsh_snip_timing_ns
  _zsh_snip_timing_ns=$(($(date +%s%N)))
}

_zsh_snip_timing_end() {
  [[ -n "$ZSH_SNIP_DEBUG_TIMING" ]] || return 0
  local label="$1"
  local end_ns=$(($(date +%s%N)))
  local elapsed_ms=$(( (end_ns - _zsh_snip_timing_ns) / 1000000 ))
  echo "[timing] $label: ${elapsed_ms}ms" >&2
}

# Detect clipboard command for yank functionality
# Returns: clipboard command string, or empty if unavailable/disabled
_zsh_snip_get_yank_cmd() {
  # If explicitly set (even to empty), use that value
  if [[ -n "${ZSH_SNIP_YANK_CMD+x}" ]]; then
    echo "$ZSH_SNIP_YANK_CMD"
    return
  fi

  # Auto-detect based on environment
  # macOS
  if command -v pbcopy &>/dev/null; then
    echo "pbcopy"
    return
  fi

  # WSL
  if command -v clip.exe &>/dev/null; then
    echo "clip.exe"
    return
  fi

  # Wayland
  if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy &>/dev/null; then
    echo "wl-copy"
    return
  fi

  # X11
  if [[ -n "$DISPLAY" ]]; then
    if command -v xclip &>/dev/null; then
      echo "xclip -selection clipboard"
      return
    elif command -v xsel &>/dev/null; then
      echo "xsel --clipboard --input"
      return
    fi
  fi

  # No clipboard available
  echo ""
}

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

# Read name from a snippet file (only searches header, before # ---)
_zsh_snip_read_name() {
  local filepath="$1"
  sed -n '1,/^# ---$/ { s/^# name: //p; }' "$filepath"
}

# Get line number of # name: field in snippet file
_zsh_snip_get_name_line_number() {
  local filepath="$1"
  sed -n '1,/^# ---$/ { /^# name: /= }' "$filepath"
}

# Open file in editor with cursor at name value
_zsh_snip_edit_at_name() {
  local filepath="$1"
  local editor="${EDITOR:-vi}"
  local editor_name="${editor##*/}"
  local line_num=$(_zsh_snip_get_name_line_number "$filepath")
  line_num="${line_num:-1}"

  case "$editor_name" in
    vim|nvim|vi)
      "$editor" "+call cursor($line_num,9)" "$filepath"
      ;;
    nano)
      "$editor" "+$line_num,9" "$filepath"
      ;;
    code|code-insiders)
      "$editor" -g "$filepath:$line_num:9"
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

# Read description from a snippet file (only searches header, before # ---)
_zsh_snip_read_description() {
  local filepath="$1"
  sed -n '1,/^# ---$/ { s/^# description: //p; }' "$filepath"
}

# Read args from a snippet file (only searches header, before # ---)
_zsh_snip_read_args() {
  local filepath="$1"
  sed -n '1,/^# ---$/ { s/^# args: //p; }' "$filepath"
}

# Read abbr from a snippet file (only searches header, before # ---)
_zsh_snip_read_abbr() {
  local filepath="$1"
  sed -n '1,/^# ---$/ { s/^# abbr: //p; }' "$filepath"
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

# Read header and first line of command in one pass (optimized for listing)
# Sets reply variables: reply_name, reply_desc, reply_args, reply_abbr, reply_preview
# Args: filepath [max_preview_length]
_zsh_snip_read_header() {
  local filepath="$1"
  local max_preview="${2:-50}"
  local line
  local in_header=1

  # Initialize reply variables
  typeset -g reply_name="" reply_desc="" reply_args="" reply_abbr="" reply_preview=""

  # Read file line by line until we get first content line
  while IFS= read -r line; do
    if (( in_header )); then
      # Check for header separator
      if [[ "$line" == "# ---" ]]; then
        in_header=0
        continue
      fi

      # Extract header fields (escape # in pattern matching)
      if [[ "$line" == "# name: "* ]]; then
        reply_name="${line#\# name: }"
      elif [[ "$line" == "# description: "* ]]; then
        reply_desc="${line#\# description: }"
      elif [[ "$line" == "# args: "* ]]; then
        reply_args="${line#\# args: }"
      elif [[ "$line" == "# abbr: "* ]]; then
        reply_abbr="${line#\# abbr: }"
      fi
    else
      # First line after header separator - this is our preview
      reply_preview="$line"
      # Truncate if needed
      if (( ${#reply_preview} > max_preview )); then
        reply_preview="${reply_preview[1,$max_preview]}..."
      fi
      # Got what we need, stop reading
      break
    fi
  done < "$filepath"

  # Return success (while loop returns non-zero on EOF which breaks set -e)
  return 0
}

# Read header and full command content in one pass (for abbr loading)
# Sets reply variables: reply_name, reply_desc, reply_args, reply_abbr, reply_command
# Args: filepath
_zsh_snip_read_header_full() {
  local filepath="$1"
  local line
  local in_header=1
  local command_lines=()

  # Initialize reply variables
  typeset -g reply_name="" reply_desc="" reply_args="" reply_abbr="" reply_command=""

  # Read file line by line
  while IFS= read -r line; do
    if (( in_header )); then
      # Check for header separator
      if [[ "$line" == "# ---" ]]; then
        in_header=0
        continue
      fi

      # Extract header fields (escape # in pattern matching)
      if [[ "$line" == "# name: "* ]]; then
        reply_name="${line#\# name: }"
      elif [[ "$line" == "# description: "* ]]; then
        reply_desc="${line#\# description: }"
      elif [[ "$line" == "# args: "* ]]; then
        reply_args="${line#\# args: }"
      elif [[ "$line" == "# abbr: "* ]]; then
        reply_abbr="${line#\# abbr: }"
      fi
    else
      # Collect command lines
      command_lines+=("$line")
    fi
  done < "$filepath"

  # Join command lines with newlines
  reply_command="${(pj:\n:)command_lines}"

  # Return success (while loop returns non-zero on EOF which breaks set -e)
  return 0
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
  setopt LOCAL_OPTIONS EXTENDED_GLOB INTERACTIVE_COMMENTS
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

  _zsh_snip_abbr_reload_if_enabled
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
  # EXTENDED_GLOB for glob qualifiers, INTERACTIVE_COMMENTS so # in $() is a comment
  setopt LOCAL_OPTIONS EXTENDED_GLOB INTERACTIVE_COMMENTS

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
  local user_dir="$ZSH_SNIP_DIR"
  local local_dir=$(_zsh_snip_find_local_dir)
  # Pre-fill fzf query with current buffer content
  local initial_query="$BUFFER"

  # Build preview command using field 4 (full path)
  # Note: {4} refers to the 4th tab-separated field
  if command -v bat &>/dev/null; then
    preview_cmd='bat --style=plain --color=always --language=bash {4}'
  else
    preview_cmd='cat {4}'
  fi

  # Loop to allow returning to fzf after delete
  while true; do
    # Gather snippets from both user and local directories
    # N = nullglob (empty array if no matches), . = regular files only
    local user_files=("$user_dir"/**/*(N.))
    local local_files=()
    [[ -n "$local_dir" ]] && local_files=("$local_dir"/**/*(N.))

    if (( ${#user_files[@]} == 0 && ${#local_files[@]} == 0 )); then
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
    # Note: We generate fzf_list first, then pipe to fzf separately.
    # Direct pipeline { ... } | column | fzf breaks in zle widget context.
    local US=$'\x1f'
    local fzf_list
    _zsh_snip_timing_start
    fzf_list=$(
      {
        # User snippets (prefix: ~)
        for f in "${user_files[@]}"; do
          [[ -f "$f" ]] || continue
          local name="${f#$user_dir/}"
          [[ "$name" == .* || "$name" == */.* ]] && continue
          _zsh_snip_read_header "$f" "$cmd_width"
          local desc="$reply_desc"
          local cmd_preview="$reply_preview"
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
          _zsh_snip_read_header "$f" "$cmd_width"
          local desc="$reply_desc"
          local cmd_preview="$reply_preview"
          if (( ${#desc} > desc_width )); then
            desc="${desc[1,$((desc_width - 1))]}…"
          fi
          printf '! %s%s%s%s%s%s%s\n' "$name" "$US" "$desc" "$US" "$cmd_preview" "$US" "$f"
        done
      } | column -t -s $'\x1f' -o $'\t'
    )
    _zsh_snip_timing_end "fzf_list generation (${#user_files[@]} user + ${#local_files[@]} local snippets)"

    # Check if yank/clipboard is available
    local yank_cmd=$(_zsh_snip_get_yank_cmd)
    local fzf_expect="ctrl-e,alt-e,ctrl-i,ctrl-n,ctrl-d,ctrl-x,alt-x"
    local fzf_header="ctrl-x: exec | alt-x: wrap | ctrl-e: edit | alt-e: inline | ctrl-i: insert | ctrl-n: dup | ctrl-d: del"
    if [[ -n "$yank_cmd" ]]; then
      fzf_expect="$fzf_expect,ctrl-y"
      fzf_header="ctrl-y: yank | $fzf_header"
    fi

    fzf_output=$(echo "$fzf_list" | fzf \
        --delimiter=$'\t' \
        --with-nth=1,2,3 \
        --preview="$preview_cmd" \
        --preview-window=top:50% \
        --expect="$fzf_expect" \
        --header="$fzf_header" \
        --prompt="Snippet> " \
        --query="$initial_query" \
        --print-query
    )

    # Parse fzf output: line 1 is query, line 2 is key pressed, line 3 is selection
    # Capture query for next iteration (preserves search filter after edit/delete)
    initial_query="${fzf_output%%$'\n'*}"
    local rest="${fzf_output#*$'\n'}"
    key="${rest%%$'\n'*}"
    # Extract selection only if there's a newline after the key
    # When fzf has no selection, output may be just "query\nkey" without trailing selection
    if [[ "$rest" == *$'\n'* ]]; then
      selected="${rest#*$'\n'}"
    else
      selected=""
    fi

    if [[ -z "$selected" ]]; then
      break
    fi

    # Extract display name (field 1) and full path (field 4)
    local display_name="${selected%%$'\t'*}"
    # Trim trailing whitespace - use sed instead of EXTENDED_GLOB pattern
    display_name=$(echo "$display_name" | sed 's/[[:space:]]*$//')
    # Get field 4 (full path) - split by tab and get last field
    filepath="${selected##*$'\t'}"
    command=$(_zsh_snip_read_command "$filepath")
    # Get the base directory for this snippet
    local snip_dir
    if [[ "$display_name" == "~ "* ]]; then
      snip_dir="$user_dir"
    else
      snip_dir="$local_dir"
    fi
    # Strip prefix from display name for operations
    selected="${display_name#[~!] }"

    case "$key" in
      ctrl-e)
        # Edit the snippet file, then return to fzf
        "${EDITOR:-vi}" "$filepath"
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
        _zsh_snip_abbr_reload_if_enabled
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
          _zsh_snip_abbr_reload_if_enabled
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
        "${EDITOR:-vi}" "$dup_path"
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
        _zsh_snip_abbr_reload_if_enabled
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
      ctrl-y)
        # Yank/copy snippet content to clipboard
        if [[ -n "$yank_cmd" ]]; then
          printf '%s' "$command" | eval "$yank_cmd"
          zle -M "Copied '$selected' to clipboard"
        fi
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
  setopt LOCAL_OPTIONS EXTENDED_GLOB INTERACTIVE_COMMENTS
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

  _zsh_snip_abbr_reload_if_enabled
  zle reset-prompt
  zle -M "Saved (local): $filepath"
}

# =============================================================================
# CLI Interface
# =============================================================================

# Main CLI entry point
# Usage:
#   zsh-snip list [filter] [--names-only] [--full-path] [--user|--local]
#   zsh-snip expand <name> [--user|--local]
#   zsh-snip exec <name> [args...] [--user|--local]
zsh-snip() {
  local subcommand="$1"
  shift 2>/dev/null

  case "$subcommand" in
    list)   _zsh_snip_cli_list "$@" ;;
    path)   _zsh_snip_cli_path "$@" ;;
    expand) _zsh_snip_cli_expand "$@" ;;
    exec)   _zsh_snip_cli_exec "$@" ;;
    yank)   _zsh_snip_cli_yank "$@" ;;
    abbr)   _zsh_snip_cli_abbr "$@" ;;
    "")
      echo "Usage: zsh-snip <command> [options]" >&2
      echo "" >&2
      echo "Commands:" >&2
      echo "  list [filter]      List snippets (filter is glob pattern)" >&2
      echo "  path <name>        Show full path to snippet file" >&2
      echo "  expand <name>      Output snippet content" >&2
      echo "  exec <name> [args] Execute snippet with arguments" >&2
      echo "  yank <name>        Copy snippet content to clipboard" >&2
      echo "  abbr <command>     Manage abbreviations (list, load)" >&2
      echo "" >&2
      echo "Options:" >&2
      echo "  --user            Only user snippets" >&2
      echo "  --local           Only local/project snippets" >&2
      echo "  --names-only      (list) Output only names" >&2
      echo "  --full-path       (list) Show full absolute paths" >&2
      return 1
      ;;
    *)
      echo "zsh-snip: unknown command '$subcommand'" >&2
      echo "Run 'zsh-snip' for usage" >&2
      return 1
      ;;
  esac
}

# List snippets
# Output format: name [path]: description (aligned, colored)
_zsh_snip_cli_list() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local filter="*"
  local names_only=0
  local full_path=0
  local scope=""  # empty = both, "user" = user only, "local" = local only
  local no_color=0

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --names-only) names_only=1 ;;
      --full-path)  full_path=1 ;;
      --user)       scope="user" ;;
      --local)      scope="local" ;;
      --no-color)   no_color=1 ;;
      -*)
        echo "zsh-snip list: unknown option '$1'" >&2
        return 1
        ;;
      *)
        filter="$1"
        ;;
    esac
    shift
  done

  # If filter has no glob chars, wrap in *...* for substring match
  if [[ "$filter" != *[\*\?\[]* ]]; then
    filter="*${filter}*"
  fi

  local user_dir="$ZSH_SNIP_DIR"
  local local_dir
  local_dir=$(_zsh_snip_find_local_dir)

  # Track names we've seen (for local preference deduplication)
  typeset -A seen_names

  # Declare loop variables outside to avoid 'local' output issues
  local f name desc display_path

  # Colors (disabled if not tty or --no-color)
  local c_name="" c_path="" c_desc="" c_reset=""
  if [[ -t 1 && $no_color -eq 0 ]]; then
    c_name=$'\e[1;36m'   # bold cyan for name
    c_path=$'\e[33m'     # yellow for path
    c_desc=$'\e[37m'     # white/gray for description
    c_reset=$'\e[0m'
  fi

  # Use unit separator for column alignment
  local US=$'\x1f'

  # Collect results as: name[US]path[US]description
  local results=()

  # Local snippets first (they take precedence)
  if [[ "$scope" != "user" && -n "$local_dir" ]]; then
    local local_files=("$local_dir"/**/*(N.))
    for f in "${local_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$local_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue
      # Apply filter to full name (path)
      [[ "$name" != $~filter ]] && continue
      seen_names[$name]=1

      if (( names_only )); then
        results+=("$name")
      else
        _zsh_snip_read_header "$f"
        desc="$reply_desc"
        if (( full_path )); then
          display_path="$local_dir"
        else
          # Relative path from PWD
          display_path="${local_dir#$PWD/}"
          [[ "$display_path" == "$local_dir" ]] && display_path=$(realpath --relative-to="$PWD" "$local_dir" 2>/dev/null || echo "$local_dir")
        fi
        results+=("${c_name}${name}${c_reset}${US}${c_path}${display_path}${c_reset}${US}${c_desc}${desc}${c_reset}")
      fi
    done
  fi

  # User snippets
  if [[ "$scope" != "local" ]]; then
    local user_files=("$user_dir"/**/*(N.))
    for f in "${user_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$user_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue
      # Apply filter to full name (path)
      [[ "$name" != $~filter ]] && continue

      # Skip if local version exists (unless showing user-only)
      if [[ "$scope" != "user" && -n "${seen_names[$name]}" ]]; then
        continue
      fi

      if (( names_only )); then
        results+=("$name")
      else
        _zsh_snip_read_header "$f"
        desc="$reply_desc"
        if (( full_path )); then
          display_path="$user_dir"
        else
          # Abbreviate to just ~
          display_path="~"
        fi
        results+=("${c_name}${name}${c_reset}${US}${c_path}${display_path}${c_reset}${US}${c_desc}${desc}${c_reset}")
      fi
    done
  fi

  # Output results
  if (( names_only )); then
    for name in "${results[@]}"; do
      echo "$name"
    done
  else
    # Use column to align fields
    printf '%s\n' "${results[@]}" | column -t -s $'\x1f'
  fi
}

# Show full path to snippet file
_zsh_snip_cli_path() {
  local name=""
  local scope=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  scope="user" ;;
      --local) scope="local" ;;
      -*)
        echo "zsh-snip path: unknown option '$1'" >&2
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          echo "zsh-snip path: unexpected argument '$1'" >&2
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$name" ]]; then
    echo "zsh-snip path: missing snippet name" >&2
    return 1
  fi

  local filepath
  filepath=$(_zsh_snip_cli_resolve "$name" "$scope")
  if [[ -z "$filepath" ]]; then
    echo "zsh-snip path: '$name' not found" >&2
    return 1
  fi

  echo "$filepath"
}

# Expand snippet - output command content
_zsh_snip_cli_expand() {
  local name=""
  local scope=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  scope="user" ;;
      --local) scope="local" ;;
      -*)
        echo "zsh-snip expand: unknown option '$1'" >&2
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          echo "zsh-snip expand: unexpected argument '$1'" >&2
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$name" ]]; then
    echo "zsh-snip expand: missing snippet name" >&2
    return 1
  fi

  local filepath=$(_zsh_snip_cli_resolve "$name" "$scope")
  if [[ -z "$filepath" ]]; then
    echo "zsh-snip expand: '$name' not found" >&2
    return 1
  fi

  _zsh_snip_read_command "$filepath"
}

# Execute snippet
_zsh_snip_cli_exec() {
  local name=""
  local scope=""
  local -a args=()

  # Parse arguments - flags must come before name
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  scope="user" ;;
      --local) scope="local" ;;
      -*)
        echo "zsh-snip exec: unknown option '$1'" >&2
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          args+=("$1")
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$name" ]]; then
    echo "zsh-snip exec: missing snippet name" >&2
    return 1
  fi

  local filepath=$(_zsh_snip_cli_resolve "$name" "$scope")
  if [[ -z "$filepath" ]]; then
    echo "zsh-snip exec: '$name' not found" >&2
    return 1
  fi

  local command=$(_zsh_snip_read_command "$filepath")
  local args_hint=$(_zsh_snip_read_args "$filepath")

  # Check if args are required but not provided
  if [[ -n "$args_hint" && ${#args[@]} -eq 0 ]]; then
    echo "zsh-snip exec: '$name' requires args: $args_hint" >&2
    return 1
  fi

  # Build and execute command as anonymous function
  local full_cmd="() { $command } ${(q)args[@]}"

  # Add to history
  print -s "$full_cmd"

  # Execute
  eval "$full_cmd"
}

# Yank snippet - copy content to clipboard
_zsh_snip_cli_yank() {
  local name=""
  local scope=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  scope="user" ;;
      --local) scope="local" ;;
      -*)
        echo "zsh-snip yank: unknown option '$1'" >&2
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        else
          echo "zsh-snip yank: unexpected argument '$1'" >&2
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "$name" ]]; then
    echo "zsh-snip yank: missing snippet name" >&2
    return 1
  fi

  # Check clipboard command availability
  local yank_cmd=$(_zsh_snip_get_yank_cmd)
  if [[ -z "$yank_cmd" ]]; then
    echo "zsh-snip yank: no clipboard command available" >&2
    echo "Set ZSH_SNIP_YANK_CMD or install xclip/wl-copy/pbcopy" >&2
    return 1
  fi

  local filepath=$(_zsh_snip_cli_resolve "$name" "$scope")
  if [[ -z "$filepath" ]]; then
    echo "zsh-snip yank: '$name' not found" >&2
    return 1
  fi

  local command=$(_zsh_snip_read_command "$filepath")

  # Pipe to clipboard command (no trailing newline)
  printf '%s' "$command" | eval "$yank_cmd"
}

# Resolve snippet name to filepath
# Args: name [scope]
# scope: "" = prefer local, "user" = user only, "local" = local only
_zsh_snip_cli_resolve() {
  local name="$1"
  local scope="$2"

  local user_dir="$ZSH_SNIP_DIR"
  local local_dir=$(_zsh_snip_find_local_dir)

  # Check local first (unless user-only)
  if [[ "$scope" != "user" && -n "$local_dir" && -f "$local_dir/$name" ]]; then
    echo "$local_dir/$name"
    return
  fi

  # Check user (unless local-only)
  if [[ "$scope" != "local" && -f "$user_dir/$name" ]]; then
    echo "$user_dir/$name"
    return
  fi

  # Not found
  return 1
}

# =============================================================================
# Abbreviation Integration (zsh-abbr)
# =============================================================================

# List snippets that have abbr: header defined
# Output format: name [abbr-keys] description
_zsh_snip_cli_abbr_list() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local scope=""  # empty = both, "user" = user only, "local" = local only
  local no_color=0

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)     scope="user" ;;
      --local)    scope="local" ;;
      --no-color) no_color=1 ;;
      -*)
        echo "zsh-snip abbr list: unknown option '$1'" >&2
        return 1
        ;;
      *)
        echo "zsh-snip abbr list: unexpected argument '$1'" >&2
        return 1
        ;;
    esac
    shift
  done

  local user_dir="$ZSH_SNIP_DIR"
  local local_dir
  local_dir=$(_zsh_snip_find_local_dir)

  # Track names we've seen (for local preference deduplication)
  typeset -A seen_names

  # Declare loop variables outside to avoid 'local' output issues
  local f name

  # Colors (disabled if not tty or --no-color)
  local c_name="" c_abbr="" c_desc="" c_reset=""
  if [[ -t 1 && $no_color -eq 0 ]]; then
    c_name=$'\e[1;36m'   # bold cyan for name
    c_abbr=$'\e[1;33m'   # bold yellow for abbr keys
    c_desc=$'\e[37m'     # white/gray for description
    c_reset=$'\e[0m'
  fi

  # Use unit separator for column alignment
  local US=$'\x1f'

  # Collect results as: name[US]abbr-keys[US]description
  local results=()

  # Local snippets first (they take precedence)
  if [[ "$scope" != "user" && -n "$local_dir" ]]; then
    local local_files=("$local_dir"/**/*(N.))
    for f in "${local_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$local_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue

      # Read header including abbr field
      _zsh_snip_read_header "$f"

      # Skip if no abbr defined
      [[ -z "$reply_abbr" ]] && continue

      seen_names[$name]=1

      results+=("${c_name}${name}${c_reset}${US}${c_abbr}${reply_abbr}${c_reset}${US}${c_desc}${reply_desc}${c_reset}")
    done
  fi

  # User snippets
  if [[ "$scope" != "local" ]]; then
    local user_files=("$user_dir"/**/*(N.))
    for f in "${user_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$user_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue

      # Skip if local version exists (unless showing user-only)
      if [[ "$scope" != "user" && -n "${seen_names[$name]}" ]]; then
        continue
      fi

      # Read header including abbr field
      _zsh_snip_read_header "$f"

      # Skip if no abbr defined
      [[ -z "$reply_abbr" ]] && continue

      results+=("${c_name}${name}${c_reset}${US}${c_abbr}${reply_abbr}${c_reset}${US}${c_desc}${reply_desc}${c_reset}")
    done
  fi

  # Output results
  if (( ${#results[@]} > 0 )); then
    printf '%s\n' "${results[@]}" | column -t -s $'\x1f'
  fi
}

# Load abbreviations from snippets into zsh-abbr
# Args: [--user|--local]
_zsh_snip_cli_abbr_load() {
  setopt LOCAL_OPTIONS EXTENDED_GLOB

  local scope=""  # empty = both, "user" = user only, "local" = local only

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)  scope="user" ;;
      --local) scope="local" ;;
      -*)
        echo "zsh-snip abbr load: unknown option '$1'" >&2
        return 1
        ;;
      *)
        echo "zsh-snip abbr load: unexpected argument '$1'" >&2
        return 1
        ;;
    esac
    shift
  done

  # Check if abbr command is available
  if ! command -v abbr &>/dev/null; then
    # Check if we've warned before in this session
    if [[ -z "${_ZSH_SNIP_ABBR_WARNED:-}" ]]; then
      echo "zsh-snip: zsh-abbr not found, skipping abbreviation loading" >&2
      echo "zsh-snip: install zsh-abbr or set ZSH_SNIP_ABBR=0 to suppress this warning" >&2
      typeset -g _ZSH_SNIP_ABBR_WARNED=1
    fi
    return 0
  fi

  local user_dir="$ZSH_SNIP_DIR"
  local local_dir
  local_dir=$(_zsh_snip_find_local_dir)

  # Track names we've seen (for local preference deduplication)
  typeset -A seen_names

  # Declare loop variables
  local f name abbr_keys abbr_key command

  # Load local snippets first (they take precedence)
  if [[ "$scope" != "user" && -n "$local_dir" ]]; then
    _zsh_snip_timing_start
    local local_files=("$local_dir"/**/*(N.))
    for f in "${local_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$local_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue

      # Read header and command in one pass (optimized)
      _zsh_snip_read_header_full "$f"

      # Skip if no abbr defined
      [[ -z "$reply_abbr" ]] && continue

      seen_names[$name]=1

      # Register each abbr key (space-separated)
      for abbr_key in ${=reply_abbr}; do
        # Use session abbreviations (-S) to avoid polluting zsh-abbr's config
        abbr -S "$abbr_key=$reply_command" >/dev/null
      done
    done
    _zsh_snip_timing_end "abbr load (local)"
  fi

  # Load user snippets
  if [[ "$scope" != "local" ]]; then
    _zsh_snip_timing_start
    local user_files=("$user_dir"/**/*(N.))
    for f in "${user_files[@]}"; do
      [[ -f "$f" ]] || continue
      name="${f#$user_dir/}"
      [[ "$name" == .* || "$name" == */.* ]] && continue

      # Skip if local version exists (unless showing user-only)
      if [[ "$scope" != "user" && -n "${seen_names[$name]}" ]]; then
        continue
      fi

      # Read header and command in one pass (optimized)
      _zsh_snip_read_header_full "$f"

      # Skip if no abbr defined
      [[ -z "$reply_abbr" ]] && continue

      # Register each abbr key (space-separated)
      for abbr_key in ${=reply_abbr}; do
        abbr -S "$abbr_key=$reply_command" >/dev/null
      done
    done
    _zsh_snip_timing_end "abbr load (user)"
  fi
}

# Main abbr subcommand dispatcher
_zsh_snip_cli_abbr() {
  local subcommand="$1"
  shift 2>/dev/null

  case "$subcommand" in
    list) _zsh_snip_cli_abbr_list "$@" ;;
    load) _zsh_snip_cli_abbr_load "$@" ;;
    "")
      echo "Usage: zsh-snip abbr <command> [options]" >&2
      echo "" >&2
      echo "Commands:" >&2
      echo "  list [--user|--local]  List snippets with abbr: defined" >&2
      echo "  load [--user|--local]  Load abbreviations into zsh-abbr" >&2
      return 1
      ;;
    *)
      echo "zsh-snip abbr: unknown command '$subcommand'" >&2
      echo "Run 'zsh-snip abbr' for usage" >&2
      return 1
      ;;
  esac
}

# Register widgets and keybindings
zle -N _zsh_snip_save
zle -N _zsh_snip_save_local
zle -N _zsh_snip_search

bindkey '^X^S' _zsh_snip_save
bindkey '^X^P' _zsh_snip_save_local
bindkey '^X^X' _zsh_snip_search

# =============================================================================
# Auto-loading abbreviations (when ZSH_SNIP_ABBR=1)
# =============================================================================

# Unload local abbreviations previously loaded by zsh-snip
# Uses _ZSH_SNIP_LOCAL_ABBRS array to track which abbrs to remove
_zsh_snip_abbr_unload_local() {
  # Skip if abbr command not available
  command -v abbr &>/dev/null || return 0

  # Skip if no local abbrs were loaded
  [[ -z "${_ZSH_SNIP_LOCAL_ABBRS:-}" ]] && return 0

  # Unload each abbr key
  local abbr_key
  for abbr_key in "${_ZSH_SNIP_LOCAL_ABBRS[@]}"; do
    abbr -S -e "$abbr_key" 2>/dev/null || true
  done

  # Clear the tracking array
  _ZSH_SNIP_LOCAL_ABBRS=()
}

# Load local abbreviations and track them for later unloading
_zsh_snip_abbr_load_local() {
  # Skip if abbr command not available
  command -v abbr &>/dev/null || return 0

  local local_dir
  local_dir=$(_zsh_snip_find_local_dir)

  # No local dir found - clear any previously loaded local abbrs
  if [[ -z "$local_dir" ]]; then
    _zsh_snip_abbr_unload_local
    typeset -g _ZSH_SNIP_CURRENT_PROJECT=""
    return 0
  fi

  # Check if we're in the same project (avoid unnecessary reloads)
  if [[ "$_ZSH_SNIP_CURRENT_PROJECT" == "$local_dir" ]]; then
    return 0
  fi

  # Unload previous local abbrs if project changed
  if [[ -n "${_ZSH_SNIP_CURRENT_PROJECT:-}" ]]; then
    _zsh_snip_abbr_unload_local
  fi

  # Track new project
  typeset -g _ZSH_SNIP_CURRENT_PROJECT="$local_dir"

  # Initialize tracking array
  typeset -ga _ZSH_SNIP_LOCAL_ABBRS
  _ZSH_SNIP_LOCAL_ABBRS=()

  # Load local abbrs
  _zsh_snip_timing_start
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  local local_files=("$local_dir"/**/*(N.))
  local f name abbr_key

  for f in "${local_files[@]}"; do
    [[ -f "$f" ]] || continue
    name="${f#$local_dir/}"
    [[ "$name" == .* || "$name" == */.* ]] && continue

    # Read header and command in one pass (optimized)
    _zsh_snip_read_header_full "$f"

    # Skip if no abbr defined
    [[ -z "$reply_abbr" ]] && continue

    # Register each abbr key and track it
    for abbr_key in ${=reply_abbr}; do
      abbr -S "$abbr_key=$reply_command" 2>/dev/null || true
      _ZSH_SNIP_LOCAL_ABBRS+=("$abbr_key")
    done
  done
  _zsh_snip_timing_end "abbr load local (chpwd)"
}

# chpwd hook to auto-load/unload local abbrs on directory change
_zsh_snip_abbr_chpwd() {
  _zsh_snip_abbr_load_local
}

# Reload abbreviations after snippet changes (save/edit/delete)
# Called by save, edit, duplicate, delete operations when ZSH_SNIP_ABBR=1
_zsh_snip_abbr_reload_if_enabled() {
  [[ "${ZSH_SNIP_ABBR:-0}" == "1" ]] || return 0
  _zsh_snip_cli_abbr_load 2>/dev/null || true
}

# Initialize abbreviation auto-loading if enabled
if [[ "${ZSH_SNIP_ABBR:-0}" == "1" ]]; then
  # Load user abbreviations synchronously on startup
  _zsh_snip_cli_abbr_load --user 2>/dev/null || true

  # Set up chpwd hook for local abbreviations
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _zsh_snip_abbr_chpwd

  # Load local abbrs for current directory
  _zsh_snip_abbr_load_local
fi
