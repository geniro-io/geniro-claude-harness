# Design Review Criteria

Visual and interaction quality for UI changes: tokens, spacing, typography, states, responsive, contrast, a11y polish, and exemplar conformance.

## What to Check

### 1. Token Conformance
- Raw hex/rgb/rgba/hsl values in components instead of semantic tokens
- Hardcoded Tailwind color utilities (`text-white`, `bg-black`) or arbitrary classes (`text-[#abc]`) when a token system exists
- Inline `style={{ color: '#fff' }}` for static colors

**How to detect:**
```bash
grep -nE "#[0-9a-fA-F]{3,8}\b|rgb\(|rgba\(|hsl\(" file.tsx
grep -nE "(text|bg|border|ring|fill|stroke)-\[#" file.tsx
```
**Red flag:** any raw color literal in a project that ships a token system (check `tailwind.config.*`, `theme.ts`, CSS variable files).

### 2. Spacing Scale Conformance
- Magic spacing values that don't map to the project's scale
- Arbitrary Tailwind values like `p-[13px]`, `mt-[27px]`, `gap-[6px]`
- Inline `style={{ padding: '13px' }}` for static spacing

**How to detect:**
```bash
grep -nE "\b(p|m|gap|space|inset|top|right|bottom|left)[trblxy]?-\[" file.tsx
```
**Red flag:** any arbitrary spacing value in a project with a defined scale.

### 3. Typography Conformance
- New font family imports when the project already loads fonts
- Font sizes/weights outside the project's type scale
- Inline `style={{ fontSize: ... }}` or arbitrary `text-[15px]` / `font-[Inter]` classes

**How to detect:**
```bash
grep -nE "font-\[|text-\[|fontFamily|@font-face|@import.*fonts" file.tsx
```
**Red flag:** typographic values that bypass the scale on a project with one.

### 4. Component Variant Invention
- New visual variant of an existing primitive (a third Button shape) instead of composing existing variants
- Custom-built equivalents of components already in the library (custom Modal when a Dialog primitive exists)
- New component file whose responsibility overlaps an existing primitive

**How to detect:**
```bash
ls src/components/ui/ src/components/primitives/ 2>/dev/null
grep -rn "export.*\(Button\|Modal\|Dialog\|Input\|Select\|Card\)" src/components/
```
**Red flag:** new file shipping UI the design system already provides.

### 5. State Completeness
- Interactive elements missing default / hover / active / focus-visible / disabled
- Async or data surfaces missing loading / empty / error branches
- Buttons with no `:disabled` styling, links with no `:hover` feedback

**How to detect:**
```bash
grep -nE "hover:|focus:|focus-visible:|active:|disabled:" file.tsx
grep -nE "(isLoading|loading|isEmpty|error)" file.tsx
```
**Red flag:** any interactive element silently missing one of the five base states, or any async surface without loading/empty/error.

### 6. Responsive Coverage
- Multi-column layout with no breakpoint prefixes (`sm:`, `md:`, `lg:`)
- Horizontal overflow at 375px (fixed widths or min-widths larger than viewport)
- Touch targets smaller than ~44x44 on mobile

**How to detect:**
```bash
grep -nE "\b(sm|md|lg|xl|2xl):" file.tsx
grep -nE "w-\[?[0-9]{3,}|min-w-\[?[0-9]{3,}" file.tsx
```
**Red flag:** a flex/grid layout with multiple columns/rows and zero responsive prefixes.

### 7. WCAG AA Contrast
- Text/background contrast below 4.5:1 (normal) or 3:1 (large text and UI components)
- Light grays on white (`text-gray-400` on `bg-white` is borderline; `text-gray-300` fails)
- Placeholder and disabled-state colors that vanish against their surface

**How to detect:** resolve class pairs to hex values and compute contrast. When Playwright MCP is available, read computed styles directly.
**Red flag:** any low-contrast pair, especially placeholder and disabled colors.

### 8. Keyboard and Accessibility Polish
- `<div onClick>` instead of `<button>` (semantic HTML before ARIA)
- Custom interactive elements without `tabIndex` and keyboard handlers
- `focus:outline-none` without a `focus-visible:ring-*` replacement
- Icon-only buttons without `aria-label`; modal/overlay without ESC handler or focus trap

**How to detect:**
```bash
grep -nE "<div[^>]*onClick" file.tsx
grep -nE "focus:outline-none|outline-none" file.tsx
grep -nE "<button[^>]*>\s*<(svg|Icon)" file.tsx
```
**Red flag:** focus-visible removed without replacement, or clickable `div`/`span` with no role or keyboard handler.

