# Reporter boundary — a workflow wrapper does not relax the contract

Canonical contract for Reporter-class skills: running under a dynamic `Workflow(...)`, ultracode, or any elevated-effort mode does NOT relax the skill's read-only contract. A workflow is an execution wrapper that parallelizes the subagent fan-out — it is not a contract override.

Consumers: `/geniro:review`, `/geniro:debug`, `/geniro:refactor`, `/geniro:investigate`, `/geniro:resolve`.

## Contents

- The four invariants that bind identically inside a Workflow run
  - 1. Reporter boundary — findings, not changes (incl. the authored-test push carve-out)
  - 2. Canonical action gate — the documented options are an allowlist
  - 3. State writes via `atomic_state_write`
  - 4. Verify what's verifiable; surface only genuine decisions
- Why this binds — the wrapper-as-authority failure mode
- Anti-rationalization

## The four invariants that bind identically inside a Workflow run

### 1. Reporter boundary

A Reporter-class skill produces findings, not changes. Inside every workflow step the same boundary holds:

- No `Edit` / `Write` to production source.
- No push of fixes or production-source — no `git add` / `git commit` / `git push` of any production or fix change.
- No `gh pr create` / `gh pr merge`.

The skill's documented on-disk deliverable (handoff file, reproduction test, or working-tree diff) and its sanctioned side-effects (for example, `/geniro:review` posting a PENDING PR review) are the ONLY outputs. That review side-effect is bounded: `/geniro:review` posts a PENDING draft only, after the explicit action-gate pick, and never publishes/submits the review it creates (never the `reviews/<id>/events` endpoint) — submitting fires notifications to the PR author and is the user's own github.com action, across all rounds. The action gate always fires before posting, and chat text ("submit it yourself") never substitutes for it. Route fixes to `/geniro:implement` — never apply them in-skill.

**Carve-out — authored-test push (`/geniro:review` only).** `/geniro:review` may commit + push ONLY the failing tests it authored to the reviewed branch, because authored tests are evidence, not a fix. The carve-out is triple-scoped: only files listed in the handoff `## Authored Tests`, only tests authored by `adversarial-tester-agent`, and only after the explicit "Commit + push" pick in the Phase 6 Failing-tests gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6). It applies to `/geniro:review` ONLY — `/geniro:debug`, `/geniro:refactor`, `/geniro:investigate`, and `/geniro:resolve` have no failing-tests gate and no authored-test push, so they read this carve-out as inapplicable, not as a general push license. A fix never rides along with the tests on that push.

### 2. Canonical action gate

The skill's documented `AskUserQuestion` options are an allowlist. Do not substitute an ad-hoc question — no "apply the fix now", no "add the test now", no "what next?". **State the boundary as a routing choice and name the route in the same message.** A reporter's read-only contract is a scope boundary the user crosses by routing the work onward, not a limit on what the agent can do — so describe it that way wherever it surfaces: mid-run when the user asks for a fix, and unprompted in the report. "These fixes are ready to apply — `/geniro:implement <handoff-path>` applies them" leaves the user with a next move; "I am read-only and cannot apply them" reads as final, and the user stops asking for as long as they believe it. Offering the route is what keeps the boundary intact: the reporter routes the work, it never becomes the fixer.

Routing findings to `/geniro:implement` hands off work to fix, not authority to ship. The action-gate pick ("/geniro:implement findings") authorizes /geniro:implement to apply the fixes; /geniro:implement still runs its own ship gate before any commit or push. A Reporter's action-gate selection never pre-authorizes the downstream push — an "apply the findings" approval is not ship consent. The general rule this follows is `${CLAUDE_PLUGIN_ROOT}/skills/_shared/approval-scope.md`.

### 3. State writes via atomic_state_write

