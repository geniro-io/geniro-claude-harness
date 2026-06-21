# Plan Artifact

Owns the full lifecycle of an opt-in "visual plan artifact" for `/geniro:plan` — a live, rich, collapsible HTML page published to a private `claude.ai` URL and updated in place as the plan's phases proceed. The page drives Claude Code's native `Artifact` tool, which is prose-driven: you make the page appear and evolve by instructing the model in natural language, capture the returned URL, and persist it so a later session re-targets the same page. This is native-only — when a session can't publish, the caller shows one clean skip notice and `/plan` continues in chat exactly as before.

## Contents

- When to run — the `artifact_mode` gate and the native-only constraint
- The opt-in question — the Phase-0 question fired when `--artifact` is absent
- Availability detection & create — the first publish (skeleton page + inspect-for-URL)
- Update — per-phase revise-and-republish, blanking the Current decision panel once an answer lands
- Before-gate update — mirroring the pending decision onto the Current decision panel before a gate fires
- Content layers — the rich page outline (the heart of the page), including the Current decision panel
- URL persistence — saving the captured URL into state via `atomic_state_write`
- Unavailable / skip handling — one notice, then continue
- Caller contract — what callers provide and receive, with the verbatim invocation strings
- Anti-rationalization — common wrong turns and the correct move

## When to run

Run only when state shows `artifact_mode: true` — the user opted in. The caller checks this before entering any step here; do not re-check.

The page is native-only. It exists exactly when Claude Code's `Artifact` tool can publish to `claude.ai` in this session. There is no portable Markdown or HTML fallback file — a session that can't publish gets a one-time skip notice (per §Unavailable / skip handling) and `/plan` proceeds in chat. The create step (§Availability detection & create) additionally guards the rest of the lifecycle: once it records that this session can't publish, the update step skips silently rather than retrying.

## The opt-in question

When the `--artifact` flag is absent from the run's arguments, the caller fires this single `AskUserQuestion` at the start of planning (before exploration), so the page can be built up from the first phase. With the flag present, skip the question — the flag is the opt-in.

- **Question:** "Build a live visual artifact of this plan as it develops? It publishes a private, auto-updating page to claude.ai."
- **Option A — "Yes — build it and keep it updated"** → the user wants the page.
- **Option B — "No — keep planning in chat only"** → plan in chat with no page.

