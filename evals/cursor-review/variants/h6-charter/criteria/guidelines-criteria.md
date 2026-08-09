# Guidelines review criteria


Check code style and conventions against how the surrounding codebase does it.

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

5. **Comments explaining "why"** — These are good, not obvious
- Explaining business logic or tricky decisions is valuable
- Only flag comments that state the obvious code

6. **Linter conflicts** — If codebase uses specific config
- Project might enforce different style than standard
- Check `.eslintrc`, `prettier.config`, etc.
- Don't flag if matches project config

7. **Tagging documentation gaps as MEDIUM** — Documentation polish, PR-description verbosity, comment wording, and naming suggestions are LOW (never MEDIUM). MEDIUM requires the drift to break or degrade a load-bearing tool consumer. If you are uncertain, default to LOW. LOW sits below the Phase 4.1 admission gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5), so it lands in `## Deferred — sub-threshold` rather than on the PR — for a style finding that is the intended disposition, not a reason to inflate the tier.


