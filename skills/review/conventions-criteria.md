# Conventions Review Criteria

Statistical pattern inference across siblings. Flags deviations from the modal pattern when no explicit rule exists. Treats code as a language: sample N siblings, compute frequency per pattern category, take the mode, flag the diff only when one variant is dominant.

## Contents

- Methodology — Modal Pattern Inference
- What to Check
- What This Dimension Does NOT Cover
- How to Detect — Worked Example
- Output Format
- [NEW] vs [PRE-EXISTING] Tagging
- Common False Positives
- Stack-Agnostic Patterns
- Cross-PR Convention Drift (peer-PR context)
- Review Checklist
- Severity Guidelines

---

## Methodology — Modal Pattern Inference

Per Allamanis et al. NATURALIZE and Microsoft IntelliCode: structural conventions emerge from repetition. Codify them by sampling.

For every pattern category checked, follow this recipe before emitting any finding:

1. **Read explicit conventions first.** Check `CLAUDE.md`, `.claude/rules/`, `AGENTS.md`, `CONTRIBUTING.md`, ADRs at `docs/adr/` or `docs/decisions/`. Explicit rules override modal inference — when an explicit rule exists for the pattern, emit a finding citing the rule; do not duplicate with a modal-inferred finding.
2. **Identify the file kind.** Component file? Service? Test? Schema? Migration? Hook? The kind determines which siblings are relevant.
3. **Glob siblings of the same kind.** Same directory first; then analogous directories if the immediate parent has fewer than 3 siblings (`src/components/Button.tsx` → also check `src/ui/`, `packages/*/components/`).
4. **Compute the modal frequency.** For each pattern category, count each variant across siblings.
5. **Apply the 80% modal threshold.** Emit a finding ONLY if one variant accounts for ≥80% of N≥3 siblings.
6. **Skip ambiguous splits.** A 60/40 or three-way split means multiple valid patterns coexist — flagging would be bikeshedding. Stay silent.
7. **Skip when N<3.** Fewer than 3 siblings makes the modal threshold unreliable. Stay silent — too few samples to call a "house style".
8. **Cite the supporting samples.** Every emitted finding MUST list the sibling paths that establish the modal. No evidence paths → no finding.

The 80% threshold, the N≥3 minimum, and the skip-ambiguous rule are the load-bearing constraints. Apply them at every category — they prevent this dimension from devolving into bikeshedding.

## What to Check

### 1. Sibling-File Consistency

Where things live. A new helper function in a component file when 5 of 6 sibling components keep helpers in `utils.ts`. A new schema declared inline when sibling routes import schemas from `schemas.ts`. A feature folder shipping a single file when 7 of 8 siblings ship a `service + controller + types` triplet.

**How to detect:**
```bash
# Sibling helper-placement modal
ls src/components/
grep -l "from ['\"]\\./utils['\"]" src/components/*.tsx | wc -l
# Triplet-shape modal
for d in src/services/*/; do
ls "$d" | grep -cE "(service|controller|types)\\.ts$"
done
# If ≥80% of N≥3 siblings agree, flag the diff that diverges.
```
**Red flag:** the diff places code in a file kind where ≥80% of siblings put it elsewhere. Skip silently if N<3 or split is ambiguous.

### 2. Mixing of Code Kinds

Functions vs types vs constants vs schemas vs hooks colocated in the same file. Some repos separate them strictly (`types.ts`, `constants.ts`, `hooks.ts`); others colocate. Detect which is the modal and flag the inverse.

**How to detect:**
```bash
# Are sibling files type-pure or mixed?
ls src/services/*/types.ts 2>/dev/null | wc -l
grep -lE "^(export )?(interface|type) " src/services/*/service.ts | wc -l
# Constants in dedicated files?
ls src/**/constants.ts src/**/constants/*.ts 2>/dev/null | wc -l
```
**Red flag:** the diff inlines types into `service.ts` while ≥80% of N≥3 siblings keep `types.ts` separate (or vice versa). Cite the sibling paths.

