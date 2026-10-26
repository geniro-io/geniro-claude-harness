#!/usr/bin/env bash
# Behavior tests for lib/load-custom-instructions.sh — the custom instruction
# loader whose output is the echo line per file (skills/_shared/load-custom-instructions.md
# §Echo contract) followed by a `Read: <absolute path>` line per file to Read,
# never the file content.
#
# Pins: the load set per tier (pipeline = four files in order, rules-only = two);
# checkout-first resolution (the git top level, so a subdirectory of a linked
# worktree finds that worktree's own files) with a per-file fallback to the
# primary worktree, and the plain form when cwd is a subdirectory of the main
# checkout; output that stays small whatever the file sizes; an external
# instructions dir that overrides the repo
# entirely (no merge, GENIRO_INSTRUCTIONS_DIR over the plugin option, tilde
# expanded, a relative path made absolute); a configured-but-missing external dir
# printing the caveat first and falling back to the repo; `No <file> found` for a
# file absent everywhere; the
# rules/constraints/additional-steps/data-sources echo with singular/plural and
# literal anchor names; the memory.md memory-backend forms (commented-out
# scaffold entries and fenced examples are not a declared backend); a directory
# or unreadable file reporting `Failed to load` without stopping the rest, and a
# counting failure on a readable file echoing `counts unavailable` and still
# listing its path; rc 0 on every missing file and rc 64 on a usage error; and identical output
# when the helper is sourced under `set -u` by bash 3.2 and by zsh.
#
# Run: bash tests/memory/load-custom-instructions.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_ROOT/lib/load-custom-instructions.sh"
TMPDIR_BASE="$(cd "$(mktemp -d)" && pwd -P)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

OUT=""
RC=0

# run_loader <dir> <slug> <tier> [VAR=value ...] — runs the helper from <dir> in a
# fresh bash with both override variables cleared except those passed. Sets OUT
# (stdout + stderr) and RC.
run_loader() {
  local dir="$1" slug="$2" tier="$3"
  shift 3
  RC=0
  OUT="$(cd "$dir" && env -u GENIRO_INSTRUCTIONS_DIR -u CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR "$@" \
    bash -c "source '$LIB' && load_custom_instructions '$slug' '$tier'" 2>&1)" || RC=$?
}

# The structural lines of OUT, in order: the caveat, echo lines, then Read paths.
spine() {
  printf '%s\n' "$OUT" | grep -E '^(Read: |Loaded |No .* found|Failed to load |External instructions dir )' || true
}

expect_spine() {
  local expected="$1" label="$2" got
  got="$(spine)"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label — expected:
$expected
got:
$got"
  fi
}

expect_in_out() {
  local needle="$1" label="$2"
  if printf '%s\n' "$OUT" | grep -qxF -- "$needle"; then
    pass "$label"
  else
    fail "$label — line not found: $needle
output:
$OUT"
  fi
}

expect_not_in_out() {
  local needle="$1" label="$2"
  if printf '%s\n' "$OUT" | grep -qF -- "$needle"; then
    fail "$label — unexpected text found: $needle"
  else
    pass "$label"
  fi
}

expect_rc() {
  local want="$1" label="$2"
  if [ "$RC" -eq "$want" ]; then
    pass "$label"
  else
    fail "$label — expected rc $want, got $RC"
  fi
}

# mk <dir> <file> — fixture from stdin, written under <dir>/.geniro/instructions/.
mk() {
  mkdir -p "$1/.geniro/instructions"
  cat > "$1/.geniro/instructions/$2"
}

# --- Fixture project: four files with distinct counts. ---
PROJ="$TMPDIR_BASE/proj"
mkdir -p "$PROJ"
( cd "$PROJ" && git init -q )
mk "$PROJ" global.md <<'EOF'
# Custom Instructions

## Rules
- Global rule one
- Global rule two

## Constraints
- Global constraint

## Data Sources
- **src one** (confirms: x) — cmd
- **src two** (confirms: x) — cmd
EOF
mk "$PROJ" memory.md <<'EOF'
# Memory
EOF
mk "$PROJ" debug.md <<'EOF'
# Custom Instructions

## Rules
- Debug rule

## Additional Steps
### After ship
- a step
EOF
mk "$PROJ" code-style.md <<'EOF'
# Custom Instructions

## Rules
- Style one
- Style two
- Style three

## Constraints
- Style constraint one
- Style constraint two
EOF

H="$PROJ/.geniro/instructions"

