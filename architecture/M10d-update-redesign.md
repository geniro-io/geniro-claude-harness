# M10d — `/geniro:update` redesign

**Milestone:** M10 (operational skills) — part **d** of 4. Companion to M10a (`/setup`), M10b (`/instructions`), M10c (`/actions`).

**Status:** Decided 2026-05-19. Builds on M1 (no state — stateless single-pass operation), M10a (`/setup` re-run mode handles post-update CLAUDE.md refresh — see M10a §10.3), M10b/M10c (user-authored content under `.geniro/instructions/` and `.geniro/actions/` MUST survive plugin updates intact).

**Cross-cutting closures landing here:**

- **Q6 decision** — `/update` scope expanded to **wrapper + integrity check + MIGRATION.md reader**. Most-ambitious of the three Q6 options. M10d specs the MIGRATION.md contract that plugin maintainers populate going forward.
- **OQ-M10a-2 partial** — plugin-side breaking changes (e.g., a previously-spun-out `.geniro/docs/<topic>.md` template changed in the new plugin version) surfaced in MIGRATION.md and walked by `/update` Phase Migration.

---

## 1. Purpose

Upgrade the plugin in-place to the latest version available via the Claude Code marketplace, then verify that **(a)** plugin files installed cleanly, **(b)** user-authored content (`.geniro/instructions/`, `.geniro/actions/`, user-edited `CLAUDE.md`) survived the upgrade untouched, and **(c)** any breaking changes documented in `MIGRATION.md` are surfaced to the user with concrete next-step guidance.

**Why not just `claude plugin update geniro-claude-plugin@geniro-claude-harness`?** Three reasons:

1. **Plugin path resolves once per session** — after `claude plugin update`, the in-memory `${CLAUDE_PLUGIN_ROOT}` still points to the OLD version. The update cache and stable-copy statusline script must be refreshed against the NEW path; `/update` does both atomically.
2. **User content needs a survival check** — `.geniro/instructions/*.md` and `.geniro/actions/*.md` are user-authored and must NOT be touched by an update. A post-update hash check verifies this; the integrity check exists because the alternative is silent data loss.
3. **Breaking changes need guided application** — if v1.5 renamed `phase: implement_step_1` to `phase: IMPLEMENT`, user-authored `.geniro/instructions/implement.md` files may have stale subsection headers. `/update` reads `MIGRATION.md` and walks the user through fixes.

**Anti-goal:** No autonomous file mutation outside the plugin install path. `/update` never edits user content; if MIGRATION.md says "user must rename a phase header," `/update` surfaces a `/geniro:instructions edit implement` suggestion, but does not auto-edit.

---

## 2. Architecture overview

### 2.1 State machine

`/update` is **stateless** (per M10a Q5). The phase enum below describes runtime flow only.

```
init
  │
  ▼
pre-check
  │ read current version from plugin.json; locate $CLAUDE_USER_DIR + registry
  │ verify pre-update state (existence of .geniro/instructions/* + .geniro/actions/*)
  ▼
update
  │ shell call: claude plugin marketplace update + claude plugin update
  │ discover new install path from registry
  ▼
post-check
  │ hash-check plugin files + verify user-authored content untouched
  │ refresh update-cache + refresh stable statusline copy
  ▼
migration
  │ if MIGRATION.md exists in new plugin AND new version > old version → read it, walk user
  ▼
done
       │
       └─ failed (network error, version not found, hash-check failed,
                  user-content tampered, MIGRATION.md walked then aborted by user)
```

### 2.1.1 Termination case → state mapping

