#!/usr/bin/env bash
# enforce-state-helper.sh
# PreToolUse hook for Write/Edit/MultiEdit — blocks direct writes to canonical
# state paths under .geniro/, steering skills to atomic-state-write.
#
# Scope: writes to canonical state paths under .geniro/ must go through the
# atomic-state-write helper (lib/atomic-state-write.sh), not direct
# Edit/Write calls. The helper guarantees tmp + fsync + rename + fsync-dir
# atomicity. Direct calls truncate-and-rewrite — a reader during the window
# sees a partial file.
#
# The guard reads .tool_input.file_path — a declared, unambiguous target.
#
# Bash is deliberately NOT matched. A shell-side branch has no target field to
# read, so it has to guess one out of the command string, and the guessing is
# what broke: measured across 1,408 sessions (2026-08-13), the Bash branch fired
# 67 times and produced compliance under a third of the time — blocking a
# MIGRATION.md edit whose prose merely mentioned `.geniro/instructions/plan.md`,
# and blocking on the fragment `./.geniro/planning/t` lifted out of a Python
# heredoc that was editing this very directory. Both came from the
# unresolved-target fallback, which matched any `.geniro/` string anywhere in
# the command on the theory that "a path that is not the real target costs
# nothing". It cost a near-identical retry or a workaround most times it fired.
# Shell-side atomicity is now a prose contract (CLAUDE.md §State Files), not a
# hook: an undetectable write is better than a guard that blocks the wrong ones.
#
# Paths under .geniro/state/tdd/ are exempt: the TDD cycle's own RED-phase
# state file is a documented exception written via its own mktemp + mv
# procedure (skills/_shared/tdd-cycle.md §State file contract).
#
# Per-project bypass:
#   .geniro/safety.json — { "allow_patterns": ["enforce-state-helper"] }
#
# Pattern ID: enforce-state-helper
#
# Design rationale: ARCHITECTURE.md §State Files

set -euo pipefail

# Consume stdin — REQUIRED first step for Claude Code hooks.
INPUT=$(cat)

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

if [ "$HAVE_JQ" = "1" ]; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null || echo "")
else
  TOOL_NAME=""
  FILE_PATH=""
fi

