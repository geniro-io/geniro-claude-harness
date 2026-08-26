---
name: geniro-update
description: "Use when the status line shows a plugin update is available, or to manually pull the latest Geniro plugin version. Verifies plugin integrity, ensures user-authored .geniro/instructions/ and .geniro/actions/ survived intact, and walks any breaking changes in MIGRATION.md."
context: main
---
<!-- Generated from skills/update/SKILL.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->


# /geniro:update — update plugin

## Contents

- Path constraints
- Loop invariants
- Anti-rationalization
- Definition of done
- Budgets — quality-first
- ACI per-phase tool surface
- Termination case → message
- Memory I/O
- User-content snapshot
- Phase 1 — pre-check · Phase 2 — update · Phase 3 — post-check · Phase 4 — migration
- Done — final report
- REFERENCE

---

4-phase loop: **Pre-check → Update → Post-check → Migration**. Stateless.

**Runtime requirement.** This skill drives the `claude plugin` CLI and the Claude Code install registry, and functions only under Claude Code. When invoked from another runtime (e.g. Cursor), state that updates are managed by that runtime's own plugin mechanism and exit without side effects.

**Read the phase's Steps on entry to that phase**, from `${CLAUDE_PLUGIN_ROOT}/skills/update/`: `phase-1-precheck.md` · `phase-2-update.md` · `phase-3-postcheck.md` · `phase-4-migration.md` · `done-final-report.md`. That Read is the phase's physically-first action and carries a one-line echo, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates (the update-confirmation AUQ, the hash-check and tamper-diff AUQs, the per-entry migration AUQ) and their helper call sites, so work started before the Read runs outside them. `/geniro:update` keeps no state file, so a compaction mid-run is recovered by re-Reading the phase you were in, named from this spine's phase headings, rather than by re-invoking the whole skill.

## Path constraints

Pass `${CLAUDE_PLUGIN_ROOT}` (for plugin files) or a fully resolved absolute path (for project files) to Read, Write, Edit, Glob, and Grep — these tools do not expand `~`, so a literal `~` directory gets created. Honor `CLAUDE_CONFIG_DIR` and fall back to `$HOME/.claude` only inside Bash blocks where `$HOME` expands correctly.

## Loop invariants

