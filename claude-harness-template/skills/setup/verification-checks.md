# Verification Checks

This file is read by the `/setup` skill during Phase 4 verification. Read this file using the Read tool and run all checks.

---

**Cross-language contamination check (critical):**

For each generated file (backend-agent, frontend-agent, rules files, review criteria files), verify it contains ONLY the detected stack's content. Use Grep on the generated files to search for wrong-language artifacts:

| If detected language is… | Search for and flag if found: |
|---|---|
| Python | `npm`, `yarn`, `pnpm`, `tsc`, `jest`, `vitest`, ` tsx`, `package.json`, `node_modules`, ````typescript`, ````javascript` |
| TypeScript/JavaScript | `pip`, `pytest`, `ruff`, `pyproject`, `requirements.txt`, `venv`, `__init__`, ````python` |
| Go | `npm`, `pip`, `cargo`, `gem`, ````typescript`, ````python`, ````rust`, ````ruby` |
| Rust | `npm`, `pip`, `go mod`, ````typescript`, ````python`, ````go` |
| Ruby | `npm`, `pip`, `cargo`, ````typescript`, ````python`, ````rust` |
| Java | `npm`, `pip`, `cargo`, `gem`, ````typescript`, ````python`, ````rust`, ````ruby` |

If any wrong-language reference is found in a generated file:
1. Read the offending line(s)
2. Determine if it's a genuine cross-language reference (some projects legitimately use multiple languages) or a generation artifact
3. If artifact → remove it using Edit tool
4. If legitimate (e.g., a monorepo with both Python and TypeScript) → keep it

**Template artifact check:**

Search generated files for phrases that belong in templates, not in production files:
- "customize this", "replace with", "fill in", "TEMPLATE NOTICE"
- "e.g.,", "such as", "for example" followed by multiple framework alternatives
- Parenthetical framework lists like "(Django, Rails, FastAPI, Spring, etc.)"
- "customizable for" — this is template language, not project-specific content

If found → rewrite the section to be concrete and project-specific.

**Review criteria contamination check:**

For each generated criteria file (`skills/review/*-criteria.md`), verify:
- No `file.js` or `file.ts` references remain (unless the project IS JavaScript/TypeScript)
- No `npm audit` / `npm list` commands remain (unless the project uses npm)
- No "Stack-Agnostic Patterns" section remains (should have been removed during generation)
- Grep patterns use the correct file extension for the detected language
- Framework-specific checks are present (e.g., Django N+1 for Python/Django projects)

If any template-era JS patterns remain in a non-JS project's criteria → rewrite the offending sections.

**Reference example contamination check:**

Verify that none of the `_reference/*.example` content was copied verbatim:
- The reference files contain generic multi-language examples for all possible stacks
- Generated files must be project-specific, not generic
- Spot-check: compare a few sections of each generated file against its reference example. If they're identical (just with placeholders filled in), the file needs to be regenerated more thoughtfully.
