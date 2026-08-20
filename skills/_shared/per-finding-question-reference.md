# Finding-gate shapes — single-finding, investigation, and their field plumbing

Companion reference to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (the core contract: message-first rendering, the lean question, the multi-select pick loop, the cap-extension, the Recommended-label policy). Read THIS file when a gate fires on a concrete finding or investigation result — it carries the required AUQ shape, the challenge option, the mandatory pre-fire scrub, the visual map, and the source-field maps. A run that reaches no finding gate never needs it.

This file is the single source of truth for these sections. Skills cite specific sections — the body schema lives only here.

## Contents

- Finding-type visual map — visual shape per finding/unit type
- Single-finding gate — one finding per call (shape + challenge option + scrub + source-field map)
- Investigation-driven fix gate — debug-flavored single-finding variant
- Where the body fields come from — in-memory vs handoff-artifact sources

## Finding-type visual map

Every rendered finding carries a visual per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Visual rendering language. The shape per unit type:

| Unit type | Visual shape |
|---|---|
| Logic / bug finding | 3-6 line ASCII data-flow of the broken path (`request ──▸ buildQuery() ──▸ WHERE archived=false ──▸ rows silently dropped`) or a before → after snippet pair |
| Architecture / conventions finding | Blast-radius sketch: the changed symbol and its callers/consumers as a 3-6 line tree |
| Security / risk finding | Mini-table: risk · symptom you'd see · severity |
| Test-coverage finding | `☐` checklist of the missing/affected test names |
| Performance finding | Small numbers table (current vs expected measurement) when numbers exist; otherwise the hot-path data-flow |
| Debug root cause | Cause → effect flow: `<root cause at path:line> ──▸ <intermediate> ──▸ <observed failure>` |
| Refactor step set | Steps flow diagram (`step 1 ▸ step 2 ▸ step 3`) + risk mini-table for HIGH-risk steps |

When a finding genuinely has nothing to map, the 2-5 line evidence snippet IS the visual; never invent a diagram for content that doesn't diagram.

## Single-finding gate (one finding per call)

Used by:
- `/geniro:review` Phase action-gate (PRODUCT-DECISION resolution; PR-comment Pick-one-by-one per-finding gate — calling-skill-set fixed menu: Post / Skip / Stop posting)
- `/geniro:implement` Phase 3 self-review fix loop (resolving findings that need the user's decision)
- `/geniro:refactor` escalation
- `/geniro:resolve` Phase 2 single-item gate (one ambiguous PR-comment item per call; the "Challenge this comment" option re-verifies the comment)

**One finding per call — never batched.** Each finding fires its own `AskUserQuestion` call carrying exactly one entry in `questions[]`: render that finding to chat, fire the question, collect the answer, then move to the next. When ≥2 findings need resolving, that is N sequential calls — never one call whose `questions[]` array holds several findings (the tabbed multi-question prompt the user navigates with Tab and submits all at once). Batching defeats the message-first render: a finding's chat block and its visual can only precede a call that asks about that one finding, so a multi-finding call leaves every finding but the first un-rendered at the moment of decision. The cap-extension rule (`per-finding-question.md` §Cap-extension) governs ONE finding's option overflow, never the finding count.

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (e.g. `"Decision"`, `"Escalate"`).
- **Chat render (first):** render the finding to chat per `per-finding-question.md` §Message-first rendering before firing the AUQ — the self-contained block carries the tracker (when ≥2 decisions are queued), the one-sentence opener, the conversational lead, the why-it-matters line with its evidence cite, the visual (§ Finding-type visual map), and the options, built from the finding's structured fields (see `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format) and expanded into plain English per the self-containment rule there (never echoed verbatim when they carry reviewer shorthand).
- **`question`** (lean): the plain-English one-line title, then a pointer to the chat block:

 ```
 <plain-English one-line title> — `path:lines`

 Full explanation above. How do you want to resolve it?
 ```

- **`options[]`** — one per enumerated path (from the finding's `Options:` field for PRODUCT-DECISION resolution gates; from the calling skill's escalation menu for refactor-style escalation gates — see `/geniro:refactor` Phase 3 escalation for the 4-fixed-option menu):
 - **`label`**: 1-5 words — the action name (e.g. `"Move to utils"`, `"Keep as-is"`, `"Run /geniro:implement"`).
 - **`description`**: 1-line trade-off. Preserves the existing `Options:` bullet's "— <one-line trade-off>" portion. For escalation gates where the calling skill overrides the finding's `Options:` with a fixed menu (e.g. `/geniro:refactor` escalation), the calling skill provides each option's `description` directly per its escalation menu's trade-off line — not derived from the finding's `Options:`.
 - **`preview`**: empty or a one-line recap only — the finding body (Evidence, Suggested fix, Confidence, Origin) lives in the chat block per `per-finding-question.md` §Message-first rendering (the "Why this shape" rationale there governs). When the calling skill's options are an escalation menu (not the finding's own `Options:`), the chat block still describes the finding's body — the escalation labels merely tell the user what action will be taken on it.
 - **Explain-further option:** append an **"Explain further"** option to the decision options — a reading aid per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option: picking it renders a deeper walkthrough of the finding (full evidence chain, expanded diagram, edge cases) as a new chat message, then the same question re-fires. It writes no decisions and never counts toward the calling skill's revision/round caps. When the finding's own options already fill 4 slots, surface it via the chained call (`per-finding-question.md` §Cap-extension) instead of dropping a decision option.
 - **Challenge-finding option (calling-skill opt-in):** when the calling skill enables it, append a **"Challenge this finding"** option per § Challenge-finding option below — picking it RE-VERIFIES the finding (not merely re-explains it) and can flip the verdict. Like Explain-further it writes no decision and consumes no round cap; unlike Explain-further it spawns a fresh verification pass. Counts toward the 4-slot cap (chain per `per-finding-question.md` §Cap-extension, when full).

