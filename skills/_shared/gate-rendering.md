# Gate Rendering — shared visual language

Canonical visual language for every gate that renders rich, multi-part content to chat before a lean `AskUserQuestion`. The calling contract owns the gate's two-step shape and field plumbing — `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §"Gate presentation contract" for the /geniro:plan approval gates; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering for finding gates — this file defines the visual language those renders share.

This file is the single source of truth for the visual language. Calling contracts cite specific sections; do NOT inline-paste the element definitions.

## Contents

- When this applies — which gates render in this language
- Visual rendering language — the five elements every gate message carries
- Explain-further option — the reading-aid option pattern
- Lean-question conventions — generic AskUserQuestion conventions for the lean question
- Why this exists — the rationale

## When this applies

Any gate that presents rich multi-part content before a decision:

- `/geniro:plan` approval gates — Phase 4 approaches, Phase 5 section clusters, Phase 8 final approval (per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md` §"Gate presentation contract").
- Finding and product-decision gates under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — /geniro:review decision gates and PR-comment per-finding gates, /geniro:implement self-review decision resolution, /geniro:refactor product-decision escalation.
- Run-outcome and investigation gates — /geniro:review's report wrap-up (Action gate) and round-escalation, /geniro:debug's stall / fix-fail / open-question gates, /geniro:refactor's HIGH-risk step approval and blocked/regression escalations.

The two-step shape — render to a SEPARATE chat message first, then a lean `AskUserQuestion` — is owned by the calling contract (plan-loop.md §"Gate presentation contract"; per-finding-question.md §Message-first rendering), including the separate-message rule and the render-exists check; the pre-fire scrub belongs to the finding-gate contract (per-finding-question.md §Single-finding gate, "Scrub before the AUQ fires"). This file defines the visual language the render uses; consult the calling contract for when and how the render fires.

## Visual rendering language

Every gate message in this language carries five elements, so the user always knows where they are in the decision flow and what they are deciding — without reading a wall of text:

- **Progress tracker.** The first line places the gate on its journey: `✔` decided · `●` deciding now · `○` still ahead. The stops are the calling flow's journey:
  - /geniro:plan uses its approval stops: `✔ Approach · ● Goal & scope (step 1 of 3) · ○ Steps · ○ Safety · ○ Final approval`.
  - Finding gates use the decision queue, with short plain-English tags per stop: `✔ Decision 1 — auth bypass · ● Decision 2 of 4 — export filter · ○ Decision 3 · ○ Decision 4`.

  Derive the denominator from already-persisted state — the kept-finding set, the open-questions list, the queued gate items. The tracker is presentation-only: never add a state-file field to carry it. Render the tracker only when the queue holds ≥2 decisions — a one-stop tracker is noise, not orientation.
- **One-sentence opener.** Immediately after the tracker (or as the first line when no tracker renders), one plain-English sentence stating what this gate decides: `**In one sentence:** we're deciding whether the export filter silently dropping archived rows is intended.`
- **Friendly digest blocks.** Explain each unit conversationally, not as a labeled ADR form: a lead sentence stating what is happening or what will be done, then `**Why:**` or `**Why it matters:**` (the reason in plain words, evidence cite in parentheses), an optional `**How it gets built:**`-style line when an action plan exists, and `**You'll see:**` (the observable outcome) when one exists. The calling contract maps its structured fields onto these slots — the slots are the language; the field plumbing stays with the caller.
- **A visual per unit.** Every unit — spec section, approach, finding, investigation result — carries a visual. The shape comes from the calling contract's map: plan units per `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-reference.md` §"Concrete example + visual per section type"; findings and investigation results per per-finding-question.md §Finding-type visual map. The visuals are the load-bearing comprehension aid for a user skimming the gate; render plain text instead only when a unit genuinely has nothing to map.
- **Light icons on headings** — one per heading (e.g. 🎯 🧭 📦 🚫 ⚠️ 🧪 ↩️ ✅ 🔍) to make the message scannable at a glance.

Close every render against the plain-English bar: a user with no plugin internals loaded must be able to act on every line (the fresh-user test, `.claude/rules/skill-prose.md` §"User-facing output uses plain English"). Expand shorthand, drop internal identifiers, keep evidence cites as `path:lines`.

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

## Explain-further option

A gate's option set may include an **"Explain further"** option — a reading aid, not a decision:

- Picking it renders a deeper walkthrough of the unit — the full evidence chain (additional `file:line` cites), an expanded or alternative diagram, edge-case behavior — as a NEW chat message, then re-fires the same question.
- It writes NO approvals or decisions, never changes the unit's content, and does NOT count toward any revision/round cap in the calling skill. Counting a reading aid against a revision budget punishes the user for wanting to understand before deciding.
- When the gate's option set already holds 4 decision options, surface Explain-further via the chained follow-up question per per-finding-question.md §Cap-extension — never drop a decision option to make room.

## Lean-question conventions

The lean `AskUserQuestion` that follows the render obeys these conventions at every gate:

- **Single-select** unless the gate is explicitly multi-select (e.g. a pick loop).
- **Never auto-default on an empty answer.** An empty answer indicates an upstream tool bug, not a user choice — re-ask, falling back to a plain-text question in chat if the tool keeps failing.
- **≤4 options per call**, chaining a follow-up question per per-finding-question.md §Cap-extension when more exist; never drop or merge options to fit one call.
- **`preview` stays empty or a one-line recap.** The chat message is the rendering surface; the `preview` side-box hard-truncates long content and is often absent in an interactive session.

## Why this exists

Walls of labeled text get skimmed, and a skimmed gate obtains an uninformed approval — the ceremony of a decision without the substrate for one. The tracker and opener orient the user in seconds; the per-unit visual carries comprehension of the thing being decided; the lean question then captures only the decision. One language across plan, review, implement, debug, and refactor means the user learns the gate shape once and reads every gate the same way.
