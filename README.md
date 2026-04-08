# Geniro Claude Plugin

A production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks. Provides 13 agents, 13 skills, and 8 safety hooks out of the box.

Built and maintained by the [Geniro](https://github.com/geniro-io) team.

## Install

```bash
claude plugin marketplace add geniro-io/geniro-claude-harness
claude plugin install geniro-claude-plugin
```

### For your team (project-scoped)

Add to your repo's `.claude/settings.json` so teammates get prompted to install:

```json
{
  "extraKnownMarketplaces": {
    "geniro-claude-harness": {
      "source": { "source": "github", "repo": "geniro-io/geniro-claude-harness" }
    }
  }
}
```

## Getting Started

After installing the plugin, run the setup skill in Claude Code:

```
/geniro:setup
```

This will:
1. **Scan** your codebase -- detect language, framework, ORM, test runner, linter, architecture patterns
2. **Discover** validation commands -- from package.json, Makefile, config files
3. **Interview** you -- ask about workflow preferences and conventions (only things it can't auto-detect)
4. **Generate** tailored files -- CLAUDE.md, agents, rules specific to your project
5. **Verify** -- check for broken formatting, unreplaced placeholders, wrong-language content

## Skills

| Skill | Purpose |
|-------|---------|
| `/geniro:setup` | AI-driven project setup -- scans codebase, interviews you, generates tailored config |
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

## The Pipeline: /geniro:implement

```
/geniro:implement add user authentication
```

1. **Discover** -- Clarify scope, edge cases, decisions
2. **Architect** -- Design solution; skeptic agent validates; you approve
3. **Approval** -- Full plan presented; you confirm before coding starts
4. **Implement** -- Backend and frontend agents build in parallel
5. **Validate** -- Automated checks (lint, build, test, startup)
6. **Simplify** -- 3 parallel agents review for reuse, quality, efficiency
7. **Review** -- Code quality review across 5 dimensions with fix cycles
8. **Ship** -- Present results; you decide to commit/push/PR

## Safety Hooks

All hooks run automatically after installation:

| Hook | Protection |
|------|-----------|
| `dangerous-command-blocker` | Blocks `rm -rf`, `git reset --hard`, `git push --force` |
| `db-guard` | Prevents `DROP DATABASE`, `DELETE FROM` without WHERE |
| `secret-protection-input` | Blocks reading `.env`, credentials, SSH keys |
| `file-protection` | Prevents writing to `.env`, `.pem`, secrets |
| `secret-protection-output` | Scans output for leaked API keys, tokens, passwords |
| `pre-compact-state-save` | Saves state before context compaction |
| `post-compact-notification` | Notifies when compaction occurs |
| `backpressure` | Compresses verbose test/build output to save context |

## Updating

The plugin auto-updates via the Claude Code marketplace. To manually update:

```bash
claude plugin update geniro-claude-plugin
```

Or run `/geniro:update` inside Claude Code. The status line shows an arrow when updates are available.

## Plugin Structure

```
geniro-claude-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/                      # 13 specialized agent definitions
├── skills/                      # 13 reusable workflow definitions
│   ├── setup/                   # AI-driven project setup
│   ├── implement/               # 8-phase feature pipeline
│   ├── plan/                    # Implementation planning
│   ├── review/                  # 5-dimension code review
│   └── ...
├── hooks/                       # 10 safety & quality hooks
│   ├── hooks.json               # Hook configuration
│   ├── geniro-check-update.js   # Update detection (SessionStart)
│   ├── geniro-statusline.js     # Status line display
│   └── *.sh                     # Safety hook scripts
├── rules/                       # Scoped instruction files
├── settings.json                # Permissions and status line config
├── CLAUDE.md                    # Plugin instructions (auto-loaded)
└── HOOKS.md                     # Hook documentation
```

## Credits

Patterns synthesized from analysis of: [Metaswarm](https://github.com/Chachamaru127/claude-code-harness), [GSD](https://github.com/cline/gsd), Citadel, claude-pipeline, [ECC](https://github.com/anthropics/claude-code), [SuperClaude](https://github.com/NexonAI/superclaude), Orchestrator Kit, Claude Forge, gstack, OMC, Beads, [Ruflo](https://github.com/ruvnet/ruflo), and the official Claude Code `/code-review` plugin.

## License

[Apache License 2.0](LICENSE)

---

Made with care by the [Geniro](https://github.com/geniro-io) team.
