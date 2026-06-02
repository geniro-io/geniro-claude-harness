# L2 episodic-memory read helper

## Contents

- §API — `query_learnings` signature
- §MODE contract
- §Flags — type / tag / scope / trust / score filters
- §Filter pipeline — order of application
- §Score formula — recency × trust × access × recurrence
- §`record_access` function — bumping access counts on read
- §Trust level ordering
- §Examples
- §Caller conventions
- §Known limitations
- §Test coverage

**Status:** Authoritative for every read of `.geniro/knowledge/learnings.jsonl`. Skills that recall prior diagnoses, decisions, conventions, pitfalls, or discoveries — `/geniro:debug`, `/geniro:implement`, `/geniro:plan`, `/geniro:review` — call this helper.

## API

```bash
source lib/query-learnings.sh
query_learnings [flags] > matches.jsonl
```

Emits matching JSONL entries to stdout, one per line. Exit codes (`query_learnings`):
- `0` — query ran (zero or more matches).
- `64` — unknown flag or invalid `--min-trust` value.

The `record_access` function has its own exit-code table in the §`record_access` function section (rc=1 IO error, rc=64 missing key).

**Path resolution:** this helper uses `lib/repo-root.sh::_geniro_repo_root` to find the project root. When invoked from a linked git worktree (where `.geniro/` may exist with just `planning/`), the resolver returns the PRIMARY worktree's path so the L2 read sources the canonical store (and not an empty linked-worktree log). See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Why this exists" for the contract.

## MODE contract

Request/response helper — **no MODE parameter, compaction-immune.** Each
call is a fresh query against the on-disk L2 log; the helper holds no
context-resident state across calls. Skill flow decides when to re-query
after a SessionStart event (e.g., `/geniro:debug` Phase 2 may re-query after
resume if its hypothesis thread depends on prior findings).

## Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--type TYPE` | (any) | Match `type` field exactly. Common values: `diagnosis`, `decision`, `convention`, `pitfall`, `discovery`. Extended types: `discarded_hypothesis`, `user_rejected_suggestion`, `retry_failure_sequence`. |
| `--tag TAG` | (any) | Entries whose `tags` array contains `TAG`. |
| `--scope SCOPE` | (any) | Match `scope` exactly. Use `--scope global` for global entries. |
| `--min-trust LEVEL` | (any) | Only entries with trust ≥ LEVEL. Levels (high→low): `verified`, `retrieved`, `inferred`. Entries with no `trust` field are treated as `inferred`. |
| `--score-min N` | (no scoring) | Compute per-entry score = recency_decay × trust_weight × access_weight × recurrence_weight; include only entries with score ≥ N AND sort result DESC by score. See §Score formula below. |
| `--include-superseded` | excluded | Include entries whose `dedup_key` appears as `supersedes` in a later entry. Useful for audit / history. |
| `--include-deprecated` | excluded | Include entries with `deprecated: true`. |
| `--include-archive` | excluded | Also read `.geniro/knowledge/archive/learnings-*.jsonl` for cold history. |
| `--limit N` | (no cap) | Emit at most N entries (after all filters). Semantics depend on `--score-min`: with score, top-N by score (`head`); without, most-recent-N by append position (`tail`, original behavior). |

## Filter pipeline

1. **Source set:** start with `learnings.jsonl`, optionally union with archive files.
2. **Build superseded set:** collect every `supersedes` value present in the union (set of dedup_keys that some later entry invalidates).
3. **Apply scalar filters** (`--type`, `--tag`, `--scope`, `--min-trust`) and the implicit `deprecated == false` filter (unless `--include-deprecated`).
4. **Apply supersede filter** unless `--include-superseded`.
5. **Apply score filter and sort** if `--score-min N` is set.
6. **Apply `--limit`** — `head -n N` if score-sorted, otherwise `tail -n N`.

Each filter is logically AND-ed.

## Score formula

When `--score-min N` is active:

```
score = recency_decay × trust_weight × access_weight × recurrence_weight

recency_decay    = exp(-Δdays / τ), τ = 90 days (env: GENIRO_DECAY_TAU_DAYS)
trust_weight     = { verified: 1.0, retrieved: 0.66, inferred: 0.33 }
access_weight    = 1.0 + log10(1 + access_count)
recurrence_weight = 1.0 + ln(max(recurrence_count, 1))
```

