# Plan artifact — house visual design language

**Load the native `artifact-design` skill first, before any HTML.** It owns the general methodology: grounding the look in the subject, the compact color / type / layout token plan, typeface pairing, chosen neutrals, both light and dark themes, the AI-default looks not to spend a free axis on, motion restraint, and structure that encodes meaning rather than decorates. Everything below is only what that skill cannot know — which treatment this page takes, the component vocabulary later fills reuse, and the rendering rules `/geniro:plan`'s content depends on.

Precedence when guidance collides: the user's own words, then the project's `## Design system` tokens if CLAUDE.md declares one, then the house calls here, then the native skill's defaults.

Apply this on the create step AND on every later per-phase update or before-gate fill that adds a section, panel, or layer (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` loads it before writing any HTML, and re-loads it on a cross-session update where it has fallen out of context).

## Treatment — editorial, grounded in this plan

The native skill asks you to read the request and calibrate the treatment. That read is already answered here: run its **editorial** branch. The page's whole reason to exist is to be the richest, most visual surface of the plan, so a neutral "clean readable" theme is the failure mode — it is the same look the page would carry for any plan, and it reads as templated. Derive the direction from *this* plan's subject: a telemetry surface, a billing flow, and an auth refactor should not come out looking identical.

The page is a document, not a dashboard — but its status badge, progress tracker, and state marks are the operated parts, so encode their state in form as well as in words.

## House components

The page is built from a small named set that every later fill reuses rather than re-invents: an **eyebrow** (mono, uppercase, wide-tracked) naming the real section above its heading — `RUNTIME · ONE CRON TICK`; a **card** one surface-step above the ground; a **code pill**; a collapsed `<details>` deep-dive layer; the header **status badge** and **progress tracker**; and a faint graph-paper **grid ground** that gives the field texture without competing with content. Spend the page's one bold move on a **signature element** that embodies the plan's subject — most often the lead data-flow diagram.

## Diagrams are the visual language

Every structural relationship — data flow, component architecture, before/after, and the data layer's schema — is authored as inline `<svg>` (or an HTML/CSS box-and-connector layout when SVG would be overkill). Hand-author these even though the native skill steers generative graphics toward Canvas: a plan's diagrams are small, labelled, and have to stay legible and selectable. A monospace `<pre>` ASCII tree is the chat fallback, never the artifact standard — it is exactly the flat, text-only result the artifact exists to replace, so a `<pre>` used as a diagram is a defect, not a shortcut. Which diagrams a given plan renders: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` § Content layers.

## Code & data tokens

Render inline code and JSON examples as styled token pills, not flat `<pre>` dumps — one inline-styled `<span>` per token in a conventional developer syntax palette (distinct hues for keys, strings, numbers, booleans, null, and punctuation), with identifiers and constants on a subtly tinted background pill. This needs no external highlighter, so it survives the page's content policy. The project's `## Design system` tokens win over the developer palette when CLAUDE.md declares one.

## State marks

Plan content carries states the page has to mark — retired, absent, stale, current, and the 2xx / 3xx / 4xx-5xx classes on the data layer. Give each a semantic hue held separate from the accent AND a distinct form: strikethrough for a retired item, a dashed border for an absent slot, a diagonal-stripe fill for stale, solid accent for current. Encoding both ways keeps the state readable without color, and any such system needs a small legend to be legible at all.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "It's an internal planning doc, so the utilitarian treatment is the right read." | The page exists to be the richest surface of the plan, and a templated report is the exact outcome it was built to replace. Run the native skill's editorial branch and ground the direction in this plan's subject. |
| "An ASCII `<pre>` tree shows the same structure." | A monospace tree is the flat, text-only output the artifact exists to replace. Author flow, architecture, before/after, and the data layer as inline `<svg>` or an HTML/CSS box-and-connector layout. |
| "The native skill covers design, so I can skip the house file." | It cannot know this page's treatment is already decided, that structural diagrams are hand-authored SVG here, or which component classes the page's later fills must reuse — the failure shows up as a second section that looks nothing like the first. |
| "The design language is loaded once at create, so later updates inherit it." | Each per-phase update and before-gate fill authors NEW content (a section, the decision panel, a data layer), and after a compaction or in a new session this file is out of context — a fill done without it drifts to a generic look while the rest of the page stays art-directed. Re-load this file on a cross-session update, and author every filled section, panel, and layer with the page's existing tokens and component classes. |
