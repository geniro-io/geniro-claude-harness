# Root-Cause Gate

Canonical AskUserQuestion gate that fires when a finding or proposed change is classified `[SYMPTOM]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`. Replaces the older "just fix it" implicit handling — auto-patching a symptom without confirming the underlying cause is the same class of failure as auto-dropping MEDIUMs (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`): a real bug ships, no audit trail, and the visible defect re-emerges later via a different surface.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the gate logic.

## When this fires

Used by:
- `/geniro:implement` Phase 2 — when the architect-agent's design output contains `Root-cause classification: SYMPTOM-PATCH` (or `MIXED`) for any design unit
- `/geniro:review` Phase 5 disposition — when any finding carrying `Cause: [SYMPTOM]` survives the relevance-filter (i.e., wasn't dropped at Phase 4c) and is about to enter the fix-loop pool
- `/geniro:follow-up` Phase 1 Step 2.5 — Root vs Symptom assessment for the Small and Medium lanes (Trivial lane bypasses the gate; the Trivial scope is too narrow for symptom-vs-root to apply meaningfully)

Skip silently when zero `[SYMPTOM]` (or `[MIXED]`) classifications are present after the upstream filter step, or when the upstream skill is in a lane that bypasses architect/reviewer entirely (Fast Lane in `/geniro:implement`, Trivial in `/geniro:follow-up`).

## Always-WAIT contract

This gate is **Always-WAIT** in every mode and lane (Auto, Fast, Light included, except where the lane bypasses architect/reviewer entirely as noted above). Auto-handling SYMPTOM findings ("just patch it, the visible defect goes away") is unsafe — the user has context the orchestrator does not:
- The deeper bug may be intentionally deferred for v2 (the symptom-patch IS the right call right now while the root cause is being addressed in a separate work stream).
- Conversely, the orchestrator's `[SYMPTOM]` classification may be wrong, and the user knows the true root cause sits elsewhere — in which case a "just patch it" auto-handling buries the real bug.
- Or the user wants to halt and run `/geniro:debug` first to confirm causation before any fix lands.

The orchestrator cannot distinguish those three cases from the finding alone. Always-WAIT routes the call to the only entity who can.

Empty `AskUserQuestion` answer = upstream Claude Code bug; fall back to plain text and re-ask. Never auto-default.

## Required AUQ shape (single-select)

- **`header`**: `"Root cause"`.
- **`question`**: multi-line markdown — render the classification, the finding/design title, the location, the symptom, the suspected root cause, and one line of why-this-matters so the user can decide without drilling into the full report:

  ```
  Classification: [SYMPTOM] — proposed change patches a downstream effect, not the underlying cause.

  Finding/design: <title>
  Where: <file:line or design-section>
  Symptom: <one-line>
  Suspected root cause: <one-line>
  Why this matters: <one-line>

  How do you want to handle this?
  ```

  Pull the `<title>` / `<file:line or design-section>` / `<symptom>` / `<suspected root cause>` / `<why this matters>` values from the upstream artifact's persisted body fields:
  - For `/geniro:review` and `/geniro:follow-up`: from each finding's `File:` / finding-title / `Why this matters:` plus the new `Cause:` and `Suspected root cause:` sub-fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` § Persistence schema.
  - For `/geniro:implement` Phase 2: from the architect-agent's design unit fields (design title / target file / `Symptom:` / `Suspected root cause:` / `Why this matters:`).

  When more than one `[SYMPTOM]` finding/design fires the gate in the same skill phase, fire the AUQ once per finding (sequentially) — the user's choice on one symptom does not transfer to another. The single-select shape stays the same per call; do NOT batch into a multi-select.

- **`options[]`** (3 single-select):
  - `label`: `"Confirmed root cause (proceed)"` — `description`: `"I have already verified the underlying cause; this fix is the correct surface-level implementation. Proceed."`
  - `label`: `"Symptom — escalate to /geniro:debug"` — `description`: `"Stop, run scientific-method debug to confirm the root cause before any fix."` (Recommended when classification is [SYMPTOM] and confidence is low — the orchestrator may surface a Recommended marker in the option text per `AskUserQuestion`'s convention.)
  - `label`: `"Mixed — annotate and proceed"` — `description`: `"I acknowledge this is a symptom patch; ship it with a tracked tech-debt note. Use sparingly."`

## Result handling

After the gate resolves:
- **"Confirmed root cause (proceed)"** → re-tag the finding/design as `[ROOT-CAUSE]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` (overwrite the `Cause:` field in `<task-dir>/review-feedback.md` and `.geniro/state/<skill>/state-<slug>.md`), then proceed in the upstream skill — the finding/design enters the normal fix-loop / implementation pool.
- **"Symptom — escalate to /geniro:debug"** → halt the current skill at the gate. Surface a hand-off message: `Run /geniro:debug "<finding/design title>" to confirm the root cause via the scientific-method workflow, then re-invoke the original skill once the debug findings persist to <PRIMARY_ROOT>/.geniro/state/debug/findings-state.md.` Do NOT auto-invoke `/geniro:debug` — surface the suggestion only; the user runs the slash command themselves (matches the escalation convention in `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` Step 6.5b). The current skill exits cleanly; its state file remains so the user can resume after debug.
- **"Mixed — annotate and proceed"** → re-tag the finding/design as `[SYMPTOM-ACK]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`, append a row to a `## Acknowledged tech debt` section in the skill's Ship summary capturing `<title>` + `<file:line>` + `<symptom>` + `<suspected root cause>` so the user has a documented backlog. Then proceed in the upstream skill.

## Why this exists

Symptom-matching is correlation, not causation — the same principle the `/geniro:debug` Evidence Standard enforces ("the hypothesis matches the symptom" is rejected as confirmation; only reproduction with a captured artifact qualifies — see `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard). Extending that discipline beyond `/geniro:debug` is necessary because the reviewer-agent and architect-agent classify findings/designs by structural signals (does the change touch the surface where the defect is observed, or does it touch the layer where causation originates?) but cannot judge user intent. Two indistinguishable `[SYMPTOM]` classifications can mean radically different things:

- intentional deferral (root cause is being addressed in a separate work stream; patch the surface for now)
- accidental shortcut (author didn't realize the real bug sits elsewhere; patch will mask the defect until it re-emerges through a different surface)

Always-WAIT routes the call to the only entity that holds that intent. The cost is one AUQ call per `[SYMPTOM]` finding that survives the relevance-filter — matches the `medium-gate.md` cost profile (skipped silently when zero `[SYMPTOM]` classifications exist).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The symptom matches the bug, that's good enough" | Symptom-matching is correlation, not causation. Only confirmed cause (verified by code-trace, repro test, or hypothesis-confirmation artifact per `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard) justifies a fix. The reviewer/architect's `[SYMPTOM]` classification means causation is unconfirmed — fire the gate. |
| "I'll just pick one of the two valid fixes" | If the architect classifies a design unit as `[MIXED]` (one path treats the symptom, another addresses the cause) and the user has not been asked, picking silently ships a product decision the user did not authorize. Symmetric with the multi-path fix gate in `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` Step 5 and the `[PRODUCT-DECISION]` gate in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Fire the AUQ. |
| "The classification looks wrong — it's clearly a root-cause fix, I'll skip the gate" | Skipping the gate based on your own re-classification is the same anti-pattern as auto-dropping a MEDIUM because "it didn't seem real" (see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` § Why this exists). The agent's classification is the gate trigger; if it's wrong, the user picks "Confirmed root cause (proceed)" and the re-tag happens at result-handling — the audit trail records the override. |
| "Only one [SYMPTOM] finding fired — the user will get annoyed by the question" | One AUQ call is the cost of preventing a real bug from shipping. The user is far more annoyed by a regression caused by an unconfirmed root cause than by a single decision prompt. |
| "I'll batch every [SYMPTOM] finding into one multi-select" | Each symptom has its own root cause, its own user context, and its own correct disposition. Batching forces the user to over-generalize ("escalate all" or "proceed all") and loses the per-finding decision the gate exists to capture. Fire one AUQ per finding sequentially. |
