# Plan artifact

Owns the full lifecycle of an opt-in "visual plan artifact" for `/geniro:plan` — a live, rich, collapsible HTML page published to a private `claude.ai` URL and updated in place as the plan's phases proceed. You author the page as a single self-contained HTML file — inline CSS and inline SVG, no external requests — placed in the session scratchpad (never the hook-guarded `.geniro/` tree), and publish it with Claude Code's native `Artifact` tool; you capture the returned `claude.ai` URL, persist it, and evolve the page by editing that same HTML file and re-publishing to the same URL. The page must read like an RFC and lead with diagrams, not restate the spec as prose — its whole reason to exist is to be the richest, most visual surface of the plan (see § Content layers). Author it in the house visual design language defined in § House design language, below — an art-directed, subject-grounded look, never a templated "clean default". This is native-only — when a session can't publish, the caller shows one clean skip notice and `/plan` continues in chat exactly as before.

## Contents

- When to run — the `artifact_mode` gate and the native-only constraint
- House design language — the native-skill hand-off, treatment, component vocabulary, and the diagram / code-token / state-mark rules every fill reuses
- The opt-in question — wording lives with the caller (`${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1b)
- Availability detection & create — the first publish (skeleton page + inspect-for-URL)
- Update — per-phase revise-and-republish, blanking the Current decision panel once an answer lands
- Before-gate update — mirroring the pending decision onto the Current decision panel before a gate fires
- Re-sync on revision — re-running the before-gate refresh when a gate is re-presented after a revise, so the page never shows a stale plan
- Content layers — the rich page outline (the heart of the page), including the Current decision panel and the data layer
- URL persistence — saving the captured URL into state via `atomic_state_set_field`
- Unavailable / skip handling — one notice, then continue
- Caller contract — what callers provide and receive, with the verbatim invocation strings
- Anti-rationalization — common wrong turns and the correct move

## When to run

Run only when state shows `artifact_mode: true` — the user opted in. The caller checks this before entering any step here; do not re-check.

The page is native-only — it exists exactly when Claude Code's `Artifact` tool can publish to `claude.ai` in this session; there is no portable Markdown or HTML fallback file. A session that can't publish gets one skip notice and no retry for the rest of the run — the full skip/never-retry contract lives in §Unavailable / skip handling.

## House design language

Load the native `artifact-design` skill first, before any HTML. It owns the general methodology: grounding the look in the subject, the compact color / type / layout token plan, typeface pairing, chosen neutrals, both light and dark themes, the AI-default looks not to spend a free axis on, motion restraint, and structure that encodes meaning rather than decorates. Everything below is only what that skill cannot know — which treatment this page takes, the component vocabulary later fills reuse, and the rendering rules this page's content depends on.

Precedence when guidance collides: the user's own words, then the project's `## Design system` tokens if CLAUDE.md declares one, then the house calls here, then the native skill's defaults.

This section applies to every step below that writes or revises HTML — the create step, every later per-phase update, and every before-gate fill that adds a section, panel, or layer — since each of those steps already reads this same file.

### Treatment — editorial, grounded in this plan

The native skill asks you to read the request and calibrate the treatment. That read is already answered here: run its **editorial** branch. The page's whole reason to exist is to be the richest, most visual surface of the plan, so a neutral "clean readable" theme is the failure mode — it is the same look the page would carry for any plan, and it reads as templated. Derive the direction from *this* plan's subject: a telemetry surface, a billing flow, and an auth refactor should not come out looking identical.

The page is a document, not a dashboard — but its status badge, progress tracker, and state marks are the operated parts, so encode their state in form as well as in words.

### House components

The page is built from a small named set that every later fill reuses rather than re-invents: an **eyebrow** (mono, uppercase, wide-tracked) naming the real section above its heading — `RUNTIME · ONE CRON TICK`; a **card** one surface-step above the ground; a **code pill**; a collapsed `<details>` deep-dive layer; the header **status badge** and **progress tracker**; and a faint graph-paper **grid ground** that gives the field texture without competing with content. Spend the page's one bold move on a **signature element** that embodies the plan's subject — most often the lead data-flow diagram.

### Diagrams are the visual language

Every structural relationship — data flow, component architecture, before/after, and the data layer's schema — is authored as inline `<svg>` (or an HTML/CSS box-and-connector layout when SVG would be overkill). Hand-author these even though the native skill steers generative graphics toward Canvas: a plan's diagrams are small, labelled, and have to stay legible and selectable. A monospace `<pre>` ASCII tree is the chat fallback, never the artifact standard — it is exactly the flat, text-only result the artifact exists to replace, so a `<pre>` used as a diagram is a defect, not a shortcut. Which diagrams a given plan renders: § Content layers, below.

### Code & data tokens

Render inline code and JSON examples as styled token pills, not flat `<pre>` dumps — one inline-styled `<span>` per token in a conventional developer syntax palette (distinct hues for keys, strings, numbers, booleans, null, and punctuation), with identifiers and constants on a subtly tinted background pill. This needs no external highlighter, so it survives the page's content policy. The project's `## Design system` tokens win over the developer palette when CLAUDE.md declares one.

### State marks

Plan content carries states the page has to mark — retired, absent, stale, current, and the 2xx / 3xx / 4xx-5xx classes on the data layer. Give each a semantic hue held separate from the accent AND a distinct form: strikethrough for a retired item, a dashed border for an absent slot, a diagonal-stripe fill for stale, solid accent for current. Encoding both ways keeps the state readable without color, and any such system needs a small legend to be legible at all.

## The opt-in question

The opt-in question wording and its persistence rules live with the caller, in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1b — the caller fires it without loading this file, so a run that declines the page never pays for the lifecycle machinery below.

## Availability detection & create

The first publish builds the page skeleton and tells you whether this session can publish at all. There is no separate availability pre-check — you attempt the publish and read the result.

### Step 1: Author and publish the skeleton

Pin a one-line creative direction grounded in this plan's subject, in the house design language (§ House design language), before writing any HTML; every part of the page is authored in that language. Then author the page as a self-contained HTML file in the session scratchpad, and publish it with the `Artifact` tool (which takes the file path). You steer every part of the page — title, structure, styling, and the inline-SVG diagrams — by authoring the HTML, not by passing prose content to the tool. Build the first version as an RFC-shaped skeleton, ordered problem → design → diagrams → alternatives → risks (fill the plan title and the planning-journey stops from the run):

> - A header with the plan title, a status badge reading "🚧 In progress", and a progress tracker over the planning journey (explore · clarify · approach · steps · approval) with the current stop marked.
> - An "At a glance" summary block near the top, left empty for now with a short "filling in as we plan" placeholder — it will lead with an inline-`<svg>` data-flow diagram once the approach is set.
> - A "Before / after" summary block placeholder, for the inline-`<svg>` (or two-column HTML/CSS) side-by-side of how the system works now versus after the change.
> - Empty, collapsed `<details>` placeholders for the deep-dive sections that this plan will need (steps, validation, evidence, alternatives, decision log, risks, architecture & data-flow diagrams) — each with its heading and a one-line "to be filled" note.
> - Style the page in the house design language (§ House design language): adopt the project's `## Design system` tokens when CLAUDE.md declares one, and otherwise derive an art-directed, subject-grounded look from that section's methodology and techniques — never a generic clean theme, which reads as templated.
> - Self-contained only: inline CSS, no external scripts or stylesheets. Author every diagram as inline `<svg>` (or an HTML/CSS box-and-connector layout), never a monospace `<pre>` ASCII tree.

The first publish triggers a one-time consent prompt because the page goes to a private `claude.ai` page — that prompt is the meaningful "publishing to claude.ai" confirmation. Let it fire; do not add the `Artifact` tool to the skill's `allowed-tools` to suppress it.

### Step 2: Inspect the result for a URL

A successful publish prints a `https://claude.ai/code/artifact/<id>` URL to the session. Read the result:

- **A `claude.ai` URL came back** → the page is live. Capture the URL and persist it (per §URL persistence): record the page as live and save the URL. Tell the user the page is up and share the link.
- **No `claude.ai` URL — a bare local file path, or a "cannot publish" message** → this session can't publish. Record that the page is unavailable for this run, show the skip notice once (per §Unavailable / skip handling), and do not retry on later phases.

The distinction is the presence of the `claude.ai` URL, nothing else. Don't infer availability from anything but a returned `claude.ai` link.

## Update

Each later phase boundary that produces real content (approaches chosen, sections approved, spec written, final approval) revises the existing page in place and republishes to the same URL — never a fresh page. Revising in place keeps the user's open tab stable and avoids re-rendering the whole document, which both thrashes the view and risks the 16 MiB rendered-size ceiling on a large plan.

**Author every in-place fill in the house design language (§ House design language).** This applies to every fill — a § Update of a finished section AND a § Before-gate update of the panel and eager-filled layers. The new content must match the look the create step established: reuse the page's existing design tokens and component classes (the `:root` variables, the eyebrow / card / code-pill / `<details>` styles already in the file), and render its diagrams as inline `<svg>` and its data as styled token pills — never fresh ad-hoc styles, a generic block, or a flat `<pre>`. Same-session, those tokens live in the HTML file you are editing, so reuse them rather than inventing new ones. Cross-session or post-compaction, this file itself may have fallen out of context — the § Update and § Before-gate update calls below already re-read it, which brings § House design language back with it, so an in-place fill after a resume authors from the same guidance as the create step did; skipping that re-read is what makes the section you add drift to a generic look while the rest of the page stays art-directed and the page stops reading as one document. One carve-out: a UI mockup filled into the UI-mockup layer keeps its own styles, because it depicts the product's UI rather than this document — re-skinning it in the page's tokens would misrepresent what the plan approved. Style its frame (heading, eyebrow, caption) in the house language and embed the mockup markup unchanged.

### Same-session update

When the page was published earlier in this same session, the file↔URL link still holds, so instruct a silent in-place revision without re-stating the URL:

> Revise the artifact and republish to the same URL: fill the "<section name>" section with <the content just produced>, flip any status that changed, and advance the progress tracker to <current stop>. Keep every other section as-is — revise in place, don't regenerate the page.

### Cross-session / resume update

After a compaction or a new session, the file↔URL link is lost, so the saved URL must be named explicitly or a duplicate page gets created:

> Update <artifact_url> with <the content just produced> for the "<section name>" section, authored in the page's existing design tokens and component classes (§ House design language), advance the progress tracker to <current stop>, and republish to that same URL. Revise the existing page in place — don't rebuild it.

In both forms, fill only the layers that now have real content and flip the header status badge / progress tracker to match the current stop. Also blank ONLY the Current decision panel (per § Content layers): the decision it mirrored just resolved, so leaving it in place would show the user a stale question — but the eager-filled deep-dive layers persist, so this Update just promotes the chosen option into At a glance / Steps and demotes the non-chosen options into the Considered alternatives layer rather than filling either from scratch. At final approval, set the badge to "✅ Approved" and mark every tracker stop done.

### Before-gate update

Just before a substantive decision gate fires in chat, fill the Current decision panel (per § Content layers) with the question the user is about to be asked plus the rich per-option detail — for each option its rationale, its trade-off, a code/schema snippet or small inline-SVG, and any feasibility verdict — richer than the per-option consequence the chat gate message carries. In the SAME in-place revision, also eager-fill the deep-dive layers whose content already exists at this gate — the Evidence (e.g. the stress-test table plus the exploration findings), the candidate options' full write-ups, and the architecture / data-flow diagram — so the page is the richest surface at the decision moment, with the panel anchor-linking down to them. These eager-filled deep-dive layers persist after the answer: only the panel blanks; the chosen option later moves to At a glance / Steps and the losing options become the Considered alternatives layer, so no re-authoring is needed. The page is emitted as output tokens under a ~32K per-response cap and a 16 MiB rendered ceiling, so build the richer panel and layers as targeted in-place edits, filling the panel and the one or two most decision-relevant layers first; if a single revision would be too large, fill those and let the rest land at the post-pick § Update. Never regenerate the page. Author the panel and the eager-filled layers in the house design language (§ House design language) — reuse the page's existing tokens and classes — per § Update's in-place-fill rule. The user can then read the whole decision on the page while answering in the terminal.

This panel mirrors the chat gate message; it never replaces it. The chat message stays the place the decision is rendered, and the answer is still captured by the terminal `AskUserQuestion`. The page is published and read-only — it has no way to send a click back to the session — so a question shown only on the page would leave the user with nothing to act on, and the chat-side render check still expects the question in chat. Keep the chat render; the panel just mirrors it.

Refresh via targeted in-place edits — never regenerate the page. The matching after-the-decision Update call blanks the panel once the answer lands (per § Update), so the panel never accumulates stale questions or grows the page toward the 16 MiB ceiling.

Same-session form:

> Revise the artifact and republish to the same URL: fill the "Current decision" panel with <the pending question; for each option its rationale, trade-off, a code/schema snippet or inline-SVG, and any feasibility verdict; and the deep-dive layers that already have content (evidence, candidate write-ups, diagram)>. Keep every other section as-is — revise in place, don't regenerate the page.

Cross-session / resume form (name the saved URL so no duplicate page is created):

> Update <artifact_url> by filling its "Current decision" panel with <the pending question; for each option its rationale, trade-off, a code/schema snippet or inline-SVG, and any feasibility verdict; and the deep-dive layers that already have content (evidence, candidate write-ups, diagram)>, all authored in the page's existing design tokens and component classes (§ House design language), and republish to that same URL. Revise the existing page in place — don't rebuild it.

### Re-sync on revision

When a decision gate is re-presented because the user asked to revise it — the content is re-authored and the chat gate message is re-rendered (e.g. the Phase 5 "Revise specific sections" round) — re-run the Before-gate update above against the revised content so the page mirrors the re-rendered chat: refill the Current decision panel and re-eager-fill the deep-dive layers that changed, including the Data layer when a data-bearing section changed. Do NOT blank the panel on a revision — the gate is still open and no answer has landed; the panel blanks only at the matching post-resolution § Update once the user finally approves. The chat render stays primary and the page mirror stays in lockstep with it. This fires once per revision round (the revise loop is bounded), not per micro-edit — the same throttle as refreshing only at substantive gates, not at each grill question.

## Content layers

The page is the heart of this feature: a single always-visible summary plus collapsible deep-dive layers, far richer than the terse spec.md the user also gets. The summary layer is always expanded; every deep-dive layer is a native `<details>` collapsed by default. Render a layer only when this plan actually has content for it — an SVG sequence diagram for a plan with no sequence is noise, so omit empty layers entirely rather than showing empty headings.

**Visual-first, and never a text substitute for a diagram.** This page exists to *show* the design, not retype the spec. Every structural relationship — the data flow, the component architecture, and the before/after of the change — is authored as an inline `<svg>` (or an HTML/CSS box-and-connector layout when SVG would be overkill), per § House design language § Diagrams are the visual language, which owns the `<pre>`-is-a-defect rule. The same bar extends to data, which that section does not cover: the data layer's structure renders as an inline-`<svg>` ER diagram, and its request/response/types render as the typed-JSON widget (inline-styled JSON-with-types beside a typed field table). And every section either visualizes the design or adds depth the spec lacks (expanded examples, evidence drill-downs, trade-off detail) — a section that would only restate spec prose is rendered as a diagram or omitted. The bar is RFC readability: a reader who never opens the spec should grasp the problem, see how it works from the diagrams, and weigh the alternatives from the page alone.

The page's visual identity — palette, type scale, grid ground, motion, and the signature element — comes from § House design language; apply it to every layer so the whole page reads as one art-directed document rather than a styled-by-default report. Reuse the visuals `/plan` already builds at the approach gate, the section-approval gate, and the final-approval gate (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — borrow the five visual elements there as structural guidance: a progress tracker, a one-sentence opener, friendly digest blocks, a visual per unit, and light heading icons). Those elements were defined for chat gate messages; here they style a persistent page, so take the look and the structure but none of the chat mechanics (no question pairing, no turn guard). On the page, go deeper than chat or the spec allow — expanded code examples richer than the spec's terse snippets, full evidence drill-downs, complete alternative write-ups.

**Always-visible summary layer:**

- **Header** — plan title, a status badge (`🚧 In progress N/total` while planning, `✅ Approved` once approved), and a progress tracker over the planning journey (explore · clarify · approach · steps · approval) with the current stop marked. The badge and tracker are the at-a-glance "where is this plan" signal.
- **At a glance** — the objective in one or two sentences, an in-scope / out-of-scope split, the chosen approach in a sentence, and a small inline-`<svg>` data-flow diagram of how the change moves through the system — real SVG nodes and arrows.
- **Before / after** — for any plan that changes existing structure or behavior, a side-by-side visual of how the system works now versus after the change, authored as inline `<svg>` or two HTML/CSS columns. This is the single most load-bearing picture of *how it will work*, so it lives in the always-visible summary, not a collapsed layer. Omit only when the plan adds something wholly new with no prior state to contrast.
- **Current decision** — while a decision gate is open, the question the user is being asked right now and, for each option, its rationale, its trade-off, a decision-relevant artifact (a code or schema snippet, or a small inline-SVG diagram), and any feasibility / stress-test verdict — going deeper than the per-option consequence the chat gate message carries, since this panel is where the user weighs the options on the page (the lean one-line recap belongs to the terminal question's preview box, not here). The panel auto-expands while the gate is open and anchor-links each option to its full write-up in the deep-dive layers below; it sits empty between gates. The page is read-only — the user answers in the terminal — so this panel shows the decision, it does not collect it. Filled by § Before-gate update, blanked by the next § Update.

**Collapsible deep-dive layers** (each a collapsed `<details>`, rendered only when it has content):

1. **Steps** — every implementation step with its Why, the files it touches, an expanded code example (fuller than the spec's), and the per-step risks.
2. **Validation & done conditions** — the success criteria as an interactive checklist the reader can tick through.
3. **Evidence from exploration** — the `file:line` findings that grounded the plan, with drill-down into what each one showed.
4. **Considered alternatives** — full write-ups of the approaches that were weighed and not chosen, with why each lost.
5. **Decision log** — every clarifying question asked during planning and the answer that was chosen, in order.
6. **Risks & mitigations** — the plan-level risks and how each is handled.
7. **Glossary / data tables / dependency list** — terms, reference tables, and the components this plan depends on.
8. **Architecture diagram** — an SVG of the components and how they connect.
9. **Sequence & data-flow diagrams** — SVG diagrams of the runtime flow and how data moves.
10. **Before / after (detail)** — the code-level diff behind the summary's before/after visual: the as-is versus to-be source side-by-side, longer and more concrete than the summary picture.
11. **Data layer** — the typed widget for everything this plan changes about data. Render it only when the plan actually changes data — a database/table/entity, an API endpoint, or a type/data shape — and omit the whole layer otherwise. It has three conditional parts; render each only when the plan touches that part:
    - **Database / data model** (when the plan changes a schema, table, or entity) — an inline-`<svg>` ER diagram: each entity is a box with a table-name header and one row per column, the primary key marked (underlined or `PK`-prefixed) and foreign keys marked `FK`; relationships are drawn as connectors between the FK and the parent PK, with **crow's-foot cardinality** end-markers so 1:1 / 1:N / M:N read off the line ends; group related tables by fill color; lay it out anchor-table-first (central domain tables first, lookup/link tables outward). Alongside the diagram, give the **schema diff** (columns/tables added · changed · dropped) and the **ordered migration steps**. State-machine transitions the change introduces also render here as an inline-`<svg>`.
    - **API endpoints** (when the plan adds or changes an endpoint) — one block per endpoint: a method badge showing the verb (GET/POST/PUT/PATCH/DELETE) plus the path, visually distinguished so the verb is scannable at a glance — choose the encoding from the page palette / the project's design-system tokens — then a **request** pane (headers + an example body) and a **response** pane (a status badge that distinguishes the 2xx / 3xx / 4xx–5xx classes at a glance using the page's semantic-state hues per § House design language, deferring to the project's `## Design system` tokens when CLAUDE.md declares one, + an example body). Pair each example with a **typed field table**: one row per field carrying name · a type badge · a required/optional marker · any constraint chips (enum, min/max, format) · a one-line description — the example pane alongside the typed field reference. Response-only (read-only) fields appear only in the response example; request-only (write-only) fields appear only in the request example. Nested objects/arrays collapse via inner `<details>` (no JavaScript).
    - **Types & data shapes** (when the change adds or alters a type) — the type definitions rendered the same way: a typed field table beside an annotated example.
   Render every JSON example as inline-CSS-styled tokens, not a flat `<pre>` dump — one styled `<span>` per token in the conventional developer palette per § House design language § Code & data tokens (which also defers to the project's `## Design system` tokens when CLAUDE.md declares one). This needs no external highlighter and stays within the content policy. Keep examples representative — a few rows, a trimmed body — never full datasets, so the typed widget stays under the token cap and the 16 MiB ceiling.
12. **Test plan** — the test cases, example test code, edge cases to cover, and coverage targets.
13. **Security & privacy** — the threat model, plus how auth and sensitive data are handled.
14. **Performance** — the expected impact, the hot paths touched, and any benchmark figures.
15. **Rollout & rollback** — feature flags, the deploy and migration sequence, what to monitor, and how to roll back.
16. **Milestones & timeline** — the ordered milestones for a larger plan.
17. **Dependencies & libraries** — the build-vs-buy calls, chosen versions, install commands, and links.
18. **Links & references** — linked tracker tickets, related pull requests, and the sources the plan cites.
19. **Interactivity** — an in-page search box, jump-to navigation, expand-all / collapse-all controls, and a live changelog of the plan's revisions. These use small inline JavaScript, which is allowed because it makes no external request; keep all script inline (no CDN, no external file).
20. **UI mockup** — for a plan that changes UI, the rendered mockup produced at the preview gate: every component in each of its visible states as labelled variants, one labelled frame per breakpoint, and the focus order marked. It arrives as a self-contained block scoped under its own container, so embed it as-is rather than re-styling it (§ Update's carve-out), and caption it as structure-and-states, not final visual design. While the preview gate is open the Current decision panel anchor-links down to it instead of repeating it.

Deliberately omit a file-change / blast-radius map — that view is not part of this page.

### Page structure mock

A concrete target for the model authoring the page:

```
┌─────────────────────────────────────────────────────────────┐
│  <Plan title> — Plan            🚧 In progress 3/5           │
│  explore ✔ · clarify ✔ · approach ● · steps ○ · approval ○  │
├─────────────────────────────────────────────────────────────┤
│  CURRENT DECISION            (only while a gate is open)    │
│  Q: <the question being asked in chat right now>            │
│  ── Option A ─────────────────────────────────────────────  │
│   Why: <rationale>    Trade-off: <gain vs give-up>          │
│   [ snippet / inline-SVG ]      ↳ full write-up: §Evidence  │
│  ── Option B ─────────────────────────────────────────────  │
│   Why: <rationale>    Trade-off: <gain vs give-up>          │
│   [ snippet / inline-SVG ]      ↳ full write-up: §Alts      │
│  ↳ answer in the terminal — this panel only shows it        │
├─────────────────────────────────────────────────────────────┤
│  AT A GLANCE                                                 │
│  Objective: …                                               │
│  In scope: …                Out of scope: …                 │
│  Approach: …                                                │
│  [ inline-SVG data-flow diagram — not an ASCII tree ]       │
├─────────────────────────────────────────────────────────────┤
│  BEFORE / AFTER                                             │
│  [ before ]            →            [ after ]               │
│  inline-SVG (or two HTML/CSS columns) — how it works now    │
│  versus after the change                                    │
├─────────────────────────────────────────────────────────────┤
│  ▸ Steps                                          (collapsed)│
│  ▸ Validation & done conditions                   (collapsed)│
│  ▸ Evidence from exploration                      (collapsed)│
│  ▸ Considered alternatives                        (collapsed)│
│  ▸ Decision log                                   (collapsed)│
│  ▸ Risks & mitigations                            (collapsed)│
│  ▸ Architecture / sequence / data-model diagrams  (collapsed)│
│  ▸ Data layer — DB schema · API · types           (collapsed)│
│  ▸ Test plan · security · performance             (collapsed)│
│  ▸ Rollout & rollback · milestones                (collapsed)│
│  ▸ Dependencies · links & references              (collapsed)│
│  ▸ UI mockup — states · breakpoints               (collapsed)│
├─────────────────────────────────────────────────────────────┤
│  [search box]  [jump to ▾]  [expand all] [collapse all]     │
│  Revision log: r1 skeleton · r2 approach · r3 steps …       │
└─────────────────────────────────────────────────────────────┘
```

Only sections with real content appear; a plan with no data change drops the whole data layer, a plan with no UI drops the data-flow visual. The Current decision panel shows only while a gate is open and is blank otherwise.

## URL persistence

Save the captured `claude.ai` URL into state.md frontmatter so a later session re-targets the same page. Set the three artifact fields in place — the rest of the file is not rewritten, so no other field can carry forward at a stale value. The pattern, run by the caller after the create step returns a URL:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
S=".geniro/planning/<task-dir>/state.md"

atomic_state_set_field "$S" artifact_status live
atomic_state_set_field "$S" artifact_url "<captured claude.ai url>"
atomic_state_set_field "$S" timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Carry the rest of the frontmatter and the whole body through unchanged — the only fields this write touches are `artifact_status` (now `live`) and `artifact_url` (the captured link). Use a fresh `date -u` read in the same Bash call for `timestamp`; never a copied literal.

## Unavailable / skip handling

When the create step gets no `claude.ai` URL back, this session can't publish a live page. Record the page as unavailable for the run, show this notice once, and continue planning in chat:

> A live visual artifact needs a Team or Enterprise plan and a `/login` session — this session can't publish one, so I'll keep planning in chat. Everything else works normally.

Then stop trying for the rest of the run: the unavailable state disarms the update step, so no later phase re-attempts the publish or re-shows the notice. Never half-build a local stand-in file when the native publish is unavailable — the feature is native-only, and a stray local HTML file in the project would just be litter the user has to clean up.

## Caller contract

- **Callers provide:** the task-dir / state.md path, the current phase, the planning-journey stops for the tracker, the content just produced for the layer being filled, and — for a before-gate refresh — the pending question and, per option, its rationale / trade-off / a code-or-schema snippet or inline-SVG / any feasibility verdict, plus the supporting deep-dive content already available at this gate (evidence, candidate write-ups, diagram).
- **Callers receive:** a persisted `claude.ai` URL with the page recorded as live, or an unavailable signal after the one-time skip notice.
- **Callers are responsible for:** writing the artifact frontmatter fields (`artifact_mode`, `artifact_status`, `artifact_url`) via `atomic_state_write`; guarding every call on `artifact_mode: true`; and additionally skipping the update call when the page is recorded as unavailable.

Invocation strings the callers use, verbatim:

- **Create** (once, at the start of planning): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Availability detection & create`
- **Update** (at later phase boundaries): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: <phase> and the content just produced`
- **Before-gate update** (just before a substantive gate fires): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: <phase> and the pending decision with full per-option detail + the supporting deep-dive content now available`

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The native skill covers design, so I can skip § House design language." | It cannot know this page's treatment is already decided, that structural diagrams are hand-authored SVG here, or which component classes the page's later fills must reuse — the failure shows up as a second section that looks nothing like the first. |
| "An ASCII `<pre>` tree shows the same structure." | A monospace tree is the flat, text-only output the artifact exists to replace. Author flow, architecture, before/after, and the data layer as inline `<svg>` or an HTML/CSS box-and-connector layout. |
| "The data layer is tabular, so a `<pre>` JSON block or an ASCII column list carries it." | The `<pre>`-is-a-defect rule is § House design language § Diagrams are the visual language; what it does not carry is the data layer's own two shapes, documented in § Content layers: schema renders as an inline-`<svg>` ER diagram (PK / FK / crow's-foot cardinality), and request/response/types render as the typed-JSON widget (inline-styled JSON-with-types beside a typed field table). |
| "I'll use Mermaid for the diagrams." | The page runs under a strict content policy that blocks every external request, so a Mermaid CDN script never loads. Draw diagrams as inline SVG or HTML/CSS, which render with no external fetch. |
| "No URL came back — I'll retry the publish each phase." | A missing `claude.ai` URL means this session can't publish at all; retrying every phase just re-fails and re-spams the notice. Record the page as unavailable, show the skip notice once, and stop attempting. |
| "I'll regenerate the whole page from scratch each phase." | A full regen re-renders the whole document, thrashing the user's open tab and pushing a large plan toward the 16 MiB ceiling. Revise the existing page in place and republish to the same URL. |
| "I'll write the artifact's HTML source into `.geniro/planning/<slug>/`." | The state-helper hook guards `.geniro/` and blocks the write. Author the HTML in the session scratchpad instead, publish it from there, and persist the returned `claude.ai` URL into state — the scratchpad file is disposable, the URL is what a later session re-targets. |
| "The user opted in, so I'll suppress the publish consent prompt / add `Artifact` to `allowed-tools`." | The one-time native consent prompt is the meaningful "publishing to a private claude.ai page" confirmation — opting into the artifact is not opting into the publish. Leave the consent prompt in place and keep `Artifact` out of `allowed-tools`. |
| "It's an internal planning doc that already has the spec content, so a utilitarian look or a terse copy is enough." | The page exists to be the richest surface of the plan — a templated report is the exact outcome it was built to replace, and a prose copy of the spec wastes the richer surface. Run the native skill's editorial branch grounded in this plan's subject (§ House design language), and go deeper than the spec: expanded code examples, full evidence drill-downs, complete alternative write-ups, and real diagrams — or restate a section as a diagram or drill-down, or omit it. |
| "The panel mirrors the chat gate, so one line per option is enough." | The panel is where the user weighs the options on the page, so it carries each option's rationale, trade-off, and a snippet or diagram — deeper than chat. The lean one-liner belongs to the terminal question's preview box; the only thing the panel must not do is collect the answer. |
| "I'll leave Evidence / alternatives / diagrams 'to be filled' until the post-pick Update." | At the gate the user is deciding, and all that content already exists in context, so deferring it leaves the page emptiest exactly when the user most needs it. Eager-fill the layers that have content at the gate boundary; the post-pick Update then just promotes the chosen option and demotes the losers to Considered alternatives. |
| "I'll refresh the Current decision panel before every grill question." | The grill asks many questions one at a time; republishing the page on each would thrash the user's tab and burn tokens for little gain. Refresh the panel only at the substantive gates — the grill checkpoint, the approach gate, each section cluster, and final approval — not at each individual grill question. |
| "I'll put the gate question only on the artifact so the user answers there." | The page is published and read-only — it has no way to send a click back to the session, so a question shown only on the page leaves the user with nothing to act on, and the chat-side render check still expects the question in chat. Always render the gate message in chat and answer the `AskUserQuestion` in the terminal; the panel only mirrors it. |
| "I'll add a `## Data` section to the spec to source the data layer." | The spec's section schema is fixed by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md`, and a bump propagates to `/geniro:implement`, `/geniro:review`, and the Phase 7 validator. The data layer is artifact-only content synthesized from the spec's Steps section plus the Phase 1 exploration evidence — build it on the page, do not bump the spec schema for it. |
| "The chat re-rendered the revised sections, so the page will catch up at the next Update." | The next § Update only fires on approve, which can be several revision rounds away; until then the page shows the stale pre-revision plan. Re-run the Before-gate refresh on every revision round so the page mirrors the chat — and do not blank the panel, since the gate is still open. |
