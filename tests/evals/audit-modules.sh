#!/usr/bin/env bash
# Suite for the evals/loop audit modules: stage-task.sh "audit" mode, the
# loop_lib.py "audit-findings" parser, and sync-champion.sh section extraction.
#
# Run: bash tests/evals/audit-modules.sh
#
# Both directions on every assertion: a shape that must parse and one that must
# not, so a parser silently reduced to "emit nothing" is visible here rather
# than as a zero-recall sweep nobody can explain.
#
# Plugin-developer tooling only — not shipped to user projects.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOOP="$REPO_ROOT/evals/loop"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# --- module declarations ----------------------------------------------------

for m in audit-instructions audit-plugin; do
  T="$LOOP/modules/$m/target.json"
  if jq -e '.parser == "audit-findings" and .pass_expr != null and .negative_pass_expr != null' \
       "$T" >/dev/null 2>&1; then
    pass "$m target.json names the audit-findings parser and both pass expressions"
  else
    fail "$m target.json is missing the parser or a pass expression"
  fi

  if [ -f "$LOOP/modules/$m/variants/champion/preamble.md" ]; then
    pass "$m champion carries a preamble"
  else
    fail "$m champion has no preamble.md"
  fi

  # Every facet's criteria must resolve, or a sweep assembles a prompt with a
  # missing rubric and the dimension silently reviews against nothing.
  MISSING="$(jq -r '.facets[].criteria[]' "$T" | sort -u | while IFS= read -r c; do
    [ -f "$LOOP/modules/$m/variants/champion/criteria/$c" ] || echo "$c"
  done)"
  if [ -z "$MISSING" ]; then
    pass "$m every facet criteria file exists in the champion"
  else
    fail "$m champion is missing criteria:"$'\n'"$MISSING"
  fi

  # A screen facet naming a facet that does not exist would silently screen nothing.
  BADSCREEN="$(jq -r '(.facets | map(.name)) as $f | .screen_facets[] | select(. as $s | $f | index($s) | not)' "$T")"
  if [ -z "$BADSCREEN" ]; then
    pass "$m every screen facet is a declared facet"
  else
    fail "$m screen_facets names undeclared facets: $BADSCREEN"
  fi

  # Every champion_sync source must still resolve. sync-champion.sh already
  # hard-fails on a renamed heading, but only when someone runs it — which is
  # after the skill edit has landed. Checking here moves the break to the commit
  # that renames the heading.
  UNRESOLVED="$(jq -r '.champion_sync[] | [.from, (.section // "")] | @tsv' "$T" | while IFS=$'\t' read -r from section; do
    if [ ! -f "$REPO_ROOT/$from" ]; then
      echo "missing source: $from"
    elif [ -n "$section" ] && ! grep -qxF "## $section" "$REPO_ROOT/$from"; then
      echo "missing section '## $section' in $from"
    fi
  done)"
  if [ -z "$UNRESOLVED" ]; then
    pass "$m every champion_sync source and section resolves"
  else
    fail "$m champion_sync is stale:"$'\n'"$UNRESOLVED"
  fi
done

# --- stage-task.sh "audit" mode ---------------------------------------------

TASK="$LOOP/modules/audit-instructions/benchmarks/dev/planted-1"
STAGE="$SANDBOX/stage"
if bash "$LOOP/stage-task.sh" "$TASK" "$STAGE" >/dev/null 2>&1; then
  pass "audit mode stages without error"
else
  fail "stage-task.sh failed on an audit-mode task"
fi

if [ -d "$STAGE/tree" ] && [ -n "$(ls -A "$STAGE/tree" 2>/dev/null)" ]; then
  pass "audit mode materializes a non-empty tree"
else fail "audit mode left the tree empty"; fi
if [ ! -f "$STAGE/diff.patch" ]; then pass "audit mode writes no diff — nothing changed"
else fail "audit mode wrote a diff.patch"; fi
if [ ! -f "$STAGE/spec.md" ]; then pass "audit mode writes no spec — the tree is the artifact"
else fail "audit mode wrote a spec.md"; fi

# surfaces.txt is the staged stand-in for the skill's mechanical pre-pass. An
# empty one would hand every reviewer an empty scope and score as a capability
# failure rather than a staging bug.
if [ -s "$STAGE/surfaces.txt" ] && grep -q 'CLAUDE.md' "$STAGE/surfaces.txt"; then
  pass "audit mode writes a non-empty surfaces.txt covering the tree"
else
  fail "surfaces.txt is empty or missing the instruction surfaces"