### 3. Declaration Order Within a File

Imports → constants → types → public exports → helpers. Receiver methods grouped after struct (Go). Class field-order conventions (static fields, instance fields, constructor, public methods, private methods).

**How to detect:**
```bash
# Section ordering across siblings — extract top-level kinds in order
for f in src/services/*/service.ts; do
echo "=== $f ==="
grep -nE "^(import|const|export const|type|interface|export (function|class))" "$f" | head -10
done
# If ≥80% of N≥3 siblings start with imports → constants → types → exports, flag the diff if it reorders.
```
**Red flag:** a class places private methods before public when ≥80% of sibling classes do the opposite. Cite samples.

### 4. Naming Style — Modal Detection

NOT generic naming heuristics — that is `guidelines-criteria.md`'s job (vague names, magic numbers, unclear abbreviations). THIS check is purely sibling-modal: "PR introduced PascalCase filename when 6 of 7 siblings use kebab-case"; "diff added an underscore-prefixed private method when sibling classes use the `#private` syntax".

**How to detect:**
```bash
# Filename casing modal
ls src/components/ | grep -cE "^[A-Z]" # PascalCase
ls src/components/ | grep -cE "^[a-z]+-[a-z]" # kebab-case
ls src/components/ | grep -cE "^[a-z]+[A-Z]" # camelCase
# Pick the variant ≥80% of N≥3 — flag the diff if it deviates.

# Private-method affix modal
grep -hE "^\s+#[a-z]|^\s+_[a-z]|^\s+private " src/services/*.ts | head
```
**Red flag:** the diff introduces a casing or affix style that ≤20% of siblings use. Skip when a configured linter (`@typescript-eslint/naming-convention`, `ruff` `N801/N802/N806`) already enforces this. Always cite samples.

### 5. Import Grouping Mode

Grouping convention only — stdlib / third-party / first-party / relative. Whether groups are separated by a blank line. Whether type imports live in their own group. NOT alphabetization within groups (linter territory).

**How to detect:**
```bash
# Skip if formatter/linter already enforces ordering
grep -lE "import/order|simple-import-sort" .eslintrc* package.json 2>/dev/null
grep -E "^profile.*black|isort" pyproject.toml 2>/dev/null

# Are import groups separated by blank lines?
for f in $(ls src/services/*.ts | head -5); do
echo "=== $f ==="
awk '/^import/ {print; next} /^[^[:space:]]/ {exit}' "$f"
done
# If ≥80% of N≥3 siblings separate first-party from relative with a blank line, flag the diff that inlines them.
```
**Red flag:** the diff jumbles stdlib + third-party + local imports while ≥80% of siblings separate them. Cite samples.

### 6. Error-Handling Pattern Modal

try/catch vs Result types vs sentinel values vs Either monads vs Go-style `(T, error)` returns. Detect what the directory uses and flag the deviation. The modal often differs between layers (controllers throw, services return Results) — sample within the layer, not across.

**How to detect:**
```bash
# Result vs try/catch in a service directory
grep -lE "Result<|Ok\(|Err\(" src/services/*.ts | wc -l
grep -lE "try\s*{|catch\s*\(" src/services/*.ts | wc -l
# Pick the modal — flag if the diff introduces the minority pattern.

# Are errors typed?
grep -nE "class.*Error|extends Error" src/lib/errors.ts 2>/dev/null
```
**Red flag:** 5 of 6 sibling services use Result types but the diff introduces try/catch. Cite the 5 sibling paths.

### 7. Class Construction Pattern

Factory function vs `new` constructor. Static field order. Public-then-private vs grouped-by-feature. Constructor parameter order (`(deps, config)` vs `(config, deps)`). Whether siblings use composition over inheritance.

**How to detect:**
```bash
# Factory vs constructor modal
grep -lE "^export (function|const) create[A-Z]" src/services/*.ts | wc -l
grep -lE "^export class [A-Z].*{" src/services/*.ts | wc -l
# Class member ordering across siblings
for f in $(grep -lE "^export class" src/services/*.ts | head -5); do
echo "=== $f ==="
grep -nE "constructor|public |private |static " "$f" | head -8
done
```
**Red flag:** ≥80% of N≥3 siblings export factory functions but the diff introduces a class with a constructor. Cite samples.

