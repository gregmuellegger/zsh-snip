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
