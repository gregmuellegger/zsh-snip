#!/usr/bin/env zsh
# Tests for zsh-snip
#
# Run (quiet by default, only failures + summary): zsh tests/test_zsh_snip.zsh
# Verbose (all assertions): zsh tests/test_zsh_snip.zsh -v
#
# Exit code is governed by the assertion counters: the suite exits non-zero if
# and only if at least one assertion failed. There is no `set -e`, so a
# non-zero setup command never aborts the run before the summary prints.

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

# Source the plugin (but skip keybinding setup by mocking zle/bindkey)
function zle() { :; }
function bindkey() { :; }
source "$PROJECT_DIR/zsh-snip.plugin.zsh"

# Shared assertion helpers, counters, QUIET/color handling, and summary/exit.
source "${SCRIPT_DIR}/lib/harness.zsh"

# =============================================================================
# Tests for _zsh_snip_extract_command
# =============================================================================
log "Testing _zsh_snip_extract_command..."

assert_eq "git" "$(_zsh_snip_extract_command 'git diff | grep foo')" \
  "extracts first command from pipeline"

assert_eq "git" "$(_zsh_snip_extract_command 'sudo git push')" \
  "skips sudo"

assert_eq "apt" "$(_zsh_snip_extract_command 'sudo apt install vim')" \
  "skips sudo for apt"

assert_eq "git" "$(_zsh_snip_extract_command 'FOO=bar git push')" \
  "skips variable assignment"

assert_eq "make" "$(_zsh_snip_extract_command 'FOO=bar BAZ=qux make build')" \
  "skips multiple variable assignments"

assert_eq "cd" "$(_zsh_snip_extract_command '(cd /tmp; make)')" \
  "handles subshell prefix"

assert_eq "git" "$(_zsh_snip_extract_command '  git status')" \
  "handles leading whitespace"

assert_eq "echo" "$(_zsh_snip_extract_command 'echo hello world')" \
  "extracts builtin commands"

assert_eq "kubectl" "$(_zsh_snip_extract_command 'kubectl get pods -A')" \
  "extracts regular commands"

assert_eq "git" "$(_zsh_snip_extract_command 'sudo FOO=bar git push')" \
  "skips sudo and variable assignment combined"

assert_eq "snippet" "$(_zsh_snip_extract_command '')" \
  "returns 'snippet' for empty input"

assert_eq "snippet" "$(_zsh_snip_extract_command '   ')" \
  "returns 'snippet' for whitespace-only input"


# =============================================================================
# Tests for _zsh_snip_next_id
# =============================================================================
log ""
log "Testing _zsh_snip_next_id..."

# Create a temp directory for testing
TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

assert_eq "1" "$(_zsh_snip_next_id "$TEST_SNIP_DIR" 'git')" \
  "returns 1 for new command with no existing snippets"

# Create some test files
touch "$TEST_SNIP_DIR/git-1"
touch "$TEST_SNIP_DIR/git-2"
touch "$TEST_SNIP_DIR/git-5"

assert_eq "6" "$(_zsh_snip_next_id "$TEST_SNIP_DIR" 'git')" \
  "returns max+1 for existing snippets"

assert_eq "1" "$(_zsh_snip_next_id "$TEST_SNIP_DIR" 'docker')" \
  "returns 1 for command with no existing snippets (other snippets exist)"

# Test with non-numeric suffix (should be ignored)
touch "$TEST_SNIP_DIR/git-foo"

assert_eq "6" "$(_zsh_snip_next_id "$TEST_SNIP_DIR" 'git')" \
  "ignores non-numeric suffixes"

# Cleanup temp directory
rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_write and _zsh_snip_read_command
# =============================================================================
log ""
log "Testing _zsh_snip_write and _zsh_snip_read_command..."

TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

# Test writing and reading a snippet
_zsh_snip_write "$TEST_SNIP_DIR/test-1" "test-1" "Test description" "git status"
read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/test-1")

assert_eq "git status" "$read_cmd" \
  "reads command from written snippet"

# Test with multiline command
_zsh_snip_write "$TEST_SNIP_DIR/test-2" "test-2" "Multiline test" $'git add .\ngit commit -m "test"'
read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/test-2")

assert_eq $'git add .\ngit commit -m "test"' "$read_cmd" \
  "reads multiline command correctly"

# Test reading description
desc=$(_zsh_snip_read_description "$TEST_SNIP_DIR/test-1")
assert_eq "Test description" "$desc" \
  "reads description correctly"

# Test reading name
name=$(_zsh_snip_read_name "$TEST_SNIP_DIR/test-1")
assert_eq "test-1" "$name" \
  "reads name correctly"

# Test reading args (not present)
args=$(_zsh_snip_read_args "$TEST_SNIP_DIR/test-1")
assert_eq "" "$args" \
  "returns empty when no args header"

# Test reading args (present) - create file with args header manually
cat > "$TEST_SNIP_DIR/test-with-args" <<'EOF'
# name: test-with-args
# description: Test with args
# args: <domain> [port]
# created: 2024-01-01T00:00:00+00:00
# ---
echo "Checking $1:${2:-80}"
EOF
args=$(_zsh_snip_read_args "$TEST_SNIP_DIR/test-with-args")
assert_eq "<domain> [port]" "$args" \
  "reads args header correctly"

# Test empty description
_zsh_snip_write "$TEST_SNIP_DIR/test-3" "test-3" "" "echo hello"
desc=$(_zsh_snip_read_description "$TEST_SNIP_DIR/test-3")
assert_eq "" "$desc" \
  "reads empty description correctly"

# An empty description must omit the "# description:" header line entirely
# (no trailing-space placeholder line).
if grep -q "^# description:" "$TEST_SNIP_DIR/test-3"; then has_desc_line=yes; else has_desc_line=no; fi
assert_eq "no" "$has_desc_line" \
  "test_write_omits_description_line_when_description_empty"

# A non-empty description still writes the "# description:" header line
_zsh_snip_write "$TEST_SNIP_DIR/test-hasdesc" "test-hasdesc" "Some description" "echo hi"
if grep -q "^# description: Some description\$" "$TEST_SNIP_DIR/test-hasdesc"; then has_desc_line=yes; else has_desc_line=no; fi
assert_eq "yes" "$has_desc_line" \
  "test_write_keeps_description_line_when_description_present"