### 8. Module / Layer Boundaries (Intra-File Grain)

Which kinds of imports a file kind is allowed. Controllers that never import directly from `db/`. UI components that never import from `services/api/`. `domain/` that does not import `infrastructure/`. The convention is implicit in what siblings do.

**How to detect:**
```bash
# Do controllers import from db/ in this repo?
grep -lE "from ['\"].*\\bdb/" src/controllers/*.ts
# Do UI components hit api/ directly?
grep -lE "from ['\"].*\\bservices/api" src/components/**/*.tsx
# Reverse-direction sniff
grep -rn "from '@/app'" src/domain/ src/core/ 2>/dev/null
# If 0 of 8 siblings cross the boundary — and the diff does — that is the finding.
```
**Red flag:** the diff crosses a layer boundary that 100% of N≥3 siblings respect. This is the strongest conventions signal — emit at HIGH.

### 9. Sibling File Sample — Step 0

Mandatory before judging anything else. Glob the candidate siblings, count them, record their paths. If N<3, skip the entire dimension for that file. If N≥3 but no category clears 80%, emit nothing.

**How to detect:**
```bash
# Always run this first for each changed file
DIR=$(dirname "$CHANGED_FILE")
KIND_GLOB="*.tsx" # match the changed file's extension/kind
ls "$DIR"/$KIND_GLOB 2>/dev/null | grep -v "$(basename "$CHANGED_FILE")" | head -10
# If fewer than 3 results, broaden to analogous directories before giving up.
```

## What This Dimension Does NOT Cover

The conventions reviewer is **structural and semantic**. It ignores anything a linter or formatter handles, and anything covered by another dimension.

**Linter / formatter territory — never flag:**
- Whitespace, indentation, line length, trailing commas, semicolons, brace style, blank-line rules within functions
- Import alphabetization within groups (Prettier / isort / goimports own this)
- Quote style (single vs double)
- Pure aesthetic naming preferences (`userList` vs `users` when both are clear)

**Other dimensions — defer:**
- Vague names, magic numbers, missing JSDoc, TODO without issue ref → `guidelines-criteria.md`
- Single-exemplar rubric drift signals (default-vs-named export rubric, ADR contradictions, file placement) → owned here (emit with modal inference and/or explicit-rule citation per the recipe at §What to Check).
- Module-scale organization, utils sprawl, circular imports, file-structure inconsistency at module scale → `architecture-criteria.md`
- Findings that match repo patterns and should be silenced → handled by orchestrator-side Phase 3 dedup + KEEP/FILTER (SKILL.md Phase 3)
- Visual/UI exemplar drift (radius, shadow, spacing rhythm) → `design-criteria.md`
If a finding fits a style/naming/docs rubric mold, it is `guidelines`'s job. If a finding requires sampling siblings and computing a mode (repo-modal patterns / single-exemplar rubric drift / ADR contradictions / file placement / convention guard), it is conventions's job.

## How to Detect — Worked Example

A PR adds `src/components/UserCard.tsx`. Reviewer runs the conventions check.

```bash
# Step 0: glob siblings of the same kind
ls src/components/*.tsx | grep -v UserCard.tsx
# Output: Avatar.tsx Badge.tsx Banner.tsx Card.tsx Header.tsx Spinner.tsx Toast.tsx
# N=7 siblings — proceed.

# Category: export style modal
grep -lE "^export default" src/components/*.tsx | wc -l # → 1
grep -lE "^export (function|const) [A-Z]" src/components/*.tsx | wc -l # → 6
# 6/7 = 86% use named exports. Modal threshold met.

# Inspect the diff
grep "^export" src/components/UserCard.tsx
# → export default function UserCard(...)
```

