---
name: update
description: "Use when the status line shows a plugin update is available, or to manually pull the latest Geniro plugin version. Verifies plugin integrity, ensures user-authored .geniro/instructions/ and .geniro/actions/ survived intact, and walks any breaking changes in MIGRATION.md."
context: main
model: inherit
allowed-tools: [Bash, AskUserQuestion, Read, Write, Edit, Glob, Grep]
argument-hint: "[--dry-run]"
---

# /geniro:update — update plugin

## Contents

- Path constraints
- Loop invariants
- Anti-rationalization
- Budgets — quality-first
- ACI per-phase tool surface
- Termination case → message
- User-content snapshot
- Phase 1 — pre-check · Phase 2 — update · Phase 3 — post-check · Phase 4 — migration
- Done — final report
- Memory I/O
- REFERENCE

---

4-phase loop: **Pre-check → Update → Post-check → Migration**. Stateless.

**Runtime requirement.** This skill drives the `claude plugin` CLI and the Claude Code install registry, and functions only under Claude Code. When invoked from another runtime (e.g. Cursor), state that updates are managed by that runtime's own plugin mechanism and exit without side effects.

**After a compaction, re-invoke this skill before running a phase whose steps are not in context** — only the first ~5,000 tokens of a skill are re-attached after a summary, and `/geniro:update` keeps no state file, so re-read the phase you were in before continuing it.

## Path constraints

Pass `${CLAUDE_PLUGIN_ROOT}` (for plugin files) or an absolute path (for project files) to Read, Write, Edit, and Glob — these tools do not expand `~`, so a literal `~` directory gets created. Honor `CLAUDE_CONFIG_DIR` and fall back to `$HOME/.claude` only inside Bash blocks where `$HOME` expands correctly.

## Loop invariants

