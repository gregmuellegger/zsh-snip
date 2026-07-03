# Shared test harness for the zsh-snip suites.
#
# Provides the assertion helpers, pass/fail/skip counters, QUIET handling,
# TTY-aware color output, and a summary/exit function used by all three suites
# (unit, integration, e2e). Each suite sources this file near the top:
#
#   source "${0:A:h}/lib/harness.zsh"
#
# Counters (TESTS_RUN/TESTS_PASSED/TESTS_FAILED) and the assert function names
# match what the suite bodies already use, so sourcing this changes no test.
# Suite-specific setup (temp dirs, mock fzf, tmux helpers, plugin sourcing)
# stays in each suite.

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Quiet by default: only failures and the summary print. Invoking a suite with
# -v/--verbose (or QUIET=0) shows all output; an explicit QUIET env var wins
# over the flag. `$@` here is the sourcing suite's argv, since the suites
# source this file without arguments.
if [[ -z "${QUIET:-}" ]]; then
  QUIET=1
  for _harness_arg in "$@"; do
    [[ "$_harness_arg" == "-v" || "$_harness_arg" == "--verbose" ]] && QUIET=0
  done
  unset _harness_arg
fi

# Log function that respects QUIET mode
log() { [[ "$QUIET" != "1" ]] && echo "$@"; return 0; }

# Colors: enabled only when stdout is a real terminal and NO_COLOR is unset, so
# piping to `tail`/CI (non-TTY) never emits raw escape codes. Empty strings
# otherwise, which keeps every "${GREEN}...${RESET}" interpolation harmless.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\e[31m'
  GREEN=$'\e[32m'
  YELLOW=$'\e[33m'
  BLUE=$'\e[34m'
  RESET=$'\e[0m'
else
  RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

# =============================================================================
# Assertion helpers
# =============================================================================

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
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

# Record a skipped test. Increments TESTS_SKIPPED, which the summary prints when
# the sourcing suite has declared it.
skip_test() {
  local msg="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_SKIPPED=$((${TESTS_SKIPPED:-0} + 1))
  log "  ${YELLOW}⊘${RESET} $msg (skipped)"
}

# =============================================================================
# Summary + exit
# =============================================================================

# Print the totals and exit with a code governed by TESTS_FAILED (non-zero iff
# at least one assertion failed). Optional $1 is a title shown between rules.
# The "Skipped" line appears only when the suite tracks TESTS_SKIPPED.
_harness_summary() {
  local title="$1"
  log ""
  echo "=========================================="
  if [[ -n "$title" ]]; then
    echo "$title"
    echo "=========================================="
  fi
  echo "Tests run: $TESTS_RUN"
  echo "Passed:    ${GREEN}$TESTS_PASSED${RESET}"
  echo "Failed:    ${RED}$TESTS_FAILED${RESET}"
  (( ${+TESTS_SKIPPED} )) && echo "Skipped:   ${YELLOW}$TESTS_SKIPPED${RESET}"
  echo "=========================================="

  [[ $TESTS_FAILED -gt 0 ]] && exit 1
  exit 0
}