Finding emitted: `[NEW] export default in src/components/UserCard.tsx; 6 of 7 sibling components use named exports without default. evidence_paths: [Avatar.tsx, Badge.tsx, Banner.tsx, Card.tsx, Header.tsx, Toast.tsx]`. Severity HIGH (clear ≥80% violation, evidence cited).

Counter-example: same PR, but only 2 sibling components exist (`Avatar.tsx`, `Card.tsx`). N<3 — skip silently. No finding.

Counter-example: 4 of 7 siblings use named exports, 3 use default. 57% — ambiguous split, multiple valid patterns coexist. Skip silently. No finding.

## Output Format

```json
{
"type": "conventions",
"severity": "high|medium",
"title": "Convention drift in <file>",
"file": "path/to/file.tsx",
"line_start": 42,
"line_end": 48,
"description": "What the diff does and what the modal pattern is",
"category": "sibling-consistency|mixing-of-kinds|declaration-order|naming-style|import-grouping|error-handling|class-construction|module-boundary",
"current": "Current pattern in the diff",
"modal_pattern": "What ≥80% of N≥3 siblings do",
"evidence_paths": ["src/components/Avatar.tsx", "src/components/Badge.tsx", "src/components/Card.tsx"],
"modal_frequency": "6/7",
"tag": "[NEW]|[PRE-EXISTING]",
"recommendation": "Match the modal pattern:...",
"confidence": 85
}
```

The `evidence_paths` field is **mandatory**. Every finding MUST cite the supporting sample paths or it is not emitted. A finding without evidence paths is bikeshedding — the threshold is structural, not opinion.

## [NEW] vs [PRE-EXISTING] Tagging

Style findings on legacy code are noise. Use the diff context pre-inlined by the orchestrator (the same field bugs and security reviewers receive) to tag every finding:

- **[NEW]** — code in lines added or modified by the diff. The diff introduces a pattern that diverges from the modal. Prioritized in the report.
- **[PRE-EXISTING]** — finding lives on an unchanged line, surfaced because the reviewer read the file while sampling. The file was already an outlier before this change. Demoted to MEDIUM at most. Informational only.

Reviewers should never block a PR on [PRE-EXISTING] convention drift. If pre-existing drift dominates the file, surface it as a single informational note rather than a per-line flood. The Phase 3 §3.3 KEEP/FILTER judgment demotes [PRE-EXISTING] findings — just tag accurately.

## Common False Positives

1. **Greenfield / N<3 siblings** — Modal threshold unreliable. Skip silently. Do not emit findings. (See Methodology Step 7.)
2. **Modal split (60/40 or three-way)** — Multiple valid patterns coexist. Flagging would be bikeshedding. Stay silent.
3. **Intentional cross-cutting refactor** — When the PR introduces a new convention deliberately, the modal still reflects the OLD pattern. Check the PR description for refactor intent before flagging — a refactor PR's whole point is changing the modal.
4. **Migration in progress** — Codebase visibly contains old style + new style coexisting (4/9 old, 5/9 new). Signals "we're moving from A to B"; flag only if the diff regresses to the old pattern.
5. **Test fixtures and stories** — `*.fixtures.ts`, `*.stories.tsx`, `__mocks__/`, `__snapshots__/` legitimately diverge from production siblings. Exclude from sibling globs.
6. **Generated code** — codegen output (`*.gen.ts`, `*.pb.go`), lockfiles, migrations, Prisma client, tRPC types. Skip.
7. **Framework-required patterns** — Next.js `page.tsx` / `layout.tsx`, Svelte `+page.svelte`, Astro `*.astro` pages, NestJS class decorators, Rails models. The framework dictates the kind, so only siblings of the same framework-kind count.
8. **Linter-territory categories** — Quote style, semicolons, alphabetization, indentation, line length. See exclusion list above. The linter handles these; conventions does not.
9. **Tooling configuration files** — `tsconfig.json`, `vite.config.ts`, `package.json`, ESLint config. These are project-level singletons with no meaningful sibling cohort.

## Stack-Agnostic Patterns

