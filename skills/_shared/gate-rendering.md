# Gate rendering — shared visual language

Canonical visual language for every gate that renders rich, multi-part content to chat before a lean `AskUserQuestion`. This file defines the visual language those renders share; the two-step shape they sit inside and the per-gate field plumbing belong to the calling contract (§When this applies).

This file is the single source of truth for the visual language. Calling contracts cite specific sections — the element definitions live only here.

## Contents

- When this applies — which gates render in this language
- Two explanation layers — plain first, technical second
- Visual rendering language — the elements every gate message carries
- Plan-unit visual map — visual shape per spec section
- Turn-completion guard — the render is not a gate until the question has fired
- Explain-further option — the reading-aid option pattern
- Lean-question conventions — generic AskUserQuestion conventions for the lean question
- Why this exists — the rationale

## When this applies

Any gate that presents rich multi-part content before a decision:

- `/geniro:plan` approval gates — Phase 4 approaches, Phase 5 section clusters, Phase 8 final approval.
- Finding and product-decision gates under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — /geniro:review decision gates and PR-comment per-finding gates, /geniro:implement self-review decision resolution, /geniro:refactor product-decision escalation.
- Run-outcome and investigation gates — /geniro:review's report wrap-up (Action gate) and round-escalation, /geniro:debug's stall / fix-fail / open-question gates, /geniro:refactor's HIGH-risk step approval and blocked/regression escalations.
- Rule-improvement candidate gates — /geniro:reflect's per-candidate "write this project rule?" walk (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §Presentation). No other skill fires one.

The two-step shape — render to a SEPARATE chat message first, then a lean `AskUserQuestion` — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, together with the separate-message rule, the render-exists check, and the pre-fire scrub (§Single-finding gate, "Scrub before the AUQ fires"). Every calling contract above cites that file rather than restating it. This file defines the visual language the render uses; consult per-finding-question.md for when and how the render fires.

## Two explanation layers

Every explanation a gate carries — the reasoning behind a recommendation, what the problem is, what happens next, what an option costs — is written in two layers, in this order:

1. **The plain layer (always present).** What is going on and what it means for the user, in ordinary words, grounded in a concrete instance of the situation. Write it for someone who has never opened this codebase: say what the code does rather than naming the function that does it, and show the consequence rather than the mechanism — "a user exporting *all records* gets a smaller file than they asked for", not "`buildQuery()` appends a WHERE clause". Identifiers of every kind — file paths, symbol, class and type names, config keys, commands, error strings — belong to the layer below, not here.

2. **The technical layer (only where there is something to cite).** A `**Technical detail:**` block after the plain layer and before the options, carrying what a reader checking the claim needs: the `path:lines` cites, the symbol / class / config names, the command or error string, and any code-shaped visual.

Two properties make the split work, and a render that breaks either has merged the layers again:

- **The plain layer stands alone.** Delete the technical block and the user can still understand the situation and pick an option. A term the plain layer needs but cannot say in ordinary words is a term the plain layer has to define in ordinary words.
- **The technical layer adds no argument.** It is evidence for what the plain layer already said. A consideration that appears only there is a consideration the skimming user decides without.

Omit the technical block entirely at a gate with nothing to cite — a workspace pick, a how-deep-should-I-go choice. A labeled block holding restated prose is noise, and padding one teaches the next render to pad too.

## Visual rendering language

Every gate message in this language carries these elements, so the user always knows where they are in the decision flow and what they are deciding — without reading a wall of text:

- **Progress tracker.** The first line places the gate on its journey: `✔` decided · `●` deciding now · `○` still ahead. The stops are the calling flow's journey:
  - /geniro:plan uses its approval stops: `✔ Approach · ● Goal & scope (step 1 of 3) · ○ Steps · ○ Safety · ○ Final approval`.
  - Finding gates use the decision queue, with short plain-English tags per stop: `✔ Decision 1 — auth bypass · ● Decision 2 of 4 — export filter · ○ Decision 3 · ○ Decision 4`.

  Derive the denominator from already-persisted state — the kept-finding set, the open-questions list, the queued gate items. The tracker is presentation-only: never add a state-file field to carry it. Render the tracker only when the queue holds ≥2 decisions — a one-stop tracker is noise, not orientation.
