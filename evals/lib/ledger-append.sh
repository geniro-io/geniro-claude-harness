#!/usr/bin/env bash
# evals/lib/ledger-append.sh — the cross-run eval history ledger writer.
#
# The evals pipeline's committed, append-only scorecard (plan §8). Reads one JSON
# record on stdin (built by evals/ingest.sh in Phase B, or by hand for a smoke run)
# and:
#   1. appends one normalised record to  <repo-root>/evals/history.jsonl
#   2. appends one human-readable row to  <repo-root>/evals/HISTORY.md
#
# Built on geniro's own primitives rather than a hand-rolled `>>` (plan §8, decision 15):
#   - lib/atomic-state-write.sh : atomic_state_append (torn-write-safe, 4094-byte ceiling)
#   - lib/redact-secrets.sh     : redact_secrets on the free-text `notes`
#   - lib/repo-root.sh          : _geniro_repo_root (resolve the committed evals/ path)
#   - lib/hash.sh               : _geniro_sha256 (available for digests)
# and modelled on emit-learning.sh's producer contract (ts auto-inject, redact, dedup-key).
#
# Producer contract (mirrors emit_learning):
#   - run_id auto-injected when absent — it is the record's identity. The auto-inject value is
#     `<UTC ISO-8601>-<random>`: a bare 1-second-resolution timestamp would collide (and silently
#     dedup-drop) two distinct runs ingested in the same second, so a random suffix is appended.
#     A caller-supplied run_id (the Phase-B ingest path) is preserved verbatim.
#   - The free-text `notes` field is run through redact_secrets before storage.
#   - Dedup on run_id within the last 200 records (the emit-learning tail-scan window): a run is
#     immutable, so re-ingesting the same run_id is a no-op (idempotent retry). To correct a run,
#     append a new attempt_no under a new run_id. (Re-ingesting a run_id older than 200 rows is not
#     deduped — a Phase-B caller that replays old runs must guard idempotency itself.)
#   - Required fields: skill, baseline_ref, candidate_ref. Missing → rc 64, nothing written.
#   - Oversize (line + framing > 4094 bytes) → rc 68, nothing written (atomicity guarantee).
#
# history.jsonl is the source of truth; HISTORY.md is a regenerable human mirror.
#
# Plugin-developer / eval tooling only — NOT shipped to user projects, NOT loaded by any skill.

if [ -z "${_LA_DEPS_LOADED:-}" ]; then
  _la_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _la_lib_dir="$(cd "$_la_script_dir/../../lib" && pwd)"
  # shellcheck disable=SC1091
  source "$_la_lib_dir/repo-root.sh"
  # shellcheck disable=SC1091
  source "$_la_lib_dir/redact-secrets.sh"
  # shellcheck disable=SC1091
  source "$_la_lib_dir/atomic-state-write.sh"
  # shellcheck disable=SC1091
  source "$_la_lib_dir/hash.sh"
  _LA_DEPS_LOADED=1
fi

# Canonical HISTORY.md preamble + table header. SINGLE SOURCE — both the create-if-absent
# path here and the committed seed (scripts/seed-ledger.sh) call this, so they cannot drift.
ledger_history_header() {
  cat <<'EOF'
# Eval history ledger

One row per version-vs-version eval run, appended by `evals/lib/ledger-append.sh`
(via `evals/ingest.sh`). The machine-readable source of truth is `evals/history.jsonl`;
this table is its human mirror and can be regenerated from it.

**Read discipline (plan §6):** consult this table BEFORE a run only to recall the current
champion ref. Do NOT read the trend before the blind verdict is fixed — that re-introduces
the anchoring bias the machine judge is designed to avoid. Read the trend post-hoc via
`/geniro:eval`.

Promotion gates on **one primary metric** clearing its task-clustered CI (plan §9); cost,
time, and pass-rate are reported, not gated. A delta inside the CI is a tie, not a win.

| Date | Skill | Cand | vs | Primary (winrate, CI) | Recall^k | κ | Cost Δ | Time Δ | Tasks×Trials | Sig | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
EOF
}