# --- 1. pipeline tier from cwd: four echo lines in order, then a Read path each. ---
run_loader "$PROJ" debug pipeline
expect_spine "Loaded global.md (2 rules, 1 constraint, 2 data sources).
Loaded memory.md (no memory backend declared).
Loaded debug.md (1 rule, 0 constraints, 1 additional step: After ship).
Loaded code-style.md (3 rules, 2 constraints).
Read: $H/global.md
Read: $H/memory.md
Read: $H/debug.md
Read: $H/code-style.md" \
  "pipeline tier: four echo lines in order, then the four absolute paths to Read"
expect_not_in_out "- Global rule two" "pipeline tier: file content is not printed"
expect_not_in_out "- Style constraint two" "pipeline tier: the last file's content is not printed"
expect_rc 0 "pipeline tier: rc 0"

# --- 2. rules-only tier loads only its two files even when the others exist. ---
run_loader "$PROJ" debug rules-only
expect_spine "Loaded global.md (2 rules, 1 constraint, 2 data sources).
Loaded memory.md (no memory backend declared).
Read: $H/global.md
Read: $H/memory.md" \
  "rules-only tier: global.md + memory.md only"
expect_not_in_out "debug.md" "rules-only tier: the per-skill file is not in the load set"
expect_not_in_out "code-style.md" "rules-only tier: code-style.md is not in the load set"

# --- 3. Absent everywhere: the not-found echo per file, rc 0, no Read path. ---
EMPTY="$TMPDIR_BASE/empty"
mkdir -p "$EMPTY"
( cd "$EMPTY" && git init -q )
run_loader "$EMPTY" debug pipeline
expect_spine "No global.md found — skipping.
No memory.md found — skipping.
No debug.md found — skipping.
No code-style.md found — skipping." \
  "files absent everywhere: one not-found line each, no paths to Read"
expect_rc 0 "files absent everywhere: fail-open rc 0"

# --- 4. Linked worktree whose files exist only in the main checkout. ---
MAIN="$TMPDIR_BASE/main"
mkdir -p "$MAIN"
( cd "$MAIN" && git init -q \
  && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git worktree add -q "$TMPDIR_BASE/main-wt" 2>/dev/null )
cp -R "$PROJ/.geniro" "$MAIN/.geniro"
M="$MAIN/.geniro/instructions"
WT="$TMPDIR_BASE/main-wt"
run_loader "$WT" debug pipeline
expect_spine "Loaded global.md from primary worktree (2 rules, 1 constraint, 2 data sources).
Loaded memory.md from primary worktree (no memory backend declared).
Loaded debug.md from primary worktree (1 rule, 0 constraints, 1 additional step: After ship).
Loaded code-style.md from primary worktree (3 rules, 2 constraints).
Read: $M/global.md
Read: $M/memory.md
Read: $M/debug.md
Read: $M/code-style.md" \
  "linked worktree with files only in the main checkout: every file loads from the primary worktree"

# cwd-first, per file: a copy in the linked worktree wins over the main checkout's.
mk "$WT" global.md <<'EOF'
## Rules
- Branch-local rule
EOF
run_loader "$WT" debug rules-only
expect_spine "Loaded global.md (1 rule, 0 constraints).
Loaded memory.md from primary worktree (no memory backend declared).
Read: $WT/.geniro/instructions/global.md
Read: $M/memory.md" \
  "linked worktree: a cwd copy wins for its file, the rest fall back per file"
expect_not_in_out "Read: $M/global.md" "linked worktree: the main checkout's copy of a shadowed file is not listed"

# A subdirectory of the main checkout resolves the main checkout's own files: the plain form.
mkdir -p "$MAIN/src/deep"
run_loader "$MAIN/src/deep" debug pipeline
expect_spine "Loaded global.md (2 rules, 1 constraint, 2 data sources).
Loaded memory.md (no memory backend declared).
Loaded debug.md (1 rule, 0 constraints, 1 additional step: After ship).
Loaded code-style.md (3 rules, 2 constraints).
Read: $M/global.md
Read: $M/memory.md
Read: $M/debug.md
Read: $M/code-style.md" \
  "subdirectory of the main checkout: the main checkout's own files carry no from-primary-worktree label"

# A subdirectory of a linked worktree still reaches the main checkout's files, labelled.
mkdir -p "$WT/src"
run_loader "$WT/src" debug rules-only
expect_in_out "Loaded memory.md from primary worktree (no memory backend declared)." \
  "subdirectory of a linked worktree: the main checkout's file keeps the from-primary-worktree label"

