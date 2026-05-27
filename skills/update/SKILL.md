---
name: geniro:update
description: "Use when the status line shows a plugin update is available, or to manually pull the latest geniro-claude-plugin version. Verifies plugin integrity, ensures user-authored.geniro/instructions/ and.geniro/actions/ survived intact, and walks any breaking changes in MIGRATION.md."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Write, Edit, Glob, Grep]
argument-hint: "[--dry-run]"
---

# /geniro:update — Update Plugin

4-phase loop: **Pre-check → Update → Post-check → Migration**. Stateless. Architecture spec: *(internal)*.

## Path Constraints

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** Use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths for project files. Honor `CLAUDE_CONFIG_DIR` and fall back to `$HOME/.claude` only inside Bash blocks where `$HOME` expands correctly.

## Loop invariants

1. One result per subagent call — `/update` does NOT spawn subagents.
2. Args validated before exec — every shell call has its prereq checked (registry exists, plugin.json parseable, network reachable).
3. Permission before side-effect — the pre-update AUQ (§Phase 1 Step 3) is the explicit gate.
4. Bounded structured results — hash diffs truncated at ~2000 chars; per migration step at ~500 chars.
5. Hard escalation gates — 4-retry exponential-backoff (2s, 4s, 8s, 16s) per CLAUDE.md network rules; after 4 retries → abort.
6. Observations not assumed success — shell exit codes checked at every step.
7. Errors as structured observations — surfaced inline; no silent skips.

## Budgets — quality-first

`/update` has **zero Class-A hard kill caps**. Class-B gates: 4-retry network backoff, hash-diff truncation, per-migration-step truncation. NOT capped: migration walk step count, hash-check file count, total update duration.

## ACI surface per phase

