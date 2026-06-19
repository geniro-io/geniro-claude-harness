# /geniro:resolve — design doc

Source of truth for the `/geniro:resolve` build. Pins the schemas every file depends on. Approved 2026-06-19.

## Decisions (locked)

| Fork | Choice |
|---|---|
| Who closes the loop (post replies + resolve threads) | **/geniro:implement at ship** (not a `/resolve --close` second run) |
| Scope of "errors" read from the PR | **Review comments + failing CI checks** |
| Comment authors processed | **Humans + bots** (CodeRabbit / Greptile / Sourcery / …) |
| Skill name | **/geniro:resolve** |

## What it is

A read-only **spec producer**. Given an open PR, it reads every unresolved review thread and failing CI check, verifies/reproduces each against the code, asks the user about ambiguous ones, then writes a comment-keyed `spec.md` + a T2 handoff. `/geniro:implement` consumes the handoff, applies the fixes, and — new — at ship re-verifies each fix landed and posts the drafted reply + resolves the thread.

`/geniro:resolve` NEVER edits code and NEVER posts to the PR. `/geniro:review` writes review comments (author side); `/geniro:resolve` reads + triages them (recipient side); `/geniro:implement` mutates code AND closes the threads at ship. PR-comment I/O *logic* is single-sourced in `_shared/pr-threads.md`; only the invocation points differ.

## Files this touches

1. `skills/resolve/SKILL.md` (new) — the producer, read-only.
2. `skills/resolve/resolve-reference.md` (new) — phase detail, schemas, gh shapes.
3. `skills/_shared/pr-threads.md` (new) — the PR-comment/CI I/O contract: read side (list unresolved threads + failing checks) for `/resolve`, write side (reply + resolve thread) for `/implement`.
4. `skills/_shared/state-tier-spec.md` (edit) — `/resolve` producer section + the handoff `comment_resolutions[]` array (schema lockstep with `/implement`).
5. `skills/implement/SKILL.md` (edit) — Phase 1 Step 12 parses `comment_resolutions[]`; new post-ship Ship sub-step "Resolve PR review threads".
6. `CLAUDE.md` (edit) — add the `/geniro:resolve` row to the skills table.

No new agent: Phase 2 per-comment verification reuses `reviewer-agent` (verify-finding mode); CI-repro reuses orchestrator Bash + a general research spawn.

## Pinned schema — handoff `comment_resolutions[]`

Rides in the T2 handoff frontmatter `from-resolve-<branch>.md` alongside the existing `open_questions[]`. `/implement` reads it at ship.

```yaml
comment_resolutions:                 # producer: resolve · consumer: implement · MAY be empty []
  - thread_id: <PRRT_node_id>        # GraphQL reviewThread node id — for resolveReviewThread
    comment_id: <numeric>            # top comment of the thread — for the reply endpoint
    source: review-comment | ci-check
    author: <login>                  # bot logins keep their suffix (coderabbitai[bot])
    path: <file|null>                # null for a check with no annotation location
    line: <int|null>
    verdict: fix | answer-only | wontfix
    reply_draft: <text to post on the thread>
    resolve_after_fix: <bool>        # fix → true (resolve thread); wontfix/answer-only → false
    verify: <shell command|null>     # passes ⇒ the fix landed (links to spec §9 criterion)
    fix_step_anchor: <step-N|null>   # links to the spec Step that implements the fix
    status: pending                  # pending | posted | skipped
```