# Emit the markdown table row derived from a compact JSON record (on $1). Missing fields → "—".
_la_history_row() {
  printf '%s' "$1" | jq -r '
    def dash($v): if $v == null then "—" else ($v | tostring) end;
    def short($r):
      if ($r | type) == "string" then
        (if ($r | test("^[0-9a-fA-F]{7,40}$")) then $r[0:7] else $r[0:12] end)
      else "—" end;
    def ci($a): if $a == null then "" else " [" + ($a[0] | tostring) + "," + ($a[1] | tostring) + "]" end;
    "| "
    + ((.run_id // "") | split("T")[0]) + " | "
    + dash(.skill) + " | "
    + short(.candidate_ref) + " | "
    + short(.baseline_ref) + " | "
    + ( if (.primary_metric != null) and (.[.primary_metric] != null)
        then (.[.primary_metric] | tostring) + ci(.quality_ci // .recall_passk_ci)
        else "—" end ) + " | "
    + dash(.recall_passk) + " | "
    + dash(.judge_human_kappa) + " | "
    + dash(.cost_delta) + " | "
    + dash(.time_delta) + " | "
    + ( if (.tasks != null) and (.trials_per_task != null)
        then (.tasks | tostring) + "×" + (.trials_per_task | tostring) else "—" end ) + " | "
    + ( if .significant_on_primary == true then "yes"
        elif .significant_on_primary == false then "no" else "—" end ) + " | "
    + dash(.comparator_verdict // .verdict) + " |"
  '
}

# Append one eval-run record. Reads JSON on stdin.
ledger_append() {
  local input
  input="$(cat)"
  # Empty stdin is a no-op (mirrors atomic_state_append / emit_learning), not a crash.
  if [ -z "$input" ]; then
    return 0
  fi

  # Reject non-JSON input early.
  if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
    echo "ledger_append: stdin is not valid JSON" >&2
    return 64
  fi

  # Required fields — fail before any write.
  local skill baseline candidate
  skill="$(printf '%s' "$input" | jq -r '.skill // empty')"
  baseline="$(printf '%s' "$input" | jq -r '.baseline_ref // empty')"
  candidate="$(printf '%s' "$input" | jq -r '.candidate_ref // empty')"
  if [ -z "$skill" ] || [ -z "$baseline" ] || [ -z "$candidate" ]; then
    echo "ledger_append: missing required field (skill, baseline_ref, candidate_ref all required)" >&2
    return 64
  fi

  # run_id is the record identity — auto-inject when absent. A bare 1-second-resolution timestamp
  # would collide (and dedup-drop) two distinct runs in the same second, so append random entropy.
  local run_id
  run_id="$(printf '%s' "$input" | jq -r '.run_id // empty')"
  if [ -z "$run_id" ]; then
    run_id="$(date -u +%Y-%m-%dT%H:%M:%SZ)-${RANDOM}${RANDOM}"
  fi

  # Redact the free-text notes before storage.
  local notes notes_sanitized
  notes="$(printf '%s' "$input" | jq -r '.notes // empty')"
  if [ -n "$notes" ]; then
    notes_sanitized="$(printf '%s' "$notes" | redact_secrets "eval-ledger" "notes" "$run_id")"
  fi

  # Rebuild the normalised record (jq, never string concat).
  local rebuilt
  if [ -n "$notes" ]; then
    rebuilt="$(printf '%s' "$input" | jq -c --arg r "$run_id" --arg n "$notes_sanitized" '. + {run_id:$r, notes:$n}')"
  else
    rebuilt="$(printf '%s' "$input" | jq -c --arg r "$run_id" '. + {run_id:$r}')"
  fi

  local root log hist
  root="$(_geniro_repo_root)"
  log="$root/evals/history.jsonl"
  hist="$root/evals/HISTORY.md"

  # Dedup on run_id (scan the tail, like emit_learning) — a run is immutable.
  if [ -f "$log" ]; then
    local existing
    existing="$(tail -n 200 "$log" 2>/dev/null \
      | jq -Rc --arg r "$run_id" 'fromjson? | select(.run_id == $r)' 2>/dev/null \
      | tail -n 1)"
    if [ -n "$existing" ]; then
      return 0
    fi
  fi

  local line line_bytes
  line="$(printf '%s' "$rebuilt" | jq -c .)"
  line_bytes="$(printf '%s' "$line" | wc -c | tr -d ' ')"
  if [ "$line_bytes" -gt "$GENIRO_APPEND_MAX_BYTES" ]; then
    echo "ledger_append: serialized record + framing exceeds 4096 bytes (${line_bytes}); atomicity not guaranteed — shrink notes" >&2
    return 68
  fi

  # 1. Durable record (source of truth) first. Capture the real rc AFTER a non-negated pipeline:
  #    `if ! pipe; then rc=$?` would read 0, because the `!` negation zeroes $? before the body —
  #    masking a genuine append failure (rc 65/69) as success and silently losing the run.
  local rc
  printf '%s' "$line" | atomic_state_append "$log"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ledger_append: failed to append history.jsonl (rc=$rc)" >&2
    return "$rc"
  fi

  # 2. Human mirror — create the header when absent (single-sourced), then append the row.
  if [ ! -f "$hist" ]; then
    ledger_history_header | atomic_state_write "$hist" || {
      echo "ledger_append: WARN — wrote history.jsonl but failed to seed HISTORY.md header" >&2
      return 0
    }
  fi
  local row
  row="$(_la_history_row "$line")"
  if [ -n "$row" ]; then
    printf '%s' "$row" | atomic_state_append "$hist" || {
      echo "ledger_append: WARN — wrote history.jsonl but failed to append HISTORY.md row" >&2
    }
  fi
  return 0
}
