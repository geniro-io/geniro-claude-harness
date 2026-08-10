#!/usr/bin/env bash
# Run one variant of one module over a task set through an executor adapter.
#
#   run.sh --module <name> [--variant <dir>] --tasks <dir>
#          [--trials N] [--model M] [--adapter cursor-cli] [--out <dir>] [--conc N]
#          [--max-usd X] [--probe] [--dry-run] [--no-cache]
#
# Per task, per trial, per facet: assemble the prompt (variant preamble +
# criteria + task materials per the module's target.json), call the adapter,
# store the raw JSON result. Scoring is a separate step (score.sh).
#
# Guards built in (not policy prose):
#   --probe    run ONE call, print measured tokens + extrapolated sweep cost, exit
#   --max-usd  hard ceiling; the sweep stops launching once measured spend crosses it
#   cache      content-keyed (model + task@version + prompt hash) under cache/;
#              a re-run or resume of an unchanged call is free
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MODULE=""
MODEL="composer-2.5"
ADAPTER="cursor-cli"
TRIALS=1
CONC=4
OUT=""
VARIANT=""
TASKS=""
MAX_USD="50"
PROBE=0
DRY=0
NO_CACHE=0
FACETS_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --module)  MODULE="$2"; shift 2;;
    --variant) VARIANT="$2"; shift 2;;
    --tasks)   TASKS="$2"; shift 2;;
    --trials)  TRIALS="$2"; shift 2;;
    --model)   MODEL="$2"; shift 2;;
    --adapter) ADAPTER="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --conc)    CONC="$2"; shift 2;;
    --max-usd) MAX_USD="$2"; shift 2;;
    --probe)   PROBE=1; shift;;
    --dry-run) DRY=1; shift;;
    --no-cache) NO_CACHE=1; shift;;
    --facets)  FACETS_FILTER="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
[ -n "$MODULE" ] && [ -n "$TASKS" ] || { echo "usage: run.sh --module <name> --tasks <dir>" >&2; exit 64; }

MOD_DIR="$HERE/modules/$MODULE"
TARGET="$MOD_DIR/target.json"
[ -f "$TARGET" ] || { echo "no module target: $TARGET" >&2; exit 66; }
[ -n "$VARIANT" ] || VARIANT="$MOD_DIR/variants/champion"
VARIANT="$(cd "$VARIANT" && pwd)"
TASKS="$(cd "$TASKS" && pwd)"
ADAPTER_SH="$HERE/adapters/$ADAPTER.sh"
[ -x "$ADAPTER_SH" ] || { echo "no executable adapter: $ADAPTER_SH" >&2; exit 66; }
[ -n "$OUT" ] || OUT="$HERE/runs/scratch/$(date -u +%Y%m%dT%H%M%SZ)-$MODULE-$(basename "$VARIANT")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
CACHE_DIR="${LOOP_CACHE_DIR:-$HERE/cache}"
mkdir -p "$CACHE_DIR"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi }

CHAMPION="$MOD_DIR/variants/champion"
PREAMBLE="$VARIANT/preamble.md"
[ -f "$PREAMBLE" ] || PREAMBLE="$CHAMPION/preamble.md"
FACETS_JSON="$VARIANT/facets.json"
[ -f "$FACETS_JSON" ] || FACETS_JSON="$TARGET"   # target.json carries .facets
MAX_PROMPT_BYTES="$(jq -r '.assembly.max_prompt_bytes // 614400' "$TARGET")"
REPO_RULES_SLOT="$(jq -r '.assembly.repo_rules_slot == true' "$TARGET")"
RETRY_REGEX="$(jq -r '.output_contract.retry_regex // "### "' "$TARGET")"
CLEAN_REGEX="$(jq -r '.output_contract.clean_regex // "^$"' "$TARGET")"

# Blended $/Mtok for the executor model (measured, adapter-local). 0 = unknown.
PRICES="$HERE/adapters/cursor-prices.json"
RATE="$(jq -r --arg m "$MODEL" '.models[$m].blended_per_mtok // 0' "$PRICES" 2>/dev/null || echo 0)"

criteria_path() { # resolve a criteria file: variant-local first, champion fallback
  local f="$1"
  if [ -f "$VARIANT/criteria/$f" ]; then echo "$VARIANT/criteria/$f";
  elif [ -f "$CHAMPION/criteria/$f" ]; then echo "$CHAMPION/criteria/$f";
  else echo "missing criteria: $f" >&2; return 66; fi
}

