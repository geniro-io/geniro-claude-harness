#!/usr/bin/env bash
# Smoke test for lib/repo-profile.sh — the repo-profile detector that decides
# whether a code-graph index pays off or grep retrieval is already sufficient.
#
# Run: bash tests/memory/repo-profile.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/repo-profile.sh"

# Extract a `key=value` field from the default (non-JSON) output.
field() { sed -n "s/^$2=//p" <<<"$1"; }

# Generate a code file: $1 defs, each padded to $2 body lines, into file $3.
gen_code_file() {
  local defs="$1" body="$2" out="$3" i j
  : >"$out"
  for ((i = 1; i <= defs; i++)); do
    echo "function fn_${i}() {" >>"$out"
    for ((j = 1; j <= body; j++)); do echo "  const v${j} = ${j};" >>"$out"; done
    echo "}" >>"$out"
  done
}

expect_verdict() {
  local root="$1" expected="$2" label="$3"
  local out got
  out=$(repo_profile --root "$root" 2>/dev/null)
  got=$(field "$out" verdict)
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected verdict '$expected', got '$got' ($(field "$out" reason))"
  fi
}

# 1. Doc-heavy repo (mostly markdown) → grep-sufficient. The graph cannot see
#    prose coupling, so grep is more complete. Mirrors this plugin's own shape.
mkdir -p "$TMPDIR_BASE/doc-heavy"
git -C "$TMPDIR_BASE/doc-heavy" init -q
gen_code_file 5 20 "$TMPDIR_BASE/doc-heavy/helper.sh"
for i in $(seq 1 40); do
  yes "Some prose line documenting a contract and cross-referencing a helper." \
    | head -200 >"$TMPDIR_BASE/doc-heavy/doc_$i.md"
done
git -C "$TMPDIR_BASE/doc-heavy" add -A 2>/dev/null
expect_verdict "$TMPDIR_BASE/doc-heavy" "grep-sufficient" \
  "doc-heavy repo → grep-sufficient (graph blind to prose coupling)"

# 2. Large code-dense repo → graph-beneficial. Coupling IS code call edges and
#    the layer is deep enough that transitive queries beat repeated grep.
mkdir -p "$TMPDIR_BASE/code-big/src"
git -C "$TMPDIR_BASE/code-big" init -q
for i in $(seq 1 50); do gen_code_file 30 10 "$TMPDIR_BASE/code-big/src/mod_$i.js"; done
git -C "$TMPDIR_BASE/code-big" add -A 2>/dev/null
expect_verdict "$TMPDIR_BASE/code-big" "graph-beneficial" \
  "large code-dense repo → graph-beneficial"

# 3. Tiny code repo → grep-sufficient. Indexing overhead is not worth it; grep
#    + Read is cheaper than building and maintaining a graph.
mkdir -p "$TMPDIR_BASE/code-small"
git -C "$TMPDIR_BASE/code-small" init -q
gen_code_file 3 5 "$TMPDIR_BASE/code-small/main.py"
git -C "$TMPDIR_BASE/code-small" add -A 2>/dev/null
expect_verdict "$TMPDIR_BASE/code-small" "grep-sufficient" \
  "tiny code repo → grep-sufficient (indexing overhead unjustified)"

# 4. Mid-size, code-dense, but shallow (few symbols) → borderline. Above the
#    grep floor, below the beneficial bar on both scale gates.
mkdir -p "$TMPDIR_BASE/code-mid/src"
git -C "$TMPDIR_BASE/code-mid" init -q
# 40 files x 10 defs (=400 symbols) x ~20 body lines (~8000 code lines): clears
# the grep floor (5000 lines / 150 symbols) but misses beneficial (20000 / 800).
for i in $(seq 1 40); do gen_code_file 10 18 "$TMPDIR_BASE/code-mid/src/m_$i.go"; done
git -C "$TMPDIR_BASE/code-mid" add -A 2>/dev/null
expect_verdict "$TMPDIR_BASE/code-mid" "borderline" \
  "mid-size shallow code repo → borderline"

# 5. Fail-open: a nonexistent root must yield grep-sufficient and rc 0 — never a
#    forced graph onto a repo we could not measure.
out=$(repo_profile --root "$TMPDIR_BASE/does-not-exist" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ "$(field "$out" verdict)" = "grep-sufficient" ]; then
  pass "nonexistent root → fail-open grep-sufficient, rc 0"
else
  fail "nonexistent root — expected grep-sufficient/rc0, got '$(field "$out" verdict)'/rc$rc"
fi

# 6. Non-git directory uses the find fallback and still measures lines > 0.
mkdir -p "$TMPDIR_BASE/no-git/src"
for i in $(seq 1 30); do gen_code_file 20 10 "$TMPDIR_BASE/no-git/src/m_$i.rs"; done
out=$(repo_profile --root "$TMPDIR_BASE/no-git" 2>/dev/null)
if [ "$(field "$out" code_lines)" -gt 0 ]; then
  pass "non-git dir → find fallback measures code_lines > 0 ($(field "$out" code_lines))"
else
  fail "non-git dir — find fallback measured 0 code lines"
fi

# 7. JSON mode emits parseable JSON carrying a verdict key.
out=$(repo_profile --root "$TMPDIR_BASE/code-big" --json 2>/dev/null)
if command -v jq >/dev/null 2>&1; then
  if jq -e '.verdict and (.code_lines | type == "number")' >/dev/null 2>&1 <<<"$out"; then
    pass "JSON mode → valid JSON with verdict + numeric fields"
  else
    fail "JSON mode — output is not valid JSON with expected keys: $out"
  fi
else
  case "$out" in
    *'"verdict"'*) pass "JSON mode → carries verdict key (jq absent, string check)" ;;
    *) fail "JSON mode — missing verdict key: $out" ;;
  esac
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
