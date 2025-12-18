#!/usr/bin/env zsh
# Tests for zsh-snip

set -e

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

# Source the plugin (but skip keybinding setup by mocking zle/bindkey)
function zle() { :; }
function bindkey() { :; }
source "$PROJECT_DIR/zsh-snip.plugin.zsh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  TESTS_RUN=$((TESTS_RUN + 1))

  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
  fi
}

# =============================================================================
# Tests for _zsh_snip_extract_command
# =============================================================================
echo "Testing _zsh_snip_extract_command..."

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
echo ""
echo "Testing _zsh_snip_next_id..."

# Create a temp directory for testing
TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

assert_eq "1" "$(_zsh_snip_next_id 'git')" \
  "returns 1 for new command with no existing snippets"

# Create some test files
touch "$TEST_SNIP_DIR/git-1"
touch "$TEST_SNIP_DIR/git-2"
touch "$TEST_SNIP_DIR/git-5"

assert_eq "6" "$(_zsh_snip_next_id 'git')" \
  "returns max+1 for existing snippets"

assert_eq "1" "$(_zsh_snip_next_id 'docker')" \
  "returns 1 for command with no existing snippets (other snippets exist)"

# Test with non-numeric suffix (should be ignored)
touch "$TEST_SNIP_DIR/git-foo"

assert_eq "6" "$(_zsh_snip_next_id 'git')" \
  "ignores non-numeric suffixes"

# Cleanup temp directory
rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_write and _zsh_snip_read_command
# =============================================================================
echo ""
echo "Testing _zsh_snip_write and _zsh_snip_read_command..."

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

# Test writing to subdirectory (e.g., git/add)
_zsh_snip_write "$TEST_SNIP_DIR/git/add" "git/add" "stage files" "git add ."
read_cmd=$(_zsh_snip_read_command "$TEST_SNIP_DIR/git/add")
assert_eq "git add ." "$read_cmd" \
  "creates parent directory and writes snippet to subdirectory"

# Cleanup
rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_extract_trailing_comment
# =============================================================================
echo ""
echo "Testing _zsh_snip_extract_trailing_comment..."

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
echo ""
echo "Testing _zsh_snip_extract_trailing_name..."

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
echo ""
echo "Testing _zsh_snip_slugify..."

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
echo ""
echo "Testing _zsh_snip_read_command_preview..."

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
echo ""
echo "Testing _zsh_snip_insert_at_cursor..."

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
echo ""
echo "Testing _zsh_snip_duplicate_name..."

TEST_SNIP_DIR=$(mktemp -d)
ZSH_SNIP_DIR="$TEST_SNIP_DIR"

# Test basic duplication (docker-1 → docker-2)
touch "$TEST_SNIP_DIR/docker-1"
assert_eq "docker-2" "$(_zsh_snip_duplicate_name 'docker-1')" \
  "increments numeric suffix"

# Test when next number already exists (docker-1 with docker-2 existing → docker-3)
touch "$TEST_SNIP_DIR/docker-2"
assert_eq "docker-3" "$(_zsh_snip_duplicate_name 'docker-1')" \
  "skips existing files to find next available"

# Test name without numeric suffix (node-shell → node-shell-1)
assert_eq "node-shell-1" "$(_zsh_snip_duplicate_name 'node-shell')" \
  "appends -1 to name without numeric suffix"

# Test subdirectory (git/status-1 → git/status-2)
mkdir -p "$TEST_SNIP_DIR/git"
touch "$TEST_SNIP_DIR/git/status-1"
assert_eq "git/status-2" "$(_zsh_snip_duplicate_name 'git/status-1')" \
  "handles subdirectory paths"

rm -rf "$TEST_SNIP_DIR"


# =============================================================================
# Tests for _zsh_snip_wrap_anon_func
# =============================================================================
echo ""
echo "Testing _zsh_snip_wrap_anon_func..."

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
echo ""
echo "Testing _zsh_snip_find_local_dir..."

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
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "Tests run: $TESTS_RUN"
echo "Passed:    $TESTS_PASSED"
echo "Failed:    $TESTS_FAILED"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
  exit 1
fi
