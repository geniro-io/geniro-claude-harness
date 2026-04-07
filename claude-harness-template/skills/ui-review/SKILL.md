---
name: ui-review
description: "Visual review of UI via Playwright screenshots. Compares against expected layouts. Checks responsive design, visual consistency, accessibility basics, broken layouts. Produces review report in .claude/.artifacts/planning/UI_REVIEW.md."
context: fork
model: sonnet
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_resize, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_fill_form, mcp__plugin_playwright_playwright__browser_press_key, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_close]
argument-hint: "[URL or page path to review]"
---

# UI Review: Visual & Accessibility Inspection

Use this skill to visually inspect UI components, pages, or full flows. Automates screenshot-based review to catch layout issues, responsive design problems, accessibility gaps, and visual inconsistencies. Useful for: pre-release QA, design system validation, responsive design testing, accessibility spot-checks.

## Review Dimensions

| Dimension | What to Check | Tools |
|-----------|---------------|-------|
| **Layout** | No broken layouts, proper spacing, no overflow | Playwright, CSS inspection |
| **Responsive** | Design works at desktop, tablet, mobile sizes | Viewport resizing, screenshots |
| **Consistency** | Colors, fonts, spacing match design system | CSS inspection via browser_evaluate, DOM snapshot via browser_snapshot |
| **Accessibility** | Alt text, ARIA labels, keyboard navigation, contrast | browser_snapshot (accessibility tree), browser_press_key (keyboard nav), browser_evaluate (ARIA/alt-text checks) |
| **Functionality** | Buttons clickable, forms work, links navigate | Interactive testing |
| **Performance** | Page loads quickly, no jank, smooth animations | browser_evaluate (Performance API), browser_network_requests |

## Workflow: Capture → Inspect → Report

### 0. Pre-flight
- If the URL or page path is unclear, use `AskUserQuestion` to ask the user which pages to review and at what viewport sizes
- If Playwright fails to load the page (network error, timeout, auth wall), use `AskUserQuestion` to ask the user for a corrected URL or credentials before retrying
- **Playwright check:** Attempt to call `browser_navigate` to `about:blank`. If the tool is unavailable or returns an error, use the `AskUserQuestion` tool (do NOT output as plain text) to inform the user: "Playwright MCP server is not installed. Install with: `claude mcp add playwright -- npx @playwright/mcp@latest` and restart Claude Code." Stop the skill.

### 1. Capture Screenshots
- Take screenshots at user-specified viewport sizes, or defaults (desktop: 1920x1080, tablet: 768x1024, mobile: 375x667)
- Capture key user flows (login → dashboard → settings)
- Highlight interactive elements (buttons, forms, modals)
- Document scroll depth and overflow states
- Use `browser_take_screenshot` with explicit `filename` parameter (e.g., `desktop-homepage.png`, `mobile-settings.png`). Screenshots are saved by the MCP server. Verify files exist after capture.

### 2. Inspect Visually
For each screenshot:
- **Layout:** Check for broken grids, misaligned elements, unexpected wrapping
- **Typography:** Verify fonts, sizes, line-height consistency
- **Colors:** Check computed colors via `browser_evaluate` with `getComputedStyle()`. Compute WCAG contrast ratios manually.
- **Spacing:** Check padding, margins match design system
- **Responsive:** Does it reflow properly? Any cutoff text?
- **Accessibility:** Visible focus states, sufficient contrast, semantic HTML

### 3. Test Interactively
- Click buttons, fill forms, submit
- Test keyboard navigation (Tab key, Enter)
- Inspect accessibility tree via `browser_snapshot` — verify ARIA roles, labels, and semantic HTML structure
- Check loading states and error messages

### 4. Report Findings
Generate `.claude/.artifacts/planning/UI_REVIEW.md` with:
- Screenshot gallery (key views)
- Findings grouped by severity (critical, major, minor)
- Before/after if fixes were tested
- Accessibility findings (from accessibility tree inspection and ARIA checks)
- Responsive design matrix (✓ works, ✗ broken at sizes)

## UI_REVIEW.md Format