# A subdirectory of a linked worktree looks in that worktree's root first: its own files load in
# the plain form, a shadowed file wins over the main checkout's copy, and a file only the worktree has is found.
mk "$WT" wtonly.md <<'EOF'
## Rules
- Worktree-only rule
EOF
run_loader "$WT/src" wtonly pipeline
expect_spine "Loaded global.md (1 rule, 0 constraints).
Loaded memory.md from primary worktree (no memory backend declared).
Loaded wtonly.md (1 rule, 0 constraints).
Loaded code-style.md from primary worktree (3 rules, 2 constraints).
Read: $WT/.geniro/instructions/global.md
Read: $M/memory.md
Read: $WT/.geniro/instructions/wtonly.md
Read: $M/code-style.md" \
  "subdirectory of a linked worktree: the worktree root's files load in the plain form, the rest fall back per file"
expect_not_in_out "Read: $M/global.md" "subdirectory of a linked worktree: the main checkout's copy of a shadowed file is not listed"

# --- 5. External instructions dir: flat layout, overrides the repo, no merge. ---
EXT="$TMPDIR_BASE/ext"
mkdir -p "$EXT"
cat > "$EXT/global.md" <<'EOF'
## Rules
- External rule

## Constraints
- External constraint one
- External constraint two
EOF
cat > "$EXT/debug.md" <<'EOF'
## Rules
- External debug rule
EOF
run_loader "$PROJ" debug pipeline GENIRO_INSTRUCTIONS_DIR="$EXT"
expect_spine "Loaded global.md from external instructions dir (1 rule, 2 constraints).
No memory.md found — skipping.
Loaded debug.md from external instructions dir (1 rule, 0 constraints).
No code-style.md found — skipping.
Read: $EXT/global.md
Read: $EXT/debug.md" \
  "external dir set: flat layout, repo copies ignored even where the external dir lacks the file"

# The plugin-option channel works alone; GENIRO_INSTRUCTIONS_DIR wins when both are set.
EXT2="$TMPDIR_BASE/ext2"
mkdir -p "$EXT2"
printf '## Rules\n- Option rule\n- Option rule two\n' > "$EXT2/global.md"
run_loader "$PROJ" debug rules-only CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR="$EXT2"
expect_in_out "Loaded global.md from external instructions dir (2 rules, 0 constraints)." \
  "plugin-option dir alone is used"
run_loader "$PROJ" debug rules-only GENIRO_INSTRUCTIONS_DIR="$EXT" CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR="$EXT2"
expect_in_out "Loaded global.md from external instructions dir (1 rule, 2 constraints)." \
  "both set: GENIRO_INSTRUCTIONS_DIR takes precedence"

# A leading ~ expands to $HOME.
HOME_DIR="$TMPDIR_BASE/home"
mkdir -p "$HOME_DIR/rules"
printf '## Rules\n- Home rule\n' > "$HOME_DIR/rules/global.md"
run_loader "$PROJ" debug rules-only HOME="$HOME_DIR" GENIRO_INSTRUCTIONS_DIR="~/rules"
expect_in_out "Read: $HOME_DIR/rules/global.md" \
  "external dir with a leading ~ expands to HOME"

# A relative dir is resolved against cwd, so the listed path is absolute.
run_loader "$HOME_DIR" debug rules-only GENIRO_INSTRUCTIONS_DIR="rules"
expect_in_out "Read: $HOME_DIR/rules/global.md" \
  "relative external dir: the listed path is absolute"

# --- 6. External dir configured but missing: caveat first, then the repo load. ---
run_loader "$PROJ" debug rules-only GENIRO_INSTRUCTIONS_DIR="$TMPDIR_BASE/no-such-dir"
expect_spine "External instructions dir $TMPDIR_BASE/no-such-dir not found — using in-repo instructions.
Loaded global.md (2 rules, 1 constraint, 2 data sources).
Loaded memory.md (no memory backend declared).
Read: $H/global.md
Read: $H/memory.md" \
  "missing external dir: the caveat prints once, before the in-repo load"
expect_rc 0 "missing external dir: fail-open rc 0"

# --- 7. memory.md forms. ---
MEM="$TMPDIR_BASE/mem"
mkdir -p "$MEM"
( cd "$MEM" && git init -q )

memory_case() {
  local label="$1" expected="$2"
  run_loader "$MEM" debug rules-only
  expect_in_out "$expected" "$label"
}

mk "$MEM" memory.md <<'EOF'
# Memory

## Memory Backend
- layer: learnings
  mode: replace
  write: mcp tool `mcp__memory__upsert`
  read:  mcp tool `mcp__memory__search`
EOF
memory_case "memory.md with a replace-mode backend names layer and mode" \
  "Loaded memory.md (memory backend: learnings → replace)."

mk "$MEM" memory.md <<'EOF'
## Memory Backend
- layer: learnings
  write: mcp tool `mcp__memory__upsert`