### Challenge-finding option

A finding's option set MAY include a **"Challenge this finding"** option — a re-verification action distinct from the Explain-further reading aid. Explain-further re-renders the same finding in more depth and leaves the verdict untouched; Challenge re-runs the finding's verification and can overturn it.

- Picking it makes the calling skill spawn a fresh verification pass primed with the user's stated objection, then re-render the finding to chat with the returned verdict + fresh evidence and re-fire the same gate. For `/geniro:review` the pass is a `finding-verifier-agent` (the same mechanism that confirmed the finding at Phase 4.2); see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3 for the wired action.
- A `refuted` verdict demotes the finding (drops its gate); a `confirmed` verdict re-presents the same options, now with the verification the user asked for.
- It writes no resolution and does NOT count toward any revision/round cap — double-checking a finding must not cost the user a round, mirroring Explain-further.
- The calling skill owns the re-verification action and decides whether to offer the option; `/geniro:review` mandates it on every PRODUCT-DECISION gate, and `/geniro:resolve` offers it (labelled "Challenge this comment") on every single-item gate. When the finding's decision options plus the appended reading-aid and challenge options exceed 4 slots, surface them via the chained call (`per-finding-question.md` §Cap-extension); never drop a resolution path to make room.

### Scrub before the AUQ fires (hard)

The plain-English rule (`per-finding-question.md` §Message-first rendering, self-containment rule) is otherwise advisory — when the orchestrator builds the question and option fields from a finding's structured fields, it naturally echoes internal shorthand into them, so the rule leaks under drift — a decision-type tag like `PRODUCT-DECISION` lands in an option field because it was the field's value upstream, and nothing between the finding and the question converts it. Pair the advisory rule with a mechanical scrub at the question boundary, mirroring the PR-comment boundary's scrub in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.5 ("scrub before POST"): before firing ANY finding-gate `AskUserQuestion`, scan every string that will render — `question`, `header`, each option `label`, each option `description`, each `preview` — against the forbidden-token set:

- Decision-type tags: `PRODUCT-DECISION`, `FIX-NOW`, `TESTABLE`, `INTENT-CHECK`.
- Internal finding IDs: `M1` / `M1b` / `L5`-style `<letter><digit>` handles.
- Plugin branding: the `/geniro:` prefix.
- State-file paths and schema references.
- Phase / step labels: `Phase 4.3`, `Step 0`, `Pre-gate`, etc.
- Memory-layer / state-tier / subagent tokens: `L1`–`L4`, `T1`–`T3`, `KR` / `CE` / `TR`.

- `carry-over` / `carryover` — plain-English form: "carried over from the previous review round".
- `USER STEERING` / `steering-note` — plain-English form: "your steering note for this round".

On a hit, rewrite it into plain English — every token class listed above has a plain form: decision-type tags state what they mean for the user (`PRODUCT-DECISION` → "needs your decision"), memory-layer / state-tier / subagent codes state their plain meaning (`T2` → "handoff", `L4` → "project rules", `KR` → "knowledge-retrieval output"), and phase / step labels state what is happening (`Phase 6 Pre-gate` → "the open-question gate") — then re-scan until clean. Never fire a question whose rendered strings still match. A reviewer's verbatim `description:` about the code under review (a code symbol legitimately named `M1`, a cache the reviewer calls `L2`) stands; the scrub targets the orchestrator-composed question and option framing, not the finding's words about the code. Chat narration step-echoes pass the same translation tables — the scrub mechanism guards the AUQ and PR-comment boundaries, and by the plain-English rule narration follows the same vocabulary.

**Render-exists check (part of this scrub).** Before firing a gate AUQ whose `question` references previously-rendered content ("the message above", "rendered above", "summarized above"), verify the immediately-preceding assistant message IS that render (per `per-finding-question.md` §Message-first rendering). If it is not — a status line, a tool call, or absent — author the render first as its own message, then fire the AUQ in the next turn. A reference to a render that does not exist is a gate failure (the user could not have been informed), not a wording nit — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard carries the recovery.

### Source-field map

The chat block (`per-finding-question.md` §Message-first rendering) is the surface that carries the finding body; the AUQ stays lean. Fields are expanded into plain English, not echoed verbatim when they carry reviewer shorthand.