### 9. Exemplar Drift
- New component diverges visually from the named design exemplar (closest existing sibling)
- Different border-radius family, shadow elevation, or spacing rhythm than neighboring components
- Different container pattern (card vs bare panel) at the same hierarchy level

**How to detect:**
```bash
grep -nE "rounded-|shadow-|border-" exemplar.tsx > /tmp/exemplar.txt
grep -nE "rounded-|shadow-|border-" new_file.tsx > /tmp/new.txt
diff /tmp/exemplar.txt /tmp/new.txt
```
**Red flag:** a button, card, or surface that looks nothing like its siblings.

### 10. Hierarchy and Information Density
- Equal visual weight on items of unequal importance (primary/secondary/tertiary actions indistinguishable)
- Walls of text with no scannable hierarchy; dense surfaces (tables, dashboards) without progressive disclosure
- Hover-only critical actions (poor discoverability)

**Red flag:** primary action not visually dominant, or critical actions revealed only on hover.

## Output Format

```json
{
  "type": "design",
  "severity": "critical|high|medium",
  "title": "Visual or interaction quality issue",
  "file": "path/to/Component.tsx",
  "line_start": 42,
  "line_end": 48,
  "description": "Description of the design violation",
  "category": "tokens|spacing|typography|variants|states|responsive|contrast|a11y|exemplar-drift|hierarchy",
  "current": "Current markup/class/style",
  "expected": "Expected pattern per design system",
  "recommendation": "How to fix it",
  "confidence": 88
}
```

## Common False Positives

1. **Greenfield with no design system** — if no token/scale/exemplar exists, tag findings as informational only; skip tokens/spacing/typography/exemplar checks.
2. **Arbitrary Tailwind values as convention** — some projects intentionally use arbitrary values. Check `tailwind.config.*` and existing files before flagging `p-[13px]`-style classes.
3. **Storybook and fixtures** — visual oddities in `*.stories.tsx`, `*.test.tsx`, `__fixtures__/`, and Playwright specs are intentional. Skip.
4. **Marketing/landing pages** — landing routes may legitimately diverge from the app design system; check if a separate system is in scope before flagging drift.
5. **Dark mode via CSS variables** — when files use semantic tokens (`text-foreground`, `bg-card`), contrast applies to the resolved value, not the literal class name.
6. **Inline styles for dynamic values** — `style={{ width: progress + '%' }}` is fine; only flag inline styles for static literals.
7. **Single-state elements** — static badges and labels don't need hover/focus/disabled; state completeness applies only to truly interactive surfaces.

## Stack-Agnostic Patterns

Applies to UI code across frameworks: React/JSX with Tailwind, styled-components, CSS Modules, Emotion, vanilla-extract; Vue, Svelte, Solid, Astro templates; plain HTML + CSS/SCSS; Web Components with Shadow DOM. Skip for pure backend, infrastructure-as-code, CLI tools, build scripts, and any file without visual output.

## Review Checklist

- [ ] No raw color literals in token-driven projects
- [ ] Spacing values come from the scale; no arbitrary magic numbers
- [ ] Typography uses the type scale; no rogue font imports
- [ ] No reinvented primitives that duplicate the design system
- [ ] Interactive elements cover default/hover/active/focus-visible/disabled
- [ ] Async surfaces cover loading/empty/error
- [ ] Non-trivial layouts have responsive breakpoint coverage
- [ ] Contrast meets WCAG AA (4.5:1 normal, 3:1 large/UI)
- [ ] Semantic HTML before ARIA; focus-visible rings present; icon-only buttons labeled; modals trap focus and handle ESC
- [ ] New components match the named exemplar (radius, shadow, rhythm)
- [ ] Hierarchy distinguishes primary/secondary/tertiary; false-positive guards applied (stories, fixtures, marketing, dynamic styles)

## Severity Guidelines

- **CRITICAL**: WCAG AA contrast failures, `focus-visible` removed without replacement, keyboard-inaccessible interactive elements, hardcoded raw colors in a strict-token project.
- **HIGH**: Missing state coverage on interactive surfaces, arbitrary spacing values in a scaled project, exemplar drift, missing responsive handling on multi-column layouts, reinvented primitives.
- **MEDIUM**: Hierarchy and density issues, single missing state on a non-critical element, hover-only secondary actions, minor typography drift, informational findings on greenfield projects.
