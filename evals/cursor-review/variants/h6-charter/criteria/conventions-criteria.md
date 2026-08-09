# Conventions review criteria


Check consistency with the repo's own modal patterns.

## Common false positives

1. **Greenfield / N<3 siblings** — Modal threshold unreliable. Skip silently. Do not emit findings. (See Methodology Step 7.)
2. **Modal split (60/40 or three-way)** — Multiple valid patterns coexist. Flagging would be bikeshedding. Stay silent.
3. **Intentional cross-cutting refactor** — When the PR introduces a new convention deliberately, the modal still reflects the OLD pattern. Check the PR description for refactor intent before flagging — a refactor PR's whole point is changing the modal.
4. **Migration in progress** — Codebase visibly contains old style + new style coexisting (4/9 old, 5/9 new). Signals "we're moving from A to B"; flag only if the diff regresses to the old pattern.
5. **Test fixtures and stories** — `*.fixtures.ts`, `*.stories.tsx`, `__mocks__/`, `__snapshots__/` legitimately diverge from production siblings. Exclude from sibling globs.
6. **Generated code** — codegen output (`*.gen.ts`, `*.pb.go`), lockfiles, migrations, Prisma client, tRPC types. Skip.
7. **Framework-required patterns** — Next.js `page.tsx` / `layout.tsx`, Svelte `+page.svelte`, Astro `*.astro` pages, NestJS class decorators, Rails models. The framework dictates the kind, so only siblings of the same framework-kind count.
8. **Linter-territory categories** — Quote style, semicolons, alphabetization, indentation, line length. See exclusion list above. The linter handles these; conventions does not.
9. **Tooling configuration files** — `tsconfig.json`, `vite.config.ts`, `package.json`, ESLint config. These are project-level singletons with no meaningful sibling cohort.


## Severity guidelines

- **CRITICAL**: never. Convention drift is never CRITICAL — bugs and security own that tier. Conventions caps at HIGH.
- **HIGH**: clear ≥80% modal violation in [NEW] code that introduces a pattern the repo uses nowhere else (zero-shot novel), or crosses a 100%-respected module/layer boundary.
- **MEDIUM**: ≥80% modal violation in [NEW] code where the introduced pattern exists in 1–2 other places (minority but not novel); any [PRE-EXISTING] finding regardless of frequency.
- **LOW**: not emitted. N<3 siblings or modal frequency below 80% means no finding at all — these conditions suppress the finding rather than producing a low-severity one.

Canonical decision rules: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1 (the conventions dim tightens it — caps at HIGH, suppresses LOW; see §6).