Persistence intent: on option A, the run is in artifact mode (`artifact_mode: true`, and the publish hasn't happened yet so the status starts at `pending`); on option B, artifact mode stays off and no artifact fields are written. Either way, record the choice as a saved decision for this run under the category `artifact_choice`, so a resume after compaction doesn't re-ask. The caller owns the frontmatter write via `atomic_state_write`; this section owns only the question text and the choice that gets persisted.

## Availability detection & create

The first publish builds the page skeleton and tells you whether this session can publish at all. There is no separate availability pre-check — you attempt the publish and read the result.

### Step 1: Instruct the skeleton publish

The `Artifact` tool is prose-driven, so steer the title, content, and styling in natural language rather than hand-authoring a tool call. Instruct the model with a message shaped like this (fill the plan title and the planning-journey stops from the run):

> Publish an artifact titled "<plan title> — Plan" as an HTML page. This is a live plan that I'll revise as planning proceeds, so build it as a skeleton I can fill in:
> - A header with the plan title, a status badge reading "🚧 In progress", and a progress tracker over the planning journey (explore · clarify · approach · steps · approval) with the current stop marked.
> - An "At a glance" summary block near the top, left empty for now with a short "filling in as we plan" placeholder.
> - Empty, collapsed `<details>` placeholders for the deep-dive sections that this plan will need (steps, validation, evidence, alternatives, decision log, risks, diagrams) — each with its heading and a one-line "to be filled" note.
> - Honor the project's design system: if this project's CLAUDE.md has a `## Design system` block, style the page to match it; otherwise use a clean, readable default.
> - Self-contained only: inline CSS, no external scripts or stylesheets, SVG for any diagrams.

The first publish triggers a one-time consent prompt because the page goes to a private `claude.ai` page — that prompt is the meaningful "publishing to claude.ai" confirmation. Let it fire; do not add the `Artifact` tool to the skill's `allowed-tools` to suppress it.

### Step 2: Inspect the result for a URL

A successful publish prints a `https://claude.ai/code/artifact/<id>` URL to the session. Read the result:

- **A `claude.ai` URL came back** → the page is live. Capture the URL and persist it (per §URL persistence): record the page as live and save the URL. Tell the user the page is up and share the link.
- **No `claude.ai` URL — a bare local file path, or a "cannot publish" message** → this session can't publish. Record that the page is unavailable for this run, show the skip notice once (per §Unavailable / skip handling), and do not retry on later phases.

The distinction is the presence of the `claude.ai` URL, nothing else. Don't infer availability from anything but a returned `claude.ai` link.

## Update

Each later phase boundary that produces real content (approaches chosen, sections approved, spec written, final approval) revises the existing page in place and republishes to the same URL — never a fresh page. Revising in place keeps the user's open tab stable and avoids re-rendering the whole document, which both thrashes the view and risks the 16 MiB rendered-size ceiling on a large plan.

### Same-session update

When the page was published earlier in this same session, the file↔URL link still holds, so instruct a silent in-place revision without re-stating the URL:

> Revise the artifact and republish to the same URL: fill the "<section name>" section with <the content just produced>, flip any status that changed, and advance the progress tracker to <current stop>. Keep every other section as-is — revise in place, don't regenerate the page.

### Cross-session / resume update

After a compaction or a new session, the file↔URL link is lost, so the saved URL must be named explicitly or a duplicate page gets created:

> Update <artifact_url> with <the content just produced> for the "<section name>" section, advance the progress tracker to <current stop>, and republish to that same URL. Revise the existing page in place — don't rebuild it.

In both forms, fill only the layers that now have real content and flip the header status badge / progress tracker to match the current stop. Also blank the Current decision panel (per § Content layers): the decision it mirrored just resolved, so leaving it in place would show the user a stale question. At final approval, set the badge to "✅ Approved" and mark every tracker stop done.

### Before-gate update

Just before a substantive decision gate fires in chat, fill the Current decision panel (per § Content layers) with the question the user is about to be asked — the same pending question, its options, and a one-line consequence of each that the chat gate message carries. The user can then read the whole decision on the page while answering in the terminal.

This panel mirrors the chat gate message; it never replaces it. The chat message stays the place the decision is rendered, and the answer is still captured by the terminal `AskUserQuestion`. The page is published and read-only — it has no way to send a click back to the session — so a question shown only on the page would leave the user with nothing to act on, and the chat-side render check still expects the question in chat. Keep the chat render; the panel just mirrors it.

Refresh only the panel, in place — never regenerate the page. The matching after-the-decision Update call blanks the panel once the answer lands (per § Update), so the panel never accumulates stale questions or grows the page toward the 16 MiB ceiling.

Same-session form:

> Revise the artifact and republish to the same URL: fill the "Current decision" panel with <the pending question, its options, and the one-line consequence of each>. Keep every other section as-is — revise in place, don't regenerate the page.

Cross-session / resume form (name the saved URL so no duplicate page is created):

> Update <artifact_url> by filling its "Current decision" panel with <the pending question, its options, and the one-line consequence of each>, and republish to that same URL. Revise the existing page in place — don't rebuild it.

## Content layers

The page is the heart of this feature: a single always-visible summary plus collapsible deep-dive layers, far richer than the terse spec.md the user also gets. The summary layer is always expanded; every deep-dive layer is a native `<details>` collapsed by default. Render a layer only when this plan actually has content for it — an SVG sequence diagram for a plan with no sequence is noise, so omit empty layers entirely rather than showing empty headings.

Reuse the visuals `/plan` already builds at the approach gate, the section-approval gate, and the final-approval gate (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` — borrow the five visual elements there as page-styling guidance: a progress tracker, a one-sentence opener, friendly digest blocks, a visual per unit, and light heading icons). Those elements were defined for chat gate messages; here they style a persistent page, so take the look and the structure but none of the chat mechanics (no question pairing, no turn guard). On the page, go deeper than chat or the spec allow — expanded code examples richer than the spec's terse snippets, full evidence drill-downs, complete alternative write-ups.

**Always-visible summary layer:**

- **Header** — plan title, a status badge (`🚧 In progress N/total` while planning, `✅ Approved` once approved), and a progress tracker over the planning journey (explore · clarify · approach · steps · approval) with the current stop marked. The badge and tracker are the at-a-glance "where is this plan" signal.
- **At a glance** — the objective in one or two sentences, an in-scope / out-of-scope split, the chosen approach in a sentence, and a small SVG data-flow diagram of how the change moves through the system.
- **Current decision** — while a decision gate is open, the question the user is being asked right now, its options, and a one-line consequence of each, styled to match the chat gate render. It mirrors the chat gate message so the user can read the full decision on the page; it sits empty between gates. The page cannot capture the answer — the user answers in the terminal — so this panel shows the decision, it does not collect it. Filled by § Before-gate update, blanked by the next § Update.

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
10. **Before / after** — a side-by-side of the code or behavior as it is now versus as it will be.
11. **Data model / ER / state-machine** — an SVG of the entities, their relationships, or the state transitions the change introduces.
12. **API contracts** — endpoint or function signatures with request and response schemas.
13. **Schema & migrations** — database schema diffs and the ordered migration steps.
14. **Types & data shapes** — the type definitions and data shapes the change adds or alters.
15. **Test plan** — the test cases, example test code, edge cases to cover, and coverage targets.
16. **Security & privacy** — the threat model, plus how auth and sensitive data are handled.
17. **Performance** — the expected impact, the hot paths touched, and any benchmark figures.
18. **Rollout & rollback** — feature flags, the deploy and migration sequence, what to monitor, and how to roll back.
19. **Milestones & timeline** — the ordered milestones for a larger plan.
20. **Dependencies & libraries** — the build-vs-buy calls, chosen versions, install commands, and links.
21. **Links & references** — linked tracker tickets, related pull requests, and the sources the plan cites.
22. **Interactivity** — an in-page search box, jump-to navigation, expand-all / collapse-all controls, and a live changelog of the plan's revisions. These use small inline JavaScript, which is allowed because it makes no external request; keep all script inline (no CDN, no external file).

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
│  ◦ <option A> — <consequence>   ◦ <option B> — <consequence>│
│  ↳ answer in the terminal — this panel only shows it        │
├─────────────────────────────────────────────────────────────┤
│  AT A GLANCE                                                 │
│  Objective: …                                               │
│  In scope: …                Out of scope: …                 │
│  Approach: …                                                │
│  [ SVG data-flow diagram ]                                  │
├─────────────────────────────────────────────────────────────┤
│  ▸ Steps                                          (collapsed)│
│  ▸ Validation & done conditions                   (collapsed)│
│  ▸ Evidence from exploration                      (collapsed)│
│  ▸ Considered alternatives                        (collapsed)│
│  ▸ Decision log                                   (collapsed)│
│  ▸ Risks & mitigations                            (collapsed)│
│  ▸ Architecture / sequence / data-model diagrams  (collapsed)│
│  ▸ API contracts · schema · types                 (collapsed)│
│  ▸ Test plan · security · performance             (collapsed)│
│  ▸ Rollout & rollback · milestones                (collapsed)│
│  ▸ Dependencies · links & references              (collapsed)│
├─────────────────────────────────────────────────────────────┤
│  [search box]  [jump to ▾]  [expand all] [collapse all]     │
│  Revision log: r1 skeleton · r2 approach · r3 steps …       │
└─────────────────────────────────────────────────────────────┘
```

Only sections with real content appear; a plan with no schema change drops the schema row, a plan with no UI drops the data-flow visual. The Current decision panel shows only while a gate is open and is blank otherwise.

## URL persistence

Save the captured `claude.ai` URL into state.md frontmatter so a later session re-targets the same page. There is no partial-field helper — `atomic_state_write` re-writes the whole file, so the caller reads the current state.md, sets the artifact fields, and writes the whole frontmatter back. The pattern, run by the caller after the create step returns a URL:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"

atomic_state_write ".geniro/planning/<task-dir>/state.md" <<EOF
---
tier: T1.5
producer: plan
schema-version: 1
branch: <git-branch>
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
phase: <current-phase>
status: in-progress
non-resumable-actions: []
artifact_mode: true
artifact_status: live
artifact_url: "<captured claude.ai url>"
approvals: [<existing entries preserved>]
---

<existing state.md body preserved verbatim>
EOF
```

Carry the rest of the frontmatter and the whole body through unchanged — the only fields this write touches are `artifact_status` (now `live`) and `artifact_url` (the captured link). Use a fresh `date -u` read in the same Bash call for `timestamp`; never a copied literal.

## Unavailable / skip handling

When the create step gets no `claude.ai` URL back, this session can't publish a live page. Record the page as unavailable for the run, show this notice once, and continue planning in chat:

> A live visual artifact needs a Team or Enterprise plan and a `/login` session — this session can't publish one, so I'll keep planning in chat. Everything else works normally.

Then stop trying for the rest of the run: the unavailable state disarms the update step, so no later phase re-attempts the publish or re-shows the notice. Never half-build a local stand-in file when the native publish is unavailable — the feature is native-only, and a stray local HTML file in the project would just be litter the user has to clean up.

## Caller contract

- **Callers provide:** the task-dir / state.md path, the current phase, the planning-journey stops for the tracker, the content just produced for the layer being filled, and — for a before-gate refresh — the pending question, its options, and each option's one-line consequence.
- **Callers receive:** a persisted `claude.ai` URL with the page recorded as live, or an unavailable signal after the one-time skip notice.
- **Callers are responsible for:** writing the artifact frontmatter fields (`artifact_mode`, `artifact_status`, `artifact_url`) via `atomic_state_write`; guarding every call on `artifact_mode: true`; and additionally skipping the update call when the page is recorded as unavailable.

Invocation strings the callers use, verbatim:

- **Create** (once, at the start of planning): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Availability detection & create`
- **Update** (at later phase boundaries): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Update with PHASE: <phase> and the content just produced`
- **Before-gate update** (just before a substantive gate fires): `apply ${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md § Before-gate update with PHASE: <phase> and the pending question`

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll hand-author an `Artifact(path=, content=)` call." | The native tool is prose-driven — there is no structured call to hand-author. Make the page appear by instructing the model in natural language, steering title, content, and styling through prose. |
| "I'll use Mermaid for the diagrams." | The page runs under a strict content policy that blocks every external request, so a Mermaid CDN script never loads. Draw diagrams as inline SVG or HTML/CSS, which render with no external fetch. |
| "No URL came back — I'll retry the publish each phase." | A missing `claude.ai` URL means this session can't publish at all; retrying every phase just re-fails and re-spams the notice. Record the page as unavailable, show the skip notice once, and stop attempting. |
| "I'll regenerate the whole page from scratch each phase." | A full regen re-renders the whole document, thrashing the user's open tab and pushing a large plan toward the 16 MiB ceiling. Revise the existing page in place and republish to the same URL. |
| "I'll write the artifact source file into `.geniro/planning/<slug>/`." | The native tool owns the artifact's file path, and the state-helper hook guards that directory — fighting it just earns a block. Persist the returned URL, not a hand-placed file. |
| "The user opted in, so I'll suppress the publish consent prompt / add `Artifact` to `allowed-tools`." | The one-time native consent prompt is the meaningful "publishing to a private claude.ai page" confirmation — opting into the artifact is not opting into the publish. Leave the consent prompt in place and keep `Artifact` out of `allowed-tools`. |
| "The page already has the spec content, so a terse copy is enough." | The page exists to go deeper than the spec — expanded code examples, full evidence drill-downs, complete alternative write-ups. A terse mirror of the spec wastes the richer surface. |
| "I'll render every deep-dive section so the page looks complete." | Empty sections are noise the reader has to skip past. Render a layer only when this plan has real content for it; omit the rest entirely. |
| "I'll refresh the Current decision panel before every grill question." | The grill asks many questions one at a time; republishing the page on each would thrash the user's tab and burn tokens for little gain. Refresh the panel only at the substantive gates — the grill checkpoint, the approach gate, each section cluster, and final approval — not at each individual grill question. |
| "I'll put the gate question only on the artifact so the user answers there." | The page is published and read-only — it has no way to send a click back to the session, so a question shown only on the page leaves the user with nothing to act on, and the chat-side render check still expects the question in chat. Always render the gate message in chat and answer the `AskUserQuestion` in the terminal; the panel only mirrors it. |
