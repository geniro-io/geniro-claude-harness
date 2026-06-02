# Improvement Routing (canonical)

## Contents

- §Routing table — improvement type → target file
- §Decision logic when target is ambiguous
- §ADR target — when to use it (sparingly)
- §Why code rules go to `.claude/rules/`, not CLAUDE.md
- §Presentation — how to surface the routed suggestion

When a skill's end-of-flow "Suggest Improvements" step finds a project-scope improvement, classify it by **routing target** using the table below. **Project scope only** — do NOT route to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/agents/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/**`, `${CLAUDE_PLUGIN_ROOT}/hooks/**`); the plugin is installed globally and overwritten on update. Plugin-file improvements belong to a separate channel — submit a PR to the plugin repo OR edit your local plugin install directly (out of scope for skill-level "Suggest Improvements").

## Routing table

| What was discovered | Route to | Why |
|---|---|---|
| New/changed build, test, or lint command | **CLAUDE.md** | Loaded every turn for every agent — commands must be always at hand |
| Tech stack or project structure change | **CLAUDE.md** | Future sessions need current project shape |
| Project-wide gate that must survive compaction (e.g. "never commit without approval") | **CLAUDE.md** | Reserved for critical compaction-surviving guidance |
| **File-pattern-scoped** code rule (e.g., language-specific, directory-specific) | **`.claude/rules/<scope>.md`** with YAML frontmatter `paths: [glob, ...]` (Anthropic-native, **file-scoped** — auto-loads only when Claude reads/writes a matching file) | **Loaded only when the matching files are touched — keeps CLAUDE.md lean and avoids "rule bloat" that dilutes compliance for every CLAUDE.md rule. The native Claude Code analog of Cursor's `.mdc` auto-attach.** |
| **Cross-cutting code-style / convention rule that should apply to ALL code-writing and ALL review (regardless of file pattern)** | **`.geniro/instructions/code-style.md`** (Geniro cross-skill scope; authored via `/geniro:instructions create code-style`) | Loaded by `implement` (Phase 1 / Phase 3 entry), `refactor` (Phase 1 / Phase 3 entry), `review` (Phase 1 entry); pre-inlined into reviewer-agent prompts for the guidelines / conventions / design / architecture dimensions. Use this when the rule is style-adjacent and applies project-wide, not gated on a glob. |
| Quality gate, workflow step, or hard constraint the user enforced for **skill behavior** (e.g. "always run codegen after editing DTOs", "max PR size 500 lines") | **`.geniro/instructions/<skill>.md`** (or `global.md` if cross-skill) | Geniro-specific **skill-scoped** — loads when the matching skill runs, not on every file edit |
| Pattern that should be enforced automatically without LLM judgment | **Project rules/hooks** (CI, lint, project-local hooks) | Automated enforcement beats manual memory |
| Non-obvious gotcha, workaround, or debugging insight | **Knowledge** (`.geniro/knowledge/learnings.jsonl`, path resolved per `_shared/primary-worktree.md`) | Searchable across sessions via `lib/query-learnings.sh` (loaded at every pipeline skill's Phase 1) |
| Architectural decision with rationale (lightweight, internal) | **Knowledge** (`.geniro/knowledge/learnings.jsonl`, path resolved per `_shared/primary-worktree.md`) | Provides context for future changes in the same area |
| Architectural decision that is **(1) hard to reverse, (2) surprising without context, AND (3) the result of genuine trade-offs** — including refactor candidates explicitly REJECTED with rationale | **ADR** (`docs/adr/NNNN-<slug>.md` or `docs/decisions/NNNN-<slug>.md`) | Survives team turnover and shipped code; the durable record for "why we chose / rejected X" when learnings.jsonl is too transient |
| User preference or correction about how to collaborate | **Memory** (native auto-memory) | Auto-retrieved by Claude in future sessions |

## Decision logic when target is ambiguous

Apply in order — first match wins:

1. **Can a linter, formatter, CI check, or hook enforce it without LLM judgment?** → **Project rules/hooks**
2. **Is it a code rule that genuinely needs file-pattern scoping (language-specific, directory-specific) — i.e., should fire only when matching files are read/written?** → **`.claude/rules/<scope>.md`** with `paths:` glob (file-scoped, Anthropic-native)
2.5. **Is it a cross-cutting code-style / convention rule that should apply to all code-writing and all review (no file pattern)?** → **`.geniro/instructions/code-style.md`** (Geniro cross-skill scope)
3. **Is it a quality gate / workflow step / hard constraint that should fire when a particular skill runs (not per-file)?** → **`.geniro/instructions/<skill>.md`** (skill-scoped, Geniro-specific)
4. **Is it a project-wide command, structure fact, or compaction-surviving gate that every agent needs every turn?** → **CLAUDE.md**
5. **Is it an architectural decision that is hard to reverse AND surprising without context AND the result of genuine trade-offs (including a refactor candidate explicitly REJECTED with rationale)?** → **ADR** (`docs/adr/` or `docs/decisions/` — see ADR rules below)
6. **Is it a reusable technical insight (gotcha, lightweight architectural decision, surprising coupling)?** → **Knowledge** (`.geniro/knowledge/learnings.jsonl` — path resolved per `_shared/primary-worktree.md`)
7. **Is it a user preference or correction about how to collaborate?** → **Memory** (native auto-memory)
8. **Uncertain** → default to **Knowledge** (lowest risk, still searchable)

## ADR target — when to use it (sparingly)

Architecture Decision Records survive code, sessions, and team turnover. Use them only when **all three** criteria hold:

1. **Hard to reverse** — undoing the decision later requires non-trivial migration (e.g., choice of database engine, auth model, monorepo vs polyrepo, sync vs async API).
2. **Surprising without context** — a future reader (human or agent) would ask "why did we do this?" and not infer the answer from the code alone.
3. **Genuine trade-offs** — the decision had real alternatives with real upsides; this is not "we picked the obvious option."

If any criterion fails → use **Knowledge** (`learnings.jsonl`) instead. Most architectural choices are NOT ADRs — bias toward learnings.

### Where to write

- Look for an existing `docs/adr/`, `docs/decisions/`, or `doc/adrs/` directory (per `/geniro:setup` Phase 1 detect-output step §1.6).
- If none exists, propose creating `docs/adr/` only after user confirms via `AskUserQuestion`.
- Filename: `NNNN-<short-slug>.md` where NNNN is the next sequential number (zero-padded). Use Glob to find the highest existing NNNN.

### ADR template (when creating)

```markdown
# NNNN. <Decision title — verb + object>

**Status:** Accepted | Superseded by NNNN | Rejected
**Date:** YYYY-MM-DD

## Context
What was the situation that forced a decision? What constraints applied?

## Decision
What did we choose? State it as a single sentence at the top.

## Alternatives considered
- **Option A** — pros / cons / why rejected
- **Option B** — pros / cons / why rejected

## Consequences
What do we accept by choosing this? What becomes harder? What becomes easier?

## References
- Related ADRs (NNNN), commits, learnings, or external sources
```

### Skills that route to ADR

- `/geniro:investigate` save-routing step — "Save key findings to memory" gains an ADR sub-option when the finding meets all 3 criteria.
- `/geniro:debug` — root causes traced to an undocumented architectural choice trigger an ADR proposal alongside the L2 emit.
- `/geniro:refactor` — refactor candidates explicitly REJECTED by the user (PRODUCT-DECISION findings, escalated work) propose an ADR capturing "why we did NOT do X." 4th AUQ option fires only when ADR-eligibility criteria met (hard to reverse + surprising without context + genuine trade-offs).
- `/geniro:implement` Phase 3 ship sub-step presents ADR alongside CLAUDE.md / `.claude/rules/` / instructions / knowledge targets, grouped per usual.

## Why code rules go to `.claude/rules/`, not CLAUDE.md

CLAUDE.md is loaded **every turn for every agent**, so its budget is finite — Anthropic's official guidance is **<200 lines** and "rule bloat" is a documented anti-pattern: each added line dilutes compliance for *every* CLAUDE.md rule, including the high-value ones. Code rules / coding conventions / style patterns only need to fire **when matching files are read or written** — Anthropic-native `.claude/rules/<scope>.md` files with `paths:` YAML frontmatter provide exactly that file-scoped auto-attach. Anthropic, Cursor, GitHub Copilot, and the AGENTS.md spec have all converged on this split: always-on global file + path-scoped rules files.

### Three-tier rules: file-scoped, skill-scoped, cross-skill

| Mechanism | Path | Triggers when | Use for |
|---|---|---|---|
| **Anthropic-native rules file** | `.claude/rules/<scope>.md` with `paths: [glob, ...]` frontmatter | Claude reads/writes a file matching the glob | Code rules, coding conventions, style/naming patterns, file-pattern constraints, language-specific rules |
| **Geniro instructions file** | `.geniro/instructions/<skill>.md` (or `global.md`) | The matching skill (`implement` / `plan` / `review` / `debug` / `refactor` / `onboard` / `investigate`) starts a run | Skill-behavior customization: extra workflow steps, quality gates, hard constraints applied at skill phase boundaries |
| **Geniro cross-skill code-style file** | `.geniro/instructions/code-style.md` | A Geniro pipeline skill (`implement` / `refactor` / `review`) starts a code-writing or review phase | Cross-cutting code-style / convention rules that apply to ALL code writing and ALL review (regardless of file pattern). Pre-inlined into 4 style-adjacent reviewer-agent dimensions (guidelines, conventions, design, architecture). |

The three are complementary, not overlapping. Choose based on the trigger you want:
- **File-scoped** (`.claude/rules/`) fires per-edit when a matching glob touches a file. Use for language-specific or directory-specific rules.
- **Skill-scoped** (`.geniro/instructions/<skill>.md`) fires when the matching skill runs. Use for workflow steps, quality gates, hard constraints specific to one skill's lifecycle.
- **Cross-skill code-style** (`.geniro/instructions/code-style.md`) fires when ANY pipeline skill enters a code-writing or review phase. Use for project-wide style/naming/convention rules that don't need file-pattern scoping.

**Reserve CLAUDE.md for:** commands, tech-stack/structure facts, and project-wide gates that must survive context compaction. Code rules go to `.claude/rules/` (per file-pattern) or `.geniro/instructions/code-style.md` (cross-cutting); skill-behavior rules go to `.geniro/instructions/<skill>.md`.

## Presentation

For each improvement, draft `target / file / change / why`. Present via `AskUserQuestion` with header "Improvements" and options `Apply all` / `Review one-by-one` / `Skip`. Group by target so the user sees what goes where. If no improvements found, skip silently.