| Termination cause | Message format |
|---|---|
| Network error during marketplace update (after exponential-backoff retry per CLAUDE.md git/network rules) | `aborted: network error during plugin marketplace update after 4 retries` |
| Update succeeded but new plugin path not found in registry | `aborted: registry missing geniro-claude-plugin entry after update — see ~/.claude/plugins/installed_plugins.json` |
| Hash-check failed (plugin file corrupted) | `aborted: plugin integrity check failed — manifest hash mismatch on <file>` |
| User-content tampering detected (e.g., `.geniro/instructions/global.md` modified-time changed during update) | `WARNING: user content under .geniro/instructions/global.md was modified during update; please verify file integrity. Continue?` (AUQ — non-terminal; user picks Continue or Abort) |
| MIGRATION.md walked successfully | `done` |
| MIGRATION.md walked, user aborted mid-walk | `aborted: user aborted migration walk at step <N>; new plugin version is installed but breaking changes not yet applied` |
| No update available (already on latest) | `info: already on latest version (<version>)` — DONE |
| Restart-session warning emitted | DONE |

### 2.2 Loop invariants

Per M4 §2.2:

1. **One result per subagent call** — `/update` does NOT spawn subagents. All work is orchestrator-direct.
2. **Args validated before exec** — every shell call has its prereq checked (registry exists, plugin.json parseable, network reachable).
3. **Permission before side-effect** — `claude plugin update` is shell-invoked but **must be AUQ-gated**: the user explicitly invoked `/update` so the AUQ is at the very start ("Update geniro-claude-plugin from v1.4.2 to v1.5.0? (Confirm | Cancel)").
4. **Bounded structured results** — hash-check output truncated; MIGRATION.md walk steps truncated per-step at ~500 chars.
5. **Hard escalation gates** — 4-retry exponential-backoff for network errors (per CLAUDE.md git/network rules: 2s, 4s, 8s, 16s). After 4 retries → abort.
6. **Observations not assumed success** — shell command exit codes checked at every step.
7. **Errors as structured observations** — surfaced inline; no silent skips.

### 2.3 Budgets — quality-first framing (per M4 §2.3)

`/update` has **zero Class-A hard kill caps**.

| Layer | Lever | Why |
|---|---|---|
| **Class-B escalation gates** | 4-retry exponential-backoff on network errors (CLAUDE.md-aligned) | Plugin marketplace failures are usually transient; 4 retries cover most cases without hanging forever |
| | Hash-check output truncation at ~2000 chars | Long hash diffs aren't useful; first 10 mismatched files is enough |
| | MIGRATION.md walked step-by-step (one AUQ per step) — no batch | Each breaking change deserves explicit user attention |
| **Architecture constraints** | Stateless | Update is a one-shot maintenance operation; no resume value |
| | No subagents | Operations are atomic shell calls; no decomposition need |
| **NOT capped** | MIGRATION.md walk step count, hash-check file count, total update duration | Quality-first |

### 2.4 ACI surface per phase

| Phase | Allowed tools | Forbidden tools |
|---|---|---|
| `pre-check` | `Read`, `Bash` (`cat plugin.json`, `grep`, `python3 -c "json.load"`), `Glob`, `AskUserQuestion` | `Write`, `Edit`, `Bash` (mutating), `Agent`, `mcp__*` |
| `update` | `Bash` (`claude plugin marketplace update`, `claude plugin update`, `python3 -c "json.load"` to parse registry) | `Read`, `Write`, `Edit` on project files (no project edits during update); `Agent`; `mcp__github__*` |
| `post-check` | `Read`, `Bash` (`sha256sum`, `stat`, `cp` to refresh statusline), `Glob` | `Edit` on project files outside `$CLAUDE_USER_DIR/hooks/`; `mcp__*` |
| `migration` | `Read`, `AskUserQuestion`, `Bash` (`grep -r` for stale references), `Glob` | `Write`, `Edit` (migration suggestions are surfaced as `/geniro:instructions edit` recommendations, NEVER auto-applied); `Agent`; `mcp__*` |
| `DONE` | (terminal report) | (none) |

External sends: not in `/update` ACI ever.

---

## 3. Scope deltas vs. pre-M10 `/geniro:update`

### 3.1 Removed

Nothing removed from current 92-LOC SKILL.md — it was a thin wrapper and most of it is preserved.

### 3.2 Kept (with adaptation)

