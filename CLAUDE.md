# Geniro Harness Plugin

Production-grade Claude Code harness with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions
- Backend/frontend agent configurations matched to your stack
- Rules files for your coding patterns

## Available Skills

| Skill | Purpose |
|-------|---------|
| `/geniro:setup` | AI-driven project setup — scans codebase, interviews you, generates tailored config |
| `/geniro:implement` | Full-featured implementation with architecture review and multi-agent execution |
| `/geniro:plan` | Create detailed implementation plans with architect + skeptic validation |
| `/geniro:review` | Parallel 5-agent code review (bugs, security, architecture, tests, guidelines) |
| `/geniro:debug` | Scientific-method bug investigation with hypothesis tracking |
| `/geniro:follow-up` | Quick post-implementation changes (trivial/small scope) |
| `/geniro:deep-simplify` | Three-pass parallel code review for reuse, quality, and efficiency |
| `/geniro:refactor` | Restructure code with zero behavior change guarantee |
| `/geniro:investigate` | Deep codebase Q&A with parallel research agents |
| `/geniro:features` | Feature backlog management and spec creation |
| `/geniro:onboard` | Rapid codebase mapping and orientation |
| `/geniro:learnings` | Extract session learnings into categorized memory |
| `/geniro:update` | Update plugin to latest version |
| `/geniro:cleanup` | Remove all plugin files from project and uninstall |

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **Dangerous command blocker** — blocks `rm -rf /`, `git push --force`, `DROP TABLE`, etc.
- **Database guard** — prevents unsafe database operations
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files
- **Secret scanning** — scans inputs and outputs for leaked secrets
- **Compaction state** — preserves critical state across context compaction

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
