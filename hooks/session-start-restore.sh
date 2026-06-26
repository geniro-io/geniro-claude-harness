#!/usr/bin/env bash
# session-start-restore.sh — SessionStart hook (matcher: "compact|resume|startup").
#
# Responsibilities:
#   1. Read $SOURCE from input (compact|resume|startup|clear); exit 0 on clear.
#   2. Resolve the active T1.5 state file using the canonical slug + frontmatter
#      `branch:` fallback (see skills/_shared/state-tier-spec.md Slug rule).
#   3. Pre-flight validate via lib/validate-state-file.sh; if the helper
#      itself is missing, degrade gracefully with Block 4 notice.
#   4. Parse frontmatter — producer, spec-file, phase, non-resumable-actions[] count.
#   5. Assemble `additionalContext` from the ordered Block 1..6 set.
#   6. Emit `systemMessage` (suppressed on cold startup with no active task).
#
# Read-only guarantee: this hook NEVER writes state.md. State writes are the
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

# Source the canonical repo-root resolver. Cross-session reads/writes
# (state.md restoration, learnings auto-archive) must land in the PRIMARY
# worktree even when the orchestrator sits in a linked worktree; the helper
# enforces that. If the helper is missing (vendored install without lib/),
# fall back to a cwd-relative resolution to keep the hook running.
_geniro_root_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/repo-root.sh"
if [ -f "$_geniro_root_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_root_helper" 2>/dev/null || true
fi
if ! command -v _geniro_repo_root >/dev/null 2>&1; then
  _geniro_repo_root() { echo "${PWD:-.}"; }
fi
GENIRO_ROOT="$(_geniro_repo_root)"

# Resolve where L4 custom instructions load from — an external override
# (GENIRO_INSTRUCTIONS_DIR / the plugin's instructions_dir option) means
# they live outside the repo, which the post-compaction re-read must know.
# The helper lives in repo-root.sh (sourced above); fall back to the in-repo
# default when it is missing on a vendored install.
if declare -f _geniro_instructions_dir >/dev/null 2>&1; then
  INSTR_DIR="$(_geniro_instructions_dir)"
else
  INSTR_DIR="$GENIRO_ROOT/.geniro/instructions"
fi

# Portable SHA-256 resolver. Stock macOS ships `shasum` but not `sha256sum`;
# a bare `sha256sum` would fail silently and yield empty slug suffixes / hash
# markers. Source the canonical helper, falling back to an inline definition
# so the hook stays self-contained on vendored installs.
_geniro_hash_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/hash.sh"
if [ -f "$_geniro_hash_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_hash_helper" 2>/dev/null || true
fi
if ! command -v _geniro_sha256 >/dev/null 2>&1; then
  _geniro_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
fi

# Branch -> slug derivation, single-sourced in lib/branch-slug.sh so this hook and
# the sibling enforce-tdd-order.sh compute an identical slug from a branch name (a
# divergent form misses the producer's state file on every >60-char branch). Inline
# fallback keeps the hook self-contained on a vendored install without lib/.
_geniro_slug_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/branch-slug.sh"
if [ -f "$_geniro_slug_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_slug_helper" 2>/dev/null || true
fi
if ! command -v _geniro_branch_slug >/dev/null 2>&1; then
  _geniro_branch_slug() {
    local b="${1:-}"
    if [ -z "$b" ]; then
      b="$(git branch --show-current 2>/dev/null || true)"
      [ -z "$b" ] && b="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    fi
    local s
    s="$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##' || true)"
    s="${s:0:60}"
    printf '%s' "${s%-}"
  }
fi

# Find the nearest .geniro/safety.json walking up from cwd. Mirrors
# file-protection.sh / block-dangerous-git.sh so the auto-archive opt-out is
# honored regardless of cwd depth (a single cwd-relative check misses the
# opt-out from any subdirectory or linked worktree).
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

SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "compact"' 2>/dev/null || echo "compact")

# `clear` source: explicit user reset; no auto-reload.
if [ "$SOURCE" = "clear" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Branch + slug resolution — canonical rule lives in
# within-skill-state-handoff.md §Slug rules (state-tier-spec.md §Slug rule
# delegates to it). The truncation MUST match the producers byte-for-byte, or
# the Tier-1 direct-path match below cannot find the file they wrote.
# ---------------------------------------------------------------------------

branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "${branch:-}" ]; then
  branch="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

slug="$(_geniro_branch_slug "$branch")"

# ---------------------------------------------------------------------------
# Terminal-state sets + candidate filter
# ---------------------------------------------------------------------------
#
# A finished task's state.md is durable (T1.5 — retained after Ship), so
# resolution must SKIP terminal candidates rather than discard the final pick:
# a done /plan task-dir at Tier 1a would otherwise shadow an in-flight /debug
# slug dir on the same branch (Tier 1b/2) and the live task would silently not
# be restored.
#
# Completion is carried primarily by `phase:` — implement/plan/refactor/onboard/
# investigate leave `status: in-progress` even at their terminal phase and mark
# done via `phase:` alone. `status:` is the coarse fallback (setup/debug/review
# advance it; it also absorbs model-drift values like `completed`, which is not
# in the documented in-progress|done|failed enum but was observed in the wild).
# Bare `escalated` (review's terminal phase) is terminal; the membership test
# is whole-word (space-padded `case` match), so the hyphenated `*-escalated`
# paused phases (verify-escalated, phase-2-escalated, ...) do NOT match it —
# they represent in-flight work waiting on the user and must still resume.
TERMINAL_PHASES="done aborted routed failed escalated ship-committed-only self-review-only debug-handoff ship-summary-only adversarial-aborted verify-summary-only reverted adr-documented map-truncated present-summary-only"
TERMINAL_STATUSES="done completed failed aborted routed"

# Extract one scalar frontmatter value (line-anchored, between the first two
# `---` fences; strips one layer of surrounding quotes). One parse shape for
# branch / phase / status during resolution.
_fm_scalar_quick() {
  awk -v key="$2" '
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && $0 ~ "^" key ":" {
      sub("^" key ":[[:space:]]*", "")
      gsub(/[[:space:]]+$/, "")
      if ($0 ~ /^"[^"]*"$/ || $0 ~ /^\047[^\047]*\047$/) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$1" 2>/dev/null
}

_is_terminal_candidate() {
  local _f="$1" _p _s
  _p="$(_fm_scalar_quick "$_f" phase)"
  _s="$(_fm_scalar_quick "$_f" status)"
  if [ -n "$_p" ]; then
    case " $TERMINAL_PHASES " in *" $_p "*) return 0 ;; esac
  fi
  if [ -n "$_s" ]; then
    case " $TERMINAL_STATUSES " in *" $_s "*) return 0 ;; esac
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Active T1.5 state-file resolution
# ---------------------------------------------------------------------------
#
# Layouts (state-tier-spec Path roots):
#   A. .geniro/planning/<task-dir>/state.md       (multi-file task-bound)
#   B. .geniro/state/<skill>/<slug>/state.md      (session-bound)
#   C. .geniro/state/<skill>/state.md             (singleton — setup)
#
# Tier 1: direct slug-match within layouts A, B, plus singleton C.
# Tier 2: glob all candidate state.md files and grep frontmatter `branch:` field
#         (handles task-dirs that don't match the slug exactly).

state_file=""
task_dir=""

# Tier 1a — layout A (task-dir = slug). Terminal candidates are skipped so a
# finished task here cannot shadow an in-flight Tier 1b/2 candidate.
if [ -n "$slug" ] && [ -f "./.geniro/planning/$slug/state.md" ] \
   && ! _is_terminal_candidate "./.geniro/planning/$slug/state.md"; then
  state_file="./.geniro/planning/$slug/state.md"
fi

# Tier 1b — layout B (session-bound skills)
if [ -z "$state_file" ] && [ -n "$slug" ]; then
  for _skill_dir in ./.geniro/state/*/; do
    [ -d "$_skill_dir" ] || continue
    _candidate="${_skill_dir}${slug}/state.md"
    if [ -f "$_candidate" ] && ! _is_terminal_candidate "$_candidate"; then
      state_file="$_candidate"
      break
    fi
  done
fi

# Tier 1c — layout C (singleton — currently only setup). Resolved against the
# primary worktree via the repo-root helper — /setup writes its singleton in
# the project root and a linked-worktree session must restore from there.
if [ -z "$state_file" ] && [ -f "$GENIRO_ROOT/.geniro/state/setup/state.md" ] \
   && ! _is_terminal_candidate "$GENIRO_ROOT/.geniro/state/setup/state.md"; then
  state_file="$GENIRO_ROOT/.geniro/state/setup/state.md"
fi

# Tier 2 — frontmatter `branch:` field grep across all candidate state.md files.
# Iterates layouts A+B+C, with mtime tiebreak when multiple match. Scans both
# cwd-relative paths (covers task-local state.md per primary-worktree.md
# §"Artifacts NOT in scope") AND $GENIRO_ROOT-rooted singleton/cross-session
# state (covers /setup state.md plus any future singleton layouts). Dedup by
# absolute path so the cwd-IS-primary case doesn't double-count.
#
# Staleness gate (Tier 2 ONLY): Tier 1 is an exact slug/path match — a strong
# signal the user is actively on this task's branch — so it is never gated. Tier 2
# matches only on the recorded `branch:` field, a far weaker signal: a `/plan` run
# is authored on `main` (the feature branch is cut later, at /implement) and so
# records `branch: main`; left at a non-terminal phase it would otherwise
# resurface on EVERY future `main` session indefinitely. So skip a Tier-2
# candidate whose state file has not been touched within the cutoff window. Uses
# file mtime (already read portably here for the mtime tiebreak) rather than the
# frontmatter `timestamp:`, which is producer-written and sometimes a rounded
# placeholder. Set GENIRO_RESUME_STALE_DAYS=0 to disable the gate (always resume).
_state_candidates() {
  {
    find ./.geniro/planning -maxdepth 2 -name 'state.md' -type f 2>/dev/null
    find ./.geniro/state -maxdepth 3 -name 'state.md' -type f 2>/dev/null
    if [ "$GENIRO_ROOT" != "." ] && [ "$GENIRO_ROOT" != "$PWD" ]; then
      find "$GENIRO_ROOT/.geniro/state" -maxdepth 3 -name 'state.md' -type f 2>/dev/null
    fi
  } | awk '!seen[$0]++' | while IFS= read -r p; do
    _mtime=$(stat -c %Y "$p" 2>/dev/null || stat -f %m "$p" 2>/dev/null)
    [ -n "$_mtime" ] && printf '%s %s\n' "$_mtime" "$p"
  done | sort -rn | cut -d' ' -f2-
}

# Frontmatter `branch:` extraction shares _fm_scalar_quick (defined with the
# terminal-candidate filter above) — one parse shape for branch/phase/status.

if [ -z "$state_file" ]; then
  _resume_stale_days="${GENIRO_RESUME_STALE_DAYS:-14}"
  case "$_resume_stale_days" in ''|*[!0-9]*) _resume_stale_days=14 ;; esac
  _now_epoch=$(date +%s 2>/dev/null || echo 0)
  _stale_cutoff_secs=$(( _resume_stale_days * 86400 ))

  while IFS= read -r _candidate; do
    [ -z "$_candidate" ] && continue
    _fm_branch="$(_fm_scalar_quick "$_candidate" branch)"
    if [ -n "$_fm_branch" ] && [ "$_fm_branch" = "$branch" ] \
       && ! _is_terminal_candidate "$_candidate"; then
      # Staleness gate — skip a branch-matched candidate untouched past the
      # cutoff so an abandoned task on a long-lived branch (typically a /plan
      # left on `main`) stops resurfacing. Fail-open: a failed `date`/`stat`
      # (epoch 0) leaves the candidate eligible.
      if [ "$_resume_stale_days" -gt 0 ] && [ "$_now_epoch" -gt 0 ]; then
        _cand_mtime=$(stat -c %Y "$_candidate" 2>/dev/null || stat -f %m "$_candidate" 2>/dev/null || echo 0)
        if [ "$_cand_mtime" -gt 0 ] && [ "$(( _now_epoch - _cand_mtime ))" -gt "$_stale_cutoff_secs" ]; then
          continue
        fi
      fi
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
# Pre-flight validation
# ---------------------------------------------------------------------------

validation_status="not-applicable"  # values: pass | fail | skipped | not-applicable
validation_error=""

if [ -n "$state_file" ]; then
  _vsf_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/validate-state-file.sh"
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
# Frontmatter parse — producer, spec-file, phase, list counts
# ---------------------------------------------------------------------------

active_skill=""
spec_file=""
phase=""
status=""
recorded_branch=""
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
# Structured rendering for known action types, fallback for unknown.
_render_non_resumable_block() {
  jq -rR 'fromjson? // empty
    | .action as $a
    | (.["completed-at"] // "?") as $c
    | if $a == "git-push" then
        "  - git-push (target: \(.target // "?"), ref: \(.ref // "?"), completed: \($c))"
      elif $a == "pr-created" then
        "  - pr-created (pr: \(.pr // "?"), url: \(.url // "?"), completed: \($c))"
      elif $a == "pr-comment-posted" then
        "  - pr-comment-posted (pr: \(.pr // "?"), comment-id: \(.["comment-id"] // "?"), completed: \($c))"
      elif $a == "slack-notify-sent" then
        "  - slack-notify-sent (channel: \(.channel // "?"), ts: \(.ts // "?"), completed: \($c))"
      elif $a == "release-tagged" then
        "  - release-tagged (tag: \(.tag // "?"), completed: \($c))"
      elif $a == "git-commit" then
        "  - git-commit (commit-sha: \(.["commit-sha"] // "?"), completed: \($c))"
      elif $a == "pr-review-comment-batch" then
        "  - pr-review-comment-batch (pr: \(.["pr-ref"] // "?"), finding-count: \(.["finding-count"] // "?"), completed: \($c))"
      elif $a == "pr-comment-amended" then
        "  - pr-comment-amended (pr: \(.["pr-ref"] // "?"), comment-id: \(.["comment-id"] // "?"), kind: \(.kind // "?"), completed: \($c)) — a posted PR comment was already edited/withdrawn; do not repeat"
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
# Filter: resolved entries are excluded — legacy `resolved: "true"` OR canonical
# `status: resolved|wontfix`; default (neither set) renders.
_render_errors_block() {
  jq -rR 'fromjson? // empty
    | if (.resolved == "true") or (.status == "resolved") or (.status == "wontfix") then empty
    else
      "  - \(.ts // "?") · \(.tool // "?") `\(.detail // "")` failed: \(.error // "(no error message)")\n      attempted_fix: \(.attempted_fix // "?") — did NOT resolve"
    end
  ' 2>/dev/null
}

# Render `## Open Questions` body section into Block 5c bullets.
_render_open_questions_block() {
  jq -rR 'fromjson? // empty
    | if (.resolved == "true") or (.status == "resolved") or (.status == "wontfix") then empty
    else "  - \"\(.question // "?")\""
    end
  ' 2>/dev/null
}

# Render frontmatter `approvals[]` into Block 5d bullets.
# No filter — producer controls which categories persist.
_render_approvals_block() {
  jq -rR 'fromjson? // empty
    | "  - [\(.category // "?")] User picked: \"\(.picked // "?")\"\n      (asked in phase: \(.asked_in_phase // "?") · at: \(.at // "?"))"
  ' 2>/dev/null
}

if [ -n "$state_file" ] && [ -f "$state_file" ]; then
  active_skill="$(_fm_scalar "$state_file" producer)"
  spec_file="$(_fm_scalar "$state_file" spec-file)"
  phase="$(_fm_scalar "$state_file" phase)"
  status="$(_fm_scalar "$state_file" status)"
  recorded_branch="$(_fm_scalar "$state_file" branch)"
  non_resumable_count="$(_fm_block_list_count "$state_file" non-resumable-actions)"
  [ -z "$non_resumable_count" ] && non_resumable_count=0
fi

# ---------------------------------------------------------------------------
# Terminal-state gate
# ---------------------------------------------------------------------------
#
# A resolved state.md whose task already finished must NOT be surfaced as
# resumable — otherwise a fresh session (e.g. opened to run /update) re-opens a
# completed task and the orchestrator announces a bogus "resume".
#
# Resolution already skips terminal candidates (_is_terminal_candidate, defined
# with the terminal sets near the top), so this gate is a defense-in-depth net:
# it re-checks the values parsed by the main frontmatter pass and clears the
# task so every downstream block falls through to the cold-startup path.

if [ -n "$state_file" ]; then
  _is_terminal=false
  if [ -n "$phase" ]; then
    case " $TERMINAL_PHASES " in *" $phase "*) _is_terminal=true ;; esac
  fi
  if [ "$_is_terminal" = false ] && [ -n "$status" ]; then
    case " $TERMINAL_STATUSES " in *" $status "*) _is_terminal=true ;; esac
  fi
  if [ "$_is_terminal" = true ]; then
    state_file=""
    task_dir=""
    active_skill=""
    spec_file=""
    phase=""
    status=""
    recorded_branch=""
    non_resumable_count=0
    validation_status="not-applicable"
    validation_error=""
  fi
fi

# ---------------------------------------------------------------------------
# LOAD_TIER for active skill (used in Block 6 resume protocol)
# ---------------------------------------------------------------------------

case "$active_skill" in
  implement|plan|review|debug|refactor)
    load_tier="pipeline"
    ;;
  *)
    load_tier="rules-only"
    ;;
esac

# ---------------------------------------------------------------------------
# additionalContext assembly
# ---------------------------------------------------------------------------

# Block 1 — source-phrased prefix. The `startup` phrasing
# "Active task detected" applies **only if active task found**; cold-startup
# (no state.md) gets a distinct phrasing.
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

# When custom instructions resolve to an external directory (set via
# GENIRO_INSTRUCTIONS_DIR or the plugin's instructions_dir option), the loader
# reads them from outside the repo — the re-read must know where, since the
# default .geniro/instructions/ path no longer holds them.
if [ "$INSTR_DIR" != "$GENIRO_ROOT/.geniro/instructions" ]; then
  BLOCK1="$BLOCK1
Custom instructions load from an external directory: $INSTR_DIR (set via GENIRO_INSTRUCTIONS_DIR or the plugin's instructions_dir option) — the loader reads them from there, not from .geniro/instructions/."
fi

# Block 1b — standing behavioral contracts. File pointers survive compaction but
# the behavioral rules drop silently; re-assert them whenever a Geniro task is
# in flight so the orchestrator does not bypass write discipline or ship gates.
BLOCK1B=""
if [ -n "$active_skill" ]; then
  BLOCK1B="Standing rules for this in-flight task (re-asserted because compaction
drops them while keeping file pointers):
- State files under .geniro/ are written through the atomic-write helper
  (atomic_state_write / atomic_state_append, called from Bash) — never a direct
  Edit or Write, and never shell redirection (> / >> / tee). A hook now blocks
  both routes, so reach for the helper.
- Every outward-facing action — git push (including pushing to a feature branch
  that has an open PR), opening a pull request, posting a PR comment, posting a
  tracker comment — needs its own explicit approval in THIS session, or a
  recorded approval already saved in the state file's decisions. An earlier
  \"apply the fixes\" pick means work to do, not permission to ship. Handoffs
  carry work, not authority.
- Skills that produce reports (/geniro:review, /geniro:debug, /geniro:refactor,
  /geniro:investigate) never push code or open pull requests. If the restored
  plan looks like it wants one to, re-read that skill's SKILL.md before acting."
fi

# Block 2 — suggested files. State.md pointer is suppressed when validation
# failed (Block 3). Spec.md and plan.md remain pointers.
BLOCK2="- CLAUDE.md
- .geniro/planning/_FEATURES.md
- .geniro/instructions/global.md            (loader-routed, MODE: refresh)
- .geniro/instructions/code-style.md        (loader-routed, MODE: refresh)"

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
On next turn, fire AskUserQuestion with the recovery options:
  1. Delete state file and restart skill from spec   (lose in-flight state)
  2. Open file in editor and fix manually            (skill pauses; retry validation)
  3. Skip validation and continue (emergency)        (risk: silent corruption)
After user picks, follow the validation-helper recovery flow.
Suppress all state.md Reads below — pointer was withheld for safety."
fi

# Block 4 — helper-missing notice.
BLOCK4=""
if [ "$validation_status" = "skipped" ]; then
  BLOCK4="⚠️ Helpers not installed — validation skipped.
The state.md file was NOT validated by validate_state_file (required helpers have
not landed yet). Treat resumed state with caution — confirm 'phase:' and
'status:' fields look sane before continuing."
fi

# Block 5 — non-resumable-actions warning. Renders structured entries.
# When validation fails, suppress all state.md-derived blocks
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
# Surface unresolved errors so the model doesn't repeat the
# same approach after compaction.
BLOCK5B=""
if [ -n "$state_file" ] && [ "$validation_status" != "fail" ]; then
  _errors_rendered=$(_body_section_to_jsonl "$state_file" "Errors" \
    | _render_errors_block)
  if [ -n "$_errors_rendered" ]; then
    BLOCK5B="⚠️ ERRORS ENCOUNTERED IN PRIOR TURNS — do not repeat the same approach:
$_errors_rendered
Consider a fundamentally different approach or escalate."
  fi
fi

# Block 5c — Open questions from state.md `## Open Questions` body section.
# Pending user-facing questions surface as AUQ-FIRST directive.
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
# One-time user picks surface so the model
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

# Block 5e — Auto-archive stale L2 entries.
#
# Triggers archive-stale.sh on SessionStart when:
#   - learnings.jsonl > GENIRO_AUTO_ARCHIVE_THRESHOLD lines (default 5000)
#   - file hash changed since last archive run (skip-if-unchanged)
#   - safety.json memory.auto_archive_stale != false (default-on, opt-out)
#   - mkdir-lock acquired (multi-tab race protection)
#
# All checks are dirt-cheap (wc, _geniro_sha256, mkdir). archive-stale itself
# is ~50-200ms for 5000 entries — fits within SessionStart latency budget.
# Skipped silently when nothing to do; surfaces summary block only when
# entries were actually flipped.
BLOCK5E=""
ARCHIVED_COUNT=0
# Auto-archive paths anchor to the primary worktree so cross-session writes
# (learnings.jsonl, the hash marker, the lock dir) survive linked-worktree
# removal. safety.json keeps its walk-up resolution below — file-protection.sh
# and block-dangerous-git.sh use the same walk-up and the patterns must stay
# aligned across the three hooks.
_learnings_log="$GENIRO_ROOT/.geniro/knowledge/learnings.jsonl"
_threshold="${GENIRO_AUTO_ARCHIVE_THRESHOLD:-5000}"
# Sanitize — a non-numeric override (e.g. "5k") would make the `-gt` test below
# error to stderr and evaluate false, silently disabling auto-archive. Mirror
# the numeric-input sanitization used elsewhere in this hook.
case "$_threshold" in ''|*[!0-9]*) _threshold=5000 ;; esac

if [ -f "$_learnings_log" ]; then
  # Opt-out check (default ON; user sets false to disable).
  _auto_enabled="true"
  _safety_file=$(find_safety_json 2>/dev/null || true)
  if [ -n "$_safety_file" ] && [ -f "$_safety_file" ]; then
    # Resolve with an explicit `== false` test, not jq's `//` default operator:
    # `//` treats a boolean `false` as empty and falls through to the default,
    # so a defaulted read of this key would never honor an explicit `false`
    # (a real opt-out bug this form replaced).
    _opt=$(jq -r 'if .memory.auto_archive_stale == false then "false" else "true" end' "$_safety_file" 2>/dev/null)
    if [ "$_opt" = "false" ]; then
      _auto_enabled="false"
    fi
  fi

  _line_count=$(wc -l < "$_learnings_log" 2>/dev/null | tr -d ' ')

  if [ "$_auto_enabled" = "true" ] && [ -n "$_line_count" ] && [ "$_line_count" -gt "$_threshold" ]; then
    _hash_marker="$GENIRO_ROOT/.geniro/knowledge/.archive-stale.hash"
    _lock_dir="$GENIRO_ROOT/.geniro/knowledge/.archive-stale.lock"

    _current_hash=$(_geniro_sha256 "$_learnings_log" 2>/dev/null | cut -d' ' -f1)
    _last_hash=$(cat "$_hash_marker" 2>/dev/null)

    if [ -n "$_current_hash" ] && [ "$_current_hash" != "$_last_hash" ]; then
      # File changed since last archive — eligible to run.
      # Stale-lock cleanup (orphaned > 10 min from crashed process).
      if [ -d "$_lock_dir" ]; then
        _lock_mtime=$(stat -c %Y "$_lock_dir" 2>/dev/null || stat -f %m "$_lock_dir" 2>/dev/null || echo 0)
        _lock_age=$(( $(date +%s) - _lock_mtime ))
        # Shared reclaim window — override via GENIRO_LOCK_RECLAIM_SECS (default
        # 600s), the same env knob update-semantic.sh (_US_STALE_LOCK_SECS) and
        # archive-stale.sh honor for this same .archive-stale.lock, so a retuned
        # window stays consistent across all reclaimers.
        if [ "$_lock_age" -gt "${GENIRO_LOCK_RECLAIM_SECS:-600}" ]; then
          rmdir "$_lock_dir" 2>/dev/null
        fi
      fi

      # Atomic lock acquisition. Failure = another tab is running it; skip.
      if mkdir "$_lock_dir" 2>/dev/null; then
        _archive_rc=0
        # GENIRO_ARCHIVE_LOCK_HELD=1 — this hook already holds the mkdir lock;
        # without the flag the helper's direct-invocation branch would see the
        # held lock and skip with rc=3.
        _archive_output=$(GENIRO_ARCHIVE_LOCK_HELD=1 bash "${CLAUDE_PLUGIN_ROOT:-.}/lib/archive-stale.sh" 2>&1) || _archive_rc=$?

        if [ "$_archive_rc" -le 1 ]; then
          # Update hash marker (capture POST-archive state) — only after a
          # COMPLETED scan (rc=0 archived / rc=1 nothing matched, per the
          # archive-stale.md exit-code contract). A real failure (rc>=2, or a
          # missing helper) must stay retry-eligible on the next session start.
          _geniro_sha256 "$_learnings_log" 2>/dev/null | cut -d' ' -f1 > "$_hash_marker"
        fi

        # Release lock.
        rmdir "$_lock_dir" 2>/dev/null

        # Extract archived count from helper's stderr line:
        # "archive-stale: flipped deprecated:true on N entries:"
        ARCHIVED_COUNT=$(printf '%s\n' "$_archive_output" | grep -oE 'flipped deprecated:true on [0-9]+' | grep -oE '[0-9]+' | head -1)
        ARCHIVED_COUNT="${ARCHIVED_COUNT:-0}"

        if [ "$ARCHIVED_COUNT" -gt 0 ]; then
          BLOCK5E="ℹ️ Auto-archived $ARCHIVED_COUNT stale L2 entries (deprecated:true; audit trail preserved on-disk).
Criteria: age>180d AND score<0.1 AND access_count==0.
learnings.jsonl: $_line_count entries (size unchanged — entries kept, flagged only).
Opt-out: set \`memory.auto_archive_stale: false\` in .geniro/safety.json."
        fi
      fi
      # mkdir failed → another tab owns the lock; silent skip.
    fi
    # hash unchanged → no new entries since last archive; silent skip.
  fi
fi

# Verification-coverage suffix — the fraction of the live (non-deprecated) L2
# corpus whose trust is `verified`, surfaced read-only on the systemMessage.
# Computed INDEPENDENTLY of the archiver (which only runs past the 5000-line
# threshold, so its coverage line would near-never surface on small repos) via a
# cheap jq tally over the same primary-worktree learnings.jsonl. Absent trust
# folds into `inferred` ((.trust // "inferred")) to match the score-formula and
# query-learnings normalization. n/a guards the zero-live divide-by-zero. Opt-out
# via safety.json memory.show_coverage (default ON), mirroring auto_archive_stale.
# The `-s` guard (non-empty) avoids wasted work on a 0-byte file, but size alone
# is insufficient: a non-empty learnings.jsonl whose every entry is
# `deprecated: true` still computes $total == 0 over the live set and yields the
# "n/a" sentinel — a non-empty string that would defeat the cold-startup
# suppression clause below ([ -z "$COVERAGE_SUFFIX" ]) and fire a bogus
# `verified: n/a` systemMessage. So the assignment below filters the "n/a"
# sentinel out (not just the 0-byte case): COVERAGE_SUFFIX is set only for a real
# ratio. Treat both an empty file and an all-deprecated corpus as "no coverage to
# report".
COVERAGE_SUFFIX=""
if [ -f "$_learnings_log" ] && [ -s "$_learnings_log" ]; then
  _coverage_enabled="true"
  _cov_safety_file=$(find_safety_json 2>/dev/null || true)
  if [ -n "$_cov_safety_file" ] && [ -f "$_cov_safety_file" ]; then
    # Test for an explicit `false` rather than `// true` — jq's `//` treats the
    # boolean `false` as empty and falls through to the default, so `// true`
    # could never read an opt-out the user actually set to false.
    _cov_opt=$(jq -r 'if .memory.show_coverage == false then "false" else "true" end' "$_cov_safety_file" 2>/dev/null)
    if [ "$_cov_opt" = "false" ]; then
      _coverage_enabled="false"
    fi
  fi

  if [ "$_coverage_enabled" = "true" ]; then
    _cov=$(jq -Rsr '
      [splits("\n") | select(length > 0) | fromjson?
       | select((.deprecated // false) == false)] as $live
      | ($live | length) as $total
      | ([$live[] | select((.trust // "inferred") == "verified")] | length) as $verified
      | if $total == 0 then "n/a"
        else "\($verified)/\($total) (\(($verified * 100 / $total) | round)%)"
        end' "$_learnings_log" 2>/dev/null)
    if [ -n "$_cov" ] && [ "$_cov" != "n/a" ]; then
      COVERAGE_SUFFIX="$_cov"
    fi
  fi
fi

# Block 6 — resume protocol. The cold-startup branch
# (no active task) emits no "active task" block — i.e., the 7-step
# resume protocol is suppressed entirely. Loader-refresh advice still
# matters, so we emit a trimmed 1-step block in that case.
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
7. Continue from the next incomplete phase. The summary above is historical reference only — it may describe steps that already ran. Do not re-run any slash command or re-apply its arguments from this restored context; confirm current intent first, then proceed from where the task left off."
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
_append_block "$BLOCK1B"
_append_block "$BLOCK2"
_append_block "$BLOCK3"
_append_block "$BLOCK4"
_append_block "$BLOCK5"
_append_block "$BLOCK5B"
_append_block "$BLOCK5C"
_append_block "$BLOCK5D"
_append_block "$BLOCK5E"
_append_block "$BLOCK6"

# ---------------------------------------------------------------------------
# systemMessage
# ---------------------------------------------------------------------------

_active_label="none"
_phase_label="—"
if [ -n "$task_dir" ]; then
  _active_label="$(basename "$task_dir")"
fi
if [ -n "$phase" ]; then
  _phase_label="$phase"
fi

# The task-dir basename (often a ticket slug like `ci-302-...`) reads like a git
# branch but is a directory name — a frequent source of "why is this strange
# branch restoring?" confusion. Spell out the producer skill and the branch the
# task is bound to so the resume line is unambiguous about what is resuming and
# on which branch (a /plan authored on `main` shows `branch: main`).
if [ -n "$active_skill" ]; then
  _task_segment="active task: $_active_label · skill: /$active_skill · branch: ${recorded_branch:-?} · phase: $_phase_label"
else
  _task_segment="active task: $_active_label · phase: $_phase_label"
fi
SYSTEM_MESSAGE="Geniro: restoring context (source: $SOURCE · $_task_segment · non-resumable: $non_resumable_count)"
if [ "${ARCHIVED_COUNT:-0}" -gt 0 ]; then
  SYSTEM_MESSAGE="$SYSTEM_MESSAGE · auto-archived: $ARCHIVED_COUNT"
fi
if [ -n "$COVERAGE_SUFFIX" ]; then
  SYSTEM_MESSAGE="$SYSTEM_MESSAGE · memory verified: $COVERAGE_SUFFIX"
fi

# Suppression rule: cold startup with no active task → no systemMessage spam.
# Exception: auto-archive event (ARCHIVED_COUNT > 0) OR a coverage line overrides
# suppression — the user wants maintenance / memory-health signals even on a cold
# start.
emit_system_message=true
if [ "$SOURCE" = "startup" ] && [ -z "$state_file" ] \
   && [ "${ARCHIVED_COUNT:-0}" -eq 0 ] && [ -z "$COVERAGE_SUFFIX" ]; then
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
