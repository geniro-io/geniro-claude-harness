# Within-skill state handoff (canonical, shared)

**Status:** Authoritative for these session-bound state files, each under `<skill>`'s state dir (`_geniro_state_dir <skill>`): `refactor`, `debug`, `onboard`, `investigate`, `audit-instructions`, `resolve` — `state.md` inside the dir.

Within-skill state files are main-rooted and branch-slugged: two sessions on different branches never share a path. Two worktrees can still share a slug (detached worktrees at one commit, a bare hub's root and its `main` worktree), which Case B handles. This file codifies the slug-scoped path contract, the frontmatter fields every producer writes, and the mismatch UX every consumer surfaces on resume.

## Contents

- §Why this exists — the shared-state-dir collision
- §Slug rules — how the task slug is derived
- §Producer contract — frontmatter fields every writer writes
- §Consumer contract — how a resume reads the state file
- §Mismatch handling — Case A/B/C/D resume UX
- §Cleanup contract — when the state file is removed
- §Anti-rationalization
- §Definition of Done

## Why this exists

Every state dir sits in the main checkout (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`), so all sessions share one `.geniro/state/<skill>/`. An unscoped `state.md` there would be overwritten by whichever session wrote last, and a later session on another branch would inherit it on resume after compaction, applying old plans to new code. The branch slug keeps each session's state apart.

## Slug rules

The branch slug is the suffix on every within-skill state file path. Compute it once at producer-write time and again at consumer-read time; both sites must produce the same string, or the producer writes under one slug while the consumer reads from another and silently misses the state file.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/branch-slug.sh"
slug="$(_geniro_branch_slug)"    # the current branch; pass a branch name to derive from that one instead
```

`${CLAUDE_PLUGIN_ROOT}/lib/branch-slug.sh` is the only home of the derivation (lowercase, non-alphanumeric runs to one dash, trimmed dashes, 60-character cap; a detached HEAD slugs as `detached-<short-sha>`), so a producer and the session-start-restore hook (which sources it, with an inline fallback for vendored installs) cannot disagree.

When `git` is unavailable or the project isn't a git repo, the fallback chain produces slug `detached-unknown` — the file still works for single-session use; collision is impossible without branches.

## Producer contract

Every producer of a within-skill state file must:

1. Compute the slug per `## Slug rules`.
2. Name the dir with `STATE_DIR="$(source "${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh" && _geniro_state_dir <skill>)"` — the absolute, main-rooted `<main>/.geniro/state/<skill>/<slug>` (re-run it in each Bash call that needs it) — and write `$STATE_DIR/state.md`. Never write to a non-scoped path. The `.geniro/state/` prefix is mandatory — root-level state files are blocked by convention so only user-content (instructions/, actions/, workflow/, planning/, knowledge/) lives at the root.
3. Write the full T1.5 frontmatter field set per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` (common-base `producer` / `schema-version` / `branch` / `timestamp` + tier-specific `phase` / `status` / `non-resumable-actions`), plus the `worktree:` field this helper adds for pwd-change detection. `branch:` / `worktree:` / `timestamp:` are the slug-collision-relevant subset this helper governs; the rest satisfy `validate_state_file` (which returns exit 4 on a missing `producer` / `schema-version` and exit 5 on a missing `phase` / `status` / `non-resumable-actions`). The frontmatter starts on line 1 with `---`:

```yaml
---
tier: T1.5
producer: <skill>            # debug | refactor | onboard | investigate | audit-instructions | resolve
schema-version: 1
branch: <git branch --show-current OR detached-<short-sha>>
worktree: <git rev-parse --show-toplevel>
timestamp: <ISO-8601 UTC, e.g., 2026-05-07T14:32:00Z>
phase: <skill phase enum>
status: <in-progress | done | failed>
non-resumable-actions: []
---
```

The frontmatter `branch:` field is the source of truth on resume — even if two branch names slugify identically after truncation (rare but possible at >60 chars), the field is unambiguous. The `worktree:` field detects the rare case where `pwd` changed without a branch change. The `timestamp:` aids stale-state diagnosis. Plain-text `Branch:`/`Worktree:`/`Timestamp:` headers before the fence would push the `---` off line 1 and fail `validate_state_file` (exit 2 when line 1 is not `---`) and the SessionStart restore-hook frontmatter parser.

## Consumer contract

On skill start (or resume after compaction), every consumer must:

1. Compute current branch + slug per `## Slug rules`.
2. Try to read `$STATE_DIR/state.md` (primary path, `STATE_DIR` from `_geniro_state_dir <skill>` as in §Producer contract).
3. If the primary path exists, read the frontmatter `branch:` and `worktree:` fields and run `## Mismatch handling` Case A/B/C.
4. If the primary path does NOT exist BUT an older path exists at any of these locations, enter Case D (migration). Try in this order:
 - `./.geniro/state/<skill>/<slug>/state.md` in the current worktree (written before state was main-rooted): move the whole legacy dir with `[ -n "$STATE_DIR" ] && [ ! -e "$STATE_DIR" ] && mkdir -p "$(dirname "$STATE_DIR")" && mv "<legacy dir>" "$STATE_DIR"` (the skill's other files in it, such as findings, drafts and scratch, travel with `state.md`), then continue with Case A/B/C
 - `.geniro/<skill>/state-<slug>.md` (slug-scoped, older directory layout)
 - `.geniro/<skill>-state.md` or `.geniro/<skill>/state.md` (non-scoped)
 - For debug: `.geniro/state/debug/HYPOTHESES-<slug>.md`; then `.geniro/state/debug/findings-state.md`; then `.geniro/state/debug/adversarial-tests.md`; then `.geniro/debug/HYPOTHESES-<slug>.md`; then `.geniro/debug/HYPOTHESES.md`
 - For refactor: `.geniro/state/refactor/state-<slug>.md`; then `.geniro/refactor/state-<slug>.md`; then `.geniro/refactor/state.md`
 - For onboard / investigate: no older paths to check.

This is the single list of legacy paths a resume checks; §Cleanup contract below cites it rather than repeating it.
5. If neither exists, no state to resume — proceed fresh.

## Mismatch handling

Four cases — consumers must handle all four:

**Case A — Headers match current branch + worktree.** Proceed silently with the resume. No user-visible message needed.

**Case B — Branch matches, Worktree differs.** When the recorded `worktree:` is still listed by `git worktree list`, another live session may own this state: treat it as Case C. Otherwise (the recorded worktree no longer exists, typically because the repo moved) surface a one-line note: `State found for branch '<branch>' but written from worktree '<state-worktree>'; current worktree is '<current-worktree>'. Proceeding.` No AUQ.

**Case C — Branch differs (collision detected).** Render the clash, then fire `AskUserQuestion` (the canonical user-facing recovery — NOT improvised at runtime). The render is a chat message in the two layers of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers, because four branch and directory names packed into a question is exactly the shape a user skips:

```
### ⚠️ Unfinished work from a different branch

**In one sentence:** there's saved progress from an earlier run that was working
on a different branch than the one you're on now, so continuing it here would
put those changes somewhere they weren't meant to go.

**Technical detail:** saved state at <path> targets branch '<state-branch>'
(worktree '<state-worktree>'); you are on '<current-branch>' (worktree
'<current-worktree>').
```

- Header: "State clash"
- Question: "Saved progress from another branch — explained above. How should I proceed?"
- Options (in this order — first is Recommended):
 1. **"Stop — I'll switch to <state-branch>"** (Recommended) — abort the skill; user runs `git checkout <state-branch>` (or `cd <state-worktree>` if a sibling worktree) and re-invokes.
 2. **"Discard and start fresh on <current-branch>"** — delete the conflicting state file; begin a new pipeline scoped to current branch.
 3. **"Continue anyway"** — proceed; changes will land on `<current-branch>` regardless of what the state file claims. WARN that downstream cross-references in the state file (e.g., `changed-files:`) may be wrong.

**Case D — Non-scoped state file at an older path.** Surface a one-line migration note: `Old state file at <path>; scoping to current branch slug.` Then either (a) read it as if Case A/B/C using its frontmatter `branch:` field if present, or (b) treat as Case C if the file lacks a `branch:` field. After successful resume, the producer rewrites at the slug-scoped path on the next checkpoint, and the older paths stay orphaned on disk, while a legacy `./.geniro/state/<skill>/<slug>/` dir has been moved to `$STATE_DIR` (§Cleanup contract, Old path cleanup).

## Cleanup contract

When a skill completes its pipeline, it removes its slug-scoped state directory — the whole dir, not just `state.md`:

```bash
STATE_DIR="$(source "${CLAUDE_PLUGIN_ROOT}/lib/unit-dir.sh" && _geniro_state_dir <skill>)"; [ -n "$STATE_DIR" ] && rm -rf "$STATE_DIR"
```

Resolve and remove in one Bash call. The slug is recomputed from the current branch at cleanup time, so the deletion targets the dir the skill itself wrote. Guard on a non-empty `STATE_DIR`: an empty one leaves `rm -rf` with no safe target. Removing the directory sweeps any scratch the run wrote alongside `state.md` (`/geniro:debug` may write experiment artifacts there), and the migration sweep only scans `.geniro/planning`, so a stray file has no backstop. Durable cross-run artifacts never live in this dir — handoffs are in the unit dir `<PLANNING_ROOT>/<unit>/`, authored tests at the project's test paths, the codebase map at `.geniro/planning/_*.md` — so removing it loses nothing the chain still needs. Delete only the current branch's slug dir, never a glob across `.geniro/state/<skill>/*/` — sibling slugs belong to parallel pipelines on other branches still in flight.


**Old path cleanup.** Producer skills do NOT clear the older legacy paths listed in `## Consumer contract` step 4 at run end, and no cleanup pass removes them; they exist solely as the Case D resume fallback, checked only when the slug-scoped path is absent, so an old-format state file still resumes instead of silently disappearing. The one exception is the worktree-local legacy dir, which Case D moves to `$STATE_DIR`.

The `2>/dev/null || true` discipline applies — these are best-effort.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I'll skip the slug — one task at a time" | The state dir is shared by every session in the repo, so an unscoped file is the documented collision. Slug is mandatory. |
| "I'll use `${CLAUDE_SESSION_ID}` instead of branch slug" | Session IDs are opaque, accumulate orphans, and don't survive compaction. Branch is the natural durability anchor. |
| "I'll auto-execute `git checkout <state-branch>` in Case C" | Forbidden by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Forbidden discovery moves. Mismatch surfaces an AUQ; the user runs the checkout themselves. |
| "I'll delete all `.geniro/state/<skill>/*/` at cleanup to be tidy" | Other slug dirs belong to other-branch pipelines that may still be in flight. Delete only the current branch's slug dir. The older paths in `## Consumer contract` step 4 are no delete target either, apart from the worktree-local dir Case D moves (§Cleanup contract, Old path cleanup). |
| "I'll skip Case D — users can clean up old state files themselves" | Old state files exist in users' trees. Case D is the migration ramp; without it, the first run after upgrade silently strips a real resume. |

## Definition of Done

- [ ] Producer writes the full T1.5 frontmatter field set inside the `---` fence — common-base `producer` / `schema-version` / `branch` / `timestamp` + tier-specific `phase` / `status` / `non-resumable-actions` (per state-tier-spec.md), plus this helper's `worktree:` — with the frontmatter starting on line 1
- [ ] Producer writes to slug-scoped path; never to a non-scoped path
- [ ] Consumer reads slug-scoped path first, older path as fallback (Case D)
- [ ] Consumer fires Case-C AUQ on branch mismatch; never auto-executes git operations
- [ ] Cleanup deletes only the current branch's slug; never other slugs
- [ ] Producer/consumer pair survives compaction (state file is the durable medium)