The canonical loop invariants 1-7 (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with five update-specific bindings:

- **Invariant #2 (args validated before execution)** — every shell call has its prereq checked (registry exists, plugin.json parseable, network reachable).
- **Invariant #3 (permission before side-effect)** — the pre-update AUQ (§Phase 1 Step 3) is the explicit gate.
- **Invariant #4 (bounded structured tool results)** — the migration-step AUQ truncates auto-detect output to its first ~10 lines; the full content diff is written to a log file rather than inlined.
- **Invariant #5 (escalation gates, not silent abort)** — 4-retry exponential-backoff on network errors; abort after the 4th retry. (Step 1 owns the exact delays.)
- **Invariant #7 (errors → structured observations)** — this skill is stateless, so errors surface inline in the run's output rather than in a state-file `## Errors` section; no silent skips.

This skill adds one invariant:

8. **No subagent spawns.** `/geniro:update` does NOT spawn subagents — every phase runs inline in the orchestrator.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "My recalled experience says the MIGRATION.md version headings don't match the package version, so I'll range-filter or read only the newest block." | A recalled learning does not override the walk-all consumption contract. The version heading is not a selection gate — walk EVERY entry across ALL sections (Phase 4) and let each read-only auto-detect decide relevance. The current skill body and the MIGRATION.md preamble are authoritative over any prior-session recollection. |
| "The version-confirm AUQ is a formality — I'll just run the update." | That AUQ is the one explicit permission gate before a mutating marketplace + plugin update touches the install. Skipping it removes the user's only chance to cancel before the network fetch and registry write. Fire it unless `--dry-run`. |
| "I ran the Auto-fix command, so the migration entry is resolved." | Auto-fix can apply partially. Re-run the entry's `Auto-detect:` after fixing; only an empty result confirms resolution. Reporting "fixed" without the re-detect can leave the user on a half-migrated install. |
| "A file is missing from the hash-check but the update likely worked — continue." | A missing key file means a broken install, not a benign blip. Fire the Cancel-as-recommended AUQ and let the user decide; auto-continuing ships a plugin that may fail mid-skill later. |
| "The user-content survival diff shows changes, but they're probably benign." | The update must never touch `.geniro/instructions/` or `.geniro/actions/`. Any diff is either a plugin bug or tampering — surface it via the AUQ; never auto-dismiss content the user authored. |

## Budgets — quality-first

`/geniro:update` has **zero hard kill caps**. Class-B gates: 4-retry network backoff, hash-diff truncation, per-migration-step truncation. NOT capped: migration walk step count, hash-check file count, total update duration.

## ACI per-phase tool surface

| Phase | Allowed | Forbidden |
|---|---|---|
| `pre-check` | `Read`, `Bash` (`cat`, `grep`, `python3 -c "json.load"`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, mutating `Bash`, `Agent`, all `mcp__*` |
| `update` | `Bash` (`claude plugin marketplace update`, `claude plugin update --scope user`, `claude plugin install --scope user` for the global-install repair, `python3 -c` to parse registry) | `Read`/`Write`/`Edit` on project files, `Agent`, `mcp__github__*` |
| `post-check` | `Read`, `Bash` (`sha256sum` or `shasum -a 256` on macOS, `stat`, `cp` for statusline refresh), `Glob` | `Edit` on project files outside `$CLAUDE_USER_DIR/hooks/`, `mcp__*` |
| `migration` | `Read`, `AskUserQuestion`, `Bash` (detect commands from MIGRATION.md + auto-fix commands when user picks "Fix it for me"), `Glob`, `Write`, `Edit` (only when user picks "Fix it for me" per-entry) | `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

External sends: not in `/geniro:update` ACI ever.

## Termination case → message

| Cause | Message |
|---|---|
| Network error after 4 retries | `aborted: network error during plugin marketplace update after 4 retries` |
| Install recorded under the legacy plugin id | `aborted: plugin renamed — reinstall required` (Phase 1 Step 1.5 prints the reinstall commands) |
| Update succeeded but registry missing entry | `aborted: registry missing the geniro plugin entry — see ~/.claude/plugins/installed_plugins.json` |
| Hash-check failed | `aborted: plugin integrity check failed — missing file(s) or manifest hash mismatch on <file>` |
| User-content tampering detected | AUQ surfaces; user picks Continue or Abort |
| MIGRATION.md walked successfully | `done` |
| MIGRATION.md walked, user aborted mid-walk | `aborted: user aborted migration walk at step <N>` |
| Already on latest version | `info: already on latest version (<version>)` — done |
| Hooks/registry write blocked | `aborted: blocked by hook — see <hint>` |

## User-content snapshot

The one definition of the snapshot, used by Phase 1 Step 2 (baseline) and Phase 3 Step 2 (comparison). Both phases must run identical code: a second copy that drifted by one flag would make the survival diff raise a tamper alarm over content nothing touched. Shell state does not persist between Bash calls, so each phase pastes these definitions into its own call and passes the `PRIMARY_ROOT` it just re-resolved.

```bash
# One "<sha256> <mtime> <path>" line per user-authored file, sorted. $1 = PRIMARY_ROOT.
_gu_snapshot() {
  find "$1/.geniro/instructions" "$1/.geniro/actions" -type f -name "*.md" 2>/dev/null \
  | sort \
  | while IFS= read -r f; do
      h=$({ sha256sum "$f" 2>/dev/null || shasum -a 256 "$f" 2>/dev/null; } | cut -d' ' -f1)
      printf '%s %s %s\n' "$h" "$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null)" "$f"
    done
}

# Carry-forward channel between the two phases. The PRIMARY_ROOT hash in the filename keeps
# concurrent /update sessions in different repos from clobbering each other's baseline. $1 = PRIMARY_ROOT.
_gu_snapshot_file() {
  printf '/tmp/geniro-user-snapshot.%s.txt' \
    "$(printf '%s' "$1" | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -c1-12)"
}
```

## Phase 1 — pre-check

### Step 0 — Load custom instructions

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: update`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory. Per-skill `update.md` and `code-style.md` are NOT loaded — this is a meta-skill that updates the plugin itself, so the pipeline-tier files don't apply (helper §Caller contract `rules-only` list).

### Step 1 — Read current version

Read `version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` into `CURRENT_VERSION`. Abort when it cannot be read — the already-on-latest check, the major-bump test, and the final report all compare against it, and an "unknown" baseline makes each of them silently wrong rather than absent.

### Step 1.5 — Legacy install-id check

An install still recorded under the legacy `geniro-claude-plugin` id cannot be updated in place — `claude plugin update` resolves ids exactly, and that id no longer exists in the marketplace. Detect it before spending a network round-trip on a command that cannot succeed:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LEGACY=$(python3 -c "
import json
try:
    d = json.load(open('$CLAUDE_USER_DIR/plugins/installed_plugins.json'))
    print('yes' if any(k.startswith('geniro-claude-plugin@') for k in d.get('plugins', {})) else 'no')
except Exception:
    print('no')
")
```

When `LEGACY=yes`, print the reinstall block below verbatim and terminate with `aborted: plugin renamed — reinstall required` (Termination case: legacy install id). Do not attempt the update, and do not run the reinstall yourself — it uninstalls the plugin currently executing this skill, so the user runs it:

```
The plugin was renamed geniro-claude-plugin → geniro. Update in place is not
possible across an id change. Run these three commands, then restart the session:

  claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
  claude plugin marketplace update geniro-claude-harness
  claude plugin install geniro@geniro-claude-harness --scope user

Your project files under .geniro/ are untouched — instructions, actions,
planning artifacts, and learnings all survive the reinstall.
Commands change from /geniro-claude-plugin:geniro:<skill> to /geniro:<skill>.
```

### Step 2 — Resolve `$CLAUDE_USER_DIR`, `$PRIMARY_ROOT`, and snapshot user content

Resolve `PRIMARY_ROOT` by running the Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (single-sourced there — do not inline a copy). The snapshot must capture user-authored content in the primary worktree, not whichever worktree the orchestrator currently sits in: `/geniro:update` is typically run from `main`, but a session in a linked worktree would otherwise compare the wrong tree.

Then take the baseline snapshot:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"
# PRIMARY_ROOT is set by the Mode A resolver, which runs inside THIS Bash call —
# each Bash call is a fresh shell, so a value resolved in an earlier call is gone.

# --- paste the §User-content snapshot definitions here ---

_gu_snapshot "$PRIMARY_ROOT" > "$(_gu_snapshot_file "$PRIMARY_ROOT")" || true
```

The redirect is best-effort — a benign trailing `find`/read status must not read as failure. Survival is verified by the Phase 3 Step 2 diff, not by this exit code.

### Step 3 — Version-confirm AUQ

Use `AskUserQuestion`:

- **Question:** `Update the Geniro plugin? Current version: v<CURRENT_VERSION>. This will run marketplace + plugin update, verify integrity, and walk MIGRATION.md.`
- **Options:**
- `Confirm update` — Run the update flow (Recommended)
- `Cancel` — Exit without updating

On `Cancel` → terminate with `info: update cancelled by user`. On `Confirm update` → transition to Phase 2.

If `--dry-run` was passed in `$ARGUMENTS`, **skip the AUQ entirely** and instead read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md` (the currently-installed copy, before any marketplace fetch — `$PLUGIN_PATH` is not set until Phase 2 Step 2, which dry-run skips); print "what would happen" and exit. `--dry-run` does NOT modify any files.

## Phase 2 — update

### Step 1 — Marketplace refresh + plugin update (exponential backoff)

Run the marketplace update, then the plugin update, each retried up to 4× on network error with 2s / 4s / 8s / 16s backoff between attempts; abort with a non-zero exit if either still fails after the 4th attempt (Termination case: network error after 4 retries):

1. `claude plugin marketplace update geniro-claude-harness`
2. `claude plugin update geniro@geniro-claude-harness --scope user`

Pass `--scope user` explicitly. The plugin is meant to be available in every directory, which is the user (global) scope — the install record that the global `enabledPlugins` entry in `settings.json` resolves against. Updating without the flag lets the CLI target whichever scope matches the current working directory; when a project-scoped install record exists for the cwd, the user-scope record gets dropped and the plugin then loads only in that one project (it disappears everywhere else). Pinning the scope keeps the global install authoritative.

### Step 1.5 — Restore the global install if it went missing

After the update, confirm a `user`-scope install record still exists. A prior update run (before the `--scope user` pin) may have left the plugin project-scoped only — in which case it loads nowhere except that one project. Re-install at user scope to repair it:

```bash
# Re-resolve REGISTRY — each Bash call runs in a fresh shell, so the Phase 1 definition does not survive.
REGISTRY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"

HAS_USER_SCOPE=$(python3 -c "
import json
try:
    d = json.load(open('$REGISTRY'))
    entry = d['plugins'].get('geniro@geniro-claude-harness', [])
    print('yes' if any(e.get('scope') == 'user' for e in entry) else 'no')
except Exception:
    print('unknown')
")

if [ "$HAS_USER_SCOPE" = "no" ]; then
  echo "[repair] no global install record found — restoring user-scope install so the plugin loads in every directory." >&2
  claude plugin install geniro@geniro-claude-harness --scope user 2>&1 | tee /tmp/geniro-plugin-repair.log || true
fi
```

When the repair runs, tell the user in plain English that the plugin's global install was restored — it had been left available in only one project, and is now back in every directory.

### Step 2 — Discover new plugin path

```bash
# Re-resolve REGISTRY — each Bash call runs in a fresh shell, so the Phase 1 definition
# does not survive. CURRENT_VERSION cannot be re-read: plugin.json now holds the NEW
# version, so substitute the literal value Phase 1 Step 1 read.
REGISTRY="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
CURRENT_VERSION="<the version read in Phase 1 Step 1>"

if [ ! -f "$REGISTRY" ]; then
echo "ERROR: registry not found at $REGISTRY — abort." >&2
echo "Hint: if you use a custom config dir, ensure CLAUDE_CONFIG_DIR is exported." >&2
exit 1
fi

PLUGIN_PATH=$(python3 -c "
import json, sys
try:
d = json.load(open('$REGISTRY'))
entry = d['plugins'].get('geniro@geniro-claude-harness', [])
# Prefer the user-scope (global) install — the one this skill keeps authoritative.
# Fall back to the first record only if no user-scope entry exists.
chosen = next((e for e in entry if e.get('scope') == 'user'), entry[0] if entry else None)
print(chosen['installPath'] if chosen else '')
except Exception as e:
print(f'PARSE_ERROR: {e}', file=sys.stderr)
sys.exit(1)
")

if [ -z "$PLUGIN_PATH" ]; then
echo "ERROR: registry parsed but no entry for the geniro plugin — abort." >&2
exit 1
fi

NEW_VERSION=$(cat "$PLUGIN_PATH/.claude-plugin/plugin.json" \
| python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")

if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
echo "[info] already on latest version (v$NEW_VERSION) — nothing to do."
# Same refresh as Phase 3 Step 3. The status line renders straight from this cache and
# nothing else rewrites it before the next session start — exiting without it leaves the
# "update available" arrow lit for the rest of the session, in the run meant to clear it.
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" \
node "$PLUGIN_PATH/hooks/geniro-check-update.js"
exit 0
fi

echo "PLUGIN_PATH=$PLUGIN_PATH"
echo "NEW_VERSION=$NEW_VERSION"
```

Carry both echoed values forward by literal substitution: every later fenced block re-assigns them at its top, because each Bash call runs in a fresh shell and nothing else recomputes them.

Transition to Phase 3.

## Phase 3 — post-check

### Step 1 — Plugin file hash-check (sanity mode)

If the new plugin publishes `$PLUGIN_PATH/.claude-plugin/manifest.sha256`, verify each file via `sha256sum -c` (or `shasum -a 256 -c` on macOS, which ships no `sha256sum`). Otherwise (no manifest published), sanity-check that key files exist:

```bash
# Fresh shell — re-assign from the value Phase 2 Step 2 echoed.
PLUGIN_PATH="<the path Phase 2 Step 2 echoed>"

HASH_FAIL=0
MISSING=()
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

If `HASH_FAIL=1`, fire AUQ (Cancel-as-recommended — a hash-check failure means the download may be corrupted or tampered, so default the user to Cancel):

- **Question:** `Integrity check failed — ${MISSING[*]}. Continue anyway?`
- **Options:**
- `Abort` — Exit without continuing; investigate (Recommended)
- `Continue anyway (not recommended)` — Proceed with possibly broken install

### Step 2 — User-content survival check

Re-resolve `PRIMARY_ROOT` by running the same Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` used in Phase 1 Step 2 — Bash environments don't persist across phases (the AUQ + plugin-update step runs in separate shell invocations). The post-update snapshot must scan the same tree as the pre-update one, and must be computed by the same code, or the diff is meaningless. Paste the §User-content snapshot definitions into this call and pass the re-resolved `PRIMARY_ROOT` — that recomputes the baseline's filename and reads it back.

```bash
# PRIMARY_ROOT is set by the Mode A resolver, which runs inside THIS Bash call.
# --- paste the §User-content snapshot definitions here ---

USER_SNAPSHOT=$(cat "$(_gu_snapshot_file "$PRIMARY_ROOT")" 2>/dev/null)
CURRENT_SNAPSHOT=$(_gu_snapshot "$PRIMARY_ROOT")

if [ -z "$USER_SNAPSHOT" ]; then
echo "[info] pre-update snapshot missing or empty — skipping tamper diff (cannot compare against a baseline that was never recorded)."
elif [ "$USER_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
diff <(printf '%s\n' "$USER_SNAPSHOT") <(printf '%s\n' "$CURRENT_SNAPSHOT") > /tmp/geniro-content-diff.log
# Fire AUQ below.
fi
```

If diff non-empty, AUQ:

- **Question:** `User content under .geniro/instructions/ or .geniro/actions/ changed during the update. Files affected: <list>. The plugin update should not touch user-authored content — review before continuing.`
- **Options:**
- `Show diff and continue (review later)` — Print diff, then continue to the migration walk
- `Abort — preserve current state` — Exit; investigate manually (Recommended)

### Step 3 — Refresh update cache

```bash
# Fresh shell — re-assign from the value Phase 2 Step 2 echoed.
PLUGIN_PATH="<the path Phase 2 Step 2 echoed>"

GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" \
node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

This writes `update_available: false` to the cache with the new installed version.

### Step 4 — Refresh statusline stable copy (conditional)

Only when `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` already exists, overwrite it from `$PLUGIN_PATH/hooks/geniro-statusline.js`. Its absence means the user never ran `/geniro:setup` or has no `statusLine` settings entry — creating the file there would install a statusline they never asked for. The plugin's bundled `settings.json` already exposes the statusline via `${CLAUDE_PLUGIN_ROOT}`.

Transition to Phase 4.

## Phase 4 — migration

```bash
# Fresh shell — re-assign from the values Phase 2 Step 2 echoed.
PLUGIN_PATH="<the path Phase 2 Step 2 echoed>"
NEW_VERSION="<the version Phase 2 Step 2 echoed>"

MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
exit 0
fi
```

When MIGRATION.md is absent, there are no breaking changes to walk — skip the rest of Phase 4 and go straight to the Done — Final report below.

Otherwise walk `$MIGRATION_FILE` — the copy just installed — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md`: it parses the entries, runs each `Auto-detect:` behind its `N/A` guard, and classifies each entry as applicable or not. Log each not-affected entry as `skipped (not affected): <change-name>` and continue. This section owns the apply policy — what happens to an entry the helper classified as applicable.

For each applicable entry: **live-task guard, then AUQ.**

**Live-task guard (delete-class entries only).** When the entry's `Auto-fix:` is delete-class (contains `rm`, `-delete`, or `-exec rm`) and any detected path sits inside a task-dir (`.geniro/planning/<task-dir>/` or `.geniro/state/<skill>/<slug>/`), read each owning dir's `state.md` before building the AUQ: the task is live when `state.md` exists with a non-terminal `phase:`/`status:` (the same terminal-state test the session-start restore hook applies; when unsure, treat the task as live). A maintainer-written auto-fix matches paths mechanically and cannot know which task is mid-run — the walk supplies that check. Live-task paths are excluded from `Fix it for me` and named in the AUQ question; they re-detect as orphans once their task finishes. Never delete a live task's files even when the documented command would match them.

- **Question:** `Breaking change in v<X.Y.Z>: <change-name>. <Action required text>. Auto-detected N affected files: <first 10 lines truncated>` — when the guard excluded live-task paths, append `; <M> of these belong to a live task (<dir>: <phase/status>) and are excluded from the fix`.
- **Options:**
- `Fix it for me (Recommended)` — Run the `Auto-fix:` commands from the MIGRATION.md entry via `bash -c` (same shell-safety reason as the detect). When the guard excluded live-task paths, do NOT run the blanket documented command — apply the same operation restricted to the orphan path set (narrowing the target set is the one sanctioned deviation; the operation itself stays as documented). If the entry's `Auto-fix:` value begins with `manual-only` (matched case-insensitively, so `Manual-only` is caught too) or the field is absent, fall back to printing the manual instructions and continue. After the fix, verify per the shared walk §6 — if still affected, warn and continue; paths the guard deliberately kept are expected to re-detect on a status-blind detector — log those as deferred-live, not as a fix failure.
- `Show me how to fix manually` — Print the `Action required:` text with exact commands; continue to next entry.
- `Skip for now` — Log skipped; continue to next entry.
- `Cancel migration walk` — Stop here; log remaining; terminate and emit final report.

After last entry: terminate and emit final report.

When the shared walk reports the file as malformed (§3 there), skip the rest of Phase 4 and emit its warning line here: `[warn] MIGRATION.md present but malformed — proceeding without walk`.

**Auto-fix safety:** each `Auto-fix:` command is written by the plugin maintainer and tested, so "Fix it for me" runs those commands and nothing else — an improvised fix is untested against the install it is about to mutate.

## Done — final report

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
| CLAUDE.md (project context) | not read | not written | `/geniro:setup re-run` handles CLAUDE.md refresh; `/geniro:update` only emits a recommendation if user-project CLAUDE.md may be stale |
| L2 learnings.jsonl | not read | not written | `/geniro:update` is operational, not knowledge-producing |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | snapshot+integrity check (Phase 1 Step 2; Phase 3 Step 2) | Written ONLY when user picks "Fix it for me" per-entry | Auto-fix runs MIGRATION.md commands; manual entries untouched |
| `.geniro/actions/*.md` (T3) | snapshot+integrity check | Written ONLY when user picks "Fix it for me" per-entry | Same |

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` — the canonical invariants 1-7 the §Loop invariants bindings extend.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — Phase 1 Step 0 rules load.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` — Mode A resolver for `PRIMARY_ROOT` (Phase 1 Step 2, Phase 3 Step 2).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md` — Phase 4 parse / auto-detect / classify / re-verify procedure shared with the `/geniro:setup` re-run sweep.
