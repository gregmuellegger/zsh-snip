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

# Exit code is governed by the assertion counters (see summary at the bottom):
# the suite exits non-zero iff at least one assertion failed. No `set -e`, so a
# non-zero setup command never aborts the run before the summary prints.
setopt EXTENDED_GLOB

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

# =============================================================================
# Test Framework
# =============================================================================

# Shared assertion helpers, counters, QUIET/color handling, and summary/exit.
source "${SCRIPT_DIR}/lib/harness.zsh"

TEST_DIR=""

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
    export EDITOR="$TEST_DIR/bin/mock_editor"

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
# Test: User save reports the "Saved:" confirmation with the user dir path
# =============================================================================
test_save_reports_user_saved_message() {
    log ""
    log "Testing: User save reports 'Saved:' confirmation message..."
    setup_test_env

    BUFFER="docker run -it ubuntu"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    local msg=$(get_last_message)
    assert_eq "Saved: $ZSH_SNIP_DIR/docker-1" "$msg" "user save reports 'Saved:' with user path"

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
# Test: Editor rename with path traversal is rejected (B7)
# =============================================================================
test_editor_rename_rejects_path_traversal() {
    log ""
    log "Testing: Editor rename rejects path-traversal name (B7)..."
    setup_test_env

    # Editor rewrites the name field to an escaping path
    cat > "$TEST_DIR/traversal_editor.sh" <<'SCRIPT'
filepath="$1"
sed -i 's|^# name: docker-1$|# name: ../../evil|' "$filepath"
SCRIPT
    chmod +x "$TEST_DIR/traversal_editor.sh"
    export MOCK_EDITOR_SCRIPT="$TEST_DIR/traversal_editor.sh"

    BUFFER="docker ps"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    # File must stay put, not escape the snippet dir
    assert_file_exists "$ZSH_SNIP_DIR/docker-1" "traversal name keeps original file"
    assert_file_not_exists "$TEST_DIR/evil" "traversal name did not escape snippet dir"

    # Error is surfaced via zle -M (B8), not a swallowed echo
    local msg=$(get_last_message)
    assert_contains "$msg" "invalid name" "traversal rename shows invalid-name message"

    teardown_test_env
}

# =============================================================================
# Test: Editor rename collision keeps original and warns (B8)
# =============================================================================
test_editor_rename_collision_keeps_original() {
    log ""
    log "Testing: Editor rename collision keeps original file (B8)..."
    setup_test_env

    # A snippet named "taken" already exists
    create_test_snippet "taken" "Existing snippet" "echo existing"

    # Editor renames the freshly saved docker-1 to the taken name
    cat > "$TEST_DIR/collision_editor.sh" <<'SCRIPT'
filepath="$1"
sed -i 's|^# name: docker-1$|# name: taken|' "$filepath"
SCRIPT
    chmod +x "$TEST_DIR/collision_editor.sh"
    export MOCK_EDITOR_SCRIPT="$TEST_DIR/collision_editor.sh"

    BUFFER="docker ps"
    CURSOR=${#BUFFER}

    _zsh_snip_save

    # Original snippet stays as docker-1; the existing "taken" is untouched
    assert_file_exists "$ZSH_SNIP_DIR/docker-1" "collision keeps original file name"
    assert_eq "echo existing" "$(_zsh_snip_read_command "$ZSH_SNIP_DIR/taken")" \
        "collision does not overwrite existing target"

    # Error surfaced via zle -M (B8)
    local msg=$(get_last_message)
    assert_contains "$msg" "already exists" "collision rename shows already-exists message"

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
# Test: Local save reports the "Saved (local):" confirmation with local path
# =============================================================================
test_save_local_reports_local_saved_message() {
    log ""
    log "Testing: Local save reports 'Saved (local):' confirmation message..."
    setup_test_env

    local orig_dir="$PWD"
    cd "$TEST_DIR/project"

    BUFFER="make build"
    CURSOR=${#BUFFER}

    _zsh_snip_save_local

    cd "$orig_dir"

    local msg=$(get_last_message)
    assert_eq "Saved (local): $TEST_DIR/project/.zsh-snip/make-1" "$msg" "local save reports 'Saved (local):' with local path"

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
    local new_name=$(_zsh_snip_duplicate_name "$ZSH_SNIP_DIR" "docker-1")
    assert_eq "docker-2" "$new_name" "generates correct duplicate name"

    # Create docker-2 and test again
    create_test_snippet "docker-2" "Second docker" "docker run redis"
    new_name=$(_zsh_snip_duplicate_name "$ZSH_SNIP_DIR" "docker-1")
    assert_eq "docker-3" "$new_name" "skips existing files"

    teardown_test_env
}

# =============================================================================
# Test: CTRL-N duplication preserves args: and abbr: header fields (B3)
# =============================================================================
test_duplicate_preserves_args_and_abbr_headers() {
    log ""
    log "Testing: CTRL-N duplication preserves args/abbr headers..."
    setup_test_env

    # Create a snippet with args: and abbr: header fields plus an extra comment
    cat > "$ZSH_SNIP_DIR/deploy-1" <<'EOF'
#!/usr/bin/env zsh
# name: deploy-1
# description: Deploy to a host
# args: <host> [port]
# abbr: dep dpl
# created: 2024-01-01T00:00:00+00:00
# ---
ssh "$1" "deploy --port ${2:-22}"
EOF

    # fzf returns ctrl-n on the snippet; the ctrl-n handler breaks the loop
    export MOCK_FZF_OUTPUT="deploy\nctrl-n\n~ deploy-1\tDeploy to a host\tssh...\t$ZSH_SNIP_DIR/deploy-1"

    _zsh_snip_search

    # Duplicate should be deploy-2 and preserve all header fields
    assert_file_exists "$ZSH_SNIP_DIR/deploy-2" "duplicate file created"

    local dup_content=$(cat "$ZSH_SNIP_DIR/deploy-2")
    assert_contains "$dup_content" "# name: deploy-2" "duplicate has updated name"
    assert_contains "$dup_content" "# args: <host> [port]" "duplicate preserves args header"
    assert_contains "$dup_content" "# abbr: dep dpl" "duplicate preserves abbr header"
    assert_contains "$dup_content" "#!/usr/bin/env zsh" "duplicate preserves shebang"

    # Original must be untouched
    local orig_content=$(cat "$ZSH_SNIP_DIR/deploy-1")
    assert_contains "$orig_content" "# name: deploy-1" "original name unchanged"

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
# Test: Search with CTRL-Y yanks to clipboard
# =============================================================================
test_search_ctrl_y_yanks_to_clipboard() {
    log ""
    log "Testing: Search with CTRL-Y yanks snippet to clipboard..."
    setup_test_env

    create_test_snippet "yank-me" "Test yank" "echo 'yanked content'"

    # Set up mock clipboard command
    export YANK_CAPTURE_FILE="$TEST_DIR/logs/yanked_content"
    cat > "$TEST_DIR/bin/mock-clipboard" <<CLIP
#!/bin/bash
cat > "$TEST_DIR/logs/yanked_content"
CLIP
    chmod +x "$TEST_DIR/bin/mock-clipboard"
    export ZSH_SNIP_YANK_CMD="$TEST_DIR/bin/mock-clipboard"

    export MOCK_FZF_OUTPUT="yank\nctrl-y\n~ yank-me\tTest yank\techo 'yanked content'\t$ZSH_SNIP_DIR/yank-me"

    BUFFER=""
    CURSOR=0

    _zsh_snip_search

    # Verify content was yanked
    local yanked=$(cat "$TEST_DIR/logs/yanked_content" 2>/dev/null)
    assert_eq "echo 'yanked content'" "$yanked" "snippet content was yanked to clipboard"

    # Verify buffer was not modified
    assert_eq "" "$BUFFER" "buffer remains unchanged after yank"

    # Verify message was shown
    local msg=$(get_last_message)
    assert_contains "$msg" "Copied" "shows copied message"

    teardown_test_env
}

# =============================================================================
# Test: CTRL-Y not shown when clipboard unavailable
# =============================================================================
test_search_ctrl_y_hidden_when_no_clipboard() {
    log ""
    log "Testing: CTRL-Y hint hidden when no clipboard available..."
    setup_test_env

    create_test_snippet "test-snip" "Test" "echo test"

    # Disable clipboard
    export ZSH_SNIP_YANK_CMD=""

    # We need a more sophisticated mock fzf to capture the header
    cat > "$TEST_DIR/bin/fzf" <<FZF
#!/bin/bash
# Capture all arguments for inspection
echo "\$*" > "$TEST_DIR/logs/fzf_args.log"
# Read input
cat > "$TEST_DIR/logs/fzf_input.log"
# Return empty (cancelled)
echo ""
echo ""
echo ""
FZF
    chmod +x "$TEST_DIR/bin/fzf"

    _zsh_snip_search

    # Check fzf args don't include ctrl-y
    local fzf_args=$(cat "$TEST_DIR/logs/fzf_args.log" 2>/dev/null)
    [[ "$fzf_args" != *"ctrl-y"* ]]
    assert_eq 0 $? "ctrl-y not in fzf expect list when clipboard unavailable"

    teardown_test_env
}

# =============================================================================
# Test: fzf list format (tab-delimited, columns aligned)
# =============================================================================
# Characterizes the exact list string piped to fzf so the column-padding
# implementation stays byte-compatible with fzf's --delimiter/--with-nth.
test_search_fzf_list_is_tab_aligned() {
    log ""
    log "Testing: fzf list is tab-delimited and column-aligned..."
    setup_test_env

    # Deterministic width: 80 cols -> desc_width 20, cmd_width 30
    export COLUMNS=80

    # A short and a long name so name-column padding actually matters.
    create_test_snippet "longnamehere" "a longer description" "echo long"
    create_test_snippet "s" "short desc" "echo short"

    # Empty fzf output = user cancels; we only care about the captured input.
    export MOCK_FZF_OUTPUT=""

    _zsh_snip_search

    local logcontent="$(cat "$TEST_DIR/logs/fzf_input.log")"
    local -a lines=("${(f)logcontent}")

    # Locate the two rows (glob order sorts longnamehere before s).
    local short_line="" long_line=""
    local line field1
    for line in "${lines[@]}"; do
        field1="${line%%$'\t'*}"
        [[ "$field1" == "~ s"* ]] && short_line="$line"
        [[ "$field1" == "~ longnamehere"* ]] && long_line="$line"
    done

    # Each record must have exactly 4 tab-separated fields (3 tabs).
    local short_tabs="${short_line//[^$'\t']/}"
    assert_eq 3 ${#short_tabs} "record has 4 tab-separated fields"

    # Name column is padded to the widest name (~ longnamehere = 14 chars).
    local short_f1="${short_line%%$'\t'*}"
    local long_f1="${long_line%%$'\t'*}"
    assert_eq "~ s           " "$short_f1" "short name padded to name-column width"
    assert_eq "~ longnamehere" "$long_f1" "widest name defines the column width"
    assert_eq ${#long_f1} ${#short_f1} "name columns aligned to equal width"

    # Description column padded to widest description (20 chars).
    local short_rest="${short_line#*$'\t'}"
    local short_f2="${short_rest%%$'\t'*}"
    assert_eq "short desc          " "$short_f2" "description padded to desc-column width"

    # Last field is the unpadded full path.
    local short_f4="${short_line##*$'\t'}"
    assert_eq "$ZSH_SNIP_DIR/s" "$short_f4" "last field is the full path, unpadded"

    unset COLUMNS
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
test_save_reports_user_saved_message
test_save_extracts_trailing_comment
test_save_uses_name_from_comment
test_editor_rename_moves_file
test_editor_rename_rejects_path_traversal
test_editor_rename_collision_keeps_original
test_search_enter_replaces_buffer
test_search_ctrl_i_inserts_at_cursor
test_search_ctrl_e_opens_editor
test_search_ctrl_d_deletes_snippet
test_search_alt_x_wraps_function
test_save_local_creates_in_project
test_save_local_reports_local_saved_message
test_duplicate_snippet
test_duplicate_preserves_args_and_abbr_headers
test_subdirectory_snippets
test_empty_buffer_rejected
test_snippet_with_args_header
test_search_ctrl_y_yanks_to_clipboard
test_search_ctrl_y_hidden_when_no_clipboard
test_search_fzf_list_is_tab_aligned

# =============================================================================
# Summary
# =============================================================================
_harness_summary "Integration Tests Summary"
