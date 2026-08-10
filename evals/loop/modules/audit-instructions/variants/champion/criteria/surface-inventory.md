## Surface inventory (canonical)

One row per tool. Phase 0 enumerates the path column with Glob to build the run's inventory; a surface absent from the repo drops out of scope, and its absence feeds D6's coverage check when the tool shows other signs of use. The loading notes are D5's rubric input: what a file costs depends on when its tool loads it.

| Tool | Paths | Format & loading notes |
|---|---|---|
| Claude Code | `CLAUDE.md` (root and nested per-directory), `CLAUDE.local.md`, `.claude/rules/*.md`, `.claude/skills/**/SKILL.md`, `.claude/agents/*.md`, `.claude/commands/*.md` | Root CLAUDE.md and CLAUDE.local.md load whole every session (always-on; line budget owned by `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` §"Why code rules go to `.claude/rules/`, not CLAUDE.md"); nested CLAUDE.md loads lazily when its directory is touched and is not re-injected after compaction; .claude/rules/*.md scope via paths: frontmatter (no paths: = always-on); skills route via frontmatter description; commands load on explicit invocation. An unbackticked @path token in CLAUDE.md is an import (cycles and dead targets break the chain); AGENTS.md is NOT read natively — it reaches Claude Code only via an @AGENTS.md import or a symlink |
| Cross-tool standard | `AGENTS.md` (root and nested) | Read whole by Codex, Cursor, Copilot, and most newer agents; commonly symlinked to or generated from CLAUDE.md — endorsed, see §Do-not-flag list. Codex assembles the instruction chain under a ~32 KiB default cap and truncates silently past it — an oversized root file loses its tail with no error |
| Cursor | `.cursor/rules/*.mdc`; legacy `.cursorrules` | .mdc frontmatter: description / globs / alwaysApply. alwaysApply: true = every session; globs = attached when a matching file is in context; description alone = model-requested; none of the three = the rule can never activate. A plain .md file in .cursor/rules/ is silently ignored. Official guidance: keep each rule under 500 lines. .cursorrules is the deprecated single-file form |
| GitHub Copilot | `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md` | copilot-instructions.md attaches to every request (always-on; official guidance: within ~2 pages); .instructions.md scopes via applyTo frontmatter glob |
| Windsurf | `.windsurf/rules/*.md`; legacy `.windsurfrules` | Legacy single-file form deprecated |
| Cline | `.clinerules` (file or directory) | Loaded whole |
| Gemini CLI | `GEMINI.md` | Loaded whole |
| Aider | `CONVENTIONS.md` | Loaded whole when configured |
| JetBrains Junie | `.junie/guidelines.md` | Loaded whole |
| Zed | `.rules` | Loaded whole |
| Amazon Q | `.amazonq/rules/*.md` | Loaded whole |
| Geniro | `.geniro/instructions/*.md` | In scope for every dimension; per-file structural lint alone is owned by `/geniro:instructions validate` — route structural findings there instead of duplicating that lint |

**Scope boundaries.**
- User-global files (`~/.claude/CLAUDE.md`, per-user Cursor or Copilot settings) live outside the repo and are out of scope.
- `CLAUDE.local.md` and other personal-overlay files are in scope for accuracy and safety, but a personal preference differing from the team files is the overlay's design, not drift.

**Activity signals.** Alongside the surfaces, record per tool whether the repo shows the tool in active use — its config or state directories (`.cursor/`, `.windsurf/`, `.claude/`), CI jobs invoking it, its lockfiles or settings committed. D6's "tool in use, no instructions" check consumes this; a coverage claim without an activity signal is speculation.

