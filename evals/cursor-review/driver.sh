#!/usr/bin/env bash
# Run one variant over a task set with cursor-agent.
#
#   driver.sh --variant <dir> --tasks <dir> [--trials N] [--model M] [--out <dir>] [--conc N]
#
# Per task, per trial, per dimension: assemble the reviewer prompt (preamble +
# criteria inline + project context + diff + changed-file contents), run
#   cursor-agent -p --mode plan --workspace <staged tree>
# and store the raw JSON result. Scoring is a separate step (score.sh).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MODEL="cursor-grok-4.5-medium"
TRIALS=1
CONC=4
OUT=""
VARIANT=""
TASKS=""
MAX_PROMPT_BYTES=$((600 * 1024))

while [ $# -gt 0 ]; do
  case "$1" in
    --variant) VARIANT="$2"; shift 2;;
    --tasks)   TASKS="$2"; shift 2;;
    --trials)  TRIALS="$2"; shift 2;;
    --model)   MODEL="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --conc)    CONC="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$VARIANT" ] && [ -n "$TASKS" ] || { echo "usage: driver.sh --variant <dir> --tasks <dir>" >&2; exit 64; }
VARIANT="$(cd "$VARIANT" && pwd)"
TASKS="$(cd "$TASKS" && pwd)"
[ -n "$OUT" ] || OUT="$HERE/runs/$(date -u +%Y%m%dT%H%M%SZ)-$(basename "$VARIANT")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

PREAMBLE="$VARIANT/preamble.md"
DIMS_JSON="$VARIANT/dims.json"
[ -f "$PREAMBLE" ] || PREAMBLE="$HERE/variants/champion/preamble.md"
[ -f "$DIMS_JSON" ] || DIMS_JSON="$HERE/variants/champion/dims.json"

criteria_path() { # resolve a criteria file: variant-local first, champion fallback
  local f="$1"
  if [ -f "$VARIANT/criteria/$f" ]; then echo "$VARIANT/criteria/$f";
  elif [ -f "$HERE/variants/champion/criteria/$f" ]; then echo "$HERE/variants/champion/criteria/$f";
  else echo "missing criteria: $f" >&2; return 66; fi
}

assemble_prompt() { # task_stage_dir dim_name criteria_files... -> prompt on stdout
  local stage="$1" dim="$2"; shift 2
  cat "$PREAMBLE"
  printf '\n\n## Your dimension: %s\n\n## Criteria\n\n' "$dim"
  local c
  for c in "$@"; do
    printf '\n---\n\n'
    cat "$(criteria_path "$c")"
  done
  printf '\n\n## Project context\n\n%s\n' "$(jq -r '.project_context // "No additional context."' "$stage/task.json" 2>/dev/null || echo "No additional context.")"
  printf '\n## Diff under review (unified)\n\n```diff\n'
  cat "$stage/diff.patch"
  printf '```\n\n## Changed files (full current content)\n'
  local total=0 f sz
  while IFS= read -r f; do
    [ -f "$stage/tree/$f" ] || continue
    sz=$(wc -c < "$stage/tree/$f")
    if [ $((total + sz)) -gt "$MAX_PROMPT_BYTES" ]; then
      printf '\n### %s\n(omitted for size — read it from the workspace if needed)\n' "$f"
      continue
    fi
    total=$((total + sz))
    printf '\n### %s\n```\n' "$f"
    cat "$stage/tree/$f"
    printf '```\n'
  done < "$stage/changed-files.txt"
  # Authored repo rules — what the production conventions/bugs dims see via the
  # AUTHORED RULE FILES slot; without them, rule-based ground truth is unfindable.
  if [ "$(jq -r '.include_repo_rules // false' "$stage/task.json" 2>/dev/null)" = "true" ]; then
    printf '\n## Authored rule files of the reviewed repository\n'
    local rtotal=0 rf rsz
    for rf in $(cd "$stage/tree" && ls CLAUDE.md AGENTS.md .cursorrules 2>/dev/null; \
                cd "$stage/tree" && find .claude/rules .cursor/rules -type f \( -name '*.md' -o -name '*.mdc' \) 2>/dev/null | head -20); do
      [ -f "$stage/tree/$rf" ] || continue
      rsz=$(wc -c < "$stage/tree/$rf")
      if [ $((rtotal + rsz)) -gt $((40 * 1024)) ]; then
        printf '\n### %s\n(omitted for size)\n' "$rf"; continue
      fi
      rtotal=$((rtotal + rsz))
      printf '\n### %s\n```\n' "$rf"
      cat "$stage/tree/$rf"
      printf '```\n'
    done
    printf '\nViolations of these authored rules are findings — cite the exact rule.\n'
  fi
  printf '\nYour workspace is the reviewed repository — Read/Grep it for callers and context beyond the diff.\nBegin the review now. Output ONLY the review in the exact format specified.\n'
}