| Destination | Reviewer-agent finding field |
|-----------|------------------------------|
| chat lead sentence(s) — what the code does + the concern | synthesized in plain English from finding-title + `Evidence:` + `Why this matters:` |
| chat `Why it matters` line + its evidence cite | `Why this matters:` (expanded to name the concrete impact, not a verbatim one-liner) + `File:` (the `path:lines` cite) |
| chat visual | built from `Evidence:` per § Finding-type visual map |
| chat tracker tag (when ≥2 decisions queued) | finding-title, shortened to a 2-4 word plain-English tag |
| chat `Options` / AUQ option `label` + `description` | `Options:` bullets (`label` ← action name; `description` ← "— <one-line trade-off>") |
| AUQ `question` title + `path:lines` | finding-title (plain English) + `File:` |
| chat recap of `Confidence` / `Origin` | `Confidence:` / `Origin:` |

## Investigation-driven fix gate (debug-flavored)

Used by:
- `/geniro:debug` Phase 2 (Multi-path fix gate when a confirmed root cause has 2-4 valid fix paths with real trade-offs)
- `/geniro:debug` Phase 2 escape hatch (No repro — alternative regression-guard picker when the bug is non-deterministic)

Structurally identical to the Single-finding gate above, but the "finding" is constructed by the `/geniro:debug` investigation rather than read from a reviewer-agent `Options:` field — body fields come from `.geniro/state/debug/<slug>/state.md` instead of the reviewer-agent output.

### Required AUQ shape

- **`header`**: short chip label set by the calling skill (`"Fix path"` for the multi-path fix gate, `"No repro"` for the repro-infeasible escape hatch — both `/geniro:debug` Phase 2).
- **Chat render (first):** render the investigation context to chat per `per-finding-question.md` §Message-first rendering — the progress tracker (only when ≥2 fix decisions are queued), `### 🧭 Fix decision: <plain-English root-cause title>`, `**In one sentence:** <what this decision settles>`, a conversational root-cause digest (what is failing and why, plain English — name the file / behavior in words), the cause→effect flow visual per § Finding-type visual map (Debug root cause row), a **Reproduction status** line, then **Options** (each fix path + consequence). Pull fields from `.geniro/state/debug/<slug>/state.md`.
- **`question`** (lean): multi-line markdown:

 ```
 <plain-English root-cause title> — `path:lines`

 Full explanation above. How do you want to <resolve | regression-guard> it?
 ```

 Pull the root-cause `path:lines`, hypothesis title, and observed-failure summary from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` file:line + title + `## Hypotheses` Result field pre-fix output).
- **`options[]`** — one per fix path or per alternative regression guard:
 - **`label`**: 1-5 words — the path/guard name (e.g. `"COALESCE default"`, `"Add monitor/alert"`).
 - **`description`**: 1-line trade-off — provided by the calling skill per its constructed menu.
 - **`preview`**: empty or a one-line recap only — the investigation context lives in the chat block (`per-finding-question.md` §Message-first rendering).
 - **Explain-further option:** the same rule as the Single-finding gate — append an **"Explain further"** option per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option (deeper walkthrough as a new chat message, same question re-fires, no decisions written, no round caps consumed); when the fix paths already fill 4 slots, surface it via the chained call in `per-finding-question.md` §Cap-extension.

### Source-field map

| AUQ field | `.geniro/state/debug/<slug>/state.md` field |
|-----------|--------------------------------------|
| `path:lines` in `question` | confirmed hypothesis's `## Root Cause` section (file:line of root cause) |
| `<hypothesis title>` in `question` | confirmed hypothesis's title |
| chat digest's observed failure | first line of confirmed hypothesis's `## Hypotheses` Result field → captured pre-fix output |
| chat cause→effect flow visual + evidence snippet | `## Root Cause` file:line (the flow's origin node) + full captured pre-fix output (2-5 lines) from `## Hypotheses` Result field |
| chat `Reproduction status` | "Hypothesis confirmed at Phase 1 Isolate; reproduction test pending Phase 2" (multi-path fix gate) OR "Reproduction infeasible — <reason from `## Reproduction Test` Reproduction Decision>" (repro-infeasible escape hatch) |
| chat digest's hypothesis reference | hypothesis ID from state.md `## Hypotheses` |

## Where the body fields come from

For skills running findings end-to-end in one invocation (`/geniro:review`), the orchestrator has the full reviewer-agent output in-memory and pulls Evidence / Why-matters / Suggested-fix / Confidence / Origin directly.

For cross-skill consumers (`/geniro:implement`'s Phase 1 handoff-resolution step "Persist review/debug handoffs"), findings arrive in the Phase 3 self-review context (recorded in `<task-dir>/state.md`) or via the `/geniro:review` handoff at `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`. Those files carry the body fields per finding (at minimum for PRODUCT-DECISION rows, which is the only place AUQ fires across the skill boundary) — see the per-finding body schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` for the persisted shape.

For `/geniro:debug` Phase 2 / gates, body fields come from `.geniro/state/debug/<slug>/state.md` (the confirmed hypothesis's `## Root Cause` + `## Hypotheses` Result + `## Reproduction Test` Reproduction Decision sections) — debug operates within a single invocation, so the artifact and in-memory state are the same source.
