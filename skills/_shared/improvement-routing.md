# Improvement Routing (canonical)

When a skill's end-of-flow "Suggest Improvements" step finds a project-scope improvement, classify it by **routing target** using the table below. **Project scope only** — do NOT route to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/agents/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/**`, `${CLAUDE_PLUGIN_ROOT}/hooks/**`); the plugin is installed globally and overwritten on update, plugin-file improvements belong to `/improve-template`.

## Routing table

| What was discovered | Route to | Why |
|---|---|---|
| New/changed build, test, or lint command | **CLAUDE.md** | Loaded every turn for every agent — commands must be always at hand |
| Tech stack or project structure change | **CLAUDE.md** | Future sessions need current project shape |
| Project-wide gate that must survive compaction (e.g. "never commit without approval") | **CLAUDE.md** | Reserved for critical compaction-surviving guidance |
| **Code rule / coding convention / style or naming pattern / file-pattern constraint** | **`.claude/rules/<scope>.md`** with YAML frontmatter `paths: [glob, ...]` (Anthropic-native, **file-scoped** — auto-loads only when Claude reads/writes a matching file) | **Loaded only when the matching files are touched — keeps CLAUDE.md lean and avoids "rule bloat" that dilutes compliance for every CLAUDE.md rule. The native Claude Code analog of Cursor's `.mdc` auto-attach.** |
| Quality gate, workflow step, or hard constraint the user enforced for **skill behavior** (e.g. "always run codegen after editing DTOs", "max PR size 500 lines") | **`.geniro/instructions/<skill>.md`** (or `global.md` if cross-skill) | Geniro-specific **skill-scoped** — loads when the matching skill runs, not on every file edit |
| Pattern that should be enforced automatically without LLM judgment | **Project rules/hooks** (CI, lint, project-local hooks) | Automated enforcement beats manual memory |
| Non-obvious gotcha, workaround, or debugging insight | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Searchable by knowledge-retrieval-agent across sessions |
| Architectural decision with rationale | **Knowledge** (`.geniro/knowledge/learnings.jsonl`) | Provides context for future changes in the same area |
| User preference or correction about how to collaborate | **Memory** (native auto-memory) | Auto-retrieved by Claude in future sessions |

## Decision logic when target is ambiguous

Apply in order — first match wins:

1. **Can a linter, formatter, CI check, or hook enforce it without LLM judgment?** → **Project rules/hooks**
2. **Is it a code rule / coding convention / style or naming pattern / file-pattern constraint that needs LLM compliance when editing matching files?** → **`.claude/rules/<scope>.md`** with `paths:` glob (file-scoped, Anthropic-native)
3. **Is it a quality gate / workflow step / hard constraint that should fire when a particular skill runs (not per-file)?** → **`.geniro/instructions/<skill>.md`** (skill-scoped, Geniro-specific)
4. **Is it a project-wide command, structure fact, or compaction-surviving gate that every agent needs every turn?** → **CLAUDE.md**
5. **Is it a reusable technical insight (gotcha, architectural decision, surprising coupling)?** → **Knowledge** (`.geniro/knowledge/learnings.jsonl`)
6. **Is it a user preference or correction about how to collaborate?** → **Memory** (native auto-memory)
7. **Uncertain** → default to **Knowledge** (lowest risk, still searchable)

## Why code rules go to `.claude/rules/`, not CLAUDE.md

CLAUDE.md is loaded **every turn for every agent**, so its budget is finite — Anthropic's official guidance is **<200 lines** and "rule bloat" is a documented anti-pattern: each added line dilutes compliance for *every* CLAUDE.md rule, including the high-value ones. Code rules / coding conventions / style patterns only need to fire **when matching files are read or written** — Anthropic-native `.claude/rules/<scope>.md` files with `paths:` YAML frontmatter provide exactly that file-scoped auto-attach. Anthropic, Cursor, GitHub Copilot, and the AGENTS.md spec have all converged on this split: always-on global file + path-scoped rules files.

### Two-tier rules: file-scoped vs. skill-scoped

| Mechanism | Path | Triggers when | Use for |
|---|---|---|---|
| **Anthropic-native rules file** | `.claude/rules/<scope>.md` with `paths: [glob, ...]` frontmatter | Claude reads/writes a file matching the glob | Code rules, coding conventions, style/naming patterns, file-pattern constraints, language-specific rules |
| **Geniro instructions file** | `.geniro/instructions/<skill>.md` (or `global.md`) | The matching skill (`implement` / `plan` / `review` / `debug` / `follow-up` / `refactor`) starts a run | Skill-behavior customization: extra workflow steps, quality gates, hard constraints applied at skill phase boundaries |

The two are complementary, not overlapping: a file-scoped code rule fires on every edit to matching files; a skill-scoped instruction fires only when the user invokes that skill. Choose based on **what triggers the rule**: the file being touched (file-scoped) vs. the skill being run (skill-scoped).

**Reserve CLAUDE.md for:** commands, tech-stack/structure facts, and project-wide gates that must survive context compaction. Code rules go to `.claude/rules/`; skill-behavior rules go to `.geniro/instructions/`.

## Presentation

For each improvement, draft `target / file / change / why`. Present via `AskUserQuestion` with header "Improvements" and options `Apply all` / `Review one-by-one` / `Skip`. Group by target so the user sees what goes where. If no improvements found, skip silently.
