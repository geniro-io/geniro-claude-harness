# Conventions review criteria

Statistical pattern inference across siblings. Flags deviations from the modal pattern when no explicit rule exists. Treats code as a language: sample N siblings, compute frequency per pattern category, take the mode, flag the diff only when one variant is dominant.

Find every real defect this dimension owns by reading the changed code and its callers directly — your own analysis is the detector. The sections below are the contract you are held to: what NOT to flag, and how severity is calibrated.

## Methodology — modal pattern inference

Structural conventions emerge from repetition across a codebase, not from an external style guide. Infer them by sampling the existing code and codifying the dominant pattern.

For every pattern category checked, follow this recipe before emitting any finding:

1. **Explicit authored rules belong to the authored-rule-citation class.** Compliance with the repo's authored rule files (`CLAUDE.md`, `.claude/rules/`, `.cursor/rules/`, `.cursorrules`, `AGENTS.md`, etc.) is the authored-rule-citation class of this dimension, criteria in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/rules-compliance-criteria.md` (the same reviewer spawn reads both files). This file's own checks own repo-MODAL patterns — what the surrounding code actually does, inferred by sampling siblings. When an explicit rule and a modal pattern coincide, cite the rule under the authored-rule-citation class; do not duplicate it here. Still read `CONTRIBUTING.md` + ADRs at `docs/adr/` or `docs/decisions/` for modal context that isn't a hard rule.
2. **Identify the file kind.** Component file? Service? Test? Schema? Migration? Hook? The kind determines which siblings are relevant.
3. **Glob siblings of the same kind.** Same directory first; then analogous directories if the immediate parent has fewer than 3 siblings (`src/components/Button.tsx` → also check `src/ui/`, `packages/*/components/`).
4. **Compute the modal frequency.** For each pattern category, count each variant across siblings.
5. **Apply the 80% modal threshold.** Emit a finding only when one variant accounts for ≥80% of N≥3 siblings.
6. **Skip ambiguous splits.** A 60/40 or three-way split means multiple valid patterns coexist — flagging would be bikeshedding. Stay silent.
7. **Skip when N<3.** Fewer than 3 siblings makes the modal threshold unreliable. Stay silent — too few samples to call a "house style".
8. **Cite the supporting samples.** Every emitted finding lists the sibling paths that establish the modal — a finding with no evidence paths is bikeshedding and is not emitted.

## What this dimension does NOT cover

The conventions reviewer is **structural and semantic**. It ignores anything a linter or formatter handles, and anything covered by another dimension.

**Linter / formatter territory — never flag:**
- Whitespace, indentation, line length, trailing commas, semicolons, brace style, blank-line rules within functions
- Import alphabetization within groups (Prettier / isort / goimports own this)
- Quote style (single vs double)
- Pure aesthetic naming preferences (`userList` vs `users` when both are clear)

Single-exemplar rubric drift signals (default-vs-named export rubric, ADR contradictions, file placement) are **owned here** — emit with modal inference (cite the ADR for ADR-sourced drift). Authored-rule-file citations (CLAUDE.md / `.claude/rules/` / `.cursor/rules/` / etc.) belong to the authored-rule-citation class (`rules-compliance-criteria.md`) per §What to check step 1.

**Out of this class — route:**
- Vague names, magic numbers, missing JSDoc, TODO without issue ref → the style-rubric class (`guidelines-criteria.md`)
- Module-scale organization, utils sprawl, circular imports, file-structure inconsistency at module scale → `architecture-criteria.md`
- Findings that match repo patterns and should be silenced → handled by orchestrator-side Phase 3 dedup + KEEP/FILTER (SKILL.md Phase 3)
- Visual/UI exemplar drift (radius, shadow, spacing rhythm) → `design-criteria.md`
If a finding fits a style/naming/docs rubric mold, it belongs to the style-rubric class (`guidelines-criteria.md`). If a finding requires sampling siblings and computing a mode (repo-modal patterns / single-exemplar rubric drift / ADR contradictions / file placement / convention guard), it belongs to this modal-pattern class.

