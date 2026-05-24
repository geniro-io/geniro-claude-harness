# Within-skill state handoff (canonical, shared)

**Status:** Authoritative for these task-local state files: `.geniro/state/refactor/<slug>/state.md` (M8 §9.1 — subdir-per-slug layout, M1 §T1 session-bound), `.geniro/state/debug/<slug>/state.md` (M7 §11.1 — subdir-per-slug layout, M1 §T1 session-bound), `.geniro/state/onboard/<slug>/state.md` (M9 §11.1 — subdir-per-slug layout, M1 §T1 session-bound), `.geniro/state/investigate/<slug>/state.md` (M9 §11.2 — subdir-per-slug layout, M1 §T1 session-bound).

Within-skill state files are task-local and intentionally cwd-relative, but two parallel sessions sharing the same `pwd` on different branches collide on identical paths. This file codifies the slug-scoped path contract, the headers every producer embeds, and the mismatch UX every consumer surfaces on resume.

## Why this exists

Two terminals open in the same `pwd` on different branches both write `.geniro/<skill>/state.md` — one silently overwrites the other. Sequential same-cwd sessions on different branches inherit the prior branch's state on resume after compaction, applying old plans to new code. Cross-session state files (`.geniro/knowledge/*`, `.geniro/state/handoff/from-review-<branch>.md`, `.geniro/state/handoff/from-debug-<branch>.md` per M6 §15.1 / M7 §11.2 M1-T2 canonical) route through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` to land in the primary worktree's tree — a different problem with a different fix, and NOT this file's concern. Within-skill state must stay task-local AND become branch-scoped so concurrent same-cwd pipelines on different branches stop colliding.

## Slug rules

The branch slug is the suffix on every within-skill state file path. Compute it once at producer-write time and again at consumer-read time; both sites MUST produce the same string for the consumer to find the producer's state.

```bash
branch="$(git branch --show-current 2>/dev/null)"
if [ -z "$branch" ]; then
  branch="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
slug="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]' | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##')"
slug="${slug:0:60}"
slug="${slug%-}"
```

When `git` is unavailable or the project isn't a git repo, the fallback chain produces slug `detached-unknown` — the file still works for single-session use; collision is impossible without branches.

## Producer contract

Every producer of a within-skill state file MUST:

1. Compute the slug per `## Slug rules`.
2. Write to the slug-scoped path: `.geniro/state/<skill>/state-<slug>.md` (or `.geniro/state/debug/<slug>/state.md` for debug — M7 §11.1 subdir-per-slug layout; or `.geniro/state/refactor/<slug>/state.md` for refactor — M8 §9.1 subdir-per-slug layout; or `.geniro/state/onboard/<slug>/state.md` for onboard — M9 §11.1 subdir-per-slug layout; or `.geniro/state/investigate/<slug>/state.md` for investigate — M9 §11.2 subdir-per-slug layout — all four M1 §T1 session-bound). Never write to a non-scoped path. The `.geniro/state/` prefix is mandatory — root-level state files are blocked by convention so only user-content (instructions/, actions/, workflow/, planning/, knowledge/) lives at the root.
3. Embed these three headers at the TOP of the file, before any other content:

```
Branch: <git branch --show-current OR detached-<short-sha>>
Worktree: <git rev-parse --show-toplevel>
Timestamp: <ISO-8601 UTC, e.g., 2026-05-07T14:32:00Z>
```

The `Branch:` header is the source of truth on resume — even if two branch names slugify identically after truncation (rare but possible at >60 chars), the header is unambiguous. The `Worktree:` header detects the rare case where `pwd` changed without a branch change. The `Timestamp:` aids stale-state diagnosis.

## Consumer contract

On skill start (or resume after compaction), every consumer MUST:

1. Compute current branch + slug per `## Slug rules`.
2. Try to read `.geniro/state/<skill>/state-<slug>.md` (primary path; debug uses `.geniro/state/debug/<slug>/state.md` per M7 §11.1; refactor uses `.geniro/state/refactor/<slug>/state.md` per M8 §9.1; onboard uses `.geniro/state/onboard/<slug>/state.md` per M9 §11.1; investigate uses `.geniro/state/investigate/<slug>/state.md` per M9 §11.2).
3. If the primary path exists, parse `Branch:` and `Worktree:` headers and run `## Mismatch handling` Case A/B/C.
4. If the primary path does NOT exist BUT an older path exists at any of these locations, enter Case D (migration). Try in this order:
   - `.geniro/<skill>/state-<slug>.md` (slug-scoped, older directory layout)
   - `.geniro/<skill>-state.md` or `.geniro/<skill>/state.md` (non-scoped)
   - For debug: `.geniro/state/debug/HYPOTHESES-<slug>.md`; then `.geniro/debug/HYPOTHESES-<slug>.md`; then `.geniro/debug/HYPOTHESES.md`
   - For refactor: `.geniro/state/refactor/state-<slug>.md`; then `.geniro/refactor/state-<slug>.md`; then `.geniro/refactor/state.md`
5. If neither exists, no state to resume — proceed fresh.

## Mismatch handling

Four cases — consumers MUST handle all four:

**Case A — Headers match current branch + worktree.** Proceed silently with the resume. No user-visible message needed.

**Case B — Branch matches, Worktree differs.** Rare (typically: user moved the repo or has multiple checkouts of the same branch). Surface a one-line note: `State found for branch '<branch>' but written from worktree '<state-worktree>'; current worktree is '<current-worktree>'. Proceeding.` No AUQ — Branch identity is sufficient for resume.

**Case C — Branch differs (collision detected).** Fire `AskUserQuestion` (the canonical user-facing recovery — NOT improvised at runtime):

- Header: "State mismatch"
- Question: "State file at <path> targets branch '<state-branch>' (worktree '<state-worktree>') but you are on '<current-branch>' (worktree '<current-worktree>'). How should I proceed?"
- Options (in this order — first is Recommended):
  1. **"Stop — I'll switch to <state-branch>"** (Recommended) — abort the skill; user runs `git checkout <state-branch>` (or `cd <state-worktree>` if a sibling worktree) and re-invokes.
  2. **"Discard and start fresh on <current-branch>"** — delete the conflicting state file; begin a new pipeline scoped to current branch.
  3. **"Continue anyway"** — proceed; changes will land on `<current-branch>` regardless of what the state file claims. WARN that downstream cross-references in the state file (e.g., `changed-files:`) may be wrong.

**Case D — Non-scoped state file at an older path.** Surface a one-line migration note: `Old state file at <path>; scoping to current branch slug.` Then either (a) read it as if Case A/B/C using its embedded `branch:` field if present, or (b) treat as Case C if the file lacks branch headers. After successful resume, the producer rewrites at the slug-scoped path on the next checkpoint, and the old file becomes orphaned (cleaned at next pipeline-end).

## Cleanup contract

When a skill completes its pipeline, it MUST delete its slug-scoped state file at `.geniro/state/<skill>/state-<slug>.md`. The slug is recomputed from the current branch at cleanup time, so the deletion targets the file the skill itself wrote — no need to grep `Branch:` headers. Skills MUST NOT glob and bulk-delete `.geniro/state/<skill>/state-*.md` — sibling slugs belong to parallel pipelines on other branches still in flight.

**Old path cleanup.** Producer skills MUST also `rm -f` older paths on cleanup, in case stale files persist. Paths to clear per skill:

**Debug:**
- `.geniro/state/debug/HYPOTHESES-<slug>.md`
- `.geniro/state/debug/findings-state.md`
- `.geniro/state/debug/adversarial-tests.md`
- `.geniro/debug/HYPOTHESES-<slug>.md`
- `.geniro/debug/HYPOTHESES.md`

**Refactor:**
- `.geniro/state/refactor/state-<slug>.md`
- `.geniro/refactor/state-<slug>.md`
- `.geniro/refactor/state.md`

**Onboard / Investigate:** no older paths to clear — cleanup only targets the current path at `.geniro/state/<skill>/<slug>/`.

The `2>/dev/null || true` discipline applies — these are best-effort.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I'll skip the slug — same `pwd` always means same task" | Two terminals on different branches in the same `pwd` is the documented bug. Slug is mandatory. |
| "I'll route through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A for safety" | That helper routes cross-session state to the primary worktree's tree. Within-skill state is task-local — Mode A would make sequential branch-A and branch-B sessions in `.claude/worktrees/<X>/` write into `<primary>/.geniro/...`, RE-introducing the same collision the primary helper was designed to fix elsewhere. Use the slug here instead. |
| "I'll use `${CLAUDE_SESSION_ID}` instead of branch slug" | Session IDs are opaque, accumulate orphans, and don't survive compaction. Branch is the natural durability anchor. |
| "I'll auto-execute `git checkout <state-branch>` in Case C" | Forbidden by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` § Forbidden discovery moves. Mismatch surfaces an AUQ; the user runs the checkout themselves. |
| "I'll delete all `.geniro/state/<skill>/state-*.md` at cleanup to be tidy" | Other slug files belong to other-branch pipelines that may still be in flight. Delete only the current branch's slug (для debug: only `.geniro/state/debug/<slug>/state.md`; для refactor: only `.geniro/state/refactor/<slug>/state.md`; для onboard: only `.geniro/state/onboard/<slug>/state.md`; для investigate: only `.geniro/state/investigate/<slug>/state.md`). The older paths listed in the cleanup section ARE yours to `rm -f` — they are not sibling slugs. |
| "I'll skip Case D — users can clean up old state files themselves" | Old state files exist in users' trees. Case D is the migration ramp; without it, the first run after upgrade silently strips a real resume. |

## Definition of Done

- [ ] Producer writes Branch:/Worktree:/Timestamp: headers at the top of every state file
- [ ] Producer writes to slug-scoped path; never to a non-scoped path
- [ ] Consumer reads slug-scoped path first, older path as fallback (Case D)
- [ ] Consumer fires Case-C AUQ on branch mismatch; never auto-executes git operations
- [ ] Cleanup deletes only the current branch's slug; never other slugs
- [ ] Producer/consumer pair survives compaction (state file is the durable medium)