The canonical loop invariants (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`) apply, with five update-specific bindings:

- **Invariant #2 (args validated before execution)** — every shell call has its prereq checked (registry exists, plugin.json parseable, network reachable).
- **Invariant #3 (permission before side-effect)** — the pre-update AUQ (`phase-1-precheck.md` §Confirm the update with the user) is one example among this skill's several (the hash-check and tamper-diff AUQs in `phase-3-postcheck.md`, the per-entry migration AUQ in `phase-4-migration.md`) — any further pause this skill reaches is still routed through `AskQuestion`, never a plain-text y/n, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Lean-question conventions.
- **Invariant #4 (bounded structured tool results)** — the migration-step AUQ truncates auto-detect output to its first ~10 lines; the full content diff is written to a log file rather than inlined.
- **Invariant #5 (escalation gates, not silent abort)** — 4-retry exponential-backoff on network errors; abort after the 4th retry. (`phase-2-update.md` §Marketplace refresh + plugin update owns the exact delays.)
- **Invariant #7 (errors → structured observations)** — this skill is stateless, so errors surface inline in the run's output rather than in a state-file `## Errors` section; no silent skips.

This skill adds one invariant:

S1. **No subagent spawns.** `/geniro:update` does not spawn subagents — every phase runs inline in the orchestrator.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "My recalled experience says the MIGRATION.md version headings don't match the package version, so I'll range-filter or read only the newest block." | A recalled learning does not override the walk-all consumption contract. The version heading is not a selection gate — walk EVERY entry across ALL sections (Phase 4) and let each read-only auto-detect decide relevance. The current skill body and the MIGRATION.md preamble are authoritative over any prior-session recollection. |
| "The version-confirm AUQ is a formality — I'll just run the update." | That AUQ is the one explicit permission gate before a mutating marketplace + plugin update touches the install. Skipping it removes the user's only chance to cancel before the network fetch and registry write. Fire it unless `--dry-run`. |
| "I ran the Auto-fix command, so the migration entry is resolved." | Auto-fix can apply partially. Re-run the entry's `Auto-detect:` after fixing; only an empty result confirms resolution. Reporting "fixed" without the re-detect can leave the user on a half-migrated install. |
| "A file is missing from the hash-check but the update likely worked — continue." | A missing key file means a broken install, not a benign blip. Fire the Cancel-as-recommended AUQ and let the user decide; auto-continuing ships a plugin that may fail mid-skill later. |
| "The user-content survival diff shows changes, but they're probably benign." | The update must never touch `.geniro/instructions/` or `.geniro/actions/`. Any diff is either a plugin bug or tampering — surface it via the AUQ; never auto-dismiss content the user authored. |

## Definition of done

- [ ] `phase-3-postcheck.md` §Plugin file hash-check (sanity mode) ran; `HASH_FAIL` resolved (PASS, or the user picked Continue anyway at the AUQ)
- [ ] `phase-3-postcheck.md` §User-content survival check ran; any non-empty diff was surfaced via AUQ and resolved
- [ ] `phase-3-postcheck.md` §Refresh update cache ran (`geniro-check-update.js` invoked against the new `PLUGIN_PATH`) — skipping it leaves the "update available" indicator lit for the rest of the session, in the run meant to clear it
- [ ] `phase-3-postcheck.md` §Refresh statusline stable copy (conditional) ran when `$CLAUDE_USER_DIR/hooks/geniro-statusline.js` already existed
- [ ] `phase-3-postcheck.md` §Re-point the Cursor CLI skill links (conditional) ran when `$HOME/.cursor/skills/` already held `geniro-*` links
- [ ] The final report's `Update cache`, `Statusline`, and `Cursor CLI skills` lines reflect the actual outcome of each refresh, not an assumed one

## Budgets — quality-first

`/geniro:update` has **zero hard kill caps**. Class-B gates: 4-retry network backoff, hash-diff truncation, per-migration-step truncation. Not capped: migration walk step count, hash-check file count, total update duration.

## ACI per-phase tool surface

| Phase | Allowed | Forbidden |
|---|---|---|
| `pre-check` | `Read`, `Bash` (`cat`, `grep`, `find`, `shasum`/`sha256sum`, `stat`, `python3 -c "json.load"`, plus the one sanctioned write: the `phase-1-precheck.md` §Resolve `$PRIMARY_ROOT` and snapshot user content baseline snapshot redirected into `/tmp`), `Glob`, `AskQuestion` | `Write`, `Edit`, any mutating `Bash` outside that snapshot write, `Agent`, all `mcp__*` |
| `update` | `Bash` (`claude plugin marketplace update`, `claude plugin update --scope user`, `claude plugin install --scope user` for the global-install repair, `python3 -c` to parse registry) | `Read`/`Write`/`Edit` on project files, `Agent`, `mcp__github__*` |
| `post-check` | `Read`, `Bash` (`sha256sum` or `shasum -a 256` on macOS, `stat`, `cp` for statusline refresh, the Cursor link script), `Glob`, `AskQuestion` | `Edit` on project files outside `$CLAUDE_USER_DIR/hooks/`, `mcp__*` |
| `migration` | `Read`, `AskQuestion`, `Bash` (detect commands from MIGRATION.md + auto-fix commands when user picks "Fix it for me"), `Glob`, `Write`, `Edit` (only when user picks "Fix it for me" per-entry) | `Agent`, `mcp__*` |
| `done` | (terminal report) | (none) |

External sends: not in `/geniro:update` ACI ever.

## Termination case → message

| Cause | Message |
|---|---|
| Network error after the retry cap (cap and backoff ladder set in `phase-2-update.md` §Step 1) | `aborted: network error during plugin marketplace update after <cap> retries` |
| Install recorded under the legacy plugin id | `aborted: plugin renamed — reinstall required` (`phase-1-precheck.md` §Legacy install-id check prints the reinstall commands) |
| Update succeeded but registry missing entry | `aborted: registry missing the geniro plugin entry — see ~/.claude/plugins/installed_plugins.json` |
| Hash-check failed | `aborted: plugin integrity check failed — missing file(s) or manifest hash mismatch on <file>` |
| User-content tampering detected | AUQ surfaces; user picks Continue or Abort |
| MIGRATION.md walked successfully | `done` |
| MIGRATION.md walked, user aborted mid-walk | `aborted: user aborted migration walk at step <N>` |
| Already on latest version | `info: already on latest version (<version>)` — done |
| Hooks/registry write blocked | `aborted: blocked by hook — see <hint>` |

## Memory I/O

| Layer | Read | Write | Notes |
|---|---|---|---|
| CLAUDE.md (project context) | not read | not written | `/geniro:setup re-run` handles CLAUDE.md refresh; `/geniro:update` only emits a recommendation if user-project CLAUDE.md may be stale |
| L2 learnings.jsonl | not read | not written | `/geniro:update` is operational, not knowledge-producing |
| L3 semantic files | not read | not written | N/A |
| L4 `.geniro/instructions/*.md` | snapshot+integrity check (`phase-1-precheck.md` §Resolve `$PRIMARY_ROOT` and snapshot user content; `phase-3-postcheck.md` §User-content survival check) | Written ONLY when user picks "Fix it for me" per-entry | Auto-fix runs MIGRATION.md commands; manual entries untouched |
| `.geniro/actions/*.md` (T3) | snapshot+integrity check | Written ONLY when user picks "Fix it for me" per-entry | Same |

## User-content snapshot

The one definition of the snapshot, used by `phase-1-precheck.md` §Resolve `$PRIMARY_ROOT` and snapshot user content (baseline) and `phase-3-postcheck.md` §User-content survival check (comparison). Both phases must run identical code: a second copy that drifted by one flag would make the survival diff raise a tamper alarm over content nothing touched. Shell state does not persist between Bash calls, so each phase pastes these definitions into its own call and passes the `PRIMARY_ROOT` it just re-resolved.

Read `${CLAUDE_PLUGIN_ROOT}/skills/update/user-content-snapshot.md` for the exact shell functions — the single copy both phases paste in.

## Phase 1 — pre-check

Steps: `phase-1-precheck.md`. Load custom instructions, read `CURRENT_VERSION`, check for a legacy install id, resolve `PRIMARY_ROOT` and take the baseline user-content snapshot (§User-content snapshot above), then confirm the update with the user (or take the `--dry-run` exit). Exit when the user picked `Confirm update` (or `--dry-run` printed its preview and exited).

## Phase 2 — update

Steps: `phase-2-update.md`. Run the marketplace + plugin update with exponential backoff, repair a dropped global-scope install, then discover and echo the new `PLUGIN_PATH` / `NEW_VERSION` (or exit early when already on latest). Exit when `PLUGIN_PATH` and `NEW_VERSION` are both echoed.

## Phase 3 — post-check

Steps: `phase-3-postcheck.md`. Hash-check the new install (AUQ on failure), re-take the user-content snapshot and diff it against the Phase 1 baseline (AUQ on any change), refresh the update cache, refresh the statusline copy when one already exists, and re-point the Cursor CLI skill links when those already exist. Exit when both AUQ-gated checks have resolved and the cache / statusline / Cursor-link outcomes are recorded for the final report.

## Phase 4 — migration

Steps: `phase-4-migration.md`. Skip entirely when the new install carries no `MIGRATION.md`. Otherwise walk it per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md`, applying the live-task guard before any delete-class auto-fix and firing the per-entry AUQ (`Fix it for me` / `Show me how to fix manually` / `Skip for now` / `Cancel migration walk`). Exit when every entry has been walked (or the user cancelled), and go to Done.

## Done — final report

Steps: `done-final-report.md`. Decide whether to append the `/geniro:setup` re-run recommendation (per its three trigger conditions), then print the final report and the mandatory restart warning. Exit when the report has been printed.

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` — the canonical loop invariants the §Loop invariants bindings extend.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — `phase-1-precheck.md` §Load custom instructions rules load.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` — Mode A resolver for `PRIMARY_ROOT` (`phase-1-precheck.md` §Resolve `$PRIMARY_ROOT` and snapshot user content; `phase-3-postcheck.md` §User-content survival check).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md` — Phase 4 parse / auto-detect / classify / re-verify procedure shared with the `/geniro:setup` re-run sweep.
- `${CLAUDE_PLUGIN_ROOT}/skills/update/user-content-snapshot.md` — the `_gu_snapshot` / `_gu_snapshot_file` shell functions §User-content snapshot pastes into Phase 1 and Phase 3.