Every `.geniro/` state and handoff write goes through `atomic_state_write` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`), never a raw `Edit` / `Write`, even inside a workflow step. Raw writes trip the `enforce-state-helper` hook and lose atomicity on a mid-crash.

### 4. Verify what's verifiable; surface only genuine decisions

Before a reporter surfaces a "confirm X" / "verify Y" question — to the user OR inside a posted finding — it checks X / Y itself against the evidence it can reach: the diff, the code, git history, the test suite. A finding states a verified fact; it must not delegate to the reader a check the reporter can run. "Confirm both migrations ship in the same PR" is `git diff --name-only`; "verify this symbol has no other callers" is a grep — resolve it and state the result. Only a genuinely unverifiable residue (production deploy history, business intent, a product trade-off) stays as a human-facing note, narrowed to just that residue.

A residue's audience is the user running the reporter, not an outward reader. A data-classification call, a legal/DPA question, or a team-process decision is something the outward reader (a PR author) cannot action — surface it to the user for a decision and let the user control whether it reaches the outward surface, rather than posting "worth confirming X" to the PR where it re-projects an unactionable judgment call onto the author. A reporter that posts findings (for example to a PR) gives the user a way to keep such a residue off that surface while still recording the decision.

A reporter does not apply fixes, and it does not record "how should X be fixed?" as a question — a finding carries its own recommended action, and the fixer (`/geniro:implement`) decides fix specifics when it fixes. The one decision a reporter always surfaces is the disposition: what to do with the findings (post to the PR / hand to `/geniro:implement` / save / discard), at its action gate. The test: "if I can determine the answer myself, I verify it; if it's a genuine judgment call, I ask; if it's a fix detail I won't act on, I leave it to the fixer."

## Why this binds

Wrapping a skill in a workflow makes the model treat the workflow as the authority and the skill body as advisory — the contract then evaporates. The skill body is the authority; the workflow only changes how its subagent fan-out runs. The four invariants above bind regardless of the wrapper.

## Anti-rationalization

| Rationalization | Why it is wrong |
|---|---|
| "Ultracode is on, so I can apply the fix directly to save a round." | The effort mode changes investigation depth and parallelism, not the skill's output contract. Route the fix to `/geniro:implement`. |
| "I'm running this as a Workflow, so the skill's no-push rule is just guidance." | The workflow parallelizes the fan-out, not the contract. The no-Edit / no-commit / no-push boundary binds inside every workflow step. |
| "The user asked me to fix it mid-review, so the gate doesn't apply." | Surface that fixing exceeds reporter scope and offer the `/geniro:implement` handoff. Silently dropping into fix-mode is the documented failure this rule prevents. |
| "It's faster to write state with a direct Write inside the workflow." | `atomic_state_write` binds inside workflow steps too. Raw writes trip the `enforce-state-helper` hook and lose atomicity. |
| "This finding asks the author to confirm something (e.g. 'confirm both migrations ship together') — I'll post it as written." | If the claim is checkable — both migrations in this PR's diff, the caller exists, the test covers the path — check it and state the verified result. Posting a "confirm X" you could have resolved offloads your work onto the reader. Only the genuinely unverifiable residue (did it deploy to an environment independently?) stays as a question. |
| "The finding is genuinely unverifiable (a DPA / data-classification question), so the residue rule lets me keep it as a note — I'll put that note in the PR comment." | The rule permits the residue as a note, but its audience is the user running the reporter, not the PR author who cannot action a data-classification call. Surface it to the user and let them decide whether it reaches the PR. Posting "worth confirming X" to the PR is the re-projection this rule prevents. |
| "The build is red / this finding needs a fix — I'll ask the user how to resolve it." | A reporter doesn't decide fixes. Investigate the verifiable part (why it's red) and report it; leave the fix decision to `/geniro:implement`. The only thing you ask is the disposition (post / hand off / save), at the action gate. |
| "The tests are authored and ready — I'll push the fix in the same commit while I'm at it." | The authored-test push carve-out (§1) is tests-only and `/geniro:review`-only. A fix never ships from a reporter — route it to `/geniro:implement`. Bundling a fix into the test-push commit is exactly the boundary breach the triple-scope prevents. |
| "The user told me in chat to push the authored tests — that's the approval." | Chat text is never a gate. The authored-test push still routes through the explicit "Commit + push" pick in the Phase 6 Failing-tests gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §6) — surface the gate and let the pick authorize the push. |
| "This round's findings should reach the author, so I'll submit the pending review." | Submitting fires notifications to the PR author and is the user's own github.com action — post the draft after the action-gate pick, then tell the user to Submit (§1 has the endpoint-level boundary and why it holds across all rounds). |
