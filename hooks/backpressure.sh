#!/usr/bin/env bash
# Backpressure hook — compresses verbose command output to preserve context window.
# Swallows passing test/build/lint output; surfaces only failures.
# Inspired by HumanLayer's "context-efficient backpressure" pattern.
#
# Usage in skills: Instead of running `npm test` directly, run:
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Tests" "npm test"
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Build" "npm run build"
#   bash "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" "Lint" "npm run lint"
#
# On success: outputs "✓ <description> passed (<summary>)" where <summary> is a
#   detected framework test count or "<N> lines of output".
# On failure: outputs full error details (only what's needed), capped at
#   GENIRO_BACKPRESSURE_CAP lines (default 150).
#
# Can also be sourced for the run_silent function:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh"
#   run_silent "Tests" "npm test"

run_silent() {
    local description="$1"
    local command="$2"
    local tmp_file
    tmp_file=$(mktemp) || { echo "backpressure: mktemp failed" >&2; return 1; }
    # A SIGINT/SIGTERM while the wrapped command runs skips every `rm -f` below
    # and leaks the capture file into $TMPDIR. Bash traps are not function-scoped,
    # so this one is cleared on both return paths (and self-clears when it fires)
    # rather than lingering in a caller that sourced this function and clobbering
    # its own INT trap — the same discipline lib/update-semantic.sh applies.
    trap 'rm -f "$tmp_file"; trap - INT TERM' INT TERM
    local output_cap="${GENIRO_BACKPRESSURE_CAP:-150}"
    # A non-numeric or <1 cap would make `head -"$output_cap"` diverge across platforms:
    # GNU `head -0` prints nothing and exits 0, but BSD/macOS `head -0` errors. Fall back
    # to the documented default so the suppress branch behaves identically on both.
    case "$output_cap" in ''|*[!0-9]*) output_cap=150 ;; esac
    [ "$output_cap" -lt 1 ] && output_cap=150

    # Run command in a subshell, capture all output. The subshell is load-bearing:
    # this function is often sourced into the caller's shell, and a wrapped command
    # that calls `exit` would otherwise terminate the caller before the failure
    # branch runs (losing the error output and leaking tmp_file).
    if ( eval "$command" ) > "$tmp_file" 2>&1; then
        # Success: extract summary stats if available, otherwise just checkmark
        local line_count
        # `tr -d ' '` strips the leading-space padding BSD `wc` emits on macOS,
        # which would otherwise leak into the "N lines of output" summary string.
        line_count=$(wc -l < "$tmp_file" | tr -d ' ')

        # Try to extract test count from common frameworks
        local summary=""
        # Jest/Vitest: "Tests: X passed, Y total"
        summary=$(grep -E "Tests?:.*passed|test suites?.*passed" "$tmp_file" | tail -1)
        # pytest: "X passed"
        [ -z "$summary" ] && summary=$(grep -E "^=+ .* passed" "$tmp_file" | tail -1)
        # Go: count "ok" package lines — only when there is at least one, so a
        # non-Go run falls through to the generic line-count summary below
        # instead of always reporting "0 packages ok".
        if [ -z "$summary" ]; then
            local ok_count
            ok_count=$(grep -c "^ok" "$tmp_file" 2>/dev/null)
            [ "${ok_count:-0}" -gt 0 ] && summary="$ok_count packages ok"
        fi
        # Generic: line count
        [ -z "$summary" ] && summary="${line_count} lines of output"

        printf "✓ %s passed (%s)\n" "$description" "$summary"
        rm -f "$tmp_file"
        trap - INT TERM
        return 0
    else
        local exit_code=$?
        printf "✗ %s failed (exit code %d)\n\n" "$description" "$exit_code"

        # Filter output: remove passing test lines, keep failures and errors
        # Common noise patterns to strip:
        grep -v -E "^(PASS |  ✓ |    ✓|  ●|^$|^[[:space:]]*$)" "$tmp_file" | \
        grep -v -E "^(Test Suites:.*passed|Tests:.*passed|Snapshots:|Time:)" | \
        grep -v -E "^(ok[[:space:]]+)" | \
        head -"$output_cap"  # Cap output to prevent context flooding

        local total_lines
        total_lines=$(wc -l < "$tmp_file" | tr -d ' ')
        if [ "$total_lines" -gt "$output_cap" ]; then
            printf "\n... (%d more lines truncated. Run command directly for full output)\n" $((total_lines - output_cap))
        fi

        rm -f "$tmp_file"
        trap - INT TERM
        return $exit_code
    fi
}

# If script is executed directly (not sourced), run the command
# `${BASH_SOURCE[0]:-}` — the header above documents sourcing this file, and a
# `set -u` shell where BASH_SOURCE is unset (zsh, or bash reading from stdin)
# would abort the whole source on the bare expansion.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [ $# -lt 2 ]; then
        echo "Usage: backpressure.sh <description> <command>"
        echo "Example: backpressure.sh 'Unit tests' 'npm test'"
        exit 1
    fi
    run_silent "$1" "$2"
fi
