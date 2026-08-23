<!-- Generated from skills/resolve/resolve-reference.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# /geniro:resolve — reference

Phase detail and schemas for `/geniro:resolve`. The skill body (`SKILL.md`) holds the workflow and its invariants; this file holds the item inventory, the verdict + filter rubric, the gate mechanics, the ship gate and the report shape. The `gh` command shapes live once in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/pr-threads.md` — this file references them, never re-states them.

## Contents

- §1 — Inventory item schema (Phase 1)
- §1.5 — Workspace sync: local checkout → PR head (Phase 1)
- §2 — Verdict + filter rubric (Phase 2)
- §2.5 — Gate mechanics (Phase 2)
- §3 — Reply shapes + the ship gate (Phase 3)
- §4 — Final report (Phase 3)

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
  verdict:                     # Phase 2: fix | ask | answer-only | decline
  reason:                      # Phase 2, decline only: wrong-claim | over-engineering | out-of-scope | regression-risk | too-large
  picked:                      # Phase 2, ask only: true once the user picks it, false when left unpicked
  reply_draft:                 # Phase 3 (review-comment only)
  files_touched:               # Phase 3 (applied items) — what the reply names and the resolve gate checks
```

Build rules:
- Collapse a multi-comment thread to ONE item — concatenate the comment bodies into `body`, keep the FIRST comment's `databaseId` as `comment_id` (the reply anchor) and the thread `id` as `thread_id`.
- Drop threads with `isResolved == true` (idempotency).
- A `CHANGES_REQUESTED` formal review with no inline thread becomes an item with `thread_id: null` — it cannot be replied to or resolved through the API, so it can still produce a fix, but its outcome reaches the user through the final report rather than the PR.
- Group items by `path` so one read of a file in Phase 2 serves every item citing it; CI items with `path: null` form their own group.

## 1.5 Workspace sync: local checkout → PR head (Phase 1)

The first of the two Phase 1 sync offers (the second — branch vs its base — is owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md`). The comments are anchored to the PR head (`pr-head-sha` = `headRefOid`); if the local tree sits on a different commit, the analysis reads code the comments do not describe and the fixes land somewhere other than the PR branch.

```bash
LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null)"
# pr-head-sha captured in Phase 1 Step 1 from gh pr view --json headRefOid
```

- `LOCAL_HEAD == pr-head-sha` → already on the PR head; skip silently, no question.
- Differs → fire ONE AskQuestion:

```
header: "Update to PR"
question: "Your checkout is on a different commit than the PR's latest (<short pr-head-sha>). Check out the PR's latest commit before working through the comments?"
options:
  - "Check out the PR head (Recommended)"  -> gh pr checkout <number>
  - "Keep my current checkout"             -> no git action
