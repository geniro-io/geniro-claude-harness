# Verification Checks

The `/geniro:setup` verification subagent reads this file during Phase Validate and runs every check below against the generated `CLAUDE.md`. The subagent has Read-only tools (Read, Bash read-only, Glob, Grep) — it reports DRIFT items for the orchestrator to fix in a regeneration round; it never edits any file itself.

---

**Cross-language contamination check (critical):**

For each generated file (CLAUDE.md), verify it contains ONLY the detected stack's content. Use Grep on the generated files to search for wrong-language artifacts:

| If detected language is… | Search for and flag if found: |
|---|---|
| Python | `npm`, `yarn`, `pnpm`, `tsc`, `jest`, `vitest`, ` tsx`, `package.json`, `node_modules`, ````typescript`, ````javascript` |
| TypeScript/JavaScript | `pip`, `pytest`, `ruff`, `pyproject`, `requirements.txt`, `venv`, `__init__`, ````python` |
| Go | `npm`, `pip`, `cargo`, `gem`, ````typescript`, ````python`, ````rust`, ````ruby` |
| Rust | `npm`, `pip`, `go mod`, ````typescript`, ````python`, ````go` |
| Ruby | `npm`, `pip`, `cargo`, ````typescript`, ````python`, ````rust` |
| Java | `npm`, `pip`, `cargo`, `gem`, ````typescript`, ````python`, ````rust`, ````ruby` |

For each wrong-language reference found in a generated file:
1. Read the offending line(s).
2. Decide whether it is a genuine cross-language reference (some projects legitimately use multiple languages, e.g. a monorepo with both Python and TypeScript) or a generation artifact.
3. If it is a generation artifact → report it as a DRIFT item with file:line. The orchestrator removes it during regeneration; a Read-only subagent cannot edit it.
4. If it is legitimate → leave it; do not report.

**Template artifact check:**

Search generated files for phrases that belong in templates, not in production files:
- "customize this", "replace with", "fill in", "TEMPLATE NOTICE"
- "e.g.,", "such as", "for example" followed by multiple framework alternatives
- Parenthetical framework lists like "(Django, Rails, FastAPI, Spring, etc.)"
- "customizable for" — this is template language, not project-specific content

Each match → report as a DRIFT item with file:line so the orchestrator can rewrite the section to be concrete and project-specific.

**Reference example contamination check:**

Verify that the `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/CLAUDE.md.example` content was not copied verbatim:
- The reference example contains generic placeholder content.
- The generated CLAUDE.md must be project-specific, not generic.
- Spot-check: compare a few sections of the generated CLAUDE.md against the reference example. If they are identical (just with placeholders filled in), report a DRIFT item so the orchestrator regenerates the file more thoughtfully.

---

Report findings as the §4.1 output contract requires: `## PASS items` and `## DRIFT items` (one per line, each DRIFT entry with file:line).