fi
if [ "$(wc -l < "$STAGE/surfaces.txt" | tr -d ' ')" = "$(find "$STAGE/tree" -type f | wc -l | tr -d ' ')" ]; then
  pass "surfaces.txt has one row per staged file"
else
  fail "surfaces.txt row count does not match the staged tree"
fi

# A task whose tree_dir does not resolve must fail loudly, not stage an empty tree.
BADTASK="$SANDBOX/badtask"
mkdir -p "$BADTASK"
cat > "$BADTASK/task.json" <<'JSON'
{"id":"bad","mode":"audit","tree_dir":"absent"}
JSON
if bash "$LOOP/stage-task.sh" "$BADTASK" "$SANDBOX/stage-bad" >/dev/null 2>&1; then
  fail "a missing tree_dir staged silently"
else
  pass "a missing tree_dir fails staging instead of running on an empty tree"
fi

# --- the audit-findings parser ----------------------------------------------

mk_raw() {  # mk_raw <out-path> <result-text>
  python3 - "$1" "$2" <<'PY'
import json, sys
json.dump({"type": "result", "result": sys.argv[2], "is_error": False,
           "usage": {"inputTokens": 10, "cacheReadTokens": 0, "outputTokens": 5}},
          open(sys.argv[1], "w"))
PY
}
parse() { python3 "$LOOP/loop_lib.py" parse --parser audit-findings "$1"; }
count() { printf '%s' "$1" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }

mk_raw "$SANDBOX/raw-accuracy.json" '| id | tier | file:line | issue | evidence | fix | effort |
|---|---|---|---|---|---|---|
| D2-1 | T1 | CLAUDE.md:16 | Documented test command does not exist | `npm run test:unit` | Replace with `npm test` | S |
| D2-2 | T3 | CLAUDE.md:32 | Service count is stale | "three services" | Point at the directory | S |

## Dimension verdict
Debt concentrated in the commands table.'
OUT="$(parse "$SANDBOX/raw-accuracy.json")"

if [ "$(count "$OUT")" = "2" ]; then pass "one finding per table row, header and separator skipped"
else fail "expected 2 findings, got $(count "$OUT")"; fi

fileref="$(printf '%s' "$OUT" | python3 -c 'import json,sys; f=json.load(sys.stdin); print(f[0]["file"], f[0]["line_start"], f[0]["tier"], f[0]["severity"])')"
if [ "$fileref" = "CLAUDE.md 16 T1 HIGH" ]; then pass "file:line, tier, and the mapped severity all parse"
else fail "row parse drifted: $fileref"; fi

ev="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(all(x["has_evidence"] for x in json.load(sys.stdin)))')"
if [ "$ev" = "True" ]; then pass "a non-empty evidence cell sets has_evidence"
else fail "has_evidence not set from the evidence column"; fi

# A reviewer that drops the id column still emits gradeable findings.
mk_raw "$SANDBOX/raw-noid.json" '| tier | file:line | issue | evidence | fix |
|---|---|---|---|---|
| T0 | .github/copilot-instructions.md:15 | Credential in an instruction file | line carries a Postgres URL with an inline password | Move to a secret store | M |

## Dimension verdict
One safety finding.'
if [ "$(count "$(parse "$SANDBOX/raw-noid.json")")" = "1" ]; then
  pass "a table without the id column still parses"
else
  fail "an id-less table parsed to $(count "$(parse "$SANDBOX/raw-noid.json")") findings"
fi

# A clean pass — verdict only, no table — must parse to zero findings, not junk.
mk_raw "$SANDBOX/raw-clean.json" '## Dimension verdict
Healthy. Examined all four surfaces; considered and rejected the AGENTS.md
mirror, which is generated and matches its source.'
if [ "$(count "$(parse "$SANDBOX/raw-clean.json")")" = "0" ]; then
  pass "a clean pass parses to zero findings"
else
  fail "clean pass produced $(count "$(parse "$SANDBOX/raw-clean.json")") findings"
fi

# An unrelated Markdown table must not be mistaken for a findings table.
mk_raw "$SANDBOX/raw-other.json" '| What | Command |
|---|---|
| Test | `make test` |

## Dimension verdict
Healthy.'
if [ "$(count "$(parse "$SANDBOX/raw-other.json")")" = "0" ]; then
  pass "a table with no tier column is not parsed as findings"
else
  fail "an unrelated table produced findings"
fi

