# /geniro:resolve — Phase 2: Decide

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/resolve/SKILL.md`. Read on entry to Phase 2, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table and the Definition of done — this file carries the Steps.

## Contents

- The Steps
- What the decision gate is for

---

state.md `phase: decide`. Work file by file: the inventory is grouped by path, so one read of a file serves every item citing it.

1. **Read the code each item cites.** For each file group: the cited slice, the callers that reach it, and the sibling tests. That read is what tells you whether the comment describes something real, whether the fix is behavior-preserving, and whether a test already pins the behavior the comment wants changed. A comment citing a path that no longer exists is stale — `decline`, reason `wrong-claim`.

2. **Reproduce what claims to be broken.** For a bug claim, construct the failing case or name the exact trigger path. For a failing check, run its command locally when the check name and output make it derivable. A claim that does not reproduce is evidence for `decline`, not permission to skip the item — record what you ran.

3. **Assign a verdict.** One of `fix` / `ask` / `answer-only` / `decline`, per the rubric in `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §2. The filter is part of this step, not a pass after it: an ask that is real but over-engineered, outside this PR's scope, or would regress working behavior lands on `decline` with that reason recorded. A fix that changes something a caller could depend on lands on `ask` — the SKILL.md §Loop invariants #2 line between behavior-preserving and behavior-changing is the test, and an item you cannot place is `ask`.

4. **Verify what publication or doubt demands.** Spawn a fresh `finding-verifier-agent` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, OMIT `model=`) for every `decline` and every contested `fix` — invariant #3. Items citing the same file share one spawn (cluster cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4, one verdict block each); a solo item spawns singly; fire the whole batch in ONE assistant response. The verifier contract is that file's §2, treating the comment as the finding. Then aggregate:
   - A `decline` the verifier **refutes** (the comment is right after all) re-opens as `fix` or `ask`. Its push-back is never posted.
   - A contested `fix` the verifier **refutes** (not real, not reachable, already fixed) demotes to `decline` with the verifier's evidence as the push-back.
   - A `clarified` verdict changes the fix's shape, not the verdict — apply the correction the verifier names.

5. **Render the decision set, then fire ONE gate.** Write a self-contained chat message first — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — covering all three groups: what you will fix without asking, what you are declining and the evidence for each, and each item that needs the user's call with its behavior consequence spelled out. Then fire ONE multi-select `AskUserQuestion` over the `ask` items ("Pick the changes to apply"), per that file's §Multi-select pick loop. Unpicked items are applied to nothing and posted to nothing: they stay on the PR untouched and appear in the final report as left for the user. Persist every pick to `approvals[]` (category `comment_decision`). Full mechanics — the option shape, what each group's render must carry, the >4 cap-extension: `resolve-reference.md` §2.5.

6. **An ambiguous item gets its own gate.** An item with two plausible readings is not an `ask` — you do not yet know what you would be applying. Render it on its own and fire a single-item gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate: the options are the item's competing readings plus an **"Explain further"** aid and a **"Challenge this comment"** aid. Challenge spawns one fresh `finding-verifier-agent` primed with the user's objection; a `refuted` result reclassifies the item to `decline` and drops its gate. The answer turns the item into a `fix` (apply that reading) or a `decline`. A `decline` reached any other way through this gate has not yet passed a verifier — spawn one fresh `finding-verifier-agent` (invariant #3) before step 7, the same as every other `decline` in this phase; skip only when the Challenge path already produced the verifier's `refuted` result for this item.

7. **Persist and transition.** Write every verdict, reason, verifier outcome and pick to state.md, then `phase: fix`. Leaving it at `decide` makes a compaction-resume re-run the verifier batch, the most expensive step in the run.

---

## What the decision gate is for

The gate exists because this skill edits code. A reviewer's comment is a request, not an approval: the user is the one who decides whether their PR's behavior changes, and they are deciding it here, once, over the whole set — not comment by comment while the fixes are already landing.

So the render carries consequence, not classification. "Switch the retry default from 3 to 5" tells the user nothing they can act on; "callers that relied on failing fast after 3 attempts would now wait through 5 — the batch importer is the one caller doing that" is the same fact in the form the decision needs. The declined group earns its place in the same message for the same reason: a push-back posted to a reviewer is something the user is answerable for, and this is where they see it before it goes out.