- **One-sentence opener.** Immediately after the tracker (or as the first line when no tracker renders), one plain-English sentence stating what this gate decides: `**In one sentence:** we're deciding whether the export filter silently dropping archived rows is intended.`
- **Friendly digest blocks — the plain layer.** Explain each unit conversationally, not as a labeled ADR form: a lead sentence stating what is happening or what will be done, then `**Why:**` or `**Why it matters:**` (the reason in plain words), an optional `**How it gets built:**`-style line when an action plan exists, and `**You'll see:**` (the observable outcome) when one exists. The calling contract maps its structured fields onto these slots — the slots are the language; the field plumbing stays with the caller. Write every slot to §Two explanation layers, layer 1: no identifiers, no cites.
- **A `**Technical detail:**` block — the technical layer.** One per unit, after that unit's digest, carrying the evidence per §Two explanation layers, layer 2. Where a gate renders several units, each unit gets its own block next to its own digest rather than one pooled block at the end — a reader checking one finding should not have to match cites back to units.
- **A visual per unit.** Every unit — spec section, approach, finding, investigation result — carries a visual. The shape comes from its type: plan units per §Plan-unit visual map below; findings and investigation results per per-finding-question-reference.md §Finding-type visual map. Each visual renders in the layer its content belongs to: a data-flow or blast-radius sketch naming symbols goes inside the technical block, a plain-language visual (risk mini-table, done-condition checklist, in/out scope map — where the file name is itself the plain answer, not an implementation detail) stays in the digest. The visuals are the load-bearing comprehension aid for a user skimming the gate; render plain text instead only when a unit genuinely has nothing to map.
- **Light icons on headings** — one per heading (e.g. 🎯 🧭 📦 🚫 ⚠️ 🧪 ↩️ ✅ 🔍) to make the message scannable at a glance.

Close every render against the plain-English bar: a user with no plugin internals loaded must be able to act on every line. Translate author-facing identifiers into plain English (`PRODUCT-DECISION` → "needs your decision", `T2` → "handoff"), drop internal phase / step numbers, and keep evidence cites in the technical block rather than inline in the digest.

### Worked example — a finding gate message

