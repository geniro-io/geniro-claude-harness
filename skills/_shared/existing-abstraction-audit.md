# Existing Abstraction Audit

Canonical procedure for "before creating new code, check what already exists." Consumed by `/geniro:refactor` Phase 2 (smell detection), `/geniro:deep-simplify` Pass A (Reuse & Duplication), and `/geniro:implement` Phase 5 (Simplify). Define ONCE here; reference from N consumers.

## When to run

Before recommending any of:
- "Extract to a new shared utility / helper / hook / module"
- "Replace this with a new wrapper / facade / abstraction"
- "Create a new file under `utils/` / `lib/` / `shared/` for this"

## Procedure

1. **Identify candidate analogues.** From the duplication or smell under review, derive 1-3 search terms:
   - Function name fragments (e.g., `formatDate`, `validateEmail`, `retryWith`)
   - Behavioral keywords (e.g., `debounce`, `memoize`, `parse`, `serialize`)
   - Type / signature fragments where applicable

2. **Grep designated helper directories.** Run Grep (case-insensitive, regex) across the project's conventional helper directories:
   - `utils/`, `lib/`, `shared/`, `helpers/`, `services/`
   - Plus any project-specific directories named in CLAUDE.md
   - Also check barrel files: `index.*` at module roots

3. **Categorize each candidate** found:
   - **REUSE-AS-IS** — analogue solves the same problem with the same shape; replace duplication with a call site to the existing analogue.
   - **EXTEND** — analogue solves a closely-related problem; a small extension (no new parameters that complicate its current shape) covers this case.
   - **NO-ANALOGUE** — nothing comparable exists; a new abstraction is justified ONLY when the Rule of Three applies (≥3 distinct call sites).

4. **Do NOT force-fit.** If extending an existing analogue requires adding a parameter, conditional, or generic that complicates its current shape, prefer pragmatic local duplication. The "wrong abstraction" is more expensive than the duplication it replaces.

5. **Rule of Three.** Do NOT recommend extraction on the second occurrence. Require ≥3 distinct call sites before proposing a new shared helper. With only 2 sites, the axis of variation is unknown — premature extraction encodes the wrong shape. Pragmatic local duplication is the correct outcome until the third occurrence.

## Output format

When invoked from a finding, emit one or more of:
- `reuse-as-is: <file:line>` — analogue already solves this problem; replace at the call site
- `extend-existing: <file:line> — <one-line justification>` — analogue should absorb this case via small extension
- `no-analogue: rule-of-three=<met|not-met>, call-sites=N` — no comparable analogue exists; the orchestrator weighs whether ≥3 sites justify a new helper

The orchestrator weighs these tags against the finding before applying or proposing the change.

## Anti-rationalization

| Reasoning | Why it's wrong |
|---|---|
| "I already see it duplicated twice — extract now" | Two sites = unknown axis of variation. Wait for the third. Sandi Metz: "Duplication is far cheaper than the wrong abstraction." |
| "I'll add an optional parameter to the existing helper to fit this case" | That's force-fitting. The next caller adds another optional parameter, and the helper becomes a pile of orthogonal flags. Prefer local duplication. |
| "Skip the Grep — I know that helper doesn't exist" | Project layouts vary, helpers move, your memory of the repo may be stale. The Grep takes 2 seconds and the audit is the single source of truth. |
| "Extend it anyway — the parameter complication is small" | Small parameter complications compound. Each one masks the original abstraction's intent. Today's optional flag is tomorrow's bug. |
