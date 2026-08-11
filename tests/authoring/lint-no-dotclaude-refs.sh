#!/usr/bin/env bash
# No shipped skills/** or agents/* file cites a .claude/skills/ or .claude/rules/
# path that exists only in THIS repo's own dev tree.
#
# Run: bash tests/authoring/lint-no-dotclaude-refs.sh
#
# Why this exists: `.claude/skills/` and `.claude/rules/` in this repo's own
# working tree hold plugin-maintenance-only content (audit-plugin,
# improve-template, and this repo's own authoring rules) — none of it ships to
# a consumer install. `skills/**` and `agents/*` DO ship. A shipped file naming
# one of THIS repo's own `.claude/` files as something to read sends a
# consumer session to a path that does not exist for them.
# `lint-skills.sh` cannot see this class: its dangling-reference check (§2)
# validates only `${CLAUDE_PLUGIN_ROOT}/...`-rooted paths, so a bare
# `.claude/...` mention never reaches it.
#
# What makes this decidable without false-positiving on the LEGITIMATE
# `.claude/rules/` and `.claude/skills/` mentions in this corpus — and there
# are dozens, because `.claude/rules/` and `.claude/skills/**/SKILL.md` are
# also the GENERIC, real location in ANY consumer's OWN project (used by
# /geniro:reflect routing a rule there, /geniro:audit-instructions describing
# what it scans, etc.) — is existence, not shape. A bare directory mention
# (`.claude/rules/`) or a glob (`.claude/skills/**/SKILL.md`) never resolves as
# a literal file and is skipped by construction (the character class below
# excludes `*`). An illustrative example filename that happens not to exist in
# THIS repo either (`.claude/rules/api-testing.md`, used as a worked example of
# what a CONSUMER project's file would look like) resolves to nothing here and
# is correctly silent. Only a citation naming a path that DOES exist under
# THIS repo's own `.claude/` tree is the defect: that is the one shape that can
# only be true because the author was looking at their own working tree, not
# because they were describing a consumer's.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# `<file>:<line>\t<token>` for every literal (non-glob) `.claude/skills/...` or
# `.claude/rules/...` file path cited in a shipped file.
_dotclaude_refs() {
  grep -rnoE '\.claude/(skills|rules)/[A-Za-z0-9._/-]+\.(md|json|sh)' "$@" 2>/dev/null
}

checked=0
while IFS=: read -r f l tok; do
  [ -n "${tok:-}" ] || continue
  checked=$((checked + 1))
  if [ -f "$tok" ]; then
    report_fail "$f:$l cites $tok — that path exists only in this repo's own dev tree, absent from every consumer install"
  fi
done < <(_dotclaude_refs skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no shipped skills/** or agents/* file cites a real .claude/skills/ or .claude/rules/ path ($checked candidate reference(s) checked)"
fi

# --- self-test: red on a seeded existing-path citation, silent on the two ----
# real false-positive shapes this corpus actually carries -------------------
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared" "$SELFTEST_DIR/.claude/skills/probe-only"
printf '# probe\n' > "$SELFTEST_DIR/.claude/skills/probe-only/SKILL.md"

cat > "$SELFTEST_DIR/skills/_shared/violation.md" <<'EOF'
See `.claude/skills/probe-only/SKILL.md` for the fix agents.
EOF
cat > "$SELFTEST_DIR/skills/_shared/clean.md" <<'EOF'
Route a new rule to your project's `.claude/rules/api-testing.md`.
Read every `.claude/skills/**/SKILL.md` in the target repo.
Put project rules under `.claude/rules/`.
EOF

# The existence test (`[ -f "$tok" ]`) must run in the SAME cwd the paths were
# extracted relative to, so the whole extract-and-test pipeline stays inside
# one `cd` subshell — splitting it across a subshell boundary would resolve
# `$tok` back against $REPO_ROOT and silently test the wrong tree.
n_violation=$(cd "$SELFTEST_DIR" && _dotclaude_refs skills | while IFS=: read -r f l tok; do
  [ -n "${tok:-}" ] || continue
  [ -f "$tok" ] && echo hit
done | grep -c . || true)
if [ "$n_violation" -ge 1 ]; then
  echo "OK: self-test — a citation of a real .claude/skills/ file is detected"
else
  report_fail "self-test — seeded violation was NOT detected"
fi

n_clean=$(cd "$SELFTEST_DIR" && _dotclaude_refs skills | while IFS=: read -r f l tok; do
  [ -n "${tok:-}" ] || continue
  # Leading `(` on the pattern is required, not style: bash 3.2 cannot parse a
  # one-line `case ... ;; esac` inside a `$( )` — the unbalanced `)` terminates
  # the substitution for its parser. macOS ships 3.2, so CI fails there and
  # nowhere else. `tests/authoring/bash32-parse.sh` now covers tests/ for this.
  case "$f" in (*clean.md) [ -f "$tok" ] && echo hit ;; esac
done | grep -c . || true)
if [ "$n_clean" -eq 0 ]; then
  echo "OK: self-test — an illustrative example path and a glob do not false-positive"
else
  report_fail "self-test — the illustrative-example / glob fixture false-positived ($n_clean hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS shipped-file .claude/ reference problem(s)." >&2
  exit 1
fi
echo "OK: every .claude/ path cited from a shipped file either does not exist here or is a glob/example."
