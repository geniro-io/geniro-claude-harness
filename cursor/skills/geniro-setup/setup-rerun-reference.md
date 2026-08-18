<!-- Generated from skills/setup/setup-rerun-reference.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Setup — re-run-only procedures

Everything `/geniro:setup` does ONLY when §1.1 resolved `mode == re-run`. An `init` run — the skill's leading use case — never reads this file: a fresh install has no prior `CLAUDE.md` to merge, no prior schema to migrate, and no prior plugin version to compare against.

## Contents

- 3.0 Migration sweep — walk MIGRATION.md and apply what this install is affected by
- 3.1 Pre-write existing-content audit — merge into the prior `CLAUDE.md` instead of overwriting it
- 3.4 Conflict-resolution merge rules
- 5.4 Restart-session warning on a plugin-version delta

---

## 3.0 Migration sweep

Run this before generating content, so the `.geniro/` directory structure is current before `CLAUDE.md` and the instruction files are regenerated.

Walk `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/migration-walk.md` — that helper parses the entries, runs each `Auto-detect:` behind its `N/A` guard, and classifies each entry as applicable or not. Its walk-every-entry rule is what makes the sweep complete: a user re-running `/geniro:setup` could be coming from any prior version.

Every outcome the helper reports lands in `## Phase log`, so a sweep that did nothing is distinguishable from a sweep that never ran: `[<ts>] migration sweep skipped: MIGRATION.md absent` / `... unparseable`, and `[<ts>] migration skipped (not affected): <change-name>` per entry the detect cleared.

**Apply policy.** For each applicable entry, branch on the `Auto-fix:` value in this order — test `manual-only` FIRST, because a `manual-only` value carries prose, not a runnable command, so it must not fall through to a branch that runs it via `bash -c`:

- If the `Auto-fix:` value begins with `manual-only` (matched case-insensitively, so `Manual-only` is caught too): log to `## Phase log`: `[<ts>] migration manual-only: <change-name> — will be addressed by Phase 3 regeneration or user action`.
- Else if the `Auto-fix:` command is destructive (contains `rm`, `-delete`, or `-exec rm`): do NOT apply it silently — a silent destructive sweep can delete working state the user would have chosen to keep. Log to `## Open Questions`: `[<ts>] migration destructive fix NOT auto-applied: <change-name> — run /geniro:update to apply it interactively per-entry`. When any detected path sits inside a task-dir (`.geniro/planning/<task-dir>/` or `.geniro/state/<skill>/<slug>/`) whose `state.md` shows a live task (present, with non-terminal `phase:`/`status:`), append `; <M> detected path(s) belong to a live task — /geniro:update's live-task guard excludes them from the fix`, so the deferred entry carries the liveness context into the walk.
- Else (non-destructive command): run it silently via `bash -c` — auto-fix commands are maintainer-written and tested (the same ones `/geniro:update` surfaces with "Fix it for me"), and a re-run is user-initiated, so a safe mechanical fix needs no question. Log to `## Phase log`: `[<ts>] migration fix applied: <change-name>`.

After the sweep, verify per the shared walk §6: re-run the `Auto-detect:` for every entry that was auto-applied above, and for those only — entries deferred to `## Open Questions` and entries logged `manual-only` are intentionally still affected, so re-flagging them would double-log. Any auto-applied entry that is still affected is logged to `## Open Questions`.

## 3.1 Pre-write existing-content audit

1. Read existing `CLAUDE.md`.
2. Identify project-specific sections (Tech Stack, Commands, Conventions, Domain Context).
3. For each: merge detected updates into existing content via orchestrator-inline merge (preserve user edits + update facts).
4. If existing CLAUDE.md carries anything on the exclusion list in `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content from a prior `/geniro:setup` version — **remove it silently**. It is plugin noise the plugin already loads on its own.
5. Display merged diff to user, then `AskQuestion` (header: "Merge diff") — options "Apply the merge" / "Show me the full diff" / "Keep my CLAUDE.md unchanged".

## 3.4 Conflict-resolution merge rules

Section merge runs **orchestrator-inline** — no subagent spawn. Rules:

1. Preserve all user customizations.
2. Apply factual updates from detection (e.g., new commands detected, stack changes).
3. If conflict (same statement contradicted), surface both versions via AUQ — let user pick.
4. Do not add geniro-specific content during merge — apply the exclusion list in `${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md` §Excluded content.

## 5.4 Restart-session warning

Emitted only when the current `.claude-plugin/plugin.json` version differs from the `plugin_version:` recorded in the prior state file. A prior state file that predates the field (no `plugin_version:`) yields no computable delta, so no warning fires.

```
⚠ Restart your Claude Code session before using any other Geniro skill.

Claude Code resolves ${CLAUDE_PLUGIN_ROOT} once at session start. The plugin
update brought a new install path, but in-memory skill bodies still reference
the old one. Restart and you're done.
```
