# Geniro Plugin

Production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/geniro:setup` | AI-driven project setup — scans codebase, interviews you, generates CLAUDE.md |
| `/geniro:implement` | Full-featured implementation with architecture review and multi-agent execution |
| `/geniro:decompose` | Decompose a Big task into 3-7 independently shippable milestones; hands off to `/geniro:implement milestone <N>` |
| `/geniro:review` | Parallel 7-agent code review (bugs, security, architecture, tests, optimizations, guidelines, conventions). `--tdd` flag (or startup AUQ) gates PR comments on F→P-verified failing tests. |
| `/geniro:debug` | Scientific-method bug investigation with hypothesis tracking |
| `/geniro:follow-up` | Quick post-implementation changes (trivial/small scope) |
| `/geniro:deep-simplify` | Three-pass parallel code review for reuse, quality, and efficiency |
| `/geniro:refactor` | Restructure code with zero behavior change guarantee |
| `/geniro:instructions` | Manage custom instruction files — create, list, edit, validate, delete. Scopes: `global`, the 7 pipeline skills, and `code-style` (cross-cutting style rules loaded at every code-writing & review step). |
| `/geniro:actions` | Create, edit, run, and remove custom workflow-helper actions stored in `.geniro/actions/` (Slack/PR/release automations) |
| `/geniro:brainstorm` | AI-driven ideation — refines an idea into approved design (8-phase loop with HARD-GATE). Hand-off menu to /implement, /decompose, or /features add. Skip for well-formed specs. |
| `/geniro:investigate` | Deep codebase Q&A with parallel research agents |
| `/geniro:features` | Feature backlog management and spec creation |
| `/geniro:onboard` | Rapid codebase mapping and orientation |
| `/geniro:learnings` | Extract session learnings into categorized memory |
| `/geniro:update` | Update plugin to latest version |
| `/geniro:vendor` | Vendor the plugin into `.claude/` with `geniro-` prefix for cloud runners (offline/CI use) |
| `/geniro:cleanup` | Remove all plugin files from project and uninstall |

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## Custom Agent Invocation

When a skill spawns a plugin-defined agent (`reviewer-agent`, `relevance-filter-agent`, `adversarial-tester-agent`, `refactor-agent`, `architect-agent`, `skeptic-agent`, `knowledge-retrieval-agent`, `backend-agent`, `frontend-agent`) via the `Agent(subagent_type="<name>", ...)` tool, the bare-name form resolves only when the plugin is marketplace-installed in interactive Claude Code or when the project has been `/geniro:vendor`-ed. In Claude Code SDK / harness / cloud runners the plugin's `agents/` directory is not registered and the call hard-errors with `Agent type '<name>' not found. Available agents: …`.

**Apply the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every plugin-agent spawn site.** Attempt the bare name first; on "not found", re-attempt as `Agent(subagent_type="general-purpose", ...)` with the agent's `.md` body (frontmatter stripped) prepended to the prompt. Do NOT use the `<plugin-name>:<agent-name>` prefix for programmatic `Task()`/`Agent()` invocation — that form is for UI typeahead only. This is the agent-registration layer; it is independent of the MCP-tool degradation noted in §Optional MCP Dependencies below.

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **Database guard** — prevents unsafe database operations
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files
- **Secret scanning** — scans inputs and outputs for leaked secrets
- **Git guardrails** — blocks destructive git operations (force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, filter-branch, update-ref -d)
- **`.geniro/` deletion guard** — blocks bulk deletion of `.geniro/` (which holds user-authored instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Per-file `rm -f` and deep-path `rm -rf .geniro/<top>/<sub>/` remain allowed; bulk `rm -rf .geniro/`, `rm -rf .geniro/<single-segment>`, `find .geniro -delete`, `git worktree remove`, and `git add -f` on `.geniro/` paths are blocked. The `git add -f` block exists because force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — real incident: Cursor's SCM discard wiped `.geniro/actions/*.md` after they were force-added. The correct path for tracked content is `.gitignore` negation (e.g. `!.geniro/actions/` + `!.geniro/actions/**`), never `git add -f`.
- **Post-compaction recovery** — wired as `SessionStart` with `matcher: "compact"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). Re-injects suggested-file list including `.geniro/instructions/global.md`, the active skill's `<skill>.md`, and `.geniro/instructions/code-style.md` so custom workflow rules and code-style rules survive compaction
- **Evidence-on-completion** — Stop hook (warn-only) — scans last assistant message for completion phrases (e.g., "shipped", "all tests pass", "ready to ship", "Done!") that lack an Evidence Block; cites `skills/_shared/evidence-standard.md`. Stop hooks fire ~50-80% of the time, so this is a soft reminder layer, not enforcement. Bypass: `evidence-stop` in `.geniro/safety.json` `allow_patterns`.
- **TDD-order enforcement** — PreToolUse `Edit|Write` (hard-block) — when `.geniro/state/tdd/state-<slug>.md` shows phase=RED, blocks `Edit`/`Write` on production-code files (test files still allowed). State file absence means the skill hasn't opted in to TDD, so no surprise blocks. Bypass: `tdd-order` in `.geniro/safety.json` `allow_patterns`.

### Per-project allowlist for safety guardrails

Create `.geniro/safety.json` in your project to opt out of specific guardrail patterns:

```json
{
  "allow_patterns": ["force-push-with-lease", "clean-fd"]
}
```

Pattern IDs:
- **Git guardrails**: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`
- **`.geniro/` deletion guard**: `rm-geniro-tree` (bulk `rm -rf .geniro/`), `rm-geniro-subdir` (`rm -rf .geniro/<top>/`), `rm-geniro-state-subdir` (`rm -rf .geniro/state/<skill>/`), `find-geniro-delete` (`find .geniro ... -delete`), `worktree-remove-with-state` (`git worktree remove`), `git-add-force-geniro` (`git add -f` on `.geniro/` paths)
- **Evidence-on-completion**: `evidence-stop` (skip the Stop-hook completion-phrase warning)
- **TDD-order enforcement**: `tdd-order` (skip the RED-phase production-code Edit/Write block)

The allowlist is read from the nearest `.geniro/safety.json` walking up from the cwd.

## Optional MCP Dependencies

Some skills/agents unlock additional capabilities when a companion MCP server is available. They **gracefully degrade** when it isn't — install only the ones you need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `frontend-agent` Phase 3.5(b) visual self-critique; `/geniro:implement` Phase 7 Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console/network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The tool prefix `plugin_playwright_playwright__*` is what Claude Code exposes when Playwright comes from a sibling plugin. If absent, the visual loop and smoke-test step are skipped automatically. |

To check what's available in your environment, look for `mcp__plugin_playwright_playwright__*` tools in the agent's tool list at runtime.

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
