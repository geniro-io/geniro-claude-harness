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

### 4. Fix-path questions are recorded, not asked

A reporter reports findings; it does not decide how they get fixed. So it must NOT surface a "how should X be resolved?" prompt to the user — that pushes a fix decision onto them that the reporter is not going to act on anyway. Such a question is recorded in the handoff as an `open_questions[]` entry with `gates_review: false` (schema: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2) so the downstream fixer (`/geniro:implement`) resolves it at the moment of fixing.

The ONLY questions a reporter surfaces are the ones that change what the reporter itself produces — its action gate (post / hand off / save / discard) and any scope question that genuinely changes which findings it posts (`gates_review: true`). Everything else is recorded for the consumer. The test: "if I ask this and the answer doesn't change what this skill does, I shouldn't be asking it."

## Why this binds

Wrapping a skill in a workflow makes the model treat the workflow as the authority and the skill body as advisory — the contract then evaporates. The skill body is the authority; the workflow only changes how its subagent fan-out runs. The three invariants above bind regardless of the wrapper.

## Anti-rationalization

| Rationalization | Why it is wrong |
|---|---|
| "Ultracode is on, so I can apply the fix directly to save a round." | The effort mode changes investigation depth and parallelism, not the skill's output contract. Route the fix to `/geniro:implement`. |
| "I'm running this as a Workflow, so the skill's no-push rule is just guidance." | The workflow parallelizes the fan-out, not the contract. The no-Edit / no-commit / no-push boundary binds inside every workflow step. |
| "The user asked me to fix it mid-review, so the gate doesn't apply." | Surface that fixing exceeds reporter scope and offer the `/geniro:implement` hand-off. Silently dropping into fix-mode is the documented failure this rule prevents. |
| "It's faster to write state with a direct Write inside the workflow." | `atomic_state_write` binds inside workflow steps too. Raw writes trip the `enforce-state-helper` hook and lose atomicity. |
| "The build is red / this finding needs a fix — I'll ask the user how to resolve it." | A reporter doesn't resolve fixes. If the answer wouldn't change what this skill produces, don't ask it — record it as an `open_questions[]` entry with `gates_review: false` for `/geniro:implement` to resolve when fixing. Surfacing it as a blocking prompt is the over-asking failure this rule prevents. |
| "I'll ask the user to triage every finding's scope before I finish." | Only ask scope questions that change which findings you post (`gates_review: true`). The user decides what to DO with the findings once, at the action gate — per-finding resolution prompts pre-empt that single decision. |
