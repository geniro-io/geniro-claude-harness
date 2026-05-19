# L2 episodic-memory read helper

**Status:** Authoritative for every read of `.geniro/knowledge/learnings.jsonl`. Skills that recall prior diagnoses, decisions, conventions, pitfalls, or discoveries (per M2 §5.3) — `/debug`, `/implement`, `/plan`, `/review` — call this helper.

**Spec source:** `architecture/M2-memory-layers.md` §5.2 (read side) + §5.1 trust enum + §5.3 trust defaults.

## API

```bash
source skills/_shared/query-learnings.sh
query_learnings [flags] > matches.jsonl
```

Emits matching JSONL entries to stdout, one per line. Exit code:
- `0` — query ran (zero or more matches).
- `64` — unknown flag or invalid `--min-trust` value.

## Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--type TYPE` | (any) | Match `type` field exactly. Common values per M2 §5.1: `diagnosis`, `decision`, `convention`, `pitfall`, `discovery`. |
| `--tag TAG` | (any) | Entries whose `tags` array contains `TAG`. |
| `--scope SCOPE` | (any) | Match `scope` exactly. Use `--scope global` for global entries. |
| `--min-trust LEVEL` | (any) | Only entries with trust ≥ LEVEL. Levels (high→low): `verified`, `retrieved`, `inferred`. Entries with no `trust` field are treated as `inferred`. |
| `--include-superseded` | excluded | Include entries whose `dedup_key` appears as `supersedes` in a later entry. Useful for audit / history. |
| `--include-deprecated` | excluded | Include entries with `deprecated: true`. |
| `--include-archive` | excluded | Also read `.geniro/knowledge/archive/learnings-*.jsonl` for cold history. |
| `--limit N` | (no cap) | Emit at most N entries (after all filters; uses `tail -n N` — most-recent N). |

## Filter pipeline (matches M2 §5.2 read side)

1. **Source set:** start with `learnings.jsonl`, optionally union with archive files.
2. **Build superseded set:** collect every `supersedes` value present in the union (set of dedup_keys that some later entry invalidates).
3. **Apply scalar filters** (`--type`, `--tag`, `--scope`, `--min-trust`) and the implicit `deprecated == false` filter (unless `--include-deprecated`).
4. **Apply supersede filter** unless `--include-superseded`.
5. **Apply `--limit`** by tailing the post-filter results.

Each filter is logically AND-ed.

## Trust level ordering (M2 §5.1)

```
verified  (highest)  — grounded in code or test execution
retrieved             — sourced from external content (web, MCP, third-party docs)
inferred  (lowest)   — model deduced from indirect signals
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
- **No date-range filter.** A future flag could be `--since`/`--until`; M2 PR-0 keeps it simple. Callers can pipe through `jq 'select(.ts >= "2026-01-01")'`.
- **Archive enumeration is glob-based.** All files matching `learnings-*.jsonl` under `.geniro/knowledge/archive/` are loaded; broken or partial archives can crash jq's slurp. Helper swallows jq errors and returns empty.

## Test coverage

`tests/memory/query-learnings.sh` exercises every flag, the supersede filter, trust ordering, the implicit deprecated-exclusion, archive merging, and unknown-flag rejection.
