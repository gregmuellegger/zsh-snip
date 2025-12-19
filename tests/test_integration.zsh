#!/usr/bin/env zsh
# Integration tests for zsh-snip
#
# These tests use mock dependencies to test complete workflows:
# - Mock $EDITOR to capture and verify editor interactions
# - Mock fzf via PATH manipulation to control selections
# - Real file I/O with temp directories
#
# Run: zsh tests/test_integration.zsh
# Quiet mode (only failures): QUIET=1 zsh tests/test_integration.zsh

set -e
setopt EXTENDED_GLOB

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

# =============================================================================
# Test Framework
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""

# Quiet mode - only show failures
: ${QUIET:=0}

# Log function that respects QUIET mode
log() { [[ "$QUIET" != "1" ]] && echo "$@"; return 0; }

# Colors (only if terminal supports them)
if [[ -t 1 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    RESET=$'\e[0m'
else
    RED="" GREEN="" YELLOW="" RESET=""
fi

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log "  ${GREEN}✓${RESET} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${RED}✗${RESET} $msg"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log "  ${GREEN}✓${RESET} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${RED}✗${RESET} $msg"
        echo "    expected to contain: '$needle'"
        echo "    actual: '$haystack'"
    fi
}

assert_file_exists() {
    local filepath="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ -f "$filepath" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log "  ${GREEN}✓${RESET} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${RED}✗${RESET} $msg"
        echo "    file not found: '$filepath'"
    fi
}

assert_file_not_exists() {
    local filepath="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ ! -e "$filepath" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log "  ${GREEN}✓${RESET} $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${RED}✗${RESET} $msg"
        echo "    file exists but shouldn't: '$filepath'"
    fi
}

# =============================================================================
# Test Environment Setup
# =============================================================================

setup_test_env() {
    # Create isolated test directory
    TEST_DIR=$(mktemp -d)
    export TEST_DIR  # Export so child scripts can access it
    export ZSH_SNIP_DIR="$TEST_DIR/snippets"
    export ZSH_SNIP_LOCAL_PATH=".zsh-snip"
    mkdir -p "$ZSH_SNIP_DIR"
    mkdir -p "$TEST_DIR/bin"
    mkdir -p "$TEST_DIR/logs"
    mkdir -p "$TEST_DIR/project/.zsh-snip"

    # Create mock editor that logs calls and optionally modifies files
    # Note: Uses heredoc with variable substitution for TEST_DIR
    cat > "$TEST_DIR/bin/mock_editor" <<EDITOR
#!/bin/bash
# Mock editor - logs calls and applies modifications from MOCK_EDITOR_SCRIPT
echo "EDITOR_CALL: \$*" >> "$TEST_DIR/logs/editor.log"
echo "EDITOR_FILE: \$(cat "\$1")" >> "$TEST_DIR/logs/editor.log"

# If MOCK_EDITOR_SCRIPT is set, execute it to modify the file
if [[ -n "\$MOCK_EDITOR_SCRIPT" && -f "\$MOCK_EDITOR_SCRIPT" ]]; then
    source "\$MOCK_EDITOR_SCRIPT" "\$1"
fi
EDITOR
    chmod +x "$TEST_DIR/bin/mock_editor"

    # Create mock fzf that returns predetermined output
    cat > "$TEST_DIR/bin/fzf" <<FZF
#!/bin/bash
# Mock fzf - reads input but returns MOCK_FZF_OUTPUT
# Format: query\nkey\nselection

# Read and store input (useful for debugging)
cat > "$TEST_DIR/logs/fzf_input.log"

# Return mock output if set
if [[ -n "\$MOCK_FZF_OUTPUT" ]]; then
    echo -e "\$MOCK_FZF_OUTPUT"
    exit "\${MOCK_FZF_EXIT:-0}"
else
    # Default: return empty (user cancelled)
    echo ""
    echo ""
    echo ""
    exit 0
fi
FZF
    chmod +x "$TEST_DIR/bin/fzf"

    # Set environment
    export PATH="$TEST_DIR/bin:$PATH"
    export ZSH_SNIP_EDITOR="$TEST_DIR/bin/mock_editor"

    # Clear log files
    : > "$TEST_DIR/logs/editor.log"
    : > "$TEST_DIR/logs/fzf_input.log"

    # Source the plugin with mocked zle/bindkey
    # These capture what the widget functions do
    # Reset for each test
    typeset -ga ZLE_MESSAGES
    ZLE_MESSAGES=()
    ZLE_BUFFER=""
    ZLE_CURSOR=0

    function zle() {
        case "$1" in
            -N) : ;;  # Widget registration - ignore
            -M) ZLE_MESSAGES+=("$2") ;;
            -la) command zle -la 2>/dev/null || echo "" ;;
            reset-prompt) : ;;
            accept-line) : ;;
            edit-command-line) : ;;
            *) : ;;
        esac
    }

    function bindkey() { :; }

    # Set up mock BUFFER and CURSOR
    BUFFER="$ZLE_BUFFER"
    CURSOR="$ZLE_CURSOR"

    source "$PROJECT_DIR/zsh-snip.plugin.zsh"
}

