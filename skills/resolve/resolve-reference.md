# /geniro:resolve — reference

Phase detail and schemas for `/geniro:resolve`. The skill body (`SKILL.md`) holds the workflow; this file holds the item inventory, the verdict rubric, and the two output schemas. The `gh` command shapes live once in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` — this file references them, never re-states them.

## Contents

- §1 — Inventory item schema (Phase 1)
- §1.5 — Workspace sync: local checkout → PR head (Phase 1)
- §2 — Verdict rubric + verify/reproduce (Phase 2)
- §2.5 — Clarify gate mechanics (Phase 3)
- §3 — Spec `## Comment Resolution Map` (Phase 4)
- §4 — Handoff `comment_resolutions[]` (Phase 4)

---

## 1. Inventory item schema (Phase 1)

The read side of `pr-threads.md` (§2 threads, §3 checks) returns raw GraphQL / `gh pr checks` JSON. Phase 1 normalizes it into one item list. Each item:

```yaml
- item_id: r1                  # stable local anchor (r = review-comment, c = ci-check)
  source: review-comment       # review-comment | ci-check
  thread_id: <PRRT_…|null>     # review-comment: the thread node id; ci-check: null
  comment_id: <numeric|null>   # review-comment: top comment databaseId; ci-check: null
  author: <login|null>         # review-comment author; ci-check: null
  is_bot: <bool>               # coderabbitai[bot] / greptile-apps[bot] / … → true
  path: <file|null>            # cited file; ci-check: annotation path if any, else null
  line: <int|null>
  body: |                      # review-comment: the thread conversation; ci-check: check output
    <verbatim text>
  verdict:                     # filled in Phase 2
  reply_draft:                 # filled in Phase 2 (review-comment only)
  verify:                      # filled in Phase 4 (fix items)
  fix_step_anchor:             # filled in Phase 4 (fix items)
```

Build rules:
- Collapse a multi-comment thread to ONE item — concatenate the comment bodies into `body`, keep the FIRST comment's `databaseId` as `comment_id` (the reply anchor) and the thread `id` as `thread_id`.
- Drop threads with `isResolved == true` (idempotency).
- A `CHANGES_REQUESTED` formal review with no inline thread becomes an item with `thread_id: null` (it cannot be resolved via API) — verdict `answer-only` at most.
- Group items by `path` so Phase 2 verifies neighbours together; CI items with `path: null` form their own group.

## 1.5 Workspace sync: local checkout → PR head (Phase 1)

The first of the two Phase 1 sync offers (the second — branch vs its base — is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`). The comments are anchored to the PR head (`pr-head-sha` = `headRefOid`); if the local tree sits on a different commit, the verifier reads code the comments do not describe.

```bash
LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null)"
# pr-head-sha captured in Phase 1 Step 1 from gh pr view --json headRefOid
```

- `LOCAL_HEAD == pr-head-sha` → already on the PR head; skip silently, no question.
- Differs → fire ONE AskUserQuestion:

```
header: "Update to PR"
question: "Your checkout is on a different commit than the PR's latest (<short pr-head-sha>). Check out the PR's latest commit before triaging the comments?"
options:
  - "Check out the PR head (Recommended)"  -> gh pr checkout <number>
  - "Keep my current checkout"             -> no git action
