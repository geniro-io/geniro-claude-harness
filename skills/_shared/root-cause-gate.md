# Root-Cause Gate

Canonical AskUserQuestion gate that fires when a finding or proposed change is classified `[SYMPTOM]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`. Auto-patching a symptom without confirming the underlying cause silently handles a defect the user never confirmed: a real bug ships, no audit trail, and the visible defect re-emerges later via a different surface.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the gate logic.

## When this fires

Used by:
- `/geniro:plan` — when the spec/plan authoring surfaces a proposed change classified `Root-cause classification: SYMPTOM-PATCH` (or `MIXED`) for any design unit. /geniro:plan's orchestrator-side spec-authoring prompts apply the classification; the gate fires upstream of `/geniro:implement`.
- `/geniro:review` Phase 5 disposition — when any finding carrying `Cause: [SYMPTOM]` survives Phase 3 dedup and Phase 4 judge (i.e., wasn't dropped earlier) and is about to be persisted to the handoff for a downstream fixer (/geniro:review is a Reporter and applies no fixes; the gate records the disposition the handoff carries forward)

Skip silently when zero `[SYMPTOM]` (or `MIXED`) classifications are present after the upstream filter step.

## Always-WAIT contract

This gate is **Always-WAIT** in every mode and lane (Auto, Fast, Light included). Auto-handling SYMPTOM findings ("just patch it, the visible defect goes away") is unsafe — the user has context the orchestrator does not:
- The deeper bug may be intentionally deferred for v2 (the symptom-patch IS the right call right now while the root cause is being addressed in a separate work stream).
- Conversely, the orchestrator's `[SYMPTOM]` classification may be wrong, and the user knows the true root cause sits elsewhere — in which case a "just patch it" auto-handling buries the real bug.
- Or the user wants to halt and run `/geniro:debug` first to confirm causation before any fix lands.

The orchestrator cannot distinguish those three cases from the finding alone. Always-WAIT routes the call to the only entity who can.

Empty `AskUserQuestion` answer = upstream Claude Code bug; fall back to plain text and re-ask. Never auto-default.

## Required AUQ shape (single-select)

The gate follows the two-step shape in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering: render the classification to a chat message first, then fire a lean question.

**Chat render (first).** A self-contained block in the visual language (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language):

- The progress tracker — only when ≥2 symptom-classified findings/designs are queued in the same skill phase: `✔ Decision 1 — <short tag> · ● Decision 2 of 3 — <short tag> · ○ Decision 3`.
- `### 🧭 Decision needed: <plain-English title>` — the finding/design title in plain words.
- `**In one sentence:** <what this decision settles — whether to ship the surface-level patch as-is, or confirm the underlying cause first>`
- A conversational digest: what the proposed change does, and why it is classified as patching a downstream effect rather than the underlying cause — name the file / behavior in words.
- `**Why it matters:** <one-line concrete impact>` (evidence: `<file:line or design-section>`)
- The cause→effect flow visual per per-finding-question.md § Finding-type visual map (Debug root cause row): `<suspected root cause at path:line> ──▸ <intermediate> ──▸ <observed symptom>`.
- **Options:** the three options below, each with its one-line consequence.

Pull the `<title>` / `<file:line or design-section>` / `<symptom>` / `<suspected root cause>` / `<why this matters>` values from the upstream artifact's persisted body fields:
- For `/geniro:review`: from each finding's `File:` / finding-title / `Why this matters:` plus the `Cause:` and `Suspected root cause:` sub-fields per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` § Persistence schema.
- For `/geniro:plan`: from /plan-emitted design unit fields in spec.md (design title / target file / `Symptom:` / `Suspected root cause:` / `Why this matters:`).

When more than one `[SYMPTOM]` finding/design fires the gate in the same skill phase, fire the AUQ once per finding (sequentially) — the user's choice on one symptom does not transfer to another. The single-select shape stays the same per call; do NOT batch into a multi-select. Each finding's chat block renders fresh before its own question.

**Lean `AskUserQuestion` (second):**

- **`header`**: `"Root cause"`.
- **`question`**:

 ```
 <plain-English title> — `<file:line or design-section>`

 Full explanation above. How do you want to handle this?
 ```

- **`options[]`** (3 single-select):
 - `label`: `"Confirmed root cause (proceed)"` — `description`: `"I have already verified the underlying cause; this fix is the correct surface-level implementation. Proceed."`
 - `label`: `"Symptom — escalate to /geniro:debug"` — `description`: `"Stop, run scientific-method debug to confirm the root cause before any fix."` (Recommended when classification is [SYMPTOM] and confidence is low — the orchestrator may surface a Recommended marker in the option text per `AskUserQuestion`'s convention.)
 - `label`: `"Mixed — annotate and proceed"` — `description`: `"I acknowledge this is a symptom patch; ship it with a tracked tech-debt note. Use sparingly."`

## Result handling

After the gate resolves:
- **"Confirmed root cause (proceed)"** → re-tag the finding/design as `[ROOT-CAUSE]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md` (set the `cause:` field in `<task-dir>/state.md` `## Accepted Findings` and `.geniro/state/<skill>/<slug>/state.md`), then proceed in the upstream skill — the finding/design enters the normal fix-loop / implementation pool.
- **"Symptom — escalate to /geniro:debug"** → halt the current skill at the gate. Surface a handoff message: `Run /geniro:debug "<finding/design title>" to confirm the root cause via the scientific-method workflow, then re-invoke the original skill once the debug findings persist to <PRIMARY_ROOT>/.geniro/state/handoff/from-debug-<branch>.md.` Do NOT auto-invoke `/geniro:debug` — surface the suggestion only; the user runs the slash command themselves (matches the escalation convention in `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`). The current skill exits cleanly; its state file remains so the user can resume after debug.
- **"Mixed — annotate and proceed"** → re-tag the finding/design as `[SYMPTOM-ACK]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`, append a row to a `## Acknowledged tech debt` section in the skill's Ship summary capturing `<title>` + `<file:line>` + `<symptom>` + `<suspected root cause>` so the user has a documented backlog. Then proceed in the upstream skill.

## Why this exists

Symptom-matching is correlation, not causation — the same principle the `/geniro:debug` Evidence Standard enforces ("the hypothesis matches the symptom" is rejected as confirmation; only reproduction with a captured artifact qualifies — see `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard). Extending that discipline beyond `/geniro:debug` is necessary because the reviewer-agent and /geniro:plan's orchestrator-side spec-authoring classify findings/designs by structural signals (does the change touch the surface where the defect is observed, or does it touch the layer where causation originates?) but cannot judge user intent. Two indistinguishable `[SYMPTOM]` classifications can mean radically different things:

- intentional deferral (root cause is being addressed in a separate work stream; patch the surface for now)
- accidental shortcut (author didn't realize the real bug sits elsewhere; patch will mask the defect until it re-emerges through a different surface)

Always-WAIT routes the call to the only entity that holds that intent. The cost is one AUQ call per `[SYMPTOM]` finding that survives the relevance-filter; the gate is skipped silently when zero symptom-classified findings exist.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The symptom matches the bug, that's good enough" | Symptom-matching is correlation, not causation. Only confirmed cause (verified by code-trace, repro test, or hypothesis-confirmation artifact per `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard) justifies a fix. The reviewer-agent's `[SYMPTOM]` classification means causation is unconfirmed — fire the gate. |
| "I'll just pick one of the two valid fixes" | If the reviewer-agent classifies a design unit as `MIXED` (one path treats the symptom, another addresses the cause) and the user has not been asked, picking silently ships a product decision the user did not authorize. Symmetric with the multi-path fix gate in /geniro:debug (§2.2) and the `[PRODUCT-DECISION]` gate in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md`. Fire the AUQ. |
| "The classification looks wrong — it's clearly a root-cause fix, I'll skip the gate" | Skipping the gate based on your own re-classification silently handles a finding the user never saw — the defect ships with no audit trail and re-emerges via another surface. The agent's classification is the gate trigger; if it's wrong, the user picks "Confirmed root cause (proceed)" and the re-tag happens at result-handling — the audit trail records the override. |
| "Only one [SYMPTOM] finding fired — the user will get annoyed by the question" | One AUQ call is the cost of preventing a real bug from shipping. The user is far more annoyed by a regression caused by an unconfirmed root cause than by a single decision prompt. |
| "I'll batch every [SYMPTOM] finding into one multi-select" | Each symptom has its own root cause, its own user context, and its own correct disposition. Batching forces the user to over-generalize ("escalate all" or "proceed all") and loses the per-finding decision the gate exists to capture. Fire one AUQ per finding sequentially. |