Defaults: missing `ts` or unparseable → `recency_decay = 0.5` (mid-range); missing `trust` → `inferred`; missing `access_count` → 0; missing `recurrence_count` → 1. `_score` is internal — stripped before output.

**Recurrence is dampened on purpose.** `recurrence_count` (how many times a learning has recurred — see `emit-learning.md`) feeds the score through a natural-log curve, so a frequently-repeated learning ranks higher without swamping recency and trust: count 1 → factor 1.0, 2 → ~1.69, 5 → ~2.61, 20 → ~4.0. A count of 1 (or an absent field, treated as 1) yields factor 1.0, i.e. no change — entries written before this field existed score exactly as they did before.

**Threshold guidance (callers pick their own):**
- `--score-min 0.5` — high-signal only (recently-emitted verified entries)
- `--score-min 0.3` — balanced (recommended default for Phase 1 read calls)
- `--score-min 0.1` — almost everything (mostly for debug)
- (no flag) — return everything, original append order

## `record_access` function

Increments `access_count` of entry matching a given `dedup_key`. Used by callers that want to feed access-frequency signal into future `--score-min` queries.

```bash
record_access "<dedup_key>"
```

- Returns 0 on success or no-op (no log file, no matching entry).
- Returns 1 on IO error.
- Returns 64 if no key supplied.
- Best-effort: no lock. Concurrent misses are acceptable (counter, not ledger). Uses POSIX `rename(2)` for atomicity.
- Callers typically invoke after surfacing a query result they actually used. Example: `/geniro:debug` Phase 1 surfaces 3 entries, orchestrator cites entry `bbb00002` in hypothesis → call `record_access bbb00002`.

## Trust level ordering

```
verified (highest) — grounded in code or test execution
retrieved — sourced from external content (web, MCP, third-party docs)
inferred (lowest) — model deduced from indirect signals
```

`--min-trust verified` → only verified entries. `--min-trust retrieved` → verified OR retrieved. `--min-trust inferred` → all (any entry passes). Missing `trust` field counts as `inferred` — strictest filter excludes it.

## Examples

```bash
# All diagnoses in the React subtree, supersede-aware
query_learnings --type diagnosis --tag react

# Architectural decisions, verified only
query_learnings --type decision --min-trust verified

# All conventions tagged "auth", including ones that were later refined
query_learnings --type convention --tag auth --include-superseded

# Cold history (last quarter's archive) about a specific file
query_learnings --scope src/legacy/old.ts --include-archive --limit 20
```

## Caller conventions

- The output IS a JSONL stream; callers should pipe to `jq` or process line-by-line. Don't try to feed it to a JSON parser as-is.
- Empty result is a `rc=0` with empty stdout — callers must NOT treat zero-output as an error.
- A missing log file is also empty + rc=0 (first-run case).

## Known limitations

- **No fuzzy match.** `--scope` and `--type` are exact. Callers that want substring search should pipe through `jq 'select(.scope | test("..."))'`.
- **No date-range filter.** A future flag could be `--since`/`--until`; PR-0 keeps it simple. Callers can pipe through `jq 'select(.ts >= "2026-01-01")'`.
- **Archive enumeration is glob-based.** All files matching `learnings-*.jsonl` under `.geniro/knowledge/archive/` are loaded; broken or partial archives can crash jq's slurp. Helper swallows jq errors and returns empty.
- **Supersede filter is position-based, not `ts`-based.** Spec says "last-write-wins by ts"; impl orders by file position. They agree as long as `emit_learning` is the only writer (it appends in temporal order). A back-dated hand-injected entry with an older `ts` placed at the end of the file would still be treated as the latest. skill integration should re-evaluate.
- **O(n²) at scale.** The position-aware supersede filter runs `index()` per entry against the suffix of the array. Measured: 500 entries → 60ms, 1000 → 200ms, **5000 → 4.2s**. The archival threshold is 5000 lines, so a user hitting this size has already been nudged to archive. A precomputed-superseded-set rewrite would restore O(n); deferred until a real performance complaint arrives.

## Test coverage

`tests/memory/query-learnings.sh` exercises every flag, the supersede filter, trust ordering, the implicit deprecated-exclusion, archive merging, and unknown-flag rejection.