rubric_version() { # task dir -> integer version (legacy bare array = 0)
  jq -r 'if type=="array" then 0 else (.version // 0) end' "$1/rubric.json" 2>/dev/null || echo 0
}

assemble_prompt() { # task_stage_dir facet_name criteria_files... -> prompt on stdout
  local stage="$1" facet="$2"; shift 2
  cat "$PREAMBLE"
  printf '\n\n## Your dimension: %s\n\n## Criteria\n\n' "$facet"
  local c
  for c in "$@"; do
    printf '\n---\n\n'
    cat "$(criteria_path "$c")"
  done
  printf '\n\n## Project context\n\n%s\n' "$(jq -r '.project_context // "No additional context."' "$stage/task.json" 2>/dev/null || echo "No additional context.")"
  # Two artifact shapes. A diff task asks "is this change sound"; a spec task asks
  # "do this document's claims hold against the tree". The tree is the evidence in
  # both, so only the artifact block and the file list differ.
  if [ -f "$stage/spec.md" ]; then
    printf '\n## Spec under test\n\n```markdown\n'
    cat "$stage/spec.md"
    printf '```\n'
    printf '\nThe tree around you is the code this spec makes claims about, pinned at the\ncommit the spec was written against. Nothing in it has been implemented yet.\nRead and grep it freely — the claims are settled against the tree, not against\nthe spec.\n\nBegin now. Output ONLY the verdicts in the exact format specified.\n'
    return 0
  fi
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
  # Authored repo rules — what the production conventions/bugs facets see via the
  # AUTHORED RULE FILES slot; without them, rule-based ground truth is unfindable.
  if [ "$REPO_RULES_SLOT" = "true" ] && [ "$(jq -r '.include_repo_rules // false' "$stage/task.json" 2>/dev/null)" = "true" ]; then
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

spent_usd() { # measured PAID spend: retried attempts count, cache-served results don't
  local toks
  toks="$({
    for f in "$OUT"/results/*/trial-*/raw-*.json; do
      [ -f "$f" ] || continue
      d="${f%/*}"; b="${f##*/raw-}"; b="${b%.json}"
      [ -f "$d/.cached-$b" ] || cat "$f"
    done
    cat "$OUT"/results/*/trial-*/usage-extra-*.jsonl 2>/dev/null || true
  } | jq -s '[.[].usage // {} | ((.inputTokens // 0) + (.cacheReadTokens // 0) + (.outputTokens // 0))] | add // 0')"
  awk -v t="$toks" -v r="$RATE" 'BEGIN { printf "%.4f", t * r / 1000000 }'
}

