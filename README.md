# Geniro Claude Plugin

A production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks. Provides 13 agents, 15 skills, and 8 safety hooks out of the box.

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
4. **Generate** tailored CLAUDE.md specific to your project
5. **Verify** -- check for broken formatting, unreplaced placeholders, wrong-language content

## Skills

### `/geniro:setup` -- AI-driven project setup

Scans your codebase, interviews you about preferences, and generates a tailored CLAUDE.md with detected tech stack, commands, and conventions.

```
/geniro:setup
```

### `/geniro:implement` -- Full-featured implementation

Eight-phase pipeline: discover scope, architect a solution, get your approval, implement with parallel agents, validate, simplify, review, and ship.

```
/geniro:implement add user authentication with JWT tokens
/geniro:implement create a REST API for managing blog posts
/geniro:implement integrate Stripe payments for subscriptions
```

### `/geniro:plan` -- Implementation planning

Creates a detailed file-level implementation plan validated by architect and skeptic agents. Use before `/geniro:implement` or standalone.

```
/geniro:plan migrate from REST to GraphQL
/geniro:plan add role-based access control
/geniro:plan review                          # list existing plans
```

### `/geniro:review` -- Parallel 5-agent code review

Spawns 5 specialized reviewers (bugs, security, architecture, tests, guidelines) in parallel with confidence-scored findings.

```
/geniro:review                               # review uncommitted changes
/geniro:review src/auth/ src/middleware/      # review specific files/dirs
/geniro:review HEAD~3..HEAD                   # review a commit range
```

### `/geniro:debug` -- Scientific-method bug investigation

Systematic debugging: observe, hypothesize, test, isolate, fix, verify. Tracks all hypotheses and rejects speculation.

```
/geniro:debug login returns 500 after password reset
/geniro:debug memory leak in WebSocket handler after 1000 connections
/geniro:debug tests pass locally but fail in CI on the date formatting step
```

### `/geniro:follow-up` -- Quick post-implementation changes

For small changes that skip architecture. Assesses complexity, implements, validates, reviews, and ships. Escalates to `/geniro:implement` if scope is too large.

```
/geniro:follow-up rename the "users" endpoint to "accounts"
/geniro:follow-up add created_at timestamp to the response DTO
/geniro:follow-up fix the typo in the error message on line 42
```

### `/geniro:deep-simplify` -- Three-pass parallel code review

Spawns 3 agents (reuse, quality, efficiency) on changed files. Applies P1/P2 fixes and reverts if CI breaks. Zero behavior change guaranteed.

```
/geniro:deep-simplify                        # review uncommitted changes
/geniro:deep-simplify src/services/          # review specific directory
```

### `/geniro:refactor` -- Safe code restructuring

Incremental refactoring with continuous test verification. Detects code smells, applies transformations atomically, guarantees zero behavior change.

```
/geniro:refactor extract payment logic from OrderService into PaymentService
/geniro:refactor consolidate duplicate validation across controllers
/geniro:refactor convert callback-based auth module to async/await
```

### `/geniro:investigate` -- Deep codebase Q&A

Parallel research agents explore codebase structure, git history, and internet sources to produce evidence-backed answers.

```
/geniro:investigate how does the caching layer invalidate stale entries?
/geniro:investigate what happens when a WebSocket connection drops mid-transaction?
/geniro:investigate why was the ORM switched from Sequelize to Prisma?
```

### `/geniro:features` -- Feature backlog management

Track features with status, priority, and complexity. Create detailed specs with codebase scouting and adaptive questioning.

```
/geniro:features list                        # show all tracked features
/geniro:features add dark mode support       # add a new feature
/geniro:features spec dark mode support      # create a detailed spec
/geniro:features next                        # pick the next feature to work on
/geniro:features complete dark mode support  # mark as done
```

### `/geniro:onboard` -- Rapid codebase orientation

Scans structure, files, patterns, and conventions. Produces a CODEBASE_MAP.md with architecture, module relationships, critical paths, and entry points.

```
/geniro:onboard
/geniro:onboard focus on the API layer
```

### `/geniro:instructions` -- Custom instruction management

Create, list, edit, validate, and delete project-specific rules that customize how skills behave.

```
/geniro:instructions list
/geniro:instructions create "always use snake_case for database columns"
/geniro:instructions create "skip review for test files" --scope review
/geniro:instructions delete no-orm-rule
```

### `/geniro:learnings` -- Extract session learnings

Captures patterns, gotchas, decisions, and anti-patterns from completed work into categorized memory with reusability gates.

```
/geniro:learnings
/geniro:learnings focus on the auth refactor decisions
```

### `/geniro:cleanup` -- Remove plugin files

Removes all geniro-claude-plugin files from the project. Uses plugin state to preserve user-created files. Includes confirmation before any deletion.

```
/geniro:cleanup
```

### `/geniro:update` -- Update plugin

Updates to the latest version. The status line shows an arrow when updates are available.

```
/geniro:update
```

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
claude plugin update geniro-claude-plugin@geniro-claude-harness
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
│   └── *.sh                     # Safety hook scripts
├── rules/                       # Plugin-internal conventions
├── settings.json                # Permissions config
├── CLAUDE.md                    # Plugin instructions (auto-loaded)
└── HOOKS.md                     # Hook documentation
```

## Credits

Patterns synthesized from analysis of: [Metaswarm](https://github.com/Chachamaru127/claude-code-harness), [GSD](https://github.com/cline/gsd), Citadel, claude-pipeline, [ECC](https://github.com/anthropics/claude-code), [SuperClaude](https://github.com/NexonAI/superclaude), Orchestrator Kit, Claude Forge, gstack, OMC, Beads, [Ruflo](https://github.com/ruvnet/ruflo), and the official Claude Code `/code-review` plugin.

## License

[Apache License 2.0](LICENSE)

---

Made with care by the [Geniro](https://github.com/geniro-io) team.