```

- `gh pr checkout <number>` handles both cases — on the PR branch but behind (fast-forwards), or not on the PR branch at all (creates/switches to it). It refuses on a dirty tree; when `git status --porcelain` is non-empty, chain the §5 dirty-tree offer from `branch-freshness.md` (stash → checkout → pop) rather than forcing it.
- Fail-open: any non-zero `gh`/`git` exit → surface a one-line caveat ("Couldn't switch to the PR head — triaging against your current checkout; some comments may reference code you don't have locally.") and proceed. Persist the pick to `approvals[]` (category `branch_freshness`).

Run this BEFORE the branch-vs-base offer (Step 2b): land on the PR head first, then bring that up to date with the base.

## 2. Verdict rubric + verify/reproduce (Phase 2)

Per item, after reading the cited code and attempting a repro:

| Verdict | When | Reply draft | Downstream |
|---|---|---|---|
| `fix` | The comment names a real, reachable issue in the current head; you can state what + how to fix | "Addressed in <one-line summary of the fix>." | Becomes a spec Step; `comment_resolutions[]` with `resolve_after_fix: true` |
| `answer-only` | The comment asks a question that needs a reply but no code change | The answer, grounded in the code | `comment_resolutions[]` with `verdict: answer-only`, `resolve_after_fix: false` |
| `needs-clarification` | The intended change is ambiguous — two or more plausible reads | — (deferred to Phase 3) | An `open_questions[]` entry; resolved answer may later become a `fix` |
| `wontfix` | The comment is mistaken, stale, already-fixed, or out of PR scope | The evidence-backed push-back (cite the code that refutes it) | `comment_resolutions[]` with `verdict: wontfix`, `resolve_after_fix: false` (reply, leave thread open) |

**Verify each `fix`/`wontfix`** (invariant #2). Every `fix`/`wontfix` item gets a fresh `finding-verifier-agent` verdict — no small-PR carve-out — treating the comment as the finding (the cited slice + caller grep + sibling tests per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2). Items citing the same file share one spawn, at the cluster cap defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4, one verdict block each; a solo item spawns singly. The tier (SKILL.md Budgets table) sets the vote count, not whether the verifier runs: one verifier vote by default; on Big, signal-gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3 to 3 votes only on a contested verdict, run per item rather than clustered. Fire the whole batch in one assistant turn. Aggregate:
- A `fix` the verifier **refutes** (the issue is not real / not reachable / already fixed) demotes to `wontfix` (draft the push-back) or drops if clearly stale.
- A `wontfix` the verifier **refutes** (the comment is actually right) re-opens as `needs-clarification` or `fix`.

**Reproduce** before marking `fix`:
- A bug-claim → construct a concrete failing case or name the exact trigger path. A claim that cannot be reproduced is evidence for `wontfix`, not `fix`.
- A `ci-check` → run the failing command locally when the check name/output makes it derivable (`test:unit` → the project test command scoped to the failing file). A locally-reproduced failure confirms the `fix`; a green local run flags an environment-only / flaky check → `answer-only` ("passes locally; likely flaky/env").

## 2.5 Clarify gate mechanics (Phase 3)

Each ambiguous item's lean `AskUserQuestion` carries the item's own interpretations as options, plus two standing aids:

- **"Explain further"** — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option. Renders a deeper walkthrough and re-fires the same question; writes nothing, consumes no cap slot.
- **"Challenge this comment"** — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Challenge-finding option. Spawns one fresh `finding-verifier-agent` (the Phase 2 re-verify mechanism; OMIT `model=`) primed with the user's objection, to re-check whether the comment is valid and reachable. Re-renders the item with the verdict, then re-fires the question. A `refuted` result reclassifies the item to `wontfix` (with the evidence-backed push-back draft) and drops its gate.

When the item's interpretations plus these two aids exceed 4 slots, chain per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Cap-extension — never drop an interpretation to make room. The chain extends only that one item's own option list past 4; items still fire one at a time, never batched into one call's `questions[]`.

Persist each pick to `approvals[]` (category `comment_clarification`) and write the resolved answer into the item's `open_questions[]` entry, setting `related_comments: [<thread_id>]` so the question traces back to the comment that raised it. A deferred item stays `status: unresolved` and travels to `/geniro:implement` for re-gating.

## 3. Spec `## Comment Resolution Map` (Phase 4)

Appended to `spec.md`'s standard spec schema (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`) as an allowed extra body section. Human-readable; the `comment_resolutions[]` array (§4) mirrors its review-comment rows.

```markdown
## Comment Resolution Map

| # | Source | Author | Location | Verdict | What & how to fix (or push-back) | Resolves via |
|---|--------|--------|----------|---------|----------------------------------|--------------|
| 1 | review-comment | coderabbitai[bot] | api/users.ts:42 | fix | Guard the null deref before the map() | step-3 |
| 2 | review-comment | alice | api/users.ts:88 | wontfix | Intentional — the caller already validates; cite L70-74 | — |
| 3 | review-comment | bob | api/users.ts:12 | answer-only | Yes, the retry is bounded at 3 (L9) | — |
| 4 | ci-check | — | test:unit (users.spec) | fix | Update the fixture for the new field | step-5 |
```

- Every `fix` row maps to a Step in §6 (`Resolves via step-N`) and a §9 `verify:` criterion.
- `wontfix` / `answer-only` rows have no Step (`Resolves via —`) — they produce only a reply.
- The drafted reply text for each row is NOT in this table (it can be long) — it lives in the handoff `comment_resolutions[].reply_draft`.

## 4. Handoff `comment_resolutions[]` (Phase 4)

The array lives in `from-resolve-<branch>.md` frontmatter and MAY be `[]`. Its per-entry schema — the fields `thread_id`, `comment_id`, `source`, `author`, `path`, `line`, `verdict`, `reply_draft`, `resolve_after_fix`, `verify`, `fix_step_anchor`, `status`, plus their enums and the producer/consumer responsibilities — is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §Producer-specific extensions (change in lockstep with `/geniro:implement`). Read the field definitions there before the Phase 4 write rather than reconstructing them here.

What `/geniro:implement` then does with each entry at its Ship sub-step is that same section's Consumer responsibilities; the producer's job ends at writing the array.
