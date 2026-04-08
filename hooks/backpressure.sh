#!/bin/bash
# Backpressure hook — compresses verbose command output to preserve context window.
# Swallows passing test/build/lint output; surfaces only failures.
# Inspired by HumanLayer's "context-efficient backpressure" pattern.
#
# Usage in skills: Instead of running `npm test` directly, run:
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Tests" "npm test"
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Build" "npm run build"
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Lint" "npm run lint"
#
# On success: outputs "✓ Tests passed" (~5 tokens)
# On failure: outputs full error details (only what's needed)
#
# Can also be sourced for the run_silent function:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh"
#   run_silent "Tests" "npm test"

run_silent() {
    local description="$1"
    local command="$2"
    local tmp_file
    tmp_file=$(mktemp)

    # Run command, capture all output
    if eval "$command" > "$tmp_file" 2>&1; then
        # Success: extract summary stats if available, otherwise just checkmark
        local line_count
        line_count=$(wc -l < "$tmp_file")

        # Try to extract test count from common frameworks
        local summary=""
        # Jest/Vitest: "Tests: X passed, Y total"
        summary=$(grep -E "Tests?:.*passed|test suites?.*passed" "$tmp_file" | tail -1)
        # pytest: "X passed"
        [ -z "$summary" ] && summary=$(grep -E "^=+ .* passed" "$tmp_file" | tail -1)
        # Go: "ok" lines
        [ -z "$summary" ] && summary=$(grep -c "^ok" "$tmp_file" 2>/dev/null | xargs -I{} echo "{} packages ok")
        # Generic: line count
        [ -z "$summary" ] && summary="${line_count} lines of output"

        printf "✓ %s passed (%s)\n" "$description" "$summary"
        rm -f "$tmp_file"
        return 0
    else
        local exit_code=$?
        printf "✗ %s failed (exit code %d)\n\n" "$description" "$exit_code"

        # Filter output: remove passing test lines, keep failures and errors
        # Common noise patterns to strip:
        grep -v -E "^(PASS |  ✓ |    ✓|  ●|^$|^\s*$)" "$tmp_file" | \
        grep -v -E "^(Test Suites:.*passed|Tests:.*passed|Snapshots:|Time:)" | \
        grep -v -E "^(ok\s+)" | \
        head -150  # Cap at 150 lines to prevent context flooding

        local total_lines
        total_lines=$(wc -l < "$tmp_file")
        if [ "$total_lines" -gt 150 ]; then
            printf "\n... (%d more lines truncated. Run command directly for full output)\n" $((total_lines - 150))
        fi

        rm -f "$tmp_file"
        return $exit_code
    fi
}

# If script is executed directly (not sourced), run the command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: backpressure.sh <description> <command>"
        echo "Example: backpressure.sh 'Unit tests' 'npm test'"
        exit 1
    fi
    run_silent "$1" "$2"
fi
