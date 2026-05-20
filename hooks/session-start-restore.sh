#!/usr/bin/env bash
# session-start-restore.sh — SessionStart hook (matcher: "compact|resume|startup").
#
# Spec: architecture/M3-compaction-survival.md §5, §6, §8, §10.
#
# Responsibilities:
#   1. Read $SOURCE from input (compact|resume|startup|clear); exit 0 on clear.
#   2. Resolve the active T1 state file using the M1-canonical slug + frontmatter
#      `branch:` fallback (see §5 step 4 and skills/_shared/state-tier-spec.md §Slug rule).
#   3. Pre-flight validate via skills/_shared/validate-state-file.sh; if the helper
#      itself is missing (M1 PR-0 not landed), degrade gracefully with Block 4 notice.
#   4. Parse frontmatter — producer, spec-file, phase, non-resumable-actions[] count.
#   5. Assemble `additionalContext` from the ordered Block 1..6 set. Sub-blocks
#      5/5b/5c/5d land in later commits per the M3 split.
#   6. Emit `systemMessage` per §10 (suppressed on cold startup with no active task).
#
# Read-only guarantee (§5): this hook NEVER writes state.md. State writes are the
# consumer-skill's exclusive responsibility — keeps the hook idempotent across re-runs.

set -uo pipefail

# ---------------------------------------------------------------------------
# Input plumbing
# ---------------------------------------------------------------------------

INPUT=$(cat)

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" || true
fi

SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "compact"' 2>/dev/null || echo "compact")

# §3 — `clear` source: explicit user reset; no auto-reload.
if [ "$SOURCE" = "clear" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Branch + slug resolution (state-tier-spec.md §Slug rule)
# ---------------------------------------------------------------------------

branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "${branch:-}" ]; then
  branch="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

slug="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##' || true)"
if [ "${#slug}" -gt 60 ]; then
  _suffix="$(printf '%s' "$slug" | sha256sum | head -c 8)"
  slug="$(printf '%s' "$slug" | head -c 52)-${_suffix}"
fi

# ---------------------------------------------------------------------------
# Active T1 state-file resolution (§5 step 4)
# ---------------------------------------------------------------------------
#
# Layouts (state-tier-spec §Path roots):
#   A. .geniro/planning/<task-dir>/state.md       (multi-file task-bound — M4/M5)
#   B. .geniro/state/<skill>/<slug>/state.md      (session-bound — M7/M8/M9)
#   C. .geniro/state/<skill>/state.md             (singleton — M10a setup)
#
# Tier 1: direct slug-match within layouts A, B, plus singleton C.
# Tier 2: glob all candidate state.md files and grep frontmatter `branch:` field
#         (handles task-dirs that don't match the slug exactly).

state_file=""
task_dir=""

# Tier 1a — layout A (task-dir = slug)
if [ -n "$slug" ] && [ -f "./.geniro/planning/$slug/state.md" ]; then
  state_file="./.geniro/planning/$slug/state.md"
fi

