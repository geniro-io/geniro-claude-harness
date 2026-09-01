# Guidelines review criteria

Code style, naming conventions, documentation, consistency, and compliance with project standards.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Common false positives

1. **Single-letter vars in small scope** — OK for short lambdas/loops
- `array.map(x => x * 2)` is acceptable
- `for (let i = 0; i < n; i++)` is standard
- Check scope: if var used in 5+ lines, needs better name

2. **Generic names in tests** — Often acceptable for test setup
- `const user = createTestUser`
- `const data = { id: 1, name: 'Test' }`
- Only flag if confusing within test

3. **Pragmatic duplication** — Sometimes better than premature abstraction
- Two similar implementations might have different requirements
- Duplicating for different contexts is acceptable
- Only flag obvious shared logic

4. **Type-safe "any"** — Exceptions exist for special cases
- `JSON.parse` returns any (by design)
- Bridge code to untyped libraries uses any
- Check if there's legitimate reason

5. **Comments explaining "why"** — valuable when they stay true; test durability, not why-ness
- A short comment carrying a durable constraint or business rule is not a finding
- Point-in-time content — change history, measurement notes, directives to a future author — belongs in the change description whatever its subject
- Flag length independent of subject: a block running well past the constraint it carries is change-description text living in the source
- `// retry cap: 3 — upstream rate-limits above that` is fine; a paragraph on how the cap was chosen is not

6. **Linter conflicts** — If codebase uses specific config
- Project might enforce different style than standard
- Check `.eslintrc`, `prettier.config`, etc.
- Don't flag if matches project config

## Severity tagging

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.

- **CRITICAL** — never emitted by this style-rubric class (style findings cannot be CRITICAL; the modal-pattern and authored-rule classes carry their own ceilings in `severity-calibration.md` §3).
- **HIGH** — never emitted by this style-rubric class.
- **MEDIUM** — Convention drift on a tooling-load-bearing field (e.g., missing `risk_class:` in a `.geniro/actions/*.md` that the action runner requires; missing `name:` in a SKILL.md frontmatter that the loader rejects; missing `paths:` in a `review-extra/<slug>.md` that the dispatcher needs). The drift must demonstrably break or degrade a tool that consumes the field. Documentation gaps, comment wording, naming polish, formatting, and style suggestions are NOT MEDIUM — they are LOW.
- **LOW** — Style / formatting / naming polish; documentation gaps; comment wording; comment-rot (stale references, contradictory or low-value comments) on ordinary code; convention drift on optional fields; mismatched-but-non-load-bearing rule violations. Comment-rot rises to MEDIUM only when the inaccurate comment is a load-bearing doc that a tool or generated API surface consumes (e.g., a stale `@param` in a doc-comment that a docs generator publishes) — same load-bearing test as the MEDIUM tier above.

LOW sits below the Phase 4.1 admission gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5), landing in `## Deferred — sub-threshold` rather than on the PR — the intended disposition for a style finding, not a reason to inflate the tier.