## Common false positives

1. **Greenfield / N<3 siblings** — Modal threshold unreliable. Skip silently. Do not emit findings. (See Methodology Step 7.)
2. **Modal split (60/40 or three-way)** — Multiple valid patterns coexist. Flagging would be bikeshedding. Stay silent.
3. **Intentional cross-cutting refactor** — The diff applies one transformation across many unrelated-module files, replacing the old pattern rather than adding beside it. That repetition is the modal signal — flag only a changed file that breaks from it.
4. **Migration in progress** — Codebase visibly contains old style + new style coexisting (4/9 old, 5/9 new). Signals "we're moving from A to B"; flag only if the diff regresses to the old pattern.
5. **Test fixtures and stories** — `*.fixtures.ts`, `*.stories.tsx`, `__mocks__/`, `__snapshots__/` legitimately diverge from production siblings. Exclude from sibling globs.
6. **Generated code** — codegen output (`*.gen.ts`, `*.pb.go`), lockfiles, migrations, Prisma client, tRPC types. Skip.
7. **Framework-required patterns** — Next.js `page.tsx` / `layout.tsx`, Svelte `+page.svelte`, Astro `*.astro` pages, NestJS class decorators, Rails models. The framework dictates the kind, so only siblings of the same framework-kind count.
8. **Linter-territory categories** — Quote style, semicolons, alphabetization, indentation, line length. See exclusion list above. The linter handles these; conventions does not.
9. **Tooling configuration files** — `tsconfig.json`, `vite.config.ts`, `package.json`, ESLint config. These are project-level singletons with no meaningful sibling cohort.

## Cross-PR convention drift (peer-PR context)

When the `PEER-PR CONTEXT:` slot is non-`none`, siblings in flight on same target branch ARE part of the modal denominator for recent / in-flight patterns. Inspect kept sibling diffs for convention conflicts:

- Same code kind (helper-placement, naming style, import grouping) introduced with different conventions across parallel PRs — emerging-pattern split, neither has merged yet.
- Sibling PR establishes a new convention (e.g., adopts a new error-handling library) while current PR uses the pre-existing convention — coordination needed on which becomes the modal once both merge.

Apply the 80% modal threshold AT THE MERGE-STATE LEVEL — peer PRs in flight don't yet contribute to the merged modal. A valid finding shape: "PR #N (peer) introduces convention X for <code kind>; current diff uses convention Y. Neither has merged yet — modal not established. Coordinate on which becomes the convention before either ships". Severity HIGH when current PR's pattern is uniquely novel AND peer's pattern matches existing minority precedent; MEDIUM otherwise.

Do NOT apply the modal threshold to peer PRs as if they were merged siblings — that would inflate the denominator with unmerged code. The signal is "two-way coordination needed", not "modal violation".

## Severity guidelines

Scoped to this file's modal-pattern class only — the authored-rule-citation class (`rules-compliance-criteria.md`) keeps its own ceiling, since a rule's severity there follows the impact of breaking it, not the fact that it's a rule.

- **CRITICAL**: never for a modal-pattern finding. Convention drift inferred from sibling sampling is never CRITICAL — bugs and security own that tier. The modal-pattern class caps at HIGH.
- **HIGH**: clear ≥80% modal violation in [NEW] code that introduces a pattern the repo uses nowhere else (zero-shot novel), or crosses a 100%-respected module/layer boundary.
- **MEDIUM**: ≥80% modal violation in [NEW] code where the introduced pattern exists in 1–2 other places (minority but not novel); any [PRE-EXISTING] finding regardless of frequency.
- **LOW**: not emitted. N<3 siblings or modal frequency below 80% means no finding at all — these conditions suppress the finding rather than producing a low-severity one.

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 (this file tightens it for the modal-pattern class only — caps at HIGH, suppresses LOW; see §6). The authored-rule-citation class reads its severity from `rules-compliance-criteria.md` §4 instead — a CRITICAL correctness/security rule violation there is not suppressed to HIGH by this section.