```

- `gh pr checkout <number>` handles both cases — on the PR branch but behind (fast-forwards), or not on the PR branch at all (creates/switches to it). It refuses on a dirty tree; when `git status --porcelain` is non-empty, chain the §5 dirty-tree offer from `branch-freshness.md` (stash → checkout → pop) rather than forcing it.
- Fail-open: any non-zero `gh`/`git` exit → surface a one-line caveat ("Couldn't switch to the PR head — working against your current checkout; some comments may reference code you don't have locally, and any fix will land here rather than on the PR branch.") and proceed. Persist the pick to `approvals[]` (category `branch_freshness`).

Run this BEFORE the branch-vs-base offer (Step 2b): land on the PR head first, then bring that up to date with the base.

## 2. Verdict + filter rubric (Phase 2)

Per item, after reading the cited code and attempting a repro. The filter is the verdict — there is no separate pass.

| Verdict | When | Downstream |
|---|---|---|
| `fix` | The comment names a real, reachable issue in the current head, and the correction is behavior-preserving: it makes the code do what its own tests, spec and callers already expect | Applied in Phase 3 without asking. Reply names what changed; thread resolves once the fix is pushed |
| `ask` | The correction is real and worth making, but it changes something a caller could depend on — an API shape, a default, error semantics, a data format, ordering, a deliberate performance trade-off. Also: any item you cannot confidently place on either side of that line | Goes to the decision gate. Picked → applied like a `fix`. Unpicked → nothing applied, nothing posted, reported to the user |
| `answer-only` | The comment asks a question that needs a reply but no code change | Reply posted; thread stays open unless the answer settles it |
| `decline` | The ask fails the worth-doing bar below | Evidence-backed push-back reply; thread stays open; no code change |

**The worth-doing bar.** A `decline` always carries one `reason`, and the reason is what the push-back argues:

| `reason` | The case for declining | What the push-back must show |
|---|---|---|
| `wrong-claim` | The comment is mistaken, stale, or describes an already-fixed or unreachable path | The code that refutes it, cited by `path:line` |
| `over-engineering` | The ask adds an abstraction, a configuration surface, or a generalization the current code has one caller for | What the existing code does, and what the abstraction would cost against one use |
| `out-of-scope` | The ask is a real improvement to code this PR did not change | That the cited lines are outside the PR's diff, plus where the work belongs instead |
| `regression-risk` | Making the change would break behavior something depends on | The dependent — a test that pins it, a caller that relies on it, a documented contract |
| `too-large` | The ask is real and in scope but is its own piece of work, not a review-round fix | What the change would actually touch, so the user can size the separate work |

Two rules keep this from becoming a way to avoid work: a `decline` is only ever assigned with evidence you can quote, and every `decline` is re-checked by a fresh `finding-verifier-agent` before its reply is drafted (SKILL.md §Loop invariants #3). A verifier that refutes the decline re-opens the item as `fix` or `ask`. "I would rather not" is not a reason on this table.

**Reproduce before you commit to a verdict.**
- A bug claim → construct a concrete failing case or name the exact trigger path. A claim that cannot be reproduced is evidence for `decline` / `wrong-claim`.
- A `ci-check` → run the failing command locally when the check name and output make it derivable (`test:unit` → the project test command scoped to the failing file). A locally-reproduced failure confirms the `fix`; a green local run flags an environment-only or flaky check → report it, no code change.

## 2.5 Gate mechanics (Phase 2)

**The decision gate — one multi-select call over the `ask` items.** Shape per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Multi-select pick loop:

- `multiSelect: true`; `question`: "Pick the changes to apply".
- One option per `ask` item. `label`: the change in the user's terms ("Retry default 3 → 5"). `description`: one line naming the consequence and who is exposed to it. `preview`: empty or a one-line recap.
- Past 4 items, chain per that file's §Cap-extension — never drop an item to fit the call.

The chat message that precedes it (§Message-first rendering in the same file) is the rendering surface, and it carries all three groups, in this order:

1. **Applying without asking** — one line per `fix`: the comment, the file, the correction. Short; these need no decision, only visibility.
2. **Needs your call** — one block per `ask`: what the reviewer asked, what the code does now, what changes for a caller if it is applied, and what happens if it is not. This is the block the gate is answerable from, so consequence goes here, not classification.
3. **Declining** — one line per `decline`: the comment, the reason, and the evidence in a clause. The user is answerable for a push-back posted under their PR, so they see it before it is drafted.

**The single-item gate — one call per ambiguous item.** Shape per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate. Options are the item's competing readings plus two standing aids:

- **"Explain further"** — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option. Renders a deeper walkthrough and re-fires the same question; writes nothing, consumes no cap slot.
- **"Challenge this comment"** — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Challenge-finding option. Spawns one fresh `finding-verifier-agent` (OMIT `model=`) primed with the user's objection. A `refuted` result reclassifies the item to `decline` with the verifier's evidence as the push-back and drops the gate.

Persist every pick to `approvals[]` (category `comment_decision`). An unpicked `ask` sets `picked: false` and stops there — no edit, no reply, thread untouched — and appears in the final report under what was left for the user.

## 3. Reply shapes + the ship gate (Phase 3)

**Reply drafts.** One per review-comment item, addressed to the reviewer, in plain English:

| Verdict | Shape |
|---|---|
| `fix` | "Addressed in `<short-sha>` — `<what changed>` (`<path:line>`)." |
| `decline` | The reason from §2 stated as a position, with the evidence quoted: what the code does, why the change is not being made, and — for `too-large` / `out-of-scope` — where the work belongs instead. |
| `answer-only` | The answer, grounded in the code, cited by `path:line`. |

Never post a reply that asks the reviewer to check something you can check yourself — resolve it first and state the result.

**The ship gate.** One `AskQuestion`, fired after the chat render of the outcome:

```
header: "Ship"
question: "Fixed <N> comments; declined <M>. Commit and push to PR #<num>, and post the <R> replies?"
options:
  - "Commit, push, reply and resolve (Recommended)"  -> the whole chain
  - "Commit and push only"                           -> no reply, no resolve
  - "Commit only"                                    -> no push (and so no reply: an unpushed fix is not visible)
  - "Leave it in the working tree"                   -> nothing; the diff is the deliverable
```

When nothing was applied — every item declined, answered, or left unpicked — there is no commit to make and the gate narrows to the replies alone: "Post the <R> replies to PR #<num>?" / "Post nothing". A run with no fixes and no replies skips the gate and goes straight to the report; there is nothing to authorize.

Annotate the question text with anything the user needs to weigh: a test failure that survived the retry, a pre-existing failure the run did not cause, a fix whose files did not make it into the commit. The gate's answer governs every outward action in the chain — a later step never carries out something it stopped short of.

## 4. Final report (Phase 3)

Printed to chat at the end of every run, including one that shipped nothing:

```markdown
### /geniro:resolve — PR #<num>

**Fixed (<N>)** — <one line each: comment author, what changed, path>
**Declined (<M>)** — <one line each: comment author, reason, the evidence in a clause>
**Answered (<A>)** — <one line each: comment author, the `answer-only` reply, path:line>
**Left for you (<K>)** — <the `ask` items not picked, and any item whose fix did not land>
**Tests** — <verdict, or "no test command documented in the project's instructions">
**On the PR** — <what was pushed, how many replies posted, how many threads resolved, and anything skipped after a failed write>
```

Every item in the inventory appears in exactly one of the first four sections — a run that silently drops an item is a run whose triage the user cannot check.