| Phase | Allowed | Forbidden |
|---|---|---|
| `pre-check` | `Read`, `Bash` (`cat`, `grep`, `python3 -c "json.load"`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent`, all `mcp__*` |
| `update` | `Bash` (`claude plugin marketplace update`, `claude plugin update`, `python3 -c` to parse registry) | `Read`/`Write`/`Edit` on project files, `Agent`, `mcp__github__*` |
| `post-check` | `Read`, `Bash` (`sha256sum`, `stat`, `cp` for statusline refresh), `Glob` | `Edit` on project files outside `$CLAUDE_USER_DIR/hooks/`, `mcp__*` |
| `migration` | `Read`, `AskUserQuestion`, `Bash` (detect commands from MIGRATION.md + auto-fix commands when user picks "Fix it for me"), `Glob`, `Write`, `Edit` (only when user picks "Fix it for me" per-entry) | `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

External sends: not in `/update` ACI ever.

## Termination case → state mapping

| Cause | Message |
|---|---|
| Network error after 4 retries | `aborted: network error during plugin marketplace update after 4 retries` |
| Update succeeded but registry missing entry | `aborted: registry missing geniro-claude-plugin entry — see ~/.claude/plugins/installed_plugins.json` |
| Hash-check failed | `aborted: plugin integrity check failed — manifest hash mismatch on <file>` |
| User-content tampering detected | AUQ surfaces; user picks Continue or Abort |
| MIGRATION.md walked successfully | `done` |
| MIGRATION.md walked, user aborted mid-walk | `aborted: user aborted migration walk at step <N>` |
| Already on latest version | `info: already on latest version (<version>)` — done |
| Hooks/registry write blocked | `aborted: blocked by hook — see <hint>` |

## Phase 1 — Pre-check

### Step 0 — Load custom instructions

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: update`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory. Per-skill `update.md` and `code-style.md` are NOT loaded — this is a meta-skill that updates the plugin itself, so the pipeline-tier files don't apply (helper §Caller contract «rules-only» list).

### Step 1 — Read current version

```bash
CURRENT_VERSION=$(cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null \
| python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")
if [ "$CURRENT_VERSION" = "unknown" ]; then
echo "ERROR: cannot read current plugin version from plugin.json — abort." >&2
exit 1
fi
```

### Step 2 — Resolve `$CLAUDE_USER_DIR`, `$PRIMARY_ROOT`, and snapshot user content

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A before the snapshot. The snapshot must capture user-authored content in the primary worktree — not whichever worktree the orchestrator currently sits in. `/update` is typically run from `main`, but the safe contract is to resolve explicitly so a session running in a linked worktree compares the right tree.

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"

# Resolve the primary worktree once; downstream snapshot/diff steps reuse it.
PRIMARY_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')"
PRIMARY_ROOT="${PRIMARY_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
PRIMARY_ROOT="${PRIMARY_ROOT:-$PWD}"

# Snapshot user-content sha256 + mtime for survival verification
USER_SNAPSHOT=$(find "$PRIMARY_ROOT/.geniro/instructions" "$PRIMARY_ROOT/.geniro/actions" -type f -name "*.md" 2>/dev/null \
| sort \
| xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}") {}"' 2>/dev/null)
# Save USER_SNAPSHOT (env var) for Phase 3 Step 2 comparison.
```

### Step 3 — Version-confirm AUQ

Use `AskUserQuestion`:

- **Question:** `Update geniro-claude-plugin? Current version: v<CURRENT_VERSION>. This will run marketplace + plugin update, verify integrity, and walk MIGRATION.md.`
- **Options:**
- `Confirm update` — Run the update flow (Recommended)
- `Cancel` — Exit without updating

On `Cancel` → terminate with `info: update cancelled by user`. On `Confirm update` → transition to Phase 2.

If `--dry-run` was passed in `$ARGUMENTS`, **skip the AUQ entirely** and instead read MIGRATION.md from the current install path (no marketplace fetch); print "what would happen" and exit. `--dry-run` does NOT modify any files.

## Phase 2 — Update

### Step 1 — Marketplace refresh + plugin update (exponential backoff)

Per CLAUDE.md network rules — 4 retries with 2s / 4s / 8s / 16s backoff:

```bash
attempt=1
while [ $attempt -le 4 ]; do
if claude plugin marketplace update geniro-claude-harness 2>&1 | tee /tmp/geniro-update.log; then
break
fi
echo "Marketplace update attempt $attempt failed; retrying in $((2 ** attempt))s..." >&2
sleep $((2 ** attempt))
attempt=$((attempt + 1))
done
if [ $attempt -gt 4 ]; then
echo "ERROR: marketplace update failed after 4 retries — abort." >&2
exit 1
fi

attempt=1
while [ $attempt -le 4 ]; do
if claude plugin update geniro-claude-plugin@geniro-claude-harness 2>&1 | tee /tmp/geniro-plugin-update.log; then
break
fi
echo "Plugin update attempt $attempt failed; retrying in $((2 ** attempt))s..." >&2
sleep $((2 ** attempt))
attempt=$((attempt + 1))
done
if [ $attempt -gt 4 ]; then
echo "ERROR: plugin update failed after 4 retries — abort." >&2
exit 1
fi
```

### Step 2 — Discover new plugin path

```bash
if [ ! -f "$REGISTRY" ]; then
echo "ERROR: registry not found at $REGISTRY — abort." >&2
echo "Hint: if you use a custom config dir, ensure CLAUDE_CONFIG_DIR is exported." >&2
exit 1
fi

PLUGIN_PATH=$(python3 -c "
import json, sys
try:
d = json.load(open('$REGISTRY'))
entry = d['plugins'].get('geniro-claude-plugin@geniro-claude-harness', [])
print(entry[0]['installPath'] if entry else '')
except Exception as e:
print(f'PARSE_ERROR: {e}', file=sys.stderr)
sys.exit(1)
")

if [ -z "$PLUGIN_PATH" ]; then
echo "ERROR: registry parsed but no entry for geniro-claude-plugin — abort." >&2
exit 1
fi

NEW_VERSION=$(cat "$PLUGIN_PATH/.claude-plugin/plugin.json" \
| python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
echo "[info] already on latest version (v$NEW_VERSION) — nothing to do."
exit 0
fi
```

Transition to Phase 3.

## Phase 3 — Post-check

### Step 1 — Plugin file hash-check (sanity mode)

If the new plugin publishes `$PLUGIN_PATH/.claude-plugin/manifest.sha256`, verify each file via `sha256sum -c`. Else (current state), sanity-check that key files exist:

```bash
HASH_FAIL=0
MISSING=
for f in \
"$PLUGIN_PATH/skills/_shared/load-custom-instructions.md" \
"$PLUGIN_PATH/skills/_shared/spawn-agent.md" \
"$PLUGIN_PATH/skills/implement/SKILL.md" \
"$PLUGIN_PATH/skills/setup/SKILL.md" \
"$PLUGIN_PATH/hooks/geniro-check-update.js"; do
[ -f "$f" ] || { MISSING+=("$f"); HASH_FAIL=1; }
done
[ -d "$PLUGIN_PATH/agents" ] && [ "$(ls -A "$PLUGIN_PATH/agents" | wc -l)" -gt 0 ] \
|| { MISSING+=("$PLUGIN_PATH/agents/ (empty or missing)"); HASH_FAIL=1; }
```

If `HASH_FAIL=1`, fire AUQ (Cancel-as-recommended pattern from risk_class:high):

- **Question:** `WARNING: integrity check failed — <list of missing files>. Continue?`
- **Options:**
- `Abort` — Exit without continuing; investigate (Recommended)
- `Continue anyway (NOT recommended)` — Proceed with possibly broken install

### Step 2 — User-content survival check

Re-resolve `$PRIMARY_ROOT` via the same Mode A snippet used in Phase 1 Step 2 — Bash environments don't persist across phases (the AUQ + plugin-update step runs in separate shell invocations). The post-update snapshot must scan the same tree as the pre-update one or the diff is meaningless; `$USER_SNAPSHOT` stashed by Phase 1 carries forward via the orchestrator's state, not the shell.

```bash
TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"
PRIMARY="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')"
if [ -z "$TOPLEVEL" ] || [ -z "$PRIMARY" ] || [ "$TOPLEVEL" = "$PRIMARY" ]; then
  PRIMARY_ROOT="."
else
  PRIMARY_ROOT="$PRIMARY"
fi

CURRENT_SNAPSHOT=$(find "$PRIMARY_ROOT/.geniro/instructions" "$PRIMARY_ROOT/.geniro/actions" -type f -name "*.md" 2>/dev/null \
| sort \
| xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}") {}"' 2>/dev/null)

if [ "$USER_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
diff <(echo "$USER_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") > /tmp/geniro-content-diff.log
# Fire AUQ below.
fi
```

If diff non-empty, AUQ:

- **Question:** `WARNING: user content under.geniro/instructions/ or.geniro/actions/ changed during update. Files affected: <list>. The plugin update should NOT touch user-authored content.`
- **Options:**
- `Show diff and continue (review later)` — Print diff, proceed to Phase 4
- `Abort — preserve current state` — Exit; investigate manually (Recommended)

### Step 3 — Refresh update cache

```bash
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" \
node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the new installed version.

### Step 4 — Refresh statusline stable copy (conditional)

```bash
if [ -f "$CLAUDE_USER_DIR/hooks/geniro-statusline.js" ]; then
mkdir -p "$CLAUDE_USER_DIR/hooks"
cp "$PLUGIN_PATH/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
fi
```

Skip if file doesn't exist (user didn't run `/setup` or has no `statusLine` settings entry). The plugin's bundled `settings.json` already exposes the statusline via `${CLAUDE_PLUGIN_ROOT}`.

Transition to Phase 4.

## Phase 4 — Migration

```bash
MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
# Transition to Phase 5.
fi
```

Parse MIGRATION.md, find entries between `v<CURRENT_VERSION>` (exclusive) and `v<NEW_VERSION>` (inclusive). The file follows the schema in *(internal)* — each release is `## v<X.Y.Z>`, each change is `### <name>` with `Action required:`, `Auto-detect:`, and `Severity:` fields.

For each entry, in chronological order:

1. Run the `Auto-detect:` shell command from the entry. Capture output.
2. If output empty → user not affected; log "skipped (not affected): <change-name>"; continue.
3. If output non-empty → AUQ:
- **Question:** `Breaking change in v<X.Y.Z>: <change-name>. <Action required text>. Auto-detected N affected files: <first 10 lines truncated>`
- **Options:**
- `Fix it for me (Recommended)` — Run the `Auto-fix:` commands from the MIGRATION.md entry. If the entry has no `Auto-fix:` field (manual-only migration), fall back to printing the manual instructions and continue. After fix, re-run `Auto-detect:` to verify — if still affected, warn and continue.
- `Show me how to fix manually` — Print the `Action required:` text with exact commands; continue to next entry.
- `Skip for now` — Log skipped; continue to next entry.
- `Cancel migration walk` — Stop here; log remaining; transition to Phase 5.

After last entry: transition to Phase 5.

If MIGRATION.md is present but malformed (cannot parse the heading structure), skip Phase 4 with one warning line: `[warn] MIGRATION.md present but malformed — proceeding without walk`.

**Auto-fix safety:** "Fix it for me" runs ONLY the `Auto-fix:` commands documented in MIGRATION.md — no improvised mutations. Each `Auto-fix:` command is written by the plugin maintainer and tested. Entries without `Auto-fix:` (marked `Auto-fix: manual-only`) require user action; the agent prints the manual steps instead.

## Phase 5 — Done

### Final report

```
✓ /geniro:update complete.

Updated: v<CURRENT_VERSION> → v<NEW_VERSION>
Plugin path: <PLUGIN_PATH>
Integrity check: <PASS | WARN>
User content: <UNCHANGED | CHANGED — see /tmp/geniro-content-diff.log>
Migration walked: <N changes — M applied, K skipped, L deferred>

⚠ RESTART your Claude Code session, then run /geniro:setup.

1. Restart — Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start.
   In-memory skill bodies still point at v<CURRENT_VERSION> until you restart.

2. Run /geniro:setup after restart — re-run mode will:
   • Auto-migrate your .geniro/ directory (rename files, add missing fields, clean orphans)
   • Regenerate CLAUDE.md with the updated skill table and conventions
   • Preserve your custom instructions, actions, and knowledge

If you have multiple repos with .geniro/, run /geniro:setup in each one after restart.
```

Restart + setup recommendation is **always emitted** by `/update` (unlike `/setup` which is conditional — `/update` IS a version transition by definition).

## Memory I/O

| Layer | Read | Write | Notes |
|---|---|---|---|
| L1 CLAUDE.md | not read | not written | `/setup re-run` handles CLAUDE.md refresh; `/update` only emits a recommendation if user-project CLAUDE.md may be stale |
| L2 learnings.jsonl | not read | not written | `/update` is operational, not knowledge-producing |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | snapshot+integrity check (Phase 1 Step 2; Phase 3 Step 2) | Written ONLY when user picks "Fix it for me" per-entry | Auto-fix runs MIGRATION.md commands; manual entries untouched |
| `.geniro/actions/*.md` (T3) | snapshot+integrity check | Written ONLY when user picks "Fix it for me" per-entry | Same |

## Anti-pattern check

| # | Anti-pattern | Status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md ~350 LOC; no helper sprawl needed |
| 2 | One giant tool | ✅ N/A — shell + python3 + native tools |
| 3 | Unbounded autonomous loop | ✅ 4-retry exponential backoff → abort; migration walk has explicit Cancel at every step |
| 4 | Autonomous external sends | ✅ N/A — marketplace fetches are inbound |
| 5 | No approval state | ✅ Pre-update AUQ; hash-fail AUQ; content-tamper AUQ; per-migration-step AUQ. Approvals[] persistence N/A (stateless, context-dependent) |
| 6 | No durable plans or goals | ✅ N/A — operational maintenance |
| 7 | No compaction strategy | ✅ N/A — `/update` is single-pass; survives natively via file-on-disk |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §ACI surface per phase; user content mutated ONLY via explicit "Fix it for me" AUQ pick per migration entry |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ✅ This SKILL.md has no timestamps. Hash fingerprints are runtime, never persisted to plugin |
| 12 | Non-deterministic agent registration order | ✅ N/A |

## Cross-references

- — 7 loop invariants (cited above)
- — quality-first budgets
- — per-phase ACI
- — restart-session warning (conditional for `/setup`; unconditional for `/update`)
- — validate rule set (referenced when surfacing `/geniro:instructions edit` recommendations)
- — Cancel-as-recommended AUQ pattern (used by hash-fail and content-tamper AUQs)
- CLAUDE.md "For git fetch/pull" — 4-retry exponential-backoff rule
- *(internal)* — full design rationale and MIGRATION.md schema
