#!/usr/bin/env zsh
# Meta-tests for tests/lib/harness.zsh output behavior.
#
# The harness must be quiet by default (only failures and the summary print)
# and fully verbose when the suite is invoked with -v/--verbose or QUIET=0.
#
# Run: zsh tests/test_harness.zsh
# Verbose: zsh tests/test_harness.zsh -v

SCRIPT_DIR="${0:A:h}"
HARNESS="$SCRIPT_DIR/lib/harness.zsh"

source "$HARNESS"

# =============================================================================
# Fixtures: minimal suites sourcing the real harness, run as subprocesses.
# `env -u QUIET` keeps an exported QUIET from this process out of the fixture.
# =============================================================================

FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$FIXTURE_DIR/passing_suite.zsh" <<EOF
source "$HARNESS"
log "SECTION HEADER LINE"
assert_eq a a "passing assertion message"
_harness_summary "Fixture Summary"
EOF

cat > "$FIXTURE_DIR/failing_suite.zsh" <<EOF
source "$HARNESS"
log "SECTION HEADER LINE"
assert_eq a b "failing assertion message"
_harness_summary "Fixture Summary"
EOF

run_fixture() { env -u QUIET zsh "$@" 2>&1 }

# assert_eq-based negative check: harness has no assert_not_contains.
contains() { [[ "$1" == *"$2"* ]] && echo yes || echo no }

# =============================================================================
# Default mode: only failures and the summary
# =============================================================================
log "Testing default (quiet) mode..."

output=$(run_fixture "$FIXTURE_DIR/passing_suite.zsh")
assert_eq "no" "$(contains "$output" "passing assertion message")" \
  "default run hides passing assertion lines"
assert_eq "no" "$(contains "$output" "SECTION HEADER LINE")" \
  "default run hides log/section lines"
assert_contains "$output" "Tests run: 1" \
  "default run still prints the summary"

output=$(run_fixture "$FIXTURE_DIR/failing_suite.zsh")
assert_contains "$output" "failing assertion message" \
  "default run still prints failing assertions"
assert_contains "$output" "expected: 'a'" \
  "default run still prints failure details"

run_fixture "$FIXTURE_DIR/passing_suite.zsh" >/dev/null
assert_eq "0" "$?" "passing fixture exits 0 in default mode"

run_fixture "$FIXTURE_DIR/failing_suite.zsh" >/dev/null
assert_eq "1" "$?" "failing fixture exits 1 in default mode"

# =============================================================================
# Verbose mode: -v / --verbose flag, QUIET=0 env
# =============================================================================
log ""
log "Testing verbose mode..."

output=$(run_fixture "$FIXTURE_DIR/passing_suite.zsh" -v)
assert_contains "$output" "passing assertion message" \
  "-v shows passing assertion lines"
assert_contains "$output" "SECTION HEADER LINE" \
  "-v shows log/section lines"

output=$(run_fixture "$FIXTURE_DIR/passing_suite.zsh" --verbose)
assert_contains "$output" "passing assertion message" \
  "--verbose shows passing assertion lines"

output=$(QUIET=0 zsh "$FIXTURE_DIR/passing_suite.zsh" 2>&1)
assert_contains "$output" "passing assertion message" \
  "QUIET=0 env still forces verbose output"

output=$(QUIET=1 zsh "$FIXTURE_DIR/passing_suite.zsh" -v 2>&1)
assert_eq "no" "$(contains "$output" "passing assertion message")" \
  "explicit QUIET=1 env wins over -v"

_harness_summary "Harness Meta-Tests Summary"
