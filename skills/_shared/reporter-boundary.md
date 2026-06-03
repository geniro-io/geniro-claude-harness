# Reporter Boundary — A Workflow Wrapper Does Not Relax The Contract

Canonical contract for Reporter-class skills: running under a dynamic `Workflow(...)`, ultracode, or any elevated-effort mode does NOT relax the skill's read-only contract. A workflow is an execution wrapper that parallelizes the subagent fan-out — it is not a contract override.

Consumers: `/geniro:review`, `/geniro:debug`, `/geniro:refactor`, `/geniro:investigate`.

## The three invariants that bind identically inside a Workflow run

### 1. Reporter boundary

A Reporter-class skill produces findings, not changes. Inside every workflow step the same boundary holds:

- No `Edit` / `Write` to production source.
- No `git add` / `git commit` / `git push`.
- No `gh pr create` / `gh pr merge`.

The skill's documented on-disk deliverable (handoff file, reproduction test, or working-tree diff) and its sanctioned side-effects (for example, `/geniro:review` posting a PENDING PR review) are the ONLY outputs. Route fixes to `/geniro:implement` — never apply them in-skill.

### 2. Canonical action gate

The skill's documented `AskUserQuestion` options are an allowlist. Do not substitute an ad-hoc question — no "apply the fix now", no "add the test now", no "what next?". If the user asks mid-run for a fix to be applied, surface that this exceeds the skill's reporter scope and offer to hand off to `/geniro:implement`. Do not silently become a fixer.

Routing findings to `/geniro:implement` hands off work to fix, not authority to ship. The action-gate pick ("/geniro:implement findings") authorizes /geniro:implement to apply the fixes; /geniro:implement still runs its own ship gate before any commit or push. A Reporter's action-gate selection never pre-authorizes the downstream push — an "apply the findings" approval is not ship consent.

### 3. State writes via atomic_state_write

Every `.geniro/` state and handoff write goes through `atomic_state_write` (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md`), never a raw `Edit` / `Write`, even inside a workflow step. Raw writes trip the `enforce-state-helper` hook and lose atomicity on a mid-crash.

### 4. Verify what's verifiable; surface only genuine decisions

Before a reporter surfaces a "confirm X" / "verify Y" question — to the user OR inside a posted finding — it checks X / Y itself against the evidence it can reach: the diff, the code, git history, the test suite. A finding states a verified fact; it must not delegate to the reader a check the reporter can run. "Confirm both migrations ship in the same PR" is `git diff --name-only`; "verify this symbol has no other callers" is a grep — resolve it and state the result. Only a genuinely unverifiable residue (production deploy history, business intent, a product trade-off) stays as a human-facing note, narrowed to just that residue.

A reporter does not apply fixes, and it does not record "how should X be fixed?" as a question — a finding carries its own recommended action, and the fixer (`/geniro:implement`) decides fix specifics when it fixes. The one decision a reporter always surfaces is the disposition: what to do with the findings (post to the PR / hand to `/geniro:implement` / save / discard), at its action gate. The test: "if I can determine the answer myself, I verify it; if it's a genuine judgment call, I ask; if it's a fix detail I won't act on, I leave it to the fixer."

## Why this binds

Wrapping a skill in a workflow makes the model treat the workflow as the authority and the skill body as advisory — the contract then evaporates. The skill body is the authority; the workflow only changes how its subagent fan-out runs. The three invariants above bind regardless of the wrapper.

## Anti-rationalization

| Rationalization | Why it is wrong |
|---|---|
| "Ultracode is on, so I can apply the fix directly to save a round." | The effort mode changes investigation depth and parallelism, not the skill's output contract. Route the fix to `/geniro:implement`. |
| "I'm running this as a Workflow, so the skill's no-push rule is just guidance." | The workflow parallelizes the fan-out, not the contract. The no-Edit / no-commit / no-push boundary binds inside every workflow step. |
| "The user asked me to fix it mid-review, so the gate doesn't apply." | Surface that fixing exceeds reporter scope and offer the `/geniro:implement` hand-off. Silently dropping into fix-mode is the documented failure this rule prevents. |
| "It's faster to write state with a direct Write inside the workflow." | `atomic_state_write` binds inside workflow steps too. Raw writes trip the `enforce-state-helper` hook and lose atomicity. |
| "This finding asks the author to confirm something (e.g. 'confirm both migrations ship together') — I'll post it as written." | If the claim is checkable — both migrations in this PR's diff, the caller exists, the test covers the path — check it and state the verified result. Posting a "confirm X" you could have resolved offloads your work onto the reader. Only the genuinely unverifiable residue (did it deploy to an environment independently?) stays as a question. |
| "The build is red / this finding needs a fix — I'll ask the user how to resolve it." | A reporter doesn't decide fixes. Investigate the verifiable part (why it's red) and report it; leave the fix decision to `/geniro:implement`. The only thing you ask is the disposition (post / hand off / save), at the action gate. |
