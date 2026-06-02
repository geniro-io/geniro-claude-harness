---
name: geniro:update
description: "Use when the status line shows a plugin update is available, or to manually pull the latest geniro-claude-plugin version. Verifies plugin integrity, ensures user-authored .geniro/instructions/ and .geniro/actions/ survived intact, and walks any breaking changes in MIGRATION.md."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Write, Edit, Glob, Grep]
argument-hint: "[--dry-run]"
---

# /geniro:update — Update Plugin

4-phase loop: **Pre-check → Update → Post-check → Migration**. Stateless.

## Path Constraints

Pass `${CLAUDE_PLUGIN_ROOT}` (for plugin files) or an absolute path (for project files) to Read, Write, Edit, and Glob — these tools do not expand `~`, so a literal `~` directory gets created. Honor `CLAUDE_CONFIG_DIR` and fall back to `$HOME/.claude` only inside Bash blocks where `$HOME` expands correctly.

## Loop invariants

1. `/geniro:update` does NOT spawn subagents.
2. Args validated before exec — every shell call has its prereq checked (registry exists, plugin.json parseable, network reachable).
3. Permission before side-effect — the pre-update AUQ (§Phase 1 Step 3) is the explicit gate.
4. Bounded structured results — hash diffs truncated at ~2000 chars; per migration step at ~500 chars.
5. Hard escalation gates — 4-retry exponential-backoff (2s, 4s, 8s, 16s) on network errors; after 4 retries → abort.
6. Observations not assumed success — shell exit codes checked at every step.
7. Errors as structured observations — surfaced inline; no silent skips.

## Budgets — quality-first

`/geniro:update` has **zero hard kill caps**. Class-B gates: 4-retry network backoff, hash-diff truncation, per-migration-step truncation. NOT capped: migration walk step count, hash-check file count, total update duration.

## ACI surface per phase