Most categories generalize across TypeScript/JavaScript, Python, Go, Rust, Ruby, Kotlin, Java, Swift, C#: sibling-consistency, mixing-of-kinds, naming-style, import-grouping, error-handling, module-boundary all read at the conceptual level even when concrete syntax differs (e.g., "modal error-handling pattern" reads as try/catch in JS, Result in Rust, errors-as-values in Go, exceptions in Python).

A few categories are language-specific:

- **Declaration order** depends on language conventions: Go groups receiver methods after the struct; Rust groups `impl` blocks; TypeScript classes follow access-modifier order; Python frequently uses dunder-method ordering.
- **Type-import policy** is TypeScript-specific (`import type` vs runtime imports).
- **Package privacy** differs: Go uses lowercase exports; Java uses `package-private`; Rust uses `pub(crate)`. The modal still applies but the variants change.
- **Class construction** is irrelevant in functional-only codebases (Elm, Elixir).

When a category does not apply to the language, skip it — do not force-fit.

## Cross-PR Convention Drift (peer-PR context)

When the `PEER-PR CONTEXT:` slot is non-`none`, siblings in flight on same target branch ARE part of the modal denominator for recent / in-flight patterns. Inspect kept sibling diffs for convention conflicts:

- Same code kind (helper-placement, naming style, import grouping) introduced with different conventions across parallel PRs — emerging-pattern split, neither has merged yet.
- Sibling PR establishes a new convention (e.g., adopts a new error-handling library) while current PR uses the pre-existing convention — coordination needed on which becomes the modal once both merge.

Apply the 80% modal threshold AT THE MERGE-STATE LEVEL — peer PRs in flight don't yet contribute to the merged modal. A valid finding shape: "PR #N (peer) introduces convention X for <code kind>; current diff uses convention Y. Neither has merged yet — modal not established. Coordinate on which becomes the convention before either ships". Severity HIGH when current PR's pattern is uniquely novel AND peer's pattern matches existing minority precedent; MEDIUM otherwise.

Do NOT apply the modal threshold to peer PRs as if they were merged siblings — that would inflate the denominator with unmerged code. The signal is "two-way coordination needed", not "modal violation".

## Review Checklist

- [ ] Read explicit convention sources (CLAUDE.md,.claude/rules/, AGENTS.md, ADRs) before sampling
- [ ] Step 0 sibling glob run for every changed file; N≥3 confirmed before judging
- [ ] 80% modal threshold applied per category; ambiguous splits skipped
- [ ] Sibling-file consistency: helpers placed where ≥80% of siblings put them
- [ ] Mixing of code kinds matches the directory's modal (colocated vs separated)
- [ ] Declaration order within file follows the modal section sequence
- [ ] Naming style (filename casing, private affix) matches the modal; linter-handled rules skipped
- [ ] Import grouping mode matches the modal (groups, blank lines, type-import policy); formatter-handled cases skipped
- [ ] Error-handling pattern matches the directory's modal (try/catch vs Result vs Go-style)
- [ ] Class construction pattern matches the modal (factory vs constructor, member order)
- [ ] Module/layer boundaries respected — diff does not cross a 100%-respected boundary
- [ ] Every emitted finding cites `evidence_paths` with concrete sibling paths and `modal_frequency`
- [ ] [NEW] vs [PRE-EXISTING] tag set on every finding; pre-existing capped at MEDIUM

## Severity Guidelines

- **CRITICAL**: never. Convention drift is never CRITICAL — bugs and security own that tier. Conventions caps at HIGH.
- **HIGH**: clear ≥80% modal violation in [NEW] code that introduces a pattern the repo uses nowhere else (zero-shot novel), or crosses a 100%-respected module/layer boundary.
- **MEDIUM**: ≥80% modal violation in [NEW] code where the introduced pattern exists in 1–2 other places (minority but not novel); any [PRE-EXISTING] finding regardless of frequency.
- **LOW**: not emitted. N<3 siblings or modal frequency below 80% means no finding at all — these conditions suppress the finding rather than producing a low-severity one.