# A truncated/malformed payload makes jq fail on EVERY field it would extract
# from $INPUT, not just one — so TOOL_NAME and FILE_PATH both come back empty
# together, control never reaches a real Edit/Write/MultiEdit/NotebookEdit
# call, and the branch's own empty-FILE_PATH check further down would otherwise
# exit 0 on exactly the input class this scan exists for. (A well-formed
# payload with a valid first JSON object plus trailing garbage is NOT this case
# — jq emits the parsed value before erroring on the garbage, so
# TOOL_NAME/FILE_PATH still come back populated and the normal logic already
# handles it.)
# This same coarse scan is pure grep+sed and needs no jq, so it must run
# BEFORE, not below, the jq-missing fail-open branch further down — a
# canonical state path named in the raw text still blocks even when no
# structured parsing can run at all, instead of jq's absence being a free
# pass for every direct state-path write.
# Only the file-tool target fields are scanned: `command` is not among them,
# because this hook no longer matches Bash and a `.geniro/` path inside a shell
# string is as often prose as it is a write target.
# Mirrors file-protection.sh's identical hoisted scan.
if [ -z "$TOOL_NAME" ] && [ -z "$FILE_PATH" ]; then
  RAW_TARGETS=$(printf '%s' "$INPUT" \
    | grep -oE '"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' \
    | sed -E 's/^"[a-z_]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
  if printf '%s' "$RAW_TARGETS" | grep -qE '(^|/|[[:space:]])\.geniro/(state|planning|knowledge|instructions|actions|workflow)/|(^|/|[[:space:]])\.geniro/\.geniro-state\.json|(^|/|[[:space:]])\.geniro/safety\.json'; then
    if [ "$HAVE_JQ" = "1" ]; then
      echo "State-helper [enforce-state-helper] blocked [jqless-fallback]: the tool input names a canonical .geniro/ state path but the payload could not be parsed (tool_name and file_path both came back empty), so only a coarse raw-text check ran." >&2
    else
      echo "State-helper [enforce-state-helper] blocked [jqless-fallback]: the tool input names a canonical .geniro/ state path but jq is not installed, so only a coarse raw-text check ran." >&2
    fi
    exit 2
  fi
fi

# Fail open but LOUDLY if jq is missing: the raw-text scan above still ran,
# but everything past this point needs structured parsing (the file_path
# extraction and the safety.json allow-list), which jq's absence takes off the
# table.
if [ "$HAVE_JQ" = "0" ]; then
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so direct state-path writes are NOT being checked beyond the coarse raw-text scan above. Install jq to restore the guard."}\n'
  exit 0
fi

# Locate nearest .geniro/safety.json walking up from cwd.
find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.geniro/safety.json" ]; then
      echo "$dir/.geniro/safety.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

ALLOWED=""
SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
if [ -n "$SAFETY_FILE" ] && [ -f "$SAFETY_FILE" ]; then
  # allow_patterns entries name exact pattern IDs. The membership test below is a
  # substring probe over the space-joined list, so a single entry that CARRIES
  # whitespace ("harmless write-lockfile alsoharmless") would silently enable every ID
  # spelled inside it. Reject those at load rather than weaken the probe.
  ALLOWED=$(jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
fi

# The broad "enforce-state-helper" grant is applied per-branch, AFTER
# check_safety_json_write has had a chance to run on the actual write
# target(s) — see the Edit/Write and Bash branches below. It must NOT exit
# here, before that path-specific check: .geniro/safety.json disables every
# guard by pattern ID, so a write to IT stays gated on its own,
# separately-grantable "safety-json-edit" pattern even when the broad grant is
# present. (Measured 2026-08-10: with only "enforce-state-helper" allowed, a
# direct write to safety.json returned rc 0 through an early exit sitting
# here — the same grant meant to unblock ordinary state-file writes also let
# an agent rewrite the file that turns off every other guard in one Write.)

# .geniro/safety.json disables every guard by pattern ID — an agent that can
# freely overwrite it can self-grant any bypass in one Write, so it gets a
# gate of its own rather than riding on matches_state_path's generic T1-T3
# coverage (safety.json sits at .geniro/ top level, outside every guarded
# prefix). Kept as a SEPARATE pattern ID from "enforce-state-helper" on
# purpose: by the time this runs, the broad bypass above has already exited
# if granted, so this is the narrower, independently-grantable route.
# Legitimate user edits stay possible — allow_patterns is read from the
# file's CURRENT content before this check runs, so a human adds
# "safety-json-edit" to it directly (outside the agent, or after explicit
# approval) the same way every other pattern ID here is unlocked; that first
# grant just can't come from the agent overwriting the file itself.
#
# Collapse a path to the exact string the shell/filesystem treats as the
# target, before any prefix/tier regex runs against it: repeated slashes
# (`.geniro//x`), a `.` segment (`.geniro/./x`), and a trailing slash or run of
# them (`.geniro/x/`, `.geniro/x//`) all resolve to the SAME path a bare
# `.geniro/x` spelling does, and every equivalent spelling must decide
# identically or one of them is an open bypass (2026-08-09 audit #1/#2: a
# `/./` segment defeated both is_safety_json_path and matches_state_path).
# Looped to a fixed point so a comb of these in one path
# (`.geniro/./x//./`) fully collapses regardless of order — a single pass only
# shortens a run of 3+ slashes by one. Does NOT resolve `..`: every call site
# here treats a `..` segment as its own separate concern (reject or leave
# alone) rather than resolving it, and folding that in here would silently
# turn a rejection into a resolution.
# Duplicated verbatim in hooks/block-geniro-deletion.sh rather than sourced
# from lib/: a vendored install ships hooks/ without lib/, and a missing helper
# must never make either guard fail open.
# tests/hooks/path-normalize-matrix.sh feeds both guards every spelling above
# and asserts identical exit codes — a one-sided edit fails it.
_geniro_normalize_path() {
  local p="${1:-}"
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  # Collapse `//` and `/./` with prefix/suffix cuts, looped to a fixed point —
  # NOT ${p//pat/repl}: bash 3.2 (macOS /bin/bash) keeps the backslash of an
  # escaped `/` in the replacement, emitting `\/` into the result and silently
  # un-matching every guard pattern downstream (fails OPEN).
  while :; do
    case "$p" in
      *//*)  p="${p%%//*}/${p#*//}" ;;
      */./*) p="${p%%/./*}/${p#*/./}" ;;
      *) break ;;
    esac
  done
  while [ "${p%/.}" != "$p" ]; do p="${p%/.}"; done
  while [ "${p%/}" != "$p" ] && [ -n "${p%/}" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

# Pattern ID: safety-json-edit
is_safety_json_path() {
  local p
  p="$(_geniro_normalize_path "$1")"
  echo "$p" | grep -qE '(^|/)\.geniro/safety\.json$'
}

check_safety_json_write() {
  local path="$1"
  is_safety_json_path "$path" || return 0
  case " $ALLOWED " in
    *" safety-json-edit "*) return 0 ;;
  esac
  echo "State-helper [safety-json-edit] blocked: direct write to .geniro/safety.json — this file disables every guard by pattern ID, so an agent must not self-grant a bypass in one Write. To allow this, add \"safety-json-edit\" to allow_patterns in .geniro/safety.json." >&2
  exit 2
}

# Check if the path is a canonical state-file path (ARCHITECTURE.md §State Files).
# The (^|/) prefix in the patterns below matches both relative (.geniro/...) and
# absolute (/x/.geniro/...) forms.
matches_state_path() {
  local p="$1"
  # Collapse repeated slashes and `.` segments first: the protected-prefix
  # regexes below require an EXACT `.geniro/<tier>/` span, so a path built by
  # joining a variable that already ends in `/` (`.geniro//planning/foo/state.md`)
  # inserts a second `/` right where "planning" must start, and a `/./` segment
  # (`.geniro/./planning/foo/state.md`) inserts a segment the span doesn't
  # expect either — both silently fail the match without this.
  p="$(_geniro_normalize_path "$p")"
  # Plugin metadata file (T3 CRUD). Decided BEFORE the exclusions below: it is
  # the one guarded path whose basename is dot-prefixed, so the T1 scratch rule
  # would otherwise exempt it.
  if echo "$p" | grep -qE '(^|/)\.geniro/\.geniro-state\.json$'; then
    return 0
  fi
  # Exclusions — files under .geniro/ that are NOT frontmatter-bearing state
  # files and shouldn't trigger the helper warning:
  #   *.lock      — coordination locks (e.g., .geniro/planning/.codebase-map.lock)
  #   .fingerprint.json — pure JSON, no frontmatter
  #   *.tmp / *.tmp.PID.HOST — atomic-write temp files (helper's own intermediate
  #                            file before mv), generic .tmp suffix
  #   *.swp       — vim swap files
  #   *~          — emacs backup files
  #   *.pre-edit.bak — /geniro:actions edit-subcommand's own revert snapshot
  #                    (skills/actions/subcommand-edit.md §Snapshot): a `cp`
  #                    of the file being edited to a sibling backup, restored
  #                    via `mv` or removed via `rm -f` on every exit path —
  #                    not a canonical CRUD target another consumer reads
  #   T1 ephemeral scratch — any DOT-PREFIXED basename under .geniro/, plus the
  #     one undotted convention (notes.md) and the verification screenshot.
  #     Deliberately a rule, not a roster: the named T1 outputs (.kr-out.md,
  #     .ce-out.md, .tr-out.md, .research-out.md, .spec-challenge-out.md,
  #     .research-<facet>.md) are a fixed set only for the agents that ship
  #     today, while a run invents scratch names freely.
  #     A closed roster blocked one such name (.review-round1.md) six times in
  #     a single run (measured 2026-08-13) with no way for the run to learn the
  #     roster from the deny text. Dot-prefixed is the convention every T1
  #     output already follows, and no canonical state file uses it — state.md,
  #     spec.md, milestone-N.md, from-<producer>-<branch>.md and learnings.jsonl
  #     are all undotted, so the rule cannot swallow a durable file.
  if echo "$p" | grep -qE '\.lock$|/\.fingerprint\.json$|\.tmp(\.[^/]+)?$|\.swp$|~$|\.pre-edit\.bak$|/\.[^/]+$|/notes\.md$|/playwright-verify\.png$'; then
    return 1
  fi
  # T1, T2, T3 directories under .geniro/.
  if echo "$p" | grep -qE '(^|/)\.geniro/(state|planning|knowledge|instructions|actions|workflow)/'; then
    return 0
  fi
  return 1
}

# Match the right helper to the tier.
suggested_helper() {
  local p="$1"
  if echo "$p" | grep -qE '\.geniro/knowledge/.*\.jsonl$'; then
    echo "atomic_state_append"
  else
    echo "atomic_state_write"
  fi
}

# A path directly under .geniro/state/ that conforms to none of the canonical
# layouts is invisible to the validator and session-restore (ad-hoc schema-less
# files were observed in the wild). Recognized layouts:
#   state/<skill>/<slug>/state.md  ·  state/setup/state.md singleton
#   state/handoff/from-<producer>-<branch>.md  ·  state/tdd/state-<slug>.md
non_canonical_state_layout() {
  local p="$1"
  echo "$p" | grep -qE '(^|/)\.geniro/state/' || return 1
  if echo "$p" | grep -qE '(^|/)\.geniro/state/[^/]+/[^/]+/state\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/setup/state\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/handoff/from-[^/]+\.md$'; then return 1; fi
  if echo "$p" | grep -qE '(^|/)\.geniro/state/tdd/state-[^/]+\.md$'; then return 1; fi
  return 0
}

# Emit the block message for one matched state path, then exit 2 (block) or 0 (warn).
emit_state_helper_decision() {
  local path="$1"
  local helper
  helper=$(suggested_helper "$path")

  local prefix="State-helper [enforce-state-helper]"
  local body="Direct write blocked: $path is a canonical state path — writable, but only through \`$helper\`. This is a routing guard, not a denial: don't report the file as blocked or hand off a manual patch — route it below.
$prefix:   Route it:
$prefix:     source \"\${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh\"
$prefix:     $helper \"$path\" <<'EOF'
$prefix:     ...content...
$prefix:     EOF
$prefix:   Spec: skills/_shared/atomic-state-write.md"

  local layout_hint=""
  if non_canonical_state_layout "$path"; then
    layout_hint="$prefix:   This path under .geniro/state/ matches no canonical layout (state/<skill>/<slug>/state.md, the state/setup/state.md singleton, state/handoff/from-<producer>-<branch>.md, or state/tdd/state-<slug>.md) — ad-hoc files there are invisible to the validator and session-restore."
  fi

  echo "$prefix: $body" >&2
  [ -n "$layout_hint" ] && echo "$layout_hint" >&2
  echo "$prefix: Project bypass (rare — silences the guard, not the atomicity risk): add \"enforce-state-helper\" to allow_patterns in .geniro/safety.json." >&2
  exit 2
}

# ---- Edit/Write/MultiEdit branch ----
# FILE_PATH was already extracted above (needed there for the malformed-payload check).
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

check_safety_json_write "$FILE_PATH"

# The broad grant is applied HERE, after the narrower safety.json gate above
# has already had its say — see the comment on ALLOWED's earlier, now-removed
# early exit.
case " $ALLOWED " in
  *" enforce-state-helper "*) exit 0 ;;
esac

# A `..` segment makes the .geniro/state/tdd/ prefix a lie —
# `.geniro/state/tdd/../../planning/foo/state.md` carries the substring while
# resolving to a canonical state file outside it. Reject the traversal (fall
# through to matches_state_path below, no exemption) before the substring test
# runs, mirroring check_delete_arg's `*/../*` guard in block-geniro-deletion.sh.
case "/$FILE_PATH/" in
  */../*) ;;
  *.geniro/state/tdd/*) exit 0 ;;
esac

if ! matches_state_path "$FILE_PATH"; then
  exit 0
fi

emit_state_helper_decision "$FILE_PATH"
