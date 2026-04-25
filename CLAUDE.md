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
| `/geniro:plan` | Create detailed implementation plans with architect + skeptic validation |
| `/geniro:decompose` | Decompose a Big task into 3-7 independently shippable milestones; hands off to `/geniro:implement milestone <N>` |
| `/geniro:review` | Parallel 5-agent code review (bugs, security, architecture, tests, guidelines) |
| `/geniro:debug` | Scientific-method bug investigation with hypothesis tracking |
| `/geniro:follow-up` | Quick post-implementation changes (trivial/small scope) |
| `/geniro:deep-simplify` | Three-pass parallel code review for reuse, quality, and efficiency |
| `/geniro:refactor` | Restructure code with zero behavior change guarantee |
| `/geniro:instructions` | Manage custom instruction files — create, list, edit, validate, delete |
| `/geniro:actions` | Create and invoke custom workflow-helper actions stored in `.geniro/actions/` (Slack/PR/release automations) |
| `/geniro:investigate` | Deep codebase Q&A with parallel research agents |
| `/geniro:features` | Feature backlog management and spec creation |
| `/geniro:onboard` | Rapid codebase mapping and orientation |
| `/geniro:learnings` | Extract session learnings into categorized memory |
| `/geniro:update` | Update plugin to latest version |
| `/geniro:vendor` | Vendor the plugin into `.claude/` with `geniro-` prefix for cloud runners (offline/CI use) |
| `/geniro:cleanup` | Remove all plugin files from project and uninstall |

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **Database guard** — prevents unsafe database operations
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files
- **Secret scanning** — scans inputs and outputs for leaked secrets
- **Compaction state** — preserves critical state across context compaction

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