| Kept item | Adaptation |
|---|---|
| Version check via `cat plugin.json | grep version` | Moved to Phase Pre-check §6.1 |
| `claude plugin marketplace update` + `claude plugin update` shell calls | Moved to Phase Update §7.1; retry-with-exponential-backoff added per CLAUDE.md network rules |
| Plugin path discovery via `installed_plugins.json` registry | Moved to Phase Update §7.2; preserved verbatim |
| Update cache refresh (`GENIRO_UPDATE_BG=1 node hooks/geniro-check-update.js`) | Moved to Phase Post-check §8.3 |
| Statusline stable-copy refresh (conditional on file existence) | Moved to Phase Post-check §8.4 |
| Restart-session warning at end | Moved to Phase Done §10.1 — emitted always (vs M10a §10.3 conditional logic, since `/update` IS a version transition by definition) |

### 3.3 Added (new in M10d)

| Added item | Source |
|---|---|
| **Pre-update version-confirm AUQ** | Q6 + invariant #3 (permission before side-effect) — user gets one chance to abort before shell call |
| **Pre-update user-content snapshot** | Q6 integrity — capture mtime / sha256 of `.geniro/instructions/*.md` and `.geniro/actions/*.md` before update |
| **Post-update hash check on plugin files** | Q6 integrity — verify all plugin-installed files match the manifest (if marketplace publishes one) OR sanity-check that key files (`agents/*.md`, `skills/_shared/*.md`, `hooks/*.js`) exist |
| **Post-update user-content survival verification** | Q6 integrity — diff snapshot from Pre-check; surface tampering if any |
| **MIGRATION.md reader** | Q6 migration; new contract specced in §5 |
| **Walk-user-through-MIGRATION.md flow** | Q6 migration; AUQ-per-step for each breaking change |
| Cross-version diff of plugin's own CLAUDE.md split state | OQ-M10a-2 partial — if new plugin spun out `.geniro/docs/*.md` differently, surface to user |

---

## 4. Decisions recorded so far

| ID | Question | Decision |
|---|---|---|
| **Q1** | Bundle vs split | Split — part d of 4 |
| **Q2** | Phase model | Skill-natural — 5 phases (pre-check → update → post-check → migration → done) |
| **Q3** | CLAUDE.md split | N/A — `/update` doesn't write CLAUDE.md (delegate to `/setup re-run` if user-project CLAUDE.md needs refresh) |
| **Q5** | State file | None — stateless one-shot |
| **Q6** | `/update` scope | **Wrapper + integrity + MIGRATION.md reader** — most ambitious option |

Sub-decisions:

