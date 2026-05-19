# L3 semantic-memory read helper + fingerprint drift detection

**Status:** Authoritative for L3 read-side access. Every pipeline skill that ingests current-state project facts (`/implement`, `/plan`, `/debug`, `/review`, `/refactor`, `/onboard`, `/investigate`) calls `load_semantic` at start of run.

**Spec source:** `architecture/M2-memory-layers.md` §6 (file layout, ownership table, drift detection, reader contract).

## API

```bash
source skills/_shared/load-semantic.sh

# Read — default top-2 + optional extras
content=$(load_semantic [--extras "name1 name2 ..."] [--quiet])

# Write — recompute fingerprint
update_fingerprint [<path1> <path2> ...]
```

## MODE contract (M3 §7)

The helper has a conceptual MODE — `initial-load` (Step 0 of every consumer)
or `refresh` (post-compaction or phase-boundary re-load). The procedure is
**identical** under both modes — every Read fires again, the fingerprint
drift check fires again. There is no MODE flag on the bash function; the
mode is documentary, signaling to the caller why they're invoking.

| Mode | When | Caller |
|------|------|--------|
| `initial-load` | First action of every L3-consuming skill | Pipeline skill at Step 0 |
| `refresh` | Post-compaction (via `hooks/session-start-restore.sh` Block 6 step 3) or on-demand if a phase explicitly needs fresh L3 facts | Model on next turn after a compact / resume / startup SessionStart |

**Phase-boundary refresh sites:** unlike `load-custom-instructions`, this
helper has NO mid-pipeline refresh sites — L3 facts are baseline awareness
(model corroborates via direct Grep/Read of code, not L3 prose). Per M3
§7.3: skills MAY invoke on-demand if a phase explicitly needs a fresh
module map, but no skill is required to do so.

### `load_semantic`

Concatenates the requested L3 markdown files to stdout. Each file is prefixed with a `=== file: <relative-path> ===` header so the model knows the source of each block.

**Default load:** `_project.md` + `_CODEBASE_MAP.md` (per M2 §6.4 top-2). Typical baseline cost: ~5–15 KB.

**Extras:** space-separated names (with or without leading `_`). Common usage: `--extras "_architecture _FEATURES"`.

**Drift detection:** automatically runs before content emission unless `--quiet` is set. Diverging files print `[L3 drift] …` to stderr; load itself never auto-overwrites L3 content. Reactive refresh is a deliberate user action (`/geniro:onboard --refresh-stack`).

**Missing files are skipped silently** — first-run repos that haven't created any `_*.md` yet emit empty stdout, not an error.

**Exit codes:**
- `0` — load ran (possibly emitted zero bytes).
- `64` — unknown flag.

### `update_fingerprint`

Recomputes hashes for the given files and writes `.geniro/planning/.fingerprint.json` atomically via `atomic_state_write`.

**With no args:** scans the default candidate list and includes every file that exists:

```
package.json, pnpm-lock.yaml, tsconfig.json, vite.config.{ts,js},
next.config.{ts,js}, pyproject.toml, requirements.txt, Cargo.toml, go.mod
```

This is intentionally biased toward JS/TS (the plugin's primary target) with Python / Rust / Go candidates for portability. Callers that want a stricter list can pass explicit paths.

**With explicit args:** hashes exactly those paths (relative to repo root). Missing files are skipped silently.

**Empty result:** if zero candidates exist (or zero are passed and zero exist), still writes a stub `{captured_at:<now>, files:{}}` so callers can distinguish "setup ran" from "first run".

## Fingerprint schema

```json
{
  "captured_at": "2026-05-19T15:30:00Z",
  "files": {
    "package.json": "sha256:e3ef61f583bd08f585b5a727764f2265b4ffae39ec37be29842ada7644ef27d7",
    "tsconfig.json": "sha256:..."
  }
}
```

Hash format: `sha256:<64-hex-chars>`. The `sha256:` prefix is deliberate — future implementations may extend to other hash algorithms without breaking schema.

## Drift warning shape

When `_ls_check_drift` finds any divergence:

```
[L3 drift] Tech stack fingerprint diverged — package.json, tsconfig.json changed since fingerprint captured on 2026-05-19T15:30:00Z.
[L3 drift] Consider /geniro:onboard --refresh-stack. Continuing with current memory.
```

Always to stderr (so it doesn't pollute the loaded-content stream that callers capture via `$(load_semantic)`). Exactly two lines (the diverged-file list and the action prompt).

## Caller patterns

```bash
# Most pipeline skills, default load
content=$(load_semantic)
# stderr already surfaced any drift warning to the user.

# /onboard --refresh-stack writes the fingerprint after refresh
update_fingerprint
```

```bash
# /implement loading extra context for a UI task
content=$(load_semantic --extras "_architecture _FEATURES _focus-ui")
```

```bash
# /investigate that wants L3 silently (no drift noise during a quiet query)
content=$(load_semantic --quiet)
```

## Known limitations

- **Drift detection is hash-equality, not semantic.** A reformat that changes hash but not meaning will spuriously warn. Acceptable — false-positive warnings are recoverable (user runs the refresh); false-negatives would be silent staleness.
- **No fingerprint pruning.** Files removed from the repo since the last `update_fingerprint` stay in `.fingerprint.json` (with their old hash) and silently never diverge. Refreshing via `update_fingerprint` rebuilds from scratch, so a periodic refresh is the canonical fix.
- **Default candidate list is JS-biased.** Polyglot projects should call `update_fingerprint` with explicit paths.
- **No locking on fingerprint writes.** Two concurrent `update_fingerprint` calls could race; the atomic-rename guarantees one wins cleanly but the other's data is lost. Acceptable per M2 §6.2 — fingerprint refreshes are user-initiated, not auto-triggered, so concurrent calls are rare.

## Test coverage

`tests/memory/load-semantic.sh` exercises the default top-2 load, missing-files passthrough, `--extras` (with and without leading underscore), drift warning emission on stderr, `--quiet` suppression, fingerprint creation with explicit args, fingerprint with no-args default-list discovery, the stub-fingerprint case, and unknown-flag rejection.