```
✔ Decision 1 — auth bypass · ● Decision 2 of 3 — export filter · ○ Decision 3

### 🧭 Decision needed: archived rows silently excluded from exports

**In one sentence:** we're deciding whether the export endpoint should keep
filtering out archived rows, or include them.

Every export quietly leaves out archived records. Nothing in the app or the API
docs says so, so a user who asks to export "all records" gets a smaller file
than they asked for and no warning that anything was left behind.

**Why it matters:** anyone using exports for an audit or a backup is missing
their archived records — silently, with no error to notice and nothing to
re-run.

**Technical detail:** `src/export/query.ts:41-48` — `buildQuery()` appends
`WHERE archived = false` to every export query, with no caller-side opt-out.

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
- **The render is visible message text, never internal reasoning.** Reasoning produced while deliberating is invisible to the user; a render that was only "thought through" does not exist on their screen. Emit it as an ordinary chat message — the render-exists check (per-finding-question-reference.md §Single-finding gate, "Scrub before the AUQ fires") verifies the immediately-preceding assistant message *is* the render.

**When the render is missing, write it.** A question that points at content "above" is honest only while that content is on the user's screen. On reaching a gate whose render was never emitted, write the full render as an ordinary chat message — the digest, evidence, and visuals the question refers to — then fire the same question, options unchanged. Three shortcuts each produce the blind approval the two-step shape exists to prevent: putting the options in chat as plain text (no structured answer is captured, so the approvals persistence has nothing to restore on resume), dropping the gate (the decision is never made), and stripping the "above" reference so a bare question reads self-contained when its evidence was never shown.

This section is the inverse of the separate-message rule: that rule forbids cramming the render and the question into one assistant message; this one requires the question to follow the render. Both exist because the underlying model has a documented early-stopping failure mode — deep into a long session it can end on a text-only statement of intent without issuing the corresponding tool call. Gates sit exactly on that seam, so the question-fire is part of the render's own action, not a follow-up that can be dropped.

## Explain-further option

A gate's option set may include an **"Explain further"** option — a reading aid, not a decision:

- Picking it renders a deeper walkthrough of the unit — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior — as a NEW chat message, then re-fires the same question. The walkthrough keeps both layers of §Two explanation layers: it deepens the plain explanation as well as the evidence, because the user who asks to understand more is the one least served by a longer list of cites.
- It writes NO approvals or decisions, never changes the unit's content, and does NOT count toward any revision/round cap in the calling skill. Counting a reading aid against a revision budget punishes the user for wanting to understand before deciding.
- When the gate's decision options already fill the per-call cap (`per-finding-question.md` §Cap-extension), surface Explain-further via the chained follow-up question — never drop a decision option to make room.

## Lean-question conventions

The lean `AskUserQuestion` that follows the render obeys these conventions at every gate:

- **Every user-facing choice goes through the tool.** A plain-text `(A)/(B)` in chat bypasses the approvals persistence the structured tool records — a resumed session has nothing to restore and re-asks an already-answered question. Canonical; consuming skills cite this bullet, never restate it.
- **A skill's enumerated gates are examples, not the complete set.** A mid-phase choice the list never named is still a choice, and still routes through the tool above. Canonical statement of the closed-list rule.
- **No reader for the question is not licence to decide it.** Two different absences, two different answers. The tool missing under its Claude Code name usually means the host renamed it — resolve it by name before concluding anything (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` §Tool substitutions). Nobody there to read it — a cloud or background agent, a scheduled run — means the gate is deferred, not dropped: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/non-interactive-host.md` decides which gates take a recorded reversible default and which halt and hand the question back.
- **Exception: an unbounded option set, not inconvenient authoring.** This repo's own `.claude/skills/find-threads/` tooling picks a thread by free text — a project can hold far more threads than the tool's 4-option cap allows — then gates the launch itself behind a lean `AskUserQuestion`. Test for any future carve-out: the option set cannot fit the tool at all, not that enumerating it is inconvenient.
- **The question and its options carry the plain layer only.** `question`, each option `label`, and each option `description` state the choice and its consequence in ordinary words; the `path:lines` cite in the question title is the one identifier they carry, as the anchor back to the render. Everything else technical stays in the chat message's `**Technical detail:**` block, which has the width for it — an option chip reading `Keep the buildQuery() WHERE clause` makes the user parse a symbol name to pick.
- **Single-select** unless the gate is explicitly multi-select (e.g. a pick loop).
- **Never auto-default on an empty answer — always re-ask.** An empty answer indicates an upstream tool bug, not a user choice. Only a repeated *empty-answer* loop (the tool keeps returning nothing) justifies falling back to a plain-text question in chat — canonical; cite rather than re-derive.
- **A question that fired and then went unanswered is its own state — not declined, not empty, not answered.** The turn ending before a reply arrives is exactly how it arises, and the run has no control once the turn closes — so detect it at the START of the next turn, before anything else. A skill that keeps a state file records it there first, in the `## Errors` body section (schema: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §`## Errors` — the unanswered-gate entry); a skill with no state file (e.g. `/geniro:reflect`) has nowhere to write it and skips that step, but the rule below still binds regardless. Then re-fire the identical question. Once that re-fire returns an actual answer, flip the entry's `status` to `resolved` in the same write that acts on the answer. A message that isn't a reply to it — a new instruction, a bare "continue" — answers nothing and leaves the entry unresolved (or, with no state file, simply isn't an answer); taking the option the run itself recommended is the same failure with extra self-justification.
- **The option-count cap per call** (`per-finding-question.md` §Cap-extension is canonical for the number), chaining a follow-up question when more exist; never drop or merge options to fit one call.
- **`header` ≤12 characters.** The option chip hard-truncates past that, and a chip cut off mid-word reads as a rendering glitch rather than a label the user can scan across gates.
- **`preview` stays empty or a one-line recap.** The chat message is the rendering surface: `AskUserQuestion` renders `preview` as a narrow monospace side-box that hard-truncates long content with no scroll, and it is often absent entirely in an interactive session — a body placed there is unreadable or invisible, so the body stays in the chat message, which has full width, and the lean question captures only the decision.

## Why this exists

One language across plan, review, implement, debug, and refactor means the user learns the gate shape once and reads every gate the same way — the rationale for rendering the decision body before the question at all is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Why this exists.

The layer split exists because the two readers of a gate want opposite things from the same paragraph. The user deciding wants the situation and the stakes; the user checking wants the cites. Interleaving them serves neither: a technical detail landing in the second sentence forces the first reader to parse an identifier before they have the concept, and it buries the cites the second reader came for inside prose. Split, both readers get a block written for them, and either can skip the other's.