# Guard: a slash-less filepath must write the file, not mkdir a directory named
# after it (${filepath%/*} would otherwise expand to the whole name).
GUARD_DIR=$(mktemp -d)
( cd "$GUARD_DIR" && _zsh_snip_write "relname" "relname" "" "echo guarded" ) 2>/dev/null || true
if [[ -f "$GUARD_DIR/relname" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "test_write_slashless_path_writes_file_not_directory"
rm -rf "$GUARD_DIR"

# Test writing to subdirectory (e.g., git/add)
_zsh_snip_write "$TEST_SNIP_DIR/git/add" "git/add" "stage files" "git add ."
read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/git/add")
assert_eq "git add ." "$read_cmd" \
  "creates parent directory and writes snippet to subdirectory"

# =============================================================================
# Tests for flexible header parsing
# =============================================================================
log ""
log "Testing flexible header parsing..."

# Test header with shebang before # name:
cat > "$TEST_SNIP_DIR/test-shebang" <<'EOF'
#!/usr/bin/env zsh
# name: test-shebang
# description: Script with shebang
# ---
echo "hello"
EOF
name=$(_zsh_snip_read_name "$TEST_SNIP_DIR/test-shebang")
assert_eq "test-shebang" "$name" \
  "reads name from header with shebang prefix"
desc=$(_zsh_snip_read_description "$TEST_SNIP_DIR/test-shebang")
assert_eq "Script with shebang" "$desc" \
  "reads description from header with shebang prefix"
read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/test-shebang")
assert_eq 'echo "hello"' "$read_cmd" \
  "reads command from snippet with shebang prefix"

# Test header with extra comments between and around fields
cat > "$TEST_SNIP_DIR/test-extra-comments" <<'EOF'
#!/usr/bin/env zsh
# This is a useful script
# name: test-extra-comments
# description: Has extra comments
# Remember to run this carefully
# ---
rm -rf /tmp/test
EOF
name=$(_zsh_snip_read_name "$TEST_SNIP_DIR/test-extra-comments")
assert_eq "test-extra-comments" "$name" \
  "reads name from header with extra comments"
desc=$(_zsh_snip_read_description "$TEST_SNIP_DIR/test-extra-comments")
assert_eq "Has extra comments" "$desc" \
  "reads description from header with extra comments"

# Test that command content with header-like lines doesn't confuse parser
cat > "$TEST_SNIP_DIR/test-header-in-content" <<'EOF'
# name: test-header-in-content
# description: Creates a snippet file
# ---
cat > snippet.txt <<'INNER'
# name: inner-snippet
# description: This should not be matched
# ---
echo "inner"
INNER
EOF
name=$(_zsh_snip_read_name "$TEST_SNIP_DIR/test-header-in-content")
assert_eq "test-header-in-content" "$name" \
  "only reads name from header, not from command content"
desc=$(_zsh_snip_read_description "$TEST_SNIP_DIR/test-header-in-content")
assert_eq "Creates a snippet file" "$desc" \
  "only reads description from header, not from command content"

# Test header with args and extra comments
cat > "$TEST_SNIP_DIR/test-args-extra" <<'EOF'
#!/bin/zsh
# SSL certificate checker
# name: check-ssl
# description: Check SSL cert expiry
# args: <domain> [port]
# Make sure the domain is accessible
# ---
echo "Checking $1"
EOF
name=$(_zsh_snip_read_name "$TEST_SNIP_DIR/test-args-extra")
assert_eq "check-ssl" "$name" \
  "reads name from complex header"
args=$(_zsh_snip_read_args "$TEST_SNIP_DIR/test-args-extra")
assert_eq "<domain> [port]" "$args" \
  "reads args from complex header"

# =============================================================================
# Tests for single-field header readers (name/description/args)
# Covers B4 regression: pure-zsh reader must stop at the first match and at
# the # --- separator, never running past a sensible bound.
# =============================================================================
log ""
log "Testing single-field header readers..."

HDR_TEST_DIR=$(mktemp -d)

# test_read_name_returns_first_name_when_no_separator (B4 regression)
# A file with two "# name:" lines and NO "# ---" must return only the first,
# as a single line with no embedded newline.
cat > "$HDR_TEST_DIR/no-separator" <<'EOF'
# name: first-name
# name: second-name
echo hello
EOF
name=$(_zsh_snip_read_name "$HDR_TEST_DIR/no-separator")
assert_eq "first-name" "$name" \
  "test_read_name_returns_first_name_when_no_separator"

# Well-formed header: each reader returns its field value
cat > "$HDR_TEST_DIR/well-formed" <<'EOF'
# name: well-formed
# description: A well formed snippet
# args: <domain> [port]
# ---
echo "$1"
EOF
assert_eq "well-formed" "$(_zsh_snip_read_name "$HDR_TEST_DIR/well-formed")" \
  "test_read_name_returns_value_for_well_formed_header"
assert_eq "A well formed snippet" "$(_zsh_snip_read_description "$HDR_TEST_DIR/well-formed")" \
  "test_read_description_returns_value_for_well_formed_header"
assert_eq "<domain> [port]" "$(_zsh_snip_read_args "$HDR_TEST_DIR/well-formed")" \
  "test_read_args_returns_value_for_well_formed_header"

# Header lacking a field: reader returns empty
cat > "$HDR_TEST_DIR/only-name" <<'EOF'
# name: only-name
# ---
echo hi
EOF
assert_eq "" "$(_zsh_snip_read_description "$HDR_TEST_DIR/only-name")" \
  "test_read_description_returns_empty_when_field_absent"
assert_eq "" "$(_zsh_snip_read_args "$HDR_TEST_DIR/only-name")" \
  "test_read_args_returns_empty_when_field_absent"

# Header-like line AFTER # --- (in command body) must NOT be picked up
cat > "$HDR_TEST_DIR/field-in-body" <<'EOF'
# name: field-in-body
# description: real description
# args: real args
# ---
# name: fake-name
# description: fake description
# args: fake args
echo body
EOF
assert_eq "field-in-body" "$(_zsh_snip_read_name "$HDR_TEST_DIR/field-in-body")" \
  "test_read_name_ignores_name_line_in_body"
assert_eq "real description" "$(_zsh_snip_read_description "$HDR_TEST_DIR/field-in-body")" \
  "test_read_description_ignores_description_line_in_body"
assert_eq "real args" "$(_zsh_snip_read_args "$HDR_TEST_DIR/field-in-body")" \
  "test_read_args_ignores_args_line_in_body"

# Header parser must not leak unprefixed reply_* globals into the shell. Call
# non-subshelled so any leaked global would land in the current scope.
unset reply_name reply_desc reply_args reply_preview 2>/dev/null
unset _zsh_snip_reply_name _zsh_snip_reply_desc _zsh_snip_reply_args \
  _zsh_snip_reply_preview 2>/dev/null
_zsh_snip_read_header "$HDR_TEST_DIR/well-formed"
[[ -z ${reply_name+x} ]] && leak_check=absent || leak_check=present
assert_eq "absent" "$leak_check" \
  "test_read_header_does_not_leak_unprefixed_reply_name"
[[ -z ${reply_desc+x} ]] && leak_check=absent || leak_check=present
assert_eq "absent" "$leak_check" \
  "test_read_header_does_not_leak_unprefixed_reply_desc"
[[ -z ${reply_args+x} ]] && leak_check=absent || leak_check=present
assert_eq "absent" "$leak_check" \
  "test_read_header_does_not_leak_unprefixed_reply_args"
[[ -z ${reply_preview+x} ]] && leak_check=absent || leak_check=present
assert_eq "absent" "$leak_check" \
  "test_read_header_does_not_leak_unprefixed_reply_preview"
# The namespaced globals still hold the parsed values.
assert_eq "well-formed" "$_zsh_snip_reply_name" \
  "test_read_header_sets_namespaced_reply_name"
assert_eq "A well formed snippet" "$_zsh_snip_reply_desc" \
  "test_read_header_sets_namespaced_reply_desc"

rm -rf "$HDR_TEST_DIR"

# Test _zsh_snip_get_name_line_number function
line_num=$(_zsh_snip_get_name_line_number "$TEST_SNIP_DIR/test-shebang")
assert_eq "2" "$line_num" \
  "finds name on line 2 when shebang present"

line_num=$(_zsh_snip_get_name_line_number "$TEST_SNIP_DIR/test-extra-comments")
assert_eq "3" "$line_num" \
  "finds name on line 3 with shebang and comment"

line_num=$(_zsh_snip_get_name_line_number "$TEST_SNIP_DIR/test-1")
assert_eq "1" "$line_num" \
  "finds name on line 1 for standard header"

# Cleanup
rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_extract_trailing_comment
# =============================================================================
log ""
log "Testing _zsh_snip_extract_trailing_comment..."

assert_eq "git amend" "$(_zsh_snip_extract_trailing_comment 'git commit --amend  # git amend')" \
  "extracts trailing comment"

assert_eq "description here" "$(_zsh_snip_extract_trailing_comment 'some command # description here')" \
  "extracts simple trailing comment"

assert_eq "" "$(_zsh_snip_extract_trailing_comment 'git status')" \
  "returns empty for command without comment"

assert_eq "note" "$(_zsh_snip_extract_trailing_comment 'echo "hello" # note')" \
  "extracts comment after quoted string"

assert_eq "adding files to git" "$(_zsh_snip_extract_trailing_comment 'git add # add: adding files to git')" \
  "extracts description from name: desc format"

# Note: regex doesn't understand quotes, so it captures from first unescaped #
# The save function uses % (last #) for stripping which handles this case correctly
assert_eq 'world" # actual comment' "$(_zsh_snip_extract_trailing_comment 'echo "hello # world" # actual comment')" \
  "captures from first unescaped # (quote-aware parsing not implemented)"

assert_eq "" "$(_zsh_snip_extract_trailing_comment $'cat <<EOF\n#!/bin/bash\necho hello\nEOF')" \
  "returns empty for multi-line input (heredoc)"

assert_eq "" "$(_zsh_snip_extract_trailing_comment $'line1\nline2 # comment')" \
  "returns empty for multi-line input even with comment on last line"

# =============================================================================
# Tests for _zsh_snip_extract_trailing_name
# =============================================================================
log ""
log "Testing _zsh_snip_extract_trailing_name..."

assert_eq "add" "$(_zsh_snip_extract_trailing_name 'git add # add: adding files to git')" \
  "extracts name from name: desc format"

assert_eq "" "$(_zsh_snip_extract_trailing_name 'git add # just a description')" \
  "returns empty when no colon in comment"

assert_eq "" "$(_zsh_snip_extract_trailing_name 'git status')" \
  "returns empty for command without comment"

assert_eq "my-snippet" "$(_zsh_snip_extract_trailing_name 'docker run # my-snippet: run container')" \
  "extracts hyphenated name"

assert_eq "" "$(_zsh_snip_extract_trailing_name $'cat <<EOF\n#!/bin/bash\nEOF')" \
  "returns empty for multi-line input"


# =============================================================================
# Tests for _zsh_snip_slugify
# =============================================================================
log ""
log "Testing _zsh_snip_slugify..."

assert_eq "hello-world" "$(_zsh_snip_slugify 'hello world')" \
  "replaces spaces with dashes"

assert_eq "git-add" "$(_zsh_snip_slugify 'git add')" \
  "handles simple command"

assert_eq "test" "$(_zsh_snip_slugify '  test  ')" \
  "trims leading/trailing dashes from whitespace"

assert_eq "my_snippet" "$(_zsh_snip_slugify 'my_snippet')" \
  "preserves underscores"

assert_eq "git/status" "$(_zsh_snip_slugify 'git/status')" \
  "preserves forward slashes for subdirectories"

assert_eq "file-txt" "$(_zsh_snip_slugify 'file.txt')" \
  "replaces dots with dashes"

assert_eq "simple-name" "$(_zsh_snip_slugify 'simple-name')" \
  "preserves dashes"


# =============================================================================
# Tests for _zsh_snip_read_command_preview
# =============================================================================
log ""
log "Testing _zsh_snip_read_command_preview..."

TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

_zsh_snip_write "$TEST_SNIP_DIR/test-1" "test-1" "desc" "short command"
preview=$(_zsh_snip_read_command_preview "$TEST_SNIP_DIR/test-1" 50)
assert_eq "short command" "$preview" \
  "returns full command when under limit"

_zsh_snip_write "$TEST_SNIP_DIR/test-2" "test-2" "desc" "this is a very long command that should be truncated because it exceeds fifty characters"
preview=$(_zsh_snip_read_command_preview "$TEST_SNIP_DIR/test-2" 50)
assert_eq "this is a very long command that should be truncat..." "$preview" \
  "truncates long command with ellipsis"

_zsh_snip_write "$TEST_SNIP_DIR/test-3" "test-3" "desc" $'first line\nsecond line'
preview=$(_zsh_snip_read_command_preview "$TEST_SNIP_DIR/test-3" 50)
assert_eq "first line" "$preview" \
  "returns only first line for multiline commands"

rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_insert_at_cursor
# =============================================================================
log ""
log "Testing _zsh_snip_insert_at_cursor..."

# Test inserting at cursor position in middle of buffer
BUFFER="docker run "
CURSOR=11
_zsh_snip_insert_at_cursor "--rm -it ubuntu"
assert_eq "docker run --rm -it ubuntu" "$BUFFER" \
  "inserts text at end of buffer"
assert_eq 26 "$CURSOR" \
  "moves cursor to end of inserted text"

# Test inserting at beginning
BUFFER="world"
CURSOR=0
_zsh_snip_insert_at_cursor "hello "
assert_eq "hello world" "$BUFFER" \
  "inserts text at beginning of buffer"
assert_eq 6 "$CURSOR" \
  "cursor positioned after inserted text at beginning"

# Test inserting in middle
BUFFER="git  origin"
CURSOR=4
_zsh_snip_insert_at_cursor "push"
assert_eq "git push origin" "$BUFFER" \
  "inserts text in middle of buffer"
assert_eq 8 "$CURSOR" \
  "cursor positioned after inserted text in middle"

# Test inserting into empty buffer
BUFFER=""
CURSOR=0
_zsh_snip_insert_at_cursor "ls -la"
assert_eq "ls -la" "$BUFFER" \
  "inserts into empty buffer"
assert_eq 6 "$CURSOR" \
  "cursor at end after insert into empty buffer"

# Test inserting multiline command
BUFFER="echo start; ; echo end"
CURSOR=12
_zsh_snip_insert_at_cursor $'git add .\ngit commit -m "test"'
assert_eq $'echo start; git add .\ngit commit -m "test"; echo end' "$BUFFER" \
  "inserts multiline command at cursor"


# =============================================================================
# Tests for _zsh_snip_duplicate_name
# =============================================================================
log ""
log "Testing _zsh_snip_duplicate_name..."

TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

# Test basic duplication (docker-1 → docker-2)
touch "$TEST_SNIP_DIR/docker-1"
assert_eq "docker-2" "$(_zsh_snip_duplicate_name "$TEST_SNIP_DIR" 'docker-1')" \
  "increments numeric suffix"

# Test when next number already exists (docker-1 with docker-2 existing → docker-3)
touch "$TEST_SNIP_DIR/docker-2"
assert_eq "docker-3" "$(_zsh_snip_duplicate_name "$TEST_SNIP_DIR" 'docker-1')" \
  "skips existing files to find next available"

# Test name without numeric suffix (node-shell → node-shell-1)
assert_eq "node-shell-1" "$(_zsh_snip_duplicate_name "$TEST_SNIP_DIR" 'node-shell')" \
  "appends -1 to name without numeric suffix"

# Test subdirectory (git/status-1 → git/status-2)
mkdir -p "$TEST_SNIP_DIR/git"
touch "$TEST_SNIP_DIR/git/status-1"
assert_eq "git/status-2" "$(_zsh_snip_duplicate_name "$TEST_SNIP_DIR" 'git/status-1')" \
  "handles subdirectory paths"

rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Regression tests for local-scope data-loss bugs (B1, B2)
# =============================================================================
log ""
log "Testing local-scope id/duplicate resolution..."

TEST_USER_DIR=$(mktemp -d)
TEST_LOCAL_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_USER_DIR"

# B1: _zsh_snip_next_id must scan the directory it is given, not $ZSH_SNIP_DIR
touch "$TEST_USER_DIR/docker-5"     # user snippet that must NOT be counted
touch "$TEST_LOCAL_DIR/docker-1"
touch "$TEST_LOCAL_DIR/docker-2"

assert_eq "3" "$(_zsh_snip_next_id "$TEST_LOCAL_DIR" 'docker')" \
  "next_id counts existing local snippets when saving local"

rm -rf "$TEST_USER_DIR" "$TEST_LOCAL_DIR"

# B2: _zsh_snip_duplicate_name must resolve against the given directory.
# Local dir has docker-1 only; user dir has no docker-* - the buggy version
# scanned the user dir and suggested the existing name docker-1.
TEST_USER_DIR=$(mktemp -d)
TEST_LOCAL_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_USER_DIR"
touch "$TEST_LOCAL_DIR/docker-1"

assert_eq "docker-2" "$(_zsh_snip_duplicate_name "$TEST_LOCAL_DIR" 'docker-1')" \
  "duplicate local snippet does not suggest existing name"

rm -rf "$TEST_USER_DIR" "$TEST_LOCAL_DIR"


# =============================================================================
# Regression test for overwrite protection (B2 defensive)
# =============================================================================
log ""
log "Testing _zsh_snip_write overwrite protection..."

TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

_zsh_snip_write "$TEST_SNIP_DIR/keep-me" "keep-me" "" "original content"

if _zsh_snip_write "$TEST_SNIP_DIR/keep-me" "keep-me" "" "overwritten content" 2>/dev/null; then
  write_rc=0
else
  write_rc=1
fi
assert_eq "1" "$write_rc" \
  "write refuses to overwrite existing snippet"

read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/keep-me")
assert_eq "original content" "$read_cmd" \
  "existing snippet content is preserved when overwrite is refused"

rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_apply_rename (A2 shared helper; folds in B7, B8)
# =============================================================================
log ""
log "Testing _zsh_snip_apply_rename..."

APPLY_DIR=$(mktemp -d)

# --- Valid rename: file is moved and new path reported --------------------
_zsh_snip_write "$APPLY_DIR/docker-1" "my-custom" "" "docker ps"
_zsh_snip_apply_rename "$APPLY_DIR/docker-1" "docker-1" "$APPLY_DIR"
assert_eq "$APPLY_DIR/my-custom" "$_zsh_snip_rename_path" \
  "valid rename reports new path"
assert_eq "" "$_zsh_snip_rename_msg" \
  "valid rename has no error message"
if [[ -f "$APPLY_DIR/my-custom" && ! -e "$APPLY_DIR/docker-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "valid rename moves the file"

# --- Unchanged name is a no-op --------------------------------------------
_zsh_snip_write "$APPLY_DIR/keep-1" "keep-1" "" "echo keep"
_zsh_snip_apply_rename "$APPLY_DIR/keep-1" "keep-1" "$APPLY_DIR"
assert_eq "$APPLY_DIR/keep-1" "$_zsh_snip_rename_path" \
  "unchanged name reports original path"
assert_eq "" "$_zsh_snip_rename_msg" \
  "unchanged name has no error message"
if [[ -f "$APPLY_DIR/keep-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "unchanged name leaves file in place"

# --- Subdirectory name (git/add) is preserved, not mangled by slugify -----
_zsh_snip_write "$APPLY_DIR/git-1" "git/add" "" "git add ."
_zsh_snip_apply_rename "$APPLY_DIR/git-1" "git-1" "$APPLY_DIR"
assert_eq "$APPLY_DIR/git/add" "$_zsh_snip_rename_path" \
  "subdir name git/add is preserved"
if [[ -f "$APPLY_DIR/git/add" && ! -e "$APPLY_DIR/git-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "subdir rename creates parent dir and moves file"

# --- B7: path-traversal name is rejected, file NOT moved outside the dir ---
_zsh_snip_write "$APPLY_DIR/evil-1" "../../evil" "" "rm -rf /"
_zsh_snip_apply_rename "$APPLY_DIR/evil-1" "evil-1" "$APPLY_DIR"
assert_eq "$APPLY_DIR/evil-1" "$_zsh_snip_rename_path" \
  "traversal rename keeps original path (does not escape dir)"
assert_contains "$_zsh_snip_rename_msg" "invalid name" \
  "traversal rename reports invalid-name error"
if [[ -f "$APPLY_DIR/evil-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "traversal rename keeps original file"

# --- B7: leading-slash (absolute) name is rejected ------------------------
_zsh_snip_write "$APPLY_DIR/abs-1" "/etc/passwd" "" "echo abs"
_zsh_snip_apply_rename "$APPLY_DIR/abs-1" "abs-1" "$APPLY_DIR" || true
assert_eq "$APPLY_DIR/abs-1" "$_zsh_snip_rename_path" \
  "absolute-path rename keeps original path"
assert_contains "$_zsh_snip_rename_msg" "invalid name" \
  "absolute-path rename reports invalid-name error"
if [[ -f "$APPLY_DIR/abs-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "absolute-path rename keeps original file"

# --- Collision: rename to an existing name is refused, original kept -------
_zsh_snip_write "$APPLY_DIR/taken" "taken" "" "echo taken"
_zsh_snip_write "$APPLY_DIR/src-1" "taken" "" "echo src"
_zsh_snip_apply_rename "$APPLY_DIR/src-1" "src-1" "$APPLY_DIR" || true
assert_eq "$APPLY_DIR/src-1" "$_zsh_snip_rename_path" \
  "collision rename keeps original path"
assert_contains "$_zsh_snip_rename_msg" "already exists" \
  "collision rename reports already-exists error"
if [[ -f "$APPLY_DIR/src-1" ]]; then r=yes; else r=no; fi
assert_eq "yes" "$r" \
  "collision rename keeps original file"
assert_eq "echo taken" "$(_zsh_snip_read_command "$APPLY_DIR/taken")" \
  "collision rename does not overwrite the existing target"

rm -rf "$APPLY_DIR"


# =============================================================================
# Tests for _zsh_snip_wrap_anon_func
# =============================================================================
log ""
log "Testing _zsh_snip_wrap_anon_func..."

# Test single-line command
wrapped=$(_zsh_snip_wrap_anon_func 'echo hello')
assert_eq $'() {\necho hello\n} ' "$wrapped" \
  "wraps single-line command in anonymous function"

# Test multi-line command (script)
wrapped=$(_zsh_snip_wrap_anon_func $'DOMAIN=$1\necho "Checking $DOMAIN"')
assert_eq $'() {\nDOMAIN=$1\necho "Checking $DOMAIN"\n} ' "$wrapped" \
  "wraps multi-line script in anonymous function"

# Test command with trailing newline (should not double newline)
wrapped=$(_zsh_snip_wrap_anon_func $'echo hello\n')
assert_eq $'() {\necho hello\n} ' "$wrapped" \
  "handles trailing newline without doubling"

# Test empty command
wrapped=$(_zsh_snip_wrap_anon_func '')
assert_eq $'() {\n\n} ' "$wrapped" \
  "handles empty command"

# Test with name only (second parameter)
wrapped=$(_zsh_snip_wrap_anon_func 'echo hello' 'my-snippet')
assert_eq $'() { # my-snippet\necho hello\n} ' "$wrapped" \
  "includes name as comment on opening brace line"

# Test with name and description - combined on first line
wrapped=$(_zsh_snip_wrap_anon_func 'echo hello' 'my-snippet' 'Say hello')
assert_eq $'() { # my-snippet: Say hello\necho hello\n} ' "$wrapped" \
  "combines name and description with colon on first line"

# Test with empty name but has description
wrapped=$(_zsh_snip_wrap_anon_func 'echo hello' '' 'Say hello')
assert_eq $'() { # Say hello\necho hello\n} ' "$wrapped" \
  "shows description only when name is empty"

# Test with empty name and empty description (should not add comment)
wrapped=$(_zsh_snip_wrap_anon_func 'echo hello' '' '')
assert_eq $'() {\necho hello\n} ' "$wrapped" \
  "no comment when name and description are empty"


# =============================================================================
# Tests for _zsh_snip_find_local_dir
# =============================================================================
log ""
log "Testing _zsh_snip_find_local_dir..."

# Create a temp directory structure for testing
TEST_PROJECT_ROOT=$(mktemp -d)
mkdir -p "$TEST_PROJECT_ROOT/sub/deep"
mkdir -p "$TEST_PROJECT_ROOT/.zsh-snip"

# Save original values
ORIG_ZSH_SNIP_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-}"

# Test finding .zsh-snip in current directory
ZSH_SNIP_LOCAL_PATH=".zsh-snip"
cd "$TEST_PROJECT_ROOT"
assert_eq "$TEST_PROJECT_ROOT/.zsh-snip" "$(_zsh_snip_find_local_dir)" \
  "finds .zsh-snip in current directory"

# Test finding .zsh-snip from subdirectory
cd "$TEST_PROJECT_ROOT/sub/deep"
assert_eq "$TEST_PROJECT_ROOT/.zsh-snip" "$(_zsh_snip_find_local_dir)" \
  "finds .zsh-snip walking up from deep subdirectory"

# Test with custom local path name
mkdir -p "$TEST_PROJECT_ROOT/snippets"
ZSH_SNIP_LOCAL_PATH="snippets"
assert_eq "$TEST_PROJECT_ROOT/snippets" "$(_zsh_snip_find_local_dir)" \
  "finds custom-named local snippet directory"

# Test disabled when ZSH_SNIP_LOCAL_PATH is empty
ZSH_SNIP_LOCAL_PATH=""
assert_eq "" "$(_zsh_snip_find_local_dir)" \
  "returns empty when ZSH_SNIP_LOCAL_PATH is empty"

# Test when no local dir exists
ZSH_SNIP_LOCAL_PATH=".nonexistent-snip-dir"
assert_eq "" "$(_zsh_snip_find_local_dir)" \
  "returns empty when local dir not found"

# Restore and cleanup
ZSH_SNIP_LOCAL_PATH="$ORIG_ZSH_SNIP_LOCAL_PATH"
cd /
rm -rf "$TEST_PROJECT_ROOT"


# =============================================================================
# Tests for _zsh_snip_enumerate (shared snippet iterator)
# =============================================================================
log ""
log "Testing _zsh_snip_enumerate..."

# Isolated fixture: user + local dirs with a shadowed name, a subdir snippet,
# and hidden/dotfiles in both scopes.
ENUM_TEST_DIR=$(mktemp -d)
ENUM_USER_DIR="$ENUM_TEST_DIR/user"
ENUM_PROJ_DIR="$ENUM_TEST_DIR/proj"
ENUM_LOCAL_DIR="$ENUM_PROJ_DIR/.zsh-snip"
mkdir -p "$ENUM_USER_DIR/git" "$ENUM_LOCAL_DIR" "$ENUM_PROJ_DIR/sub"

# User snippets (incl. subdir git/add) + hidden files
touch "$ENUM_USER_DIR/alpha" "$ENUM_USER_DIR/shared" "$ENUM_USER_DIR/git/add"
touch "$ENUM_USER_DIR/.secret" "$ENUM_USER_DIR/git/.ignore"
# Local snippets (shared shadows the user one) + hidden file
touch "$ENUM_LOCAL_DIR/local-only" "$ENUM_LOCAL_DIR/shared" "$ENUM_LOCAL_DIR/.hidden"

ORIG_ENUM_ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
ORIG_ENUM_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-}"
ORIG_ENUM_PWD="$PWD"
ZSH_SNIP_DIR="$ENUM_USER_DIR"
ZSH_SNIP_LOCAL_PATH=".zsh-snip"
cd "$ENUM_PROJ_DIR/sub"

ENUM_US=$'\x1f'
# Render _zsh_snip_enum as "scope:name|scope:name|..." (order-preserving)
_enum_dump() {
  local rec s r n out=()
  for rec in "${_zsh_snip_enum[@]}"; do
    s="${rec%%${ENUM_US}*}"; r="${rec#*${ENUM_US}}"; n="${r%%${ENUM_US}*}"
    out+=("$s:$n")
  done
  local IFS='|'; echo "${out[*]}"
}

# dedup mode, both scopes: local shadows user, local-first ordering
_zsh_snip_enumerate both dedup
assert_eq "local:local-only|local:shared|user:alpha|user:git/add" "$(_enum_dump)" \
  "enumerate dedup both: local shadows user, ordered local-then-user, hidden skipped"

# raw mode, both scopes: user-first, both scopes in full, no dedup
_zsh_snip_enumerate both raw
assert_eq "user:alpha|user:git/add|user:shared|local:local-only|local:shared" "$(_enum_dump)" \
  "enumerate raw both: user-first, both scopes, no dedup"

# scope user only
_zsh_snip_enumerate user dedup
assert_eq "user:alpha|user:git/add|user:shared" "$(_enum_dump)" \
  "enumerate scope user: only user snippets"

# scope local only (dedup + raw both yield just local)
_zsh_snip_enumerate local dedup
assert_eq "local:local-only|local:shared" "$(_enum_dump)" \
  "enumerate scope local dedup: only local snippets"
_zsh_snip_enumerate local raw
assert_eq "local:local-only|local:shared" "$(_enum_dump)" \
  "enumerate scope local raw: only local snippets"

# filepath field points at the real file (local wins for shadowed name)
_zsh_snip_enumerate both dedup
enum_shared_fp=""
enum_alpha_fp=""
for rec in "${_zsh_snip_enum[@]}"; do
  [[ "$rec" == "local${ENUM_US}shared${ENUM_US}"* ]] && enum_shared_fp="${rec##*${ENUM_US}}"
  [[ "$rec" == "user${ENUM_US}alpha${ENUM_US}"* ]] && enum_alpha_fp="${rec##*${ENUM_US}}"
done
assert_eq "$ENUM_LOCAL_DIR/shared" "$enum_shared_fp" \
  "enumerate filepath field resolves shadowed name to local file"
assert_eq "$ENUM_USER_DIR/alpha" "$enum_alpha_fp" \
  "enumerate filepath field resolves user snippet path"

# Hidden/dotfiles are skipped even when GLOB_DOTS makes the glob match them
setopt GLOB_DOTS
_zsh_snip_enumerate both dedup
setopt NO_GLOB_DOTS
enum_dump_out="$(_enum_dump)"
[[ "$enum_dump_out" != *".secret"* && "$enum_dump_out" != *".hidden"* && "$enum_dump_out" != *".ignore"* ]]
assert_eq 0 $? "enumerate skips hidden/dotfiles even under GLOB_DOTS"

# Cleanup enumerate fixture
cd "$ORIG_ENUM_PWD"
ZSH_SNIP_DIR="$ORIG_ENUM_ZSH_SNIP_DIR"
ZSH_SNIP_LOCAL_PATH="$ORIG_ENUM_LOCAL_PATH"
unfunction _enum_dump
rm -rf "$ENUM_TEST_DIR"


# =============================================================================
# Tests for _zsh_snip_build_fzf_list (search helper: fzf input list)
# Characterizes the exact aligned, tab-delimited list format fed to fzf, so the
# pure-zsh column padding stays byte-compatible with fzf's --delimiter/--with-nth.
# =============================================================================
log ""
log "Testing _zsh_snip_build_fzf_list..."

BUILD_DIR=$(mktemp -d)
cat > "$BUILD_DIR/longnamehere" <<'EOF'
# name: longnamehere
# description: a longer description
# ---
echo long
EOF
cat > "$BUILD_DIR/s" <<'EOF'
# name: s
# description: short desc
# ---
echo short
EOF

BUILD_US=$'\x1f'
_zsh_snip_enum=(
  "user${BUILD_US}longnamehere${BUILD_US}$BUILD_DIR/longnamehere"
  "user${BUILD_US}s${BUILD_US}$BUILD_DIR/s"
)
# desc_width=20, cmd_width=30 (matches an 80-column terminal budget)
build_out=$(_zsh_snip_build_fzf_list 20 30)
build_lines=("${(f)build_out}")

assert_eq 2 ${#build_lines} \
  "test_build_fzf_list_emits_one_line_per_snippet"

# Locate rows by their (trimmed) first field
build_short_line="" build_long_line=""
for line in "${build_lines[@]}"; do
  bf1="${line%%$'\t'*}"
  [[ "$bf1" == "~ s"* ]] && build_short_line="$line"
  [[ "$bf1" == "~ longnamehere"* ]] && build_long_line="$line"
done

# Exactly 4 tab-separated fields (3 tabs)
build_short_tabs="${build_short_line//[^$'\t']/}"
assert_eq 3 ${#build_short_tabs} \
  "test_build_fzf_list_record_has_four_tab_fields"

# Name column padded to the widest name (~ longnamehere = 14 chars)
build_short_f1="${build_short_line%%$'\t'*}"
build_long_f1="${build_long_line%%$'\t'*}"
assert_eq "~ s           " "$build_short_f1" \
  "test_build_fzf_list_pads_name_to_column_width"
assert_eq "~ longnamehere" "$build_long_f1" \
  "test_build_fzf_list_widest_name_defines_column_width"

# Description column padded to desc_width (20 chars)
build_short_rest="${build_short_line#*$'\t'}"
build_short_f2="${build_short_rest%%$'\t'*}"
assert_eq "short desc          " "$build_short_f2" \
  "test_build_fzf_list_pads_description_to_desc_width"

# Last field is the unpadded full path
build_short_f4="${build_short_line##*$'\t'}"
assert_eq "$BUILD_DIR/s" "$build_short_f4" \
  "test_build_fzf_list_last_field_is_unpadded_path"

# Local-scope records get the "!" prefix instead of "~"
_zsh_snip_enum=("local${BUILD_US}s${BUILD_US}$BUILD_DIR/s")
build_out=$(_zsh_snip_build_fzf_list 20 30)
build_f1="${build_out%%$'\t'*}"
assert_eq "! s" "$build_f1" \
  "test_build_fzf_list_uses_bang_prefix_for_local_scope"

# Description longer than desc_width is truncated with an ellipsis
cat > "$BUILD_DIR/longdesc" <<'EOF'
# name: longdesc
# description: aaaaaaaaaaaaaaaaaaaaaaaaaaaa
# ---
echo x
EOF
_zsh_snip_enum=("user${BUILD_US}longdesc${BUILD_US}$BUILD_DIR/longdesc")
build_out=$(_zsh_snip_build_fzf_list 10 30)
build_rest="${build_out#*$'\t'}"
build_f2="${build_rest%%$'\t'*}"
assert_eq "aaaaaaaaa…" "$build_f2" \
  "test_build_fzf_list_truncates_long_description_with_ellipsis"

rm -rf "$BUILD_DIR"
_zsh_snip_enum=()


# =============================================================================
# Tests for _zsh_snip_parse_fzf_output (search helper: parse fzf return)
# Characterizes how the query/key/selection triple from fzf is split into the
# pressed key plus the selected snippet identity (scope/name/filepath).
# =============================================================================
log ""
log "Testing _zsh_snip_parse_fzf_output..."

# Enter (empty key), user scope, padded name field must be trimmed
_zsh_snip_parse_fzf_output $'myquery\n\n~ docker-run    \tRun it\tprev\t/path/to/docker-run'
assert_eq "myquery" "$_zsh_snip_fzf_query" \
  "test_parse_fzf_output_captures_query"
assert_eq "" "$_zsh_snip_fzf_key" \
  "test_parse_fzf_output_empty_key_for_enter"
assert_eq "1" "$_zsh_snip_fzf_has_selection" \
  "test_parse_fzf_output_flags_selection_present"
assert_eq "user" "$_zsh_snip_fzf_scope" \
  "test_parse_fzf_output_tilde_prefix_is_user_scope"
assert_eq "docker-run" "$_zsh_snip_fzf_name" \
  "test_parse_fzf_output_strips_prefix_and_padding_from_name"
assert_eq "/path/to/docker-run" "$_zsh_snip_fzf_filepath" \
  "test_parse_fzf_output_extracts_full_path_field"

# Local scope (! prefix)
_zsh_snip_parse_fzf_output $'q\nctrl-e\n! local-snip\tdesc\tprev\t/local/local-snip'
assert_eq "ctrl-e" "$_zsh_snip_fzf_key" \
  "test_parse_fzf_output_reports_ctrl_e_key"
assert_eq "local" "$_zsh_snip_fzf_scope" \
  "test_parse_fzf_output_bang_prefix_is_local_scope"
assert_eq "local-snip" "$_zsh_snip_fzf_name" \
  "test_parse_fzf_output_local_name_stripped"

# Subdirectory name is preserved
_zsh_snip_parse_fzf_output $'q\nctrl-x\n~ git/add\tdesc\tprev\t/path/git/add'
assert_eq "git/add" "$_zsh_snip_fzf_name" \
  "test_parse_fzf_output_preserves_subdir_name"
assert_eq "/path/git/add" "$_zsh_snip_fzf_filepath" \
  "test_parse_fzf_output_subdir_full_path"

# Each --expect key round-trips through the key field
for expect_key in alt-e ctrl-i ctrl-n ctrl-d alt-x ctrl-y; do
  _zsh_snip_parse_fzf_output "q"$'\n'"$expect_key"$'\n'"~ n\td\tp\t/x/n"
  assert_eq "$expect_key" "$_zsh_snip_fzf_key" \
    "test_parse_fzf_output_reports_${expect_key}_key"
done

# No selection: only query + key present (user cancelled or pressed key on none)
_zsh_snip_parse_fzf_output $'leftover\nctrl-x'
assert_eq "leftover" "$_zsh_snip_fzf_query" \
  "test_parse_fzf_output_keeps_query_when_no_selection"
assert_eq "ctrl-x" "$_zsh_snip_fzf_key" \
  "test_parse_fzf_output_keeps_key_when_no_selection"
assert_eq "0" "$_zsh_snip_fzf_has_selection" \
  "test_parse_fzf_output_flags_no_selection"
assert_eq "" "$_zsh_snip_fzf_name" \
  "test_parse_fzf_output_empty_name_when_no_selection"

# Trailing newline but empty selection is also "no selection"
_zsh_snip_parse_fzf_output $'q\nctrl-x\n'
assert_eq "0" "$_zsh_snip_fzf_has_selection" \
  "test_parse_fzf_output_empty_trailing_selection_is_no_selection"


# =============================================================================
# Tests for zsh-snip CLI interface
# =============================================================================
log ""
log "Testing zsh-snip CLI interface..."

# Create test environment for CLI tests
CLI_TEST_DIR=$(mktemp -d)
CLI_USER_DIR="$CLI_TEST_DIR/user-snippets"
CLI_LOCAL_DIR="$CLI_TEST_DIR/project/.zsh-snip"
CLI_PROJECT_DIR="$CLI_TEST_DIR/project/subdir"
mkdir -p "$CLI_USER_DIR"
mkdir -p "$CLI_LOCAL_DIR"
mkdir -p "$CLI_PROJECT_DIR"

# Save original values
ORIG_ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
ORIG_ZSH_SNIP_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-}"
ORIG_PWD="$PWD"

# Set up test environment
ZSH_SNIP_DIR="$CLI_USER_DIR"
ZSH_SNIP_LOCAL_PATH=".zsh-snip"
cd "$CLI_PROJECT_DIR"

# Helper to create test snippets
_create_cli_test_snippet() {
  local dir="$1"
  local name="$2"
  local desc="$3"
  local cmd="$4"
  local args="${5:-}"

  [[ "$name" == */* ]] && mkdir -p "$dir/${name%/*}"

  cat > "$dir/$name" <<EOF
# name: $name
# description: $desc
${args:+# args: $args}
# created: 2024-01-01T00:00:00+00:00
# ---
$cmd
EOF
}

# Create test snippets
_create_cli_test_snippet "$CLI_USER_DIR" "git-status" "Show git status" "git status"
_create_cli_test_snippet "$CLI_USER_DIR" "git-push" "Push to remote" "git push"
_create_cli_test_snippet "$CLI_USER_DIR" "docker-run" "Run docker container" 'docker run -it $1'
_create_cli_test_snippet "$CLI_USER_DIR" "deploy" "Deploy app" 'deploy.sh $1 $2' '<env> <version>'
_create_cli_test_snippet "$CLI_USER_DIR" "sub/nested" "Nested snippet" "echo nested"
_create_cli_test_snippet "$CLI_LOCAL_DIR" "local-only" "Local only snippet" "echo local"
_create_cli_test_snippet "$CLI_LOCAL_DIR" "git-status" "Local git status override" "git status --short"
# Hidden/dotfile snippet - must never be listed
_create_cli_test_snippet "$CLI_USER_DIR" ".hidden-snip" "Should be skipped" "echo hidden"

# -----------------------------------------------------------------------------
# Tests for zsh-snip list
# -----------------------------------------------------------------------------
log ""
log "Testing zsh-snip list..."

# Test: list shows all snippets
output=$(zsh-snip list 2>&1)
assert_contains "$output" "git-status" "list shows git-status snippet"
assert_contains "$output" "git-push" "list shows git-push snippet"
assert_contains "$output" "local-only" "list shows local-only snippet"

# Test: list with glob filter
output=$(zsh-snip list 'git-*' 2>&1)
assert_contains "$output" "git-status" "list glob filter matches git-status"
assert_contains "$output" "git-push" "list glob filter matches git-push"
[[ "$output" != *"docker-run"* ]]
assert_eq 0 $? "list glob filter excludes docker-run"

# Test: list with substring filter (no glob chars = substring match)
output=$(zsh-snip list 'git' 2>&1)
assert_contains "$output" "git-status" "list substring matches git-status"
assert_contains "$output" "git-push" "list substring matches git-push"
[[ "$output" != *"docker-run"* ]]
assert_eq 0 $? "list substring excludes docker-run"

# Test: list substring matches in path (e.g., sub/nested matches 'sub')
output=$(zsh-snip list 'sub' 2>&1)
assert_contains "$output" "sub/nested" "list substring matches nested path"

# Test: list --names-only
output=$(zsh-snip list --names-only 2>&1)
# Should NOT contain path (e.g., no ~)
[[ "$output" != *"~"* ]]
assert_eq 0 $? "list --names-only excludes path"
assert_contains "$output" "git-status" "list --names-only shows names"

# Test: list --full-path
output=$(zsh-snip list --full-path 2>&1)
assert_contains "$output" "$CLI_USER_DIR" "list --full-path shows absolute user path"
assert_contains "$output" "$CLI_LOCAL_DIR" "list --full-path shows absolute local path"

# Test: list --user (only user snippets)
output=$(zsh-snip list --user 2>&1)
assert_contains "$output" "git-push" "list --user shows user snippets"
[[ "$output" != *"local-only"* ]]
assert_eq 0 $? "list --user excludes local snippets"

# Test: list --local (only local snippets)
output=$(zsh-snip list --local 2>&1)
assert_contains "$output" "local-only" "list --local shows local snippets"
# git-status appears in both, so check it's there
assert_contains "$output" "git-status" "list --local shows local git-status"
# But deploy is user-only
[[ "$output" != *"deploy"* ]]
assert_eq 0 $? "list --local excludes user-only snippets"

# Test: list shows local preference (local first when both have same name)
output=$(zsh-snip list 'git-status' 2>&1)
# Should show the local version (which has "Local git status" description)
assert_contains "$output" "Local git status" "list prefers local over user for same name"

# Test: list with nested snippet
output=$(zsh-snip list 'sub/*' 2>&1)
assert_contains "$output" "sub/nested" "list shows nested snippet path"

# Test: list skips hidden/dotfile snippets
output=$(zsh-snip list 2>&1)
[[ "$output" != *".hidden-snip"* ]]
assert_eq 0 $? "list skips hidden/dotfile snippets"

# -----------------------------------------------------------------------------
# Tests for zsh-snip expand
# -----------------------------------------------------------------------------
log ""
log "Testing zsh-snip expand..."

# Test: expand outputs command content
output=$(zsh-snip expand git-push 2>&1)
assert_eq "git push" "$output" "expand outputs command content"

# Test: expand prefers local when same name exists
output=$(zsh-snip expand git-status 2>&1)
assert_eq "git status --short" "$output" "expand prefers local over user"

# Test: expand --user forces user snippet
output=$(zsh-snip expand --user git-status 2>&1)
assert_eq "git status" "$output" "expand --user forces user snippet"

# Test: expand --local forces local snippet
output=$(zsh-snip expand --local git-status 2>&1)
assert_eq "git status --short" "$output" "expand --local forces local snippet"

# Test: expand error on not found
output=$(zsh-snip expand nonexistent 2>&1) && result=0 || result=$?
assert_eq 1 $result "expand returns exit 1 for not found"
assert_contains "$output" "not found" "expand error message mentions not found"

# Test: expand --local error when only in user
output=$(zsh-snip expand --local git-push 2>&1) && result=0 || result=$?
assert_eq 1 $result "expand --local returns exit 1 for user-only snippet"

# Test: expand nested snippet
output=$(zsh-snip expand sub/nested 2>&1)
assert_eq "echo nested" "$output" "expand works with nested snippets"

# -----------------------------------------------------------------------------
# Tests for zsh-snip path
# -----------------------------------------------------------------------------
log ""
log "Testing zsh-snip path..."

# Test: path outputs full path
output=$(zsh-snip path git-push 2>&1)
assert_eq "$CLI_USER_DIR/git-push" "$output" "path outputs full path"

# Test: path prefers local when same name exists
output=$(zsh-snip path git-status 2>&1)
assert_eq "$CLI_LOCAL_DIR/git-status" "$output" "path prefers local over user"

# Test: path --user forces user snippet
output=$(zsh-snip path --user git-status 2>&1)
assert_eq "$CLI_USER_DIR/git-status" "$output" "path --user forces user snippet"

# Test: path --local forces local snippet
output=$(zsh-snip path --local git-status 2>&1)
assert_eq "$CLI_LOCAL_DIR/git-status" "$output" "path --local forces local snippet"

# Test: path error on not found
output=$(zsh-snip path nonexistent 2>&1) && result=0 || result=$?
assert_eq 1 $result "path returns exit 1 for not found"
assert_contains "$output" "not found" "path error message mentions not found"

# Test: path nested snippet
output=$(zsh-snip path sub/nested 2>&1)
assert_eq "$CLI_USER_DIR/sub/nested" "$output" "path works with nested snippets"

# -----------------------------------------------------------------------------
# Tests for zsh-snip exec
# -----------------------------------------------------------------------------
log ""
log "Testing zsh-snip exec..."

# Test: exec runs command (simple echo test)
_create_cli_test_snippet "$CLI_USER_DIR" "echo-test" "Echo test" 'echo "executed"'
output=$(zsh-snip exec echo-test 2>&1)
assert_eq "executed" "$output" "exec runs the command"

# Test: exec with args
_create_cli_test_snippet "$CLI_USER_DIR" "echo-args" "Echo with args" 'echo "arg: $1"' '<arg>'
output=$(zsh-snip exec echo-args "hello" 2>&1)
assert_eq "arg: hello" "$output" "exec passes args to command"

# Test: exec error when args required but not given
output=$(zsh-snip exec echo-args 2>&1) && result=0 || result=$?
assert_eq 1 $result "exec returns exit 1 when args required but not given"
assert_contains "$output" "args" "exec error mentions args requirement"

# Test: exec without args field runs even with no args
_create_cli_test_snippet "$CLI_USER_DIR" "no-args-needed" "No args" 'echo "no args needed"'
output=$(zsh-snip exec no-args-needed 2>&1)
assert_eq "no args needed" "$output" "exec runs without args when not required"

# Test: exec prefers local
_create_cli_test_snippet "$CLI_USER_DIR" "scope-test" "User version" 'echo "user"'
_create_cli_test_snippet "$CLI_LOCAL_DIR" "scope-test" "Local version" 'echo "local"'
output=$(zsh-snip exec scope-test 2>&1)
assert_eq "local" "$output" "exec prefers local over user"

# Test: exec --user forces user snippet
output=$(zsh-snip exec --user scope-test 2>&1)
assert_eq "user" "$output" "exec --user forces user snippet"

# Test: exec error on not found
output=$(zsh-snip exec nonexistent 2>&1) && result=0 || result=$?
assert_eq 1 $result "exec returns exit 1 for not found"

# Test: exec adds to history (check fc -l)
# Note: History testing is tricky in non-interactive shell, skip for unit tests

# -----------------------------------------------------------------------------
# Characterization: CLI option-parsing contract (list/expand/path/exec/yank)
# -----------------------------------------------------------------------------
log ""
log "Testing CLI option-parsing contract..."

# list: unknown option is rejected with exit 1
output=$(zsh-snip list --bogus 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_list_rejects_unknown_option_exit_1"
assert_contains "$output" "unknown option" "test_list_rejects_unknown_option_message"

# list: last positional filter wins when several are given
output=$(zsh-snip list git-push docker-run 2>&1)
assert_contains "$output" "docker-run" "test_list_last_positional_filter_wins_shows_last"
[[ "$output" != *"git-push"* ]]
assert_eq 0 $? "test_list_last_positional_filter_wins_excludes_earlier"

# list: scope flag may appear before the positional filter
output=$(zsh-snip list --user git 2>&1)
assert_contains "$output" "git-push" "test_list_scope_flag_before_filter_keeps_user"
[[ "$output" != *"local-only"* ]]
assert_eq 0 $? "test_list_user_scope_excludes_local"

# expand: missing name errors with exit 1
output=$(zsh-snip expand 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_expand_missing_name_exit_1"
assert_contains "$output" "missing snippet name" "test_expand_missing_name_message"

# expand: unknown option is rejected
output=$(zsh-snip expand --bogus git-push 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_expand_rejects_unknown_option_exit_1"
assert_contains "$output" "unknown option" "test_expand_rejects_unknown_option_message"

# path: missing name errors with exit 1
output=$(zsh-snip path 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_path_missing_name_exit_1"
assert_contains "$output" "missing snippet name" "test_path_missing_name_message"

# path: extra positional argument is rejected
output=$(zsh-snip path git-push extra 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_path_rejects_extra_argument_exit_1"
assert_contains "$output" "unexpected argument" "test_path_rejects_extra_argument_message"

# yank: missing name errors before clipboard resolution
output=$(zsh-snip yank 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_yank_missing_name_exit_1"
assert_contains "$output" "missing snippet name" "test_yank_missing_name_message"

# yank: unknown option is rejected
output=$(zsh-snip yank --bogus 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_yank_rejects_unknown_option_exit_1"
assert_contains "$output" "unknown option" "test_yank_rejects_unknown_option_message"

# exec: missing name errors with exit 1
output=$(zsh-snip exec 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_exec_missing_name_exit_1"
assert_contains "$output" "missing snippet name" "test_exec_missing_name_message"

# exec: forwards remaining positional args to the snippet (current quoting merges
# them into a single "$@" element via ${(q)args[@]} - characterize as-is)
_create_cli_test_snippet "$CLI_USER_DIR" "echo-multi" "Echo all args" 'printf "%s\n" "$@"' '<a> <b>'
output=$(zsh-snip exec echo-multi one two 2>&1)
assert_eq "one two" "$output" "test_exec_forwards_remaining_args_to_snippet"

# exec: a dashed token after the name is parsed as an option (rejected), not forwarded
output=$(zsh-snip exec echo-multi --bogus 2>&1) && result=0 || result=$?
assert_eq 1 $result "test_exec_dashed_arg_after_name_is_rejected_exit_1"
assert_contains "$output" "unknown option" "test_exec_dashed_arg_after_name_is_rejected_message"

# exec: a scope flag after the name is consumed as scope, not forwarded
_create_cli_test_snippet "$CLI_USER_DIR" "scope-forward" "User only" 'echo "userscope"'
output=$(zsh-snip exec scope-forward --user 2>&1)
assert_eq "userscope" "$output" "test_exec_scope_flag_after_name_sets_scope"

# -----------------------------------------------------------------------------
# Tests for invalid subcommands
# -----------------------------------------------------------------------------
log ""
log "Testing zsh-snip error handling..."

# Test: unknown subcommand
output=$(zsh-snip unknown 2>&1) && result=0 || result=$?
assert_eq 1 $result "unknown subcommand returns exit 1"
assert_contains "$output" "unknown" "error mentions unknown command"

# Test: no subcommand shows usage
output=$(zsh-snip 2>&1) && result=0 || result=$?
assert_eq 1 $result "no subcommand returns exit 1"
assert_contains "$output" "list" "usage mentions list"
assert_contains "$output" "path" "usage mentions path"
assert_contains "$output" "expand" "usage mentions expand"
assert_contains "$output" "exec" "usage mentions exec"

# Cleanup CLI test environment
cd "$ORIG_PWD"
ZSH_SNIP_DIR="$ORIG_ZSH_SNIP_DIR"
ZSH_SNIP_LOCAL_PATH="$ORIG_ZSH_SNIP_LOCAL_PATH"
rm -rf "$CLI_TEST_DIR"


# =============================================================================
# Tests for _zsh_snip_get_yank_cmd
# =============================================================================
log ""
log "Testing _zsh_snip_get_yank_cmd..."

# Save original values
ORIG_ZSH_SNIP_YANK_CMD="${ZSH_SNIP_YANK_CMD:-__unset__}"
ORIG_DISPLAY="${DISPLAY:-__unset__}"
ORIG_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-__unset__}"

# Helper to reset environment
_reset_yank_env() {
  unset ZSH_SNIP_YANK_CMD DISPLAY WAYLAND_DISPLAY
}

# Test: explicit ZSH_SNIP_YANK_CMD is used
_reset_yank_env
ZSH_SNIP_YANK_CMD="my-custom-copy"
assert_eq "my-custom-copy" "$(_zsh_snip_get_yank_cmd)" \
  "uses explicit ZSH_SNIP_YANK_CMD"

# Test: empty ZSH_SNIP_YANK_CMD disables yank
_reset_yank_env
ZSH_SNIP_YANK_CMD=""
assert_eq "" "$(_zsh_snip_get_yank_cmd)" \
  "empty ZSH_SNIP_YANK_CMD disables yank"

# Test: X11 detection with xclip available
_reset_yank_env
DISPLAY=":0"
# Create mock xclip
TEST_BIN_DIR=$(mktemp -d)
cat > "$TEST_BIN_DIR/xclip" <<'EOF'
#!/bin/sh
echo "mock xclip"
EOF
chmod +x "$TEST_BIN_DIR/xclip"
PATH="$TEST_BIN_DIR:$PATH"
result=$(_zsh_snip_get_yank_cmd)
assert_eq "xclip -selection clipboard" "$result" \
  "detects X11 with xclip"
rm -rf "$TEST_BIN_DIR"

# Test: Wayland detection with wl-copy available
_reset_yank_env
WAYLAND_DISPLAY="wayland-0"
TEST_BIN_DIR=$(mktemp -d)
cat > "$TEST_BIN_DIR/wl-copy" <<'EOF'
#!/bin/sh
echo "mock wl-copy"
EOF
chmod +x "$TEST_BIN_DIR/wl-copy"
PATH="$TEST_BIN_DIR:$PATH"
result=$(_zsh_snip_get_yank_cmd)
assert_eq "wl-copy" "$result" \
  "detects Wayland with wl-copy"
rm -rf "$TEST_BIN_DIR"

# Test: no display, no clipboard command returns empty
_reset_yank_env
# Ensure no clipboard commands in PATH for this test
PATH="/usr/bin:/bin"
result=$(_zsh_snip_get_yank_cmd)
assert_eq "" "$result" \
  "returns empty when no clipboard available"

# Restore original values
if [[ "$ORIG_ZSH_SNIP_YANK_CMD" != "__unset__" ]]; then
  ZSH_SNIP_YANK_CMD="$ORIG_ZSH_SNIP_YANK_CMD"
else
  unset ZSH_SNIP_YANK_CMD
fi
if [[ "$ORIG_DISPLAY" != "__unset__" ]]; then
  DISPLAY="$ORIG_DISPLAY"
else
  unset DISPLAY
fi
if [[ "$ORIG_WAYLAND_DISPLAY" != "__unset__" ]]; then
  WAYLAND_DISPLAY="$ORIG_WAYLAND_DISPLAY"
else
  unset WAYLAND_DISPLAY
fi


# =============================================================================
# Tests for zsh-snip yank CLI command
# =============================================================================
log ""
log "Testing zsh-snip yank..."

# Create test environment for CLI yank tests
YANK_TEST_DIR=$(mktemp -d)
YANK_USER_DIR="$YANK_TEST_DIR/user-snippets"
YANK_LOCAL_DIR="$YANK_TEST_DIR/project/.zsh-snip"
YANK_PROJECT_DIR="$YANK_TEST_DIR/project/subdir"
mkdir -p "$YANK_USER_DIR"
mkdir -p "$YANK_LOCAL_DIR"
mkdir -p "$YANK_PROJECT_DIR"

# Save original values
ORIG_ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
ORIG_ZSH_SNIP_LOCAL_PATH="${ZSH_SNIP_LOCAL_PATH:-}"
ORIG_PWD_YANK="$PWD"

# Set up test environment
ZSH_SNIP_DIR="$YANK_USER_DIR"
ZSH_SNIP_LOCAL_PATH=".zsh-snip"
cd "$YANK_PROJECT_DIR"

# Helper to create test snippets for yank tests
_create_yank_test_snippet() {
  local dir="$1"
  local name="$2"
  local cmd="$3"

  [[ "$name" == */* ]] && mkdir -p "$dir/${name%/*}"

  cat > "$dir/$name" <<EOF
# name: $name
# description: Test snippet
# created: 2024-01-01T00:00:00+00:00
# ---
$cmd
EOF
}

# Create test snippets
_create_yank_test_snippet "$YANK_USER_DIR" "yank-test" "echo yank-user"
_create_yank_test_snippet "$YANK_LOCAL_DIR" "yank-test" "echo yank-local"
_create_yank_test_snippet "$YANK_USER_DIR" "yank-only-user" "echo only-user"

# Create mock clipboard command to capture what was yanked
YANK_CAPTURE_FILE="$YANK_TEST_DIR/yanked_content"
cat > "$YANK_TEST_DIR/mock-copy" <<EOF
#!/bin/sh
cat > "$YANK_CAPTURE_FILE"
EOF
chmod +x "$YANK_TEST_DIR/mock-copy"
ZSH_SNIP_YANK_CMD="$YANK_TEST_DIR/mock-copy"

# Test: yank outputs to clipboard command
output=$(zsh-snip yank yank-only-user 2>&1)
yanked=$(cat "$YANK_CAPTURE_FILE" 2>/dev/null)
assert_eq "echo only-user" "$yanked" \
  "yank sends content to clipboard command"

# Test: yank prefers local over user
: > "$YANK_CAPTURE_FILE"  # Clear capture file
output=$(zsh-snip yank yank-test 2>&1)
yanked=$(cat "$YANK_CAPTURE_FILE" 2>/dev/null)
assert_eq "echo yank-local" "$yanked" \
  "yank prefers local over user snippet"

# Test: yank --user forces user snippet
: > "$YANK_CAPTURE_FILE"
output=$(zsh-snip yank --user yank-test 2>&1)
yanked=$(cat "$YANK_CAPTURE_FILE" 2>/dev/null)
assert_eq "echo yank-user" "$yanked" \
  "yank --user forces user snippet"

# Test: yank error on not found
output=$(zsh-snip yank nonexistent 2>&1) && result=0 || result=$?
assert_eq 1 $result "yank returns exit 1 for not found"
assert_contains "$output" "not found" "yank error mentions not found"

# Test: yank error when no clipboard command available
ORIG_YANK_CMD="$ZSH_SNIP_YANK_CMD"
ZSH_SNIP_YANK_CMD=""
output=$(zsh-snip yank yank-only-user 2>&1) && result=0 || result=$?
assert_eq 1 $result "yank returns exit 1 when clipboard unavailable"
assert_contains "$output" "clipboard" "yank error mentions clipboard"
ZSH_SNIP_YANK_CMD="$ORIG_YANK_CMD"

# Cleanup yank test environment
cd "$ORIG_PWD_YANK"
ZSH_SNIP_DIR="$ORIG_ZSH_SNIP_DIR"
ZSH_SNIP_LOCAL_PATH="$ORIG_ZSH_SNIP_LOCAL_PATH"
rm -rf "$YANK_TEST_DIR"


# =============================================================================
# Tests for _zsh_snip_timing_start / _zsh_snip_timing_end
# =============================================================================
log ""
log "Testing timing helpers..."

# Disabled by default: no output, non-failing.
(
  unset ZSH_SNIP_DEBUG_TIMING
  _zsh_snip_timing_start
  _zsh_snip_timing_end "noop"
) 2>&1 >/dev/null
assert_eq "" "$( (unset ZSH_SNIP_DEBUG_TIMING; _zsh_snip_timing_start; _zsh_snip_timing_end 'noop') 2>&1 )" \
  "timing helpers emit nothing when ZSH_SNIP_DEBUG_TIMING is unset"

# Enabled: emits '[timing] <label>: <N>ms' on stderr with a numeric duration.
timing_output="$( (ZSH_SNIP_DEBUG_TIMING=1; _zsh_snip_timing_start; _zsh_snip_timing_end 'my-label') 2>&1 )"
assert_contains "$timing_output" "[timing] my-label: " \
  "timing end emits the '[timing] <label>: ' prefix when enabled"
[[ "$timing_output" == *": "<->"ms" ]]
assert_eq 0 $? "timing end reports an integer millisecond duration"

# =============================================================================
# Tests for option hardening (emulate -L zsh in entry points)
# =============================================================================
# Entry points must behave identically regardless of the user's global setopts.
# Drive them under hostile options scoped to a subshell so they cannot
# destabilize the rest of this suite.
log ""
log "Testing option hardening under hostile setopts..."

HARDEN_USER_DIR=$(mktemp -d)
HARDEN_PROJECT_DIR=$(mktemp -d)
HARDEN_LOCAL_DIR="$HARDEN_PROJECT_DIR/.zsh-snip"
mkdir -p "$HARDEN_LOCAL_DIR"

HARDEN_ORIG_DIR="$ZSH_SNIP_DIR"
HARDEN_ORIG_LOCAL_PATH="$ZSH_SNIP_LOCAL_PATH"
HARDEN_ORIG_PWD="$PWD"
ZSH_SNIP_DIR="$HARDEN_USER_DIR"
ZSH_SNIP_LOCAL_PATH=".zsh-snip"
cd "$HARDEN_PROJECT_DIR"

print -r -- $'# name: git-status\n# ---\ngit status' > "$HARDEN_USER_DIR/git-status"
# A local override of git-status forces the dedup path (the _enum_seen
# associative-array lookup), which is what breaks under `nounset` without
# emulate -L zsh.
print -r -- $'# name: git-status\n# ---\ngit status --short' > "$HARDEN_LOCAL_DIR/git-status"
print -r -- $'# name: echoer\n# args: <a> <b>\n# ---\necho got "$1" "$2"' > "$HARDEN_USER_DIR/echoer"

# list under hostile options must succeed and enumerate snippets.
harden_rc=0
harden_out=$( setopt nounset ksh_arrays sh_word_split glob_subst
              zsh-snip list --names-only 2>&1 ) || harden_rc=$?
assert_eq 0 "$harden_rc" \
  "test_list_succeeds_under_nounset_ksharrays_shwordsplit_globsubst"
assert_contains "$harden_out" "git-status" \
  "test_list_outputs_snippets_under_hostile_setopts"
assert_contains "$harden_out" "echoer" \
  "test_list_outputs_all_names_under_hostile_setopts"

# exec under hostile options: anonymous-function wrapping and (q) arg expansion
# must run; nounset otherwise trips on the wrapped snippet's $1/$2.
harden_rc=0
harden_out=$( setopt nounset ksh_arrays sh_word_split glob_subst
              zsh-snip exec echoer alpha beta 2>&1 ) || harden_rc=$?
assert_eq 0 "$harden_rc" \
  "test_exec_succeeds_under_hostile_setopts"
assert_contains "$harden_out" "got alpha beta" \
  "test_exec_runs_snippet_with_args_under_hostile_setopts"

# expand under hostile options: content comes out unchanged (local override wins).
harden_rc=0
harden_out=$( setopt nounset ksh_arrays sh_word_split glob_subst
              zsh-snip expand git-status 2>&1 ) || harden_rc=$?
assert_contains "$harden_out" "git status --short" \
  "test_expand_outputs_content_under_hostile_setopts"

# Restore suite state.
ZSH_SNIP_DIR="$HARDEN_ORIG_DIR"
ZSH_SNIP_LOCAL_PATH="$HARDEN_ORIG_LOCAL_PATH"
cd "$HARDEN_ORIG_PWD"
rm -rf "$HARDEN_USER_DIR" "$HARDEN_PROJECT_DIR"

# =============================================================================
# Summary
# =============================================================================
_harness_summary
