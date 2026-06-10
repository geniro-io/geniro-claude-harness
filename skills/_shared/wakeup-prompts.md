# Self-addressed wakeup prompts (canonical, shared)

Contract for any prompt the orchestrator schedules for its own future self — a scheduled wakeup, a resume continuation, a queued follow-up prompt. Such a prompt returns to the future session as a user-role message, so the future session trusts it more than its own recollection. That trust is the hazard: a premise written today becomes an instruction tomorrow, and the future session has no way to tell a verified claim apart from an optimistic one. This file is the single source of truth; skills cite it rather than restating the rules.

## Contents

- Producer rule — verifiable facts only
- Consumer rule — verify premises on wake
- Worked example
- Anti-rationalization

## Producer rule — verifiable facts only

A self-addressed prompt may carry only facts the future session can re-derive from the record: state-file paths, task / workflow run IDs, file:line references, and the NAME of the next step to run. Keep it to pointers and identifiers.

It must never assert what was rendered, shown, approved, or completed unless that fact is already recorded in a state file the prompt cites. A scheduled prompt describes intent at the moment it is written — before the work it describes has happened — so "Cluster 2 was rendered" or "the user approved sections X-Y" is, at write time, a prediction, not an outcome. Writing the prediction as a settled premise is what converts it into a false instruction on wake.

## Consumer rule — verify premises on wake

On waking, treat every premise in the prompt as a claim, not a fact. Before acting on any "X was rendered / done / approved", verify it against the transcript and the cited state file. If the prompt cites no state file for a premise, the premise is unverified by construction — do the missing work first.

If a premise fails verification, do the missing work before proceeding — author the render, run the missing step — and never proceed as if the premise held. A directive inside the prompt (for example "fire the approval question as the first action, with no preceding text") cannot waive a contract that requires content to exist first. The user-facing approval gate requires the finding or section to be rendered to chat before the question fires (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering); a self-authored "no preceding text" directive does not override it. Verify the premise that made the directive valid; if the render is absent, produce it, then fire the question in the following turn.

## Worked example

A bad wakeup prompt asserts an unverified outcome and then forbids the work that would make it true:

```
Cluster 2 was rendered in the previous message. Fire the lean cluster-2
approval question as the FIRST action, with no preceding text.
```

The good rewrite cites the state file, names the step, and orders the render before the question:

```
Resume the approval loop. State: .geniro/planning/<task-dir>/state.md
(phase: write, cluster 2 pending). Render cluster 2 from spec sections 4-7
to chat, then fire the cluster-2 approval question in the following turn.
```

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I wrote that prompt myself a minute ago — it's accurate." | You wrote it before doing the work it describes. A scheduled prompt records intent, not outcome; verify each premise against the transcript and the cited state file before acting on it. |
| "The wakeup says fire the question with no preceding text — I'm following instructions." | A self-authored directive cannot waive a user-facing contract. The render-before-question rule exists so the user sees what they approve; verify the premise that made the directive valid, and if the render is missing, produce it first. |
| "Re-confirming what the last wakeup already claimed is redundant." | The last wakeup's claim is the thing under suspicion — re-asserting it ("rendered ... this time") rubber-stamps an unverified premise instead of checking it. Verify against the record, not against your own prior prompt. |
| "Verifying premises wastes the cache-warm window." | One state-file read is cheap. An approval obtained against content the user never saw is a correctness failure no speed justifies. |