# Tier 1b — layout B (session-bound skills)
if [ -z "$state_file" ] && [ -n "$slug" ]; then
  for _skill_dir in ./.geniro/state/*/; do
    [ -d "$_skill_dir" ] || continue
    _candidate="${_skill_dir}${slug}/state.md"
    if [ -f "$_candidate" ]; then
      state_file="$_candidate"
      break
    fi
  done
fi

# Tier 1c — layout C (singleton — currently only setup)
if [ -z "$state_file" ] && [ -f "./.geniro/state/setup/state.md" ]; then
  state_file="./.geniro/state/setup/state.md"
fi

# Tier 2 — frontmatter `branch:` field grep across all candidate state.md files.
# Iterates layouts A+B+C, with mtime tiebreak when multiple match.
_state_candidates() {
  {
    find ./.geniro/planning -maxdepth 2 -name 'state.md' -type f 2>/dev/null
    find ./.geniro/state -maxdepth 3 -name 'state.md' -type f 2>/dev/null
  } | while IFS= read -r p; do
    _mtime=$(stat -c %Y "$p" 2>/dev/null || stat -f %m "$p" 2>/dev/null)
    [ -n "$_mtime" ] && printf '%s %s\n' "$_mtime" "$p"
  done | sort -rn | cut -d' ' -f2-
}

# Extract `branch:` value from frontmatter (line-anchored, between first two `---` fences).
_fm_branch_of() {
  awk '
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && /^branch:/ {
      sub(/^branch:[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
      if ($0 ~ /^"[^"]*"$/ || $0 ~ /^\047[^\047]*\047$/) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$1" 2>/dev/null
}

if [ -z "$state_file" ]; then
  while IFS= read -r _candidate; do
    [ -z "$_candidate" ] && continue
    _fm_branch="$(_fm_branch_of "$_candidate")"
    if [ -n "$_fm_branch" ] && [ "$_fm_branch" = "$branch" ]; then
      state_file="$_candidate"
      break
    fi
  done <<EOF
$(_state_candidates)
EOF
fi

if [ -n "$state_file" ]; then
  task_dir="$(dirname "$state_file")"
fi

# ---------------------------------------------------------------------------
# Pre-flight validation (§5 step 5, §12)
# ---------------------------------------------------------------------------

validation_status="not-applicable"  # values: pass | fail | skipped | not-applicable
validation_error=""

if [ -n "$state_file" ]; then
  _vsf_helper="${CLAUDE_PLUGIN_ROOT:-.}/skills/_shared/validate-state-file.sh"
  if [ ! -f "$_vsf_helper" ]; then
    validation_status="skipped"
  else
    # shellcheck source=/dev/null
    if ! source "$_vsf_helper" 2>/dev/null; then
      validation_status="skipped"
    else
      # Capture stderr + exit code separately — exit code is the truth
      # signal. A future stderr-emitting helper update wouldn't accidentally
      # flip pass→fail.
      validation_error=$(validate_state_file "$state_file" 2>&1 >/dev/null)
      _vsf_rc=$?
      if [ "$_vsf_rc" -eq 0 ]; then
        validation_status="pass"
        validation_error=""
      else
        validation_status="fail"
        validation_error=$(printf '%s' "$validation_error" | head -n 1)
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Frontmatter parse (§5 step 6) — producer, spec-file, phase, list counts
# ---------------------------------------------------------------------------

active_skill=""
spec_file=""
phase=""
non_resumable_count=0

_fm_scalar() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      gsub(/[[:space:]]+$/, "")
      if ($0 ~ /^"[^"]*"$/ || $0 ~ /^\047[^\047]*\047$/) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$file" 2>/dev/null
}

# Count entries of a YAML block-list field. Returns 0 for absent, `[]`,
# or unparseable. Counts `- ` entries indented under the parent key.
# END block is the single print site — mid-stream conditions just set
# `done=1` and `exit` (awk runs END regardless of where exit is called).
_fm_block_list_count() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && $0 ~ "^" k ":[[:space:]]*\\[\\][[:space:]]*$" { exit 0 }
    in_fm && $0 ~ "^" k ":[[:space:]]*$" { in_list = 1; next }
    in_list && /^[a-zA-Z_][a-zA-Z0-9_-]*:/ { exit 0 }
    in_list && /^[[:space:]]+-[[:space:]]/ { c++ }
    END { print c+0 }
  ' "$file" 2>/dev/null
}

# Convert a YAML block-list field in frontmatter to JSONL on stdout.
# Each `- key: value` entry becomes one JSON object; nested fields
# (4-space indented) are merged into the same object until the next `-`.
# Returns empty output for absent or `[]` lists. Unquoted values are
# kept as strings; quoted values lose one balanced outer pair.
_fm_block_list_to_jsonl() {
  local file="$1" key="$2"
  awk -v k="$key" '
    function jesc(s,   t) {
      t = s
      gsub(/\\/, "\\\\", t)
      gsub(/"/, "\\\"", t)
      gsub(/\t/, "\\t", t)
      gsub(/\r/, "\\r", t)
      gsub(/\n/, "\\n", t)
      return t
    }
    function dequote(s) {
      if (s ~ /^"[^"]*"$/ || s ~ /^\047[^\047]*\047$/) {
        return substr(s, 2, length(s) - 2)
      }
      return s
    }
    function add_pair(line,   pos, kk, vv) {
      pos = index(line, ":")
      if (pos < 2) return
      kk = substr(line, 1, pos - 1)
      vv = substr(line, pos + 1)
      sub(/^[[:space:]]+/, "", vv)
      sub(/[[:space:]]+$/, "", vv)
      vv = dequote(vv)
      if (have == 0) {
        keynum = 0
        delete keys
        delete vals
        have = 1
      }
      keys[++keynum] = kk
      vals[kk] = vv
    }
    function flush(   i, out) {
      if (!have) return
      out = "{"
      for (i = 1; i <= keynum; i++) {
        if (i > 1) out = out ","
        out = out "\"" jesc(keys[i]) "\":\"" jesc(vals[keys[i]]) "\""
      }
      print out "}"
      have = 0
    }
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && $0 ~ "^" k ":[[:space:]]*\\[\\][[:space:]]*$" { exit 0 }
    in_fm && $0 ~ "^" k ":[[:space:]]*$" { in_list = 1; next }
    in_list && /^[a-zA-Z_][a-zA-Z0-9_-]*:/ { exit 0 }
    in_list && /^[[:space:]]+-[[:space:]]/ {
      flush()
      line = $0
      sub(/^[[:space:]]+-[[:space:]]+/, "", line)
      add_pair(line)
      next
    }
    in_list && /^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_-]*:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      add_pair(line)
      next
    }
    END { flush() }
  ' "$file" 2>/dev/null
}

# Render a non-resumable-actions JSONL stream into Block 5 bullet lines.
# Per §8: structured rendering for known action types, fallback for unknown.
_render_non_resumable_block() {
  jq -r '
    .action as $a
    | (.["completed-at"] // "?") as $c
    | if $a == "git-push" then
        "  - git-push (target: \(.target // "?"), ref: \(.ref // "?"), completed: \($c))"
      elif $a == "pr-comment-posted" then
        "  - pr-comment-posted (pr: \(.pr // "?"), comment-id: \(.["comment-id"] // "?"), completed: \($c))"
      elif $a == "slack-notify-sent" then
        "  - slack-notify-sent (channel: \(.channel // "?"), ts: \(.ts // "?"), completed: \($c))"
      elif $a == "release-tagged" then
        "  - release-tagged (tag: \(.tag // "?"), completed: \($c))"
      else
        "  - \($a) (completed: \($c))"
      end
  ' 2>/dev/null
}

# Convert a body YAML block-list section (e.g. `## Errors`) to JSONL.
# Body sections use indent-0 `- key: val` + indent-2 `key: val` continuations
# (distinct from frontmatter block-list which uses 2/4). Skips frontmatter
# entirely. Terminates at next `##` heading or EOF.
_body_section_to_jsonl() {
  local file="$1" section="$2"
  awk -v section="$section" '
    function jesc(s,   t) {
      t = s
      gsub(/\\/, "\\\\", t)
      gsub(/"/, "\\\"", t)
      gsub(/\t/, "\\t", t)
      gsub(/\r/, "\\r", t)
      gsub(/\n/, "\\n", t)
      return t
    }
    function dequote(s) {
      if (s ~ /^"[^"]*"$/ || s ~ /^\047[^\047]*\047$/) {
        return substr(s, 2, length(s) - 2)
      }
      return s
    }
    function add_pair(line,   pos, kk, vv) {
      pos = index(line, ":")
      if (pos < 2) return
      kk = substr(line, 1, pos - 1)
      vv = substr(line, pos + 1)
      sub(/^[[:space:]]+/, "", vv)
      sub(/[[:space:]]+$/, "", vv)
      vv = dequote(vv)
      if (have == 0) {
        keynum = 0
        delete keys
        delete vals
        have = 1
      }
      keys[++keynum] = kk
      vals[kk] = vv
    }
    function flush(   i, out) {
      if (!have) return
      out = "{"
      for (i = 1; i <= keynum; i++) {
        if (i > 1) out = out ","
        out = out "\"" jesc(keys[i]) "\":\"" jesc(vals[keys[i]]) "\""
      }
      print out "}"
      have = 0
    }
    NR == 1 && $0 != "---" { in_body = 1; next }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; in_body = 1; next }
    in_fm { next }
    in_body && $0 ~ "^## " section "[[:space:]]*$" { in_sect = 1; next }
    in_sect && /^## / { flush(); exit 0 }
    in_sect && /^-[[:space:]]/ {
      flush()
      line = $0
      sub(/^-[[:space:]]+/, "", line)
      add_pair(line)
      next
    }
    in_sect && /^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_-]*:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      add_pair(line)
      next
    }
    END { flush() }
  ' "$file" 2>/dev/null
}

# Render `## Errors` body section into Block 5b bullets.
# Filter: entries with `resolved: "true"` are excluded; default (missing field) renders.
_render_errors_block() {
  jq -r '
    if .resolved == "true" then empty
    else
      "  - \(.ts // "?") · \(.tool // "?") `\(.detail // "")` failed: \(.error // "(no error message)")\n      attempted_fix: \(.attempted_fix // "?") — did NOT resolve"
    end
  ' 2>/dev/null
}

# Render `## Open Questions` body section into Block 5c bullets.
_render_open_questions_block() {
  jq -r '
    if .resolved == "true" then empty
    else "  - \"\(.question // "?")\""
    end
  ' 2>/dev/null
}

# Render frontmatter `approvals[]` into Block 5d bullets.
# No filter — producer controls which categories persist (M3 §6 Block 5d).
_render_approvals_block() {
  jq -r '
    "  - [\(.category // "?")] User picked: \"\(.picked // "?")\"\n      (asked в phase: \(.asked_in_phase // "?") · at: \(.at // "?"))"
  ' 2>/dev/null
}

if [ -n "$state_file" ] && [ -f "$state_file" ]; then
  active_skill="$(_fm_scalar "$state_file" producer)"
  spec_file="$(_fm_scalar "$state_file" spec-file)"
  phase="$(_fm_scalar "$state_file" phase)"
  non_resumable_count="$(_fm_block_list_count "$state_file" non-resumable-actions)"
  [ -z "$non_resumable_count" ] && non_resumable_count=0
fi

# ---------------------------------------------------------------------------
# LOAD_TIER for active skill (used in Block 6 resume protocol)
# ---------------------------------------------------------------------------

case "$active_skill" in
  implement|plan|review|debug|refactor|decompose|follow-up|deep-simplify)
    load_tier="pipeline"
    ;;
  *)
    load_tier="rules-only"
    ;;
esac

# ---------------------------------------------------------------------------
# additionalContext assembly (§6)
# ---------------------------------------------------------------------------

# Block 1 — source-phrased prefix. §3 line 92: the `startup` phrasing
# "Active task detected" applies **only if active task found**; cold-startup
# (no state.md) gets а distinct phrasing per §3 line 95.
case "$SOURCE" in
  compact) _prefix="Context was compressed by compaction (SessionStart source: compact)." ;;
  resume)  _prefix="Restoring from prior session (SessionStart source: resume)." ;;
  startup)
    if [ -n "$state_file" ]; then
      _prefix="Active task detected at startup (SessionStart source: startup)."
    else
      _prefix="Geniro plugin active at startup — no in-flight task (SessionStart source: startup)."
    fi
    ;;
  *)       _prefix="Restoring Geniro context (SessionStart source: $SOURCE)." ;;
esac

BLOCK1="$_prefix
SKILL.md instructions and conversation nuance may have been lost — re-read these
files before continuing (the .geniro/instructions/* entries route through the
canonical loader, NOT direct cwd Reads; CLAUDE.md, .geniro/planning/_FEATURES.md,
spec/plan files remain direct Reads):"

# Block 2 — suggested files. State.md pointer is suppressed when validation
# failed (§6 last paragraph of Block 3). Spec.md and plan.md remain pointers.
BLOCK2="- CLAUDE.md
- .geniro/planning/_FEATURES.md
- .geniro/instructions/global.md            (loader-routed, MODE: refresh)
- .geniro/instructions/code-style.md        (loader-routed, MODE: refresh)
- .geniro/instructions/user-preferences.md  (loader-routed, MODE: refresh)"

if [ -n "$active_skill" ]; then
  BLOCK2="$BLOCK2
- .geniro/instructions/$active_skill.md (loader-routed, MODE: refresh)"
fi

if [ -n "$state_file" ] && [ "$validation_status" != "fail" ]; then
  BLOCK2="$BLOCK2
- $state_file"
fi

if [ -n "$spec_file" ]; then
  BLOCK2="$BLOCK2
- $spec_file"
elif [ -n "$task_dir" ] && [ -f "$task_dir/spec.md" ]; then
  BLOCK2="$BLOCK2
- $task_dir/spec.md"
fi

if [ -n "$task_dir" ] && [ -f "$task_dir/plan.md" ]; then
  BLOCK2="$BLOCK2
- $task_dir/plan.md"
fi

# Block 3 — validation-failure recovery.
BLOCK3=""
if [ "$validation_status" = "fail" ]; then
  BLOCK3="⚠️ STATE FILE FAILED VALIDATION
State file at $state_file failed validation: $validation_error.
Do NOT resume from it.
On next turn, fire AskUserQuestion with the M1 recovery options:
  1. Delete state file and restart skill from spec   (lose in-flight state)
  2. Open file in editor and fix manually            (skill pauses; retry validation)
  3. Skip validation and continue (emergency)        (risk: silent corruption)
After user picks, follow the validation-helper recovery flow in M1 §Validation
helper. Suppress all state.md Reads below — pointer was withheld for safety."
fi

# Block 4 — M1 helper-missing notice.
BLOCK4=""
if [ "$validation_status" = "skipped" ]; then
  BLOCK4="⚠️ M1 helpers not installed — validation skipped.
The state.md file was NOT validated by validate_state_file (M1 PR-0 has
not landed yet). Treat resumed state with caution — confirm 'phase:' and
'status:' fields look sane before continuing."
fi

# Block 5 — non-resumable-actions warning. Renders structured entries per §8.
# §6 Block 3: when validation fails, suppress all state.md-derived blocks
# (5/5b/5c/5d). Their contents may be partially trusted; the recovery AUQ
# must run first.
BLOCK5=""
if [ -n "$state_file" ] && [ "$validation_status" != "fail" ] && [ "$non_resumable_count" -gt 0 ]; then
  _rendered=$(_fm_block_list_to_jsonl "$state_file" non-resumable-actions \
    | _render_non_resumable_block)
  if [ -n "$_rendered" ]; then
    BLOCK5="⚠️ ALREADY COMPLETED in prior turns — DO NOT repeat:
$_rendered
Resuming should re-validate code state but MUST NOT re-trigger these actions.
If a re-trigger is genuinely required (e.g., rebase + re-push), explicitly
acknowledge in your next message before performing it."
  fi
fi

# Block 5b — Last-known errors from state.md `## Errors` body section.
# Per P-M3-1: surface unresolved errors so the model doesn't repeat the
# same approach after compaction.
BLOCK5B=""
if [ -n "$state_file" ] && [ "$validation_status" != "fail" ]; then
  _errors_rendered=$(_body_section_to_jsonl "$state_file" "Errors" \
    | _render_errors_block)
  if [ -n "$_errors_rendered" ]; then
    BLOCK5B="⚠️ ERRORS ENCOUNTERED IN PRIOR TURNS — do not repeat the same approach:
$_errors_rendered
Consider a fundamentally different approach or escalate per M4 §6.3 (Phase 2)
or §7.4 (Phase 3)."
  fi
fi

# Block 5c — Open questions from state.md `## Open Questions` body section.
# Per P-M3-1: pending user-facing questions surface as AUQ-FIRST directive.
BLOCK5C=""
if [ -n "$state_file" ] && [ "$validation_status" != "fail" ]; then
  _oq_rendered=$(_body_section_to_jsonl "$state_file" "Open Questions" \
    | _render_open_questions_block)
  if [ -n "$_oq_rendered" ]; then
    BLOCK5C="❓ PENDING QUESTIONS FROM PRIOR TURN — ask user before continuing:
$_oq_rendered
Open Question Protocol: surface these via AskUserQuestion as your FIRST action
this turn. Do not advance pipeline phase until resolved."
  fi
fi

# Block 5d — Persisted approvals from frontmatter `approvals[]`.
# Per P-M3-2 (depends on P-M1-1): one-time user picks surface so the model
# doesn't re-ask after compaction. Producer decides which categories persist;
# the hook just renders what's there.
BLOCK5D=""
if [ -n "$state_file" ] && [ "$validation_status" != "fail" ]; then
  _approvals_count=$(_fm_block_list_count "$state_file" approvals)
  if [ -n "$_approvals_count" ] && [ "$_approvals_count" -gt 0 ]; then
    _approvals_rendered=$(_fm_block_list_to_jsonl "$state_file" approvals \
      | _render_approvals_block)
    if [ -n "$_approvals_rendered" ]; then
      BLOCK5D="✓ DECISIONS ALREADY MADE in prior turns — do NOT re-ask:
$_approvals_rendered
Use these picked values directly. Only re-ask if context has materially
changed (e.g., spec file deleted, branch switched) — explicitly acknowledge
the re-ask in your next message."
    fi
  fi
fi

# Block 6 — resume protocol. Per §3 line 95 the cold-startup branch
# (no active task) emits no "active task" block — i.e., the 7-step
# resume protocol is suppressed entirely. Loader-refresh advice still
# matters, so we emit а trimmed 1-step block in that case.
BLOCK6=""
if [ -n "$state_file" ]; then
  if [ -n "$active_skill" ]; then
    _step2="2. Re-invoke the canonical instruction loader at
   \${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md
   with SKILL_SLUG: $active_skill, LOAD_TIER: $load_tier, MODE: refresh.
   The helper's Echo contract makes the re-Read user-visible."
    _step3="3. Invoke load-semantic with MODE: refresh:
   \${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-semantic.md (MODE: refresh).
   Fingerprint drift check fires; if drift detected, soft notice surfaces."
  else
    _step2="2. Re-invoke the canonical instruction loader at
   \${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md
   with SKILL_SLUG: <active-skill>, LOAD_TIER: rules-only, MODE: refresh.
   The helper's Echo contract makes the re-Read user-visible."
    _step3="3. (load-semantic refresh skipped — no active skill detected; invoke on demand if a phase explicitly needs the L3 module map.)"
  fi

  BLOCK6="Resume steps:
1. Read the current skill's SKILL.md to restore phase instructions.
$_step2
$_step3
4. Read state.md (if not suppressed by Block 3) to identify the current phase.
5. Read spec.md and plan.md (if present) for task context.
6. If a feature ID is set in state.md, read the .geniro/planning/_FEATURES.md row and the linked spec.
7. Continue from the next incomplete phase."
fi

# ---------------------------------------------------------------------------
# Concatenate blocks (omit empty ones, blank line between blocks)
# ---------------------------------------------------------------------------

_append_block() {
  local block="$1"
  [ -z "$block" ] && return 0
  if [ -z "$ADDITIONAL_CONTEXT" ]; then
    ADDITIONAL_CONTEXT="$block"
  else
    ADDITIONAL_CONTEXT="$ADDITIONAL_CONTEXT

$block"
  fi
}

ADDITIONAL_CONTEXT=""
_append_block "$BLOCK1"
_append_block "$BLOCK2"
_append_block "$BLOCK3"
_append_block "$BLOCK4"
_append_block "$BLOCK5"
_append_block "$BLOCK5B"
_append_block "$BLOCK5C"
_append_block "$BLOCK5D"
_append_block "$BLOCK6"

# ---------------------------------------------------------------------------
# systemMessage (§10)
# ---------------------------------------------------------------------------

_active_label="none"
_phase_label="—"
if [ -n "$task_dir" ]; then
  _active_label="$(basename "$task_dir")"
fi
if [ -n "$phase" ]; then
  _phase_label="$phase"
fi

SYSTEM_MESSAGE="Geniro: restoring context (source: $SOURCE, active: $_active_label · phase: $_phase_label · non-resumable: $non_resumable_count)"

# Suppression rule: cold startup with no active task → no systemMessage spam.
emit_system_message=true
if [ "$SOURCE" = "startup" ] && [ -z "$state_file" ]; then
  emit_system_message=false
fi

# ---------------------------------------------------------------------------
# Emit JSON output
# ---------------------------------------------------------------------------

if [ "$emit_system_message" = "true" ]; then
  OUTPUT=$(jq -n \
    --arg ac "$ADDITIONAL_CONTEXT" \
    --arg sm "$SYSTEM_MESSAGE" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $ac
      },
      systemMessage: $sm
    }')
else
  OUTPUT=$(jq -n \
    --arg ac "$ADDITIONAL_CONTEXT" \
    '{
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $ac
      }
    }')
fi

printf '%s\n' "$OUTPUT"
exit 0
