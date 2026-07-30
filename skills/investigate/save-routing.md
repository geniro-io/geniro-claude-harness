# Investigate — save-routing

Read at Phase 3 Step 4a, and only there: the Step 4 follow-up question has four picks, and this file governs one of them ("Save key findings to memory"). A run that dives deeper, asks a fresh question, or ends at "Done — answer is sufficient" never opens it.

## Contents

- Routing classes 1-4 — where each kind of finding belongs
- The per-finding walk — how each candidate is surfaced and approved

---

Before writing to a single store, classify each finding to its proper destination per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` — never default everything to learnings.jsonl — then surface them one at a time per the per-finding walk below. Check each target store for an existing entry covering the topic first: UPDATE it rather than adding a duplicate.

Every Agent spawn below follows the skill's §Subagent spawn contract — the six pre-inlined fields — and spawns as `general-purpose` directly.

Anything routed to Claude Code's native memory — by route 3's auto-memory path or route 4 — carries its qualifier in the text: that store has no `trust` field, so a root cause with no captured artifact behind it is written as suspected, naming what would confirm it. Memory outlives the session, and a confidently-worded wrong diagnosis misdirects every later session that recalls it.

## Routing classes

1. **Domain-vocabulary findings** — the investigation surfaced a new domain entity, role, or business-rule term that wasn't in CLAUDE.md's Domain Context. Examples: "the codebase calls X a `Tenant` but production calls it a `Workspace`" / "there's a hidden `BillingAccount` entity that wraps `Subscription`+`PaymentMethod`+`Invoice`."
   - Route: **CLAUDE.md** "Domain Context" section.
   - Method: surface each term via the per-finding walk below — **What I'd save** is the proposed 1-3 line term-block, **Where** is CLAUDE.md's Domain Context, **Why** is the vocabulary gap it closes; the lean question's "Save elsewhere" pick routes the term to a learning instead, and "Skip this finding" drops a term that is not durable enough.
   - On approval: investigate's `allowed-tools` does NOT include Write/Edit (research-only by design). Spawn a focused Agent (no `subagent_type`; per the spawn contract) with the proposed term-block pre-inlined (field 3) and the instruction: "Read CLAUDE.md, locate the `## Domain Context` section (create one before the first `##`-level section if missing — confirm via the orchestrator's prior AskUserQuestion answer pre-inlined here), append the proposed term-block at the section's end, do not modify other sections. Report the resulting diff." Pin task scope (field 1), acceptance criteria (field 2: "Domain Context section contains the proposed term-block; no other sections modified"), allowed mutation surface (field 4: only CLAUDE.md), output schema (field 5: returned diff), and model tier (field 6: inherit). This preserves investigate's research-only identity while enabling the auto-extract; the agent does the file write.
2. **Architectural decisions meeting all 3 ADR criteria** (hard to reverse + surprising + genuine trade-offs) — route to **ADR** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR target. Draft the ADR using the template; write into the existing `docs/adr/` or `docs/decisions/` directory (whichever the project uses), and ask the user before creating `docs/adr/` if neither exists. Spawn a focused Agent with the drafted ADR content + resolved target path pre-inlined; agent writes to `<adr-dir>/NNNN-<slug>.md`.
3. **Reusable technical insights** (gotchas, lightweight architectural decisions, surprising coupling) — store this learning per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract" (the same routing Step 5 uses): under a `## Memory Backend` block the store routes per its mode — `replace` writes the backend only (redacted first), `mirror` writes both the backend and the local file; absent block → append to **`<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl`** via `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` (resolve path prefix via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A so writes land in the main worktree). Bias hard toward flow, architectural, and recurring-mistake learnings; do NOT save narrow interface/field shapes, single-file behaviors, or facts re-derivable by reading the code. Apply the Reflect → Abstract → Generalize pre-pass before every save: if you cannot restate the finding one level up, drop it. The file-append path uses a focused spawned Agent since investigate has no Write tool; the backend-write path is the orchestrator's own routed store (or use the auto-memory path if the entry maps to project-memory shape).
4. **User preferences about how to collaborate** — route to Claude Code's native memory feature. It needs no file write, so this path doesn't require the agent-spawn workaround.

## The per-finding walk

**Surface the to-save findings one at a time** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering and the visual language in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — the same one-by-one walk `improvement-routing.md` §Presentation uses. For each finding, render a self-contained message:

- **What I'd save** — the exact content that will be written (term-block / ADR title + one-line decision / learning sentence), shown as it will land.
- **Where** — the routed store in plain English (Domain Context in CLAUDE.md / an ADR under `docs/adr/` / past learnings / collaboration memory).
- **Why** — why it is durable enough and why that store.

Then fire its own lean `AskUserQuestion` (header `Save N of M`), options "Save to <store>" (Recommended when durable, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy) / "Save elsewhere" / "Skip this finding" / "Skip the rest". A finding load-bearing in two stores names both in **Where** and adds a "Save to both <X> and <Y>" option; past the 4-option cap, chain per §Cap-extension. Never batch all findings into one save action.