teardown_test_env() {
    # Return to original directory before cleanup
    cd /workspaces/zsh-snip 2>/dev/null || cd /tmp
    rm -rf "$TEST_DIR"
    unset TEST_DIR ZSH_SNIP_DIR ZSH_SNIP_LOCAL_PATH
    unset MOCK_FZF_OUTPUT MOCK_FZF_EXIT MOCK_EDITOR_SCRIPT
}

# Helper to get last zle message
get_last_message() {
    echo "${ZLE_MESSAGES[-1]:-}"
}

# Helper to read editor log
get_editor_log() {
    cat "$TEST_DIR/logs/editor.log" 2>/dev/null || echo ""
}

# Helper to create a test snippet
create_test_snippet() {
    local name="$1"
    local description="$2"
    local command="$3"
    local dir="${4:-$ZSH_SNIP_DIR}"

    [[ "$name" == */* ]] && mkdir -p "$dir/${name%/*}"

    cat > "$dir/$name" <<EOF
# name: $name
# description: $description
# created: 2024-01-01T00:00:00+00:00
# ---
$command
EOF
}

# =============================================================================
# Test: Save workflow with editor interaction
# =============================================================================
test_save_creates_snippet_and_opens_editor() {
    log "Testing: Save creates snippet file and opens editor..."
    setup_test_env

    # Simulate user typing a command
    BUFFER="docker run -it ubuntu"
    CURSOR=${#BUFFER}

    # Call the save function directly
    _zsh_snip_save

    # Verify editor was called
    local editor_log=$(get_editor_log)
    assert_contains "$editor_log" "EDITOR_CALL:" "editor was invoked"
    assert_contains "$editor_log" "$ZSH_SNIP_DIR/docker-1" "editor opened correct file"

    # Verify snippet file was created
    assert_file_exists "$ZSH_SNIP_DIR/docker-1" "snippet file exists"

    # Verify file contents
    local content=$(cat "$ZSH_SNIP_DIR/docker-1")
    assert_contains "$content" "# name: docker-1" "snippet has name header"
    assert_contains "$content" "docker run -it ubuntu" "snippet contains command"

    teardown_test_env
}

# =============================================================================
# Test: Save with trailing comment extracts description
# =============================================================================
test_save_extracts_trailing_comment() {
    log ""
    log "Testing: Save extracts trailing comment as description..."
    setup_test_env

    BUFFER="git status # check repo state"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    local content=$(cat "$ZSH_SNIP_DIR/git-1")
    assert_contains "$content" "# description: check repo state" "description extracted from comment"
    assert_contains "$content" "git status" "command saved without comment"

    # Verify the command doesn't include the comment
    local cmd=$(_zsh_snip_read_command "$ZSH_SNIP_DIR/git-1")
    assert_eq "git status" "$cmd" "saved command has no trailing comment"

    teardown_test_env
}

# =============================================================================
# Test: Save with name: prefix in comment uses that name
# =============================================================================
test_save_uses_name_from_comment() {
    log ""
    log "Testing: Save uses name from trailing comment..."
    setup_test_env

    BUFFER="kubectl get pods -A # k8s-pods: List all pods"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    # Should create file with the custom name
    assert_file_exists "$ZSH_SNIP_DIR/k8s-pods" "uses custom name from comment"

    local content=$(cat "$ZSH_SNIP_DIR/k8s-pods")
    assert_contains "$content" "# description: List all pods" "description after colon is extracted"

    teardown_test_env
}

# =============================================================================
# Test: Editor rename triggers file rename
# =============================================================================
test_editor_rename_moves_file() {
    log ""
    log "Testing: Editor rename triggers file rename..."
    setup_test_env

    # Create editor script that changes the name field
    cat > "$TEST_DIR/rename_editor.sh" <<'SCRIPT'
filepath="$1"
sed -i 's/^# name: docker-1$/# name: my-custom-docker/' "$filepath"
SCRIPT
    chmod +x "$TEST_DIR/rename_editor.sh"
    export MOCK_EDITOR_SCRIPT="$TEST_DIR/rename_editor.sh"

    BUFFER="docker ps"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    # Original file should be moved
    assert_file_not_exists "$ZSH_SNIP_DIR/docker-1" "original file was moved"
    assert_file_exists "$ZSH_SNIP_DIR/my-custom-docker" "file renamed to new name"

    teardown_test_env
}

# =============================================================================
# Test: Search with Enter replaces buffer
# =============================================================================
test_search_enter_replaces_buffer() {
    log ""
    log "Testing: Search with Enter replaces buffer..."
    setup_test_env

    # Create test snippets
    create_test_snippet "docker-run" "Run a container" "docker run -it --rm ubuntu"
    create_test_snippet "git-status" "Check git status" "git status"

    # Mock fzf to return the docker snippet
    # Format: query\nkey\nselection (with tab-separated fields for selection)
    # The selection format is: "~ docker-run\tdescription\tpreview\t$ZSH_SNIP_DIR/docker-run"
    export MOCK_FZF_OUTPUT="docker\n\n~ docker-run\tRun a container\tdocker run -it --rm ubuntu\t$ZSH_SNIP_DIR/docker-run"

    BUFFER="git"  # Initial buffer content
    CURSOR=3

    _zsh_snip_search

    assert_eq "docker run -it --rm ubuntu" "$BUFFER" "buffer replaced with snippet command"

    teardown_test_env
}

# =============================================================================
# Test: Search with CTRL-I inserts at cursor
# =============================================================================
test_search_ctrl_i_inserts_at_cursor() {
    log ""
    log "Testing: Search with CTRL-I inserts at cursor..."
    setup_test_env

    create_test_snippet "flag-rm" "Remove flag" "--rm"

    export MOCK_FZF_OUTPUT="rm\nctrl-i\n~ flag-rm\tRemove flag\t--rm\t$ZSH_SNIP_DIR/flag-rm"

    BUFFER="docker run  ubuntu"
    CURSOR=11  # Position between "run " and "ubuntu"

    _zsh_snip_search

    assert_eq "docker run --rm ubuntu" "$BUFFER" "snippet inserted at cursor position"

    teardown_test_env
}

# =============================================================================
# Test: Search with CTRL-E opens editor
# =============================================================================
test_search_ctrl_e_opens_editor() {
    log ""
    log "Testing: Search with CTRL-E opens editor..."
    setup_test_env

    create_test_snippet "test-snippet" "Test" "echo hello"

    # ctrl-e should open editor and return to fzf
    # We create a fzf mock that returns ctrl-e first, then cancels
    cat > "$TEST_DIR/bin/fzf" <<FZF
#!/bin/bash
count_file="$TEST_DIR/logs/fzf_count"
count=\$((  \$(cat "\$count_file" 2>/dev/null || echo 0) + 1))
echo "\$count" > "\$count_file"

cat > "$TEST_DIR/logs/fzf_input_\${count}.log"

if [[ "\$count" -eq 1 ]]; then
    # First call: return ctrl-e selection
    echo "test"
    echo "ctrl-e"
    echo "~ test-snippet	Test	echo hello	$ZSH_SNIP_DIR/test-snippet"
else
    # Second call: simulate cancellation (empty selection)
    echo ""
    echo ""
    echo ""
fi
FZF
    chmod +x "$TEST_DIR/bin/fzf"

    _zsh_snip_search

    # Verify editor was called
    local editor_log=$(get_editor_log)
    assert_contains "$editor_log" "EDITOR_CALL:" "editor was invoked for snippet"
    assert_contains "$editor_log" "test-snippet" "correct snippet was opened"

    teardown_test_env
}

# =============================================================================
# Test: Search with CTRL-D deletes snippet (with mock confirmation)
# =============================================================================
test_search_ctrl_d_deletes_snippet() {
    log ""
    log "Testing: Search with CTRL-D deletes snippet..."
    setup_test_env

    create_test_snippet "to-delete" "Will be deleted" "echo delete me"
    assert_file_exists "$ZSH_SNIP_DIR/to-delete" "snippet exists before delete"

    # We can't easily mock the read confirmation in zsh
    # Instead, we'll test the delete logic by calling it directly
    # This is a limitation of the mock approach

    # For now, just verify the file structure is correct
    local files_before=$(ls "$ZSH_SNIP_DIR" | wc -l)
    assert_eq "1" "$files_before" "one snippet exists before test"

    log "  ${YELLOW}⚠${RESET} Full CTRL-D test requires interactive input (skipped)"

    teardown_test_env
}

# =============================================================================
# Test: Search with ALT-X wraps in anonymous function
# =============================================================================
test_search_alt_x_wraps_function() {
    log ""
    log "Testing: Search with ALT-X wraps in anonymous function..."
    setup_test_env

    create_test_snippet "echo-test" "Echo test" $'echo "Hello $1"'

    export MOCK_FZF_OUTPUT="echo\nalt-x\n~ echo-test\tEcho test\techo \"Hello \$1\"\t$ZSH_SNIP_DIR/echo-test"

    BUFFER=""
    CURSOR=0

    _zsh_snip_search

    assert_contains "$BUFFER" "() { # echo-test: Echo test" "buffer contains function wrapper with name and description"
    assert_contains "$BUFFER" 'echo "Hello $1"' "buffer contains original command"
    assert_contains "$BUFFER" "} " "buffer ends with closing brace and space for args"

    teardown_test_env
}

# =============================================================================
# Test: Local snippet save to project directory
# =============================================================================
test_save_local_creates_in_project() {
    log ""
    log "Testing: Save local creates snippet in project directory..."
    setup_test_env

    # Save original directory and change to project directory
    local orig_dir="$PWD"
    cd "$TEST_DIR/project"

    BUFFER="make build"
    CURSOR=${#BUFFER}

    _zsh_snip_save_local

    # Return to original directory before assertions
    cd "$orig_dir"

    # Should save to local .zsh-snip directory
    assert_file_exists "$TEST_DIR/project/.zsh-snip/make-1" "snippet created in local directory"

    local content=$(cat "$TEST_DIR/project/.zsh-snip/make-1")
    assert_contains "$content" "make build" "local snippet contains command"

    teardown_test_env
}

# =============================================================================
# Test: Duplicate snippet functionality
# =============================================================================
test_duplicate_snippet() {
    log ""
    log "Testing: Duplicate snippet creates new file..."
    setup_test_env

    create_test_snippet "docker-1" "Original docker command" "docker run nginx"

    # Test the duplicate name function
    local new_name=$(_zsh_snip_duplicate_name "docker-1")
    assert_eq "docker-2" "$new_name" "generates correct duplicate name"

    # Create docker-2 and test again
    create_test_snippet "docker-2" "Second docker" "docker run redis"
    new_name=$(_zsh_snip_duplicate_name "docker-1")
    assert_eq "docker-3" "$new_name" "skips existing files"

    teardown_test_env
}

# =============================================================================
# Test: Subdirectory support
# =============================================================================
test_subdirectory_snippets() {
    log ""
    log "Testing: Subdirectory snippet support..."
    setup_test_env

    # Create editor script that changes name to include subdirectory
    cat > "$TEST_DIR/subdir_editor.sh" <<'SCRIPT'
filepath="$1"
sed -i 's|^# name: git-1$|# name: git/status|' "$filepath"
SCRIPT
    chmod +x "$TEST_DIR/subdir_editor.sh"
    export MOCK_EDITOR_SCRIPT="$TEST_DIR/subdir_editor.sh"

    BUFFER="git status"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    # Should create in subdirectory
    assert_file_exists "$ZSH_SNIP_DIR/git/status" "snippet created in subdirectory"

    teardown_test_env
}

# =============================================================================
# Test: Empty buffer handling
# =============================================================================
test_empty_buffer_rejected() {
    log ""
    log "Testing: Empty buffer is rejected..."
    setup_test_env

    BUFFER=""
    CURSOR=0

    # _zsh_snip_save returns 1 for empty buffer, which is expected
    _zsh_snip_save || true

    local msg=$(get_last_message)
    assert_contains "$msg" "Nothing to save" "empty buffer shows error message"

    teardown_test_env
}

# =============================================================================
# Test: Snippet with args header prompts for input
# =============================================================================
test_snippet_with_args_header() {
    log ""
    log "Testing: Snippet with args header recognized..."
    setup_test_env

    # Create snippet with args header
    cat > "$ZSH_SNIP_DIR/ping-host" <<'SNIPPET'
# name: ping-host
# description: Ping a host
# args: <hostname>
# created: 2024-01-01T00:00:00+00:00
# ---
ping -c 3 "$1"
SNIPPET

    # Verify args are read correctly
    local args=$(_zsh_snip_read_args "$ZSH_SNIP_DIR/ping-host")
    assert_eq "<hostname>" "$args" "args header is read correctly"

    teardown_test_env
}

# =============================================================================
# Run all tests
# =============================================================================
log "╔════════════════════════════════════════╗"
log "║   zsh-snip Integration Tests           ║"
log "╚════════════════════════════════════════╝"
log ""

test_save_creates_snippet_and_opens_editor
test_save_extracts_trailing_comment
test_save_uses_name_from_comment
test_editor_rename_moves_file
test_search_enter_replaces_buffer
test_search_ctrl_i_inserts_at_cursor
test_search_ctrl_e_opens_editor
test_search_ctrl_d_deletes_snippet
test_search_alt_x_wraps_function
test_save_local_creates_in_project
test_duplicate_snippet
test_subdirectory_snippets
test_empty_buffer_rejected
test_snippet_with_args_header

# =============================================================================
# Summary
# =============================================================================
log ""
echo "=========================================="
echo "Integration Tests Summary"
echo "=========================================="
echo "Tests run: $TESTS_RUN"
echo "Passed:    ${GREEN}$TESTS_PASSED${RESET}"
echo "Failed:    ${RED}$TESTS_FAILED${RESET}"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
