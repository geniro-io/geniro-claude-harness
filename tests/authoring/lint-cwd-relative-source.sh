#!/usr/bin/env bash
# C2 (plugin-audit 2026-09-23, fix-plan §O / T2-2) — no skills/ or agents/ body
# sources a `lib/` helper with a cwd-relative path.
#
# Run: bash tests/authoring/lint-cwd-relative-source.sh
#
# Why this exists: `source lib/emit-learning.sh` resolves against the
# CONSUMER's own working directory in an installed plugin, where `lib/` does
# not exist — only `source "${CLAUDE_PLUGIN_ROOT}/lib/<helper>.sh"` (or the
# `$PLUGIN_PATH/lib/` form `/geniro:update` uses pre-marketplace-fetch)
# resolves in a real install. T2-2: eight `_shared/*.md` API blocks shipped
# the cwd-relative form verbatim as the literal command to run.
#
# Detection: `source` (or POSIX `.`) followed by an optionally-quoted `lib/`
# path, NOT preceded on the same match by `${CLAUDE_PLUGIN_ROOT}/` or
# `$PLUGIN_PATH/` — those two rooted spellings are the only ones that resolve
# in a consumer install and must stay silent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

# <dirs...> -> file:line:match for every cwd-relative `source lib/...` (or
# `. lib/...`) hit. A rooted citation never matches: after "source " the next
# characters are `${CLAUDE_PLUGIN_ROOT}` / `$PLUGIN_PATH`, not `lib/` or
# `"lib/`, so the pattern below cannot land on it.
_cwd_relative_source() {
  grep -rnoE '(^|[^A-Za-z0-9_/.$-])(source|\.)[[:space:]]+"?lib/[A-Za-z0-9._-]+\.sh' "$@" 2>/dev/null
}

checked=0
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  checked=$((checked + 1))
  f="${hit%%:*}"; rest="${hit#*:}"; l="${rest%%:*}"; m="${rest#*:}"
  m=$(printf '%s' "$m" | sed 's/^[^A-Za-z.]*//')
  report_fail "$f:$l cwd-relative helper source ($m) — resolves against the consumer's own cwd, not the plugin install; use \${CLAUDE_PLUGIN_ROOT}/lib/..."
done < <(_cwd_relative_source skills agents)

if [ "$FAILS" -eq 0 ]; then
  echo "OK: no skills/ or agents/ file sources a lib/ helper with a cwd-relative path ($checked candidate reference(s) found)"
fi

# --- self-test: red on a seeded bare `source lib/x.sh`, green on the rooted form ----
SELFTEST_DIR="$(mktemp -d)"
trap 'rm -rf "$SELFTEST_DIR"' EXIT
mkdir -p "$SELFTEST_DIR/skills/_shared"

cat > "$SELFTEST_DIR/skills/_shared/violation.md" <<'EOF'
## API

```bash
source lib/emit-learning.sh
echo '<json-object>' | emit_learning
```
EOF

cat > "$SELFTEST_DIR/skills/_shared/clean.md" <<'EOF'
## API

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
echo '<json-object>' | emit_learning
```

Pre-marketplace-fetch form: `source "$PLUGIN_PATH/lib/emit-learning.sh"`.
EOF

v=$(_cwd_relative_source "$SELFTEST_DIR/skills" | grep -c .)
if [ "$v" -ge 1 ]; then
  echo "OK: self-test — a seeded bare 'source lib/emit-learning.sh' is detected"
else
  report_fail "self-test — seeded cwd-relative source was NOT detected"
fi

c=$(_cwd_relative_source "$SELFTEST_DIR/skills/_shared/clean.md" | grep -c .)
if [ "$c" -eq 0 ]; then
  echo "OK: self-test — \${CLAUDE_PLUGIN_ROOT}/lib/ and \$PLUGIN_PATH/lib/ forms do not false-positive"
else
  report_fail "self-test — the rooted-source fixture false-positived ($c hit(s))"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS cwd-relative lib/ source problem(s)." >&2
  exit 1
fi
echo "OK: every lib/ helper source in skills/ and agents/ is plugin-root-rooted."