EOF
memory_case "memory.md without a mode defaults to mirror" \
  "Loaded memory.md (memory backend: learnings → mirror)."

mk "$MEM" memory.md <<'EOF'
## Memory Backend
<!-- Optional. Route agent learnings through a custom backend. -->
- layer: learnings   # mode: mirror|replace; write: <mcp tool>; read: <read-only mcp tool>
EOF
memory_case "memory.md with only an inline comment after the layer reads mirror, not the comment's mode list" \
  "Loaded memory.md (memory backend: learnings → mirror)."

mk "$MEM" memory.md <<'EOF'
# Memory

## Memory Backend
<!-- Optional. Route agent learnings (L2) through a custom backend. -->
<!-- - layer: learnings -->
<!--   mode: replace -->
<!--
- layer: learnings
  mode: replace
-->
```
- layer: learnings
  mode: replace
```
EOF
memory_case "memory.md whose only entries are in single-line comments, a multi-line comment or a fence declares no backend" \
  "Loaded memory.md (no memory backend declared)."

mk "$MEM" memory.md <<'EOF'
## Rules
- layer: learnings
  mode: replace
EOF
memory_case "an entry outside the Memory Backend section is not a backend" \
  "Loaded memory.md (no memory backend declared)."

mk "$MAIN" memory.md <<'EOF'
## Memory Backend
- layer: learnings
  mode: replace
EOF
run_loader "$WT" debug rules-only
expect_in_out "Loaded memory.md from primary worktree (memory backend: learnings → replace)." \
  "memory.md from the primary worktree keeps the memory form"

printf '## Memory Backend\n- layer: learnings\n  mode: mirror\n' > "$EXT/memory.md"
run_loader "$PROJ" debug rules-only GENIRO_INSTRUCTIONS_DIR="$EXT"
expect_in_out "Loaded memory.md from external instructions dir (memory backend: learnings → mirror)." \
  "memory.md from the external dir keeps the memory form"

# --- 8. Echo counts: quoted from the counters, singular/plural, literal anchors. ---
CNT="$TMPDIR_BASE/cnt"
mkdir -p "$CNT"
( cd "$CNT" && git init -q )
mk "$CNT" plan.md <<'EOF'
# Custom Instructions

## Rules
- Only rule

## Additional Steps
### After explore
- one
### after User-approve
- two
### Before ship
- three
EOF
mk "$CNT" global.md <<'EOF'
## Rules
- r1
  - nested, not counted
- r2
- r3

```
## Constraints
- fenced, not counted
```

## Constraints
- c1
- c2
EOF
: > "$CNT/.geniro/instructions/code-style.md"
run_loader "$CNT" plan pipeline
expect_in_out "Loaded plan.md (1 rule, 0 constraints, 3 additional steps: After explore, after User-approve, Before ship)." \
  "echo: singular rule, plural steps, anchor names verbatim in file order (case and Before form kept)"
expect_in_out "Loaded global.md (3 rules, 2 constraints)." \
  "echo: nested and fenced bullets are not counted"
expect_in_out "Loaded code-style.md (0 rules, 0 constraints)." \
  "echo: an empty file still prints the literal zero counts"

# --- 9. A file with no trailing newline still counts and lists. ---
NONL="$TMPDIR_BASE/nonl"
mkdir -p "$NONL/.geniro/instructions"
( cd "$NONL" && git init -q )
printf '## Rules\n- last line has no newline' > "$NONL/.geniro/instructions/global.md"
run_loader "$NONL" debug rules-only
expect_in_out "Loaded global.md (1 rule, 0 constraints)." "a final line without a trailing newline is counted"
expect_in_out "Read: $NONL/.geniro/instructions/global.md" "a final line without a trailing newline: the file is listed"

# --- 9b. Output stays small whatever the file sizes, and lists every path. ---
BIG="$TMPDIR_BASE/big"
mkdir -p "$BIG"
( cd "$BIG" && git init -q )
for f in global.md memory.md debug.md code-style.md; do
  {
    printf '## Rules\n'
    i=0
    while [ "$i" -lt 600 ]; do
      printf -- '- filler rule %s padded so the file runs long and the fixture totals well over thirty thousand characters\n' "$i"
      i=$((i + 1))
    done
  } | mk "$BIG" "$f"
done
BIG_BYTES="$(cat "$BIG"/.geniro/instructions/*.md | wc -c | tr -d ' ')"
run_loader "$BIG" debug pipeline
if [ "$BIG_BYTES" -gt 30000 ] && [ "${#OUT}" -lt 2000 ]; then
  pass "large fixture: ${BIG_BYTES} bytes of instructions, ${#OUT}-character output"