```markdown
# UI Review Report

**Date:** 2026-04-03 | **Scope:** Dashboard | **Sizes:** Desktop, Tablet, Mobile

## Summary

| Metric | Status | Notes |
|--------|--------|-------|
| Layout | ✓ | No breaks at any size |
| Typography | ✓ | Consistent |
| Colors | ⚠ | Contrast issue on primary button |
| Responsive | ✓ | Works at all sizes |
| Accessibility | ⚠ | Missing alt text on 2 icons |
| Forms | ✓ | Functional |
| Performance | ✓ | TTFB: 0.3s, DOM loaded: 0.8s, Full load: 1.2s (via Performance API) |

## Findings by Severity

### Critical Issues
*None found.*

### Major Issues
*None found.*

### Minor Issues

1. **Contrast Issue:** Primary button (#4A90E2) WCAG AA ratio 3.2:1 (needs 4.5:1)
   - Fix: Darken to #2563EB

2. **Missing Alt Text:** Dashboard widget icons lack aria-label
   - Fix: Add aria-label="widget name" to each

3. **Modal Close Button:** 32x32px (Apple HIG recommends 44x44px at mobile)

## Responsive Design

| Component | Desktop | Tablet | Mobile |
|-----------|---------|--------|--------|
| Header | ✓ | ✓ | ✓ |
| Sidebar | ✓ | ✓ | Hamburger |
| Task List | ✓ | ✓ | ✓ |
| Forms | ✓ | ✓ | Full-width |

## Accessibility Checklist

- [ ] Screenshots at desktop (1920x1080), tablet (768x1024), mobile (375x667)
- [ ] Keyboard navigation tested (Tab, Enter, Escape)
- [ ] Color contrast verified (WAVE scan)
- [ ] Alt text on images and icons
- [ ] Focus indicators visible
- [ ] Form validation displays properly
- [ ] Performance metrics recorded

```

## Compliance — Do Not Cut Corners

| Your reasoning | Why it's wrong |
|---|---|
| "It looks fine visually" | Visual appearance lies. Measure contrast ratios and touch target sizes with tools. |
| "We'll add accessibility later" | Later never comes. Check accessibility now — missing alt text and non-functional buttons are blockers. |
| "Desktop looks good, ship it" | Most users are on mobile. Test at real viewport sizes (320px, 375px, 768px, 1024px). |
| "Something looks off here" | Vague reports waste developer time. Record specific measurements and concrete fixes. |
| "Let me fix this while I'm reviewing" | Review and implementation don't mix. Report findings only — let the implementer fix them. |

## Definition of Done

For each UI review, confirm:

- [ ] All pages/components reviewed at desktop, tablet, mobile sizes
- [ ] Screenshots captured and documented
- [ ] Layout checked for breaks, overflow, alignment
- [ ] Typography and colors verified against design spec
- [ ] Responsive design tested and confirmed working
- [ ] Accessibility basics checked (contrast, alt text, keyboard nav)
- [ ] Interactive elements tested (buttons, forms, navigation)
- [ ] Performance metrics recorded
- [ ] UI_REVIEW.md generated in .claude/.artifacts/planning/
- [ ] Issues categorized by severity (critical/major/minor)
- [ ] Recommendations provided with estimated effort

---

## When to Use This Skill

**Use `/ui-review`:**
- Before releasing a page or feature to production
- Validating a new design system component
- Testing responsive design across viewport sizes
- Spot-checking accessibility compliance
- Pre-QA verification before handing to testers
- Design system validation after updates

**Don't use:**
- Quick visual check (use browser dev tools)
- Need to implement visual changes (use `/implement`)
- Detailed user testing or usability research (different process)
- Backend or API testing (use `/debug`)

---

## Examples

### Example 1: Review New Dashboard
```
/ui-review /dashboard --viewport desktop,tablet,mobile --focus layout
```
→ Screenshot dashboard at three sizes
→ Check for layout breaks, responsive flow
→ Test interactive widgets
→ Report: layout ✓, responsive ✓, minor spacing issue at tablet
→ Generate UI_REVIEW.md with findings

### Example 2: Accessibility Audit
```
/ui-review /settings --focus accessibility
```
→ Screenshot settings page
→ Test keyboard navigation (Tab through all fields)
→ Check color contrast (WAVE scan)
→ Test with screen reader basics
→ Report: 1 contrast issue (fix suggested), all fields keyboard-accessible
→ Generate report with remediation steps

### Example 3: Pre-Ship QA
```
/ui-review --viewport desktop,tablet,mobile
```
→ Full review of current page
→ Desktop, tablet, mobile screenshots
→ Layout, typography, colors, responsive, accessibility
→ Report all findings (critical/major/minor)
→ Recommend fixes before shipping
