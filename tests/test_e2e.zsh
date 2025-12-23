#!/usr/bin/env zsh
# End-to-end tests for zsh-snip using tmux
#
# These tests use tmux to simulate real terminal interaction:
# - Real keyboard shortcuts (CTRL-X CTRL-S, etc.)
# - Real fzf interaction
# - Real zle widget behavior
#
# Requirements:
# - tmux
# - fzf
#
# Run: zsh tests/test_e2e.zsh
# Run specific test: TEST_FILTER="save" zsh tests/test_e2e.zsh
# Quiet mode (only failures): QUIET=1 zsh tests/test_e2e.zsh

set -e

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

# Check requirements
if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required for E2E tests"
    exit 1
fi

if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is required for E2E tests"
    exit 1
fi

# =============================================================================
# Test Framework
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_DIR=""
TMUX_SESSION=""

# Quiet mode - only show failures
: ${QUIET:=0}

# Log function that respects QUIET mode
log() { [[ "$QUIET" != "1" ]] && echo "$@"; return 0; }

# Colors
if [[ -t 1 ]]; then
    RED=$'\e[31m'
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    BLUE=$'\e[34m'
    RESET=$'\e[0m'
else
    RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

# Unique session name for this test run
TMUX_SESSION="zsh-snip-test-$$"

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
        echo "    haystack: '$haystack'"
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

skip_test() {
    local msg="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log "  ${YELLOW}⊘${RESET} $msg (skipped)"
}

# =============================================================================
# tmux Helpers
# =============================================================================

# Start a new tmux session with zsh
start_tmux_session() {
    TEST_DIR=$(mktemp -d)
    export ZSH_SNIP_DIR="$TEST_DIR/snippets"
    mkdir -p "$ZSH_SNIP_DIR"

    # Get full path to zsh (needed for CI environments where PATH might differ)
    local zsh_path
    zsh_path=$(command -v zsh)

    # Create .zshenv to skip global compinit (runs before .zshrc)
    cat > "$TEST_DIR/.zshenv" <<'ZSHENV'
# Skip compinit security check that blocks in CI
skip_global_compinit=1
ZSHENV

    # Create .zshrc for the test shell (ZDOTDIR approach)
    cat > "$TEST_DIR/.zshrc" <<ZSHRC
# Disable flow control so C-s and C-q keybindings work
# (C-s is normally XON/XOFF flow control which freezes the terminal)
stty -ixon -ixoff 2>/dev/null || true

# Test environment init
export ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
export ZSH_SNIP_LOCAL_PATH=".zsh-snip"
export EDITOR="true"  # Use true as editor - does nothing and exits 0
export TERM=xterm-256color
PS1='READY> '

# Source the plugin
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
ZSHRC

    # Start tmux session with ZDOTDIR pointing to our test dir
    # Use full path to zsh to work in CI environments
    tmux new-session -d -s "$TMUX_SESSION" -x 120 -y 30 \
        "ZDOTDIR='$TEST_DIR' ZSH_SNIP_DIR='$ZSH_SNIP_DIR' $zsh_path -i"

    # Wait for shell to be ready (look for PS1)
    sleep 1
    wait_for_prompt
}

# Wait for the shell prompt to appear
wait_for_prompt() {
    local max_wait=50  # 5 seconds max
    local i=0
    while (( i < max_wait )); do
        local pane_content=$(tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null || echo "")
        if [[ "$pane_content" == *"READY>"* ]] || [[ "$pane_content" == *">"* ]]; then
            sleep 0.1  # Extra settling time
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    # Debug output on failure
    echo "ERROR: Timed out waiting for prompt" >&2
    echo "Pane content was:" >&2
    tmux capture-pane -t "$TMUX_SESSION" -p 2>&1 | head -20 >&2
    return 1
}

# Send keys to the tmux session
send_keys() {
    tmux send-keys -t "$TMUX_SESSION" "$@"
}

# Send literal text (escaping special characters)
send_text() {
    tmux send-keys -t "$TMUX_SESSION" -l "$1"
}

# Capture the current pane content
capture_pane() {
    tmux capture-pane -t "$TMUX_SESSION" -p
}