else
  fail "large fixture: ${BIG_BYTES} bytes of instructions, ${#OUT}-character output (want fixture > 30000, output < 2000)"
fi
expect_spine "Loaded global.md (600 rules, 0 constraints).
Loaded memory.md (no memory backend declared).
Loaded debug.md (600 rules, 0 constraints).
Loaded code-style.md (600 rules, 0 constraints).
Read: $BIG/.geniro/instructions/global.md
Read: $BIG/.geniro/instructions/memory.md
Read: $BIG/.geniro/instructions/debug.md
Read: $BIG/.geniro/instructions/code-style.md" \
  "large fixture: every echo line and every path is present"
expect_not_in_out "filler rule" "large fixture: no file content is printed"

# --- 10. Load failures report and continue; the loader never halts. ---
BAD="$TMPDIR_BASE/bad"
mkdir -p "$BAD/.geniro/instructions/global.md"
( cd "$BAD" && git init -q )
printf '## Rules\n- fine\n' > "$BAD/.geniro/instructions/memory.md"
run_loader "$BAD" debug rules-only
expect_spine "Failed to load global.md: is a directory — skipping.
Loaded memory.md (no memory backend declared).
Read: $BAD/.geniro/instructions/memory.md" \
  "a directory in place of a file: Failed to load and no path, and the next file still loads"
expect_rc 0 "a directory in place of a file: rc 0"

# Counters failing on a readable file: the echo says counts are unavailable, not that the file is skipped, and the path is still listed.
RC=0
OUT="$(cd "$PROJ" && env -u GENIRO_INSTRUCTIONS_DIR -u CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR \
  bash -c "source '$LIB'; count_instruction_sections() { return 1; }; load_custom_instructions debug rules-only" 2>&1)" || RC=$?
expect_spine "Loaded global.md (counts unavailable: section counters failed).
Loaded memory.md (no memory backend declared).
Read: $H/global.md
Read: $H/memory.md" \
  "a counting failure on a readable file: counts unavailable, and the file is still listed to Read"
expect_not_in_out "skipping" "a counting failure on a readable file: no skip wording"
expect_rc 0 "a counting failure on a readable file: rc 0"

RC=0
OUT="$(cd "$PROJ" && env -u GENIRO_INSTRUCTIONS_DIR -u CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR \
  bash -c "source '$LIB'; _lci_memory_entries() { return 1; }; load_custom_instructions debug rules-only" 2>&1)" || RC=$?
expect_spine "Loaded global.md (2 rules, 1 constraint, 2 data sources).
Loaded memory.md (counts unavailable: memory backend block not parsed).
Read: $H/global.md
Read: $H/memory.md" \
  "a memory backend parse failure on a readable file: counts unavailable, and the file is still listed to Read"

if [ "$(id -u)" != "0" ]; then
  NOPERM="$TMPDIR_BASE/noperm"
  mkdir -p "$NOPERM"
  ( cd "$NOPERM" && git init -q )
  mk "$NOPERM" global.md <<'EOF'
## Rules
- secret
EOF
  chmod 000 "$NOPERM/.geniro/instructions/global.md"
  run_loader "$NOPERM" debug rules-only
  chmod 644 "$NOPERM/.geniro/instructions/global.md"
  expect_in_out "Failed to load global.md: permission denied — skipping." \
    "an unreadable file: Failed to load"
  expect_not_in_out "Read:" "an unreadable file: no path to Read"
else
  echo "SKIP: running as root — permission-bit test would not block the read."
fi

# --- 11. Usage errors are the only non-zero exit. ---
run_loader "$PROJ" "" ""
expect_rc 64 "no arguments: usage error rc 64"
run_loader "$PROJ" debug sideways
expect_rc 64 "unknown LOAD_TIER: usage error rc 64"
expect_not_in_out "Read:" "unknown LOAD_TIER: nothing is listed"

# --- 12. Sourced under `set -u` by bash 3.2 and zsh: same output as bash. ---
run_loader "$PROJ" debug pipeline
EXPECTED_OUT="$OUT"
for shell in /bin/bash zsh; do
  if ! command -v "$shell" >/dev/null 2>&1; then
    echo "SKIP: $shell not available."
    continue
  fi
  got="$(cd "$PROJ" && env -u GENIRO_INSTRUCTIONS_DIR -u CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR \
    "$shell" -c "set -u; source '$LIB' && load_custom_instructions debug pipeline" 2>&1)"
  if [ "$got" = "$EXPECTED_OUT" ]; then
    pass "$shell under set -u: output identical to bash"
  else
    fail "$shell under set -u: output differs from bash:
$got"
  fi
done

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