run_one() { # task_id trial dim criteria...
  local task_id="$1" trial="$2" dim="$3"; shift 3
  local stage="$OUT/stage/$task_id"
  local rdir="$OUT/results/$task_id/trial-$trial"
  mkdir -p "$rdir"
  local prompt_file="$rdir/prompt-$dim.md"
  assemble_prompt "$stage" "$dim" "$@" > "$prompt_file"
  # Prompt over stdin: argv has a hard size ceiling, review prompts do not.
  # Ask mode: read-only AND the answer lands in the result text (plan mode routes
  # long output into its plan buffer, which silently drops the review).
  local attempt=1
  while [ "$attempt" -le 2 ]; do
    if cursor-agent -p --output-format json --model "$MODEL" --mode ask \
         --workspace "$stage/tree" --trust < "$prompt_file" \
         > "$rdir/raw-$dim.json" 2> "$rdir/err-$dim.log" \
       && jq -er '.result | test("### ")' "$rdir/raw-$dim.json" >/dev/null 2>&1; then
      return 0
    fi
    # A findings-free clean review is legal: accept a result carrying the summary header.
    if jq -er '.result | test("## Dimension Summary|Review — 0 findings")' "$rdir/raw-$dim.json" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  jq -e '.type == "result"' "$rdir/raw-$dim.json" >/dev/null 2>&1 || \
    echo "{\"type\":\"result\",\"is_error\":true,\"driver_error\":\"cursor-agent-failed\"}" > "$rdir/raw-$dim.json"
}

# Stage every task once
for tdir in "$TASKS"/*/; do
  task_id="$(basename "$tdir")"
  [ -f "$tdir/task.json" ] || continue
  echo "[stage] $task_id"
  bash "$HERE/stage-task.sh" "$tdir" "$OUT/stage/$task_id" >/dev/null
  cp "$tdir/task.json" "$OUT/stage/$task_id/task.json"
done

# Fire trials × dims with a small job pool
jobs_running() { jobs -pr | wc -l | tr -d ' '; }
N_DIMS="$(jq '.dims | length' "$DIMS_JSON")"
for tdir in "$TASKS"/*/; do
  task_id="$(basename "$tdir")"
  [ -f "$tdir/task.json" ] || continue
  trial=1
  while [ "$trial" -le "$TRIALS" ]; do
    i=0
    while [ "$i" -lt "$N_DIMS" ]; do
      dim="$(jq -r ".dims[$i].name" "$DIMS_JSON")"
      # shellcheck disable=SC2046
      set -- $(jq -r ".dims[$i].criteria[]" "$DIMS_JSON")
      while [ "$(jobs_running)" -ge "$CONC" ]; do sleep 1; done
      echo "[run] $task_id trial-$trial $dim"
      run_one "$task_id" "$trial" "$dim" "$@" &
      i=$((i + 1))
    done
    trial=$((trial + 1))
  done
done
wait

jq -n --arg variant "$(basename "$VARIANT")" --arg model "$MODEL" \
      --arg tasks "$TASKS" --argjson trials "$TRIALS" \
      '{variant:$variant, model:$model, tasks:$tasks, trials:$trials}' > "$OUT/meta.json"
echo "$OUT"