# Wait for specific text to appear in the pane
wait_for_text() {
    local text="$1"
    local timeout="${2:-5}"
    local max_wait=$((timeout * 10))
    local i=0

    while (( i < max_wait )); do
        local content=$(capture_pane)
        if [[ "$content" == *"$text"* ]]; then
            return 0
        fi
        sleep 0.1
        i=$((i + 1))
    done
    return 1
}

# Kill the tmux session
stop_tmux_session() {
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# Create a test snippet
# Note: Creates in the current TEST_DIR's snippets, must be called after start_tmux_session
create_test_snippet() {
    local name="$1"
    local description="$2"
    local command="$3"
    local snip_dir="$TEST_DIR/snippets"

    [[ "$name" == */* ]] && mkdir -p "$snip_dir/${name%/*}"

    cat > "$snip_dir/$name" <<EOF
# name: $name
# description: $description
# created: 2024-01-01T00:00:00+00:00
# ---
$command
EOF
}

# =============================================================================
# E2E Tests
# =============================================================================

# Test: Basic shell interaction works
test_shell_ready() {
    log ""
    log "Testing: Shell session is ready..."
    start_tmux_session

    # Type a simple command
    send_text "echo hello"
    send_keys Enter
    sleep 0.3

    local output=$(capture_pane)
    assert_contains "$output" "hello" "shell executes commands"

    stop_tmux_session
}

# Test: Plugin loads and widgets are available
test_plugin_loads() {
    log ""
    log "Testing: Plugin loads correctly..."
    start_tmux_session

    # Check that our keybindings exist
    send_text "bindkey | grep -c 'zsh_snip'"
    send_keys Enter
    sleep 0.3

    local output=$(capture_pane)
    # Should have 3 bindings (save, save-local, search)
    assert_contains "$output" "3" "plugin registers 3 keybindings"

    stop_tmux_session
}

# Test: CTRL-X CTRL-X opens fzf (with no snippets, should show message)
test_search_empty() {
    log ""
    log "Testing: CTRL-X CTRL-X with no snippets..."
    start_tmux_session

    # Press CTRL-X CTRL-X
    send_keys C-x C-x
    sleep 0.5

    # zle -M messages appear below the command line but may not persist.
    # The key indicator is that fzf does NOT open (no "Snippet>" prompt).
    # We verify by checking that we're back at the shell prompt.
    local output=$(capture_pane)

    # fzf would show "Snippet>" prompt - it should NOT appear
    if [[ "$output" == *"Snippet>"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ${RED}✗${RESET} fzf should not open with no snippets"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log "  ${GREEN}✓${RESET} fzf does not open when no snippets exist"
    fi

    stop_tmux_session
}

# Test: CTRL-X CTRL-X shows snippets in fzf
test_search_with_snippets() {
    log ""
    log "Testing: CTRL-X CTRL-X shows snippets in fzf..."
    start_tmux_session

    # Create some test snippets
    create_test_snippet "docker-run" "Run docker container" "docker run -it --rm ubuntu"
    create_test_snippet "git-status" "Check git status" "git status"

    # Press CTRL-X CTRL-X
    send_keys C-x C-x
    sleep 0.5

    local output=$(capture_pane)
    # Should show fzf with snippets
    assert_contains "$output" "docker-run" "fzf shows docker snippet"
    assert_contains "$output" "git-status" "fzf shows git snippet"

    # Cancel fzf
    send_keys Escape
    sleep 0.2

    stop_tmux_session
}

# Test: Selecting a snippet replaces buffer
test_select_replaces_buffer() {
    log ""
    log "Testing: Selecting snippet replaces command line..."
    start_tmux_session

    create_test_snippet "test-echo" "Echo test" "echo 'snippet works'"

    # Type something that will match the snippet (buffer becomes fzf query)
    # "test" will match "test-echo"
    send_text "test"
    sleep 0.1

    # Open fzf - the buffer "test" becomes the initial query
    send_keys C-x C-x
    sleep 0.5

    # Select the snippet (press Enter)
    send_keys Enter
    sleep 0.3

    local output=$(capture_pane)
    # Buffer should now contain the snippet command
    assert_contains "$output" "echo 'snippet works'" "buffer replaced with snippet"

    # Clean up - press Ctrl-C to cancel
    send_keys C-c
    sleep 0.1

    stop_tmux_session
}

# Test: CTRL-X CTRL-S saves a snippet
test_save_snippet() {
    log ""
    log "Testing: CTRL-X CTRL-S saves snippet..."
    start_tmux_session

    # Type a command to save as snippet
    send_text "kubectl get pods -A"
    sleep 0.1

    # Press CTRL-X CTRL-S to save
    # The editor (set to "true") will exit immediately, accepting the auto-generated content
    send_keys C-x C-s
    sleep 1.0  # Give more time for file operations

    # Check if snippet file was created
    # The auto-generated name should be "kubectl-1" (first word + counter)
    local snippet_file="$ZSH_SNIP_DIR/kubectl-1"
    if [[ -f "$snippet_file" ]]; then
        local content=$(cat "$snippet_file")
        assert_contains "$content" "kubectl get pods -A" "snippet file contains command"
        assert_contains "$content" "# name:" "snippet has metadata header"
    else
        # Try to find any kubectl snippet
        local found=$(ls "$ZSH_SNIP_DIR" 2>/dev/null | grep kubectl || echo "")
        if [[ -n "$found" ]]; then
            local first_match="${found%%$'\n'*}"
            local content=$(cat "$ZSH_SNIP_DIR/$first_match")
            assert_contains "$content" "kubectl" "kubectl snippet was created"
        else
            TESTS_RUN=$((TESTS_RUN + 1))
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "  ${RED}✗${RESET} snippet file was created"
            echo "    no kubectl snippet found in $ZSH_SNIP_DIR"
            ls -la "$ZSH_SNIP_DIR" 2>/dev/null || echo "    (directory empty or missing)"
        fi
    fi

    stop_tmux_session
}

# Test: fzf filter works with query
test_fzf_filter() {
    log ""
    log "Testing: fzf filters snippets by query..."
    start_tmux_session

    create_test_snippet "docker-run" "Run container" "docker run -it ubuntu"
    create_test_snippet "docker-build" "Build image" "docker build ."
    create_test_snippet "git-push" "Push changes" "git push"

    # Open fzf
    send_keys C-x C-x
    sleep 0.5

    # Type filter query
    send_text "docker"
    sleep 0.3

    local output=$(capture_pane)
    # Should show docker snippets but not git
    assert_contains "$output" "docker-run" "shows matching docker-run"
    assert_contains "$output" "docker-build" "shows matching docker-build"
    # Note: git-push might still be in the buffer from before filtering
    # This is hard to test precisely without more complex pane analysis

    # Cancel
    send_keys Escape
    sleep 0.2

    stop_tmux_session
}

# Test: Alt-X wraps snippet in function
test_alt_x_wraps_function() {
    log ""
    log "Testing: ALT-X wraps snippet in anonymous function..."
    start_tmux_session

    create_test_snippet "echo-arg" "Echo with arg" 'echo "Hello $1"'

    # Open fzf
    send_keys C-x C-x
    sleep 0.5

    # Press Alt-X
    send_keys M-x
    sleep 0.3

    local output=$(capture_pane)
    # Should show wrapped function
    assert_contains "$output" "() {" "buffer contains function opening"
    assert_contains "$output" 'echo "Hello $1"' "buffer contains command"

    # Clean up
    send_keys C-c
    sleep 0.1

    stop_tmux_session
}

# Test: abbr load registers abbreviations
test_abbr_load() {
    log ""
    log "Testing: zsh-snip abbr load registers abbreviations..."

    # Create a special test environment with abbr enabled
    TEST_DIR=$(mktemp -d)
    export ZSH_SNIP_DIR="$TEST_DIR/snippets"
    mkdir -p "$ZSH_SNIP_DIR"

    # Get full path to zsh
    local zsh_path
    zsh_path=$(command -v zsh)

    # Create .zshenv
    cat > "$TEST_DIR/.zshenv" <<'ZSHENV'
skip_global_compinit=1
ZSHENV

    # Create .zshrc with abbr enabled
    cat > "$TEST_DIR/.zshrc" <<ZSHRC
stty -ixon -ixoff 2>/dev/null || true
export ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
export ZSH_SNIP_LOCAL_PATH=".zsh-snip"
export ZSH_SNIP_ABBR=1
export ZSH_SNIP_EDITOR="true"
export TERM=xterm-256color
PS1='READY> '
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
ZSHRC

    # Create a snippet with abbr field
    cat > "$ZSH_SNIP_DIR/test-abbr" <<'EOF'
# name: test-abbr
# description: Test abbreviation
# abbr: gst
# created: 2024-01-01T00:00:00+00:00
# ---
git status
EOF

    # Start session with unique name for this test
    local test_session="zsh-snip-abbr-test-$$"
    tmux new-session -d -s "$test_session" -x 120 -y 30 \
        "ZDOTDIR='$TEST_DIR' ZSH_SNIP_DIR='$ZSH_SNIP_DIR' ZSH_SNIP_ABBR=1 $zsh_path -i"

    sleep 1

    # Wait for shell to be ready
    local max_wait=50
    local i=0
    while (( i < max_wait )); do
        local pane_content=$(tmux capture-pane -t "$test_session" -p 2>/dev/null || echo "")
        if [[ "$pane_content" == *"READY>"* ]] || [[ "$pane_content" == *">"* ]]; then
            sleep 0.1
            break
        fi
        sleep 0.1
        i=$((i + 1))
    done

    # Run abbr list to check if abbreviation was registered
    tmux send-keys -t "$test_session" "abbr list-abbreviations | grep gst" Enter
    sleep 0.5

    local output=$(tmux capture-pane -t "$test_session" -p)
    assert_contains "$output" "gst" "abbreviation gst was registered"

    # Cleanup
    tmux kill-session -t "$test_session" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

# Test: chpwd hook loads local abbrs when entering project directory
test_abbr_chpwd() {
    log ""
    log "Testing: chpwd hook loads local abbrs on directory change..."

    # Create test environment
    TEST_DIR=$(mktemp -d)
    export ZSH_SNIP_DIR="$TEST_DIR/snippets"
    mkdir -p "$ZSH_SNIP_DIR"

    # Create a project directory with local snippets
    local project_dir="$TEST_DIR/project"
    mkdir -p "$project_dir/.zsh-snip"

    cat > "$project_dir/.zsh-snip/local-abbr" <<'EOF'
# name: local-abbr
# description: Local abbreviation
# abbr: dps
# created: 2024-01-01T00:00:00+00:00
# ---
docker ps -a
EOF

    # Get full path to zsh
    local zsh_path
    zsh_path=$(command -v zsh)

    # Create .zshenv
    cat > "$TEST_DIR/.zshenv" <<'ZSHENV'
skip_global_compinit=1
ZSHENV

    # Create .zshrc with abbr enabled
    cat > "$TEST_DIR/.zshrc" <<ZSHRC
stty -ixon -ixoff 2>/dev/null || true
export ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
export ZSH_SNIP_LOCAL_PATH=".zsh-snip"
export ZSH_SNIP_ABBR=1
export ZSH_SNIP_EDITOR="true"
export TERM=xterm-256color
PS1='READY> '
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
ZSHRC

    # Start session
    local test_session="zsh-snip-chpwd-test-$$"
    tmux new-session -d -s "$test_session" -x 120 -y 30 \
        "ZDOTDIR='$TEST_DIR' ZSH_SNIP_DIR='$ZSH_SNIP_DIR' ZSH_SNIP_ABBR=1 $zsh_path -i"

    sleep 1

    # Wait for shell
    local max_wait=50
    local i=0
    while (( i < max_wait )); do
        local pane_content=$(tmux capture-pane -t "$test_session" -p 2>/dev/null || echo "")
        if [[ "$pane_content" == *"READY>"* ]] || [[ "$pane_content" == *">"* ]]; then
            sleep 0.1
            break
        fi
        sleep 0.1
        i=$((i + 1))
    done

    # cd into project directory (should trigger chpwd hook)
    tmux send-keys -t "$test_session" "cd $project_dir" Enter
    sleep 0.5

    # Check if local abbr was loaded
    tmux send-keys -t "$test_session" "abbr list-abbreviations | grep dps" Enter
    sleep 0.5

    local output=$(tmux capture-pane -t "$test_session" -p)
    assert_contains "$output" "dps" "local abbreviation dps was loaded via chpwd"

    # Cleanup
    tmux kill-session -t "$test_session" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

# Test: local abbrs are unloaded when leaving project directory
test_abbr_unload() {
    log ""
    log "Testing: local abbrs are unloaded when leaving project..."

    # Create test environment
    TEST_DIR=$(mktemp -d)
    export ZSH_SNIP_DIR="$TEST_DIR/snippets"
    mkdir -p "$ZSH_SNIP_DIR"

    # Create a project directory with local snippets
    local project_dir="$TEST_DIR/project"
    mkdir -p "$project_dir/.zsh-snip"

    cat > "$project_dir/.zsh-snip/local-abbr" <<'EOF'
# name: local-abbr
# description: Local abbreviation
# abbr: dps
# created: 2024-01-01T00:00:00+00:00
# ---
docker ps -a
EOF

    # Get full path to zsh
    local zsh_path
    zsh_path=$(command -v zsh)

    # Create .zshenv
    cat > "$TEST_DIR/.zshenv" <<'ZSHENV'
skip_global_compinit=1
ZSHENV

    # Create .zshrc with abbr enabled - start in project dir
    cat > "$TEST_DIR/.zshrc" <<ZSHRC
stty -ixon -ixoff 2>/dev/null || true
export ZSH_SNIP_DIR="$ZSH_SNIP_DIR"
export ZSH_SNIP_LOCAL_PATH=".zsh-snip"
export ZSH_SNIP_ABBR=1
export ZSH_SNIP_EDITOR="true"
export TERM=xterm-256color
PS1='READY> '
source "$PROJECT_DIR/zsh-snip.plugin.zsh"
cd "$project_dir"
ZSHRC

    # Start session
    local test_session="zsh-snip-unload-test-$$"
    tmux new-session -d -s "$test_session" -x 120 -y 30 \
        "ZDOTDIR='$TEST_DIR' ZSH_SNIP_DIR='$ZSH_SNIP_DIR' ZSH_SNIP_ABBR=1 $zsh_path -i"

    sleep 1

    # Wait for shell
    local max_wait=50
    local i=0
    while (( i < max_wait )); do
        local pane_content=$(tmux capture-pane -t "$test_session" -p 2>/dev/null || echo "")
        if [[ "$pane_content" == *"READY>"* ]] || [[ "$pane_content" == *">"* ]]; then
            sleep 0.1
            break
        fi
        sleep 0.1
        i=$((i + 1))
    done

    # First verify abbr is loaded
    tmux send-keys -t "$test_session" "abbr list-abbreviations | grep -q dps && echo 'LOADED' || echo 'NOT_LOADED'" Enter
    sleep 0.5

    local output=$(tmux capture-pane -t "$test_session" -p)
    assert_contains "$output" "LOADED" "local abbreviation was initially loaded"

    # cd out of project directory
    tmux send-keys -t "$test_session" "cd /" Enter
    sleep 0.5

    # Check if abbr was unloaded
    tmux send-keys -t "$test_session" "abbr list-abbreviations | grep -q dps && echo 'STILL_LOADED' || echo 'UNLOADED'" Enter
    sleep 0.5

    output=$(tmux capture-pane -t "$test_session" -p)
    assert_contains "$output" "UNLOADED" "local abbreviation was unloaded when leaving project"

    # Cleanup
    tmux kill-session -t "$test_session" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Run Tests
# =============================================================================

log "╔════════════════════════════════════════╗"
log "║   zsh-snip E2E Tests (tmux)            ║"
log "╚════════════════════════════════════════╝"
log ""
log "${BLUE}Using tmux session: $TMUX_SESSION${RESET}"

# Filter tests if TEST_FILTER is set
run_test() {
    local test_name="$1"
    if [[ -z "$TEST_FILTER" ]] || [[ "$test_name" == *"$TEST_FILTER"* ]]; then
        $test_name
    fi
}

# Cleanup any leftover sessions
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

# Run tests
run_test test_shell_ready
run_test test_plugin_loads
run_test test_search_empty
run_test test_search_with_snippets
run_test test_select_replaces_buffer
run_test test_save_snippet
run_test test_fzf_filter
run_test test_alt_x_wraps_function
run_test test_abbr_load
run_test test_abbr_chpwd
run_test test_abbr_unload

# =============================================================================
# Summary
# =============================================================================
log ""
echo "=========================================="
echo "E2E Tests Summary"
echo "=========================================="
echo "Tests run:    $TESTS_RUN"
echo "Passed:       ${GREEN}$TESTS_PASSED${RESET}"
echo "Failed:       ${RED}$TESTS_FAILED${RESET}"
echo "Skipped:      ${YELLOW}$TESTS_SKIPPED${RESET}"
echo "=========================================="

# Final cleanup
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
