#!/usr/bin/env bash
# No ad-hoc file sits directly under .geniro/state/.
#
# Run: bash tests/authoring/lint-adhoc-state-files.sh
#
# Placement note: this asserts a live filesystem invariant, not a markdown-
# authoring rule, so `tests/state/` would be the more natural home for it. It
# lives here instead because this fix agent's file allowlist for this audit
# round is `tests/authoring/**` and `tests/run-all.sh` only — `tests/state/`
# does not exist and is out of scope to create. `tests/run-all.sh` discovers
# every `tests/**/*.sh` regardless of subdirectory, so the check runs exactly
# the same either way; a future maintainer with a wider allowlist can move
# this file without changing its behavior.
#
# Why this exists: `skills/_shared/state-tier-spec.md` §"No ad-hoc state files
# under .geniro/state/" names the failure mode — a free-form file dropped
# directly under `.geniro/state/` (e.g. a hand-written
# `ci-201-verification-tracker.md`) "is invisible to `validate_state_file`, to
# the SessionStart restore hook, and to the terminal-exit cleanup contract" —
# but the condition it describes is one a command can just decide, and nothing
# did. The check itself is the fix: none of the four canonical layouts
# (`state/<skill>/<slug>/state.md`, the `state/setup/state.md` singleton,
# `state/handoff/from-<producer>-<branch>.md`, the documented
# `state/tdd/state-<slug>.md` exception) — nor the one documented
# frontmatter-less companion artifact
# (`state/audit-instructions/report-<date>.md`) — ever places a file directly
# at `.geniro/state/<file>`; every one of them nests at least one directory
# level deeper. So the invariant collapses to one `find`: nothing should ever
# be a plain file at that exact depth, full stop — no per-layout logic needed.
#
# `.geniro/state/` is gitignored local runtime data (`.gitignore`'s
# `.geniro/*` line), so a fresh checkout or CI run typically has none at all —
# in which case this check has nothing to verify and reports OK trivially. Its
# real job is the self-test below, which builds its own scratch
# `.geniro/state/`-shaped tree and proves the assertion is correct
# independent of whatever is (or is not) on this machine right now; it also
# runs the same assertion against THIS machine's actual `.geniro/state/`, if
# one exists, as a live bonus check.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# Every file directly at <state_root>/<file> — the one shape no canonical
# layout ever produces.
_adhoc_state_files() {
  find "$1" -maxdepth 1 -type f 2>/dev/null
}

if [ -d ".geniro/state" ]; then
  hits="$(_adhoc_state_files .geniro/state)"
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      report_fail "$h sits directly under .geniro/state/ — not one of the canonical layouts (state/<skill>/<slug>/state.md, state/setup/state.md, state/handoff/from-<producer>-<branch>.md, state/tdd/state-<slug>.md); route it to .geniro/planning/<task-dir>/ instead"
    done <<< "$hits"
  else
    echo "OK: no ad-hoc file directly under this machine's .geniro/state/"
  fi
else
  echo "OK: no .geniro/state/ directory present on this machine — nothing to check"
fi

# --- self-test: red on a seeded ad-hoc file, silent across all four ---------
# canonical layouts plus the documented companion-artifact shape -------------
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
STATE="$SELFTEST_DIR/.geniro/state"

mkdir -p "$STATE/debug/feature-x-slug"
: > "$STATE/debug/feature-x-slug/state.md"                       # layout 1: <skill>/<slug>/state.md
mkdir -p "$STATE/setup"
: > "$STATE/setup/state.md"                                      # layout 2: singleton
mkdir -p "$STATE/handoff"
: > "$STATE/handoff/from-review-feature-x.md"                    # layout 3: handoff
mkdir -p "$STATE/tdd"
: > "$STATE/tdd/state-feature-x-slug.md"                          # layout 4: TDD exception
mkdir -p "$STATE/audit-instructions"
: > "$STATE/audit-instructions/report-2026-08-10.md"              # documented companion artifact

clean_hits="$(_adhoc_state_files "$STATE")"
if [ -z "$clean_hits" ]; then
  echo "OK: self-test — all four canonical layouts plus the companion artifact stay silent"
else
  report_fail "self-test — a canonical-layout fixture false-positived: $(printf '%s' "$clean_hits" | tr '\n' ' ')"
fi

: > "$STATE/ci-201-verification-tracker.md"                       # the seeded ad-hoc violation
violation_hits="$(_adhoc_state_files "$STATE")"
if printf '%s\n' "$violation_hits" | grep -q 'ci-201-verification-tracker.md'; then
  echo "OK: self-test — a seeded ad-hoc file directly under state/ is detected"
else
  report_fail "self-test — seeded ad-hoc violation was NOT detected"
fi
# Only the one seeded file should be flagged — the four layouts and the
# companion artifact must not regress once the violation is added alongside them.
violation_count=$(printf '%s\n' "$violation_hits" | grep -c . || true)
if [ "$violation_count" -eq 1 ]; then
  echo "OK: self-test — exactly the seeded file is flagged, none of the canonical fixtures alongside it"
else
  report_fail "self-test — expected exactly 1 flagged file, got $violation_count: $(printf '%s' "$violation_hits" | tr '\n' ' ')"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS ad-hoc .geniro/state/ file problem(s)." >&2
  exit 1
fi
echo "OK: no ad-hoc file sits directly under .geniro/state/."