| Phase | Allowed | Forbidden |
|---|---|---|
| `pre-check` | `Read`, `Bash` (`cat`, `grep`, `python3 -c "json.load"`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent`, all `mcp__*` |
| `update` | `Bash` (`claude plugin marketplace update`, `claude plugin update`, `python3 -c` to parse registry) | `Read`/`Write`/`Edit` on project files, `Agent`, `mcp__github__*` |
| `post-check` | `Read`, `Bash` (`sha256sum`, `stat`, `cp` for statusline refresh), `Glob` | `Edit` on project files outside `$CLAUDE_USER_DIR/hooks/`, `mcp__*` |
| `migration` | `Read`, `AskUserQuestion`, `Bash` (detect commands from MIGRATION.md + auto-fix commands when user picks "Fix it for me"), `Glob`, `Write`, `Edit` (only when user picks "Fix it for me" per-entry) | `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

External sends: not in `/geniro:update` ACI ever.

## Termination case → state mapping

| Cause | Message |
|---|---|
| Network error after 4 retries | `aborted: network error during plugin marketplace update after 4 retries` |
| Update succeeded but registry missing entry | `aborted: registry missing geniro-claude-plugin entry — see ~/.claude/plugins/installed_plugins.json` |
| Hash-check failed | `aborted: plugin integrity check failed — missing file(s) or manifest hash mismatch on <file>` |
| User-content tampering detected | AUQ surfaces; user picks Continue or Abort |
| MIGRATION.md walked successfully | `done` |
| MIGRATION.md walked, user aborted mid-walk | `aborted: user aborted migration walk at step <N>` |
| Already on latest version | `info: already on latest version (<version>)` — done |
| Hooks/registry write blocked | `aborted: blocked by hook — see <hint>` |

## Phase 1 — Pre-check

### Step 0 — Load custom instructions

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: update`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory. Per-skill `update.md` and `code-style.md` are NOT loaded — this is a meta-skill that updates the plugin itself, so the pipeline-tier files don't apply (helper §Caller contract `rules-only` list).

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

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A before the snapshot. The snapshot must capture user-authored content in the primary worktree — not whichever worktree the orchestrator currently sits in. `/geniro:update` is typically run from `main`, but the safe contract is to resolve explicitly so a session running in a linked worktree compares the right tree.

Resolve `PRIMARY_ROOT` by running the Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (single-sourced there — do not inline a copy). Then snapshot:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"
# PRIMARY_ROOT is set by the Mode A resolver run above.

# Snapshot user-content sha256 + mtime for survival verification
USER_SNAPSHOT=$(find "$PRIMARY_ROOT/.geniro/instructions" "$PRIMARY_ROOT/.geniro/actions" -type f -name "*.md" 2>/dev/null \
| sort \
| xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}" 2>/dev/null || stat -f%m "{}" 2>/dev/null) {}"' 2>/dev/null) || true
# The snapshot is best-effort (a benign trailing find/xargs status must not read as failure); survival is verified by the Phase 3 Step 2 diff, not this exit code.
# Persist the snapshot to a temp file — each Bash call runs in a fresh shell, so the shell variable does not survive to Phase 3 Step 2. The temp file is the carry-forward channel.
printf '%s\n' "$USER_SNAPSHOT" > /tmp/geniro-user-snapshot.txt
```

### Step 3 — Version-confirm AUQ

Use `AskUserQuestion`:

- **Question:** `Update geniro-claude-plugin? Current version: v<CURRENT_VERSION>. This will run marketplace + plugin update, verify integrity, and walk MIGRATION.md.`
- **Options:**
- `Confirm update` — Run the update flow (Recommended)
- `Cancel` — Exit without updating

On `Cancel` → terminate with `info: update cancelled by user`. On `Confirm update` → transition to Phase 2.

If `--dry-run` was passed in `$ARGUMENTS`, **skip the AUQ entirely** and instead read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md` (the currently-installed copy, before any marketplace fetch — `$PLUGIN_PATH` is not set until Phase 2 Step 2, which dry-run skips); print "what would happen" and exit. `--dry-run` does NOT modify any files.

## Phase 2 — Update

### Step 1 — Marketplace refresh + plugin update (exponential backoff)

On network errors — 4 retries with 2s / 4s / 8s / 16s backoff:

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

Re-resolve `PRIMARY_ROOT` by running the same Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` used in Phase 1 Step 2 — Bash environments don't persist across phases (the AUQ + plugin-update step runs in separate shell invocations). The post-update snapshot must scan the same tree as the pre-update one or the diff is meaningless. The pre-update snapshot carries forward through the temp file `/tmp/geniro-user-snapshot.txt` written in Phase 1 Step 2, not through a shell variable — read it back below.

```bash
# PRIMARY_ROOT is set by the Mode A resolver run above.
# Read the pre-update snapshot back from the temp file written in Phase 1 Step 2.
USER_SNAPSHOT=$(cat /tmp/geniro-user-snapshot.txt 2>/dev/null)

CURRENT_SNAPSHOT=$(find "$PRIMARY_ROOT/.geniro/instructions" "$PRIMARY_ROOT/.geniro/actions" -type f -name "*.md" 2>/dev/null \
| sort \
| xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}" 2>/dev/null || stat -f%m "{}" 2>/dev/null) {}"' 2>/dev/null)

if [ -z "$USER_SNAPSHOT" ]; then
echo "[info] pre-update snapshot missing or empty — skipping tamper diff (cannot compare against a baseline that was never recorded)."
elif [ "$USER_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
diff <(printf '%s\n' "$USER_SNAPSHOT") <(printf '%s\n' "$CURRENT_SNAPSHOT") > /tmp/geniro-content-diff.log
# Fire AUQ below.
fi
```

If diff non-empty, AUQ:

- **Question:** `WARNING: user content under .geniro/instructions/ or .geniro/actions/ changed during update. Files affected: <list>. The plugin update should NOT touch user-authored content.`
- **Options:**
- `Show diff and continue (review later)` — Print diff, then continue to the migration walk
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

Skip if file doesn't exist (user didn't run `/geniro:setup` or has no `statusLine` settings entry). The plugin's bundled `settings.json` already exposes the statusline via `${CLAUDE_PLUGIN_ROOT}`.

Transition to Phase 4.

## Phase 4 — Migration

```bash
MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
exit 0
fi
```

When MIGRATION.md is absent, there are no breaking changes to walk — skip the rest of Phase 4 and go straight to the Done — Final report below.

Otherwise, parse MIGRATION.md and collect **every** `### <name>` entry across **all** `## v<X.Y.Z>` sections — per the consumption contract in MIGRATION.md's preamble. The version heading groups entries into feature cohorts for readability; it is not a selection gate. The `## vX.Y.Z` axis tracks plugin features, not the package's semver, so a feature can already be live in this install even when its heading version sits outside the `<CURRENT_VERSION> → <NEW_VERSION>` package range — gating on the heading would silently skip it. Run each entry's read-only `Auto-detect:` command and let its output decide relevance (empty → already current → skipped). The file follows this schema — each release is `## v<X.Y.Z>`, each change is `### <name>` with `Action required:`, `Auto-detect:`, `Auto-fix:`, and `Severity:` fields.

For each entry, in file order (newest cohort first — entries are independent, so order does not affect which fire):

