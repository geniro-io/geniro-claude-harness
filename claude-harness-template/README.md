# Claude Code Harness Template

A production-grade template for setting up a Claude Code harness in any software project. Analyzes your codebase, interviews you about preferences, and generates tailored configuration.

**Based on:** Analysis of 14 production frameworks (Node.js, Python, Rust, Go, Java, Ruby, C#), patterns from Metaswarm, GSD, Citadel, claude-pipeline, ECC, and proven Claude Code deployments.

## What's Included

- **13 Agents** — 6 core (architect, skeptic, reviewer, backend, frontend, refactor) + 7 optional (debugger, security, doc, devops, knowledge, knowledge-retrieval, meta)
- **13 Skills** — 10 core (/setup, /plan, /spec, /implement, /review, /follow-up, /deep-simplify, /refactor, /features, /learnings) + 3 optional (/debug, /onboard, /ui-review)
- **8 Hooks** — 5 Priority 1 safety + 1 Priority 2 observability + 2 Priority 3 lifecycle + 1 context management utility (backpressure)
- **Rules Files** — Generated for your specific language and framework
- **CLAUDE.md** — Generated with your project's commands, conventions, and patterns
- **settings.json** — Claude Code configuration for permissions and hook orchestration

## Quick Start

```bash
# 1. Clone this template (once)
git clone <repo-url> ~/claude-harness-template

# 2. Install into your project
~/claude-harness-template/install.sh /path/to/your/repo

# 3. Open your project in Claude Code and run setup
cd /path/to/your/repo
claude
/setup
```

**What `/setup` does:**
1. Scans your codebase — detects language, framework, ORM, test runner, linter, directory structure, architecture patterns
2. Discovers validation commands — from package.json scripts, Makefile targets, config files, and language defaults
3. Interviews you — asks about workflow preferences, team conventions, and integrations (only things it can't auto-detect)
4. Generates tailored files — CLAUDE.md, backend-agent, frontend-agent, rules files — specific to your project
5. Copies universal files — agents, skills, hooks that work for any tech stack
6. Verifies — checks for broken formatting, unreplaced placeholders, wrong-language content

To re-sync with an updated template, run `install.sh` again and then `/setup` — it compares each file against the template and shows you exactly what changed.

## Template Structure

```
claude-harness-template/
├── CLAUDE.md                         # Stub → /setup generates project-specific version
├── README.md                         # This file
├── HOOKS.md                          # Hook documentation and priority levels
│
├── agents/                           # Specialized Claude agents (13 total)
│   ├── architect-agent.md            ✓ Universal — system design and decisions
│   ├── skeptic-agent.md              ✓ Universal — validation and gap detection
│   ├── reviewer-agent.md             ✓ Universal — code review across 5 dimensions
│   ├── backend-agent.md              ⚙ Generated — tailored to your backend stack
│   ├── frontend-agent.md             ⚙ Generated — tailored to your frontend stack
│   ├── refactor-agent.md             ✓ Universal — safe incremental refactoring
│   ├── debugger-agent.md             ✓ Universal — scientific-method debugging
│   ├── security-agent.md             ✓ Universal — threat modeling, OWASP audit
│   ├── doc-agent.md                  ✓ Universal — documentation maintenance
│   ├── devops-agent.md               ✓ Universal — infrastructure and CI/CD
│   ├── knowledge-agent.md            ✓ Universal — learning extraction
│   ├── knowledge-retrieval-agent.md  ✓ Universal — cross-session knowledge search
│   └── meta-agent.md                 ✓ Universal — agent and skill creation
│
├── skills/                           # Reusable workflows (13 total)
│   ├── setup/SKILL.md                ★ The setup skill itself
│   ├── plan/                         # Implementation planning
│   │   ├── SKILL.md
│   │   └── plan-criteria.md          # Plan structure, naming, quality checklist
│   ├── spec/SKILL.md                 # Write requirements and specifications
│   ├── implement/SKILL.md            # 8-phase feature pipeline
│   ├── review/                       # Comprehensive code review
│   │   ├── SKILL.md
│   │   ├── architecture-criteria.md
│   │   ├── bugs-criteria.md
│   │   ├── security-criteria.md
│   │   ├── tests-criteria.md
│   │   └── guidelines-criteria.md
│   ├── follow-up/SKILL.md            # Iterate and improve
│   ├── deep-simplify/SKILL.md        # Parallel 3-agent code review
│   ├── refactor/SKILL.md             # Refactoring workflow
│   ├── features/SKILL.md             # Feature catalog and management
│   ├── debug/SKILL.md                # Scientific debugging workflow
│   ├── onboard/SKILL.md              # Codebase orientation
│   ├── learnings/SKILL.md            # Extract learnings from sessions
│   └── ui-review/SKILL.md            # UI/UX review workflow
│
├── hooks/                            # Safety & quality automation (8 registered + 1 utility)
│   ├── dangerous-command-blocker.sh  # Priority 1: Block rm -rf, git reset
│   ├── db-guard.sh                   # Priority 1: Prevent destructive DB ops
│   ├── secret-protection-input.sh    # Priority 1: Redact secrets in stdin
│   ├── file-protection.sh            # Priority 1: Protect .env, secrets
│   ├── secret-protection-output.sh   # Priority 1: Redact secrets in output
│   ├── context-monitor.sh            # Priority 2: Monitor token usage
│   ├── pre-compact-state-save.sh     # Priority 3: Save state before compact
│   ├── post-compact-notification.sh  # Priority 3: Notify after compact
│   └── backpressure.sh               # Utility: Compress test/build/lint output
│
├── rules/                            # Scoped instructions
│   ├── backend-conventions.md        ⚙ Generated — language-specific conventions
│   └── security-patterns.md          ⚙ Generated — language-specific security
│
├── settings.json                     # Hook registration and permissions
│
├── .artifacts/                       # Git-ignored transient data
│   ├── planning/                     # Specs, architecture docs, state files
│   ├── debug/                        # Hypothesis tracking during /debug sessions
│   └── knowledge/                    # Persistent learnings and session artifacts
│       ├── learnings.jsonl           # Cross-session learnings from /learnings
│       └── sessions/                 # Session summary documents
│
└── _reference/                       # Reference examples (AI reads these during /setup)
    └── CLAUDE.md.example             # Example CLAUDE.md structure
```

## The Pipeline: /implement, /review, /follow-up

### /implement — Feature Pipeline (7 Phases)

When you say `/implement add user authentication`:

1. **Discover** — Clarify scope, edge cases, decisions (backward compatibility? rollout strategy?)
2. **Architect** — Design proposed solution; skeptic agent validates; you approve
3. **Approval** — Full plan presented; you confirm before coding starts
4. **Implement** — Backend and frontend agents build in parallel
5. **Deep Simplify** — 3 parallel agents review for reuse, quality, and efficiency
6. **Review & Validate** — Automated checks + spec compliance + code quality review with fix cycles
7. **Ship** — Present results; you decide to commit/push/PR

Produces: Feature branch with tests, documentation, clean commits.

### /review — Code Review Workflow

Checks across 5 dimensions: Architecture, Tests, Bugs, Security, Guidelines.
Produces: Specific issues with line numbers and fix suggestions.

### /follow-up — Iteration

Continues from the last implementation/review, making incremental improvements.

## Re-Running Setup

Run `/setup` again at any time to:
- **Fresh install** — backup existing files, reinstall from template, then port back your project-specific content (domain rules, custom commands, safety constraints). You get the latest template structure without losing project knowledge.
- **Per-file diff** — compare every installed file against the current template, see exactly what changed, and decide per-file whether to update

```bash
# Re-run install.sh to stage the latest template, then /setup
~/claude-harness-template/install.sh /path/to/your/repo
cd /path/to/your/repo && claude
/setup
```

The skill detects existing `.claude/` files and compares each one against the template — showing additions, removals, and modifications with full detail. You decide per-file what to accept.

## Production Best Practices

1. **Check `.claude/` into git** — Share conventions with your team
2. **Keep CLAUDE.md fresh** — Re-run `/setup` or manually update as patterns evolve
3. **Review agent outputs** — Use skeptic-agent to challenge designs before implementing
4. **Tune hooks** — Add project-specific protections as needed
5. **Iterate on skills** — When repeating the same prompt, create a reusable skill with `/meta-agent`

## Credits

Part of [Geniro Claude Harness](https://github.com/geniro-io/geniro-claude-harness), built by the [Geniro](https://github.com/geniro-io) team.

Patterns synthesized from: Metaswarm, GSD, Citadel, claude-pipeline, ECC, and analysis of 14 production frameworks.

## License

[Apache License 2.0](../LICENSE) — use freely, customize, and contribute back.