# Cross-talk: each parser must ignore the other's shape rather than half-match.
n="$(python3 "$LOOP/loop_lib.py" parse "$SANDBOX/raw-accuracy.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$n" = "0" ]; then pass "the review parser ignores audit tables (no cross-talk)"
else fail "review parser matched $n audit rows"; fi
n="$(python3 "$LOOP/loop_lib.py" parse --parser audit-findings "$SANDBOX/raw-clean.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$n" = "0" ]; then pass "the audit parser emits nothing for a verdict-only result"
else fail "audit parser invented $n findings from a verdict"; fi

# --- sync-champion.sh section extraction ------------------------------------

# Extract from the real shipped reference: the source whose §Reviewer spawn
# template holds a fenced block with `## ` lines of its own, which is exactly
# what a naive scan truncates on.
PROBE="$LOOP/modules/.probe-test"
rm -rf "$PROBE"
mkdir -p "$PROBE/variants/champion"
touch "$PROBE/variants/champion/preamble.md"
cat > "$PROBE/target.json" <<'JSON'
{"module":".probe-test","champion_sync":[
  {"from":"skills/audit-instructions/dimensions-reference.md",
   "section":"Severity tiers (shared output classification)",
   "to":"criteria/tiers.md"}]}
JSON
if bash "$LOOP/sync-champion.sh" --module .probe-test >/dev/null 2>&1; then
  EXTRACTED="$PROBE/variants/champion/criteria/tiers.md"
  if grep -q 'T0 | Safety' "$EXTRACTED"; then
    pass "section extraction returns the named section's body"
  else
    fail "section extraction returned the wrong body"
  fi
  if ! grep -q 'Finding output contract' "$EXTRACTED"; then
    pass "section extraction stops at the next heading"
  else
    fail "section extraction crossed into the next section"
  fi
  if ! grep -q 'AI-instruction audit — dimension' "$EXTRACTED"; then
    pass "section extraction is fence-aware"
  else
    fail "a fenced ## line leaked into the extracted section"
  fi
else
  fail "sync-champion.sh failed on a section entry"
fi

# A renamed heading upstream must break the sync loudly, not ship an empty file.
sed -i.bak 's|Severity tiers (shared output classification)|Renamed Upstream|' "$PROBE/target.json"
rm -f "$PROBE/target.json.bak"
if bash "$LOOP/sync-champion.sh" --module .probe-test >/dev/null 2>&1; then
  fail "a missing section synced silently"
else
  pass "a missing section fails the sync instead of shipping an empty criteria file"
fi
rm -rf "$PROBE"

# --- fixture consistency across both dev sets -------------------------------
#
# Dev only. A holdout failure would print holdout content into the tuning
# session, which is exactly what the dark-holdout rule forbids.

VIOL="$(python3 - "$LOOP/modules/audit-instructions/benchmarks/dev" "$LOOP/modules/audit-plugin/benchmarks/dev" <<'PY'
import json, os, sys

bad = []
for root in sys.argv[1:]:
    module = os.path.basename(os.path.dirname(os.path.dirname(root)))
    for task in sorted(os.listdir(root)):
        d = os.path.join(root, task)
        if not os.path.isdir(d):
            continue
        rubric = json.load(open(os.path.join(d, "rubric.json")))
        tree = os.path.join(d, "tree")
        lines_of = {}
        for dirpath, _, names in os.walk(tree):
            for n in names:
                p = os.path.join(dirpath, n)
                lines_of[os.path.relpath(p, tree)] = sum(1 for _ in open(p, errors="replace"))

        if rubric.get("negative") and rubric.get("items"):
            bad.append(f"{module}/{task}: negative task carries ground-truth items")
        if not rubric.get("negative") and not rubric.get("items"):
            bad.append(f"{module}/{task}: positive task carries no ground-truth items")
        # A positive task with no must_find item can never pass: recall_must is
        # null and the pass expression reads false however good the run was.
        if not rubric.get("negative") and not [i for i in rubric["items"] if i.get("must_find")]:
            bad.append(f"{module}/{task}: positive task has no must_find item — it can never pass")

        for it in rubric.get("items", []):
            f, ln = it.get("file"), it.get("lines") or []
            if f not in lines_of:
                bad.append(f"{module}/{task}/{it['id']}: file {f} is not in the tree")
                continue
            for n in ln:
                if n > lines_of[f]:
                    bad.append(f"{module}/{task}/{it['id']}: line {n} past end of {f} ({lines_of[f]} lines)")

print("\n".join(bad))
PY
)"
if [ -z "$VIOL" ]; then
  pass "every dev fixture's rubric citations resolve in its own tree"
else
  fail "fixture inconsistencies:"$'\n'"$VIOL"
fi

echo
echo "audit-modules: $TESTS_RUN run, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ]