run_one() { # task_id trial facet criteria...
  local task_id="$1" trial="$2" facet="$3"; shift 3
  local stage="$OUT/stage/$task_id"
  local rdir="$OUT/results/$task_id/trial-$trial"
  mkdir -p "$rdir"
  local prompt_file="$rdir/prompt-$facet.md"
  assemble_prompt "$stage" "$facet" "$@" > "$prompt_file"
  local ver key cached wseg
  ver="$(rubric_version "$TASKS/$task_id")"
  # trial is part of the key: trials must be independent samples, while a
  # re-run/resume of the SAME trial index stays a free cache hit. A PRUNED
  # workspace adds its scope hash: identical prompts over differently-pruned
  # trees are different measurement conditions. Full trees keep the legacy
  # key shape so paid full-workspace caches stay valid.
  wseg=""
  if [ -f "$stage/workspace-scope.txt" ] && [ "$(head -1 "$stage/workspace-scope.txt")" != "full" ]; then
    wseg="|w$(sha < "$stage/workspace-scope.txt")"
  fi
  key="$(printf '%s|%s|t%s|v%s%s|%s' "$MODEL" "$task_id" "$trial" "$ver" "$wseg" "$(sha < "$prompt_file")" | sha)"
  cached="$CACHE_DIR/$key.json"
  if [ "$NO_CACHE" -eq 0 ] && [ -f "$cached" ]; then
    cp "$cached" "$rdir/raw-$facet.json"
    : > "$rdir/.cached-$facet"   # marker: this result was NOT paid for by this run
    echo "[cache] $task_id trial-$trial $facet"
    return 0
  fi
  rm -f "$rdir/.cached-$facet"
  # Prompt over stdin: argv has a hard size ceiling, prompts do not.
  local attempt=1
  while [ "$attempt" -le 2 ]; do
    if bash "$ADAPTER_SH" "$MODEL" "$stage/tree" "$prompt_file" \
         "$rdir/raw-$facet.json" "$rdir/err-$facet.log" \
       && jq -er --arg re "$RETRY_REGEX" '.result | test($re)' "$rdir/raw-$facet.json" >/dev/null 2>&1; then
      cp "$rdir/raw-$facet.json" "$cached"
      return 0
    fi
    # A findings-free clean result is legal when the contract names its header.
    if jq -er --arg re "$CLEAN_REGEX" '.result | test($re)' "$rdir/raw-$facet.json" >/dev/null 2>&1; then
      cp "$rdir/raw-$facet.json" "$cached"
      return 0
    fi
    # The retry will overwrite this raw file — keep the failed attempt's usage
    # so spent_usd and the --max-usd ceiling still count what it billed.
    jq -c '{usage: (.usage // {})}' "$rdir/raw-$facet.json" >> "$rdir/usage-extra-$facet.jsonl" 2>/dev/null || true
    attempt=$((attempt + 1))
  done
  jq -e '.type == "result"' "$rdir/raw-$facet.json" >/dev/null 2>&1 || \
    echo "{\"type\":\"result\",\"is_error\":true,\"driver_error\":\"adapter-failed\"}" > "$rdir/raw-$facet.json"
}