| Sub-decision | Resolution |
|---|---|
| Should `/update` auto-trigger `/setup re-run` if plugin's own CLAUDE.md changed? | **No** — auto-mutate of user's CLAUDE.md is anti-pattern. Surface a recommendation: "Plugin's CLAUDE.md template changed in this version. Consider running `/geniro:setup` to refresh your project's CLAUDE.md." |
| Should hash-check fail abort, or warn-and-continue? | **Abort on failure**, but with an AUQ giving user `[Abort | Continue anyway (NOT recommended)]`. Recommended option = Abort. Same Cancel-default pattern as M10c risk_class:high actions |
| What if MIGRATION.md is missing in new plugin version? | Skip Phase Migration entirely; print one-line info "no migration notes for v<old> → v<new>" |
| Should `/update` refuse to run if there are uncommitted changes in `.geniro/`? | **No** — `/update` doesn't touch `.geniro/` user content (only checks integrity). Uncommitted changes are user's prerogative |
| Should `/update` support a `--dry-run` mode? | Yes — defer to implementation. `--dry-run` prints what would happen but does not invoke `claude plugin update`. Useful for ops teams |
| Should `/update` support pinning to a specific version (`--to v1.5.0`)? | Out of scope MVP — Claude Code's marketplace doesn't expose pin-to-version cleanly. If a user wants downgrade, they edit `installed_plugins.json` manually (out of `/update`'s scope) |

---

## 5. MIGRATION.md contract (NEW — specced here)

`/update` consumes a file at `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md` after the plugin update. The file documents breaking changes between versions.

**Plugin maintainer's obligation:** populate `MIGRATION.md` whenever a release introduces a user-visible breaking change.

### 5.1 File schema

```markdown
# Migration Notes

## v1.5.0 (released 2026-05-19)

### Breaking change — phase enum renamed

`/implement` Phase 4 was renamed `IMPLEMENT_STEP_1` → `IMPLEMENT`.

**Action required:** Edit `.geniro/instructions/implement.md` (if present); rename any
subsection `### After IMPLEMENT_STEP_1` → `### After IMPLEMENT`.

**Auto-detect:** `grep -r "After IMPLEMENT_STEP_1" .geniro/instructions/`

**Severity:** MEDIUM — old name still works for v1.5; will be removed in v2.0.

---

### New feature — risk_class field in actions

Actions now require `risk_class: low | medium | high` in frontmatter.

**Action required:** Run `/geniro:actions validate` to find actions missing the field;
edit each with `/geniro:actions edit <slug>` and add risk_class.

**Auto-detect:** `grep -L "risk_class:" .geniro/actions/*.md`

**Severity:** HIGH — actions without risk_class will fail validation in v1.5.

---

## v1.4.0 (released 2026-04-01)

### ... (older entries)

```

**Required structure:**

- One `## v<X.Y.Z>` heading per release.
- Within each, `### <change-name>` headings.
- Each change documents: (a) what changed, (b) "Action required:" — one-line user instruction, (c) "Auto-detect:" — one-line shell command for `/update` to run, (d) "Severity:" — `LOW | MEDIUM | HIGH | CRITICAL`.

### 5.2 How `/update` consumes it

Phase Migration (§9):

1. Read `MIGRATION.md`.
2. Find entries between `v<old>` (exclusive) and `v<new>` (inclusive).
3. For each entry:
   - Run the `Auto-detect:` command to determine if THIS user is affected.
   - If affected:
     - AUQ: "Breaking change in v<X.Y.Z>: <change-name>. <Action required>. Auto-detect found N matches. Apply now (opens `/geniro:instructions edit <scope>`) | Skip for now | Cancel update walk"
     - On `Apply now`: print the suggestion + path; `/update` exits this step (user re-invokes /update or /instructions later to actually apply). **`/update` does NOT auto-edit user content.**
     - On `Skip for now`: log the skipped change in DONE final report.
     - On `Cancel update walk`: transition to DONE with remaining migration entries logged as "deferred — review MIGRATION.md when ready."
   - If not affected: skip silently.
4. After last entry: transition to DONE.

If MIGRATION.md is absent (plugin maintainer didn't write one for this release), skip Phase Migration with one info line.

### 5.3 Plugin maintainer guidance (out-of-scope of M10d but documented)

This is what plugin authors writing `MIGRATION.md` should know:

- Keep entries terse — 4-6 lines per change. Long prose belongs in CHANGELOG.md.
- The `Auto-detect:` shell command MUST run safely on any project; use `grep`, `find`, `ls` — no `rm`, no `sed -i`, no `git` commands.
- Severity HIGH or CRITICAL means: action MUST be taken before next pipeline run, or skills will misbehave.
- Severity MEDIUM means: action SHOULD be taken; old behavior still works but deprecated.
- Severity LOW means: informational; no user action needed but good to know.

---

## 6. Defect inventory (audit 2026-05-19 — before/after)

8 defects identified in current `/update` SKILL.md (92 LOC). All closed in this redesign.

| # | Defect | Fix |
|---|---|---|
| **D1** | No pre-update AUQ confirmation — running `/update` invokes shell update immediately | §6.2 Pre-check Step 3 adds version-confirm AUQ |
| **D2** | No integrity check — silently corrupted plugin install (e.g., partial download) goes undetected | §8.1 hash-check; §8.2 user-content survival check |
| **D3** | No MIGRATION.md reader — breaking changes between versions are user's responsibility to read CHANGELOG | §5 + §9 specs the contract and the walk |
| **D4** | No exponential-backoff on network errors (CLAUDE.md rule) | §7.1 retry-up-to-4-times with 2s, 4s, 8s, 16s |
| **D5** | No anti-pattern check | §11 added |
| **D6** | No master plan reconciliation | §10 added |
| **D7** | No structural error handling (e.g., what if `installed_plugins.json` has malformed JSON?) | §7.2 error handling — surface JSON parse failure with file path; abort to FAILED |
| **D8** | Restart-session warning is wall-of-text formatted inline; user may miss the key sentence | §10.1 message formatted with one key sentence first, details after |

---

## 7. Phase Pre-check — **DECIDED**

### 7.1 Step 1 — Read current version

```bash
CURRENT_VERSION=$(cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")
if [ "$CURRENT_VERSION" = "unknown" ]; then
  echo "ERROR: cannot read current plugin version from plugin.json — abort." >&2
  exit 1
fi
```

### 7.2 Step 2 — Resolve `$CLAUDE_USER_DIR` and snapshot user content

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"

# Snapshot user-content sha256 + mtime for survival verification
USER_SNAPSHOT=$(find .geniro/instructions .geniro/actions -type f -name "*.md" 2>/dev/null \
  | sort \
  | xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}") {}"')
# Store in env var for §Post-check §8.2 reuse
```

### 7.3 Step 3 — Version-confirm AUQ

Spawn `AskUserQuestion`:

```
Question: "Update geniro-claude-plugin?

Current version: v<CURRENT_VERSION>
This will:
  • Run `claude plugin marketplace update`
  • Run `claude plugin update geniro-claude-plugin@geniro-claude-harness`
  • Verify integrity of installed files
  • Verify user-authored .geniro/instructions/ and .geniro/actions/ untouched
  • Walk any breaking changes in MIGRATION.md
"
Options:
  - "Confirm update" — Run the update flow above (Recommended)
  - "Cancel" — Exit without updating
```

On `Cancel` → `done` with one-line message "Update cancelled by user."

Transition to Phase Update on `Confirm update`.

---

## 8. Phase Update — **DECIDED**

### 8.1 Step 1 — Marketplace refresh + plugin update

Per CLAUDE.md network-retry rules (4 retries with exponential backoff 2s, 4s, 8s, 16s on network errors only):

```bash
attempt=1
while [ $attempt -le 4 ]; do
  if claude plugin marketplace update geniro-claude-harness 2>&1 | tee /tmp/geniro-update.log; then
    break
  fi
  echo "Attempt $attempt failed; retrying in $((2 ** attempt))s..." >&2
  sleep $((2 ** attempt))
  attempt=$((attempt + 1))
done
if [ $attempt -gt 4 ]; then
  echo "ERROR: marketplace update failed after 4 retries — abort." >&2
  exit 1  # → failed
fi

# Same retry pattern for plugin update
attempt=1
while [ $attempt -le 4 ]; do
  if claude plugin update geniro-claude-plugin@geniro-claude-harness 2>&1 | tee /tmp/geniro-plugin-update.log; then
    break
  fi
  sleep $((2 ** attempt))
  attempt=$((attempt + 1))
done
if [ $attempt -gt 4 ]; then
  exit 1  # → failed
fi
```

### 8.2 Step 2 — Discover new plugin path

```bash
if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: registry not found at $REGISTRY — abort." >&2
  exit 1  # → failed
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
  echo "ERROR: registry parsed but no entry for plugin — abort." >&2
  exit 1
fi

NEW_VERSION=$(cat "$PLUGIN_PATH/.claude-plugin/plugin.json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('version','unknown'))")
```

Transition to Phase Post-check.

---

## 9. Phase Post-check — **DECIDED**

### 9.1 Step 1 — Plugin file hash-check

Two modes depending on whether the plugin publishes a manifest:

**Mode A (manifest exists, future):**

```bash
# If $PLUGIN_PATH/.claude-plugin/manifest.sha256 exists, verify each file:
if [ -f "$PLUGIN_PATH/.claude-plugin/manifest.sha256" ]; then
  cd "$PLUGIN_PATH" && sha256sum -c .claude-plugin/manifest.sha256 || HASH_FAIL=1
fi
```

**Mode B (no manifest, current — sanity check only):**

Verify these key files exist:

- `$PLUGIN_PATH/skills/_shared/load-custom-instructions.md`
- `$PLUGIN_PATH/skills/_shared/spawn-agent.md`
- `$PLUGIN_PATH/skills/implement/SKILL.md`
- `$PLUGIN_PATH/skills/setup/SKILL.md`
- `$PLUGIN_PATH/hooks/geniro-check-update.js`
- `$PLUGIN_PATH/agents/` (directory has ≥1 file)

If any missing → AUQ:

```
WARNING: hash-check failed — <list of missing files>.
Options:
  - "Abort" (Recommended) — exit without continuing; investigate
  - "Continue anyway (NOT recommended)" — proceed with possibly broken install
```

Recommended option = Abort. Per Cancel-default pattern from M10c risk_class:high.

### 9.2 Step 2 — User-content survival check

```bash
CURRENT_SNAPSHOT=$(find .geniro/instructions .geniro/actions -type f -name "*.md" 2>/dev/null \
  | sort \
  | xargs -I{} sh -c 'echo "$(sha256sum "{}" | cut -d" " -f1) $(stat -c%Y "{}") {}"')

if [ "$USER_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
  # diff is significant — surface
  diff <(echo "$USER_SNAPSHOT") <(echo "$CURRENT_SNAPSHOT") > /tmp/geniro-content-diff.log
  # AUQ
fi
```

If diff non-empty → AUQ:

```
WARNING: user content under .geniro/instructions/ or .geniro/actions/ changed during update.

Files affected: <list>

This is unexpected — the plugin update should NOT touch user-authored content.
Options:
  - "Show diff and continue (review later)" — Print diff, proceed to DONE
  - "Abort — preserve current state" (Recommended) — Exit; investigate manually
```

### 9.3 Step 3 — Refresh update cache

(Preserved from current §4):

```bash
GENIRO_UPDATE_BG=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_PATH" node "$PLUGIN_PATH/hooks/geniro-check-update.js"
```

### 9.4 Step 4 — Refresh statusline stable copy (conditional)

(Preserved from current §4.1):

```bash
if [ -f "$CLAUDE_USER_DIR/hooks/geniro-statusline.js" ]; then
  mkdir -p "$CLAUDE_USER_DIR/hooks"
  cp "$PLUGIN_PATH/hooks/geniro-statusline.js" "$CLAUDE_USER_DIR/hooks/geniro-statusline.js"
fi
```

Skip if file doesn't exist (user didn't run `/setup` or doesn't have a `statusLine` settings entry).

Transition to Phase Migration.

---

## 10. Phase Migration — **DECIDED**

Implements §5.2 reader logic.

```bash
MIGRATION_FILE="$PLUGIN_PATH/MIGRATION.md"
if [ ! -f "$MIGRATION_FILE" ]; then
  echo "[info] No MIGRATION.md in v$NEW_VERSION — skipping migration walk."
  # Transition to DONE
fi

# Parse MIGRATION.md, find entries between $CURRENT_VERSION (exclusive) and $NEW_VERSION (inclusive)
# (parser implementation: Python script reading markdown headings; deferred to implementation)
```

For each entry between `v<CURRENT_VERSION>` and `v<NEW_VERSION>`:

1. Run the `Auto-detect:` shell command. Capture output.
2. If detect output is empty → user not affected; log "skipped (not affected): <change-name>"; continue.
3. If detect output non-empty → user affected; AUQ:

```
Question:
  "Breaking change in v<X.Y.Z>: <change-name>

   <Action required text from MIGRATION.md>

   Auto-detected N affected files:
   <first 10 lines of detect output, truncated>"

Options:
  - "Show me how to fix this" — Print exact command, exit migration walk
  - "Skip for now" — Continue to next change
  - "Cancel migration walk" — Stop here; remaining changes logged
```

On `Show me how to fix this`: print exact `/geniro:instructions edit <scope>` or `/geniro:actions edit <slug>` command + the manual fix instruction. Transition to DONE.

On `Skip for now`: log skipped; continue to next entry.

On `Cancel migration walk`: log remaining unprocessed; transition to DONE.

After last entry: transition to DONE.

---

## 11. Phase Done — **DECIDED**

### 11.1 Final report + restart warning

```
✓ /geniro:update complete.

Updated: v<CURRENT_VERSION> → v<NEW_VERSION>
Plugin path: <PLUGIN_PATH>
Integrity check: <PASS | WARN>
User content: <UNCHANGED | CHANGED — see /tmp/geniro-content-diff.log>
Migration walked: <N changes — M applied, K skipped, L deferred>

⚠ RESTART your Claude Code session before using any Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start.
In-memory skill bodies still point at v<CURRENT_VERSION>. Restart and you're done.
```

Restart warning is **always emitted** by `/update` (unlike `/setup` which conditional on plugin-version delta, since `/update` IS a version transition by definition).

---

## 12. Memory I/O (M2 §13 obligation)

`/update` does NOT participate in any M2 memory layer:

| Layer | Read at | Write at | Notes |
|---|---|---|---|
| **L1 (CLAUDE.md)** | not read | not written | `/setup re-run` handles CLAUDE.md refresh; `/update` only emits a recommendation if user-project CLAUDE.md may be stale |
| **L2 (`learnings.jsonl`)** | not read | not written | `/update` is operational, not knowledge-producing |
| **L3 (semantic project files)** | not read | not written | N/A |
| **L4 (`.geniro/instructions/*.md`)** | read only for snapshot+integrity check (Phase Pre-check §7.2, Phase Post-check §9.2) | not written | The migration walk emits suggestions, never auto-edits |
| **Actions (`.geniro/actions/*.md`)** | same — snapshot only | not written | Same |

**M3 compaction-survival route:** `/update` is single-pass and brief; compaction during the skill itself is unlikely. The output (new plugin install) survives compaction trivially (file-on-disk).

---

## 13. Master plan reconciliation

| Master plan ref | Closure |
|---|---|
| §107 row M10 (operational skills) | M10d covers `/update` |
| §122 row M10 ("lowest priority") | Respected — minimal phase count (5), no state machine, no subagents, narrow ACI |
| **Q6 decision (this milestone)** | Closed — wrapper + integrity + MIGRATION.md reader specced in §5-§10 |
| **OQ-M10a-2 partial** | Closed partial — plugin-side breaking changes surfaced via MIGRATION.md walk; the spun-out `.geniro/docs/<topic>.md` template diff specifically is a forward-reference (no v1.5 template change to walk yet; future plugin releases will populate MIGRATION.md for this) |
| **P-MP-1** | §14 below |
| Restart-session warning rationale (`${CLAUDE_PLUGIN_ROOT}` resolves once per session) | §11.1 preserved from current `/update` skill |

---

## 14. Anti-pattern check (P-MP-1 obligation)

| # | Anti-pattern | M10d status |
|---|---|---|
| 1 | One giant prompt | ✅ SKILL.md will be ~150 LOC after redesign; no helper sprawl needed |
| 2 | One giant tool | ✅ N/A — shell + python3 + native tools |
| 3 | Unbounded autonomous loop | ✅ 4-retry exponential backoff on network errors; 4 → abort. Migration walk has explicit "Cancel" path at every step |
| 4 | Autonomous external sends in first release | ✅ N/A — `/update` doesn't send externally (marketplace fetches are inbound) |
| 5 | No approval state | ✅ Pre-update AUQ confirm (§7.3); hash-fail AUQ; content-tamper AUQ; per-migration-step AUQ. Approvals[] persistence is N/A (stateless, context-dependent decisions intentionally re-asked) |
| 6 | No durable plans or goals | ✅ N/A — operational maintenance |
| 7 | No compaction strategy | ✅ N/A — `/update` is single-pass; compaction during the run unlikely; survives natively via file-on-disk |
| 8 | All connectors loaded up front | ✅ N/A |
| 9 | High-risk tools without policy | ✅ §2.4 per-phase ACI; shell calls bounded by ACI; no mutation of user content |
| 10 | Subagents before single-agent MVP measured | ✅ Zero subagents |
| 11 | Dynamic timestamps in plugin-distributed Markdown | ⚠ Implementation note — SKILL.md must NOT embed runtime timestamps. Hash check fingerprints are computed at runtime, never persisted to plugin-distributed files |
| 12 | Non-deterministic agent registration order | ✅ N/A |

---

## 15. Open questions

| # | OQ | Resolution path |
|---|---|---|
| **OQ-M10d-1** | Should MIGRATION.md support a `Auto-apply:` field (alongside `Auto-detect:`) that `/update` can run with user confirmation? | Deferred — anti-pattern (autonomous mutation of user content); current design's "Show me how to fix" pattern is safer |
| **OQ-M10d-2** | Should `/update --check` mode preview the new version + MIGRATION entries without actually updating? | Yes-in-principle — defer to implementation. Read MIGRATION.md from a temp marketplace fetch without invoking `claude plugin update` |
| **OQ-M10d-3** | If the user has multiple `.geniro/` directories across worktrees, does `/update` snapshot all of them or just cwd's? | cwd only — `/update` is cwd-bound. Other worktrees get their own `/update` runs |
| **OQ-M10d-4** | Should `/update` validate that the new plugin's MIGRATION.md is well-formed before walking it? | Yes — parser should fail-soft: if MIGRATION.md is malformed, skip Phase Migration with a warning ("MIGRATION.md present but malformed; proceeding") |

---

## 16. Cleanup checklist

`/update` is stateless and writes to:

| Path | Cleanup |
|---|---|
| `$CLAUDE_USER_DIR/plugins/installed_plugins.json` | Owned by Claude Code; `/update` modifies via shell only |
| `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` | Owned by `/setup`; `/update` only refreshes content (conditional on existence) |
| Plugin install path (`$PLUGIN_PATH`) | Owned by Claude Code marketplace; `/update` doesn't manage cleanup of old versions |
| `/tmp/geniro-update.log`, `/tmp/geniro-plugin-update.log`, `/tmp/geniro-content-diff.log` | Transient — `/tmp` is OS-managed; no plugin-side cleanup |
| User content (`.geniro/instructions/*`, `.geniro/actions/*`) | NEVER touched by `/update` |

---

## 17. Cross-references

- **M1** — N/A (`/update` is stateless; no T1/T2/T3 state file)
- **M2 §5.4 L4** — `.geniro/instructions/*` is L4; `/update` reads for integrity only
- **M3 §6** — N/A (no compaction-survival concern for `/update`)
- **M4 §2.2** — 7 loop invariants; §2.2 cites
- **M4 §2.3** — quality-first budgets; §2.3 mirrors
- **M4 §13.5** — per-phase ACI; §2.4 mirrors
- **M10a §10.3** — restart-session warning conditional logic for `/setup` (M10a is conditional; M10d is unconditional — `/update` IS a version transition)
- **M10b §10** — validate rule set (shared with `/actions validate`; not directly invoked by `/update`)
- **M10c §6.3** — Cancel-as-recommended AUQ pattern; M10d hash-fail and content-tamper AUQs use the same pattern
- **CLAUDE.md "For git fetch/pull"** — 4-retry exponential-backoff network rule; §8.1 follows it
- **P-X6** (deferred candidate) — observability would enable `/update` to log version transitions to L2; out of M10d scope
- **OQ-M10a-2** — partial closure for plugin-side breaking changes via MIGRATION.md walk
