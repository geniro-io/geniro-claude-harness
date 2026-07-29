# Gate rendering — shared visual language

Canonical visual language for every gate that renders rich, multi-part content to chat before a lean `AskUserQuestion`. This file defines the visual language those renders share; the two-step shape they sit inside and the per-gate field plumbing belong to the calling contract (§When this applies).

This file is the single source of truth for the visual language. Calling contracts cite specific sections; do NOT inline-paste the element definitions.

## Contents

- When this applies — which gates render in this language
- Visual rendering language — the five elements every gate message carries
- Plan-unit visual map — visual shape per spec section
- Turn-completion guard — the render is not a gate until the question has fired; render-before-question is mechanically enforced
- Explain-further option — the reading-aid option pattern
- Lean-question conventions — generic AskUserQuestion conventions for the lean question
- Why this exists — the rationale

## When this applies

Any gate that presents rich multi-part content before a decision:

- `/geniro:plan` approval gates — Phase 4 approaches, Phase 5 section clusters, Phase 8 final approval.
- Finding and product-decision gates under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — /geniro:review decision gates and PR-comment per-finding gates, /geniro:implement self-review decision resolution, /geniro:refactor product-decision escalation.
- Run-outcome and investigation gates — /geniro:review's report wrap-up (Action gate) and round-escalation, /geniro:debug's stall / fix-fail / open-question gates, /geniro:refactor's HIGH-risk step approval and blocked/regression escalations, /geniro:investigate's save-routing walk.
- Rule-improvement candidate gates — the improvement pass's per-candidate "write this project rule?" walk across /geniro:reflect, /geniro:plan, /geniro:debug, and /geniro:onboard (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §Presentation).

The two-step shape — render to a SEPARATE chat message first, then a lean `AskUserQuestion` — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, together with the separate-message rule, the render-exists check, and the pre-fire scrub (§Single-finding gate, "Scrub before the AUQ fires"). Every calling contract above cites that file rather than restating it. This file defines the visual language the render uses; consult per-finding-question.md for when and how the render fires.

## Visual rendering language

Every gate message in this language carries five elements, so the user always knows where they are in the decision flow and what they are deciding — without reading a wall of text:

- **Progress tracker.** The first line places the gate on its journey: `✔` decided · `●` deciding now · `○` still ahead. The stops are the calling flow's journey:
  - /geniro:plan uses its approval stops: `✔ Approach · ● Goal & scope (step 1 of 3) · ○ Steps · ○ Safety · ○ Final approval`.
  - Finding gates use the decision queue, with short plain-English tags per stop: `✔ Decision 1 — auth bypass · ● Decision 2 of 4 — export filter · ○ Decision 3 · ○ Decision 4`.

  Derive the denominator from already-persisted state — the kept-finding set, the open-questions list, the queued gate items. The tracker is presentation-only: never add a state-file field to carry it. Render the tracker only when the queue holds ≥2 decisions — a one-stop tracker is noise, not orientation.
- **One-sentence opener.** Immediately after the tracker (or as the first line when no tracker renders), one plain-English sentence stating what this gate decides: `**In one sentence:** we're deciding whether the export filter silently dropping archived rows is intended.`
- **Friendly digest blocks.** Explain each unit conversationally, not as a labeled ADR form: a lead sentence stating what is happening or what will be done, then `**Why:**` or `**Why it matters:**` (the reason in plain words, evidence cite in parentheses), an optional `**How it gets built:**`-style line when an action plan exists, and `**You'll see:**` (the observable outcome) when one exists. The calling contract maps its structured fields onto these slots — the slots are the language; the field plumbing stays with the caller.
- **A visual per unit.** Every unit — spec section, approach, finding, investigation result — carries a visual. The shape comes from its type: plan units per §Plan-unit visual map below; findings and investigation results per per-finding-question.md §Finding-type visual map. The visuals are the load-bearing comprehension aid for a user skimming the gate; render plain text instead only when a unit genuinely has nothing to map.
- **Light icons on headings** — one per heading (e.g. 🎯 🧭 📦 🚫 ⚠️ 🧪 ↩️ ✅ 🔍) to make the message scannable at a glance.

Close every render against the plain-English bar: a user with no plugin internals loaded must be able to act on every line. Translate author-facing identifiers into plain English (`PRODUCT-DECISION` → "needs your decision", `T2` → "handoff"), drop internal phase / step numbers, keep evidence cites as `path:lines`.

### Worked example — a finding gate message

```
✔ Decision 1 — auth bypass · ● Decision 2 of 3 — export filter · ○ Decision 3

### 🧭 Decision needed: archived rows silently excluded from exports

**In one sentence:** we're deciding whether the export endpoint should keep
filtering out archived rows, or include them.

The export endpoint builds its query through `buildQuery()` in
`src/export/query.ts`, which appends `WHERE archived = false` to every export.
Nothing in the UI or the API docs says archived rows are excluded — a user
exporting "all records" gets a silently smaller file.

**Why it matters:** anyone relying on exports for audits or backups is missing
their archived records, with no error and no hint (evidence: `src/export/query.ts:41-48`)

request ──▸ buildQuery() ──▸ WHERE archived=false ──▸ archived rows dropped

**Options:**
- **Include archived rows** — exports become complete; files get bigger
- **Keep the filter, document it** — behavior unchanged; docs + UI say so
```

The lean question that follows carries only the title, the `path:lines`, and the option selectors.

## Plan-unit visual map

The visual shape per spec section, for a `/geniro:plan` section-approval gate. Three sections carry the centerpiece visual of their cluster — the scope map, the data-flow diagram, and the done-condition checklist; the rest are lighter.