Rules:
- `verdict: fix` → `resolve_after_fix: true`. `/implement` posts `reply_draft` AND resolves the thread, but ONLY after re-verifying the fix landed (`verify:` passes, or `fix_step_anchor`'s files appear in the pushed diff). If the fix did not land → `status: skipped`, thread untouched.
- `verdict: wontfix` → `resolve_after_fix: false`. `/implement` posts the evidence-backed push-back reply, leaves the thread OPEN for the reviewer.
- `verdict: answer-only` → no code change. `/implement` posts the answer reply; `resolve_after_fix: false` — the reviewer resolves the thread after reading the answer.
- `source: ci-check` items have no thread to resolve (a check goes green on the next push). They appear in the spec's fix Steps but carry NO `comment_resolutions[]` entry. (Only review-comment items get entries.)

## Pinned schema — spec `## Comment Resolution Map`

A body section appended to the standard /plan 11-section `spec.md` (allowed extra section, like `## Considered Alternatives`). One row per processed item, human-readable, the source of truth the `comment_resolutions[]` array mirrors.

```markdown
## Comment Resolution Map

| # | Source | Author | Location | Verdict | What & how to fix | Resolves via |
|---|--------|--------|----------|---------|-------------------|--------------|
| 1 | review-comment | coderabbitai[bot] | api/users.ts:42 | fix | <one line> | step-3 |
| 2 | review-comment | alice | api/users.ts:88 | wontfix | push-back: <reason> | — |
| 3 | ci-check | — | test:unit | fix | <one line> | step-5 |

For each `fix`/`wontfix`, the drafted reply text is held in the handoff `comment_resolutions[].reply_draft`.
```

## Reused schemas (no change)

- **`open_questions[]`** (state-tier-spec §T2) — the `needs-clarification` comments map onto it 1:1, adding an optional `related_comments: [<thread_id>]` field (parallel to the existing `related_findings[]`). `/implement` already gates Edit/Write on unresolved entries — the ambiguous comments must be resolved before fixing.
- **spec.md** — the standard /plan 11-section schema + frontmatter; `producer: resolve`, `geniro_kind: design-doc`. `workflow_refs[]` if the PR links a tracker ticket.
- **Handoff frontmatter** — same as review's: `pr-ref` / `pr-url` / `pr-head-sha` / `resolved-threads-snapshot` carried so `/implement` knows the PR at ship.

## Stages

### /geniro:resolve (Mode A, read-only)

- **Phase 1 — Fetch & Triage.** Resolve the PR (`$ARGUMENTS` `#N`/URL, else `gh pr view` on the branch; fail-open → ask). Via `_shared/pr-threads.md` read side: unresolved threads (`isResolved == false`, bodies + authors + path/line, humans + bots) AND failing CI (`gh pr checks` + check-run annotations). Build the item inventory; collapse a thread to one item; group by file. Tier (Trivial/Small/Medium/Big via `_shared/effort-scaling.md`) scales the Phase 2 verifier count. Idempotency: skip items whose thread `isResolved == true`.
- **Phase 2 — Analyze & Verify** (per item, /debug methodology). Classify intent (change / question / wrong-claim / ci-fail). Verify against current code (read cited path:line). Reproduce bug-claims and CI-fails locally (bounded). Verdict per item: `fix` / `answer-only` / `needs-clarification` / `wontfix`. Adversarially re-verify each verdict (`reviewer-agent` verify-finding mode, signal-gated per `_shared/deep-mode.md` precision layer); a refuted `fix` demotes to `wontfix`/drop.
- **Phase 3 — Clarify.** For `needs-clarification` items only: message-first render (comment + code + options) then a lean AUQ per `_shared/gate-rendering.md`. Picks → `approvals[]` + `open_questions[]`. Unresolved deferrals stay `status: unresolved`.
- **Phase 4 — Emit.** Write `spec.md` (T1.5) with `## Comment Resolution Map`; Steps (§6) carry the fixes, Validation (§9) carries `verify:` per fix. Write the handoff `from-resolve-<branch>.md` (T2) with `open_questions[]` + `comment_resolutions[]` + `pr-ref`/`pr-head-sha`. Hand off → `/geniro:implement <handoff>`. NEVER edits code, NEVER posts.

### /geniro:implement — new post-ship Ship sub-step "Resolve PR review threads"

- Phase 1 Step 12 already parses the handoff; extend it to also stash `comment_resolutions[]`.
- After the Ship-mode AUQ approves and the push/PR lands, for each `comment_resolutions[]` entry with `status: pending`:
  - **Re-verify the fix landed** (`verdict: fix`): run `verify:` if present, else confirm `fix_step_anchor`'s files are in the pushed diff. Not landed → `status: skipped`, skip.
  - **Action gate (AUQ)** "Post N replies + resolve M threads on PR #X?" — external write, mirrors the existing push gate, never auto.
  - On approve: via `_shared/pr-threads.md` write side, post `reply_draft` + (for `resolve_after_fix: true`) `resolveReviewThread`. Mark `status: posted`. Append a `non-resumable-actions[]` entry (`pr-comment-posted`).
- Skips entirely when the handoff carries no `comment_resolutions[]` (non-resolve handoffs).

## Validation

- Phase 2 verifier re-checks every `fix`/`wontfix` verdict; refuted demotes (precision, signal-gated — bounded cost).
- Reproduce bug-claims + CI-fails locally before marking `fix`.
- Always-on spec-challenge (`_shared/spec-challenge.md` MODE: plan-equivalent) red-teams the produced spec before handoff.
- Mechanical: spec passes /plan's validator (11-section shape + frontmatter).
- `/implement` re-verifies each fix landed BEFORE resolving a thread — never claim-resolves a thread whose fix didn't land or didn't match.
- Idempotency: already-resolved threads skipped; re-running Mode A doesn't re-spec handled items.

## Known tradeoffs of the /implement-at-ship choice

- **Manual-fix path does not auto-close threads.** If the user fixes by hand (not via `/implement`), nothing posts replies / resolves threads — they resolve on GitHub themselves. A future `/resolve --close` fallback could cover this; out of scope for v1.
- **+1 ship gate** in `/implement` and **schema lockstep** handoff↔implement (`comment_resolutions[]` defined once in state-tier-spec, read by implement).

## Boundaries

- `/resolve` allowed-tools: Read, Grep, Glob, Bash (read-only `gh` + `atomic_state_write`), Agent (reviewer-agent verify), AskUserQuestion, TodoWrite. NO Edit/Write — the read-only producer boundary is enforced at the tool level (state files write via `atomic_state_write`, never the Write tool).
- Never ships code, never posts to the PR. The only external GitHub write in this whole feature is `/implement`'s ship sub-step, action-gated.
