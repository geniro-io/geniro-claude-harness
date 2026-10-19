# /geniro:resolve — Phase 2: Decide

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/resolve/SKILL.md`. Read on entry to Phase 2, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table and the Definition of done — this file carries the Steps.

## Contents

- The Steps
- What the decision gate is for

---

state.md `phase: decide`.

**Step 0 — Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: resolve`, `LOAD_TIER: pipeline`, `MODE: refresh`; echo per the helper's contract. Compaction may have dropped the rules, and this phase assigns the verdicts they govern (e.g. "never decline a security bot's comment").

Work file by file: the inventory is grouped by path, so one read of a file serves every item citing it.

1. **Read the code each item cites.** For each file group: the cited slice, the callers that reach it, and the sibling tests. That read tells you whether the comment is real, whether the fix is behavior-preserving, and whether a test already pins the behavior it wants changed. For an item with `is_outdated: true`, judge whether an earlier commit already on the PR head addressed the comment's concern at that path or line: if it did, verdict `fix` and record that commit in `addressed_by` — the reply names it, and Phase 3 resolves the thread on that evidence rather than the pushed-diff check; if it did not, triage normally below. A comment citing a path this PR removed outright, with nothing to weigh, is stale — `decline`, reason `wrong-claim`.

2. **Reproduce what claims to be broken.** For a bug claim, construct the failing case or name the exact trigger path. For a failing check, run its command locally when derivable. A claim that does not reproduce is evidence for `decline`, not permission to skip the item — record what you ran.

3. **Assign a verdict.** One of `fix` / `ask` / `answer-only` / `decline`, per the rubric in `${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §2. The filter is part of this step, not a pass after it: an ask that is over-engineered, outside this PR's scope, or would regress working behavior lands on `decline` with that reason recorded. A fix that changes something a caller could depend on lands on `ask` — the SKILL.md §Loop invariants #2 line between behavior-preserving and behavior-changing is the test, and an item you cannot place is `ask`.

4. **Verify what publication or doubt demands.** Spawn a fresh `finding-verifier-agent` (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md`, **session**) for every `decline` and every contested `fix` — invariant #3. Items that share code share one spawn (cluster rule and cap per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4, one verdict block each); fire the whole batch in ONE assistant response. The verifier contract is that file's §2, treating the comment as the finding; write its shared intent file from the PR body and the commit subjects (plus any plan section the items touch), so a verdict quoting documented intent can fire the `intent-check` → `ask` branch below. Verifiers per contested call: the Verifier fan-out row of SKILL.md §Budgets / quality gates for the run's tier, aggregated by majority. Then aggregate:
   - A `decline` the verifier **refutes** (the comment is right after all) re-opens as `fix` or `ask`. Its push-back is never posted.
   - A contested `fix` the verifier **refutes** (not real, not reachable, already fixed) demotes to `decline` with the verifier's evidence as the push-back.
   - A `clarified` verdict changes the fix's shape, not the verdict — apply the correction the verifier names. A verdict (`clarified` or `confirmed`) with `recommended_action: intent-check` quoting documented intent (PR body, commit message, or plan) on a contested `fix` is not a correction: the fix would reverse behavior the author declared deliberate, so the item becomes an `ask` carrying the quote.

5. **Render the decision set, then fire ONE gate.** Write a self-contained chat message first — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering — covering all three groups: what you will fix without asking, what you are declining and the evidence for each, and each item that needs the user's call with its behavior consequence spelled out. Then fire ONE multi-select `AskUserQuestion` over the `ask` items ("Pick the changes to apply"), per that file's §Multi-select pick loop. Unpicked items stay on the PR untouched and appear in the final report as left for the user. Persist every pick to `approvals[]` (category `comment_decision`). Full mechanics: `resolve-reference.md` §2.5.

6. **An ambiguous item gets its own gate.** An item with two plausible readings is not an `ask` — you do not yet know what you would be applying. Render it on its own and fire a single-item gate per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` §Single-finding gate: the options are the item's competing readings plus an **"Explain further"** aid and a **"Challenge this comment"** aid. Challenge spawns one fresh `finding-verifier-agent` primed with the user's objection; a `refuted` result reclassifies the item to `decline` and drops its gate. A `clarified` result is written back: the item's body takes the verifier's corrected reading, and its `recommended_action` re-routes it — `fix-now` / `testable` make it a `fix` and drop the gate; `product-decision` / `intent-check` re-fire the gate on the corrected body (carrying an `intent-check`'s quote). The answer turns the item into a `fix` (apply that reading) or a `decline`. Any other `decline` from this gate gets a fresh `finding-verifier-agent` (invariant #3) before step 7, as every `decline` does; skip only when Challenge already produced the `refuted` result.

7. **Persist and transition.** Write every verdict, reason, verifier outcome and pick to state.md, then `phase: fix`. Leaving it at `decide` makes a compaction-resume re-run the verifier batch, the run's most expensive step.

---

## What the decision gate is for

The gate exists because this skill edits code. A reviewer's comment is a request, not an approval: the user decides whether their PR's behavior changes, here, once, over the whole set — not comment by comment while fixes are already landing.

So the render carries consequence, not classification. "Switch the retry default from 3 to 5" tells the user nothing they can act on; "callers that relied on failing fast after 3 attempts would now wait through 5 — the batch importer is the one caller doing that" is the same fact in the form the decision needs. The declined group sits in the same message because a push-back posted to a reviewer is something the user answers for, and this is where they see it before it goes out.
