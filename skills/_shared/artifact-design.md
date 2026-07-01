# Plan artifact — visual design language

The house design language for the `/geniro:plan` visual artifact. Apply it whenever you author or substantially re-author the page — the create step AND every later per-phase update or before-gate fill that adds a section, panel, or layer (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` loads this first before writing any HTML, and re-loads it on a cross-session update where it has fallen out of context). The job is a single self-contained HTML page — inline CSS, inline SVG, no external requests — that reads as if it were art-directed for *this* plan's subject, not a generic readable default. A "clean default" is the failure this file exists to prevent: it reads as templated and AI-generated. The page should look deliberate, opinionated, and specific to the system being planned.

The specific palette, type, and layout values below are illustrative: you own those choices and derive them from this plan's subject. What is required is the methodology — ground the look in the subject, avoid the generic defaults, render diagrams as SVG, and defer to the project's design system when it declares one; the exact hues, sizes, and spacing are yours to set.

## Contents

- The failure this prevents — why a clean default is the wrong target
- Ground the design in the subject — derive identity from the plan, not a stock palette
- Two-pass method — plan a token system, critique it, build, critique again
- Design tokens — color, type, surface, rhythm
- The signature element — spend boldness in one place
- Structure encodes meaning — eyebrows, numbering, state marks
- Diagrams are the visual language — inline SVG, never an ASCII `<pre>`
- Code & data tokens — styled token pills
- Motion — deliberate, inline-only, reduced-motion-safe
- Quality floor — responsive, accessible, self-contained
- Worked default — a disposable illustration of the techniques (author your own tokens)
- Anti-rationalization

## The failure this prevents

A plan artifact that uses a neutral, "clean readable" theme reads as templated — the same look the page would have for any plan. AI-generated design clusters around three recognizable defaults, and they appear regardless of subject:

1. Warm cream background with a high-contrast serif display and a terracotta accent.
2. Near-black background with a single bright acid-green or vermilion accent.
3. Broadsheet layout with hairline rules, zero border-radius, and dense newspaper columns.

All three are legitimate for *some* brief, but reaching for one by reflex spends a design choice on a default. Where the project's design system or the plan's subject pins a direction, follow it exactly. Where an axis is free, do not spend that freedom on a stock look — make a choice grounded in the subject.

## Ground the design in the subject

Distinctive choices come from the subject's own world — its domain, its instruments, its vocabulary. Before authoring, pin a one-line creative direction: name the subject (the system this plan changes), its audience (who reads the plan), and the page's single job (let a reader grasp the design without opening the spec). State the direction in a sentence, then derive every color and type decision from it.

Defer to the project first:

- If this project's `CLAUDE.md` has a `## Design system` block, adopt its tokens exactly — palette, type, spacing. The project's identity outranks any default here.
- If there is no design-system block, derive an identity from the plan's subject and domain, using the §Worked default below as the floor, not the answer.

A telemetry/coverage surface, a billing flow, and an auth refactor should not look identical. The example that motivates this guide deliberately avoided the phosphor-green radar cliché and chose a deep slate ground with one warm accent *because* the subject was a control surface — the choice fit the brief.

## Two-pass method

Plan before you build, then critique before you ship. Do this in your thinking; show the user the published page, not the deliberation.

1. **Plan a compact token system** — four parts:
   - **Color** — 4–6 named hex values: a ground, one or two surface steps, hairline lines, body text, muted text, and a single vivid accent. Add semantic state hues (success / warning / info) only if the plan's content has states to mark.
   - **Type** — at least two roles: a characterful display face used with restraint, a readable body face, and a monospace utility face for eyebrows, labels, code, and data. Set a real type scale with intentional weights and letter-spacing.
   - **Layout** — a one-sentence layout concept and rhythm (single editorial column with a wide measure is the right register for an RFC-style plan).
   - **Signature** — the one element the page is remembered by (see §The signature element).
2. **Critique the plan against the brief** — ask: *would I produce this same token system for any plan?* If yes, the choice is a default; revise the part that reads generic and note what changed and why.
3. **Build** the page from the revised tokens, deriving every value from them.
4. **Critique again** — remove one accessory. Cut any decoration that does not serve the plan. Restraint is what separates art-directed from busy.

## Design tokens

- **Color.** Choose a ground derived from the subject and register — an RFC-style plan wants a calm, low-chroma field that gives diagrams and code room to read, whichever direction (dark, light, or tinted) the brief and any project design system point to. Use one vivid accent as the page's voice — apply it to the thesis word, section eyebrows, and the signature element, and almost nowhere else. Keep body text muted, headings bright. Semantic state colors (a teal for valid/covered, a magenta for stale/breaking, a violet for secondary) earn their place only when the content marks states; used everywhere they become noise.
- **Type.** Display headings are large, tight in line-height, and heavy — the headline is the hero, not a label over a paragraph. Body sits at a comfortable reading size with generous line-height and muted color. The monospace utility face carries eyebrows (uppercase, wide letter-spacing, small, accent-or-muted), inline code, data labels, and figure captions — it is the page's "telemetry" voice and signals "this is a technical document."
- **Surface & structure.** A faint grid or graph-paper ground (a low-opacity textured layer) gives the field texture without competing with content. Quiet dividers separate sections. Cards sit one surface-step above the ground with a subtle border and an optional top edge tinted by the card's semantic role.
- **Rhythm.** Generous vertical space between sections; a content measure that keeps prose comfortably readable (roughly 60–75 characters per line is the typographic comfort zone — pick the exact width for your type and layout); consistent padding inside cards. Whitespace is the cheapest way to read as deliberate rather than cramped.

## The signature element

Spend boldness in one place. Pick a single device that embodies the plan's subject and make it the one memorable thing — a glowing connector that ties a list to its outcome, a coverage grid with a legend, an oversized thesis headline with the key word in the accent, a state-machine drawn as inline SVG. Let everything around the signature stay quiet and disciplined. A page with one strong idea and calm surroundings lands harder than one with five competing effects.

## Structure encodes meaning

Structural devices should encode something true about the content, not decorate it.

- **Eyebrows** (a short label above a heading, styled in the Type token's mono face) name the real section — `RUNTIME · ONE CRON TICK` — and orient the reader.
- **Numbered markers** (`01 / 02 / 03`) are right only when the content is a genuine sequence — an ordered process, a typed timeline — where order carries information. Do not number a set that has no order.
- **State marks** encode each state distinctly and carry meaning at a glance — for example strikethrough for a retired/removed item, a dashed border for a missing/absent slot, a diagonal-stripe fill for a stale state, a solid accent for the healed/current one; choose the glyphs that fit the content. Pair any such system with a small legend so the marks are legible.

## Diagrams are the visual language

Every structural relationship — data flow, component architecture, before/after, and the data layer's schema — is authored as inline `<svg>` (or an HTML/CSS box-and-connector layout when SVG would be overkill). A monospace `<pre>` ASCII tree is the chat fallback, never the artifact standard: it is exactly the flat, text-only result the artifact exists to replace, so a `<pre>` used as a diagram is a defect, not a shortcut. The full per-layer diagram contract (data-flow, architecture, before/after, the ER/typed-JSON data layer) lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` § Content layers — this file owns the *look*, that file owns *which* diagrams a plan renders.

## Code & data tokens

Render inline code and JSON examples as styled token pills, not flat `<pre>` dumps — one inline-styled `<span>` per token, colored with a conventional developer syntax palette (distinct hues for keys, strings, numbers, booleans, null, and punctuation — your exact colors, tuned to the page's accent); identifiers and constants get a subtle tinted background pill. This needs no external highlighter and stays within the content policy. Defer the palette to the project's `## Design system` tokens when CLAUDE.md declares one.

## Motion

Use motion deliberately. One orchestrated moment — a page-load reveal sequence, a scroll-triggered fade-and-rise as sections enter — lands harder than scattered effects, and over-animation is itself a tell that a page was AI-generated. A short list that serves the page:

- A single entrance: sections fade and rise as they scroll into view (a small inline `IntersectionObserver` is allowed — it makes no external request).
- A smooth `<details>` expand/collapse for the deep-dive layers.
- At most one ambient touch on the signature element (a slow pulse on a connector dot, say) — and only if it earns its place.

Respect `prefers-reduced-motion: reduce` — disable transforms and ambient loops under it. Keep all CSS and JS inline; no CDN, no external file — the page runs under a content policy that blocks every external request, so an external animation library never loads.

## Quality floor

Build to a floor without announcing it:

- **Responsive** down to a 375px mobile width — the editorial column reflows, diagrams scale or scroll, nothing clips.
- **Accessible** — visible keyboard focus on every interactive control, sufficient text-vs-ground contrast, real heading order.
- **Reduced-motion** honored (above).
- **Self-contained** — inline CSS + inline SVG + optional inline JS only; zero external requests. Keep examples representative (a few rows, a trimmed body), so the page stays under the per-response token cap and the 16 MiB rendered ceiling.

## Worked default

A disposable illustration of how the techniques wire together, NOT a stylesheet to copy. Adopt the *techniques* (grid ground, type scale, eyebrow, card edge, code pill, scroll reveal); author your own tokens and derive every color, type metric, size, spacing value, and radius from the plan's subject rather than shipping the values below.

```html
<style>
  /* =============================================================
     DISPOSABLE ILLUSTRATION — do NOT copy this as a theme.
     It shows how the techniques wire together (grid ground, type
     scale, eyebrow, card edge, code pill, reveal). Author your own
     tokens: derive every color, size, and radius from THIS plan's
     subject. The palette values are placeholders, not a stylesheet.
     ============================================================= */
  :root {
    --ground:    /* page field — derive from subject */ ;
    --surface:   /* cards — derive from subject */ ;
    --surface-2: /* nested surfaces — derive from subject */ ;
    --line:      /* dividers — derive from subject */ ;
    --text:      /* headings / strong — derive from subject */ ;
    --muted:     /* body / labels — derive from subject */ ;
    --accent:    /* the one voice — thesis word, eyebrows, signature — derive from subject */ ;
    --valid:     /* semantic: covered / compatible — derive from subject */ ;
    --stale:     /* semantic: stale / breaking — derive from subject */ ;
    --info:      /* semantic: secondary — derive from subject */ ;
    --display:   /* display heading font: large, tight, heavy — set for your type choice */ ;
    --mono:      /* monospace utility font: eyebrows, code, labels — set for your type choice */ ;
    --measure:   /* content measure ~60–75ch — set for your type and layout */ ;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; color: var(--text); background: var(--ground);
    font: 400 1.0625rem/1.65 system-ui, sans-serif;
    /* faint graph-paper grid ground */
    background-image:
      linear-gradient(var(--line) 1px, transparent 1px),
      linear-gradient(90deg, var(--line) 1px, transparent 1px);
    background-size: 48px 48px;
    background-blend-mode: soft-light;
  }
  main { max-width: 980px; margin: 0 auto; padding: clamp(2rem, 6vw, 6rem) 1.5rem; }
  .eyebrow { font: var(--mono); letter-spacing: 0.18em; text-transform: uppercase;
             color: var(--accent); margin-bottom: 0.75rem; }
  h1.thesis { font: var(--display); letter-spacing: -0.02em; margin: 0 0 1rem; }
  h1.thesis .key { color: var(--accent); }
  p { color: var(--muted); max-width: var(--measure); }
  .card { background: var(--surface); border: 1px solid var(--line);
          border-radius: 14px; padding: 1.5rem 1.75rem; position: relative; overflow: hidden; }
  .card[data-role]::before { content: ""; position: absolute; inset: 0 0 auto 0; height: 2px; }
  .card[data-role="valid"]::before   { background: var(--valid); }
  .card[data-role="stale"]::before   { background: var(--stale); }
  .card[data-role="accent"]::before  { background: var(--accent); }
  code, .tok { font: var(--mono); background: color-mix(in srgb, var(--info) 16%, transparent);
               color: var(--text); padding: 0.1em 0.4em; border-radius: 5px; }
  details > summary { cursor: pointer; list-style: none; }
  details { transition: background 0.2s ease; }
  :focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
  .reveal { opacity: 0; transform: translateY(14px); transition: opacity .6s ease, transform .6s ease; }
  .reveal.in { opacity: 1; transform: none; }
  @media (prefers-reduced-motion: reduce) {
    .reveal { opacity: 1; transform: none; transition: none; }
  }
</style>
<script>
  // inline-only, no external request: fade-and-rise sections as they enter
  addEventListener("DOMContentLoaded", () => {
    const io = new IntersectionObserver((es) => es.forEach(e => {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }), { threshold: 0.12 });
    document.querySelectorAll(".reveal").forEach(el => io.observe(el));
  });
</script>
```

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "A clean, readable default theme is the safe choice." | A neutral default reads as templated — the same look for every plan. The page should look art-directed for this plan's subject. Pin a creative direction grounded in the subject, then derive the tokens from it. |
| "I'll reach for a near-black background with one bright accent — it looks technical." | That is one of the three recognizable AI defaults. It's fine only when the subject or the project's `## Design system` pins it. Where the axis is free, make a choice specific to the subject instead of spending it on a stock look. |
| "More animation makes the page feel polished." | Over-animation is a tell that a page was AI-generated. One orchestrated moment (a scroll reveal) plus a smooth `<details>` is enough; add an ambient touch only on the signature, and honor `prefers-reduced-motion`. |
| "An ASCII `<pre>` tree shows the same structure." | A monospace tree is the flat, text-only output the artifact exists to replace. Author flow, architecture, before/after, and the data layer as inline `<svg>` or HTML/CSS box-and-connector. |
| "Numbered `01 / 02 / 03` markers everywhere make it look structured." | Numbering encodes order — use it only when the content is a genuine sequence. On an unordered set it's decoration pretending to be meaning. |
| "I'll spend the accent color across every heading, link, and border." | Spreading the accent flattens it. Spend boldness in one place — the thesis word, the eyebrows, and the signature — and keep everything else quiet so the accent still reads as the page's voice. |
| "The design language is loaded once at create, so later updates inherit it." | Each per-phase update and before-gate fill authors NEW content (a section, the decision panel, a data layer), and after a compaction or in a new session this file is out of context — a fill done without it drifts to a generic look while the rest of the page stays art-directed. Re-load this file on a cross-session update, and author every filled section, panel, and layer with the page's existing tokens and component classes. |