| Section | Visual shape |
|---|---|
| 1. Objective | None beyond the `**You'll see:**` line — the behavior sentence is the anchor |
| 2-3. Scope (Included / Excluded) | The in/out scope map: two boxed columns, `+` new file / `~` edited file / `x` excluded (cluster centerpiece) |
| 4. Assumptions | Plain cited bullets — invariants don't diagram well |
| 5. Risks | Mini-table: risk · symptom you'd see · severity |
| 6. Steps | ASCII data-flow diagram (cluster centerpiece — render it even when the section's concrete example is pseudocode) |
| 7. Tools Required | One-line list |
| 8. Approval Points | A gate timeline: `build ▸ [ask: X] ▸ build ▸ [ask: Y] ▸ ship` |
| 9. Validation | Checklist of test names: `☐ it('rejects negative quantity')` |
| 10. Rollback-Recovery | The revert command or feature-flag toggle in a code span |
| 11. Done Condition | `☐` checklist, one box per observable signal (cluster centerpiece) |

`/geniro:plan` pairs each visual with a concrete example of the section's content; that example set is the calling contract's own, while the visual shapes above are shared language.

## Turn-completion guard

The two-step shape leaves a seam between its steps: the render is emitted as its own message, and the lean question follows. A gate is not rendered until the question has actually fired — close the seam in the same pass:

- **After the render message exists, the immediate next action is the lean `AskUserQuestion`.** Never come to rest with the render emitted but the question unfired, and never close on a statement of intent ("I'll now ask which option you prefer"). Control returns to the user only through the question itself — a render with no question silently stalls the flow until the user types something, and whatever the render promised never happens.
- **Before stopping anywhere in a gate flow — including right after the question is answered — apply the canonical turn-completion check in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md`**: re-read the last emitted message and take the announced action instead of stopping.
- **The render is visible message text, never internal reasoning.** Reasoning produced while deliberating is invisible to the user; a render that was only "thought through" does not exist on their screen. Emit it as an ordinary chat message — the render-exists check (per-finding-question.md §Single-finding gate, "Scrub before the AUQ fires") verifies the immediately-preceding assistant message *is* the render.

**The render-first rule is mechanically enforced.** A plugin guard (`gate-render`) blocks any `AskUserQuestion` whose text references content "above" when the current turn contains no visible assistant message — the user would be answering blind. A blocked question is not a user denial, not an answered gate, and **not a tool failure**: it is a hard-block (`exit 2`) telling you the render is missing. Recover in two steps: write the full gate render as an ordinary chat message — the digest, evidence, and visuals the question refers to — then fire the same question again, options unchanged. Do not downgrade to plain-text options in chat (no structured answer is ever captured — treating a guard block as "the tool keeps failing" and asking in prose is the exact deviation this guard's recovery forbids), do not silently drop the gate (the decision is never made), and do not strip the "above" reference from the question to slip past the guard — the reference is what makes the lean question honest, and removing it without rendering hides the same blind-approval failure the guard exists to catch.

This guard is the inverse of the separate-message rule: that rule forbids cramming the render and the question into one assistant message; this one forbids emitting the render and then stopping without the question. Both exist because the underlying model has a documented early-stopping failure mode — deep into a long session it can end on a text-only statement of intent without issuing the corresponding tool call. Gates sit exactly on that seam, so the question-fire is part of the render's own action, not a follow-up that can be dropped.

## Explain-further option

A gate's option set may include an **"Explain further"** option — a reading aid, not a decision:

- Picking it renders a deeper walkthrough of the unit — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior — as a NEW chat message, then re-fires the same question.
- It writes NO approvals or decisions, never changes the unit's content, and does NOT count toward any revision/round cap in the calling skill. Counting a reading aid against a revision budget punishes the user for wanting to understand before deciding.
- When the gate's option set already holds 4 decision options, surface Explain-further via the chained follow-up question per per-finding-question.md §Cap-extension — never drop a decision option to make room.

## Lean-question conventions

The lean `AskUserQuestion` that follows the render obeys these conventions at every gate:

- **Every user-facing choice goes through the tool.** A plain-text `(A)/(B)` in chat bypasses the approvals persistence the structured tool records, so a resumed session has nothing to restore and re-asks a question the user already answered. The gates a skill enumerates are examples, not the complete set — a choice that arises mid-phase is still a choice. This is the canonical statement of the rule; consuming skills cite this bullet and list only their own gates.
- **Single-select** unless the gate is explicitly multi-select (e.g. a pick loop).
- **Never auto-default on an empty answer.** An empty answer indicates an upstream tool bug, not a user choice — re-ask. Only a repeated *empty-answer* loop (the tool keeps returning nothing) justifies falling back to a plain-text question in chat. A `gate-render` block (`exit 2`) is neither an empty answer nor a tool failure — recover it per §Turn-completion guard (render, then re-fire the same `AskUserQuestion`), never with the plain-text fallback.
- **≤4 options per call**, chaining a follow-up question per per-finding-question.md §Cap-extension when more exist; never drop or merge options to fit one call.
- **`preview` stays empty or a one-line recap.** The chat message is the rendering surface: `AskUserQuestion` renders `preview` as a narrow monospace side-box that hard-truncates long content with no scroll, and it is often absent entirely in an interactive session — a body placed there is unreadable or invisible, so the body stays in the chat message, which has full width, and the lean question captures only the decision.

## Why this exists

Walls of labeled text get skimmed, and a skimmed gate obtains an uninformed approval — the ceremony of a decision without the substrate for one. The tracker and opener orient the user in seconds; the per-unit visual carries comprehension of the thing being decided; the lean question then captures only the decision. One language across plan, review, implement, debug, and refactor means the user learns the gate shape once and reads every gate the same way.