1. Run the entry's `Auto-detect:` shell command via `bash -c '<command>'`. Run under bash regardless of the user's interactive shell: an unmatched glob stays literal under bash but aborts the command under zsh's default `nomatch`, which would halt the walk. Run each entry's command in isolation so one failing detect cannot cascade into the rest. Capture output.
2. If output empty → user not affected; log "skipped (not affected): <change-name>"; continue.
3. If output non-empty → AUQ:
- **Question:** `Breaking change in v<X.Y.Z>: <change-name>. <Action required text>. Auto-detected N affected files: <first 10 lines truncated>`
- **Options:**
- `Fix it for me (Recommended)` — Run the `Auto-fix:` commands from the MIGRATION.md entry via `bash -c` (same shell-safety reason as the detect). If the entry has no `Auto-fix:` field (manual-only migration), fall back to printing the manual instructions and continue. After fix, re-run `Auto-detect:` via `bash -c` to verify — if still affected, warn and continue.
- `Show me how to fix manually` — Print the `Action required:` text with exact commands; continue to next entry.
- `Skip for now` — Log skipped; continue to next entry.
- `Cancel migration walk` — Stop here; log remaining; terminate and emit final report.

After last entry: terminate and emit final report.

If MIGRATION.md is present but malformed (cannot parse the heading structure), skip Phase 4 with one warning line: `[warn] MIGRATION.md present but malformed — proceeding without walk`.

**Auto-fix safety:** "Fix it for me" runs ONLY the `Auto-fix:` commands documented in MIGRATION.md — no improvised mutations. Each `Auto-fix:` command is written by the plugin maintainer and tested. Entries without `Auto-fix:` (marked `Auto-fix: manual-only`) require user action — print the manual steps instead.

## Done — Final report

`/geniro:update` always emits the restart warning — a version transition leaves in-memory skill bodies pointing at the old version until the session restarts. The `/geniro:setup` re-run recommendation is **conditional**: `/geniro:setup`'s only work `/geniro:update` has not already done is regenerate the project CLAUDE.md (its `.geniro/` migration sweep re-walks the same MIGRATION.md entries Phase 4 just walked), so recommend it only when the run leaves setup-relevant work.

Recommend `/geniro:setup` (append the re-setup section below) when ANY of these hold:

- Phase 4 surfaced at least one applicable MIGRATION.md entry — any entry whose `Auto-detect:` returned non-empty for this install (i.e. you fired its AUQ). Applied, deferred, or skipped, that work still needs follow-through.
- The major (first) version component increased (e.g. `2.13.0 → 3.0.0`). A major release can refresh the skill table or conventions without any per-entry `Auto-detect:` firing, so CLAUDE.md may be stale even at zero applicable entries.
- The Phase 3 user-content survival diff reported `CHANGED`.

Otherwise — a clean minor/patch transition with no applicable entries, no major bump, and user content intact — emit the restart warning alone. Appending a step to regenerate an already-current CLAUDE.md is empty friction.

### Final report

Emit the report below. When none of the three conditions above hold (a clean minor/patch transition), drop the final paragraph — everything from "After restart, run /geniro:setup" onward — and end at the restart warning.

```
✓ /geniro:update complete.

Updated: v<CURRENT_VERSION> → v<NEW_VERSION>
Plugin path: <PLUGIN_PATH>
Integrity check: <PASS | WARN>
User content: <UNCHANGED | CHANGED — see /tmp/geniro-content-diff.log>
Migration walked: <N changes — M applied, K skipped, L deferred>

⚠ RESTART your Claude Code session to load v<NEW_VERSION>.
   Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start — in-memory
   skill bodies still point at v<CURRENT_VERSION> until you restart.

After restart, run /geniro:setup — re-run mode will:
   • Auto-migrate your .geniro/ directory (rename files, add missing fields) — safe mechanical fixes apply silently; destructive cleanups like orphan deletion are surfaced for your review, not auto-applied, so anything you deferred in this walk is never silently reversed
   • Regenerate CLAUDE.md with the updated skill table and conventions
   • Preserve your custom instructions, actions, and knowledge

If you have multiple repos with .geniro/, run /geniro:setup in each one after restart.
```

## Memory I/O

| Layer | Read | Write | Notes |
|---|---|---|---|
| L1 CLAUDE.md | not read | not written | `/geniro:setup re-run` handles CLAUDE.md refresh; `/geniro:update` only emits a recommendation if user-project CLAUDE.md may be stale |
| L2 learnings.jsonl | not read | not written | `/geniro:update` is operational, not knowledge-producing |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | snapshot+integrity check (Phase 1 Step 2; Phase 3 Step 2) | Written ONLY when user picks "Fix it for me" per-entry | Auto-fix runs MIGRATION.md commands; manual entries untouched |
| `.geniro/actions/*.md` (T3) | snapshot+integrity check | Written ONLY when user picks "Fix it for me" per-entry | Same |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "My recalled experience says the MIGRATION.md version headings don't match the package version, so I'll range-filter or read only the newest block." | A recalled learning does not override the walk-all consumption contract. The version heading is not a selection gate — walk EVERY entry across ALL sections (Phase 4) and let each read-only auto-detect decide relevance. The current skill body and the MIGRATION.md preamble are authoritative over any prior-session recollection. |

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — Phase 1 Step 0 rules load.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` — Mode A resolver for `PRIMARY_ROOT` (Phase 1 Step 2, Phase 3 Step 2).
