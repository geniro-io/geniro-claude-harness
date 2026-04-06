# Geniro Claude Harness

A production-grade harness template for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that provides agents, skills, hooks, and rules to make AI-assisted development safer, faster, and more consistent.

Built and maintained by the [Geniro](https://github.com/geniro-io) team.

## What is a Harness?

In AI agent engineering, a **harness** is everything that wraps around the model itself — the tools, guardrails, feedback loops, and workflow structure that turn a raw LLM into a reliable development partner. This concept was formalized as [Harness Engineering](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html) by Martin Fowler.

This project provides a ready-to-install harness for Claude Code, based on analysis of 14 production frameworks and battle-tested on real monorepo projects.

## What's Included

| Component | Count | Description |
|-----------|-------|-------------|
| **Agents** | 13 | Specialized personas (architect, reviewer, security, debugger, etc.) |
| **Skills** | 13 | Reusable workflows (`/setup`, `/plan`, `/implement`, `/review`, `/follow-up`, etc.) |
| **Hooks** | 8 | Safety automation (command blocking, secret protection, DB guards, context monitoring) |
| **Rules** | 2 | Scoped instruction files generated for your language and framework |

## Quick Start

### 1. Clone this repository

```bash
git clone https://github.com/geniro-io/geniro-claude-harness.git
```

### 2. Install into your project

```bash
./geniro-claude-harness/claude-harness-template/install.sh /path/to/your/project
```

### 3. Run setup in Claude Code

```bash
cd /path/to/your/project
claude
/setup
```

The `/setup` skill will:
1. **Scan** your codebase — detect language, framework, ORM, test runner, linter, architecture patterns
2. **Discover** validation commands — from package.json, Makefile, config files
3. **Interview** you — ask about workflow preferences and conventions (only things it can't auto-detect)
4. **Generate** tailored files — CLAUDE.md, agents, rules specific to your project
5. **Copy** universal files — agents, skills, hooks that work for any tech stack
6. **Verify** — check for broken formatting, unreplaced placeholders, wrong-language content

## The Pipeline

### `/implement` — Feature Pipeline (8 Phases)

```
/implement add user authentication
```

1. **Discover** — Clarify scope, edge cases, decisions
2. **Architect** — Design solution; skeptic agent validates; you approve
3. **Approval** — Full plan presented; you confirm before coding starts
4. **Implement** — Backend and frontend agents build in parallel
5. **Validate** — Automated checks (lint, build, test, startup)
6. **Simplify** — 3 parallel agents review for reuse, quality, efficiency
7. **Review** — Code quality review across 5 dimensions with fix cycles
8. **Ship** — Present results; you decide to commit/push/PR

### `/review` — Code Review

Checks across 5 dimensions: Architecture, Tests, Bugs, Security, Guidelines.
Produces specific issues with line numbers and fix suggestions.

### `/follow-up` — Iteration

Continues from the last implementation/review, making incremental improvements.

## Safety Hooks

All hooks run automatically — no configuration needed after install:

| Hook | Protection |
|------|-----------|
| `dangerous-command-blocker` | Blocks `rm -rf`, `git reset --hard`, `git push --force` |
| `db-guard` | Prevents `DROP DATABASE`, `DELETE FROM` without WHERE |
| `secret-protection-input` | Blocks reading `.env`, credentials, SSH keys |
| `file-protection` | Prevents writing to `.env`, `.pem`, secrets |
| `secret-protection-output` | Scans output for leaked API keys, tokens, passwords |
| `context-monitor` | Monitors token usage with debounced warnings |
| `pre-compact-state-save` | Saves state before context compaction |
| `post-compact-notification` | Notifies when compaction occurs |

## Updating

To sync with a newer version of the harness:

```bash
cd geniro-claude-harness && git pull
./claude-harness-template/install.sh /path/to/your/project
cd /path/to/your/project && claude
/setup
```

The setup skill detects existing files and shows a per-file diff — you decide what to accept.

## Project Structure

```
geniro-claude-harness/
├── README.md                    # This file
├── LICENSE                      # Apache 2.0
├── CONTRIBUTING.md              # Contribution guidelines
├── report.md                    # Best practices & patterns research (4800+ lines)
├── claude-harness-template/     # The installable template
│   ├── install.sh               # Bootstrap installer
│   ├── CLAUDE.md                # Stub — /setup generates project-specific version
│   ├── settings.json            # Hook registration and permissions
│   ├── agents/                  # 13 specialized agent definitions
│   ├── skills/                  # 13 reusable workflow definitions
│   ├── hooks/                   # 8 safety & quality automation scripts
│   ├── rules/                   # Scoped instruction files
│   └── _reference/              # Reference examples for /setup
└── .claude/skills/              # Meta-skills for improving the template itself
```

## Documentation

- **[Template README](claude-harness-template/README.md)** — Detailed documentation of all components
- **[Hooks Documentation](claude-harness-template/HOOKS.md)** — Hook priority levels and configuration
- **[Best Practices Report](report.md)** — Research behind the template (14 frameworks analyzed)

## Credits

Patterns synthesized from analysis of: [Metaswarm](https://github.com/Chachamaru127/claude-code-harness), [GSD](https://github.com/cline/gsd), Citadel, claude-pipeline, [ECC](https://github.com/anthropics/claude-code), [SuperClaude](https://github.com/NexonAI/superclaude), Orchestrator Kit, Claude Forge, gstack, OMC, Beads, [Ruflo](https://github.com/ruvnet/ruflo), and the official Claude Code `/code-review` plugin.

## License

[Apache License 2.0](LICENSE) — see [LICENSE](LICENSE) for details.

---

Made with care by the [Geniro](https://github.com/geniro-io) team.