# ---- benchmark manifest + spec (pin what this run measured) ----
TASK_IDS=()
for tdir in "$TASKS"/*/; do
  [ -f "$tdir/task.json" ] || continue
  TASK_IDS+=("$(basename "$tdir")")
done
[ "${#TASK_IDS[@]}" -gt 0 ] || { echo "no tasks under $TASKS" >&2; exit 66; }

VARIANT_HASH="$(cd "$VARIANT" && find . -type f | LC_ALL=C sort | xargs cat 2>/dev/null | sha)"
TASK_MANIFEST="$(for t in "${TASK_IDS[@]}"; do
  printf '{"id":"%s","version":%s}\n' "$t" "$(rubric_version "$TASKS/$t")"
done | jq -s '.')"
BENCH_HASH="$(printf '%s' "$TASK_MANIFEST" | sha)"

N_FACETS="$(jq '.facets | length' "$FACETS_JSON")"
if [ -n "$FACETS_FILTER" ]; then
  FACET_IDX="$(jq -r --arg f "$FACETS_FILTER" '($f | split(",")) as $want
    | .facets | to_entries[] | select(.value.name as $n | $want | index($n)) | .key' "$FACETS_JSON")"
else
  FACET_IDX="$(jq -r '.facets | keys[]' "$FACETS_JSON")"
fi
[ -n "$FACET_IDX" ] || { echo "--facets '$FACETS_FILTER' matches no facet" >&2; exit 64; }
N_SEL="$(echo "$FACET_IDX" | wc -l | tr -d ' ')"
TOTAL_CALLS=$(( ${#TASK_IDS[@]} * TRIALS * N_SEL ))

jq -n --arg module "$MODULE" --arg variant "$(basename "$VARIANT")" \
      --arg variant_hash "$VARIANT_HASH" --arg model "$MODEL" --arg adapter "$ADAPTER" \
      --arg tasks "$TASKS" --arg bench_hash "$BENCH_HASH" \
      --argjson manifest "$TASK_MANIFEST" --argjson trials "$TRIALS" \
      --arg max_usd "$MAX_USD" --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg facets "${FACETS_FILTER:-all}" \
      '{module:$module, variant:$variant, variant_hash:$variant_hash,
        model:$model, adapter:$adapter, tasks:$tasks, bench_hash:$bench_hash,
        task_manifest:$manifest, trials:$trials, max_usd:$max_usd,
        facets:$facets, started_at:$started}' \
  > "$OUT/spec.json"

# ---- stage every task once (keep a completed stage: resumes are frequent) ----
for task_id in "${TASK_IDS[@]}"; do
  if [ -f "$OUT/stage/$task_id/changed-files.txt" ]; then
    echo "[stage] $task_id (kept)"
  else
    echo "[stage] $task_id"
    bash "$HERE/stage-task.sh" "$TASKS/$task_id" "$OUT/stage/$task_id" >/dev/null
  fi
  cp "$TASKS/$task_id/task.json" "$OUT/stage/$task_id/task.json"
done

if [ "$DRY" -eq 1 ]; then
  for task_id in "${TASK_IDS[@]}"; do
    for i in $FACET_IDX; do
      facet="$(jq -r ".facets[$i].name" "$FACETS_JSON")"
      # shellcheck disable=SC2046
      set -- $(jq -r ".facets[$i].criteria[]" "$FACETS_JSON")
      p="$OUT/results/$task_id/dry-prompt-$facet.md"
      mkdir -p "$(dirname "$p")"
      assemble_prompt "$OUT/stage/$task_id" "$facet" "$@" > "$p"
      echo "[dry] $task_id $facet: $(wc -c < "$p" | tr -d ' ') bytes"
    done
  done
  echo "[dry] total calls a real sweep would make: $TOTAL_CALLS"
  echo "$OUT"
  exit 0
fi

if [ "$PROBE" -eq 1 ]; then
  task_id="${TASK_IDS[0]}"
  # shellcheck disable=SC2086
  set -- $FACET_IDX; i="$1"
  facet="$(jq -r ".facets[$i].name" "$FACETS_JSON")"
  # shellcheck disable=SC2046
  set -- $(jq -r ".facets[$i].criteria[]" "$FACETS_JSON")
  echo "[probe] $task_id $facet on $MODEL"
  NO_CACHE=1   # a probe must measure a real call (harmless: probe exits below)
  run_one "$task_id" 1 "$facet" "$@"
  raw="$OUT/results/$task_id/trial-1/raw-$facet.json"
  jq -r --arg rate "$RATE" --argjson calls "$TOTAL_CALLS" '
    (.usage // {}) as $u
    | (($u.inputTokens // 0) + ($u.cacheReadTokens // 0) + ($u.outputTokens // 0)) as $t
    | "probe tokens: \($t)  measured rate: $\($rate)/Mtok\n" +
      "per-call: $\($t * ($rate|tonumber) / 1000000 | . * 10000 | round / 10000)\n" +
      "extrapolated sweep (\($calls) calls): $\($t * ($rate|tonumber) * $calls / 1000000 | . * 100 | round / 100)"
  ' "$raw"
  echo "[probe] rate 0 means unknown model — measure from the billing row and update adapters/cursor-prices.json"
  exit 0
fi

# ---- fire trials × facets with a small job pool + spend ceiling ----
jobs_running() { jobs -pr | wc -l | tr -d ' '; }
ABORTED=0
launched=0
for task_id in "${TASK_IDS[@]}"; do
  [ "$ABORTED" -eq 1 ] && break
  trial=1
  while [ "$trial" -le "$TRIALS" ]; do
    [ "$ABORTED" -eq 1 ] && break
    for i in $FACET_IDX; do
      facet="$(jq -r ".facets[$i].name" "$FACETS_JSON")"
      # shellcheck disable=SC2046
      set -- $(jq -r ".facets[$i].criteria[]" "$FACETS_JSON")
      while [ "$(jobs_running)" -ge "$CONC" ]; do sleep 1; done
      if [ "$RATE" != "0" ] && [ $((launched % 8)) -eq 0 ]; then
        spent="$(spent_usd)"
        if awk -v s="$spent" -v m="$MAX_USD" 'BEGIN { exit !(s > m) }'; then
          echo "[ABORT] measured spend \$$spent exceeds ceiling \$$MAX_USD — stopping launches" >&2
          echo "{\"aborted\":true,\"spent_usd\":$spent,\"max_usd\":$MAX_USD}" > "$OUT/ABORTED.json"
          ABORTED=1
          break
        fi
      fi
      echo "[run] $task_id trial-$trial $facet"
      run_one "$task_id" "$trial" "$facet" "$@" &
      launched=$((launched + 1))
    done
    trial=$((trial + 1))
  done
done
wait

echo "[done] launched=$launched spent=\$$(spent_usd) (rate $RATE/Mtok; 0 = unmetered)"
echo "$OUT"
[ "$ABORTED" -eq 0 ] || exit 75
