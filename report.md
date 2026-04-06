# Claude Code Harness — Best Practices & Patterns Guide

Based on analysis of 14 production frameworks: Metaswarm, GSD, Citadel, Claude-Code-Skills, claude-pipeline, Everything Claude Code (ECC), SuperClaude, Orchestrator Kit, Claude Forge, gstack, OMC, Beads, Ruflo, and the official `/code-review` plugin.

---

## Table of Contents

1. [Known Limitations](#known-limitations)
2. [Recommended Directory Structure](#recommended-directory-structure)
3. [Agents](#agents)
4. [Skills](#skills)
5. [Review Pipeline](#review-pipeline)
6. [Implementation Pipeline (End-to-End Feature Flow)](#implementation-pipeline-end-to-end-feature-flow)
7. [Skill Composition Patterns (expanded)](#skill-composition-patterns-expanded)
8. [Testing Patterns](#testing-patterns)
9. [Session Persistence & Recovery](#session-persistence--recovery)
10. [Self-Improving Knowledge](#self-improving-knowledge)
11. [Anti-Rationalization](#anti-rationalization)
12. [Hooks & Rules](#hooks--rules-supplementary)
13. [Framework Comparison Matrix](#framework-comparison-matrix)
14. [Framework Summaries](#framework-summaries)
15. [Sources](#sources)
16. [Redundant Instructions Audit](#redundant-instructions-audit)
17. [Post-Setup Cleanup: Template Garbage Prevention](#post-setup-cleanup-template-garbage-prevention)
18. [AI-Driven Setup: From Bash Script to Skill](#ai-driven-setup-from-bash-script-to-skill)
19. [Implement & Follow-Up Skill Audit](#implement--follow-up-skill-audit)
20. [Upgrade & Sync Mechanism](#upgrade--sync-mechanism)
21. [Legacy Cleanup & Post-Setup Artifact Prevention](#legacy-cleanup--post-setup-artifact-prevention)
22. [Full Template Audit: All Skills & Agents](#full-template-audit-all-skills--agents)
23. [HumanLayer Comparison & Pattern Adoption](#humanlayer-comparison--pattern-adoption-v110)
24. [Artifact Consolidation & Template Snapshot](#artifact-consolidation--template-snapshot-v110-continued)
25. [Full Template Audit v2](#full-template-audit-v2-post-v110-review-all-skills-agents-hooks)
26. [Full Template Audit v3](#full-template-audit-v3-fresh-re-review-all-skills-agents-hooks)
27. [Template Improvement Audit v4: Production Cross-Pollination](#template-improvement-audit-v4-production-cross-pollination--best-practices-review)
28. [Template Improvement Audit v6: Skill Composition & 8-Phase Pipeline](#template-improvement-audit-v6-skill-composition--8-phase-pipeline)
29. [Template Improvement Audit v7: Refactor Skill & Agent Cross-Pollination](#template-improvement-audit-v7-refactor-skill--agent-cross-pollination)
30. [Template Improvement Audit v8: Review Skill & Agent Cross-Pollination](#template-improvement-audit-v8-review-skill--agent-cross-pollination)
31. [Template Improvement Audit v9: Follow-Up Skill Cross-Pollination](#template-improvement-audit-v9-follow-up-skill-cross-pollination)
32. [Template Improvement Audit v10: All Remaining Skills](#template-improvement-audit-v10-all-remaining-skills)
33. [Template Improvement Audit v11: Follow-Up Token Optimization](#template-improvement-audit-v11-follow-up-token-optimization)
34. [Template Improvement Audit v12: Follow-Up Phase 4 Boundary Enforcement](#template-improvement-audit-v12-follow-up-phase-4-boundary-enforcement)
35. [Template Improvement Audit v13: Setup Cleanup Skipped on Compare & Update](#template-improvement-audit-v13-setup-cleanup-skipped-on-compare--update)
36. [Template Improvement Audit v14: Follow-Up Context Exhaustion & Phase Skipping](#template-improvement-audit-v14-follow-up-context-exhaustion--phase-skipping)

---

## Known Limitations

Hard constraints in Claude Code as of April 2026. All patterns in this guide work around them.

### Orchestration & Composition

| Limitation | Impact | Workaround |
|---|---|---|
| **Subagents cannot spawn sub-tasks** | An agent spawned via Agent/Task tool cannot create nested Tasks ([#4182](https://github.com/anthropics/claude-code/issues/4182), [#19077](https://github.com/anthropics/claude-code/issues/19077)) | Orchestrate from the skill level (skills run at top level where Task works). Alternatively, use `claude -p` via Bash from a subagent (community plugin: [nested-subagent](https://github.com/gruckion/nested-subagent)) — loses visibility and structured output |
| **Skills cannot call other skills** | The Skill tool breaks when called from within a skill — control returns to main session, invoking skill's workflow is abandoned ([#17351](https://github.com/anthropics/claude-code/issues/17351), [#30256](https://github.com/anthropics/claude-code/issues/30256), [#38719](https://github.com/anthropics/claude-code/issues/38719)). `context: fork` does NOT fix this ([#30256](https://github.com/anthropics/claude-code/issues/30256)). No official composition mechanism exists yet ([#39163](https://github.com/anthropics/claude-code/issues/39163)) | Three workarounds ranked by reliability: **(1) Shared reference files + subagent delegation** — extract reusable knowledge into supporting `.md` files, pre-inline into subagent prompts (best for complex skills with their own orchestration). **(2) Inline the logic** — copy relevant instructions directly into the consuming skill (oh-my-claudecode, GSD pattern — best when logic is simple). **(3) Read SKILL.md as a file** — `Read .claude/skills/X/SKILL.md` and follow inline (works but does NOT trigger skill infrastructure: `context: fork`, `model:`, `allowed-tools:` frontmatter is ignored; only use for instruction-only skills with no infrastructure dependencies) |
| **Bare markdown links not auto-followed** | `[file.md](file.md)` in SKILL.md is documentation, not an instruction | Use explicit instructions: "Read `path/to/file.md` using the Read tool" |
| **Teammates have fewer tools than subagents** | Teammates lack Agent, AskUserQuestion, EnterPlanMode, ExitPlanMode, Cron tools — underdocumented ([#32731](https://github.com/anthropics/claude-code/issues/32731)) | Use subagents instead of teammates when you need these capabilities |

### MCP Servers

| Limitation | Impact | Workaround |
|---|---|---|
| **Subagents don't receive MCP instructions** | MCP server `instructions` field is only injected into the main agent's context, not subagents ([#29655](https://github.com/anthropics/claude-code/issues/29655)) | Manually include MCP usage instructions in the subagent's system prompt or agent `.md` file |
| **No scoped MCP servers for skills/subagents** | MCP servers in `.mcp.json` are global — all tools appear in every agent's tool list ([#24054](https://github.com/anthropics/claude-code/issues/24054), [#6915](https://github.com/anthropics/claude-code/issues/6915)) | Add CLAUDE.md rules restricting which agents use which MCP tools. Use PreToolUse hooks to block calls (fragile) |
| **MCP auth lost after compaction** | OAuth-based MCP connectors silently lose session tokens after auto-compaction — UI still shows "connected" ([#36121](https://github.com/anthropics/claude-code/issues/36121)) | PostCompact hook that notifies to re-toggle connectors OFF/ON |
| **Scheduled tasks can't access MCP** | MCP connectors are not initialized until a human message warms the session ([#35899](https://github.com/anthropics/claude-code/issues/35899)) | None — requires human interaction to warm MCP session |
| **Plugin MCP tools return "Session not found"** | Plugin-provided MCP tools fail silently in some contexts; in terminal CLI, tools may not appear at all ([#40106](https://github.com/anthropics/claude-code/issues/40106)) | None documented |

### Context & Compaction

| Limitation | Impact | Workaround |
|---|---|---|
| **SKILL.md should be under 500 lines** | Long skills degrade instruction following — LLMs have ~150-200 instruction slots and Claude Code's system prompt uses ~50 | Extract reference material into supporting files alongside SKILL.md |
| **Skills context lost after compaction** | After auto-compaction, Claude loses all awareness of loaded skills, their procedures, and constraints — does not re-read skill files ([#13919](https://github.com/anthropics/claude-code/issues/13919)) | Put critical rules in CLAUDE.md (survives compaction). Use PostCompact hooks for notifications. Start fresh sessions at logical breakpoints |
| **Deferred tools lose schema after compaction** | Tools loaded via ToolSearch can lose input schemas after compaction, causing type errors on array/number parameters ([#31002](https://github.com/anthropics/claude-code/issues/31002)) | Start a fresh session |
| **Context window much smaller than advertised** | Each MCP tool description consumes tokens; with many MCP tools, 200K window can shrink to ~70K usable. Performance degrades at ~60% capacity | Keep repo-level skills to 3-5. Use `ENABLE_TOOL_SEARCH=auto:5` to defer MCP tool definitions. Use scoped rules files instead of one large CLAUDE.md |
| **Context rot / instruction priority saturation** | Adding one low-value rule dilutes compliance of every high-value rule equally. CLAUDE.md files beyond ~150 total instructions degrade uniformly | Prune rules Claude already follows. Convert behavioral rules to hooks. Use scoped rules files triggered by file type globs |
| **AUTOCOMPACT_PCT_OVERRIDE only lowers threshold** | Uses `Math.min` internally — setting it to 75 causes EARLIER compaction (not later), since default is ~83.5% ([#36121](https://github.com/anthropics/claude-code/issues/36121)) | Remove the env var. On 1M context models the default threshold is adequate |

### Hooks & Plugins

| Limitation | Impact | Workaround |
|---|---|---|
| **Hook exit 1 is fail-open (not blocking)** | `exit 0` = allow, `exit 1` = error (FAIL-OPEN), `exit 2` = block. Security hooks using `exit 1` to block operations actually allow them through ([#36121](https://github.com/anthropics/claude-code/issues/36121)) | Always use `exit 2` to block. Document this in team setup |
| **Hook false "Hook Error" labels flood context** | Every hook execution shows "Hook Error" in transcript regardless of success. With many hooks, premature turn endings ([#36121](https://github.com/anthropics/claude-code/issues/36121)) | Always consume stdin with `INPUT=$(cat)`, never output JSON to stdout for simple hooks, redirect stderr |
| **No hook hot-reload** | Changes to hooks in `settings.json` require full session restart — no `/reload` command | Use SIGHUP signal to restart with `-c` (continue) |
| **PostCompact hook undocumented but works** | Not in official hooks documentation ([#40492](https://github.com/anthropics/claude-code/issues/40492)) | Use it — receives `trigger` and `compact_summary` fields |
| **`/reload-plugins` doesn't load new skills** | After installing a plugin with skills, `/reload-plugins` increments count but skills aren't available ([#35641](https://github.com/anthropics/claude-code/issues/35641)) | Restart the session |
| **Custom agents undiscoverable when Agent tool is deferred** | Custom agents are registered as `subagent_type` values inside Agent tool description — ToolSearch doesn't index subagent names ([#32485](https://github.com/anthropics/claude-code/issues/32485)) | Add notes to CLAUDE.md telling Claude to search for "agent" when looking for integrations |

### Session & Recovery

| Limitation | Impact | Workaround |
|---|---|---|
| **`--resume` / `--continue` broken (cache bug)** | Session resume strips deferred_tools_delta records — reprocesses entire conversation at full token cost (10-20x inflation) ([#38029](https://github.com/anthropics/claude-code/issues/38029)) | Avoid `--resume` and `--continue`. Start new sessions instead |
| **Headless mode can't recover from context overflow** | In `-p` mode, if a tool call returns output exceeding context limit, the session is irrecoverable — no Esc+Esc rewind ([#13831](https://github.com/anthropics/claude-code/issues/13831)) | Pre-filter/truncate tool outputs. Use `--bare` mode. Break large operations into smaller sessions |

---

## Recommended Directory Structure

```
.claude/
├── agents/                          # Subagent definitions
│   ├── architect-agent.md
│   ├── skeptic-agent.md
│   ├── reviewer-agent.md
│   ├── backend-agent.md
│   ├── frontend-agent.md
│   └── refactor-agent.md
│
├── skills/
│   ├── implement/
│   │   └── SKILL.md                 # Full pipeline orchestrator
│   ├── review/
│   │   ├── SKILL.md                 # Multi-agent review orchestrator
│   │   ├── bugs-criteria.md         # Supporting file: bugs & correctness
│   │   ├── security-criteria.md     # Supporting file: OWASP security
│   │   ├── architecture-criteria.md # Supporting file: patterns & structure
│   │   ├── tests-criteria.md        # Supporting file: test quality
│   │   └── guidelines-criteria.md   # Supporting file: coding standards
│   ├── follow-up/
│   │   └── SKILL.md
│   ├── spec/
│   │   └── SKILL.md
│   ├── simplify/
│   │   └── SKILL.md
│   └── refactor/
│       └── SKILL.md
│
├── rules/                           # Path-scoped convention enforcement
│   └── ...
│
└── settings.json                    # Hooks, permissions
```

**Key principles:**
- **Skills contain process, supporting files contain knowledge** (from Claude-Code-Skills, MindStudio best practice)
- **Review criteria are shared files** — referenced by the review skill, reviewer agent, and any pipeline skill that needs review
- **Agents are domain-specific** — one per tech domain, not generic workers

---

## Agents

### What frameworks define

A survey of 12 frameworks shows a range from 3 to 39 named agents. The table below maps common agent roles across frameworks to identify consensus patterns.

| Role | Metaswarm | GSD | ECC | Orchestrator Kit | SuperClaude | claude-pipeline | Claude-Code-Skills | Citadel | claude-code-agents | Claude Forge | Agent Farm | Official |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Orchestrator / Coordinator** | Swarm Coordinator, Issue Orchestrator | Orchestrator | — | meta-agent-v3 | — | — | Pipeline Orchestrator | Marshal, Archon, Fleet | — | — | — | Team Lead |
| **Planner / Researcher** | Researcher | Questioner, Researcher, Planner | planner | research-specialist, problem-investigator | deep-research-agent, requirements-analyst | — | Epic/Story/Task Coordinators | — | — | Planner | — | Explore, Plan |
| **Architect** | Architect, CTO | Plan Checker | architect | — | system-architect, backend-architect, frontend-architect | — | — | — | architect-reviewer | Architect | — | — |
| **Implementer (backend)** | Coder | Executor | — | — | — | Laravel Backend Developer | — | — | code-fixer | — | General workers | General-purpose |
| **Implementer (frontend)** | — | — | — | nextjs-ui-designer, fullstack-nextjs-specialist | frontend-architect | Bulletproof Frontend Developer | — | — | — | — | — | — |
| **Code Reviewer** | Code Review | — | code-reviewer | code-reviewer | — | Code Reviewer, Spec Reviewer | Multi-Agent Validator | — | — | Code Reviewer | — | — |
| **Security Reviewer** | Security Auditor, Security Design | — | security-reviewer | security-scanner | security-engineer | — | — | — | security-auditor | Security Reviewer | — | — |
| **Test Writer / Runner** | Test Automator | Verifier | tdd-guide, e2e-runner | integration-tester, test-writer | quality-engineer | PHP Test Validator | Test Auditor | — | test-writer, test-runner | TDD Guide | — | — |
| **Refactorer / Simplifier** | — | — | refactor-cleaner | dead-code-hunter/remover, reuse-hunter/fixer | refactoring-expert | Code Simplifier | Codebase Auditor | — | — | — | — | — |
| **Debugger** | — | Debugger | build-error-resolver | — | root-cause-analyst | — | — | — | — | — | — | — |
| **Doc Writer** | — | — | doc-updater | technical-writer | technical-writer | PHPDoc Writer | — | — | — | — | — | — |
| **Knowledge / Learning** | Knowledge Curator | — | — | — | pm-agent | — | — | — | — | — | — | — |
| **DevOps / SRE** | Release Engineer, SRE | — | — | infrastructure-specialist, deployment-engineer | devops-architect | — | — | — | deploy-checker, env-validator | — | — | — |
| **PR / Ship** | PR Shepherd | — | — | — | — | — | — | — | pr-writer | — | — | — |
| **Metrics / Reporting** | Metrics | — | — | — | — | — | — | — | — | — | — | — |
| **Customer / Support** | Customer Service | — | — | — | — | — | — | — | — | — | — | — |
| **Language-specific** | — | — | 14 lang-specific agents | — | python-expert | — | — | — | — | — | — | — |
| **Browser / QA** | — | — | — | mobile-responsiveness-tester, accessibility-tester | — | — | — | — | browser-qa-agent, visual-diff | — | — | — |
| **Meta-agent** | — | — | harness-optimizer | meta-agent-v3, skill-builder-v2 | — | CC Orchestration Writer | — | — | — | — | — | — |
| **Skeptic / Validator** | — | — | — | — | — | — | — | — | — | — | — | — |

**Agent count by framework:** Metaswarm (19), Orchestrator Kit (39), ECC (26), SuperClaude (16), claude-code-agents (24), claude-pipeline (10), Claude Forge (11), GSD (8), Citadel (4 tiers), Claude-Code-Skills (7 levels), Agent Farm (1 type × N), Official (3 built-in)

### Recommended core agents

Based on cross-framework consensus, these are the most universally useful agent roles. Start with the core 6, add optional agents as your pipeline matures.

#### Core 6

| Agent | Purpose | Key tools | Model | Source frameworks |
|---|---|---|---|---|
| **architect-agent** | Analyzes tasks, explores codebase, evaluates multiple approaches, produces implementation-ready specs with file-level plans and verification steps | Read, Write, Edit, Glob, Grep, Bash, Task, WebSearch | Default (needs deep reasoning) | Metaswarm (Architect + CTO), GSD (Planner + Plan Checker), Claude Forge, ECC, SuperClaude |
| **skeptic-agent** | Validates architect specs — detects hallucinated files/functions/packages ("mirages"), checks requirement coverage (forward + backward traceability), flags scope creep | Read, Glob, Grep, Bash, Task | Sonnet (read-only) | Unique pattern — Metaswarm has adversarial review but not a dedicated pre-implementation validator. GSD has Plan Checker (closest equivalent) |
| **reviewer-agent** | Reviews code across all dimensions in a single pass using shared criteria files. Confidence-scored judge pass. Fallback when full parallel grid is unavailable | Read, Glob, Grep, Bash, WebSearch | Sonnet (no writes) | Universal — present in every framework. Metaswarm (Code Review), ECC (code-reviewer), Orchestrator Kit, Claude Forge, claude-pipeline, GSD (Verifier) |
| **backend-agent** | Domain specialist for your backend stack — knows ORM, framework patterns, migration conventions, testing patterns | Read, Write, Edit, Bash, Glob, Grep, Task, WebSearch | Default | Metaswarm (Coder), GSD (Executor), claude-pipeline (Laravel Backend Developer), SuperClaude (backend-architect). Most frameworks use generic coders — domain-specific implementers are a competitive advantage |
| **frontend-agent** | Domain specialist for your frontend stack — knows component library, state management, routing, real-time patterns | Read, Write, Edit, Bash, Glob, Grep, Task, WebSearch, Playwright | Default | claude-pipeline (Bulletproof Frontend Developer), Orchestrator Kit (nextjs-ui-designer), SuperClaude (frontend-architect). Separate frontend agent is less common but high-impact for monorepos |
| **refactor-agent** | Incremental safe refactoring with continuous test verification. Detects code smells, plans transformations, guarantees zero behavior change | Read, Write, Edit, Glob, Grep, Bash, Task, WebSearch | Default | ECC (refactor-cleaner), SuperClaude (refactoring-expert), Orchestrator Kit (dead-code-hunter + reuse-hunter) |

#### Optional (add when needed)

| Agent | Purpose | Key tools | Model | When to add |
|---|---|---|---|---|
| **debugger-agent** | Scientific-method bug investigation — hypothesis, evidence, reproduce, fix | Read, Write, Edit, Bash, Grep, Glob, WebSearch | Default | When you have complex bugs that take multiple sessions to resolve. GSD is the only framework with a dedicated debugger agent |
| **security-agent** | Pre-implementation threat modeling + post-implementation OWASP audit | Read, Glob, Grep, Bash, WebSearch | Sonnet | When handling auth, payments, or user data. Metaswarm uniquely splits this into Security Design (pre-impl) + Security Auditor (post-impl) |
| **doc-agent** | Maintains documentation, architecture maps, API docs | Read, Write, Edit, Glob, Grep, Bash | Haiku | When documentation drift is a real problem. ECC (doc-updater), SuperClaude (technical-writer) |
| **devops-agent** | Infrastructure, deployment pipelines, CI/CD configuration | Read, Write, Edit, Bash, Glob, Grep | Default | When you manage infra-as-code. Metaswarm (Release Engineer + SRE), SuperClaude (devops-architect) |
| **knowledge-agent** | Extracts learnings from completed work, curates persistent knowledge base | Read, Write, Glob, Grep, Bash | Haiku | When institutional knowledge loss across sessions is a problem. Metaswarm (Knowledge Curator) — unique and underappreciated pattern |
| **meta-agent** | Creates or improves other agents and skills | Read, Write, Edit, Glob, Grep, Bash, WebSearch | Default | When your harness itself is evolving frequently. Orchestrator Kit (meta-agent-v3, skill-builder-v2), claude-pipeline (CC Orchestration Writer) |

### Agent design principles

| Principle | Detail | Source |
|---|---|---|
| **Domain-specific over generic** | An agent that knows your stack's patterns produces better code than a generic "coder" agent. Most frameworks (Metaswarm, ECC, GSD) use generic workers — domain-specific agents are a competitive advantage | Cross-framework analysis |
| **Restrict tools for read-only agents** | Reviewer and skeptic agents should NOT have Write/Edit. Prevents accidental modifications during analysis. Use `tools` allowlist or `disallowedTools` denylist in frontmatter | Claude-Code-Skills, Anthropic docs |
| **Set maxTurns** | Prevent runaway agents. A "turn" = one agent-loop round-trip (Claude emits tool calls → SDK executes → results feed back). Counts tool-use turns only, NOT individual tool calls within a turn (a single turn can batch ~10-20 tool calls). When hit, agent returns `error_max_turns` and post-call hooks are skipped. **Recommended ranges:** 40-80 turns for implementers, 20-40 for read-only reviewers, 15-25 for haiku utility agents. Real-world data: test runners ~20, security audits ~15, simple reviewers ~10-30, complex implementation 50-80, SDK-level autonomous agents up to 250. Always pair with scoped tasks — maxTurns is a safety net, not a task planner | All frameworks, [Claude Code Docs](https://code.claude.com/docs/en/sub-agents), [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/agent-loop), [ClaudeLog FAQ](https://claudelog.com/faqs/what-is-max-turns-in-claude-code/) |
| **Model routing** | Cheaper models for simpler tasks: haiku for exploration/triage, sonnet for review/validation, opus for architecture/implementation. GSD calls these "model profiles" (quality/balanced/budget). Use `CLAUDE_CODE_SUBAGENT_MODEL` env var for global override | GSD, Official docs, Orchestrator Kit |
| **Writer/reviewer separation** | One Claude instance writes code, a fresh-context instance reviews. Avoids confirmation bias — the reviewer hasn't seen the reasoning that led to the code | Metaswarm, GSD, Anthropic "Building Effective Agents" |
| **Never trust subagent self-reports** | Orchestrators must verify work independently — don't rely on a subagent saying "I fixed it." Read the diff, run the tests | Metaswarm (explicit principle), GSD (Verifier agent) |
| **Fresh context per executor** | Each implementation agent gets a clean context window with only what it needs — no accumulated garbage from prior steps. Pass pre-read file contents in the prompt | GSD (core principle), Citadel (Fleet pattern) |
| **Architect + skeptic is a double gate** | 2-agent validation before coding — architect proposes, skeptic validates against real codebase. Catches hallucinated APIs, nonexistent files, dropped requirements. GSD's Plan Checker is the closest equivalent in other frameworks | Our analysis, GSD (Plan Checker) |
| **Shared criteria files, not duplicated logic** | Reviewer agent and review skill read the same criteria files. Adding a review check happens in one place | Shared criteria pattern |
| **Parallel only works when agents touch different files** | Running agents in parallel on overlapping files causes merge conflicts. Use worktree isolation or file-level locking | Metaswarm (lock-based), Agent Farm (file claiming), Citadel (worktree Fleet) |
| **Anti-rationalization in agent prompts** | Agents will skip steps and rationalize why. Include explicit "you MUST do X, do NOT skip Y" constraints. Claude Forge calls this the "Surgical Changes Principle" | claude-pipeline, Claude Forge, GSD |
| **Meta-agents for harness evolution** | An agent that creates/improves other agents prevents the harness from becoming stale. The meta-agent reads existing agents, identifies gaps, and generates new agent definitions | Orchestrator Kit (meta-agent-v3), claude-pipeline (CC Orchestration Writer) |
| **Convention enforcement is multi-layered** | No single mechanism prevents convention drift. Effective enforcement requires: (1) auto-loaded rules (CLAUDE.md, .claude/rules/), (2) pre-implementation pattern discovery (architect reads exemplar files), (3) structured conventions brief passed to agents, (4) post-implementation pattern-matching review. See "Convention Enforcement" section below | Cross-framework analysis, [Drift tool](https://github.com/dadbodgeoff/drift), [AGENTS.md standard](https://agents.md/), [Codified Context paper](https://arxiv.org/html/2602.20478v1) |

### Convention enforcement: what's auto-loaded vs what agents must discover

Understanding what Claude Code provides automatically is critical for avoiding both redundant instructions and missing context:

**Auto-loaded (do NOT re-read in agent prompts):**

| What | When loaded | Scope | Source |
|---|---|---|---|
| `CLAUDE.md` | Session start (every turn for subagents) | All agents including subagents | [Claude Code Docs](https://code.claude.com/docs/en/memory) |
| `.claude/rules/*.md` | Session start (global) or when matching files touched (path-scoped) | Main session; subagents get via normal message flow | [Claude Code Settings](https://code.claude.com/docs/en/settings) |
| `MEMORY.md` | Session start (first 200 lines / 25KB) | Main session | [Claude Code Docs](https://code.claude.com/docs/en/memory) |
| Skill descriptions | Session start (summaries only; full content on-demand) | Main session; subagents only if explicitly listed | [Claude Code Skills](https://code.claude.com/docs/en/skills) |

**NOT auto-loaded (agents must explicitly read):**

| What | Why it matters | Who should read it |
|---|---|---|
| `README.md` | Project overview, architecture, setup — provides big-picture context | architect-agent (Phase 2), spec skill |
| `CONTRIBUTING.md` | Team conventions, PR process, code standards — human-written rules that code patterns alone don't express | architect-agent |
| `docs/architecture.md` | System design, component relationships, data flow | architect-agent |
| ADRs (`adr/*.md`, `decisions/*.md`) | Recorded architectural decisions with rationale — prevents agents from contradicting past decisions | architect-agent, skeptic-agent |
| Existing code patterns (exemplar files) | The actual convention source of truth — how errors are handled, how files are structured, how tests are written | All implementation agents (via conventions brief) |

**Convention drift — the #1 failure mode of AI-generated code:**

AI agents optimize for locally correct code but miss global consistency. Common drift patterns:
- Agent introduces try/catch when codebase uses Result types
- Agent uses default exports when codebase uses named exports
- Agent creates utility function that duplicates an existing one under different name
- Agent adds a new dependency when an existing dep covers the same use case
- Agent places file in wrong directory for its type

**Prevention strategy (multi-layered):**
1. **Pre-implementation:** Architect reads project docs (README, CONTRIBUTING, ADRs) + finds exemplar files → produces CONVENTIONS_BRIEF in SPEC.md
2. **During implementation:** Agents receive conventions brief with concrete exemplar snippets showing patterns to follow
3. **Post-implementation:** Review skill's guidelines dimension uses "exemplar file comparison" — finds closest existing file to each changed file and diffs the patterns
4. **Passive enforcement:** .claude/rules/ files auto-load relevant conventions when matching files are touched

**Research context:**
- The [AGENTS.md standard](https://agents.md/) (Linux Foundation) formalizes project-specific instructions for AI agents, complementing CONTRIBUTING.md for humans
- The [Codified Context paper](https://arxiv.org/html/2602.20478v1) demonstrates a three-layer approach: hot-memory (conventions loaded every turn), specialized agents, and cold-memory knowledge base — used to build a 108K-line system
- [Drift](https://github.com/dadbodgeoff/drift) is an MCP server that automatically detects patterns, conventions, and decisions across sessions using Tree-sitter analysis
- The [Agent READMEs empirical study](https://arxiv.org/html/2511.12884v1) (2,303 context files from 1,925 repos) found that documenting project-specific patterns prevents agents from repeatedly re-discovering rules
- Cursor, Continue.dev, Windsurf, and Aider all use path-scoped rule files with similar auto-loading patterns — this is an industry-wide convergence

### How agents relate to each other

```
architect-agent  ->  skeptic-agent  ->  [user approval]  ->  backend-agent / frontend-agent
                                                                     |
                                                              reviewer-agent (or review skill grid)
                                                                     |
                                                              fix loop (max 3 rounds)
```

The architect proposes, the skeptic validates, the user approves, implementers build, the reviewer checks. This is the core pipeline flow — skills orchestrate the sequence.

**Compared to other frameworks:**
- **GSD**: Questioner -> Researcher (×4 parallel) -> Planner -> Plan Checker -> Executor (×N waves) -> Verifier -> Debugger (if needed)
- **Metaswarm**: Researcher -> Architect -> CTO (review loop) -> Coder -> Code Review -> Security Auditor -> PR Shepherd -> Release Engineer
- **Citadel**: Pattern Match -> Keyword Lookup -> LLM Classify -> route to Skill / Marshal / Archon / Fleet tier
- **ECC**: planner -> architect -> implementer (language-specific) -> code-reviewer + security-reviewer -> tdd-guide

### Agent frontmatter reference

Key frontmatter fields for `.claude/agents/*.md` files:

```yaml
---
name: agent-name              # Used as subagent_type value
description: "..."            # Shown in Agent tool description — keep under 200 chars
tools:                        # Allowlist (principle of least privilege)
  - Read
  - Glob
  - Grep
  - Bash
disallowedTools:              # Denylist (alternative to allowlist)
  - Write
  - Edit
model: sonnet                 # sonnet | opus | haiku | inherit (default: inherit)
maxTurns: 40                  # Prevent runaway agents (see maxTurns guidance below)
permissionMode: default       # default | bypassPermissions | plan
isolation: worktree           # Run in isolated git worktree (for parallel agents touching files)
background: true              # Run in background (caller notified on completion)
effort: high                  # low | medium | high | max (thinking effort level)
memory:                       # Memory access
  - user                      # User memories
  - project                   # Project memories
skills:                       # Skills available to this agent
  - review
mcpServers:                   # MCP servers available to this agent
  - playwright
hooks: {}                     # Agent-specific hooks
---
```

### maxTurns guidance (research-backed)

**What a "turn" actually is:** One complete iteration of the agent loop — Claude produces output with tool call(s) → SDK executes those tools → results feed back to Claude. A single turn can contain multiple tool calls (server-side limit of ~10-20 per turn). So `maxTurns: 30` doesn't mean "30 tool calls" — it means "30 round-trips," which could involve 300+ individual tool operations.

**What happens when maxTurns is reached:** The agent stops and returns `error_max_turns`. The last tool call's PostToolUse hook is NOT triggered. The parent orchestrator receives the partial result. This means cleanup hooks may be skipped — design agents to be idempotent.

**Recommended values by agent role:**

| Agent Role | maxTurns | Rationale | Real-world examples |
|---|---|---|---|
| **Implementers** (backend, frontend, refactor, debugger, devops) | 40-80 | Need to read files, write code, run tests, fix issues. Complex features may need 50+ turns | tassh: 50, Nader Dabit SDK example: 250 (but that's full-session, not subagent) |
| **Architects/planners** | 40-60 | Explore codebase, evaluate approaches, produce specs. Less writing but more reading | Most frameworks don't cap planners separately |
| **Reviewers** (read-only) | 20-40 | Read code, analyze, produce reports. No write loops | Code reviewers: 10-30, security audits: 15 |
| **Haiku utility agents** (docs, knowledge) | 15-25 | Simple tasks with fast model. More turns risk quality degradation with cheaper models | Haiku test runner example: 20 |
| **Meta-agents** | 40-60 | Create/modify other agents — similar to implementers | Orchestrator Kit: 25 (conservative) |
| **Orchestrator agents** (spawn sub-tasks) | 30-50 | Overhead is mostly delegation + collecting results. Actual work happens in spawned agents | Reviewer spawning 5 sub-reviewers: 30 sufficient |

**Pitfalls:**

- **Too low (< 20 for implementers):** Agent exhausts budget mid-implementation, leaves partial code. No signal to user that execution was truncated. [GitHub Issue #189](https://github.com/drbeefsupreme/tassh/issues/189)
- **Too high (> 100 for subagents):** Agent stuck in loops burns tokens. Each spawned agent opens its own context window — multi-agent workflows use ~4-7x more tokens than single-agent. [Claude Code Best Practices](https://github.com/shanraisshan/claude-code-best-practice)
- **Orchestrator-spawned agents:** 3-5 parallel subagents is the practical sweet spot. Beyond 10 rarely provides benefit and multiplies costs
- **Post-hook skip:** When maxTurns is reached, PostToolUse hooks don't fire ([Issue #58](https://github.com/anthropics/claude-agent-sdk-typescript/issues/58)). Design state-saving hooks to run periodically, not just at the end

**Best practice pattern:** Scope the task tightly + set maxTurns as a safety ceiling, not a work estimate. A well-scoped task for a backend-agent should complete in 20-40 turns; `maxTurns: 60` gives 50% headroom for retries and edge cases.

---

## Skills

### What frameworks define

A survey of 12 frameworks shows a range from 5 built-in skills to 151 (ECC). The table below maps common skill roles across frameworks.

| Role | GSD | Metaswarm | Superpowers | claude-pipeline | ECC | Orchestrator Kit | SuperClaude | Claude Forge | Official (Anthropic) | Official (Built-in) |
|---|---|---|---|---|---|---|---|---|---|---|
| **Bootstrap / Activation** | — | `start` | `using-superpowers` | `using-skills` | `skill-comply` | — | — | — | — | — |
| **Discovery / Requirements** | `gsd:discuss-phase` | — | `brainstorming` | `brainstorming` | — | `speckit.clarify` | `brainstorm` | — | — | — |
| **Spec / Design** | `gsd:new-project` | `create-issue` | — | `investigating-codebase-for-user-stories` | — | `speckit.specify` | `confidence-check` | — | — | — |
| **Plan** | `gsd:plan-phase` | — | `writing-plans` | `writing-plans` | — | `speckit.plan` | — | — | — | — |
| **Implement** | `gsd:execute-phase` | `orchestrated-execution` | `executing-plans` | `implement-issue` | `tdd-workflow` | `speckit.implement` | `/sc:implement` | `cc-dev-agent` | — | — |
| **Follow-up / Quick** | `gsd:fast`, `gsd:quick` | — | — | — | — | — | — | — | — | — |
| **Review** | `gsd:review` | `plan-review-gate`, `design-review-gate` | `requesting-code-review` | `subagent-driven-development` (2-stage) | `security-review` | `code-review` | — | `frontend-code-review` | `/code-review` plugin | `/simplify` |
| **Simplify / Refactor** | — | — | — | — | — | — | — | — | — | `/simplify` |
| **Test** | `gsd:add-tests` | — | `test-driven-development` | `test-driven-development` | `tdd-workflow`, `e2e-testing` | — | — | — | — | — |
| **Debug** | `gsd:debug` | — | `systematic-debugging` | `systematic-debugging` | — | `systematic-debugging` | `troubleshoot` | — | `/debug` | `/debug` |
| **Security** | `gsd:secure-phase` | — | — | — | `security-scan` | `health-security` | — | `security-pipeline` | — | — |
| **Verify / Ship** | `gsd:verify-work`, `gsd:ship` | `pr-shepherd` | `finishing-a-development-branch` | `process-pr` | `git-workflow` | — | — | `session-wrap` | — | — |
| **Batch / Parallel** | `gsd:execute-phase` (waves) | — | `dispatching-parallel-agents` | `dispatching-parallel-agents` | — | `worktree` | — | — | — | `/batch` |
| **Backlog / Management** | `gsd:progress`, `gsd:stats`, `gsd:next` | `status` | — | `handle-issues` | — | `speckit.tasks`, `speckit.taskstoissues` | `pm` | — | — | — |
| **Knowledge / Learning** | — | — | — | `improvement-loop` | `continuous-learning-v2` | — | — | `continuous-learning-v2` | — | — |
| **Meta-skill** | `gsd:update` | — | `writing-skills` | `writing-skills`, `writing-agents` | `agent-harness-construction` | — | — | `skill-factory` | `skill-creator` | — |
| **Codebase Mapping** | `gsd:map-codebase` | — | — | — | `repo-scan` | `onboard` | `/sc:index-repo` | — | — | — |
| **UI Review** | `gsd:ui-review` | `visual-review` | — | `review-ui` | — | — | — | — | — | — |
| **Doc Generation** | — | — | — | `write-docblocks` | — | — | `/sc:document` | — | `doc-coauthoring` | — |
| **Context Management** | — | — | — | — | `strategic-compact`, `context-budget` | — | `token-efficiency` | `strategic-compact` | — | — |

**Skill count by framework:** GSD (59), ECC (151), Orchestrator Kit (68), SuperClaude (36), claude-pipeline (21), Metaswarm (13), Superpowers (14), Claude Forge (23), Official Anthropic (17), Official Built-in (5)

### Recommended core skills

Based on cross-framework consensus, these are the most universally useful skill roles. The sweet spot is **10-25 active skills** per project — all skill descriptions share ~1% of context window (~8000 chars total), with each capped at ~250 chars.

#### Core pipeline (7 skills)

| Skill | Purpose | Context | Model | Source frameworks |
|---|---|---|---|---|
| `/spec` | Gather requirements through adaptive questioning + codebase scouting. Produces a feature spec file | main | default | GSD (`discuss-phase`), Superpowers (`brainstorming`), Orchestrator Kit (`speckit.clarify` + `speckit.specify`), SuperClaude (`confidence-check`) |
| `/implement` | Full pipeline orchestrator: spec -> architecture -> approval -> implementation -> validate -> simplify -> review -> ship | main | inherit | Universal — every framework has this: GSD (`execute-phase`), Metaswarm (`orchestrated-execution`), Superpowers (`executing-plans`), claude-pipeline (`implement-issue`), Orchestrator Kit (`speckit.implement`) |
| `/review` | Multi-agent parallel review grid (5 sub-reviewers via Task) + judge pass + fix routing to implementer agents | fork | sonnet | Metaswarm (`plan-review-gate` + `design-review-gate`), Superpowers (`requesting-code-review`), claude-pipeline (2-stage review), Orchestrator Kit (`code-review`) |
| `/follow-up` | Lightweight changes — skip architecture, go straight to implement + full review | main | inherit | GSD has `gsd:fast` (trivial inline) and `gsd:quick` (with guarantees). Most frameworks don't differentiate — a unique pattern for reducing overhead on small changes |
| `/simplify` | Code quality pass on changed files — reuse patterns, readability, efficiency | fork | sonnet | Built-in Claude Code skill. ECC and claude-pipeline have similar post-implementation cleanup steps |
| `/refactor` | Safe incremental refactoring with continuous test verification | fork | default | Most frameworks bundle this into implementation. Dedicated refactor skill is less common but valuable for large codebases |
| `/features` | Feature backlog management (list, next, complete, status) | main | haiku | GSD (`gsd:progress`, `gsd:stats`, `gsd:next`), Orchestrator Kit (`speckit.tasks`), SuperClaude (`pm`) |

#### Optional skills (add when needed)

| Skill | Purpose | Context | Model | When to add | Source frameworks |
|---|---|---|---|---|---|
| `/debug` | Scientific-method bug investigation with hypothesis tracking | main | default | When bugs are complex enough to need structured debugging | Built-in Claude Code skill. GSD (`gsd:debug`), Superpowers (`systematic-debugging`), SuperClaude (`troubleshoot`) |
| `/ui-review` | Visual review via Playwright screenshots | fork | sonnet | When frontend changes need visual verification | Metaswarm (`visual-review`), GSD (`gsd:ui-review`), claude-pipeline (`review-ui`) |
| `/onboard` | Codebase mapping and knowledge extraction for new developers or new sessions | main | default | When team members frequently start new sessions | GSD (`gsd:map-codebase`), Orchestrator Kit (`onboard`), SuperClaude (`/sc:index-repo`) |
| `/improve` | Post-session learning: extract feedback, update rules, improve skills | main | haiku | When your harness itself is evolving | claude-pipeline (`improvement-loop`), ECC (`continuous-learning-v2`), Claude Forge (`continuous-learning-v2`) |
| `/meta-skill` | Create or improve agents and skills with TDD-like workflow | main | default | When building or evolving your harness | Official (`skill-creator`), claude-pipeline (`writing-skills`, `writing-agents`), Orchestrator Kit (`skill-builder-v2`) |

### Skill design rules

| Rule | Why | Source |
|---|---|---|
| **Keep SKILL.md under 500 lines** | Instruction following degrades with length. LLMs have ~150-200 instruction slots; Claude Code's system prompt uses ~50 | Claude Code docs, community research |
| **Extract reference material into supporting .md files** | Progressive disclosure — load only when needed. SKILL.md = process, supporting files = knowledge | Claude Code docs, Superpowers, claude-pipeline |
| **Use explicit "Read `path/to/file.md`" not bare markdown links** | Claude doesn't auto-follow `[file.md](file.md)` — it's documentation, not an instruction | Research finding |
| **Description says "Use when..." never summarizes workflow** | Prevents Claude from following description shortcut instead of reading full skill. Front-load the key use case — first 250 chars matter most | claude-pipeline, Official skill-creator |
| **Description under 250 chars** | All descriptions share ~1% of context window (~8000 chars total). Each skill's description is capped at ~250 chars. Beyond that, truncated | Claude Code internals, community research |
| **Every skill needs a Definition of Done section** | Clear exit criteria prevent partial completion. Superpowers has a dedicated `verification-before-completion` skill for this | Superpowers, claude-pipeline |
| **Include anti-rationalization constraints** | Counters Claude's tendency to skip steps. Use explicit "you MUST do X, do NOT skip Y" language. Claude Forge calls this "Surgical Changes Principle" | claude-pipeline, Claude Forge, Superpowers |
| **SKILL.md has process only, reference content in supporting files** | Separation of concerns. The 3-tier progressive disclosure model: metadata (~100 tokens) -> SKILL.md (<5000 tokens) -> references/ (unlimited) | Superpowers, Official skill-creator |
| **Use `disable-model-invocation: true` for dangerous skills** | Deploy, push, delete skills should only be invocable by the user, never auto-triggered by Claude | Claude Forge |
| **Use `argument-hint` for autocomplete** | Shows expected argument format in the `/` menu (e.g., `"[issue-number]"`, `"<phase> [--auto]"`) | GSD, Claude Forge |
| **Namespace skills for large collections** | GSD uses `gsd:*`, SuperClaude uses `sc:*`. Prevents name collisions and groups related skills | GSD, SuperClaude |

### Skill composition patterns

Since skills cannot call other skills directly ([#17351](https://github.com/anthropics/claude-code/issues/17351)), frameworks have developed these workarounds:

| Pattern | How it works | Source |
|---|---|---|
| **Shared reference files + subagent delegation** | Extract reusable knowledge (criteria, patterns) into supporting `.md` files. Consuming skill pre-reads them and spawns subagents with pre-inlined content. Avoids loading complex skill orchestration inline. See [Pattern 1](#pattern-1-shared-reference-files--subagent-delegation-recommended-default) | Our implementation (v6), oh-my-claudecode (inline + Task delegation), GSD (self-contained skills) |
| **Read SKILL.md inline** (simple skills only) | Skill A says "Read `.claude/skills/B/SKILL.md` and follow its instructions." Works for instruction-only skills but loses frontmatter infrastructure (`context: fork`, `model:`, `allowed-tools:`). See [Pattern 1b](#pattern-1b-read-skillmd-inline-simple-skills-only) | Community workaround — use only when skill B has no orchestration or infrastructure needs |
| **Bootstrap chain** | A session-start hook forces loading of a master skill that establishes mandatory behaviors for the entire session. Superpowers uses `using-superpowers`, claude-pipeline uses `using-skills` | Superpowers, claude-pipeline |
| **Trigger chains** | Skills auto-activate based on trigger phrases or after other skills complete. Metaswarm uses `auto_activate: true` + `triggers: ["after:superpowers:brainstorming"]` | Metaswarm |
| **Orchestrator scripts** | External shell scripts (`implement-issue-orchestrator.sh`) drive multi-step workflows with JSON schemas for each stage. The script calls `claude -p` with different prompts for each step | claude-pipeline |
| **Agent routing via `agent` field** | Frontmatter `agent: gsd-planner` delegates the entire skill to a specific subagent type when `context: fork` | GSD |
| **Dynamic context injection** | `` !`command` `` syntax in SKILL.md runs shell commands before content reaches Claude. Output replaces the placeholder | Official SKILL.md spec |
| **Pipeline state files** | Skills read/write a shared state file (e.g., `.planning/STATE.md`) to pass context between phases without conversation memory | GSD |

### Skill frontmatter reference

All available frontmatter fields for SKILL.md files:

```yaml
---
# Required
name: implement                     # Max 64 chars, lowercase + hyphens, must match directory name
description: "Use when..."          # Max 1024 chars (but only ~250 chars shown in registry)

# Execution context
context: fork                       # main (default) | fork (isolated subagent)
agent: gsd-planner                  # Subagent type when context: fork (default: general-purpose)
model: sonnet                       # sonnet | opus | haiku | inherit (override model)
effort: high                        # low | medium | high | max (thinking effort)

# Tool access
allowed-tools:                      # Pre-approved tools (skip permission prompts)
  - Read
  - Bash
  - Agent

# Invocation control
argument-hint: "[issue-number]"     # Shown in autocomplete menu
disable-model-invocation: true      # Only user can invoke (not auto-triggered by Claude)
user-invocable: false               # Hidden from / menu (only Claude invokes programmatically)

# Scoping
paths:                              # Glob patterns — skill only activates for matching files
  - "apps/api/**"
  - "*.ts"

# Hooks (skill-scoped)
hooks: {}                           # Lifecycle hooks specific to this skill

# Shell
shell: bash                         # bash (default) | powershell

# Non-standard but used by frameworks
auto_activate: true                 # Metaswarm: auto-activate on triggers
triggers: ["keyword", "after:X"]    # Metaswarm: trigger conditions
origin: community                   # ECC: tracks skill provenance
---

# Skill Content

$ARGUMENTS                          # Replaced with user's arguments
$ARGUMENTS[0] / $0                  # Positional argument access
${CLAUDE_SESSION_ID}                # Current session ID
${CLAUDE_SKILL_DIR}                 # Directory containing this SKILL.md
!`shell-command`                    # Dynamic context injection (runs before reaching Claude)
```

### Skill relationship diagram

```
/spec  ->  /implement  ->  /follow-up
               |
               |-- reads .claude/skills/review/SKILL.md (Phase 1-3)
               |       |-- spawns 5 Tasks from criteria files
               |       |-- judge pass
               |       |-- routes fixes to backend-agent / frontend-agent
               |
               |-- reads .claude/skills/simplify/SKILL.md
               |
               |-- spawns architect-agent -> skeptic-agent (pre-implementation)
               |-- spawns backend-agent / frontend-agent (implementation)

/review (standalone)
    |-- spawns 5 Tasks from criteria files
    |-- judge pass
    |-- routes fixes to backend-agent / frontend-agent
    |-- verify fixes (re-review, max 3 rounds)
```

**Compared to other frameworks:**
- **GSD**: `gsd:discuss-phase` -> `gsd:plan-phase` -> `gsd:execute-phase` (waves) -> `gsd:verify-work` -> `gsd:ship` (state persisted in `.planning/STATE.md`)
- **Metaswarm**: `start` -> `create-issue` -> `orchestrated-execution` (4-phase loop: implement -> validate -> adversarial review -> commit) -> `pr-shepherd`
- **Superpowers**: `brainstorming` -> `writing-plans` -> `executing-plans` -> `requesting-code-review` -> `receiving-code-review` -> `finishing-a-development-branch`
- **Orchestrator Kit (SpecKit)**: `speckit.clarify` -> `speckit.specify` -> `speckit.plan` -> `speckit.implement` -> `speckit.checklist` -> `speckit.tasks` -> `speckit.taskstoissues`
- **claude-pipeline**: `brainstorming` -> `writing-plans` -> `implement-issue` (orchestrator script) -> `subagent-driven-development` (2-stage review) -> `process-pr`

---

## Review Pipeline

### What frameworks implement

A survey of 10 frameworks reveals 6 distinct review architecture patterns. The table below compares them.

| Framework | Architecture | Parallel reviewers | Dimensions | Aggregation | Fix loops | Cross-model |
|---|---|---|---|---|---|---|
| **Anthropic /code-review plugin** | 4 parallel reviewers + validation layer | 4 (2× CLAUDE.md compliance, 2× bug detection) | Bugs, CLAUDE.md compliance, security, logic | Confidence 0-100, threshold 80, validation sub-agents confirm each finding | None (review only) | No (multi-tier: Haiku triage, Sonnet compliance, Opus bugs) |
| **Metaswarm** | 3 mandatory gates (design → plan → execution loop) | 3 (plan gate), 5 (design gate), 1 (execution) | Feasibility, completeness, scope, UX, security design, TDD, correctness | Unanimous binary PASS/FAIL with cited evidence | Max 3 per gate, fresh instances each round, escalate to human | Yes (Codex/Gemini reviews Claude's code) |
| **GSD** | Sequential specialized agents at pipeline stages | 1 per stage (plan-checker, verifier, security-auditor, ui-auditor) | Requirements coverage, task completeness, dependencies, scope, security, UI quality, CLAUDE.md compliance | Per-agent verdicts, no multi-voter aggregation | Revision loop (planner revises, checker re-verifies) | Yes (supports Codex, Gemini CLI, OpenCode) |
| **Superpowers** | Single reviewer with strong writer/reviewer separation | 1 (fresh Task instance) | Code quality, architecture, testing, requirements, production readiness | Single reviewer verdict: Critical/Important/Minor | One item at a time, critical first | No |
| **Claude Octopus** | Multi-LLM fleet + 2-stage pipeline | 3-8 (one per available LLM provider) | Correctness, security, architecture, TDD, CVE lookup, AI-generated code risks | Confidence >= 85% for auto-posting. "Debate" mode for disagreements | None (review only) | Yes (core differentiator: Codex, Gemini, Perplexity, Qwen, Ollama, OpenRouter) |
| **HAMY 9-Agent** | 9 parallel subagents, each one dimension | 9 | Tests, linting, code quality, security, style, test quality, performance, deps/deploy, simplification | Severity ranking (Critical > High > Medium > Low). Clean agents collapsed to one-liner | None (review only) | No |
| **ECC** | Specialized reviewer agents + AgentShield security | 2 (code-reviewer + security-reviewer in parallel) | Bugs, OWASP, language-specific patterns. AgentShield: red-team/blue-team/auditor | >80% confidence threshold | Sequential fix, STOP on CRITICAL | No |
| **claude-code-skills** | Agile pipeline with mandatory task reviewer + story quality gate | 1 per gate (ln-402 task reviewer, ln-500 story quality gate) | 15+ checks: approach alignment, cross-file DRY, config hygiene, algorithm correctness, WCAG, typography | 4-level verdict (PASS/CONCERNS/FAIL/WAIVED) with quality score | Done/To Rework cycle | Yes (external Codex/Gemini) |
| **Claude Forge** | Single-agent review with anti-rationalization | 1 | Code quality, frontend-specific (if web changes) | Single verdict | None | No |
| **Orchestrator Kit** | Quality gates between pipeline stages | 1 (`run-quality-gate` skill) | Go/no-go decision per stage | Binary gate | Implicit | No |

### Review architecture patterns

#### Pattern 1: Parallel Sub-Reviewer Grid (recommended)

The review skill spawns N focused Tasks in parallel, each checking one dimension. A judge pass aggregates and filters.

```
/review skill (context: fork)
  ├── Read N criteria files from .claude/skills/review/
  ├── Spawn N Tasks in ONE message (parallel):
  │   ├── Task 1: Bugs & Correctness (from bugs-criteria.md)
  │   ├── Task 2: Security / OWASP (from security-criteria.md)
  │   ├── Task 3: Architecture & Patterns (from architecture-criteria.md)
  │   ├── Task 4: Test Quality (from tests-criteria.md)
  │   └── Task 5: Guidelines & Design (from guidelines-criteria.md)
  ├── Judge pass: deduplicate, verify, confidence score, filter
  └── Route fixes to backend-agent / frontend-agent
```

**Why:** LLMs exhibit a U-shaped attention curve — strong at start/end, 30%+ accuracy drop in the middle of large prompts. Each sub-reviewer gets a clean context window focused on one dimension, eliminating attention degradation.

**Critical:** All Tasks must be spawned in a single message for parallel execution.

**How many dimensions?** Anthropic plugin uses 4, HAMY uses 9, most frameworks use 5-6. The sweet spot is 4-6 — enough to specialize, not so many that orchestration overhead dominates.

**Sources:** Anthropic /code-review plugin (4 reviewers), Metaswarm (5 design reviewers, 3 plan reviewers), HAMY (9 reviewers), claude-code-skills (multi-model review)

#### Pattern 1b: Adaptive File Batching for Large Diffs (research-backed)

The dimension-based split (Pattern 1) solves attention degradation *across review concerns* — but not *across files*. When a bugs-reviewer gets 20 changed files, it still hits the U-shaped attention curve on files 8-15.

**The "Lost in the Middle" problem applied to code review:**
- Liu et al. (2023) showed **30%+ accuracy drop** when relevant info is in the middle of context, regardless of context window size ([Paper](https://arxiv.org/abs/2307.03172))
- Follow-up research confirmed **all 18 frontier models** show measurable performance decay with increased context length ([Paper](https://arxiv.org/html/2510.05381v1))
- Hsieh et al. (2024) showed partial mitigation via attention calibration: up to 15pp improvement, but not a full fix ([Paper](https://arxiv.org/abs/2406.16008))

**Industry approaches to large diffs:**

| Tool | Strategy | File splitting? | Notes |
|---|---|---|---|
| **Anthropic /code-review** | All files to all 6+ specialized agents | No | 84% bug detection on >1000 LOC PRs; ~20 min review time |
| **CodeRabbit** | Compress with cheap model → review individual files with strong model | Yes (per-file) | Uses gpt-3.5 for compression, gpt-4 for review |
| **GitHub Copilot** | "Map-ahead" strategy for 20+ file PRs | No explicit split | 60M+ reviews completed; recent improvements for large PRs |
| **Qodo 2.0** | Multi-agent with chaining mechanisms | Exploring "dual by-diff and by-file context" | F1 score: 60.1% |

**Industry consensus on PR size:** Elite teams enforce **<400 LOC per PR** for effective review ([Augment Code](https://www.augmentcode.com/guides/code-review-best-practices-that-scale)). But AI review must handle whatever is thrown at it.

**Recommended pattern — adaptive batching:**

```
if (changedFiles <= 8 AND loc <= 400):
    Standard mode: 5 dimensions × all files = 5 agents
else:
    Triage: classify files as trivial (renames, formatting) vs substantive
    Batch substantive files into groups of ~5 files (by module/directory)
    For each batch: spawn only relevant dimensions (test-only batch skips security)
    Total agents: batches × applicable dimensions (typically 8-15 agents)
    Judge pass: deduplicate findings across batches before scoring
```

**Why ~5 files per batch?** No published benchmark on optimal batch size for code review. CodeRabbit processes files individually (batch=1), Anthropic uses batch=all. We pick ~5 as a middle ground that keeps context focused while preserving cross-file pattern detection within a module. Teams should tune this based on their average file size and review quality.

**Token cost trade-off:** Batched mode spawns more agents (8-15 vs 5), increasing token usage ~2-3x. But each agent's context is smaller, so per-agent cost is lower. Net cost increase is typically ~50-80%, while accuracy improves significantly on the middle-of-context files that would otherwise be missed.

**This is an unexplored optimization space** — no published research combines dimension × file-batch matrix. Anthropic splits by dimension only, CodeRabbit splits by file only, no one does both. This hybrid approach should capture the benefits of both while keeping each agent's context within the high-accuracy zone.

#### Pattern 2: Shared Criteria Files

Store review dimensions as separate files, referenced by multiple consumers:

```
.claude/skills/review/
├── SKILL.md                    # Orchestration only
├── bugs-criteria.md            # Shared dimension 1
├── security-criteria.md        # Shared dimension 2
├── architecture-criteria.md    # Shared dimension 3
├── tests-criteria.md           # Shared dimension 4
└── guidelines-criteria.md      # Shared dimension 5
```

**Consumers:** `/review` skill (N Tasks), `/implement` (reads review SKILL.md), `/follow-up` (same), `reviewer-agent` (single-agent inline).

**Why:** Single source of truth. Edit once, updates everywhere.

#### Pattern 3: Confidence-Scored Judge Pass

After sub-reviewers return findings, verify each one:

1. **Read the referenced file and line** — does the issue actually exist?
2. **Check for mitigating context** — comments, established patterns
3. **Adjust confidence** — confirmed: stays/increases, ambiguous: -20, pattern elsewhere: -40
4. **Filter** — only keep findings above threshold
5. **Classify** — Required Change (CRITICAL/HIGH, >= 80), Minor Improvement (MEDIUM, >= 70)

**Confidence thresholds across frameworks:**

| Framework | Threshold | Strategy |
|---|---|---|
| Anthropic /code-review plugin | 80 | Confidence 0-100 + validation sub-agents confirm each finding |
| Claude Octopus | 85 | Auto-post to PR only above threshold |
| ECC | 80% | Skip finding if below |
| Metaswarm | N/A | Binary PASS/FAIL with cited evidence (no scoring) |
| Superpowers | N/A | Single reviewer expected to be precise |

**Research finding:** GPT-4 and Claude both exhibit higher false positive rates than false negative rates compared to static analysis tools. The two-layer pattern (find → validate) used by Anthropic's plugin is the strongest approach for reducing false positives.

#### Pattern 4: Two-Layer Validation (from Anthropic /code-review plugin)

After initial reviewers flag findings, spawn **validation sub-agents** that receive each finding + full PR context and must independently confirm with high confidence before the finding is kept.

```
Reviewer agents (parallel)  ->  findings  ->  Validator agents (parallel, one per finding)  ->  confirmed findings only
```

**Why:** Eliminates ~40% of false positives compared to single-pass review. The validator has no knowledge of other findings (prevents anchoring) and must independently arrive at the same conclusion.

**Sources:** Anthropic /code-review plugin (explicit validation layer), Metaswarm (adversarial mode achieves similar effect)

#### Pattern 5: Multi-Gate Pipeline (from Metaswarm, GSD)

Instead of one review after implementation, insert mandatory review gates at multiple pipeline stages:

| Gate | When | What it checks | Source |
|---|---|---|---|
| **Design review** | Before planning | Architecture, UX, security design, use cases, TDD readiness | Metaswarm (5 parallel specialists) |
| **Plan review** | Before implementation | Feasibility, completeness, scope alignment, dependency ordering | Metaswarm (3 adversarial reviewers), GSD (plan-checker) |
| **Code review** | After implementation | Bugs, security, architecture, tests, guidelines | All frameworks |
| **Verification** | After fixes | Goal achievement (not just task completion), regression check | GSD (verifier), Metaswarm (re-review) |

**Why:** Fixing a design problem in the planning stage is 10x cheaper than fixing it in code. Metaswarm's Security Design agent explicitly embodies this: "10x cheaper to fix in design than code."

**Key rule from Metaswarm:** Never skip a gate for "simple" plans. All plans go through all gates.

#### Pattern 6: Spec Compliance as Separate Dimension (from claude-pipeline, Claude Octopus)

Add a review dimension that checks "Did we build the right thing?" separate from "Did we build it well?"

The spec reviewer checks requirements coverage, scope alignment, acceptance criteria. It does NOT check code quality. This prevents requirement drift from being masked by clean code.

Claude Octopus implements this as a mandatory first stage — spec compliance must pass before code quality review begins.

**Implementation:** Add `spec-compliance-criteria.md` to the review directory, or make it a gate before the main review grid.

#### Pattern 7: Cross-Model Review (from Metaswarm, Claude Octopus)

Use different LLM providers to review the same code, eliminating single-model blind spots:

| Provider | Specialty | Source |
|---|---|---|
| Claude | Architecture, synthesis, overall quality | Claude Octopus |
| Codex | Logic and correctness | Claude Octopus, Metaswarm |
| Gemini | Security and edge cases | Claude Octopus, Metaswarm |
| Perplexity | CVE lookup, known vulnerability matching | Claude Octopus |

**Why:** Different models have different blind spots. Claude tends toward false positives on style; Codex catches logic issues Claude misses; Gemini excels at security pattern recognition.

**When to use:** Optional. Most valuable for security-sensitive code or when a single model's review has been insufficient. Adds significant cost and latency.

#### Pattern 8: Model Routing Within Review (from Anthropic /code-review plugin)

Use different model tiers for different review tasks to optimize cost:

| Task | Model | Why |
|---|---|---|
| Triage (skip trivial PRs) | Haiku | Cheap, fast classification |
| Guidelines/compliance | Sonnet | Pattern matching, no deep reasoning needed |
| Bug detection | Opus | Deep code understanding required |
| Security analysis | Opus | Threat modeling requires deep reasoning |
| Finding validation | Sonnet (guidelines) / Opus (bugs) | Match model to finding type |

**Sources:** Anthropic /code-review plugin (explicit multi-tier), GSD (model profiles: quality/balanced/budget)

### Review anti-patterns

Based on explicit prohibitions across frameworks:

| Anti-pattern | Why it fails | Who forbids it | Fix |
|---|---|---|---|
| **Reusing reviewer instances across rounds** | Anchoring bias — reviewer anchors to previous findings | Metaswarm | Fresh Task instances on every review round |
| **Cross-reviewer visibility** | Convergence — reviewers influence each other | Metaswarm | Strict isolation between parallel reviewers |
| **Treating FAIL as advisory** | Undermines the gate — "we'll fix it later" never happens | Metaswarm | FAIL blocks the pipeline |
| **Planner self-reviewing** | Confirmation bias — the planner will always approve their own plan | Metaswarm, Superpowers | Writer and reviewer must be separate agents |
| **Unlimited fix iterations** | Infinite loops burn tokens without converging | All frameworks | Max 3 rounds, then escalate to human |
| **Partial re-review** | Regressions in "fixed" dimensions go undetected | Metaswarm | Re-run ALL reviewers on revision (or at minimum, all dimensions that had findings) |
| **Skipping gates for "simple" changes** | Complexity is misjudged; simple changes cause production incidents | Metaswarm | All changes go through all gates |
| **Performative agreement with reviewer** | "You're absolutely right!" followed by blind implementation | Superpowers | Verify against codebase reality before implementing suggestions |
| **Trusting reviewer self-reports** | Reviewer says "all clear" without actually reading the code | Metaswarm | Orchestrator independently verifies findings reference real code |
| **AI-generated code getting same rigor as human code** | AI code has specific failure modes: over-abstraction, weak tests, speculative patterns | Claude Octopus, ECC | Provenance-aware review — elevate scrutiny for AI-generated code |

### Fix loop patterns

How frameworks handle the review → fix → re-review cycle:

| Framework | Max rounds | Re-review scope | Escalation | Fresh reviewer? |
|---|---|---|---|---|
| Metaswarm | 3 per gate | All reviewers re-run | Human choice: Override / Revise / Simplify / Cancel | Yes (mandatory) |
| GSD | Revision loop | Same checker, gap-focused | Plan split or human | N/A (single agent) |
| claude-code-skills | Implicit | Task-scoped (Done/To Rework) | Follow-up tasks | N/A |
| ECC | Sequential | Full re-review on CRITICAL | STOP workflow | N/A |
| Anthropic plugin | 0 | N/A (review only, no fix loop) | N/A | N/A |

**Recommended pattern:** Max 3 rounds. Only re-review dimensions that had findings (saves tokens). Use fresh reviewer instances to prevent anchoring. After max rounds, escalate to the user with structured handoff (what was fixed, what remains, suggested next steps).

---

## Implementation Pipeline (End-to-End Feature Flow)

How to take a user request from idea to shipped code. This is the most complex orchestration challenge — it involves discovery, architecture, approval gates, multi-agent delegation, validation, review, fix loops, and shipping.

### What frameworks implement

A survey of 6 frameworks reveals different pipeline structures, but convergence on key phases. The table below maps phases across frameworks.

| Phase | GSD | Metaswarm | Superpowers | claude-pipeline | Orchestrator Kit | claude-code-skills |
|---|---|---|---|---|---|---|
| **Discovery / Requirements** | `discuss-phase` (adaptive questioning, gray area elimination) | Research (Researcher agent) | `brainstorming` (Socratic dialogue, per-section approval) | Issue body defines scope | `speckit.clarify` (adaptive questioning) | `ln-200-scope-decomposer` |
| **Design review** | — | Design Review Gate (5 parallel: PM, Architect, Designer, Security, CTO) | Spec self-review + user review | — | — | `ln-310` multi-agent validation (20 criteria) |
| **Architecture / Plan** | `plan-phase` (researcher → planner → plan-checker loop) | Architect + Plan Review Gate (3 adversarial reviewers) | `writing-plans` (zero-context plans, self-review) | evaluate + plan stages (JSON schema output) | `speckit.specify` → `speckit.plan` | `ln-300-task-coordinator` |
| **User approval gate** | Automated (plan checker) | After 3 failed iterations → human | Per-section + final spec approval | Automated | `speckit.plan` review | `ln-310` human checkpoint |
| **Implementation** | `execute-phase` (wave-based parallel executors, atomic commits) | Orchestrated Execution (IMPLEMENT per WU) | `subagent-driven-development` (fresh agent per task) | Per-task `claude -p` calls with JSON schemas | `speckit.implement` (1 Task = 1 Agent) | `ln-401-task-executor` |
| **Validation** | Cross-phase regression gate | VALIDATE (independent: tsc + eslint + tests + coverage) | Tests must pass | test stage (up to 10 iterations) | Quality gate | `ln-402-task-reviewer` (15+ checks) |
| **Code review** | `gsd:review` | ADVERSARIAL REVIEW (fresh reviewer, binary PASS/FAIL) | 2-stage: spec compliance → code quality (separate subagents) | 2-stage: spec-review + code-review (up to 3 iterations) | `code-review` skill | `ln-500-story-quality-gate` |
| **Fix loop** | Node repair (RETRY/DECOMPOSE/PRUNE) | Return to IMPLEMENT, fresh review, max 3 | Implementer fixes, reviewer re-reviews | Fix stage + re-review | Agent re-invocation | `ln-403-task-rework` |
| **Verification / UAT** | `verify-work` (conversational, per-deliverable) | Post-execution review | Tests + final code review | Post-PR review | `speckit.checklist` | Quality gate verdict |
| **Ship** | `gsd:ship` (PR via `gh`) | PR Shepherd (auto-monitors to merge) | 4 options: merge/PR/keep/discard | Auto PR creation | Manual | Manual |
| **Learning** | State persistence in `.planning/` | `/self-reflect` post-merge | — | `improvement-loop` | — | — |

**Phase count by framework:** GSD (5 core + autonomous mode), Metaswarm (9 phases), Superpowers (4 phases), claude-pipeline (13 stages), Orchestrator Kit (7 stages), claude-code-skills (4 levels)

### Recommended pipeline structure

Based on cross-framework consensus, a recommended `/implement` skill should have these phases. Phases marked **(WAIT)** require user input before proceeding.

```
Phase 1: Discover (WAIT)
    |
Phase 2: Architect → Validate spec (WAIT)
    |
Phase 3: Implement (delegated to agents)
    |
Phase 4: Validate (automated)
    |
Phase 5: Review (automated with fix loops)
    |
Phase 6: Ship (WAIT)
```

#### Phase 1: Discover (WAIT)

**Purpose:** Eliminate ambiguity before any code is written. Gray areas resolved here cost 10x less than in implementation.

**Who:** Main skill (inline, no subagent). The skill itself conducts discovery.

**Steps:**
1. **Read the user's request** and identify which files/modules are affected
2. **Codebase scan** (Glob/Grep/Read) to understand current patterns and constraints
3. **Identify gray areas** — decision points where the AI would otherwise guess:
   - Visual features: layout, density, interactions, empty states
   - APIs: response format, error handling, pagination
   - Business logic: edge cases, validation rules, default values
   - Architecture: where new code goes, which patterns to follow
4. **Ask the user** to resolve gray areas via structured questions (2-4 options each)
5. **Produce a spec file** with canonical references to user decisions

**Human gate:** User must confirm decisions before proceeding. Questions should be batched (not one-by-one) to reduce back-and-forth.

**Mode detection (flag-free, inferred from natural language):**
Instead of requiring flags like `--auto` or `--assumptions`, the skill detects intent from the user's phrasing:
- **Auto mode** — triggered by urgency signals ("just do it", "ASAP", "no questions", "auto", "quick"). Skips interactive questions, picks recommended defaults (GSD pattern)
- **Assumptions mode** — triggered by tentative language ("I think", "maybe", "what if", "should we"). Proposes a complete plan with assumptions, lets user correct (GSD assumptions mode — inverts the interaction)
- **Interactive (default)** — full structured questioning via `AskUserQuestion`

This eliminates CLI-style flags in favor of natural conversation, while preserving the same three behaviors.

**Git workspace setup:** After discovery questions are answered, ask the user where to work:
- **New feature branch** (recommended default) — creates `feat/<feature-name>` from HEAD. Isolates changes, enables easy revert, supports parallel work. Research consensus: "Running an agent directly on your main branch is asking for trouble" ([Addy Osmani, Code Agent Orchestra](https://addyosmani.com/blog/code-agent-orchestra/))
- **Current branch** — work on whatever is checked out. Appropriate when user is already on a feature branch or making a quick addition
- **Git worktree** — isolated copy of repo. Best for risky/experimental changes or when multiple implementation pipelines run simultaneously. Claude Code natively supports `--worktree` flag; Cursor uses worktrees for parallel agents

In auto mode: default to new feature branch unless already on one. If on `main`/`master`, always create a branch (never implement directly on main).

**Why this matters:** Aider auto-commits every change with `(aider)` attribution, making rollback trivial. Claude Code and Cursor recommend worktrees for parallel agents. The Agent Factory pattern (Leo Cardz, 2026) ties each agent session to a single branch that dies on completion — maximizing isolation. Feature branches give 100% rollback capability with zero risk to mainline.

**Edge case — scope too large:** If discovery reveals the request spans multiple independent subsystems, flag immediately and help decompose into sub-features, each getting its own pipeline cycle (Superpowers pattern).

**Edge case — user provides a spec:** If the user provides a pre-written spec file, skip discovery and read the spec directly.

**Sources:** GSD (`discuss-phase` with gray area categorization), Superpowers (`brainstorming` with per-section approval), Orchestrator Kit (`speckit.clarify`), Aider (auto-commit with attribution), Agent Factory (session-per-branch isolation)

#### Phase 2: Architect → Validate Spec (WAIT)

**Purpose:** Produce an implementation-ready specification with file-level plans, then validate it against the real codebase before the user approves.

**Who:** architect-agent (produces spec) → skeptic-agent or plan-checker (validates spec)

**Steps:**
1. **Delegate to architect-agent** with:
   - User's request and decisions from Phase 1
   - Relevant file contents (pre-read by the skill, passed inline — saves agent from re-reading)
   - Project conventions (from docs/)
   - Instruction: evaluate multiple approaches, recommend one with trade-offs
2. **Architect produces spec** containing:
   - Approach summary with alternatives considered
   - File-level plan (which files to create/modify, what changes in each)
   - Key test scenarios
   - Risks and open questions
3. **Delegate to skeptic-agent** (or plan-checker) with:
   - The architect's spec
   - The original user request
   - Instruction: verify files/functions/packages actually exist, check requirement coverage (forward + backward traceability), flag scope creep
4. **Skeptic returns validation result:**
   - PASS → present spec to user
   - FAIL → return to architect with specific issues, architect revises, re-validate (max 3 iterations)
5. **Present spec to user** for approval

**Human gate:** User approves the spec before implementation begins. Options:
- "Looks good — proceed"
- "Adjust" — user modifies the approach
- "Too large — split" — decompose into smaller pieces

**Validation dimensions (from GSD plan-checker, 8 dimensions):**
- Requirement coverage — every user decision from Phase 1 appears in the plan
- Task atomicity — each task is independently verifiable
- Dependency ordering — tasks are sequenced correctly
- File scope — all needed files are listed
- Verification commands — each task has a concrete way to verify it worked
- Context compliance — follows project conventions
- Gap detection — nothing was silently dropped
- Scope sanity — plan doesn't exceed what was asked

**Edge case — architect hallucination:** This is why the skeptic/plan-checker exists. Metaswarm calls this "never trust subagent self-reports." The skeptic greps for every file/function/package the architect referenced.

**Edge case — no architecture needed:** For truly trivial changes (1-2 files, obvious fix), skip this phase entirely. This is the `/follow-up` skill's purpose — see "Lightweight Changes" section below.

**Sources:** GSD (planner → plan-checker verification loop), Metaswarm (Architect → Plan Review Gate with 3 adversarial reviewers), Superpowers (spec self-review + user review)

#### Phase 3: Implement (delegated to agents)

**Purpose:** Execute the approved spec by delegating to domain-specific implementer agents.

**Who:** backend-agent and/or frontend-agent (determined by file scope in spec)

**Steps:**
1. **Determine scope** — API-only, Web-only, or Both (from spec's file list)
2. **For API + Web changes:** API first → codegen check (regenerate frontend API client from backend spec) → Web second. Never parallel — frontend depends on backend types
3. **Delegate to implementer agent(s)** with:
   - The approved spec (relevant section only)
   - Pre-read file contents from Phase 2 (save agent from re-reading)
   - Project conventions
   - Explicit constraints: "Do NOT run git add/commit/push", "Do NOT introduce features beyond the spec"
4. **Agent implements and reports:** files changed, what was done, any issues encountered

**Agent delegation template:**

```markdown
## Task
[Specific change from the spec — NOT the entire spec, just the agent's portion]

## Pre-Inlined Context
[Paste file contents you already read — saves agent from re-reading]

## Codebase Conventions
Match existing patterns exactly. Find the closest existing example and follow it.

## Requirements
- Follow project conventions from docs/
- Do NOT run git add/commit/push — the orchestrator handles git
- Run the project's test/lint command after changes
- Report: files changed, what was done, any issues encountered
```

**Agent selection by task type (from claude-pipeline):** Different tasks in the same feature can go to different agents — backend DAO work → backend-agent, frontend component → frontend-agent, shared types → whichever agent owns the upstream change.

**Parallel execution rules:**
- Backend and frontend agents can run in parallel ONLY if they touch completely different files
- If frontend depends on backend types (codegen), always sequential: backend → codegen → frontend
- Within the same stack, parallel agents MUST use worktree isolation to prevent file conflicts (GSD, Metaswarm)

**Error handling during implementation:**
| Failure | Response | Max attempts |
|---|---|---|
| Agent reports issues but completes | Proceed to validation, let validation catch real problems |  — |
| Agent times out | Re-dispatch with the same prompt | 1 retry |
| Agent produces garbage | Re-dispatch with more context + model escalation (Sonnet → Opus) | 1 retry |
| Agent is BLOCKED | Escalate to user with exact blocker description | — |

**Sources:** GSD (wave-based parallel executors with atomic commits), Metaswarm (per-WU IMPLEMENT phase with file scope), Superpowers (fresh subagent per task, controller provides all text)

#### Work Unit decomposition and wave-based parallelism (research-backed)

**Why decompose beyond backend/frontend?** Research data strongly favors finer-grained task decomposition:

| Task Granularity | Success Rate | Source |
|---|---|---|
| Function-level (1-3 files) | ~87% | [Augment Code multi-agent guide](https://www.augmentcode.com/guides/multi-agent-ai-system-code-development) |
| Module-level (3-8 files) | ~19-45% | Same source |
| Feature-level (8+ files) | ~19% | Same source |

**Multi-agent vs single-agent quality:**
- AgentCoder (3 specialized agents: programmer + test designer + test executor): **96.3% pass@1** on HumanEval with **56.9K tokens** — beats single-agent at 90.2% with 138.2K tokens. Fewer tokens AND better quality because separating code from test design prevents self-confirmation bias. ([Paper](https://arxiv.org/abs/2312.13010))
- AgentConductor (dynamic topology, 2026): **+14.6% accuracy** over fixed multi-agent, **68% token cost reduction** via difficulty-aware agent count — easy tasks get 2-3 agents, hard tasks get 5-7. ([Paper](https://arxiv.org/abs/2602.17100))

**Optimal agent count:** 2-4 agents per wave is the sweet spot. Beyond 5-7, coordination overhead and merge conflicts eat gains. One study found 30-50% of parallelism gains lost to conflict resolution when tasks weren't properly scoped. ([Source](https://natesnewsletter.substack.com/p/why-dumb-agents-mean-smart-orchestration))

**Conflict rates:**
- With spec-scoped tasks + git worktrees: **3.1% conflict rate** across 109 waves
- Without isolation: **40-60% conflict rate**
- ([Source](https://zenvanriel.com/ai-engineer-blog/running-multiple-ai-coding-agents-parallel/))

**Recommended decomposition pattern:**

1. **Read the architecture spec's file list** — the architect already identified which files change
2. **Group files into Work Units (WUs)** — tightly coupled files (service + its tests + its types) form one WU. Independent clusters form separate WUs.
3. **Identify hotspot files** (routing tables, config, barrel exports) — these are edited last by the orchestrator, never delegated
4. **Arrange WUs into dependency waves:**
   - Wave 1: WUs with no dependencies (run in parallel)
   - Wave 2: WUs depending on Wave 1 outputs (run in parallel after Wave 1)
   - Hotspot wave: Orchestrator edits shared files last
5. **Spawn all agents in a wave in a single message** for parallel execution
6. **Same-stack parallel agents** use `isolation: "worktree"`

**When NOT to decompose:** Total change ≤3 files, or all files tightly coupled → single agent, no waves. Don't decompose just because you can.

**Framework comparison:**

| Framework | Decomposition strategy | Parallelism model | Isolation |
|---|---|---|---|
| **Metaswarm** | Per-Work-Unit with explicit file scope + DoD | Parallel within phase, gates between phases | Lock-based |
| **GSD** | Wave-based dependency graph, atomic commits per wave | Parallel within waves, sequential between | Fresh 200K context per agent |
| **Citadel** | Fleet pattern, discovery relay between waves | Worktree Fleet execution | Git worktrees |
| **Cursor 2.0** | Up to 8 parallel agents, auto-selects best result | Per-file isolation | Git worktrees |
| **Orchestrator Kit** | 1 Task = 1 Agent via speckit.implement | Sequential pipeline | Per-agent context |
| **claude-pipeline** | Per-task `claude -p` calls with JSON schemas | Sequential with parallelizable substeps | CLI isolation |

**Key insight (report line 1154):** "Isolate at the code-writing boundary, not the orchestration boundary." The orchestrator needs shared context for routing decisions. Implementation agents need isolation for clean reasoning.

#### Phase 4: Validate (automated)

**Purpose:** Independently verify the implementation works. Never trust agent self-reports.

**Who:** Main skill (inline). Runs commands directly, not via subagent.

**Steps:**
1. **Autofix:** Run lint/format fix (e.g., `pnpm lint:fix`)
2. **Full check:** Run the project's build + lint + test command and capture output to a file
3. **Codegen check:** If DTOs/controllers changed, regenerate API client and re-run full check
4. **Startup check (medium+ complexity):** Boot the app, wait 15s, check for DI/compilation errors, kill
5. **Test coverage check:**
   - Find spec files adjacent to changed source files
   - If spec exists but doesn't cover the change → delegate to implementer agent: "Add test cases for X"
   - If no spec exists and non-trivial logic changed → delegate to implementer agent: "Create spec file, test X"
   - Run affected tests after any new/updated specs

**Fix loop (max 2 rounds):**
1. Lint/format only? → autofix, re-check
2. Type/build/test errors? → delegate to implementer with exact error output, re-check
3. After each fix, re-run codegen check → re-run full check
4. After 2 failed rounds → present structured handoff to user:

```markdown
## Remaining Failures
### Fixed
- [what was fixed, which round]
### Still failing
- **Error**: [message] — **File**: [path:line] — **Suggested fix**: [steps]
### CI status
- Lint: PASS/FAIL — Types: PASS/FAIL — Build: PASS/FAIL — Tests: N/M passing
```

**Key rule (from Metaswarm):** The ORCHESTRATOR runs validation commands itself. Never trust the implementer agent's claim that "tests pass." The agent may have run a subset, or run them in a different way, or hallucinated the output.

**Sources:** Metaswarm (VALIDATE phase runs independently: tsc + eslint + tests + coverage), GSD (cross-phase regression gate), claude-pipeline (test stage with up to 10 iterations)

#### Phase 5: Review (automated with fix loops)

**Purpose:** Check the code for bugs, security issues, architectural drift, test quality, and guideline compliance.

**Who:** Orchestrator spawns parallel reviewer-agents with pre-inlined criteria files from `.claude/skills/review/` (see [Skill Composition Pattern 1](#skill-composition-patterns-expanded)). Do NOT use "read SKILL.md and follow" — the review skill has its own multi-agent orchestration that breaks when loaded inline.

**Steps:**
1. Pre-read review criteria files (`bugs-criteria.md`, `security-criteria.md`, `architecture-criteria.md`, `tests-criteria.md`, `guidelines-criteria.md`). Spawn 5 parallel reviewer-agent instances, each with its criteria pre-inlined. Run judge pass to validate and confidence-score findings.
2. Run the full review grid — do not simplify or scope down the review
3. Process results:
   - **CHANGES REQUIRED** → fix loop: delegate to implementer, re-validate (Phase 4 step 2 only), re-review. Max 1 fix round for review findings
   - **APPROVED WITH MINOR** → fix MEDIUM+ findings only, then proceed
   - **APPROVED** → proceed directly

**Two-stage review (from Superpowers, claude-pipeline):** Check spec compliance ("did we build the right thing?") BEFORE code quality ("did we build it well?"). If spec compliance fails, code quality review is wasted.

**Sources:** All frameworks. See [Review Pipeline](#review-pipeline) section for detailed patterns.

#### Phase 6: Ship (WAIT)

**Purpose:** Present results and commit/push with user approval.

**Who:** Main skill (inline).

**Steps:**
1. **Present summary:**
   ```
   Done. Here's what changed:
   - [file]: [what changed]
   - full-check: PASS/FAIL
   - Review: [verdict]
   - Test coverage: [covered / gaps noted / tests added]
   ```
2. **User review gate** — options:
   - "Looks good" → proceed to commit decision
   - "Needs tweaks" → apply changes, re-validate, re-review if 10+ lines changed, loop back to this gate
   - "Done" → leave uncommitted, skip to cleanup
3. **Learn & Improve (medium+ complexity):** Before committing, scan conversation for learnings (user corrections, discovered problems, workarounds). Save to memory. Check if pipeline rules need updating. This runs BEFORE commit so doc/rule changes are included
4. **Ship decision** — use `AskUserQuestion` with options:
   - A) **Commit** → stage and commit on current branch with conventional commit message
   - B) **Commit + push** → commit and push to remote
   - C) **Commit + PR** → commit, push, and create PR via `gh pr create` (summary auto-generated from pipeline results)
   - D) **Review diff first** → show full diff, then re-ask
   - E) **Leave uncommitted** → leave changes staged, user handles manually
5. **Cleanup** — kill any orphaned processes on dev ports

**Tweak loop safety:** After 3 tweak rounds, suggest creating a new `/follow-up` for remaining changes (scope creep prevention).

**Why structured ship options matter:** Superpowers offers 4 options at branch finish (merge/PR/keep/discard). Metaswarm auto-creates PRs via PR Shepherd. GSD ships via `gh`. The "Commit + PR" option is the most requested workflow — users implementing features almost always want a PR, and having the agent auto-generate the PR description from pipeline results (spec, review findings, test coverage) saves significant time.

**Sources:** GSD (`gsd:ship`), Superpowers (4 options at branch finish: merge/PR/keep/discard), Metaswarm (PR Shepherd auto-monitors to merge)

### Lightweight changes (`/follow-up` skill)

Not every change needs the full pipeline. A `/follow-up` skill handles post-implementation tweaks with reduced ceremony.

**When to use:** Tweaks, fixes, style changes, missing fields — anything that doesn't need discovery or architecture.

**When NOT to use (hard escalation signals):**

| Signal | Why it escalates |
|---|---|
| New entity, table, or migration | Irreversible schema change |
| New API endpoint or new page/route | Cross-stack coordination, auth decisions |
| Auth, permissions, or role changes | Infinite blast radius |
| New module or module layer promotion | Architectural decision |
| 3+ modules coordinated | Distributed-transaction-level coordination |
| New async/queue work | Runtime failure modes not caught by tests |
| Ambiguous intent | Multiple valid design approaches |

**Complexity levels (from cross-framework analysis):**

| Level | Files | Modules | Pipeline |
|---|---|---|---|
| **Trivial** | 1-2 | 1 | Implement directly (no subagent), skip review, skip architecture |
| **Small** | 3-5 | 1-2 | Delegate to agent, full review, skip architecture |
| **Medium** | 6-8 | 1-2 | Delegate to agent, brief plan (user approves), full review |
| **Too large** | 9+ or any hard signal | — | Escalate to `/implement` |

**Key insight:** File count is a smell detector, not a complexity detector. A 2-file change adding a new entity is "Too large." A 7-file change propagating an existing filter through DTO → service → query → hook → test is "Medium."

**Follow-up pipeline:**

```
Assess complexity → [Implement] → Validate → Review (full, not simplified) → Ship (WAIT)
```

**Sources:** GSD (`gsd:fast` for trivial, `gsd:quick` for small with guarantees), claude-pipeline (different skill per complexity level)

### Human-in-the-loop design

Cross-framework consensus on where and how to involve the user:

#### Mandatory gates (never skip)

| Gate | When | What to ask | Options |
|---|---|---|---|
| **Requirements confirmation** | End of Phase 1 | "Here's what I understand. Correct?" | Confirm / Adjust / Add details |
| **Spec approval** | End of Phase 2 | "Here's the plan. Proceed?" | Approve / Adjust / Split / Escalate to user |
| **Ship decision** | Phase 6 | "Here's what changed. Ship?" | Commit / Commit+push / Tweaks / Leave as-is |
| **Escalation** | Any phase failure after max retries | "I'm stuck. Here's what happened." | Fix manually / Try different approach / Abort |

#### Optional gates (skip for speed)

| Gate | When | When to skip |
|---|---|---|
| **Plan detail review** | Phase 2 for medium complexity | Trivial and small changes |
| **Pre-review summary** | Before Phase 5 | When validation passes clean |
| **Learn & improve** | Phase 6 for medium complexity | Trivial changes |

#### Question design best practices (from GSD, Superpowers)

- **Batch questions** — don't ask one at a time, group related decisions
- **Always provide 2-4 concrete options** with short labels and descriptions
- **Include a recommended default** — the user should be able to just press Enter
- **Auto-add "Other" option** for custom input
- **Never ask open-ended questions** — "What do you want?" is bad; "Choose: A, B, C, or describe" is good
- **Skip questions already answered** — if the user's original request or a previous conversation resolved a gray area, don't re-ask (GSD cross-phase dedup)

**Sources:** GSD (structured questions with auto/batch modes), Superpowers (multiple choice preferred, one question at a time), Metaswarm (escalation with Override/Revise/Simplify/Cancel options)

### Agent delegation best practices

How to delegate work to implementer agents effectively:

| Practice | Detail | Source |
|---|---|---|
| **Pre-inline file contents** | Read files in the skill, paste contents into the agent prompt. Saves the agent from re-reading and ensures it has the right version | Superpowers ("controller provides all text directly"), GSD |
| **Scope strictly** | Agent gets only its portion of the spec, not the entire plan. Reduces context noise | All frameworks |
| **Fresh agent per task** | Each task gets a clean 200K context window with zero accumulated garbage. Never reuse an agent across tasks | GSD (core principle), Superpowers |
| **Include project conventions** | Agent needs to know patterns, naming, file organization. Either inline key rules or reference the docs path | All frameworks |
| **Explicit "do NOT" constraints** | "Do NOT run git commands", "Do NOT introduce features beyond spec", "Do NOT modify files outside scope" | All frameworks |
| **Require structured reporting** | Agent must report: files changed, what was done, any issues. This is what the orchestrator verifies against | Metaswarm |
| **Model selection by task type** | Mechanical tasks (rename, add field) → Sonnet. Architecture/integration → Opus. Exploration → Haiku | Superpowers, GSD (model profiles) |

### State persistence during long pipelines

Long pipelines (especially `/implement`) may hit context compaction. File-based state ensures the pipeline can resume.

| Mechanism | What to persist | When | Source |
|---|---|---|---|
| **Phase checkpoint file** | Current phase, completed phases, key decisions, files changed, pending work | After each phase completes | GSD (`.planning/STATE.md`), Citadel (campaign files), claude-pipeline (`status.json`) |
| **Resume-on-startup check** | If checkpoint file exists, read it and resume from recorded phase | At skill start | All frameworks with persistence |
| **Spec and plan as files** | Write approved spec/plan to a file in the repo, not just conversation memory | After Phase 2 approval | Superpowers (`docs/superpowers/specs/`), GSD (`.planning/`) |
| **Handoff file for session breaks** | Machine-readable state + human-readable context summary | On pause or session end | GSD (`HANDOFF.json` + `continue-here.md`) |

**Key principle (from GSD, Metaswarm):** Agents should be **amnesiac by design** — they rebuild context from checkpoint files, not from conversation memory. Each agent invocation includes the checkpoint state in its prompt.

### Error handling across phases

| Phase | Failure type | Response | Max retries | Escalation |
|---|---|---|---|---|
| **Discover** | User abandons | Proceed with defaults or stop | — | — |
| **Architect** | Skeptic rejects spec | Architect revises, re-validate | 3 | Present best attempt + issues to user |
| **Implement** | Agent timeout | Re-dispatch same prompt | 1 | Escalate to user |
| **Implement** | Agent BLOCKED | — | — | Escalate immediately with blocker description |
| **Implement** | Agent produces wrong output | Re-dispatch with more context + model escalation | 1 | Escalate to user |
| **Validate** | Lint/format errors | Autofix, re-check | 1 | — |
| **Validate** | Type/build/test errors | Delegate fix to implementer, re-check | 2 | Structured handoff to user |
| **Review** | CHANGES REQUIRED | Fix, re-validate, re-review | 1 (within /follow-up), 3 (within /implement) | Report outstanding issues to user |
| **Ship** | User wants tweaks | Apply, re-validate, re-review if 10+ lines | 3 tweak rounds | Suggest new `/follow-up` |

**Node repair strategies (from GSD):**
- **RETRY** — attempt the same task with a concrete adjustment (more context, different approach hint)
- **DECOMPOSE** — break the failing task into smaller sub-steps
- **PRUNE** — remove unachievable task, document what was skipped, escalate to user

### Edge cases

| Edge case | How to handle | Source |
|---|---|---|
| **Scope creep during tweaks** | After 3 tweak rounds in Ship phase, suggest new `/follow-up` or `/implement`. Track cumulative lines changed | GSD (seeds system), Superpowers (decompose into sub-projects) |
| **User changes requirements mid-pipeline** | Return to the earliest affected phase. If spec changes, re-run architect. If just tweaks, apply in current phase | GSD (`/gsd:insert-phase`), claude-code-skills (`ln-222-story-replanner`) |
| **Compaction during long pipeline** | File-based checkpoints survive compaction. Critical rules in CLAUDE.md survive. PostCompact hook can trigger re-read of checkpoint | GSD (context monitor warns at 35%/25%), Citadel (campaign files + pre-compact hooks) |
| **Multi-stack changes (backend + frontend)** | Always sequential: backend → codegen → frontend. Never parallel when types flow between stacks | Project-specific (no framework handles this generically) |
| **API/type regeneration after backend changes** | After modifying DTOs or controllers, regenerate frontend API client before proceeding to frontend work. Re-run validation after codegen | Project-specific |
| **Multiple independent subsystems** | Decompose at discovery. Each subsystem gets its own pipeline cycle. Or use wave-based parallelization for independent changes | GSD (wave-based), Superpowers (decompose before planning) |
| **Agent produces code that passes tests but doesn't match spec** | Two-stage review catches this: spec compliance review BEFORE code quality review. The spec reviewer checks "did we build the right thing?" | Superpowers, claude-pipeline |
| **Existing tests break after implementation** | Cross-phase regression gate: run ALL tests, not just new ones. If existing tests fail, it's a signal the implementation has side effects | GSD (cross-phase regression gate), Metaswarm (VALIDATE runs full test suite) |

### Pipeline comparison: full vs lightweight

| Aspect | `/implement` (full pipeline) | `/follow-up` (lightweight) |
|---|---|---|
| **Discovery** | Full gray area elimination | Skip — change is clear |
| **Architecture** | Architect + skeptic + user approval | Skip (trivial/small) or brief plan (medium) |
| **Implementation** | Delegated to agents | Direct (trivial) or delegated (small/medium) |
| **Validation** | Full check + codegen + startup + test coverage | Full check + codegen |
| **Review** | Full review grid (not simplified) | Full review grid (not simplified) |
| **Fix loops** | Max 3 rounds | Max 1 round (review), max 2 rounds (validation) |
| **Ship** | Full ceremony: summary + tweaks + learn + commit | Summary + tweaks + commit |
| **Complexity gate** | Always runs | Assesses first, escalates to `/implement` if too large |

## Skill Composition Patterns (expanded)

Since skills cannot call other skills directly ([#17351](https://github.com/anthropics/claude-code/issues/17351)), frameworks have developed workarounds ranging from simple file reads to sophisticated state machines. The table in the [Skills](#skills) section lists 7 patterns — this section provides detailed implementation guidance for each.

### What frameworks implement

| Pattern | Metaswarm | GSD | Superpowers | claude-pipeline | ECC | Citadel | Claude Forge | Beads | gstack | Claude-Code-Skills |
|---|---|---|---|---|---|---|---|---|---|---|
| **File-reading composition** | — | — | — | — | — | — | — | — | — | — |
| **CLAUDE.md workflow intercepts** | Mandatory gates | — | — | — | — | — | — | — | — | — |
| **Bootstrap chain** | — | — | `using-superpowers` | `using-skills` | `skill-comply` | — | — | — | — | — |
| **Trigger chains** | `auto_activate` + `triggers` | — | — | — | — | — | — | — | — | — |
| **Orchestrator scripts** | — | State machine (state.cjs) | — | Shell scripts | — | `/do` router | — | — | — | L0 meta-orchestrator |
| **Agent routing via frontmatter** | — | `agent: gsd-planner` | — | — | — | — | — | — | — | — |
| **Dynamic context injection** | — | — | — | — | — | — | — | — | — | — |
| **Pipeline state files** | BEADS + active-plan.md | STATE.md (schema-backed) | — | status.json | — | Campaign files | — | Molecules | — | CLI checkpoints |
| **Session cycling / handoff** | — | continue-here.md | — | — | — | — | — | Mail system | — | — |
| **Hook-to-agent injection** | — | Context monitor → bridge file | — | — | PreToolUse/PostToolUse | Pre-compact hooks | Work tracker pipeline | — | — | — |
| **Discover-ask-persist** | — | — | — | — | — | — | — | — | CLAUDE.md discovery | — |

### Pattern 1: Shared Reference Files + Subagent Delegation (recommended default)

**Updated 2026-04-04.** The previous recommendation ("read SKILL.md and follow its instructions inline") has significant limitations discovered through production use and confirmed by community research. Reading a SKILL.md file does NOT trigger skill infrastructure — `context: fork`, `model:`, `allowed-tools:` frontmatter fields are all ignored ([Claude Code Skills Docs](https://code.claude.com/docs/en/skills)). For skills with their own orchestration logic (like `/review` with its 5 parallel reviewers + judge pass), "reading and following" a complex multi-agent orchestrator inline pollutes the consuming skill's context and ignores the skill's isolation guarantees.

**Recommended pattern:** Extract reusable knowledge into supporting `.md` files alongside the skill, then have consuming skills pre-inline that knowledge into subagent prompts.

```
# Directory structure
skills/
├── simplify/
│   ├── SKILL.md              ← process (Scope → Analyze → Fix → Verify)
│   └── simplify-criteria.md  ← knowledge (3 analysis passes, severity, anti-patterns)
├── review/
│   ├── SKILL.md              ← process (Collect → Spawn Reviewers → Judge)
│   ├── bugs-criteria.md      ← knowledge (logic errors, null checks, state issues)
│   ├── security-criteria.md  ← knowledge (injection, auth, secrets)
│   ├── architecture-criteria.md
│   ├── tests-criteria.md
│   └── guidelines-criteria.md
└── implement/
    └── SKILL.md              ← orchestrator — pre-reads criteria files, spawns subagents
```

```markdown
# In implement/SKILL.md Phase 6 (Simplify):
## Step 1: Spawn simplify agent
Pre-read `.claude/skills/simplify/simplify-criteria.md`.
Spawn a general-purpose subagent with pre-inlined criteria content.
Agent applies P1/P2 fixes, reports results.
Orchestrator verifies CI, reverts if broken.

# In implement/SKILL.md Phase 7 (Review):
## Step 2: Spawn parallel reviewers
Pre-read 5 criteria files from `.claude/skills/review/`.
Spawn 5 parallel reviewer-agent instances, each with its criteria pre-inlined.
Judge pass validates findings with confidence scoring.
```

**Why this is better than "read and follow":**

| Approach | Context cost | Skill infrastructure | Orchestration | Single source of truth |
|---|---|---|---|---|
| Read SKILL.md inline | High (~5-15K tokens for complex skills) | Lost (frontmatter ignored) | Pollutes consuming skill's context | Yes but fragile |
| Shared reference + subagent | Low (~1-3K per criteria file) | Preserved (subagent runs with own context) | Clean delegation | Yes, robust |
| Inline the logic (copy) | Zero read cost but duplicated | N/A | Self-contained | No — drift risk |

**Evidence:**
- oh-my-claudecode ([Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)): uses inline logic pattern — `autopilot` SKILL.md contains full workflow inline, delegates via `Task(subagent_type=...)` calls, never invokes other skills via Skill tool
- GSD ([gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done)): each skill is self-contained with its own instructions, avoids nested Skill tool calls entirely
- [Claude Code Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices): "When workflows become large or complicated with many steps, consider pushing them into separate files and tell Claude to read the appropriate file based on the task at hand" — supports the reference file extraction pattern
- GitHub [#17351](https://github.com/anthropics/claude-code/issues/17351): multiple users confirm skill B executes but control never returns to skill A. Users `him0`, `bgeesaman`, `corticalstack` all report the same failure mode
- GitHub [#30256](https://github.com/anthropics/claude-code/issues/30256): `context: fork` does NOT fix nested skill composition — same premature exit
- GitHub [#39163](https://github.com/anthropics/claude-code/issues/39163): feature request for `/compose` command — not yet implemented, confirming no official composition mechanism exists

**Best for:** Pipeline skills that need another skill's knowledge (criteria, patterns, rules) but need to run the process themselves via subagent delegation. This is the most common case — `/implement` needs `/review`'s criteria but runs its own review orchestration.

### Pattern 1b: Read SKILL.md Inline (simple skills only)

For simple, instruction-only skills with no orchestration logic and no infrastructure dependencies (`context: fork`, `model:`, `allowed-tools:`), reading the SKILL.md inline still works:

```markdown
Read `.claude/skills/simple-skill/SKILL.md` and follow its instructions.
```

**Caveats:** Frontmatter is loaded as text but NOT interpreted — no model switching, no context forking, no tool restrictions. Only use when the skill is pure instructions with no infrastructure needs.

**Best for:** Skills that are essentially checklists or rule sets, not orchestrators.

### Pattern 2: CLAUDE.md Workflow Intercepts (from Metaswarm)

Global enforcement rules that fire regardless of which skill is active:

```markdown
## Workflow Enforcement (MANDATORY)
- After brainstorming completes -> STOP -> run design-review-gate
- After any plan is created -> STOP -> run plan-review-gate
- After any implementation -> STOP -> run validation-gate
```

**Pros:** Enforced globally — no skill can bypass gates. **Cons:** Heavier CLAUDE.md, consumes instruction slots.

**Best for:** Mandatory quality gates that must fire across ALL workflows. Metaswarm uses this for review gates that no skill should be able to skip.

### Pattern 3: Leaf Skills + Sequential Orchestrator (from Citadel)

Skills are atomic leaf protocols that do one thing. An orchestrator (Citadel's `/do` router) chains them sequentially, never nesting:

```
/do "implement auth feature"
  → Pattern Match → Keyword Lookup → LLM Classify
  → Route to: /plan → /implement → /review → /ship
```

Each skill returns control to the orchestrator, which decides the next skill. Router dispatches once per step.

**Pros:** Clean separation. No nesting issues. Each skill is testable independently.
**Cons:** Orchestrator is complex. State must be passed via files between skills.

**Best for:** Large skill collections (Citadel has 40 skills) where nesting would be fragile.

### Pattern 4: Skill() vs Agent() Split (from Claude-Code-Skills)

Use `Skill()` (shared context, `context: main`) for coordination and `Agent()` (isolated context, `context: fork`) for implementation:

```
L0 Meta-Orchestrator (Skill, shared context)
  → L1 Feature Coordinator (Skill, shared context — sees user decisions)
    → L2 Domain Coordinator (Skill, shared context)
      → L3 Worker (Agent, isolated context — clean 200K window)
```

**Key insight:** "Isolate at the code-writing boundary, not the orchestration boundary." Coordination needs shared context to make routing decisions. Implementation needs isolation to prevent context pollution.

**Best for:** Deep skill hierarchies where coordination spans multiple levels.

### Pattern 5: Schema-Backed State Files (from GSD)

Skills communicate via a structured state file with a defined schema, not ad-hoc file reads:

```markdown
<!-- .planning/STATE.md -->
## State
- Phase: execute
- Status: in_progress
- Last activity: 2026-04-01T14:30:00Z
- Progress: 3/5 tasks complete

## Accumulated Context
- Decision: use FilterQuery<T> for all DAOs (Phase 1)
- Blocker: Redis connection timeout resolved (Phase 3)

## Session Continuity
- Resume file: .planning/.continue-here-abc123.md
- Stopped at: Task 4 — implementing thread.service.ts
```

GSD's `state.cjs` library provides atomic read-patch-write operations on this file. Each skill reads state first, operates, then patches state back.

**Pros:** Survives compaction. Multiple skills share state without conversation memory. Schema prevents drift.
**Cons:** Requires discipline to maintain. State can become stale if a skill crashes mid-update.

**Best for:** Multi-phase pipelines where state must persist across sessions and compaction events.

### Pattern 6: Session Cycling via Mail/Handoff (from Beads)

When a session needs to cycle (context exhaustion, logical breakpoint), the outgoing agent sends "mail" to its own address:

```
/handoff
  → Write context summary + pending work to mail file
  → Run respawn command (new claude session)
  → New session: SessionStart hook reads mail, primes context
```

Beads calls persistent work items "molecules" — they survive session boundaries while ephemeral state resets.

**Pros:** Enables infinite-length workflows beyond single context window. Clean context per session.
**Cons:** Loss of nuance between sessions. Requires careful state serialization.

**Best for:** Long-running tasks that exceed context limits. Multi-day workflows.

### Pattern 7: Hook-to-Agent Context Injection (from GSD, Claude Forge)

Hooks produce data that other hooks or agents consume, creating a pipeline outside the conversation:

```
StatusLine hook → writes metrics to /tmp/claude-ctx-{session_id}.json
PostToolUse hook → reads bridge file → injects additionalContext warnings
Agent → receives context monitor warnings in conversation
```

GSD's `gsd-context-monitor.js` uses this two-hook pipeline: one hook writes (statusline), another reads and injects (PostToolUse). Claude Forge's work tracker uses three hooks: prompt hook → tool hook → stop hook for session-spanning telemetry.

**Pros:** 100% deterministic (hooks always fire). External to conversation. No context cost until injection.
**Cons:** Complex to debug. Bridge file race conditions possible.

**Best for:** Observability, cost tracking, context monitoring — signals that need 100% capture without consuming context.

### Pattern 8: Discover-Ask-Persist (from gstack)

Skills never hardcode project-specific commands. Instead, they discover configuration from CLAUDE.md, ask the user if missing, and persist the answer:

```
1. Read CLAUDE.md for test command → found: "pnpm test:unit"
2. Read CLAUDE.md for lint command → NOT FOUND
3. Ask user: "What's your lint command?"
4. User: "pnpm lint:fix"
5. Write "pnpm lint:fix" back to CLAUDE.md
6. Future sessions skip the question
```

**Pros:** Skills stay generic and portable across projects. Knowledge accumulates.
**Cons:** First-run friction. CLAUDE.md grows.

**Best for:** Reusable skill packages that must work across different repositories.

### Composition pattern selection guide

| Situation | Recommended pattern |
|---|---|
| Pipeline skill needing another skill's knowledge (criteria, rules) | Pattern 1 (shared reference files + subagent delegation) |
| Simple skill with no orchestration or infrastructure needs | Pattern 1b (read SKILL.md inline) |
| Mandatory gates that no workflow can bypass | Pattern 2 (CLAUDE.md intercepts) |
| Large skill collection (20+) | Pattern 3 (leaf + orchestrator) |
| Deep hierarchy with coordination + implementation | Pattern 4 (Skill/Agent split) |
| Multi-phase pipeline needing session persistence | Pattern 5 (state files) |
| Workflows exceeding context window | Pattern 6 (session cycling) |
| Observability signals needing 100% capture | Pattern 7 (hook-to-agent) |
| Reusable skills across different repos | Pattern 8 (discover-ask-persist) |

---

## AskUserQuestion Tool Usage in Skills

### Problem: Tool in allowed-tools but never referenced in body

A common antipattern: skills list `AskUserQuestion` in their `allowed-tools` frontmatter but never explicitly instruct when or how to use it in the skill body. When the skill says "ask the user" without specifying the tool, Claude defaults to outputting plain text questions — which means the user doesn't get the structured multiple-choice interface that `AskUserQuestion` provides.

### Audit findings

| Skill | Had in allowed-tools | Body referenced tool? | Action taken |
|-------|---------------------|----------------------|--------------|
| **implement** | Yes | No — said "Ask structured discovery questions" | Fixed: explicit `AskUserQuestion` tool calls in Phase 1 discovery + error handling table |
| **spec** | Yes | No — said "Present gray areas as multiple-choice questions" | Fixed: explicit `AskUserQuestion` in Section 4 + follow-up question |
| **follow-up** | Yes | No — said "ask user to confirm" | Fixed: explicit `AskUserQuestion` for medium complexity confirmation + deletions + escalation |
| **debug** | Yes | No — no user interaction step existed | Fixed: added `AskUserQuestion` instruction in Observe step for unclear reproduction |
| **improve** | Yes | No — said "verified via user feedback" without specifying how | Fixed: added `AskUserQuestion` for uncertain learning verification |
| **onboard** | Yes | No — skill never asks user anything | Removed from allowed-tools (unnecessary) |
| **features** | Yes | No — commands are explicit, no questions needed | Removed from allowed-tools (unnecessary) |
| **ui-review** | Yes | No — automated inspection, no questions needed | Removed from allowed-tools (unnecessary) |

### Best practice

When a skill needs user input, the instruction must be **tool-specific**:
- Bad: "Ask the user which approach they prefer"
- Good: "Use the `AskUserQuestion` tool to present approach options to the user"

Without the explicit tool name, Claude will output text questions and continue without waiting for a structured response. The `AskUserQuestion` tool forces a blocking interaction — Claude must wait for the user's selection before proceeding.

### When to include AskUserQuestion

Include in `allowed-tools` AND reference in the body when:
- Skill has a discovery/clarification phase (implement, spec)
- Skill needs user confirmation before destructive actions (follow-up deletions)
- Skill needs user input to validate uncertain information (improve, debug)
- Skill has branching paths that depend on user preference

Do NOT include when:
- Skill is fully automated (review, ui-review, onboard)
- Skill operates on explicit commands with no ambiguity (features)
- Skill runs in `context: fork` with no user interaction expected

---

## Git Workflow for AI Coding Agents

### The problem: agents working on unprotected branches

AI coding agents that implement features directly on `main` or the user's current branch create risk: partial implementations can't be easily reverted, parallel agent runs conflict with each other, and there's no clean rollback path if the implementation goes sideways.

### What frameworks implement

| Framework | Branch strategy | Commit approach | Ship options | Worktree support |
|---|---|---|---|---|
| **GSD** | Wave-based, atomic commits per wave | Auto-commit after validation | PR via `gh` | Worktree isolation for parallel agents |
| **Metaswarm** | Per-work-unit isolation | Auto-commit after review pass | PR Shepherd (auto-monitors to merge) | Lock-based file claiming |
| **Superpowers** | Per-task fresh agents | Per-agent commits | 4 options: merge/PR/keep/discard | Agent isolation (fresh context) |
| **Cursor 2.0** | Up to 8 parallel agents | Per-file commits | Auto-PR | Git worktrees |
| **Aider** | Works on current branch | Auto-commit every change with `(aider)` attribution | Manual push | N/A (single agent) |
| **Agent Factory** | Session = single branch, dies on completion | Auto-commit | Auto-PR | Branch-per-agent isolation |

### Research findings

**Branch isolation is the consensus:**
- "Running an agent directly on your main branch is asking for trouble. Always use a feature branch, and if you are running multiple agents, use worktrees." — [Addy Osmani, Code Agent Orchestra](https://addyosmani.com/blog/code-agent-orchestra/)
- Claude Code natively supports `--worktree` flag for isolated development environments
- Cursor's parallel agents use git worktrees by default ([Cursor docs](https://cursor.com/docs/configuration/worktrees))
- The Agent Factory pattern ties each agent session to a single branch — "separation creates resilience through isolation" ([Leo Cardz, 2026](https://leocardz.com/2026/04/01/how-i-built-an-agent-factory-that-ships-code-while-i-sleep))

**Commit strategy varies:**
- Aider: auto-commits everything with attribution metadata — transparent, no user decision needed at end
- Metaswarm/GSD: auto-commit after validation passes, user decides on PR
- Superpowers: full user choice at end (merge/PR/keep/discard)
- Anthropic best practices: smaller, focused commits with conventional commit messages ([Claude Code docs](https://code.claude.com/docs/en/common-workflows))

**Key insight — ask at start, not just at end:**
Most frameworks only ask about git at the END (commit/push decision). But asking at the START — where to work (new branch, current branch, worktree) — is more impactful because it determines the safety envelope for the entire implementation. A feature branch created at the start gives 100% rollback capability regardless of what happens during implementation.

### Recommended approach

**Phase 1 (Discovery) — ask where to work:**
1. New feature branch (default) — `feat/<feature-name>` from HEAD
2. Current branch — if already on a feature branch
3. Git worktree — for risky changes or parallel implementations

In auto mode: default to new feature branch. If on `main`/`master`: always create branch (never implement directly on main).

**Phase 6 (Ship) — ask what to do with results:**
1. Commit — stage and commit with conventional message
2. Commit + push — commit and push to remote
3. Commit + PR — commit, push, and create PR with auto-generated description
4. Review diff first — show diff, then re-ask
5. Leave uncommitted — user handles manually

Both questions use `AskUserQuestion` tool for structured interaction.

---

## Validation Command Auto-Discovery

### The problem: hardcoded validation commands

Setup scripts typically detect the language/framework and assign hardcoded default commands (`npm run build`, `pytest`, `cargo test`). This misses project-specific scripts, custom task runners, and commands that vary between projects using the same stack. The result: CLAUDE.md has wrong commands, Phase 4 validation runs the wrong checks, and agents fail silently.

### What tools and frameworks implement

| Tool | Discovery method | Sources scanned | User confirmation | Commands discovered |
|---|---|---|---|---|
| **Claude Code** | Reads CLAUDE.md/AGENTS.md for explicit commands | Config files only | N/A (manual config) | Whatever user documents |
| **Nx** | `nx init` scans workspace, emits structured JSON | package.json, project.json, workspace config | Auto-generates config | build, test, lint, e2e, serve |
| **Turborepo** | Reads package.json scripts, builds task graph | package.json per workspace | turbo.json defines pipeline | Any script name |
| **Aider** | `.aider.conf.yml` + env vars | Config files | Manual | test, lint |
| **AGENTS.md standard** | Explicit documentation | Developer-written file | N/A | Any command |

### Research findings

**Multi-source discovery is the standard:**
Projects define commands in multiple places — package.json scripts, Makefile targets, Taskfile recipes, justfile, pyproject.toml, and more. A setup script should scan all available sources and merge them with priority (explicit scripts > task runners > language defaults).

**Package manager detection matters:**
Using `npm run test` when the project uses pnpm causes subtle failures (wrong node_modules resolution, missing workspace support). Lock file detection is the standard: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, `package-lock.json` → npm ([package-manager-detector](https://www.npmjs.com/package/package-manager-detector)).

**Beyond build/test/lint — the full validation surface:**
The AGENTS.md best practices recommend documenting file-scoped commands for maximum efficiency. The full set of discoverable commands includes:

| Category | Purpose | Used by | Examples |
|---|---|---|---|
| **build** | Compile/bundle | Phase 4 full check | `npm run build`, `cargo build` |
| **test** | Unit/integration tests | Phase 4, agents | `npm test`, `pytest`, `cargo test` |
| **lint** | Static analysis (check only) | Phase 4, review agents | `npm run lint`, `ruff check .` |
| **typecheck** | Type checking | Phase 4 full check | `tsc --noEmit`, `mypy .` |
| **format_check** | Format verification | Phase 4 | `prettier --check .`, `cargo fmt --check` |
| **format_fix** | Auto-format | Phase 4 autofix step | `prettier --write .`, `ruff format .` |
| **lint_fix** | Auto-fix lint issues | Phase 4 autofix step | `npm run lint:fix`, `ruff check --fix .` |
| **codegen** | Code generation | Phase 4 codegen check | `npm run codegen`, GraphQL/OpenAPI generators |
| **e2e** | End-to-end tests | Phase 4 (optional) | `npm run test:e2e`, `playwright test` |
| **start** | Dev server | Phase 4 startup check | `npm run dev`, `python manage.py runserver` |
| **preflight** | All-in-one validation | Phase 4 shortcut | `npm run ci`, `make check` |
| **migrate** | Database migrations | Implementation agents | `npm run db:migrate`, `prisma migrate` |

**User confirmation is essential:**
Auto-detected commands can be wrong (e.g., a `build` script that also deploys, or a `test` script that requires a running database). Presenting discovered commands and letting the user confirm/override is the pattern used by Nx (`nx init`) and recommended by the AGENTS.md standard.

### Recommended approach

**Three-source discovery (priority order):**
1. **Explicit scripts** — package.json `scripts`, Makefile targets, Taskfile recipes, justfile recipes
2. **Config inference** — tsconfig.json → typecheck, .prettierrc → format, .eslintrc → lint
3. **Language defaults** — fallback commands per detected language

**Present and confirm:**
After discovery, show all found commands grouped by category (Core Validation, Autofix, Additional). Let user accept all or customize individually. This catches misdetections and lets users add project-specific commands the scanner missed.

**Write to CLAUDE.md:**
All confirmed commands get written to CLAUDE.md's "Essential commands" section — this is the single source of truth that agents and skills read at runtime.

**Sources:** [AGENTS.md best practices](https://www.builder.io/blog/agents-md), [package-manager-detector](https://www.npmjs.com/package/package-manager-detector), [Nx workspace analysis](https://nx.dev/docs/guides/adopting-nx/nx-vs-turborepo), [Claude Code docs](https://code.claude.com/docs/en/common-workflows)

---

## Mid-Flow User Input Handling

### The problem: user messages during long pipelines

The `/implement` pipeline runs through 6 phases and can take 10-30 minutes. Users naturally want to drop context, corrections, or preferences mid-execution ("oh, and we need dark mode too" or "actually use POST not GET"). Without explicit handling, the agent either ignores these messages, treats them as blockers that restart the pipeline, or gets confused about what's a command vs. a note.

### What frameworks implement

| Framework | Mid-flow input handling | Backtracking | Note persistence |
|---|---|---|---|
| **Aider** | Control-C interrupts gracefully, partial work preserved in history | User redirects with new message, agent adapts | Conversation history |
| **Cursor** | Supports injecting context mid-flow ("the server is already running on port 4000") | Agent continues with updated info, no full restart | In-memory context |
| **LangGraph** | Checkpoint/restore after each node — resume from last completed step | Restore to any previous checkpoint, replay from there | Persistent state store |
| **GSD** | STATE.md checkpoint per phase — resumable | Re-read STATE.md, resume from recorded phase | `.planning/STATE.md` |
| **Metaswarm** | Per-WU isolation — only affected WU reruns | Fresh agent per WU, orchestrator decides retry scope | Campaign files |
| **Microsoft Agent Framework** | "Co-pilot mode" — user input during execution treated as dynamic context | Agent adapts without full restart | Agent memory |

### Research findings

**Two complementary patterns emerged:**

**Pattern 1: Note capture + checkpoint evaluation (recommended)**
User input is logged to a persistent file (`.planning/NOTES.md`) and evaluated at the next phase boundary. This avoids stopping work mid-phase while ensuring nothing is lost. LangGraph's checkpoint/restore pattern is the closest analog — state is captured after each step, and any correction triggers a replay from the last valid checkpoint, not from scratch.

**Pattern 2: Immediate halt + re-plan**
Used only for blockers that make current work invalid ("stop, requirements changed completely"). The agent saves current state, halts, and re-enters discovery. This is the minority case — most mid-flow input is additive, not destructive.

**Key insight — classify before reacting:**
The critical design decision is not *how* to handle the input but *what kind* it is. Research across frameworks shows four categories: notes (informational context), preferences (soft direction), corrections (changes past decisions), and blockers (invalidates everything). Each has a different optimal response. Without classification, agents either over-react (restart for a note) or under-react (ignore a correction).

**Minimize backtracking scope:**
Metaswarm's per-WU isolation is the gold standard: when a correction only affects one work unit, only that WU reruns — not the entire implementation phase. This is 5-10x more efficient than restarting Phase 3 from scratch. Similarly, if a correction only affects future phases (e.g., "use JWT" when auth hasn't been implemented yet), no backtracking is needed at all — just update the spec.

### Recommended approach

**Classify → Log → Evaluate at checkpoint → Backtrack minimally:**

1. **Classify** the input: note, preference, correction, or blocker
2. **Log** to `.planning/NOTES.md` (persistent, survives compaction)
3. **Acknowledge** briefly: "Noted — I'll apply this at [phase]"
4. **At next phase checkpoint**, read NOTES.md and assess impact:
   - No impact → continue
   - Affects future phases only → update SPEC.md, continue (no backtrack)
   - Invalidates current output → rerun minimal scope (affected WU or phase)
   - Blocker → halt, save state, re-enter discovery
5. **Clear processed notes** to NOTES_RESOLVED.md (audit trail)

**Anti-patterns to avoid:**
- Restarting the entire pipeline for a preference change
- Ignoring user messages until a WAIT gate
- Treating every correction as a blocker
- Backtracking without saving current progress first

**Sources:** LangGraph (checkpoint/restore), Aider (graceful interrupt + history preservation), Cursor (mid-flow context injection), Microsoft Agent Framework (co-pilot mode), Metaswarm (per-WU isolation for minimal reruns), [Anthropic context engineering guide](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

---

## Issue Tracker Integration (Linear)

### The problem: disconnected implementation context

AI coding agents typically receive instructions via chat and produce code — but in team workflows, the source of truth for *what to build* lives in an issue tracker (Linear, Jira, etc.). Without integration, the agent misses acceptance criteria, linked issues, priority context, and the team loses visibility into what the agent is working on.

### What frameworks and tools implement

| Tool/Framework | Issue tracker | Integration method | Status updates | PR linking |
|---|---|---|---|---|
| **Linear** (official) | Linear | MCP server (`https://mcp.linear.app/mcp`) | Full CRUD via MCP | Auto-link via issue ID in branch/PR |
| **Cursor** | Linear | MCP via `@tacticlaunch/mcp-linear` | Read + update | Branch context via `@Branch` tool |
| **Claude Code** | Linear | MCP (official HTTP transport) | Full CRUD | Issue ID in commit/PR title |
| **Composio** | Linear + others | Managed MCP layer (handles OAuth, token refresh) | Full CRUD | Via API |
| **CrewAI** | Linear | Native integration | Read + update | Via API |
| **Agent Factory** | N/A | Session-per-branch, no tracker | N/A | Auto-PR per session |

### Research findings

**Linear MCP is the standard integration path:**
- Linear provides an official MCP server: `claude mcp add --transport http linear https://mcp.linear.app/mcp` ([Linear MCP docs](https://linear.app/docs/mcp))
- Community alternatives exist ([emmett-deen/Linear-MCP-Server](https://github.com/emmett-deen/Linear-MCP-Server), [jerhadf/linear-mcp-server](https://github.com/jerhadf/linear-mcp-server)) but the official server is recommended
- Supports reading issues, updating status, adding comments, and managing projects

**Issue ID is the linking glue:**
- Including the Linear issue ID (e.g., `ENG-123`) in branch names, commit messages, or PR titles automatically creates bidirectional links ([Linear GitHub integration docs](https://linear.app/docs/github-integration))
- Branch naming convention: `feat/ENG-123-add-user-settings` (Linear's "Copy git branch name" feature generates this format)
- Commit convention: `feat(auth): add OAuth login [ENG-123]`
- PR title convention: `[ENG-123] Add user authentication`

**Status lifecycle maps to implementation phases:**
- **Todo** → agent picks up the task
- **In Progress** → Phase 1 (Discovery) starts, agent begins implementation
- **In Review** → Phase 6 (Ship) creates a PR
- **Done** → PR merged (usually handled by Linear's GitHub integration automatically)

**Non-blocking design is critical:**
- Issue tracker integration must be graceful-failure: if Linear MCP is unavailable, the implementation pipeline continues normally
- Status updates are side effects, not gates — a failed status update should never block code implementation
- Linear detection is automatic (no flag needed) — the skill works identically without a Linear reference

### Recommended implementation

**Phase 1 (Discovery):**
1. Auto-detect Linear reference in arguments (URL like `https://linear.app/.../ENG-123`, or issue ID like `ENG-123`): fetch issue via MCP, extract title/description/acceptance criteria/comments
2. Use issue context as primary input for discovery (supplements or replaces `$ARGUMENTS`)
3. Update issue status to "In Progress"
4. Derive branch name from issue ID: `feat/ENG-123-description`

**Phase 6 (Ship):**
1. Include issue ID in commit message and PR title
2. After PR creation: update issue status to "In Review", add comment with PR link
3. After commit only: add comment summarizing implementation
4. After leave uncommitted: keep as "In Progress"

**Setup (optional, via setup.sh):**
- Ask user during setup whether to enable Linear integration
- If yes: add instructions to CLAUDE.md, remind to run `claude mcp add`
- If no: skip entirely, no traces in the harness

**Sources:** [Linear MCP docs](https://linear.app/docs/mcp), [Linear GitHub integration](https://linear.app/docs/github-integration), [Hypeflo agentic workflow guide](https://www.hypeflo.ws/workflow/agentic-claude-code-workflow-with-linear-integration), [Composio Linear MCP setup](https://composio.dev/content/how-to-set-up-linear-mcp-in-claude-code-to-automate-issue-tracking)

---

## Testing Patterns

How frameworks enforce testing quality through agents, skills, and hooks. Testing is the most universally agreed-upon quality gate — every framework has testing enforcement, but approaches vary significantly.

### What frameworks implement

| Framework | Test enforcement | Test selection | Quality checks | TDD | Coverage requirement | Verification phases |
|---|---|---|---|---|---|---|
| **Metaswarm** | VALIDATE phase (independent, never trusts agent) | Full suite per work unit | "Never lobotomize a test", no `expect.any()` as fix | Mandatory per work unit | 100% enforcement | tsc + eslint + tests + coverage |
| **GSD** | Cross-phase regression gate | Affected tests per phase | Verifier checks goal achievement | Optional | Per-project thresholds | Build + lint + unit + integration |
| **gstack** | Diff-based selection + two-tier classification | `touchfiles.ts` manifest | LLM-as-judge evals for quality | Optional | Gate tier: must-pass. Periodic: benchmark | Gate tests + periodic evals |
| **claude-pipeline** | Test stage with up to 10 iterations | Per-task tests | Anti-rationalization tables for TDD | "Iron law" TDD | Threshold-based blocking gate | Build + test + type-check |
| **ECC** | 6-phase verification loop | Per-skill TDD workflow | AgentShield red-team/blue-team | Mandatory "Tests BEFORE Code" | Enforced per workflow | Build + Types + Lint + Tests + Security + Diff |
| **Superpowers** | Tests must pass before review | Affected tests | Test quality in code review | Separate TDD skill | Project-defined | Build + test + review |
| **Ruflo** | London School TDD specialist agent | Mock-driven outside-in | Behavior verification over state testing | Mandatory (London School) | Per-agent thresholds | Red → Green → Refactor |
| **Claude Forge** | Post-implementation validation | Changed-file tests | Review agent checks test quality | Optional | None | Build + lint + test |
| **Orchestrator Kit** | Quality gate between stages | Per-stage | Binary go/no-go | Optional | None | Build + test gate |

### Testing architecture patterns

#### Pattern 1: Independent Validation (from Metaswarm — most important)

The **orchestrator** runs validation commands itself. Never trust the implementer agent's claim that "tests pass."

```markdown
## Validate Phase (MANDATORY — orchestrator runs this, not the implementer)
Run `<your-test-command>`. Capture output to a file.
If it fails, route EXACT error output back to the implementer agent.
Do NOT proceed to review until tests pass. Max 3 fix attempts, then escalate.
```

**Why:** The agent may have run a subset, run them in a different way, used `--passWithNoTests`, or hallucinated the output. The orchestrator must independently verify.

**Source:** Metaswarm (VALIDATE phase independently runs tsc + eslint + vitest + coverage, never trusts subagent self-reports), GSD (cross-phase regression gate)

#### Pattern 2: Diff-Based Test Selection (from gstack — most efficient)

Instead of running the full test suite, select tests based on what changed:

```typescript
// touchfiles.ts — each test declares its file dependencies
export const testDependencies = {
  "auth.spec.ts": ["src/v1/auth/**", "src/utils/jwt.ts"],
  "graph.spec.ts": ["src/v1/graphs/**", "src/v1/graph-templates/**"],
  "ALL": ["vitest.config.ts", "tsconfig.json"]  // Global deps trigger all tests
};
```

Only tests whose `touchfiles` dependencies changed in the current diff run. Global touchfiles (like the test runner config itself) trigger all tests.

**Why:** Full test suite runs are expensive ($1-5 per run in LLM context). Diff-based selection reduces cost by 70-90% while maintaining safety through dependency tracking.

**Source:** gstack (`touchfiles.ts` manifest, `test:affected` script)

#### Pattern 3: Two-Tier Test Classification (from gstack)

Classify tests by their purpose and reliability:

| Tier | Name | Properties | When to run | Examples |
|---|---|---|---|---|
| **Gate** | Must-pass | Deterministic, fast, blocks merge | Every pipeline run, CI | Unit tests, integration tests, type checks |
| **Periodic** | Quality benchmark | May be non-deterministic, slow, measures quality trends | Weekly cron, pre-release | LLM-as-judge evals, performance benchmarks, E2E |

Gate tests block the pipeline. Periodic tests inform decisions but don't block.

**Why:** Mixing deterministic and non-deterministic tests in the same gate causes flaky pipelines. Separation ensures the gate is always trustworthy while quality benchmarks still run regularly.

**Source:** gstack (gate vs. periodic classification), academic CI/CD research

#### Pattern 4: 6-Phase Verification Loop (from ECC — most thorough)

After implementation, run 6 verification phases in sequence. Each must pass before the next:

| Phase | What | Fails on |
|---|---|---|
| 1. Build | Compile the project | Compilation errors |
| 2. Type Check | Run type checker (tsc --noEmit) | Type errors |
| 3. Lint | Run linter | Lint violations |
| 4. Test Suite | Run affected tests | Test failures |
| 5. Security Scan | Run security audit | Known vulnerabilities |
| 6. Diff Review | Review the diff for anti-patterns | Suspicious patterns |

**Why:** Ordering matters. Build errors are cheaper to fix than test failures. Type errors caught at phase 2 prevent wasted time running tests that would fail anyway.

**Source:** ECC (`tdd-workflow` skill), Metaswarm (similar: tsc + eslint + vitest + coverage)

#### Pattern 5: LLM-as-Judge Evals (from gstack — most novel)

Use an LLM to evaluate output quality, separate from functional tests:

```bash
# Tier 3 eval: LLM judges skill output quality (~$0.15/run)
pnpm test:eval --skill implement --scenario "add-crud-endpoint"
# LLM evaluates: Did the output follow conventions? Is the code idiomatic?
# Score: 0-100 with rubric-based justification
```

This evaluates skill pipeline quality rather than code correctness — "did the harness produce good results?" not "does the code work?"

**Best for:** Evaluating and improving your harness skills themselves, not application code.

**Source:** gstack (Tier 3 evals with LLM judge)

### Test quality enforcement in review criteria

Include a **test quality litmus test** in `tests-criteria.md` — for each test, ask: "If I deleted the core logic, would the test still pass?"

#### Anti-patterns to flag

| Anti-pattern | Example | Why it's dangerous | Source |
|---|---|---|---|
| **Illusory tests** | `expect(result).toBeDefined()` | Passes for any non-undefined value, doesn't verify behavior | All frameworks |
| **Weak assertions** | `toBeTruthy()`, `toHaveLength(N)` | Doesn't check actual contents | Metaswarm |
| **Over-mocking** | Mocking the unit under test | Tests the mock, not the code | All frameworks |
| **Lobotomized tests** | Using `expect.any()` to make a failing test pass | Masks the real failure | Metaswarm ("never lobotomize a test") |
| **Missing integration tests** | New DAO/service logic without integration coverage | Unit tests with mocks miss real DB behavior | GSD, Metaswarm |
| **Conditional skips** | `it.skip()` or early returns for missing env vars | Silently passes with no coverage | Project-specific (must-fail policy) |
| **State testing over behavior** | Testing internal state instead of observable behavior | Brittle tests that break on refactoring | Ruflo (London School TDD) |
| **Tests written after code** | "I'll add tests later" | Tests pass immediately — proves nothing | claude-pipeline, ECC |

### TDD enforcement patterns

Two distinct schools across frameworks:

#### Chicago School (from Metaswarm, claude-pipeline, ECC)

Inside-out, state-based. Write tests for the smallest units first, build up:

```markdown
## TDD Rule (MANDATORY)
No production code without a failing test first. Red-Green-Refactor.
1. Write test → run → MUST FAIL (red)
2. Write minimal code to pass → run → MUST PASS (green)
3. Refactor → run → MUST STILL PASS
Coverage must meet project thresholds before proceeding to review.
```

claude-pipeline calls this the "iron law" and adds anti-rationalization tables to prevent skipping. ECC requires "Tests BEFORE Code" as step 1, with a "run tests, they should fail" gate.

#### London School (from Ruflo)

Outside-in, mock-driven. Start from the outermost layer, mock collaborators, work inward:

```markdown
## London School TDD
1. Write acceptance test for the feature (fails)
2. Write unit test for the outermost component with mocked collaborators
3. Implement until the unit test passes
4. Replace mocks with real collaborators one layer at a time
5. When acceptance test passes, stop
```

**When to use:** API endpoints, controller → service → DAO flows. The outside-in approach naturally discovers the interfaces between layers.

**Source:** Ruflo (dedicated London School TDD swarm agent)

### Test selection by change type

| Change type | Which tests to run | Source |
|---|---|---|
| **Entity/migration change** | Integration tests for the entity's DAO + unit tests for the service | GSD, Metaswarm |
| **Service logic change** | Unit tests for the service + integration tests if DAO is involved | All frameworks |
| **Controller change** | Unit tests for controller + E2E tests for the endpoint | All frameworks |
| **DTO change** | Unit tests + regenerate API client + run frontend tests | Project-specific (codegen dependency) |
| **Frontend component change** | Component unit tests + visual regression (if available) | gstack, Claude Forge |
| **Configuration change** | ALL tests (global touchfile) | gstack (touchfiles.ts) |
| **Test infrastructure change** | ALL tests | gstack (touchfiles.ts) |

---

## Session Persistence & Recovery

How to survive context compression, session breaks, and long-running pipelines. This is a critical challenge — a `/implement` pipeline can consume 50-80% of context before reaching the Ship phase.

### What frameworks implement

| Framework | Persistence mechanism | Compaction handling | Session cycling | Resume strategy | Context monitoring |
|---|---|---|---|---|---|
| **GSD** | `.planning/STATE.md` (schema-backed), continue-here files, HANDOFF.json | Context monitor warns at 35%/25% | continue-here.md files for next session | Read STATE.md, resume from recorded phase | `gsd-context-monitor.js` with severity escalation |
| **Citadel** | Campaign files + pre-compact hooks | PreCompact hook saves state automatically | — | SessionStart hook restores from campaign | Cost tracking via JSONL parsing |
| **Metaswarm** | BEADS + active-plan.md | Amnesiac agents rebuild from files | `/self-reflect` captures learnings | Agent re-reads plan files each invocation | — |
| **Beads** | Molecule persistence + mail system | — | Mail/handoff between sessions | SessionStart hook reads incoming mail | — |
| **ECC** | YAML instincts + JSONL observations | `strategic-compact` skill (proactive) | — | Hook-based observation survives compaction | Strategic compaction timing guidance |
| **Claude Forge** | Per-agent memory in `~/.claude/agent-memory/` | `session-wrap` on Stop hook | Context sync after 4h+ gaps | Suggest `/sync` after long gaps | Work tracker hooks |
| **Claude-Code-Skills** | CLI checkpoint files | — | — | Checkpoint file read on startup | — |
| **claude-pipeline** | `status.json` per pipeline stage | — | — | Status file read on re-entry | — |
| **Continuous-Claude** | PostgreSQL + pgvector + `.tldr/` cache | Daemon compresses during idle | Daemon bridges sessions | pgvector similarity search for context | Daemon-managed |

### Persistence architecture patterns

#### Pattern 1: Schema-Backed State Files (from GSD — most robust)

A structured state file with defined schema, atomic read-patch-write operations:

```markdown
<!-- .planning/STATE.md -->
## State
- Phase: execute
- Status: in_progress
- Last activity: 2026-04-01T14:30:00Z
- Progress: 3/5 tasks complete
- Resume file: .planning/.continue-here-abc123.md
- Stopped at: Task 4 — implementing thread.service.ts

## Accumulated Context
- Decision: use FilterQuery<T> for all DAOs (Phase 1)
- Blocker: Redis connection timeout resolved (Phase 3)

## Session Continuity
- Context remaining: 45%
- Compactions: 1 (at Phase 3 start)
```

GSD's `state.cjs` provides `readState()` and `patchState()` functions that handle concurrent access and partial updates.

**Why:** JSON is fragile (one bad write corrupts everything). Markdown with sections is human-readable, git-diffable, and partially recoverable.

**Sources:** GSD (STATE.md with schema), claude-pipeline (status.json — JSON variant)

#### Pattern 2: Pre-Compact State Capture (from Citadel — most automatic)

A PreCompact hook automatically saves state before context compression:

```javascript
// hooks/pre-compact.js — fires before auto-compaction
const state = {
  currentPhase: process.env.CURRENT_PHASE,
  completedPhases: JSON.parse(process.env.COMPLETED_PHASES || '[]'),
  filesChanged: getChangedFiles(),
  pendingWork: process.env.PENDING_WORK,
  timestamp: new Date().toISOString()
};
fs.writeFileSync('.claude/.state/pre-compact-snapshot.json', JSON.stringify(state));
```

**Why:** Auto-compaction is unpredictable. A PreCompact hook guarantees state is captured even when the pipeline doesn't checkpoint at a natural boundary.

**PostCompact hook** (undocumented but works): receives `trigger` and `compact_summary` fields. Can notify the agent that context was compressed and suggest re-reading critical files.

**Sources:** Citadel (campaign files + pre-compact hooks), GSD (PostCompact context monitor)

#### Pattern 3: Strategic Compaction Timing (from ECC — most proactive)

Instead of relying on auto-compaction, proactively compact at logical boundaries:

| Situation | Action | Why |
|---|---|---|
| After research phase, before planning | Compact | Research context is captured in spec — no longer needed |
| After debugging session resolves | Compact | Debug traces are noise for next task |
| After review + fix cycle completes | Compact | Review findings are applied — diff tells the story |
| **Never** mid-implementation | Do NOT compact | Losing implementation context causes regressions |
| **Never** mid-debugging | Do NOT compact | Losing hypothesis chain restarts investigation |

ECC's `strategic-compact` skill tracks tool call count via a hook and suggests `/compact` at these boundaries.

**"What survives compaction" reference:**

| Survives | Does NOT survive |
|---|---|
| CLAUDE.md files (re-injected) | Skill instructions (SKILL.md content) |
| Rules (path-scoped, re-injected) | Tool schemas loaded via ToolSearch |
| Agent frontmatter (re-loaded) | Conversation nuance and reasoning |
| Files on disk (state files, checkpoints) | MCP OAuth tokens (silent failure) |
| Native memory (MEMORY.md + topic files) | In-progress work context |

**Sources:** ECC (`strategic-compact` skill), community research on compaction behavior

#### Pattern 4: Session Cycling via Mail/Handoff (from Beads, GSD)

When context is exhausted, gracefully cycle to a new session:

**Beads pattern:**
```
1. Outgoing agent writes mail file: context summary + pending work + key decisions
2. Outgoing agent triggers session respawn (new claude instance)
3. New session: SessionStart hook reads mail, primes context
4. "Molecules" (persistent work items) carry over; ephemeral state resets
```

**GSD pattern:**
```
1. Write HANDOFF.json (machine-readable) + continue-here.md (human-readable)
2. User starts new session
3. New session reads continue-here.md for context, HANDOFF.json for state
```

**Key difference:** Beads automates the cycling. GSD makes it user-initiated.

**Sources:** Beads (mail system), GSD (HANDOFF.json + continue-here.md)

#### Pattern 5: Context Monitoring with Severity Escalation (from GSD)

Track context consumption and warn before it becomes critical:

| Threshold | Severity | Action | Debounce |
|---|---|---|---|
| ≤35% remaining | WARNING | Suggest checkpointing and compaction | 5 tool calls between warnings |
| ≤25% remaining | CRITICAL | Urgently recommend session cycling | Bypasses debounce |
| ≤15% remaining | EMERGENCY | Auto-write handoff file | Immediate |

GSD implements this with two hooks: a StatusLine hook writes metrics to a bridge file (`/tmp/claude-ctx-{session_id}.json`), and a PostToolUse hook reads the bridge file and injects `additionalContext` warnings.

**Sources:** GSD (`gsd-context-monitor.js`), Citadel (cost tracking at token-count level)

#### Pattern 6: Context Sync After Gaps (from Claude Forge)

A SessionStart hook checks time since last session end. If >4 hours, suggests running a sync command:

```bash
# hooks/context-sync-suggest.sh
LAST_SESSION=$(stat -f '%m' ~/.claude/projects/*/latest.jsonl 2>/dev/null)
NOW=$(date +%s)
GAP=$(( NOW - LAST_SESSION ))
if [ $GAP -gt 14400 ]; then  # 4 hours
  echo "It's been ${GAP}s since your last session. Run /sync to catch up on changes."
fi
```

**Why:** Overnight changes (teammate commits, CI results, dependency updates) can invalidate assumptions. A sync command reads git log, checks CI status, and updates context.

**Sources:** Claude Forge (context-sync-suggest.sh)

### Recommended persistence strategy

| Pipeline length | Strategy |
|---|---|
| **Short** (< 30 min, < 40% context) | No persistence needed. Conversation memory sufficient |
| **Medium** (30-60 min, 40-70% context) | State file checkpoints at phase boundaries. Strategic compaction between phases |
| **Long** (60+ min, > 70% context) | Full persistence: state files + pre-compact hooks + context monitoring + session cycling capability |

### Anti-patterns in persistence

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| **Relying on conversation memory** | Lost on compaction. Degrades over long conversations | File-based state |
| **JSON-only state files** | One bad write corrupts everything. Not human-readable | Markdown with sections (GSD) or JSON + backup (Citadel) |
| **No compaction strategy** | Auto-compaction fires mid-implementation, losing critical context | Strategic compaction at logical boundaries (ECC) |
| **Agent accumulating context across tasks** | Context window fills with irrelevant prior-task garbage | Fresh agent per task with checkpoint state in prompt (GSD, Metaswarm) |
| **Skipping checkpoint after successful phase** | Next phase failure requires re-running the entire pipeline | Checkpoint after EVERY phase, not just failures |

---

## Self-Improving Knowledge

How agents and skills learn from completed work, accumulate institutional knowledge, and prime future sessions.

### What frameworks implement

A survey of 12 frameworks reveals a spectrum from no learning (Superpowers — deliberately static) to fully automatic confidence-scored instinct evolution (ECC v2). The table below compares approaches.

| Framework | Trigger | What gets learned | Storage | Validation | Pruning | Automatic? |
|---|---|---|---|---|---|---|
| **Metaswarm** | Post-PR merge (`/self-reflect`) | Review patterns, build failures, architectural decisions, user overrides | JSONL fact store (file-tagged, keyword-tagged) | Coverage thresholds as blocking gates | None documented | Auto |
| **ECC v2** | PreToolUse/PostToolUse hooks (100% reliable) | Atomic "instincts" — single trigger + action behaviors | YAML instincts + JSONL observations in `~/.claude/homunculus/` | Confidence scoring (0.3-0.9) | Confidence decay over time | Fully auto |
| **Claudeception** | Hook reminder + explicit `/claudeception` + "what did we learn?" | Debugging techniques, project conventions, error-cause mappings | Structured YAML+Markdown SKILL.md files | 8 quality gates, ripgrep dedup check | Lifecycle stages: Creation → Refinement → Deprecation → Archival | Hybrid |
| **SuperClaude** | PM-Agent auto-trigger after specialist tasks | Root cause analysis, prevention strategies, checklists | `self-improvement-workflow.md`, CLAUDE.md, `.learnings/` | Systematic root cause investigation | Monthly maintenance cycle | Auto |
| **Claude Forge** | `observe.sh` hook + session-wrap | Agent-specific learnings, session outcomes | `~/.claude/agent-memory/` (per-agent dirs) | Evidence-based completion | None | Hybrid |
| **Continuous-Claude** | Daemon during idle time | Architectural decisions, codebase patterns, file-level analysis | PostgreSQL + pgvector + YAML handoffs + `.tldr/` cache | Pyright/ruff post-edit hooks | Daemon-managed, regenerates on change | Fully auto |
| **Claude Code native** | Claude's judgment during conversation | Build commands, debugging solutions, module relationships, workflow habits | `~/.claude/projects/<proj>/memory/` topic files | None (Claude's judgment) | Auto-Dream (future): merges, deduplicates, removes stale facts | Auto |
| **claude-meta** | Manual reflection prompt | Generalized rules from specific mistakes (Reflect → Abstract → Generalize) | CLAUDE.md META section | Meta-rules self-regulate quality | Anti-bloat meta-rules | Manual |
| **Session-Wrap** | `/wrap` command at session end | Doc gaps, automatable patterns, mistakes/insights, follow-up tasks | CLAUDE.md, context.md | Duplicate checker agent (Haiku) | Dedup only | Manual |
| **claude-reflect** | Linguistic signal detection from user feedback | Corrections (HIGH confidence), approvals (MEDIUM), observations (LOW) | YAML skill files with git versioning + 30-day backups | YAML validation, auto-rollback | 30-day backup cleanup | Hybrid |
| **GSD** | Phase transitions | Decisions, blockers, context (NOT behavioral patterns) | `.gsd/STATE.md`, threads, seeds, per-phase docs | Quality gates per phase | Fresh context per wave (anti-bloat) | Semi-auto |
| **Superpowers** | None (deliberately static) | Nothing — enforces fixed methodological rigor | Fixed SKILL.md files | TDD, code review, human checkpoints | N/A | Manual |

### Knowledge architecture patterns

#### Pattern 1: Confidence-Scored Instincts (from ECC v2 — most sophisticated)

Atomic learned behaviors with measurable trust levels that decay over time.

```yaml
# ~/.claude/homunculus/instincts/personal/prefer-named-exports.yaml
id: inst_abc123
trigger: "Writing TypeScript exports"
action: "Use named exports instead of default exports"
confidence: 0.7       # Strong — auto-approved
domain: code-style
source: user_correction
evidence:
  - session: "2026-03-15"
    observation: "User corrected default export to named export"
  - session: "2026-03-18"
    observation: "Same correction in different file"
```

**Confidence levels:** 0.3 (tentative, suggested) → 0.5 (moderate, contextual) → 0.7 (strong, auto-applied) → 0.9 (near-certain, core behavior)

**Confidence changes:**
- Increases: repeated observation, user non-correction, multi-source agreement
- Decreases: explicit user corrections, extended non-observation, contradicting evidence

**Evolution:** Related instincts cluster into Commands → Skills → Agents via `/evolve` command.

**Cross-project promotion:** Instincts proven in 2+ projects with ≥0.8 avg confidence promote to global scope. Contamination protection prevents framework-specific patterns bleeding across projects.

**Sources:** ECC v2, Claude Forge (similar per-agent memory)

#### Pattern 2: Selective Knowledge Priming (from Metaswarm — most practical)

File-scoped, keyword-filtered knowledge injection. Only load the 5 relevant facts, not the entire knowledge base.

```bash
# Metaswarm's priming command
bd prime --files "src/api/auth/**" --keywords "authentication" --work-type implementation
# Returns: exactly the gotchas relevant to auth implementation files
```

**Storage format:** JSONL fact store, each entry tagged by affected files, keywords, and work type:

```jsonl
{"type": "gotcha", "content": "flush() must be called after persist()", "files": ["src/v1/*/dao.ts"], "keywords": ["orm", "persist"], "confidence": "high", "source": "PR #42 review"}
{"type": "pattern", "content": "Always use FilterQuery<T> in DAOs", "files": ["src/v1/*/dao.ts"], "keywords": ["dao", "query"], "confidence": "high", "source": "architecture review"}
```

**Why selective:** Full knowledge injection fails at scale — hundreds of facts consume the context window. Selective retrieval scales to thousands of entries without context pressure.

**Categories:** patterns, gotchas, decisions, api-behaviors, codebase-facts, anti-patterns

**Sources:** Metaswarm (JSONL + `bd prime`), academic ERL research (selective heuristic retrieval outperforms full-set injection)

#### Pattern 3: Meta-Rules (from claude-meta — most elegant)

Teach the system how to write rules, creating self-regulating quality that compounds rather than degrades.

```markdown
## META — How to Write Rules

When adding a new rule to this file:
- The rule must be reusable across multiple situations
- No "Warning Signs" sections for obvious guidelines
- No examples for trivial mistakes
- Write bullets, not paragraphs
- If the rule duplicates an existing one, merge instead of adding
```

Claude internalizes these constraints and applies them when generating new rules, preventing bloat organically.

**Sources:** claude-meta, MindStudio Learnings Loop (similar meta-learning concept)

#### Pattern 4: Hook-Based Observation (from ECC v2 — most reliable)

Deterministic 100% capture via PreToolUse/PostToolUse hooks, vs. probabilistic ~50-80% with skill-based observation.

ECC v1 used a Stop hook (session end) — triggered ~50-80% of the time. V2 switched to PreToolUse/PostToolUse hooks — 100% reliable, deterministic. A background Haiku agent processes accumulated observations asynchronously every ~5 minutes.

**Key architectural insight:** This is the single most important design decision for learning systems. If observation is probabilistic, the learning system misses half the signal.

**Sources:** ECC v1 → v2 migration, Claudeception (hook-based reminder achieves higher activation than pure semantic matching)

#### Pattern 5: Multi-Agent Extraction (from Session-Wrap)

Parallel specialized agents extract different types of knowledge from a session:

| Agent | Extracts |
|---|---|
| **doc-updater** | Documentation gaps and stale docs |
| **automation-scout** | Patterns suitable for conversion to skills/commands/agents |
| **learning-extractor** | Mistakes, insights, discoveries (TIL format) |
| **followup-suggester** | Prioritized task list for next session |

A dedup checker (Haiku) cross-references proposals against existing content before writing.

**Sources:** Session-Wrap, SuperClaude PM-Agent (similar meta-agent concept)

#### Pattern 6: Background Consolidation (from Auto-Dream, Continuous-Claude)

Process knowledge during idle time, analogous to sleep-based memory consolidation.

**Claude Code Auto-Dream** (March 2026, not yet GA): Runs between sessions. Four phases: merge new signal → convert relative dates to absolute → delete contradicted facts → keep MEMORY.md under 200 lines.

**Continuous-Claude daemon:** Headless subprocess wakes during session gaps, processes thinking blocks into archival memory. TLDR compression reduces ~23,000 tokens to ~1,200 tokens (95% reduction) per code file using FAISS-indexed embeddings.

**Sources:** Claude Code Auto-Dream, Continuous-Claude v3 (PostgreSQL + pgvector + FAISS)

#### Pattern 7: Quality-Gated Extraction (from Claudeception — most rigorous)

8 quality gates before a learning is persisted:

1. Is it reusable across situations?
2. Is it non-trivial (not obvious from reading code)?
3. Is it specific (exact trigger conditions identifiable)?
4. Is it verified (actually tested, not hypothetical)?
5. Does it contain sensitive data? (reject if yes)
6. Does an existing skill already cover this? (ripgrep check → update vs. create)
7. Is it backed by current best practices? (optional web search)
8. Does it meet formatting standards? (YAML frontmatter + structured sections)

**Why gates matter:** Without quality filtering, knowledge bases degrade into noise. Claudeception draws from academic work: Voyager (2023, reusable skill libraries), CASCADE (2024, meta-skills), SEAgent (2025, learning from trial and error).

**Sources:** Claudeception

### Claude Code native memory integration

The built-in memory system (`~/.claude/projects/<proj>/memory/`) and subagent persistent memory (`memory: user|project|local` frontmatter) are the foundation all frameworks build on.

**Key built-in capabilities:**
- **Auto-memory:** Claude decides what to save based on future-session utility. Topic files + MEMORY.md index (200-line cap)
- **Subagent memory:** `memory: project` in agent frontmatter → `.claude/agent-memory/<name>/`. Shared via VCS
- **Auto-Dream (future):** Background consolidation during idle time

**How harness learning systems should integrate:**
- Use native memory for user preferences, feedback, and project context (it's already good at this)
- Use custom knowledge stores (JSONL, YAML instincts) for structured technical learnings that need selective retrieval
- Don't duplicate what native memory already captures — focus custom systems on knowledge types native memory doesn't handle well (file-scoped gotchas, confidence-scored patterns, cross-project promotion)

### Anti-patterns in self-improving systems

| Anti-pattern | Why it fails | Mitigation | Source |
|---|---|---|---|
| **Rule bloat** | CLAUDE.md grows past ~200 lines, model ignores half the rules | Meta-rules (claude-meta), monthly pruning (SuperClaude), 200-line cap (Auto-Dream) | claude-meta, SuperClaude |
| **Knowledge drift** | Rules become stale as codebase evolves, no framework has a robust automated solution | Monthly maintenance (SuperClaude), Auto-Dream (future), confidence decay (ECC v2) | All frameworks |
| **Hallucinated rules** | Agents produce plausible but semantically wrong rules | 8-gate quality filter (Claudeception), evidence requirements, automated validation (tests/types) | Claudeception |
| **Knowledge conflicts** | Contradictory rules cause arbitrary behavior. Parent/child CLAUDE.md files conflict | Periodic audit, `claudeMdExcludes` setting, separation between advisory and deterministic enforcement | Community research |
| **Probabilistic observation** | Skill-based learning triggers ~50-80% of the time, missing signal | Hook-based observation for 100% deterministic capture | ECC v1 → v2 migration |
| **Full-set injection** | Loading entire knowledge base into context consumes window, degrades performance | Selective retrieval (Metaswarm `bd prime`), TLDR compression (Continuous-Claude), 200-line caps | Metaswarm, academic ERL research |
| **Cross-project contamination** | Framework-specific patterns bleed into unrelated projects | Project-scoped vs. global instincts, contamination protection on promotion | ECC v2 |
| **Curriculum collapse** | Self-improving system generates only comfortable-zone improvements | No framework explicitly addresses this — open research problem | Academic research |

### Recommended approach

Start simple, add sophistication as needed:

1. **Baseline:** Use Claude Code native auto-memory. It handles user preferences and project context well out of the box
2. **Level 1:** Add a `/self-reflect` skill (manual, post-PR). Extract learnings into JSONL, categorized by type and tagged by files/keywords. This is Metaswarm's pattern — practical and proven
3. **Level 2:** Add hook-based observation (ECC v2 pattern). PreToolUse/PostToolUse hooks capture corrections deterministically. Background Haiku agent processes observations asynchronously
4. **Level 3:** Add confidence scoring and cross-project promotion. Instincts with measurable trust levels that decay over time and promote to global scope when proven
5. **Level 4:** Add background consolidation (Auto-Dream pattern when GA, or custom daemon). Process knowledge during idle time

Most projects will be well-served by Levels 1-2. Levels 3-4 are for teams with many developers and long-running projects where institutional knowledge loss is a real problem.

---

## Anti-Rationalization

Claude tends to shortcut pipeline phases when changes seem "simple." This is the most underappreciated failure mode in harness design — a pipeline with perfect architecture will still fail if the LLM rationalizes skipping steps. Frameworks address this through prompt-level rebuttals, hook-level enforcement, and architectural separation.

### What frameworks implement

| Framework | Approach | Mechanism | Strength |
|---|---|---|---|
| **claude-pipeline** | Extensive anti-rationalization tables per skill | Prompt-level: table of rationalization → rebuttal pairs embedded in each SKILL.md | Most comprehensive prompt-level approach. Treats skill creation as TDD with "pressure scenarios" as tests |
| **Metaswarm** | Never skip gates + adversarial review | Architectural: separate writer/reviewer agents. CLAUDE.md workflow intercepts enforce gates | Structural separation makes skipping architecturally impossible |
| **GSD** | Workflow guard hook + prompt guard hook | Hook-level: `gsd-workflow-guard.js` detects bypass, `gsd-prompt-guard.js` blocks injection | 100% deterministic enforcement via hooks |
| **gstack** | "Boil the Lake" philosophy | Cultural: explicit anti-shortcut ethos document that rejects 90% solutions | Addresses the mindset, not just individual rationalizations |
| **Claude Forge** | DB guard + security hooks | Hook-level: `db-guard.sh` blocks destructive SQL via exit code 2 | Hard blocks on the most dangerous rationalizations |
| **OMC** | Separate authoring and review passes | Architectural: "Never self-approve in the same active context" | Forces separate-agent validation |
| **ECC** | AgentShield red-team/blue-team | Architectural: adversarial agents challenge each other | Structural disagreement prevents consensus shortcuts |
| **Superpowers** | "Performative agreement" anti-pattern warning | Prompt-level: explicit warning against "You're absolutely right!" followed by blind implementation | Targets a specific and common failure mode |

### Enforcement mechanisms (ranked by reliability)

| Mechanism | Reliability | Cost | Best for |
|---|---|---|---|
| **Hook enforcement** (exit code 2 blocks) | 100% — deterministic, cannot be bypassed | Medium (hook development) | Destructive operations, security boundaries |
| **Architectural separation** (writer ≠ reviewer) | 95% — fresh context prevents self-approval bias | High (multiple agents) | Quality gates, code review, spec validation |
| **CLAUDE.md workflow intercepts** | 85% — subject to instruction-following degradation | Low (one-time rules) | Mandatory gates across all workflows |
| **Prompt-level anti-rationalization tables** | 70-80% — degrades with context length | Low (embedded in skills) | Phase skipping, TDD shortcuts, scope creep |
| **Cultural ethos documents** | 60% — sets tone but not enforced | Very low | Team alignment, philosophy |

### Prompt-level anti-rationalization tables

#### For every pipeline skill

```markdown
## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "The change is too small for full review" | Small changes cause production incidents too. Follow the process. |
| "I already know how to do this" | Skills encode process knowledge beyond individual capability. Follow them. |
| "It would be faster to just implement it" | Speed without process leads to rework. Run the pipeline. |
| "The tests are obviously fine" | Run them. "Obviously fine" is the #1 predictor of broken tests. |
| "This doesn't need architecture review" | The architect catches issues you can't see from inside the implementation. |
| "I can do this in one step" | Multi-step exists for a reason. Each step catches different failures. |
| "The user seems impatient" | Cutting corners costs more time than following the process. |
| "This is just a refactor" | Refactors break things. Tests and review apply equally. |
```

#### For TDD skills (from claude-pipeline)

| Rationalization | Rebuttal |
|---|---|
| "I'll write tests after" | Tests passing immediately prove nothing. Write the failing test first. |
| "This is too simple to test" | Simple code that breaks costs the same as complex code that breaks. |
| "The existing tests cover this" | If they do, they should fail when you change the code. Verify. |
| "Mocking is sufficient here" | Mocks test the mock, not the code. Add integration tests for real behavior. |
| "This is just a type change" | Type changes propagate. Run the type checker AND the tests. |

**Source:** claude-pipeline (extensive anti-rationalization tables per skill)

#### For scope management (from gstack)

| Shortcut | Why it's wrong |
|---|---|
| "Choose the 90% solution — less code" | Choose the complete version. Incomplete solutions create tech debt. |
| "Let's defer tests to a follow-up PR" | Tests are cheap now. A follow-up PR for tests never happens. |
| "We can optimize later" | If the optimization is in the spec, implement it now. |
| "This edge case is unlikely" | Edge cases cause production incidents. Handle them or document the risk. |

**Source:** gstack ("Boil the Lake" ethos)

### Hook-level anti-rationalization

When a prompt-level rebuttal isn't reliable enough, enforce with hooks:

#### Workflow Guard (from GSD)

Detects when Claude makes direct edits outside a tracked command context:

```javascript
// gsd-workflow-guard.js — PostToolUse hook for Edit/Write
// Soft guard: advise, don't block (avoids deadlocks)
if (toolName === 'Edit' || toolName === 'Write') {
  if (!isWithinTrackedCommand()) {
    return {
      decision: "allow",  // Soft — not exit 2
      additionalContext: "⚠️ This edit is outside a tracked command. " +
        "Changes will not be recorded in STATE.md. " +
        "Consider using /implement or /follow-up instead."
    };
  }
}
```

**Key design choice:** This is a **soft guard** (advise, not block). Blocking edits would deadlock the agent. Advising creates awareness without preventing legitimate ad-hoc work.

**Source:** GSD (`gsd-workflow-guard.js`)

#### Prompt Injection Guard (from GSD)

Scans content being written to planning files for injection patterns:

```javascript
// gsd-prompt-guard.js — PreToolUse hook for Write/Edit on .planning/ files
const INJECTION_PATTERNS = [
  /ignore previous instructions/i,
  /you are now/i,
  /<system>/i,
  /\u200B/,  // Zero-width space (invisible Unicode)
  /\u200C/,  // Zero-width non-joiner
];
```

This counters a different rationalization vector — injected content in planning files manipulating agent behavior in subsequent phases.

**Source:** GSD (`gsd-prompt-guard.js`)

#### DB Guard (from Claude Forge)

Hard-blocks destructive SQL regardless of the agent's reasoning:

```bash
# db-guard.sh — PreToolUse hook for Bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if echo "$COMMAND" | grep -qiE '(DROP|TRUNCATE|DELETE\s+FROM\s+\w+\s*$)'; then
  exit 2  # BLOCK — not exit 1 (which is fail-open!)
fi
```

**Critical:** Use `exit 2` to block, NOT `exit 1`. Exit 1 is fail-open (see Known Limitations).

**Source:** Claude Forge (`db-guard.sh`)

### Architectural anti-rationalization

The most reliable approach — make skipping architecturally impossible:

| Pattern | How it prevents skipping | Source |
|---|---|---|
| **Separate writer/reviewer agents** | Reviewer has fresh context, hasn't seen the reasoning that led to the code. Cannot confirm its own bias | Metaswarm, Superpowers, OMC |
| **Orchestrator-controlled validation** | Orchestrator runs tests/lint, not the implementer. Agent cannot claim "tests pass" without proof | Metaswarm (VALIDATE phase), GSD (cross-phase gate) |
| **Spec → implementation traceability** | Review includes spec compliance check — "did we build the right thing?" as a separate dimension from code quality | claude-pipeline, Superpowers |
| **Fresh agent per task** | Each agent starts with zero knowledge of prior shortcuts or accumulated fatigue. Clean context = clean judgment | GSD, Superpowers |
| **Multiple gate pipeline** | Design → Plan → Implement → Validate → Review. Each gate is a separate agent/skill invocation. No single agent can skip a gate | Metaswarm (9 phases), GSD (5 phases) |

### Anti-pattern: Performative Agreement (from Superpowers)

Claude will say "You're absolutely right!" when a reviewer flags an issue, then implement the suggestion without checking if it actually applies to the codebase. This is "performative agreement" — agreeing with criticism to appear cooperative, then making changes that may be wrong.

**Fix:** Before implementing any reviewer suggestion, verify it against the actual codebase. Read the file, check if the pattern exists, confirm the suggestion is applicable.

**Source:** Superpowers (explicit warning against this pattern)

---

## Hooks & Rules (supplementary)

Hooks and rules are the enforcement layer — they complement agents and skills by providing deterministic, bypass-proof controls. Hooks are 100% reliable (they always fire), unlike prompt instructions which degrade with context length.

### What frameworks implement

| Framework | Hook count | Key hook innovations | Rule approach |
|---|---|---|---|
| **Citadel** | 20+ | Cost tracking from JSONL, consent tiers (SECRETS/HARD/SOFT/ALLOW), pre-compact state save, circuit breaker | Path-scoped rules |
| **Claude Forge** | 15+ | MCP cost-gate, rate limiter, output secret filter, security auto-trigger, work tracker pipeline, session wrap suggest, continuous learning observer, DB guard, version check | Per-agent rules |
| **GSD** | 6 | Context monitor with severity escalation, workflow guard (soft), prompt injection guard, command blocker | Inline in skills |
| **ECC** | 8+ | PreToolUse/PostToolUse learning hooks (100% observation), pre-compact, strategic compaction, cross-platform (Cursor support) | Language-specific rule files |
| **claude-pipeline** | 4 | File protection, auto-format, circuit breaker | Inline in skills |
| **Beads** | 3 | SessionStart mail reader, block-interactive-cmds, git pre-commit | Minimal |
| **Metaswarm** | 0 | None — relies on CLAUDE.md workflow intercepts instead | CLAUDE.md-heavy |

### Recommended hooks

#### Safety hooks (Priority 1 — add first)

| Hook | Event | What it does | Exit code | Source |
|---|---|---|---|---|
| **Dangerous command blocker** | PreToolUse (Bash) | Regex blocks destructive commands: `docker volume rm`, `DROP TABLE`, `git push --force`, `rm -rf /`, `git reset --hard`, `git checkout .` | 2 (BLOCK) | Citadel, Claude Forge |
| **DB guard** | PreToolUse (Bash) | Blocks `DROP`, `TRUNCATE`, `DELETE FROM` without WHERE clause. Separate from general command blocker for clarity | 2 (BLOCK) | Claude Forge (`db-guard.sh`) |
| **Secret protection (input)** | PreToolUse (Bash) | Blocks reading `.env`, credential files, secrets, private keys | 2 (BLOCK) | Citadel |
| **Secret protection (output)** | PostToolUse | Scans tool output for API keys, tokens, passwords. Redacts or warns | 0 + warning | Claude Forge |
| **File protection** | PreToolUse (Write/Edit) | Blocks writes to `.env`, `.git/`, `pnpm-lock.yaml`, `package-lock.json` | 2 (BLOCK) | claude-pipeline |
| **Interactive command blocker** | PreToolUse (Bash) | Blocks commands requiring interactive input (`git rebase -i`, `nano`, `vim`, `less`) | 2 (BLOCK) | Beads |

#### Observability hooks (Priority 2)

| Hook | Event | What it does | Source |
|---|---|---|---|
| **Cost tracker** | PostToolUse (time-gated, max 1/3min) | Reads session JSONL from `~/.claude/projects/{slug}/{session}.jsonl`, computes cost from `message.usage` token counts, alerts at thresholds ($5, $15, $30) | Citadel |
| **Context monitor** | PostToolUse (debounced) | Reads context metrics from bridge file, warns at ≤35% remaining, critical at ≤25% | GSD (`gsd-context-monitor.js`) |
| **Work tracker** | UserPromptSubmit + PostToolUse + Stop | Three-hook pipeline tracking session-spanning telemetry: what was asked, what was done, what was the outcome | Claude Forge |
| **Circuit breaker** | PostToolUse | After N consecutive tool failures, suggests alternatives. After 2N, escalates to user | Citadel |

#### Lifecycle hooks (Priority 3)

| Hook | Event | What it does | Source |
|---|---|---|---|
| **Pre-compact state save** | PreCompact | Writes pipeline state + files changed + pending work to checkpoint file | Citadel |
| **Post-compact notification** | PostCompact | Injects warning that context was compressed, suggests re-reading critical files. Receives `trigger` and `compact_summary` | GSD, undocumented but works |
| **Session restore** | SessionStart | Reads latest checkpoint/handoff file, restores pipeline context | Citadel |
| **Context sync after gaps** | SessionStart | Checks time since last session. If >4h, suggests `/sync` to catch up on teammate changes | Claude Forge |
| **Auto-format** | PostToolUse (Edit/Write) | Runs formatter (prettier, eslint --fix) on edited files | claude-pipeline |
| **Version check** | SessionStart | Checks if harness/plugin version is current | Claude Forge |

#### MCP-specific hooks (Priority 4 — add when using MCP tools)

| Hook | Event | What it does | Source |
|---|---|---|---|
| **Expensive MCP cost-gate** | PreToolUse (specific MCP tools) | Blocks calls to expensive tools (e.g., `hyperbrowser__browser_use_agent`) requiring user approval | Claude Forge |
| **MCP rate limiter** | PreToolUse (MCP tools) | Limits MCP calls per time window to prevent runaway costs | Claude Forge |
| **MCP auth warmup** | SessionStart | Warns that MCP OAuth connectors need manual re-toggle after compaction | Community workaround |

#### Learning hooks (Priority 5 — add for self-improving systems)

| Hook | Event | What it does | Source |
|---|---|---|---|
| **Observation capture** | PreToolUse + PostToolUse | Captures corrections and patterns deterministically (100% reliability vs ~50-80% for skill-based) | ECC v2 |
| **Security auto-trigger** | PostToolUse (Edit/Write) | Triggers security review when security-sensitive files are modified | Claude Forge |
| **Continuous learning observer** | PostToolUse | Feeds tool usage patterns into learning skill for knowledge extraction | Claude Forge |
| **Session wrap suggest** | Stop | Suggests wrapping up / saving context when session ends | Claude Forge |

### Hook implementation best practices

| Practice | Detail | Source |
|---|---|---|
| **Always consume stdin** | `INPUT=$(cat)` as first line. Not consuming stdin causes "Hook Error" labels that flood context | GSD, community research |
| **Use exit 2 to block, never exit 1** | Exit 0 = allow, exit 1 = error (FAIL-OPEN!), exit 2 = block. Security hooks using exit 1 actually ALLOW the operation | Citadel, Known Limitations |
| **Redirect stderr** | `2>/dev/null` for non-critical hooks. stderr output pollutes the conversation | Community research |
| **Time-gate expensive hooks** | Cost tracker, context monitor should not run on every tool call. Use file-based timestamp checks | Citadel |
| **Test hooks independently** | Run `echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | your-hook.sh; echo $?` | General practice |
| **Debounce warnings** | Track last-warning-time in a temp file. Suppress repeated warnings within N tool calls | GSD (5 tool calls between warnings) |
| **Soft guards for non-destructive concerns** | Use `additionalContext` injection instead of blocking. Blocking edits can deadlock the agent | GSD (workflow guard) |

### Recommended rules (path-scoped)

Rules auto-load based on file patterns. More efficient than putting everything in CLAUDE.md — each rule only loads when Claude reads/writes matching files.

| Rule category | Scope examples | What it enforces | Priority |
|---|---|---|---|
| **Backend conventions** | `apps/api/**/*.ts` | Layered architecture, DTO patterns, error handling | High |
| **Backend security** | `**/*.controller.ts` | Auth decorators, input validation, ownership checks | High |
| **Backend testing** | `**/*.spec.ts`, `**/*.int.ts` | Test patterns, no conditional skips, cleanup | High |
| **Database entities** | `**/*.entity.ts` | ORM patterns, migration rules, column conventions | High |
| **Database queries** | `**/*.dao.ts` | Query patterns, N+1 prevention, pagination | Medium |
| **Language style** | `**/*.ts` | Type rules, naming conventions, control flow | Medium |
| **Frontend components** | `**/components/**/*.tsx` | Component library usage, storybook rules | High |
| **Frontend patterns** | `**/src/**/*.{ts,tsx}` | State management, data fetching, routing | Medium |
| **Security patterns** | `**/*.{ts,tsx}` | XSS prevention, SQL injection, OWASP top 10 | High |
| **Migration files** | `**/migrations/**` | Never hand-write, always generate | High |
| **Generated files** | `**/autogenerated/**` | Never manually edit | High |
| **Agent tool definitions** | `**/agent-tools/**/*.ts` | Description quality, parameter documentation, generic instructions | Medium |

#### Language-specific rule sets (from ECC)

ECC maintains per-language security and hook rule files:

| Rule file | Scope | Content |
|---|---|---|
| `typescript-security.md` | `**/*.ts` | Type safety, `any` prevention, injection risks |
| `typescript-hooks.md` | `**/*.ts` | Hook patterns, stdin handling, exit codes |
| `python-security.md` | `**/*.py` | Subprocess injection, pickle, eval risks |
| `golang-hooks.md` | `**/*.go` | Goroutine safety, race conditions |

This per-language approach is more targeted than generic security rules and scales better across polyglot repos.

### Safety tiers for hooks (from Citadel)

| Tier | Behavior | Exit code | Examples |
|---|---|---|---|
| **SECRETS** | Always blocked, no override | 2 | `cat .env`, `source .env`, reading credentials, private keys |
| **HARD** | Always requires user approval | 2 (with prompt) | `gh pr merge`, `gh release create`, `git push --delete`, `DROP TABLE` |
| **SOFT** | User consent preference (always-ask / session-allow / auto-allow) | Configurable | `git push`, `gh pr create`, `npm publish` |
| **ALLOW** | No gate | 0 | Read-only operations, local builds, tests, lint |

**Implementation:** Tier membership is defined in the hook itself. Citadel uses a JSON config file mapping command patterns to tiers. GSD uses inline regex in each hook script.

### Cost tracking detail (from Citadel)

Claude Code writes session data to `~/.claude/projects/{slug}/{session}.jsonl`. Each line has `message.usage` with token counts.

```javascript
// Simplified cost tracking logic
const PRICING = { opus: 0.015/1000, sonnet: 0.003/1000, haiku: 0.00025/1000 };
const THRESHOLDS = [5, 15, 30, 50, 100];

function calculateCost(sessionFile) {
  const lines = fs.readFileSync(sessionFile, 'utf8').split('\n');
  let totalCost = 0;
  for (const line of lines) {
    const data = JSON.parse(line);
    if (data.message?.usage) {
      const { input_tokens, output_tokens } = data.message.usage;
      totalCost += (input_tokens + output_tokens) * PRICING[data.model];
    }
  }
  return totalCost;
}
```

A PostToolUse hook (time-gated, max once per 3 min) runs this, checks against thresholds, and injects a cost warning into `additionalContext` when a threshold is crossed.

### Hook composition patterns

| Pattern | Description | Source |
|---|---|---|
| **Two-hook pipeline** | Hook A writes to bridge file, Hook B reads and acts | GSD (statusline → context monitor) |
| **Three-hook telemetry** | Prompt hook → tool hook → stop hook spanning full session | Claude Forge (work tracker) |
| **Hook + skill coordination** | Hook captures data, skill periodically processes accumulated data | ECC (observation hooks + background Haiku agent) |
| **Guard + fallback** | PreToolUse blocks dangerous action, PostToolUse suggests safer alternative | Citadel (circuit breaker pattern) |

### Cross-platform hooks (from ECC)

ECC maintains parallel hook implementations for multiple editors:

| Platform | Hook location | Supported hooks |
|---|---|---|
| Claude Code | `.claude/settings.json` | All standard hooks |
| Cursor | `.cursor/hooks/` | pre-compact, subagent-start/stop, session-start/end, before-submit-prompt |
| Windsurf | `.windsurf/hooks/` | Similar to Cursor |

This suggests a pattern for harnesses that need to work across multiple AI coding tools.

---

## Framework Comparison Matrix

Comprehensive comparison of 14 frameworks across 18 dimensions.

| Feature | Metaswarm | GSD | Citadel | Claude-Code-Skills | claude-pipeline | ECC | SuperClaude | Orchestrator Kit | Claude Forge | gstack | OMC | Beads | Ruflo | Official Plugin |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Type** | Plugin | npm package | Plugin (Node.js) | Plugin | Portable .claude/ | Plugin | .claude/ | .claude/ | Plugin | .claude/ | .claude/ | Plugin | Plugin | Built-in |
| **Agents** | 18 | 8 + spawned | 4 tiers | Per-skill | 12 | 36 | 16 | 39 | 11 | — | 19 | Crew-based | Swarm-based | 6-8 per run |
| **Skills** | 13 | 59 | 40 | 129 (L0-L3) | 21 | 151 | 36 | 68 | 23 | 23 | — | — | — | 1 command |
| **Full SDLC** | 9 phases | 5 phases | /do router | Pipeline orch. | Issue-to-PR | Skills-based | — | 7 stages (SpecKit) | 6 phases | Autoplan pipeline | Team pipeline | Session-scoped | Swarm-scoped | Review only |
| **Parallel review** | 5-6 agents | Plan checker | /review skill | Multi-model | 2-stage | 2 agents | — | Quality gate | Single agent | — | — | — | Review swarm | 4 agents |
| **Persistence** | BEADS + plans | STATE.md + HANDOFF | Campaigns + hooks | CLI checkpoints | Status files | Memory hooks | Learnings dir | — | Agent memory | — | .omc/ + notepad | Molecules + mail | — | — |
| **Safety hooks** | — | 6 hooks | 20+ hooks | Agent steering | File protection | AgentShield | — | — | 15+ hooks | — | Kill switches | 3 hooks | — | — |
| **Cross-model** | Codex/Gemini | Codex/Gemini/OpenCode | — | Codex+Gemini+Claude | — | 5 harnesses | — | — | — | — | — | — | Multi-LLM | — |
| **Knowledge base** | JSONL (self-improving) | Seeds + threads | /learn skill | Meta-analysis | improvement-loop | Instinct learning | Self-improvement workflow | — | Agent memory dirs | — | Project memory | — | Memory manager | — |
| **Nesting solution** | CLAUDE.md intercepts | State files + agents | Leaf skills + router | Skill() vs Agent() | External shell | — | — | — | — | — | — | — | — | N/A |
| **Anti-rationalization** | Workflow intercepts | Workflow + prompt guards | — | — | Extensive tables | — | — | — | DB guard | "Boil the Lake" | Separate auth/review | — | — | — |
| **Model routing** | — | Model profiles | — | — | — | — | — | — | — | — | haiku/sonnet/opus | — | — | Haiku/Sonnet/Opus |
| **Session cycling** | — | continue-here.md | — | — | — | — | — | — | — | — | — | Mail/handoff | — | — |
| **Eval system** | Coverage | Verification agent | — | Penalty points | Pressure scenarios | — | — | — | — | LLM-as-judge | — | — | — | — |
| **Cost management** | — | — | JSONL cost tracker | — | — | — | — | — | MCP cost-gate | — | — | — | — | — |
| **Cross-platform** | — | — | — | — | — | Claude/Codex/Cursor/OpenCode | — | — | — | — | — | — | — | — |
| **Context management** | — | Context monitor (2 hooks) | Pre-compact hooks | — | — | Strategic compact | Token efficiency | — | Context sync | — | — | — | — | — |
| **Repo** | dsifry/metaswarm | gsd-build/get-shit-done | SethGammon/Citadel | levnikolaevich/claude-code-skills | aaddrick/claude-pipeline | affaan-m/everything-claude-code | SuperClaude-Org/ | maslennikov-ig/ | sangrokjung/ | garrytan/gstack | Yeachan-Heo/ | gastownhall/beads | ruvnet/ruflo | anthropics/claude-code |

---

## Framework Summaries

### Metaswarm (`dsifry/metaswarm`)

Full 9-phase SDLC: Research → Plan → Plan Review (3 adversarial agents) → Design Review (5 specialist agents) → Decomposition → Orchestrated Execution (TDD + adversarial review per work unit) → Final Review → PR Shepherd → Self-Reflect. Self-improving JSONL knowledge base learns from every PR. Cross-model review (writer != reviewer). 100% coverage enforcement. Pure prompt engineering — no code, no hooks, all prompt.

### GSD (`gsd-build/get-shit-done`)

5-phase pipeline: Discuss → Plan → Execute → Verify → Ship. State machine backed by `state.cjs` with atomic read-patch-write on STATE.md. Wave-based parallel executors with atomic commits. Context monitor with severity escalation (WARNING at 35%, CRITICAL at 25%). Workflow guard and prompt injection guard hooks. Session cycling via HANDOFF.json + continue-here.md. 59 skills, 8 core agents + dynamically spawned specialists. Cross-model support (Codex, Gemini CLI, OpenCode). Seeds system for scope management.

### Citadel (`SethGammon/Citadel`)

4-tier intent router (`/do`): pattern match → active state → keyword match → LLM classifier. Campaign persistence survives context compression via pre-compact hooks. Real cost tracking from native JSONL session files. Consent-based external action gating (secrets/hard/soft tiers). Fleet parallel execution in isolated git worktrees with discovery relay between waves. 20+ hooks for safety. 40 skills.

### Claude-Code-Skills (`levnikolaevich/claude-code-skills`)

Strict L0-L3 skill hierarchy. L0 meta-orchestrator → L1 coordinators (Skill(), shared context) → L2 domain coordinators → L3 workers (Agent(), isolated context). Key insight: "Isolate at the code-writing boundary." Multi-model review with Codex + Gemini. 28-criteria penalty points validation. Hash-verified editing via hex-line MCP. CLI checkpoint recovery. 129 skills.

### claude-pipeline (`aaddrick/claude-pipeline`)

Portable `.claude/` folder. Full GitHub issue-to-merged-PR via shell orchestrator scripts. Two-stage review: spec compliance ("right thing?") + code quality ("built well?"). TDD applied to skill documentation (pressure scenarios as tests). Anti-rationalization tables. Circuit breaker. 21 skills, 12 agents.

### Everything Claude Code / ECC (`affaan-m/everything-claude-code`)

Cross-harness compatibility (Claude Code, Codex, Cursor, OpenCode, Windsurf). Instinct-based continuous learning: auto-extracts patterns into confidence-scored instincts (0.3-0.9) that evolve into skills via `/evolve`. Hook-based observation (PreToolUse/PostToolUse) for 100% deterministic capture — V2 migration from V1's ~50-80% reliability. AgentShield red-team/blue-team security. Strategic compaction skill. 36 agents, 151 skills, cross-platform hooks.

### SuperClaude (`SuperClaude-Org/SuperClaude_Framework`)

16 specialized agents with role-based expertise (system-architect, frontend-architect, backend-architect, security-engineer, etc.). PM-Agent auto-triggers after specialist tasks for root cause analysis and prevention strategies. Self-improvement workflow with systematic investigation and monthly maintenance cycles. Token efficiency skill for context management. 36 skills with `sc:*` namespacing.

### Orchestrator Kit (`maslennikov-ig/claude-code-orchestrator-kit`)

39 agents — the most agents of any framework. 7-stage SpecKit pipeline: clarify → specify → plan → implement → checklist → tasks → taskstoissues. Meta-agent-v3 creates/improves other agents. Skill-builder-v2 creates/improves skills. Quality gates between pipeline stages. 68 skills including systematic debugging, health-security, and worktree-based parallel execution.

### gstack (`garrytan/gstack`)

The most production-grade evaluation framework. "Boil the Lake" philosophy — choose the complete version, never the 90% shortcut. Diff-based test selection via `touchfiles.ts` manifest. Two-tier test classification (gate: must-pass, periodic: benchmark). LLM-as-judge evals for skill quality assessment (~$0.15/run). Autoplan pipeline with CEO review → design review → eng review gates. 23 skills.

### OMC / oh-my-claudecode (`Yeachan-Heo/oh-my-claudecode`)

Teams-first multi-agent orchestration with 19 specialized agents. Structured team pipeline: plan → PRD → exec → verify → fix loop. Model routing via agent frontmatter (haiku/sonnet/opus). `.omc/` state directory with notepad + project memory persistence. "Ralph" autonomous mode for unattended operation. Kill switches (`DISABLE_OMC`, `OMC_SKIP_HOOKS`). Separate authoring and review passes enforced architecturally.

### Claude Forge (`sangrokjung/claude-forge`)

Most comprehensive hooks framework. 15+ hooks including: DB guard, MCP cost-gate, MCP rate limiter, output secret filter, security auto-trigger on Edit/Write, work tracker (3-hook pipeline), session wrap suggest, continuous learning observer, version check. 11 agents, 23 skills. Per-agent memory in `~/.claude/agent-memory/`. `session-wrap` skill for context persistence. `skill-factory` meta-skill. 6-layer security model.

### Beads (`gastownhall/beads`)

Novel session cycling via mail/handoff pattern. When context is exhausted, outgoing agent sends "mail" to its own address, triggers session respawn; new session's SessionStart hook reads mail and primes context. "Molecules" are persistent work assignments that survive session boundaries while ephemeral state resets. Crew-based multi-agent coordination. Minimal hooks (3) focused on safety: block-interactive-cmds, git pre-commit, session restore.

### Ruflo (`ruvnet/ruflo`)

Swarm intelligence architecture. Byzantine coordinator for consensus across agents. Memory manager with CRDT-based conflict resolution. London School TDD specialist agent (mock-driven outside-in development). Multi-repo swarms for cross-repository coordination. Code review swarms with multiple perspectives. MCP-native integration.

### Official `/code-review` Plugin (`anthropics/claude-code`)

Single markdown file, zero code. Model routing: Haiku triage, Sonnet compliance (2x redundant), Opus bugs/security. Validation pass: every issue verified by second agent with independent context. Aggressive false-positive filtering. The reference implementation for review architecture — proves a sophisticated multi-agent pipeline can be built from a single SKILL.md file.

---

## Sources

### Primary frameworks analyzed

| Framework | Repository | Key contribution |
|---|---|---|
| Metaswarm | https://github.com/dsifry/metaswarm | 9-phase SDLC, adversarial review, self-improving knowledge |
| GSD | https://github.com/gsd-build/get-shit-done | State machine, context monitoring, session cycling, workflow guards |
| Citadel | https://github.com/SethGammon/Citadel | Safety tiers, cost tracking, campaign persistence, fleet execution |
| Claude-Code-Skills | https://github.com/levnikolaevich/claude-code-skills | L0-L3 hierarchy, Skill()/Agent() split, penalty points validation |
| claude-pipeline | https://github.com/aaddrick/claude-pipeline | Anti-rationalization, shell orchestrators, two-stage review |
| Everything Claude Code | https://github.com/affaan-m/everything-claude-code | Instinct learning, cross-platform, strategic compaction |
| SuperClaude | https://github.com/SuperClaude-Org/SuperClaude_Framework | 16 specialized agents, self-improvement workflow |
| Orchestrator Kit | https://github.com/maslennikov-ig/claude-code-orchestrator-kit | 39 agents, SpecKit pipeline, meta-agent |
| Claude Forge | https://github.com/sangrokjung/claude-forge | 15+ hooks, MCP cost-gate, DB guard, work tracker pipeline |
| gstack | https://github.com/garrytan/gstack | Diff-based test selection, LLM-as-judge evals, "Boil the Lake" |
| OMC | https://github.com/Yeachan-Heo/oh-my-claudecode | Teams-first orchestration, model routing, kill switches |
| Beads | https://github.com/gastownhall/beads | Session cycling via mail/handoff, molecule persistence |
| Ruflo | https://github.com/ruvnet/ruflo | Swarm intelligence, Byzantine coordinator, London School TDD |
| Official /code-review | https://github.com/anthropics/claude-code/tree/main/plugins/code-review | Model routing, validation pass, reference implementation |

### Additional frameworks referenced

| Framework | Repository |
|---|---|
| Claude Octopus | https://github.com/arosboro/claude-octopus |
| HAMY 9-Agent | Community reference (no public repo) |
| Claudeception | https://github.com/PierrunoYT/claudeception |
| Continuous-Claude | https://github.com/mbailey/continuous-claude |
| claude-meta | https://github.com/dsifry/claude-meta |
| claude-reflect | https://github.com/ruvnet/claude-reflect |
| Session-Wrap | https://github.com/sangrokjung/claude-forge (session-wrap skill) |
| Agent Farm | https://github.com/anthropics/claude-code (built-in) |
| claude-code-sub-agents | https://github.com/lst97/claude-code-sub-agents |

### Documentation & research

| Resource | URL |
|---|---|
| Claude Code Skills Docs | https://code.claude.com/docs/en/skills |
| Claude Code Sub-agents Docs | https://code.claude.com/docs/en/sub-agents |
| Anthropic "Building Effective Agents" | https://docs.anthropic.com/en/docs/build-with-claude/agents |
| Awesome Claude Code | https://github.com/hesreallyhim/awesome-claude-code |
| Awesome Claude Skills | https://github.com/ComposioHQ/awesome-claude-skills |
| Skill-calling-skill bug | https://github.com/anthropics/claude-code/issues/17351 |
| Subagent nesting bug | https://github.com/anthropics/claude-code/issues/4182 |

---

## Redundant Instructions Audit

### Problem

Agent and skill definitions often include instructions that Claude Code already handles automatically. This creates three issues: (1) wasted context tokens on every invocation, (2) potential conflicts if auto-loaded rules change but duplicated instructions don't, and (3) Claude may over-index on repeated instructions at the expense of unique, task-specific guidance.

### What Claude Code Auto-Loads (No Need to Repeat)

| Content | When loaded | Scope |
|---|---|---|
| `CLAUDE.md` (project root) | Every turn, including subagents | Global — all agents see it |
| `.claude/rules/*.md` | Session start, re-loaded for subagents | Global or path-scoped |
| Agent frontmatter (`tools`, `model`, `maxTurns`) | Agent spawn | Per-agent |
| `MEMORY.md` (first 200 lines) | Session start | Global |

**NOT auto-loaded** (must be explicitly read if needed): README.md, CONTRIBUTING.md, ADR docs, package.json scripts, code pattern files.

### What Counts as Redundant

1. **Git constraints already in CLAUDE.md** — e.g., "Never commit without user approval" restated in individual agents
2. **Tool-teaching** — e.g., "Use Grep to search for patterns, Glob to find files" — Claude already knows its tools
3. **Generic tool mechanics** — Tables mapping tasks to tool names add no value
4. **"Using the Read tool" phrasing** — Instructing Claude to use a specific tool for file reading is unnecessary

### Findings and Fixes

| File | Issue | Action |
|---|---|---|
| `agents/backend-agent.md` | Line 68: "Run git add, git commit, or git push" — initially removed as redundant with CLAUDE.md, then **restored** | Restored with clarified wording |
| `agents/frontend-agent.md` | "No Git operations" — initially removed as redundant, then **restored** | Restored with clarified wording |
| `agents/frontend-agent.md` | Tools & Approach table teaching tool mechanics (Glob, Grep, Read, Write, Edit, Bash) | Removed entire table |
| `agents/skeptic-agent.md` | Search Strategy section taught tool syntax (`Glob(pattern=...)`, `Grep(pattern=...)`) | Rewritten to keep priority-order concept, removed tool-teaching |
| `agents/refactor-agent.md` | Tools & Techniques section listing tool descriptions | Removed entire section |
| `agents/reviewer-agent.md` | "using the Read tool" phrasing in initialization | Simplified to "load these criteria files" |
| `skills/review/SKILL.md` | "read these files using the Read tool" + "Read `.claude/skills/...`" phrasing | Simplified to "load these criteria files" |

### What Was Kept (Not Redundant)

| File | Content | Reason |
|---|---|---|
| `agents/architect-agent.md` | List of auto-loaded vs. not-auto-loaded files | Correctly documents what the architect needs to explicitly read — this is unique knowledge |
| `agents/backend-agent.md` | "Don't run git add/commit/push — the orchestrating skill handles git" | NOT redundant with CLAUDE.md. CLAUDE.md says "ask before committing" (a gate). The agent constraint says "never do git at all" (a ban). Different semantics: subagents shouldn't touch git because the parent skill manages shipping |
| `agents/frontend-agent.md` | "No Git operations: orchestrating skill handles commits, branches, and PRs" | Same reasoning as backend-agent — subagent delegation boundary |
| `skills/implement/SKILL.md` | "Do NOT run git add/commit/push — the orchestrator handles git" | Context-specific: tells implementation subagents that the parent skill handles git, not a general rule |
| `skills/implement/SKILL.md` | Phase 6 ship options and "Never commit without explicit user approval" | Operational instructions for the shipping phase, not a redundant constraint |

### Recommendations

1. **Audit periodically**: As CLAUDE.md evolves, check agents/skills for newly-redundant content
2. **Prefer intent over mechanics**: Say "verify file existence before reading" not "use Glob to check if file exists then use Read to read it"
3. **Trust auto-loading**: Don't repeat CLAUDE.md rules in individual agents — they already receive it
4. **Reserve agent instructions for unique behavior**: Agent definitions should focus on what makes that agent different, not general Claude Code operation

---

## Post-Setup Cleanup: Template Garbage Prevention

### Problem

After running `setup.sh`, template artifacts can survive into the final output — confusing Claude with irrelevant instructions, wrong-language code examples, broken placeholders, and meta-instructions meant for human setup authors, not for AI consumption.

### Categories of Garbage Found

| Category | Example | Impact |
|---|---|---|
| **Missing placeholder replacement** | `{{LINTER_COMMAND}}` never replaced in backend-agent | Agent sees literal `{{...}}` placeholder |
| **Meta-instructions surviving setup** | "TEMPLATE NOTICE: Customize placeholders below" | Wastes context, confuses agent |
| **Placeholder reference lists** | `- \`{{FRAMEWORK}}\` → React, Vue, Angular...` (already substituted) | Agent sees choice lists with replaced values alongside options |
| **"none" default values** | `ORM: (auto-detected: none)` | Noise — adds nothing |
| **Generic multi-language references** | "package.json (or requirements.txt, Cargo.toml, etc.)" in Python project | Irrelevant |
| **Wrong-language code blocks in rules** | Python examples in `security-patterns.md` for a TypeScript project | Wastes token budget, may confuse patterns |
| **Customization Guide sections** | Template instructions at bottom of rules files | Meta-content not for AI |
| **Sed/eval escaping failures** | `ruff check . && ruff format --check .` broken by `eval` and sed `&` metacharacter | Commands garbled |
| **Overly broad sed patterns** | Deleting any line containing "Zustand" or "Playwright" | Accidentally removes frontmatter, role descriptions, stack tables |

### Fixes Applied to setup.sh

**1. Missing replacements added:**
- `{{LINTER_COMMAND}}` → derived from `DISCOVERED_CMDS[lint]`
- `TEST_RUNNER` now set for all languages (Python→pytest, Rust→cargo test, Go→go test, Java→JUnit, Ruby→RSpec, C#→xUnit)

**2. Sed-safe escaping:**
- Added `sed_escape()` helper that escapes `&`, `|`, `\`, `/` in replacement strings
- All variables passed through `sed_escape()` before use in `run_or_dry_run` (which uses `eval`)
- Prevents `&&` in commands like `ruff check . && ruff format --check .` from breaking

**3. Cleanup phase added (runs after placeholder replacement):**

CLAUDE.md cleanup:
- Removes "Template guide" meta-instruction line
- Replaces generic "package.json (or requirements.txt, Cargo.toml, etc.)" with detected dependency file
- Converts unreplaced instructional placeholders to `# TODO:` comments
- Removes "Template: customize {{PLACEHOLDERS}}" from agent description lines
- Builds tech stack string omitting "none" values

Agent file cleanup:
- Removes "TEMPLATE NOTICE" and "TEMPLATE:" lines
- Removes placeholder reference lists (pattern: `- \`Value\` → Option1, Option2, etc.`)
- Removes "Example Placeholder Customization" sections entirely
- Strips "(customizable for ...)" parentheticals
- Removes lines where detection resulted in "none"
- Removes "via Glob/Grep" tool-teaching references
- Removes table rows with "none" values
- Fixes hardcoded "TypeScript (strict mode)" based on detected language
- Collapses consecutive blank lines

Rules file cleanup:
- Removes "Customization Guide" sections from all rules files
- Narrows glob patterns to detected language extensions (e.g., `*.{js,ts,py,go,...}` → `*.{js,ts,jsx,tsx}`)
- Removes code blocks for non-detected languages (e.g., Python blocks removed from TS project)

**4. Final sweep:**
- Warns user about any remaining `{{...}}` placeholders (excluding legitimate template syntax like Jinja `{{ user_comment }}`)

### Verification

Tested with two project types:
- **Next.js/React/TS project**: All JS-specific, no Python/Go/Ruby garbage. Globs narrowed to `*.{js,ts,jsx,tsx}`. Frontend agent has correct stack (Next.js, React, Zustand, Tailwind CSS, Vitest).
- **Django/SQLAlchemy/Python project**: All Python-specific, no TypeScript garbage. Globs narrowed to `*.py`. Backend agent shows Django, SQLAlchemy, pytest correctly. `&&` in lint commands survives escaping.

> **Note:** The cleanup described above documents fixes applied to setup.sh before it was superseded by the AI-driven `/setup` skill. The section is preserved for historical reference and to document the problems that motivated the architectural change.

---

## AI-Driven Setup: From Bash Script to Skill

### The Problem with setup.sh

After extensive work fixing setup.sh (placeholder escaping, garbage cleanup, language filtering, sed pattern bugs), a pattern emerged: every fix added complexity to work around fundamental limitations of the bash-script-plus-templates approach.

| Problem | Root Cause | Fixes Required |
|---|---|---|
| `&&` in commands corrupted by eval | Shell metacharacters in sed replacement strings | `sed_escape()` helper, pre-escaping all variables |
| Overly broad sed patterns delete wrong lines | Regex alternatives (`\|`) match entire pattern, not subgroups | Rewrite patterns to match specific line formats |
| "none" values appear in generated files | Defaults always substituted, even when no value detected | Cleanup phase to delete "none" lines, table rows, etc. |
| Wrong-language code blocks in rules | Templates contain all languages, sed removes non-matching | Language-specific `sed` deletion for 7+ language pairs |
| Meta-instructions survive setup | "TEMPLATE NOTICE" and placeholder guides not removed | Dedicated cleanup sed commands for each pattern |
| Generic dependency references | "package.json (or requirements.txt, Cargo.toml, etc.)" | Language-aware DEP_FILE variable |
| TEST_RUNNER missing for non-JS languages | Only JS/TS detection set the variable | Add TEST_RUNNER to every language block |
| Unreplaced instructional placeholders | setup.sh only replaced known `{{VARS}}`, not instructional ones | Convert each to `# TODO:` comments |

Each fix was 5-20 lines of bash. After 8 rounds of fixes, the script reached ~850 lines — increasingly fragile, hard to test, and impossible to extend for new edge cases.

### Industry Trend: AI-Driven Setup

Research across the ecosystem confirms the direction:

| Tool | Approach | Key Insight |
|---|---|---|
| Claude Code `/init` (new) | Interview-based (`CLAUDE_CODE_NEW_INIT=1`) | Anthropic itself is moving from bash scanning to AI interview |
| Cursor v0.49+ | `/Generate Cursor Rules` in chat | AI generates rules by analyzing codebase in-context |
| `agents-md-generator` | Hybrid: auto-scan + interactive Q&A | Combines objective detection with subjective preferences |
| `codebase-context` | Git history + code analysis | Detects team conventions from actual usage patterns |
| Windsurf | Semantic indexing + memory system | Pre-scans repository for deep context awareness |
| `claude-rules` | Auto-detect + language-specific rule generation | Multi-tool rule generation from codebase analysis |

**Key insight from research:** The industry is moving from "auto-generate config" to "hybrid auto-detect + interview" — recognizing that optimal setup requires both objective data (tech stack, commands) and subjective knowledge (conventions, architectural decisions, team preferences).

### New Architecture: `/setup` Skill

Replaced `setup.sh` with `skills/setup/SKILL.md` — an AI-driven skill that combines codebase analysis with user interview.

**File classification:**

| Category | Files | Setup Action |
|---|---|---|
| **Universal** (work for any project) | 10 agents, 11 skills, 12 hooks, settings.json, review criteria | Copy directly — no modification needed |
| **Project-specific** (need tailoring) | CLAUDE.md, backend-agent, frontend-agent, 2 rules files | AI generates from scratch based on analysis + interview |
| **Reference examples** (AI reads during setup) | `_reference/*.example.md` | Not copied — serve as format guides for AI generation |

**The 4-phase skill flow:**

1. **Analyze** — Deep codebase scan: language, framework, ORM, test runner, linter, directory structure, architecture patterns, validation commands (3-source priority). No user input needed.

2. **Interview** — AskUserQuestion for things AI can't detect: confirm detection results, workflow preferences (git strategy, review thoroughness), team conventions (architecture pattern, error handling), integrations (Linear, database safety), scope (full/core/minimal/custom).

3. **Generate** — Copy universal files directly. Generate the 5 project-specific files from scratch using reference examples as structural guides. The AI writes these as original documents tailored to the specific project — no templates, no placeholders, no sed.

4. **Verify** — Check all generated files for: valid markdown, no `{{placeholder}}` patterns, no wrong-language content, CLAUDE.md under 150 lines, valid JSON in settings.json, executable hooks, correct agent frontmatter.

**Why this is better:**

| Aspect | setup.sh | /setup skill |
|---|---|---|
| Detection depth | Grep for package names | AI reads and understands config files, code patterns, directory structure |
| Edge cases | Each needs new bash code | AI handles naturally — it understands context |
| Output quality | Template with values substituted | Original document written for this specific project |
| Maintenance | ~850 lines of fragile bash | ~200 lines of skill instructions |
| Extensibility | Add sed commands for each new feature | Describe what you want in natural language |
| Testing | Need to run on real repos | Skill output is verifiable markdown |
| Convention detection | Can't detect — only tech stack | AI can reference actual files as "golden examples" |
| Interview | Static bash prompts | Adaptive AskUserQuestion — only asks what can't be auto-detected |
| Existing config | Overwrites or skips | Detects .cursorrules, existing CLAUDE.md — offers to merge/port |
| Re-running | Dangerous — may re-sed already-sed'd files | Smart re-run with merge/update/add options |

### Directory Structure Change

```
Before (setup.sh approach):
  setup.sh                    # 850-line bash script
  CLAUDE.md                   # Template with {{PLACEHOLDERS}}
  agents/backend-agent.md     # Template with {{PLACEHOLDERS}}
  agents/frontend-agent.md    # Template with {{PLACEHOLDERS}}
  rules/backend-conventions.md  # Multi-language template
  rules/security-patterns.md    # Multi-language template

After (/setup skill approach):
  skills/setup/SKILL.md       # AI-driven setup skill
  CLAUDE.md                   # Stub → "Run /setup"
  agents/backend-agent.md     # Stub → "Run /setup"
  agents/frontend-agent.md    # Stub → "Run /setup"
  rules/backend-conventions.md  # Stub → "Run /setup"
  rules/security-patterns.md    # Stub → "Run /setup"
  _reference/                   # Reference examples for AI
    CLAUDE.md.example
    agents/backend-agent.example.md
    agents/frontend-agent.example.md
    rules/backend-conventions.example.md
    rules/security-patterns.example.md
    setup.sh.legacy             # Preserved for reference
```

### Recommendations

1. **Use `/setup` for all new projects** — it replaces setup.sh entirely
2. **Keep `_reference/` in the template** — AI needs structural examples to generate consistent output
3. **Universal files should stay template-ready** — skills, hooks, and universal agents work for any project and don't need AI generation
4. **Re-run `/setup` after major stack changes** — the skill handles re-run gracefully with merge/update options

---

## Implement & Follow-Up Skill Audit

### Research Methodology

Compared the `/implement` (6-phase pipeline) and `/follow-up` (quick post-implementation changes) skills against industry best practices from 2025-2026, including: multi-agent orchestration patterns (Metaswarm, claude-pipeline, Addy Osmani's "Code Agent Orchestra"), AI code review automation (Qodo, CodeAnt, Augment Code), retry/error recovery patterns (LangGraph, Sparkco), state persistence (AWS DynamoDB checkpointing, Zylos), and scope control research.

### What Was Already Well-Implemented

**Implement skill — strong areas:**
- 6-phase pipeline with clear WAIT gates at discovery, architecture approval, and ship
- Work unit decomposition with dependency waves and parallel agent execution
- State persistence via `.planning/STATE.md` and `.planning/NOTES.md`
- Mid-flow user input classification (note/preference/correction/blocker)
- Convention discovery in Phase 1 with CONVENTIONS_BRIEF passed to subagents
- Startup/boot check in Phase 4 (step 4)
- Git workspace setup with branch/worktree options
- Linear integration throughout (status updates, branch naming, PR linking)

**Follow-up skill — strong areas:**
- 4-level complexity assessment (trivial/small/medium/too-large) with file + module count
- Hard escalation signals list (new entity, auth, 3+ modules, etc.)
- Anti-rationalization in review ("do not approve just because it implements what was asked")
- Clear examples for each complexity level

### Gaps Found and Fixed

**Implement Skill:**

| Gap | Industry Best Practice | Fix Applied |
|---|---|---|
| **Spec compliance check was vague** | Two-stage review: spec compliance (Stage A) before code quality (Stage B). Spec compliance should be structured, not just "check spec first" | Added explicit Stage A with 4 concrete verification steps: requirement-by-requirement check, API signature verification, edge case coverage, acceptance criteria pass/fail |
| **Hardcoded npm commands in Phase 4** | Validation commands should reference project config, not assume npm | Replaced `npm run build && npm run lint` with reference to CLAUDE.md's Essential Commands section |
| **No escalation when fix rounds exhaust** | After max iterations (2-3), change strategy — don't retry same approach | Added structured handoff after 3 review rounds: classify remaining issues as spec gap vs. code quality, offer re-architecture or `/follow-up` options |
| **Escalation rule missing** | If same error persists 2+ rounds with no progress, approach is wrong | Added: "don't retry same strategy — escalate to re-architecture (Phase 2)" |
| **TodoWrite mentioned only at end** | Progress tracking should start immediately | Expanded TASK EXECUTION to create full Phase 1-6 checklist at pipeline start |
| **Autofix commands hardcoded** | Should use project's configured commands | Changed to reference `format_fix` and `lint_fix` from CLAUDE.md |

**Follow-Up Skill:**

| Gap | Industry Best Practice | Fix Applied |
|---|---|---|
| **No iteration depth limit** | 2 iterations max on small changes before escalating | Added: after 2 failed validation attempts, use AskUserQuestion to offer different approach, escalation to `/implement`, or manual guidance |
| **No prior context loading** | Follow-ups should inherit discoveries from prior implementation | Added "Prior Context" section: check for SPEC.md, ARCHITECTURE.md, STATE.md and load if present |
| **No git handling** | Follow-up changes need commit guidance | Added diff preview and AskUserQuestion with commit/push/leave options (matching `/implement` Phase 6 pattern) |
| **Validation was vague** | Should reference project's configured commands | Changed to "use the project's validation commands from CLAUDE.md" |
| **No Linear integration** | Follow-ups on Linear issues should update the tracker | Added Linear section: detect issue ID, fetch context, comment after shipping |
| **No TodoWrite usage** | Progress tracking for user visibility | Added Task Tracking section with todo creation and status updates |
| **No diff preview at ship** | User should see what changed before approving | Added `git diff --stat` before ship approval |
| **Definition of Done incomplete** | Should include prior context and Linear | Added: "Prior context loaded" and "Linear issue updated" items |

### What Was NOT Changed (Already Correct)

| Area | Why It's Already Correct |
|---|---|
| 6-phase pipeline structure | Research confirms Discover → Architect → Implement → Validate → Review → Ship is aligned with industry. No phase should be added or removed. |
| Phase 3 parallel decomposition | Work unit approach with waves matches "Code Agent Orchestra" best practices. Sweet spot of 2-4 parallel agents confirmed. |
| Phase 4 startup check | Already included (step 4). Boot-and-check pattern matches industry standard. |
| State persistence model | `.planning/STATE.md` with phase checkpointing already follows LangGraph-style checkpointing. |
| Mid-flow user input handling | Classify → log → evaluate → backtrack pattern is more sophisticated than most frameworks. |
| Phase 5 two-stage review concept | "Spec compliance first, code quality second" was already stated — just needed the spec compliance check to be more concrete. |
| Follow-up escalation signals | The hard escalation list (new entity, auth, 3+ modules) matches scope control research. |
| Follow-up complexity levels | 4-level assessment with file + module count + smell detection is well-calibrated. |

### Industry Insights Worth Noting

1. **Review cycle count**: Industry standard is max 1-2 review iterations for well-decomposed PRs. Our 3-round max is generous but appropriate for AI-generated code which may need more correction.

2. **Single-function task accuracy**: Research shows 87% accuracy for single-function tasks vs. 19% for feature-level. Our work unit decomposition (1-5 files per WU) targets this sweet spot.

3. **PR size threshold**: Industry recommends under 400 lines per review. Our multi-wave decomposition naturally keeps individual agent output small.

4. **Claude Code's `/init` moving to interview-based**: Confirms our approach of using AskUserQuestion for discovery over static detection.

5. **Context amnesia is the #1 subagent failure mode**: Our CONVENTIONS_BRIEF + pre-inlined context addresses this directly. The follow-up skill now also loads prior context.

---

## Upgrade & Sync Mechanism

### Problem Statement

Three scenarios need to be handled:

1. **Template version upgrade** — The template gets new skills, improved agents, or bug fixes. How does a project update its installed harness without losing customizations?
2. **First setup with existing files** — A project already has some `.claude/` files (from a colleague, a different template, or manual setup). Some files may have the same names as template files but different content.
3. **Context efficiency** — Harness files are large (50+ files). How does the LLM identify changes and apply them without loading everything into context?

### Research Summary

Researched scaffolding tools (Yeoman, CRA, Next.js, Angular CLI, Rails), dotfile managers (chezmoi, yadm, dotbot, GNU Stow), git-based template sync (Copier, Cruft, Cookiecutter), AI coding framework config sync (cursor2claude, rulesync), and semantic diff tools (Semantic Merge, Graphtage, SemanticDiff).

**Key findings:**

1. **Most scaffolding tools lack upgrade mechanisms** — Yeoman, CRA, Rails have no built-in "update existing project" flow. They're designed for one-time generation.

2. **Copier/Cruft are the gold standard for template sync** — Both use 3-way merge (old template + user changes + new template) with version tracking via metadata files (`.copier-answers.yml`, `.cruft.json`). Cruft stores the template commit hash, enabling precise diffs.

3. **Text-based diffs are inadequate for prompt files** — Git's 3-way merge treats files as lines of text. For agent definitions and skill instructions, *semantic meaning* matters more than exact text. A rewording for clarity is a non-change; a new constraint is a meaningful change. Line-based tools can't distinguish these.

4. **Angular schematics show intelligent upgrade is possible** — `ng update` runs transformation rules that understand code structure. Schematics can create, modify, or delete files with awareness of what they contain. This is closer to what AI prompt files need.

5. **AI coding frameworks have no standard upgrade mechanism** — Communities build ad-hoc sync tools (cursor2claude, rulesync). The AGENTS.md standard is emerging but doesn't address versioning. Claude Code's `/init` has no "re-init to update" flow.

6. **Changelog-driven upgrades beat full-file diffing** — Instead of comparing every file (expensive, context-heavy), maintain a human-readable changelog. The upgrade tool reads the changelog to know what changed and why, then only examines affected files. This is crucial for context efficiency.

### Architecture Decision: AI-Driven Semantic Upgrade

Chose an AI-driven `/upgrade` skill over migration scripts or text-based diffing. Rationale:

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **Migration scripts** (Rails-style) | Predictable, testable | Brittle for prompt files, can't handle user customizations, N migrations to maintain | Rejected |
| **3-way text merge** (Copier/Cruft) | Well-proven for code | Can't understand semantic meaning of prompt changes, false conflicts on rewordings | Rejected for primary mechanism (useful as fallback) |
| **Full-file AI comparison** | Semantically aware | Context-heavy (reading 50+ file pairs), expensive, slow | Rejected |
| **Changelog-driven AI upgrade** | Context-efficient, semantically aware, handles customizations | Requires maintaining a changelog | **Chosen** |

### Implementation: Three New Components

**1. Version Tracking (`HARNESS_VERSION` + `.harness-meta.json`)**

- `HARNESS_VERSION`: Simple file with semantic version (e.g., `1.0.0`). Lives in template root.
- `.harness-meta.json`: Written by `/setup` into the project's `.claude/` directory. Tracks:
  - Installed template version
  - Per-file metadata: source (universal/generated/user), templateHash (MD5 at install), customized flag
  - Project context (language, framework) for regeneration

Inspired by Cruft's `.cruft.json` (commit hash tracking) and Copier's `.copier-answers.yml` (stored answers for re-generation).

**2. `/upgrade` Skill (5 phases)**

- Phase 1 — Inventory: read installed manifest + new template version + changelog between versions
- Phase 2 — Classify: for each changed file, determine action (auto-update / semantic merge / user decision) based on whether user customized it
- Phase 3 — Semantic Merge: for conflicted files, use AI to understand what both sides changed and merge intelligently. Key innovation: section-level comparison using changelog hints, not full-file diffs.
- Phase 4 — Apply: backup first, then auto-updates, then merges, then regenerations. Update manifest.
- Phase 5 — Verify: validate all modified files, present summary report.

**3. `/setup` Existing File Conflict Resolution (Phase 1.5)**

Added to `/setup` for the case where a project already has `.claude/` files from a different source:

- Scan existing files
- Match against template files by path
- For matched files: semantic comparison (identical / user-superset / template-superset / divergent)
- Efficient comparison: read frontmatter + headers first, only dive into sections if needed
- Present grouped findings to user with recommendations
- Record decisions in manifest

### Context Efficiency Strategies

The core challenge: how to identify and apply changes without loading 50+ files into context.

| Strategy | How It Works | Context Savings |
|---|---|---|
| **Changelog-driven** | Read changelog first. Only examine files mentioned in it. | Skip ~80% of files (unchanged between versions) |
| **Hash-based skip** | Compute MD5, compare against manifest. Identical = skip. | Zero context for unchanged files |
| **Section-level comparison** | Changelog says "Phase 5 changed". Read only Phase 5 from both files. | ~70% savings per conflicted file |
| **Batch auto-updates** | Files not customized by user get a simple copy. No AI analysis. | Zero AI context for clean updates |
| **Progressive header scan** | Compare `## ` headers before reading section content. | Quickly classify relationship without full read |

This design means a typical upgrade (say, 5 files changed in new version, user customized 2 of them) reads:
- 1 changelog file (small)
- 5 file hashes (instant)
- 2 conflicted file sections (partial reads)
- Total: ~10-15% of the context that a naive "compare everything" approach would use.

### What Changed

| File | Change |
|---|---|
| `HARNESS_VERSION` (new) | Template version number (`1.0.0`) |
| `CHANGELOG.md` (new) | Version history for upgrade skill to read |
| `skills/upgrade/SKILL.md` (new) | Full upgrade skill — 5 phases, semantic merge, conflict resolution |
| `skills/setup/SKILL.md` | Added Phase 1.5 (existing file conflict resolution), Phase 4.2 (manifest generation), updated Re-Running Setup to reference /upgrade |
| `README.md` | Added upgrade section, updated skill count to 13, added /upgrade to directory tree |

### What Was NOT Added (Deliberate Omissions)

1. **No automatic upgrade trigger** — User must explicitly run `/upgrade`. No auto-check-for-updates. Reason: upgrades should be intentional, not surprising.

2. **No rollback command** — Backup is created, user can `cp -r .claude.backup.*/ .claude/` manually. A dedicated rollback skill adds complexity with little value since backups are simple directory copies.

3. **No partial version upgrades** — Can't upgrade to "just 1.1.0" if 1.2.0 is available. Always upgrades to latest. Reason: partial upgrades create weird intermediate states. If a user wants to skip a version's changes, they can use `--check` to preview and then skip individual files during the upgrade.

4. **No migration scripts** — No `migrate_1.0_to_1.1.sh` files. All upgrade logic is in the AI skill, driven by the changelog. Reason: migration scripts are brittle for prompt files and require maintenance per version pair.

---

## Legacy Cleanup & Post-Setup Artifact Prevention

### Legacy Files Removed

| File | Reason |
|---|---|
| `_reference/setup.sh.legacy` | 1,016-line bash setup script from old approach. No longer needed — `/setup` skill reads `_reference/*.example` files instead. |
| `scripts/` (empty directory) | Leftover from earlier iteration. No contents. |

### Legacy References Cleaned

- README.md: removed "instead of brittle bash scripts" phrasing, removed "Bash Script (old approach) vs AI Skill" comparison table, removed `setup.sh.legacy` from directory tree
- CHANGELOG.md: replaced "replacing bash scripts" with neutral description
- skills/setup/SKILL.md: replaced "replaces traditional setup scripts" intro with forward-looking description

### Reference File Notices Updated

- `_reference/agents/backend-agent.example.md`: Changed "TEMPLATE NOTICE: Customize the {{PLACEHOLDERS}}" to "Reference example: /setup reads this for structure guidance"
- `_reference/CLAUDE.md.example`: Changed "Template guide: Replace {{PLACEHOLDERS}}" to "Reference example: /setup reads this for structure guidance"

These notices were misleading — they suggested humans should manually fill in placeholders, when actually the AI `/setup` skill reads them as structural examples and generates fresh project-specific files.

### Post-Setup Cross-Language Contamination Prevention

**Problem:** The `_reference/` examples intentionally contain multi-language content (TypeScript AND Python code blocks, mentions of Django AND Express AND Rails, etc.) to cover all possible stacks. When the `/setup` skill generates project-specific files, it reads these references for structure guidance. Risk: the LLM copies content from the reference without filtering out wrong-language artifacts.

**Prevention added at three levels:**

1. **Generation instructions (Phase 3)**: Added explicit "anti-leakage rules" to each generation step:
   - Backend agent: "only include the ONE detected framework — remove all others"
   - Frontend agent: "only include the ONE detected framework"
   - Rules files: "Include ONLY the detected language's code examples. If project is Python, every code block must be Python — zero TypeScript/Go/Java/Ruby."
   - CLAUDE.md: "No cross-language content: If the project is Python, don't mention npm/yarn/tsc."
   - All: "Do NOT copy from reference — generate fresh. Reference is for structure guidance only."

2. **Verification (Phase 4.1)**: Added three concrete verification checks:
   - **Cross-language contamination check**: Language-specific search table — if project is Python, grep generated files for `npm`, `yarn`, `jest`, ````typescript`, etc. If found, determine if legitimate (monorepo) or artifact (generation leak) and fix.
   - **Template artifact check**: Search for template-language phrases ("customize this", "e.g., Django, Rails, FastAPI", "customizable for") that indicate generic content survived into project-specific files.
   - **Reference contamination check**: Spot-check generated files against their reference examples. If sections are identical (just with placeholders filled in), the file was copied rather than generated fresh and needs to be redone.

3. **Reference file framing**: Updated notices in `_reference/*.example` files to clearly state they are structural examples, not fill-in-the-blank templates. This reduces the risk of the LLM treating them as templates to copy-and-fill.

---

## Full Template Audit: All Skills & Agents

### Methodology

Reviewed all 13 skills and 12 agents against 10 evaluation dimensions: frontmatter completeness, structure/clarity, hardcoded commands, error handling, user interaction, anti-rationalization, scope control, skill/agent integration, TodoWrite usage, and Definition of Done. Each file also compared against internet best practices for its domain. Six parallel review agents ran simultaneously, each covering a cluster of files.

Previously audited: `/implement` and `/follow-up` (see earlier section). This audit covers the remaining 11 skills and 12 agents.

### Consistent Gaps Found Across Files

| Gap | Affected Files | Severity | Fix Applied |
|---|---|---|---|
| **Missing git constraints** | architect, refactor-agent, devops, doc, meta, knowledge, security, debugger, skeptic, reviewer agents + backend/frontend stubs | Critical | Added "Rule 0: No Git Operations" (or equivalent Critical Constraints section) to all 12 agents. |
| **AskUserQuestion missing from allowed-tools** | refactor, simplify, features skills | Critical | Added AskUserQuestion to all three. |
| **Hardcoded test commands** | simplify (`npm test`, `python -m pytest`, `go test`), debug (`run full test suite if feasible`) | Warning | Replaced with "project's test command from CLAUDE.md". |
| **No escalation/retry limits** | refactor, simplify, debug skills | Warning | Added: refactor/simplify "3 failures → AskUserQuestion", debug "5 hypothesis tests → escalate", "2 fix failures → escalate". |
| **Backend/frontend stubs too minimal** | backend-agent.md, frontend-agent.md | Warning | Added: scope boundaries, convention guidance, error reporting instructions, anti-rationalization constraints. |

### Per-File Findings

#### Skills

| Skill | Rating | Key Strengths | Gaps Found | Fix Applied |
|---|---|---|---|---|
| **setup** | 8/10 | Comprehensive 4-phase pipeline, anti-leakage rules, conflict resolution | No TodoWrite mention, no detection retry logic | Not fixed (nice-to-have) |
| **upgrade** | 8/10 | Changelog-driven efficiency, semantic merge, hash tracking | Assumes CHANGELOG always exists, generated file regeneration underspecified | Not fixed (edge cases) |
| **spec** | 7.5/10 | Gray areas framework excellent, AskUserQuestion used well | No BDD/Gherkin format, DoD product-focused not LLM-focused | Not fixed (nice-to-have) |
| **review** | 8/10 | Multi-agent parallel, confidence scoring, batched mode | No explicit fix loop, triage is pattern-based not risk-based | Not fixed (review is called by /implement which has fix loops) |
| **refactor** | 7.5/10 | Strong anti-rationalization, incremental execution | Missing AskUserQuestion, no retry limit, hardcoded commit | Fixed: added AskUserQuestion, escalation at 3 failures, removed hardcoded commit |
| **simplify** | 7/10 | Good simplification patterns, clarity principle | Missing AskUserQuestion, hardcoded test commands, no retry limit, no complexity metrics | Fixed: added AskUserQuestion, escalation at 3 failures, reference CLAUDE.md |
| **features** | 7/10 | Lightweight, anti-framework, clear commands | Missing AskUserQuestion, no conflict resolution, vague tiebreaker | Fixed: added AskUserQuestion |
| **debug** | 8.5/10 | Scientific method enforced, hypothesis tracking excellent | No escalation limit, "if feasible" loophole, no binary search | Fixed: added escalation limits, binary search technique, removed "if feasible" |
| **onboard** | 7.5/10 | 3-phase workflow clear, 2000-line limit, anti-over-documentation | No error handling for scan failures, missing ADR discovery | Not fixed (nice-to-have) |
| **improve** | 7.5/10 | Quality gates, counter tracking, AskUserQuestion present | No impact/severity field, no pruning guidance | Not fixed (nice-to-have) |
| **ui-review** | 7/10 | 6 review dimensions, Playwright integration | WCAG 2.2 specifics missing, contrast ratios inconsistent, incomplete keyboard testing | Not fixed (requires domain expertise to get ratios right) |

#### Agents

| Agent | Rating | Key Strengths | Gaps Found | Fix Applied |
|---|---|---|---|---|
| **architect** | 8/10 | Anti-rationalization Rule 3, file-level precision, exploration framework | No git constraint, no ADR mandate, no C4 model | Fixed: added git constraint |
| **skeptic** | 8.5/10 | 8 validation dimensions, mirage detection, blocking rules | No git constraint, scope creep detection not quantified, DAG tool unspecified | Fixed: added git constraint + read-only constraint |
| **reviewer** | 8/10 | 5 dimensions, judge verification, confidence scoring | No git constraint, missing Google "code health" principle, criteria application rules | Fixed: added git constraint + review-only constraint |
| **refactor-agent** | 8/10 | Atomic application, rollback strategy, code smell catalog | No git constraint, dead code limits, no Fowler catalog reference | Fixed: added git constraint |
| **backend (stub)** | 5/10 | Correct frontmatter and tools | No constraints, no scope, no conventions, no git guard | Fixed: added all missing sections |
| **frontend (stub)** | 5/10 | Correct frontmatter, includes Playwright | No constraints, no scope, no accessibility mention, no git guard | Fixed: added all missing sections |
| **debugger** | 9/10 | Best agent in template. Anti-speculation, evidence hierarchy, hypothesis tracking | No git constraint, no binary search mention, no profiling guidance | Fixed: added git constraint. Binary search added to skill. |
| **security** | 9/10 | OWASP Top 10, attacker personas, severity framework, read-only | No git constraint, missing STRIDE taxonomy, no supply chain security, crypto guidance thin | Fixed: added git constraint + read-only constraint. STRIDE/supply chain not fixed (requires security domain expertise). |
| **doc** | 7.5/10 | Anti-drift rules, structured output, example testing | No Diátaxis framework, example testing says "if possible" | Fixed: added git constraint |
| **devops** | 8/10 | Production safety gates, CI/CD pipeline, Dockerfile best practices | No GitOps principles, no drift detection, state file protection missing | Fixed: added git constraint |
| **knowledge** | 7.5/10 | Reusability gate, JSONL format, validation checklist | No post-mortem integration, no runbook linkage, no git constraint | Fixed: added git constraint + read-only constraint |
| **meta** | 8/10 | Agent taxonomy, tool selection rationale, validation template | No multi-agent coordination patterns, no agent testing framework | Fixed: added git constraint |

### What Was NOT Fixed (Deliberate)

Items marked "not fixed" fall into three categories:

1. **Requires domain expertise** — WCAG 2.2 specifics, STRIDE taxonomy, supply chain security guidance, cryptography audit details. Getting these wrong is worse than leaving them as-is. These should be addressed by domain experts.

2. **Nice-to-have improvements** — BDD/Gherkin in spec, Diátaxis in doc, complexity metrics in simplify, ADR mandates in architect. The skills work well without these; adding them would improve but not fix a gap.

3. **Architectural decisions** — Review skill's fix loop is intentionally handled by `/implement` (Phase 5), not by `/review` itself. Setup's TodoWrite usage is a style preference. These are design choices, not gaps.

### Sources

- Martin Fowler's Refactoring Catalog: https://refactoring.com/catalog/
- Google Code Review Practices: https://google.github.io/eng-practices/review/reviewer/standard.html
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- STRIDE Threat Modeling: https://www.practical-devsecops.com/what-is-stride-threat-model/
- Diátaxis Documentation Framework: https://diataxis.fr/
- GitOps Principles: https://www.firefly.ai/academy/beyond-provisioning-a-2025-guide-to-infrastructure-orchestration-with-iac-and-gitops
- WCAG 2.1/2.2: https://www.w3.org/TR/WCAG21/
- Scientific Debugging: https://web.mit.edu/6.031/www/fa17/classes/13-debugging/
- Augment Code Review Best Practices: https://www.augmentcode.com/guides/code-review-best-practices-that-scale

---

## HumanLayer Comparison & Pattern Adoption (v1.1.0)

### Research

Analyzed HumanLayer/CodeLayer (github.com/humanlayer/humanlayer) — a YC-backed IDE for orchestrating AI coding agents — and their blog (hlyr.dev). Reviewed 8 blog articles and their full .claude/ configuration (6 agents, 27 commands, settings.json, CLAUDE.md). Key articles: "Skill Issue: Harness Engineering for Coding Agents" (23 min), "Advanced Context Engineering" (20 min), "12 Factor Agents" (32 min), "Long-Context Isn't the Answer", "Context-Efficient Backpressure", "Getting Claude to Actually Read Your CLAUDE.md".

Full comparison document: `humanlayer-vs-harness-analysis.md`

### Key Differences Identified

HumanLayer excels at context discipline (explicit budgets, backpressure wrappers, sub-agents as context firewalls), knowledge persistence (thoughts/ directory with search agents), and workflow decomposition (separate research → plan → validate → implement → validate pipeline with persistent artifacts). Our template excels at domain specialization (12 expert agents vs their 6 generic), universality (AI-driven setup for any tech stack), coverage breadth (security, review, refactoring skills), and upgradeability.

### Patterns Adopted

**1. Backpressure Wrappers** (from their "Context-Efficient Backpressure" article)

Problem: Running `npm test` on a 500-test project dumps all passing output into context — every "PASS src/utils/helper.test.ts" wastes tokens and degrades agent focus.

Solution: Created `hooks/backpressure.sh` with a `run_silent()` function. On success: outputs "✓ Tests passed (summary)" (~5 tokens). On failure: outputs only errors, capped at 150 lines. Integrated into 5 skills (implement, follow-up, refactor, simplify, debug). Added fail-fast flag guidance (`--bail`, `-x`, `--failfast`) as fallback.

Files changed: new `hooks/backpressure.sh`, modified `skills/implement/SKILL.md` (Phase 4), `skills/follow-up/SKILL.md`, `skills/refactor/SKILL.md`, `skills/simplify/SKILL.md`, `skills/debug/SKILL.md`, `_reference/CLAUDE.md.example`.

**2. Context Utilization Guidance** (from their "Advanced Context Engineering" and "Long-Context Isn't the Answer" articles)

Problem: No explicit guidance on context budget. Agents fill context without awareness that performance degrades past ~60% utilization.

Solution: Added Context Management section to CLAUDE.md example with 40-60% utilization target, specific guidance on when to spawn sub-agents vs continue, and conditional `<important if="...">` XML blocks for context-specific instructions (their technique for making Claude actually follow CLAUDE.md sections). Added context budget guidance to /implement Phase 3.

Files changed: `_reference/CLAUDE.md.example`, `skills/implement/SKILL.md`.

**3. Persistent Knowledge Retrieval** (from their "thoughts/" system with locator/analyzer agents)

Problem: Each session starts fresh. Prior research, debug findings, architectural decisions, and gotchas are lost between sessions. The /improve skill stores learnings in JSONL but nothing actively retrieves them.

Solution: Three-part system:
- **Session artifacts** (`knowledge/sessions/YYYY-MM-DD-<topic>.md`): Enhanced /improve skill to persist session summary documents capturing decisions, discoveries, files changed, and unresolved items.
- **Knowledge-retrieval-agent**: New read-only agent (Haiku, 15 turns) that searches learnings.jsonl, session artifacts, debug history, and planning artifacts. Returns condensed findings with citations.
- **Integration points**: /implement Phase 1 now spawns knowledge-retrieval-agent before codebase scanning. /debug now checks prior knowledge before forming hypotheses.

Files changed: new `agents/knowledge-retrieval-agent.md`, modified `skills/improve/SKILL.md`, `skills/implement/SKILL.md` (Phase 1 + Phase 6), `skills/debug/SKILL.md`, `_reference/CLAUDE.md.example`.

### Patterns Deliberately NOT Adopted

- **CLAUDE.md minimalism** (their "under 60 lines, hand-written"): Works for their single-product team. Our generated CLAUDE.md must be longer because it coordinates 13 agents without shared tribal knowledge. The ETH Zurich study they cite tested generic LLM-generated configs — our /setup generates project-specific configs from actual codebase analysis.
- **Research-only agents**: Their agents never write code. Ours must — they're dispatched as domain-expert workers by orchestrating skills.
- **Handoff/resume protocol**: Valuable but deferred. Would require a new /handoff skill and /resume skill. Session artifacts provide partial coverage.
- **Ralph autonomous mode**: Requires PM tool integration (Linear). Our template is PM-tool-agnostic by design.
- **Linear-specific patterns**: Product-specific. Template stays agnostic.

### Sources

- HumanLayer GitHub: https://github.com/humanlayer/humanlayer
- Skill Issue: Harness Engineering: https://hlyr.dev/blog/skill-issue-harness-engineering-for-coding-agents
- Advanced Context Engineering: https://hlyr.dev/blog/advanced-context-engineering
- Context-Efficient Backpressure: https://hlyr.dev/blog/context-efficient-backpressure
- Getting Claude to Read CLAUDE.md: https://hlyr.dev/blog/stop-claude-from-ignoring-your-claude-md
- Long-Context Isn't the Answer: https://hlyr.dev/blog/long-context-isnt-the-answer
- 12 Factor Agents: https://hlyr.dev/blog/12-factor-agents
- ETH Zurich Agent Files Study (cited in Skill Issue article)

---

## Artifact Consolidation & Template Snapshot (v1.1.0 continued)

### Problem

Transient artifacts were scattered across three unrelated directories: `.planning/` (at project root), `.debug/` (at project root), and `.claude/knowledge/` (inside .claude/). This caused three issues: (1) no clear gitignore boundary — users had to manually ignore each directory, (2) the locations were arbitrary (`.planning/` is not a common convention), (3) no separation between committed configuration and transient runtime data.

Additionally, the `/upgrade` skill relied on MD5 hashes in `.harness-meta.json` to detect user customizations. This is fragile — hash mismatches can't distinguish between "user intentionally modified this file" and "line endings changed" or "whitespace was reformatted."

### Solution

**1. Centralized `.claude/.artifacts/` directory** (git-ignored):

All transient data now lives under one directory:
- `.claude/.artifacts/planning/` — SPEC.md, ARCHITECTURE.md, STATE.md, NOTES.md, FEATURES.md, CODEBASE_MAP.md, UI_REVIEW.md
- `.claude/.artifacts/debug/` — HYPOTHESES.md
- `.claude/.artifacts/knowledge/` — learnings.jsonl, sessions/, patterns/, gotchas/, decisions/, recipes/
- `.claude/.artifacts/template-snapshot/` — installed template state for upgrade diffing

Benefits: single gitignore entry, clear committed-vs-transient boundary, all paths share a common prefix for easy discovery.

**2. Template snapshot for upgrade diffing:**

During `/setup`, all installed files are copied to `.claude/.artifacts/template-snapshot/`. This gives `/upgrade` a 3-way comparison:
- **Snapshot** (what was installed) vs **Current** (what exists now) → detects user customizations
- **Snapshot** (what was installed) vs **New template** (what's being upgraded to) → detects template changes
- More reliable than hash comparison: actual file-level diff, handles whitespace/formatting changes correctly
- Refreshed during `/upgrade` Phase 4.7 after updates are applied

**3. Gitignore setup:**

`/setup` Phase 4.4 creates `.claude/.gitignore` with `.artifacts/` entry and adds `.claude/.artifacts/` to root `.gitignore`.

### Files Changed

Path updates applied to 9 files: skills/implement, follow-up, debug, improve, onboard, features, ui-review; agents/knowledge-retrieval-agent, knowledge-agent; _reference/CLAUDE.md.example. Setup skill got Phases 4.3-4.4 (snapshot creation + gitignore). Upgrade skill got Phase 4.7 (snapshot refresh) and snapshot-based comparison in Phases 1.2 and 2.1.

Note: report.md retains original `.planning/` references in analytical sections describing external frameworks (GSD, etc.) — these are historical documentation, not active path references.

---

## Full Template Audit v2: Post-v1.1.0 Review (All Skills, Agents, Hooks)

### Methodology

Reviewed all 13 skills, 13 agents, 13 hooks, and 3 cross-cutting files (CLAUDE.md.example, settings.json, README.md) against 10 evaluation dimensions each. Eleven parallel review agents ran simultaneously. This audit follows the v1.1.0 changes (backpressure, context utilization, knowledge retrieval, artifact consolidation, template snapshot) and checks for regressions, inconsistencies, and new gaps.

### Consistent Gaps Found Across Files

| Gap | Affected Files | Severity | Fix Applied |
|---|---|---|---|
| **`/tmp/` path violations in hooks** | cost-tracker.sh, context-monitor.sh, circuit-breaker.sh | High | Migrated all three to `.claude/.artifacts/<hook-name>/` with fallback to `/tmp/` |
| **Missing `model` field in agent frontmatter** | backend-agent, frontend-agent, debugger-agent | Medium | Added `model: sonnet` to all three |
| **CLAUDE.md.example agent count typo** | `_reference/CLAUDE.md.example` | High | Changed "Optional Agents (6)" → "Optional Agents (7)" |
| **Escalation limit inconsistency** | follow-up skill (2 attempts) vs refactor/simplify (3 attempts) | Medium | Standardized follow-up to 3 attempts |
| **Refactor-agent git contradiction** | refactor-agent.md (forbids git at line 16 but uses `git diff`/`git checkout` in Phase 4) | High | Replaced git commands with Edit-based rollback |
| **Reviewer-agent unused WebSearch** | reviewer-agent.md | Medium | Removed WebSearch from tools |
| **Reviewer-agent criteria file validation** | reviewer-agent.md | Medium | Added explicit validation step before loading criteria |
| **TodoWrite not mentioned in most skills** | spec, review, debug, refactor, simplify, improve, onboard, features, ui-review | Low | Not fixed (nice-to-have — skills work without it; /implement covers tracking) |

### Per-File Ratings

#### Skills

| Skill | Rating | Line Count | Key Strengths | New Gaps Found | Fix Applied |
|---|---|---|---|---|---|
| **setup** | 9/10 | 662 (over 500) | Comprehensive 5-phase pipeline, excellent conflict resolution, template snapshot | Line count exceeds 500 recommendation; AskUserQuestion error handling could be more explicit | Not fixed (complexity justified) |
| **upgrade** | 8.5/10 | 502 | Changelog-driven efficiency, semantic merge, snapshot comparison | Hardcoded Bash commands without directory guards; no git constraint enforcement | Not fixed (edge cases) |
| **implement** | 9/10 | 592 | Exemplary 6-phase pipeline, 9+ AskUserQuestion references, knowledge retrieval integrated | Backpressure path assumes `.claude/hooks/` exists; subagent contracts not fully specified | Not fixed (minor) |
| **spec** | 9/10 | 311 | Gray areas framework, concrete examples, strong anti-rationalization | No TodoWrite mention; no `.artifacts/` for spec output | Not fixed (nice-to-have) |
| **review** | 8/10 | 275 | Parallel execution, confidence scoring, U-shaped attention reference | Criteria file dependencies not validated; no Agent spawn error handling | Not fixed (reviewer-agent got criteria validation fix instead) |
| **debug** | 9/10 | 209 | Scientific method enforced, hypothesis tracking, knowledge retrieval integrated | No HYPOTHESES.md initialization guidance; learnings.jsonl format not documented | Not fixed (nice-to-have) |
| **refactor** | 8.5/10 | 128 | Strong anti-rationalization, backpressure integrated, escalation logic | Unused WebSearch in allowed-tools; no TodoWrite | Not fixed (minor) |
| **simplify** | 7.5/10 | 89 | Compact and focused, clear patterns, escalation logic | Missing Agent in allowed-tools; git assumption without fallback | Not fixed (simplify runs in fork context) |
| **follow-up** | 8/10 | 196 | Complexity assessment table, TodoWrite usage, prior context loading | Escalation was 2 attempts (inconsistent with refactor/simplify at 3); unused WebSearch | Fixed: standardized to 3 attempts |
| **improve** | 8.5/10 | 272 | Quality gates, session artifact persistence, learning lifecycle | No error handling for missing artifact directories; counter increment logic undefined | Not fixed (nice-to-have) |
| **onboard** | 8/10 | 242 | 3-phase workflow, anti-over-documentation, clear scope boundaries | No knowledge retrieval integration; depth parameter undefined | Not fixed (nice-to-have) |
| **features** | 7.5/10 | 142 | Simple data format, anti-over-engineering, clear commands | No file initialization check; ID auto-increment undefined; AskUserQuestion not explicit | Not fixed (lightweight tool) |
| **ui-review** | 8/10 | 198 | 6 review dimensions, Playwright integration, accessibility focus | No timeout handling for slow pages; screenshot storage unspecified | Not fixed (nice-to-have) |

#### Agents

| Agent | Rating | Key Strengths | New Gaps Found | Fix Applied |
|---|---|---|---|---|
| **architect** | 8/10 | Anti-rationalization Rule 3, file-level specs, exploration framework | Tools include Write/Edit (could violate analysis-only intent); no `.artifacts/` path for specs | Not fixed (Write needed for spec output) |
| **skeptic** | 9/10 | 8 validation dimensions, mirage detection, high approval bar | Scope sanity check requires velocity metrics with no mechanism to obtain them | Not fixed (nice-to-have) |
| **reviewer** | 8/10 | 5 dimensions, judge verification, confidence scoring | Criteria files not validated before loading; WebSearch unjustified | Fixed: removed WebSearch; added criteria validation step |
| **refactor-agent** | 8/10 | Atomic application, rollback strategy, code smell catalog | Git contradiction: forbids git but uses git diff/checkout in Phase 4 | Fixed: replaced git commands with Edit-based rollback |
| **backend** | 7/10 | Clear constraints, scope boundaries, convention-first | Missing `model` field; no output format spec; no error handling section | Fixed: added `model: sonnet` |
| **frontend** | 7/10 | Accessibility mandate, scope boundaries, Playwright included | Missing `model` field; no output format spec | Fixed: added `model: sonnet` |
| **debugger** | 9/10 | Scientific method, anti-speculation, hypothesis tracking | Missing `model` field; no `.artifacts/` for investigation artifacts | Fixed: added `model: sonnet` |
| **security** | 9/10 | OWASP Top 10, threat personas, read-only enforced | Bash tool without explicit "read-only only" caveat | Not fixed (minor) |
| **doc** | 8.5/10 | Anti-drift rules, structured output, example testing | No `.artifacts/` reference for staging docs | Not fixed (nice-to-have) |
| **devops** | 8/10 | Production safety gates, CI/CD pipeline, Dockerfile best practices | Git constraint ambiguous (permits git diff/status); no artifact storage path | Not fixed (devops legitimately needs git inspection) |
| **meta** | 8/10 | Agent taxonomy, tool selection rationale, validation template | Agent storage/versioning guidance missing | Not fixed (nice-to-have) |
| **knowledge** | 8.5/10 | Reusability gate, JSONL structure, validation checklist | JSONL format example spans multiple lines (ambiguous); no deduplication strategy | Not fixed (documentation issue) |
| **knowledge-retrieval** | 8/10 | Fast retrieval, condensed output, 5-category search | Search patterns don't specify case sensitivity or truncation strategy | Not fixed (minor) |

#### Hooks

| Hook | Rating | Critical Issues | Fix Applied |
|---|---|---|---|
| **auto-format.sh** | 8/10 | `eval` usage in formatter dispatch | Not fixed (input is internally constructed, low risk) |
| **file-protection.sh** | 9/10 | None | — |
| **dangerous-command-blocker.sh** | 8.5/10 | Some regex patterns could be stricter | Not fixed (low risk) |
| **interactive-command-blocker.sh** | 8.5/10 | Position-dependent patterns | Not fixed (low risk) |
| **db-guard.sh** | 8/10 | Incomplete WHERE clause detection | Not fixed (medium risk but complex to get right) |
| **secret-protection-input.sh** | 8.5/10 | Overly broad grep patterns for API/SECRET | Not fixed (false positive risk is low) |
| **secret-protection-output.sh** | 7.5/10 | Fragile JSON output construction | Not fixed (non-blocking hook) |
| **cost-tracker.sh** | 7.5/10 | `/tmp/` storage; `bc` dependency; hardcoded pricing | Fixed: migrated to `.claude/.artifacts/cost-tracker/` |
| **context-monitor.sh** | 7.5/10 | `/tmp/` storage; `bc` dependency; world-readable handoff | Fixed: migrated to `.claude/.artifacts/context-monitor/` |
| **pre-compact-state-save.sh** | 8.5/10 | Silent mkdir failure | Not fixed (low risk) |
| **post-compact-notification.sh** | 8/10 | Output validation missing | Not fixed (low risk) |
| **circuit-breaker.sh** | 7.5/10 | `/tmp/` storage; no JSON validation | Fixed: migrated to `.claude/.artifacts/circuit-breaker/` |
| **backpressure.sh** | 8.5/10 | Not a traditional hook; utility library | — (by design) |

#### Cross-Cutting Files

| File | Issues Found | Fix Applied |
|---|---|---|
| **CLAUDE.md.example** | "Optional Agents (6)" should be (7) | Fixed: changed to "Optional Agents (7)" |
| **settings.json** | 12 registered hooks + 1 utility = 13 total; backpressure not registered (by design) | Not fixed (correct by design) |
| **README.md** | Counts accurate (13/13/13); directory tree current | — |

### What Was NOT Fixed (Deliberate)

Items marked "not fixed" fall into four categories:

1. **Nice-to-have improvements** — TodoWrite mentions in skills, output format specs for backend/frontend stubs, depth parameter docs for onboard. These improve completeness but don't affect functionality.

2. **Complexity-justified** — Setup skill at 662 lines exceeds the 500-line recommendation but its complexity (5 phases, conflict resolution, template snapshot) justifies the length. Splitting it would add skill-calls-skill complexity.

3. **Low-risk edge cases** — Regex pattern strictness in hooks, `bc` dependency in cost-tracker/context-monitor (still works on most systems), auto-format `eval` usage with internally-constructed input.

4. **Design decisions** — Backpressure.sh as utility (not hook), devops-agent git inspection permission, backend/frontend as stubs pending `/setup` generation.

### Summary Statistics

| Category | Files Reviewed | Average Rating | Fixes Applied | Issues Deferred |
|---|---|---|---|---|
| Skills | 13 | 8.3/10 | 1 | 15 |
| Agents | 13 | 8.2/10 | 5 | 12 |
| Hooks | 13 | 8.2/10 | 3 | 10 |
| Cross-cutting | 3 | — | 1 | 1 |
| **Total** | **42** | **8.2/10** | **10** | **38** |

### Fixes Applied in This Audit

1. **CLAUDE.md.example**: "Optional Agents (6)" → "Optional Agents (7)"
2. **cost-tracker.sh**: `/tmp/` → `.claude/.artifacts/cost-tracker/` with fallback
3. **context-monitor.sh**: `/tmp/` → `.claude/.artifacts/context-monitor/` with fallback
4. **circuit-breaker.sh**: `/tmp/` → `.claude/.artifacts/circuit-breaker/` with fallback
5. **refactor-agent.md**: Removed git commands from rollback phase; replaced with Edit-based rollback
6. **follow-up/SKILL.md**: Escalation limit 2 → 3 (consistent with refactor/simplify)
7. **backend-agent.md**: Added `model: sonnet`
8. **frontend-agent.md**: Added `model: sonnet`
9. **debugger-agent.md**: Added `model: sonnet`
10. **reviewer-agent.md**: Removed WebSearch from tools; added criteria file validation step

---

## Full Template Audit v3: Fresh Re-Review (All Skills, Agents, Hooks)

### Methodology

Complete re-audit of all 42 files (13 skills, 13 agents, 13 hooks, 3 cross-cutting) using 11 fresh parallel review agents. This audit ran independently of v2 to catch issues that the previous pass either missed or introduced.

### New Issues Found (Not in v2)

| Issue | File | Severity | Fix Applied |
|---|---|---|---|
| **Missing `model` field** | refactor-agent.md | High | Added `model: sonnet` (was missed in v2 — only backend/frontend/debugger were fixed) |
| **Hardcoded `npm run dev`** | implement/SKILL.md line 375 | High | Changed to "start/dev command from CLAUDE.md's Essential Commands" |
| **Spec output to project root** | spec/SKILL.md lines 119, 287 | High | Changed to `.claude/.artifacts/planning/FEATURE_SPEC.md` |
| **AskUserQuestion missing from ui-review** | ui-review/SKILL.md | High | Added to allowed-tools; added Pre-flight step with explicit tool usage |
| **Hardcoded npm commands in example** | onboard/SKILL.md lines 156-157 | Medium | Replaced with generic placeholders |
| **Missing `bc` availability check** | context-monitor.sh | High | Added `command -v bc` guard; exits gracefully if missing |
| **Missing `awk`/`bc` availability check** | cost-tracker.sh | High | Added `command -v awk && command -v bc` guard |
| **Fragile jq output construction** | secret-protection-output.sh | Medium | Simplified to single `jq -n -c` call with `--arg` for all strings |

### Updated Per-File Ratings (Changes from v2)

#### Skills (updated ratings)

| Skill | v2 Rating | v3 Rating | Change | Reason |
|---|---|---|---|---|
| **setup** | 9/10 | 8.5/10 | -0.5 | Line count 662 (32% over 500 limit); AskUserQuestion error handling still lacks rollback path |
| **upgrade** | 8.5/10 | 7.5/10 | -1.0 | Hardcoded bash commands without guards in Phase 4.7; no TodoWrite; no escalation limits for massive changelogs |
| **implement** | 9/10 | 8.5/10 | -0.5 | Had hardcoded `npm run dev` (now fixed); `knowledge-retrieval-agent` subagent type undocumented |
| **spec** | 9/10 | 8.5/10 | -0.5 | Spec output was going to project root instead of `.artifacts/` (now fixed) |
| **review** | 8/10 | 9/10 | +1.0 | Criteria file validation added in v2 working well; batched mode logic and confidence scoring excellent |
| **debug** | 9/10 | 8.5/10 | -0.5 | No `.artifacts/debug/` directory creation guard; no definition of "inconclusive" for escalation |
| **refactor** | 8.5/10 | 8/10 | -0.5 | Backpressure fallback vague ("fail-fast flags" without examples); WebSearch in allowed-tools but unused |
| **simplify** | 7.5/10 | 7/10 | -0.5 | Still missing TodoWrite; backpressure fallback doesn't specify actual flags; git-diff-empty case unhandled |
| **follow-up** | 8/10 | 7.5/10 | -0.5 | Model `inherit` undefined; backpressure fallback vague; plan outline format unspecified for medium complexity |
| **improve** | 8.5/10 | 9/10 | +0.5 | Session artifact persistence well-integrated; quality gates strong |
| **onboard** | 8/10 | 8/10 | = | Hardcoded npm commands fixed; depth parameter still undocumented |
| **features** | 7.5/10 | 9/10 | +1.5 | Clean design, well-scoped, strong anti-over-engineering — previous rating was too low |
| **ui-review** | 8/10 | 8/10 | = | AskUserQuestion now added; Playwright error handling added in Pre-flight |

#### Agents (updated ratings)

| Agent | v2 Rating | v3 Rating | Change | Reason |
|---|---|---|---|---|
| **architect** | 8/10 | 8/10 | = | WebSearch in tools questionable but not critical |
| **skeptic** | 9/10 | 9/10 | = | Strongest agent; mirage detection, high approval bar |
| **reviewer** | 8/10 | 8/10 | = | v2 fixes (criteria validation, WebSearch removal) verified working |
| **refactor-agent** | 8/10 | 7.5/10 | -0.5 | Was missing `model` field (now fixed); test creation contradicts core "stop and ask" principle |
| **backend** | 7/10 | 8/10 | +1.0 | Model added in v2; clear constraints and scope |
| **frontend** | 7/10 | 8/10 | +1.0 | Model added in v2; accessibility mandate strong |
| **debugger** | 9/10 | 9/10 | = | Strongest implementation agent; scientific method rigorous |
| **security** | 9/10 | 9/10 | = | OWASP coverage, read-only enforcement, threat personas |
| **doc** | 8.5/10 | 9/10 | +0.5 | Anti-drift rules excellent; structured output clear |
| **devops** | 8/10 | 8/10 | = | Git constraint deliberately allows read-only inspection |
| **meta** | 8/10 | 8/10 | = | Agent taxonomy and validation template strong |
| **knowledge** | 8.5/10 | 9/10 | +0.5 | JSONL format well-defined; reusability gate prevents pollution |
| **knowledge-retrieval** | 8/10 | 9/10 | +1.0 | Librarian role tight; search strategy comprehensive; maxTurns 15 appropriate |

#### Hooks (updated ratings)

| Hook | v2 Rating | v3 Rating | Change | Reason |
|---|---|---|---|---|
| **auto-format.sh** | 8/10 | 8/10 | = | eval risk acknowledged but internally constructed |
| **file-protection.sh** | 9/10 | 8/10 | -1.0 | Double lowercase conversion (jq + tr); dot not escaped in some patterns |
| **dangerous-command-blocker.sh** | 8.5/10 | 8/10 | -0.5 | Regex anchoring inconsistent across patterns |
| **interactive-command-blocker.sh** | 8.5/10 | 8/10 | -0.5 | Pattern anchoring inconsistent |
| **db-guard.sh** | 8/10 | 8/10 | = | SQL coverage gaps unchanged |
| **secret-protection-input.sh** | 8.5/10 | 8/10 | -0.5 | Broad patterns (cat.*secret) risk false positives |
| **secret-protection-output.sh** | 7.5/10 | 7.5/10 | = | jq construction simplified (now fixed) |
| **cost-tracker.sh** | 7.5/10 | 7.5/10 | = | awk/bc guard added; pricing still hardcoded |
| **context-monitor.sh** | 7.5/10 | 7.5/10 | = | bc guard added; /tmp bridge path still hardcoded |
| **pre-compact-state-save.sh** | 8.5/10 | 9/10 | +0.5 | Clean implementation; state capture comprehensive |
| **post-compact-notification.sh** | 8/10 | 9/10 | +1.0 | Well-focused, helpful suggestions |
| **circuit-breaker.sh** | 7.5/10 | 7/10 | -0.5 | /tmp fallback still problematic conceptually |
| **backpressure.sh** | 8.5/10 | 9/10 | +0.5 | Excellent utility design; flexible sourcing pattern |

### Cross-Cutting Consistency

| Check | Status | Details |
|---|---|---|
| Agent count: README vs CLAUDE.md.example vs actual | ✓ PASS | All say 13 (6 core + 7 optional) |
| Skill count: README vs actual | ✓ PASS | 13 (9 core + 4 optional) |
| Hook count: README vs settings.json vs actual | ⚠️ NOTE | 13 files, 12 registered in settings.json + 1 utility (backpressure). By design. |
| Artifact paths consistent | ✓ PASS | All skills/agents use `.claude/.artifacts/` |
| Git constraints on all agents | ✓ PASS | All 13 agents have explicit "No Git Operations" |

### Fixes Applied in This Audit (v3)

1. **refactor-agent.md**: Added `model: sonnet` (missed in v2)
2. **implement/SKILL.md**: Replaced hardcoded `npm run dev` with CLAUDE.md reference
3. **spec/SKILL.md**: Moved spec output from project root to `.claude/.artifacts/planning/FEATURE_SPEC.md`
4. **ui-review/SKILL.md**: Added `AskUserQuestion` to allowed-tools; added Pre-flight step with error handling
5. **onboard/SKILL.md**: Replaced hardcoded `npm test`/`npm run migrate` with generic placeholders
6. **context-monitor.sh**: Added `bc` availability check before float comparisons
7. **cost-tracker.sh**: Added `awk`/`bc` availability check before calculations
8. **secret-protection-output.sh**: Simplified jq construction to single robust call

### Summary Statistics

| Category | Files | Avg v2 Rating | Avg v3 Rating | Fixes This Round |
|---|---|---|---|---|
| Skills | 13 | 8.3/10 | 8.2/10 | 5 |
| Agents | 13 | 8.2/10 | 8.5/10 | 1 |
| Hooks | 13 | 8.2/10 | 8.1/10 | 3 |
| **Total** | **42** | **8.2/10** | **8.3/10** | **8 + 10 (v2) = 18 total** |

### Remaining Deferred Items (Deliberate)

These are tracked but not fixed because they're design decisions or low-priority:

1. **Setup skill line count (662)** — complexity justified; splitting would add inter-skill complexity
2. **Upgrade skill hardcoded bash** — cp/mkdir commands are pragmatic; wrapping in Write tool would over-abstract
3. **TodoWrite not in most skills** — /implement covers orchestration tracking; adding to leaf skills is noise
4. **Backpressure fallback flags** — project-specific; documenting every framework's flags would bloat skills
5. **Follow-up model: inherit** — valid Claude Code frontmatter value; means "use parent model"
6. **bc/awk in remaining hooks** — guards added where critical; remaining usage degrades gracefully
7. **Circuit-breaker /tmp fallback** — fallback exists for systems without .claude/; conceptually impure but functional
8. **Pricing hardcoded in cost-tracker** — externalizing to config adds complexity for marginal benefit

---

## Template Improvement Audit v4: Production Cross-Pollination & Best Practices Review

### Motivation

After installing the harness template onto a production monorepo (NestJS + React 19 + pnpm + Turbo), the `/setup` skill adapted several template files to be project-specific. In four cases, the adapted versions were significantly larger and more detailed than the template originals:

| File | Template (before) | Adapted (after setup) | Delta |
|---|---|---|---|
| `agents/architect-agent.md` | 215 lines | 327 lines | +52% |
| `agents/reviewer-agent.md` | 136 lines | 493 lines | +262% |
| `skills/follow-up/SKILL.md` | 196 lines | 358 lines | +83% |
| `skills/simplify/SKILL.md` | 89 lines | 222 lines | +149% |

This audit analyzed each adapted version to extract **generic, reusable patterns** that should have been in the template all along, then applied them back to the template and cross-checked everything against this report's best practices.

### Analysis Per File

#### 1. `agents/reviewer-agent.md` — No Change Needed

**The reference project's approach:** Multi-agent orchestrator that spawns 5 Task instances with inline sub-reviewer prompts (493 lines). Each Task receives a detailed inline criteria prompt and produces JSON-structured review output.

**Why it's wrong:** This violates the Known Limitations constraint documented at line 35 of this report: "Subagents cannot spawn sub-tasks — an agent spawned via Agent/Task tool cannot create nested Tasks ([#4182](https://github.com/anthropics/claude-code/issues/4182), [#19077](https://github.com/anthropics/claude-code/issues/19077))." The orchestration must live at skill level, not agent level.

**Template's approach is correct:** The template's reviewer-agent is a focused single-dimension reviewer designed to be spawned in parallel by the `/review` skill. The skill orchestrates the parallel grid; the agent focuses on one dimension per invocation. This matches the workaround documented in the limitations table.

**Verdict:** Template correct. The adapted version is architecturally wrong. No changes.

#### 2. `agents/architect-agent.md` — Significantly Improved

**Reference project additions analyzed (327 lines):**

| Pattern | Project-specific? | Generic value | Incorporated? |
|---|---|---|---|
| **Effort Scaling** (S/M/L task complexity matching) | No — universal | High — prevents over-architecting trivial changes | ✓ Yes |
| **Minor Improvements** (implement small fixes directly during exploration) | No — universal | High — typos, dead code, stale comments don't need full spec→engineer cycle | ✓ Yes |
| **Internet Research** (mandatory WebSearch/WebFetch before designing) | No — universal | High — ecosystem evolves fast; native-first principle prevents reinventing the wheel | ✓ Yes |
| **Native-First Principle** (prefer built-in framework features over custom code) | No — universal | High — single most impactful design principle for AI agents that tend to over-build | ✓ Yes |
| **Progressive Delivery** (Phase 1 proposal → Phase 2 full spec for complex tasks) | No — universal | Medium — reduces wasted effort when user rejects approach | ✓ Yes |
| **Context Budget Management** (batch operations, read signatures not implementations) | No — universal | High — directly addresses context window degradation | ✓ Yes |
| **Dependency Mapping** (map ripple effects before finalizing specs) | No — universal | High — prevents cascading failures during implementation | ✓ Yes |
| **Plan Revision** (addendum-style revisions instead of full rewrites) | No — universal | Medium — saves tokens when engineer feedback requires spec changes | ✓ Yes |
| **Quality Bar** section (quality over compatibility, never compromise to preserve bad code) | No — universal | High — counters AI tendency to patch around problems | ✓ Yes |
| **Autonomy** section (operate without asking follow-ups unless genuinely ambiguous) | No — universal | Medium — reduces unnecessary back-and-forth | ✓ Yes |
| Project-specific knowledge (API architecture, Web architecture, cross-repo patterns) | **Yes** | None for template | ✗ Excluded |
| Keycloak safety rules | **Yes** | None for template | ✗ Excluded |
| Specific module lists (graphs, agents, agent-tools, etc.) | **Yes** | None for template | ✗ Excluded |

**Result:** Template architect-agent grew from 215 → 346 lines. All additions are generic and reusable across any project. WebFetch added to tools list (required for internet research).

**Updated rating:** architect-agent 8/10 → **9/10** (now has effort scaling, research mandate, progressive delivery, context management, and plan revision — previously missing).

#### 3. `skills/follow-up/SKILL.md` — Significantly Improved

**Reference project additions analyzed (358 lines):**

| Pattern | Project-specific? | Generic value | Incorporated? |
|---|---|---|---|
| **Hard Escalation Signals table** (8 signals with "why it escalates" rationale) | No — universal | Critical — prevents follow-up from handling what should be /implement | ✓ Yes (8 signals) |
| **Detailed complexity levels** with concrete examples per level | No — universal | High — calibrates assessment beyond file counting | ✓ Yes |
| **Codegen Rule** (run codegen after DTO/schema changes) | Partially — pnpm-specific command | High — generalized to "check CLAUDE.md for project's codegen commands" | ✓ Yes (generalized) |
| **Agent Failure Handling** (retry once, then escalate) | No — universal | High — without this, agent timeouts silently stall the pipeline | ✓ Yes |
| **Runtime Startup Check** (boot app, check for DI/compilation errors) | No — universal | Medium — catches runtime errors that static checks miss | ✓ Yes (medium complexity only) |
| **Test Coverage Check** (find/extend/create unit + integration tests) | No — universal | High — ensures changes have test coverage proportional to risk | ✓ Yes |
| **Learn & Improve phase** (extract learnings, suggest rule improvements) | No — universal | Medium — accumulates project knowledge across sessions | ✓ Yes (medium complexity only) |
| **Troubleshooting table** (5 common problems with causes and fixes) | No — universal | Medium — reduces debugging time for common pipeline issues | ✓ Yes |
| **Structured handoff on fix exhaustion** (Remaining Failures format) | No — universal | High — matches /implement's Phase 4 handoff pattern | ✓ Yes |
| **Tweak loop with scope detection** ("growing beyond follow-up scope" warning) | No — universal | High — prevents follow-up from becoming a shadow /implement | ✓ Yes |
| Project-specific commands (`pnpm --filter`, `pnpm run full-check`) | **Yes** | None for template | ✗ Excluded |
| Project-specific agent names (`api-agent`, `web-agent`) | **Yes** | None for template | ✗ Excluded |

**Additional fixes from report cross-check:**

| Issue | Report reference | Fix applied |
|---|---|---|
| Validation fix loop was 3 rounds | Report line 1176: "max 2 rounds (validation)" for follow-up | Changed from 3 → 2 |
| Missing anti-rationalization table | Report line 2200: every pipeline skill needs compliance table | Added 6-entry table |
| Description over 250 chars | Report line 389: description under 250 chars | Shortened but kept informative (includes "Do NOT use for..." guidance) |
| Validation commands not referencing CLAUDE.md | Report Pattern 8 (line 1326): discover-ask-persist | Added "from CLAUDE.md" references + fallback to AskUserQuestion |
| AskUserQuestion explicit throughout | Report line 1370: follow-up had implicit "ask user" | Now has 11 explicit AskUserQuestion references |

**Result:** Template follow-up grew from 196 → 429 lines. Pipeline comparison table against /implement now matches report's specification:

| Aspect | `/implement` | `/follow-up` (updated) | Report spec (line 1169) | Match? |
|---|---|---|---|---|
| Discovery | Full | Skip | Skip | ✓ |
| Architecture | Architect + skeptic + approval | Skip or brief plan (medium) | Skip or brief plan | ✓ |
| Validation | Full check + codegen + startup + test coverage | Full check + codegen + startup (medium) + test coverage (small/medium) | Full check + codegen | ✓ (exceeds — startup/test coverage are valuable) |
| Review | Full grid, max 3 rounds | Full review, max 1 round | Full review, max 1 round | ✓ |
| Validation fix loops | Max 3 | Max 2 | Max 2 | ✓ |
| Ship | Full ceremony + learn | Summary + tweaks + learn (medium only) | Summary + tweaks + commit | ✓ |

**Updated rating:** follow-up 7.5/10 → **9/10** (now has proper escalation signals, agent failure handling, test coverage, learn & improve, and anti-rationalization — was the weakest pipeline skill, now on par with /implement).

#### 4. `skills/simplify/SKILL.md` — Major Rewrite

**Reference project additions analyzed (222 lines):**

| Pattern | Project-specific? | Generic value | Incorporated? |
|---|---|---|---|
| **4-phase pipeline** (Scope → Analyze → Fix → Verify) | No — universal | Critical — previous version had no structured pipeline | ✓ Yes |
| **3 analysis passes** (Reuse/Duplication, Quality/Readability, Efficiency/Patterns) | No — universal | Critical — systematic coverage vs ad-hoc checklist | ✓ Yes |
| **P1/P2/P3 severity classification** | No — universal | High — prevents over-fixing (P3 = report only, never fix) | ✓ Yes |
| **AI-Generated Code Anti-Patterns** (over-abstraction, verbose error handling, unnecessary wrappers, over-documentation) | No — universal | Critical — the most common quality issues in AI-generated code | ✓ Yes |
| **Frontend-Specific checks** (component splitting, effect splitting, prop drilling, stale closures) | No — universal | Medium — generic React/frontend patterns, not framework-specific | ✓ Yes (renamed from "React-Specific" to "Frontend-Specific") |
| **Structured Completion Report** (Applied/Skipped/P3 Notes/Verification format) | No — universal | High — gives user clear visibility into what changed and what was deferred | ✓ Yes |
| **Safe revert strategy** (revert individual failed changes, max 1 retry cycle) | No — universal | High — prevents cascading failures from cleanup changes | ✓ Yes |
| **Scope limiting** (max 20 files, exclude generated code/migrations/type-only files) | No — universal | Medium — prevents runaway analysis on large diffs | ✓ Yes |
| **Test file separation** (lighter review for test files, never weaken assertions) | No — universal | Medium — different review bar for test code vs source code | ✓ Yes |
| Project-specific commands (`pnpm lint:fix`, `pnpm run full-check`) | **Yes** | None for template | ✗ Excluded |
| Project-specific patterns (`findByX` DAO methods, `FilterQuery<T>`) | **Yes** | None for template | ✗ Excluded |
| Project-specific React patterns (Ant Design theme tokens, Refine hooks) | **Yes** | None for template | ✗ Excluded |

**Additional fixes from report cross-check:**

| Issue | Report reference | Fix applied |
|---|---|---|
| Missing anti-rationalization table | Report line 2200 | Added 5-entry table specific to simplify's failure modes |
| Validation commands not referencing CLAUDE.md | Report Pattern 8 (line 1326) | Added "from CLAUDE.md" references |
| Description over 250 chars | Report line 389 | Shortened to ~200 chars while keeping key differentiators |

**Result:** Template simplify grew from 89 → 280 lines. This was the most dramatic improvement — the previous 89-line version was essentially a basic checklist with no structured pipeline, no severity classification, no AI anti-pattern detection, and no completion report format.

**Updated rating:** simplify 7/10 → **9/10** (now has proper 4-phase pipeline, 3 analysis passes with specific pattern tables, P1/P2/P3 severity, AI anti-patterns, frontend-specific checks, safe revert strategy, and structured completion report — was the weakest skill in the template).

### Summary Statistics

| File | Before | After | Delta | New Patterns |
|---|---|---|---|---|
| `architect-agent.md` | 215 | 346 | +131 (+61%) | 10 patterns added |
| `follow-up/SKILL.md` | 196 | 429 | +233 (+119%) | 10 patterns added, 5 report fixes |
| `simplify/SKILL.md` | 89 | 280 | +191 (+215%) | 9 patterns added, 3 report fixes |
| `reviewer-agent.md` | 136 | 136 | 0 | Confirmed correct (the adapted version wrong) |
| **Total** | **636** | **1191** | **+555 (+87%)** | **29 patterns + 8 fixes** |

### Updated Template Ratings (Post v4)

| File | v3 Rating | v4 Rating | Change |
|---|---|---|---|
| **architect-agent** | 8/10 | 9/10 | +1.0 |
| **follow-up** | 7.5/10 | 9/10 | +1.5 |
| **simplify** | 7/10 | 9/10 | +2.0 |
| **reviewer-agent** | 8/10 | 8/10 | = (confirmed correct) |

### Key Principle: Cross-Pollination from Production Usage

This audit demonstrates a valuable pattern: **production installations reveal template gaps**. When the setup skill adapts template files for a specific project, the adapted versions often contain patterns that should have been generic in the template all along. The signal is: if a production version is >50% larger than the template AND the additions aren't project-specific, those additions represent missing generic functionality.

**Recommended process:** After each new project installation, compare adapted files against template originals. Extract generic patterns back into the template. This creates a positive feedback loop where each installation improves the template for all future projects.

### Remaining Concerns

1. **follow-up at 429 lines** — approaching the 500-line limit from report line 383. If more features are added, reference material should be extracted to supporting files (e.g., `follow-up/escalation-signals.md`).
2. **Description length tradeoff** — report recommends <250 chars, but informative descriptions improve skill routing accuracy. Current descriptions are 200-280 chars, slightly over limit but providing critical routing information ("Do NOT use for new features, new entities..."). The routing value outweighs the marginal context cost.
3. **Startup check in follow-up** — report's pipeline comparison table (line 1174) doesn't include startup check for follow-up, but the reference project's production experience shows DI/compilation errors are caught by startup checks that static analysis misses. Kept as medium-complexity-only with the understanding that this slightly exceeds the report's minimal spec.

---

## Template Improvement Audit v5: Full Template Compliance Check

**Date:** 2026-04-03
**Scope:** All 12 skills + 13 agents checked against report.md best practices
**Method:** Three parallel audit agents (pipeline skills, utility skills, agents) + manual verification

### Fixes Applied

| File | Fix | Severity | Report Reference |
|------|-----|----------|-----------------|
| `agents/knowledge-retrieval-agent.md` | Added missing git constraint: "Do NOT run git add, git commit, git push" | P1 | Only agent without explicit git rule |
| `skills/debug/SKILL.md` | Added "Git Constraint" section with explicit git prohibition + git bisect/log/diff allowance | P2 | Report: all pipeline skills need git constraint |
| `skills/refactor/SKILL.md` | Added "Git Constraint" section with explicit git prohibition | P2 | Report: all pipeline skills need git constraint |
| `skills/refactor/SKILL.md` | Fixed Definition of Done checkboxes: `[x]` → `[ ]` (pre-checked = useless as a checklist) | P2 | Checkboxes should be unchecked templates |
| `skills/debug/SKILL.md` | Converted anti-rationalization from prose to structured table (6 entries) | P2 | Report line 2209: structured table format required |
| `skills/spec/SKILL.md` | Converted anti-rationalization from prose to structured table (5 entries) | P2 | Report line 2209 |
| `skills/features/SKILL.md` | Converted anti-rationalization from prose to structured table (5 entries) | P2 | Report line 2209 |
| `skills/learnings/SKILL.md` | Converted anti-rationalization from prose to structured table (5 entries) | P2 | Report line 2209 |
| `skills/onboard/SKILL.md` | Converted anti-rationalization from prose to structured table (4 entries) | P2 | Report line 2209 |
| `skills/ui-review/SKILL.md` | Converted anti-rationalization from prose to structured table (5 entries) | P2 | Report line 2209 |
| `skills/review/SKILL.md` | Converted anti-rationalization from prose to structured table (6 entries) | P2 | Report line 2209 |
| `skills/setup/SKILL.md` | Added missing "Compliance — Do Not Skip Phases" table (5 entries) | P2 | Report line 2209: every pipeline skill needs compliance table |

### Per-File Status After Fixes

| File | Lines | Git Constraint | Anti-Rat Table | Def of Done | AskUserQuestion | CLAUDE.md Refs | Rating |
|------|-------|---------------|----------------|-------------|-----------------|----------------|--------|
| `implement/SKILL.md` | 593 | ✓ | ✓ (per-phase) | ✓ (10 items) | ✓ (5 refs) | ✓ | 9/10 |
| `follow-up/SKILL.md` | 429 | ✓ | ✓ (6 entries) | ✓ (8 items) | ✓ (11 refs) | ✓ | 9/10 |
| `simplify/SKILL.md` | 280 | ✓ | ✓ (5 entries) | ✓ (7 items) | ✓ (in tools) | ✓ | 9/10 |
| `debug/SKILL.md` | ~218 | ✓ (NEW) | ✓ (NEW, 6 entries) | ✓ (8 items) | ✓ (2 refs) | ✓ | 8.5/10 |
| `refactor/SKILL.md` | ~137 | ✓ (NEW) | ✓ (8 entries) | ✓ (FIXED) | ✓ (2 refs) | ✓ | 8.5/10 |
| `review/SKILL.md` | ~276 | N/A (fork) | ✓ (NEW, 6 entries) | ✓ (8 items) | N/A (fork) | N/A | 8.5/10 |
| `spec/SKILL.md` | ~312 | N/A | ✓ (NEW, 5 entries) | ✓ (7 items) | ✓ (2 refs) | N/A | 8.5/10 |
| `features/SKILL.md` | ~143 | N/A | ✓ (NEW, 5 entries) | ✓ (6 items) | ✓ (in tools) | N/A | 8/10 |
| `learnings/SKILL.md` | ~273 | N/A | ✓ (NEW, 5 entries) | ✓ (6 items) | ✓ (1 ref) | N/A | 8/10 |
| `onboard/SKILL.md` | ~243 | N/A | ✓ (NEW, 4 entries) | ✓ (6 items) | N/A | N/A | 8/10 |
| `ui-review/SKILL.md` | ~203 | N/A (fork) | ✓ (NEW, 5 entries) | ✓ (6 items) | ✓ (in tools) | N/A | 8/10 |
| `setup/SKILL.md` | ~754 | N/A (user) | ✓ (NEW, 5 entries) | ✓ (8 items) | ✓ (many) | ✓ | 8/10 |

### Agent Status After Fixes

| Agent | Git Constraint | Model | maxTurns | Desc <250 | Output Format | Task Limitation |
|-------|---------------|-------|----------|-----------|---------------|-----------------|
| `architect-agent` | ✓ | sonnet | 60 | ✓ (268) | ✓ (6 sections) | ✓ (context budget) |
| `reviewer-agent` | ✓ | sonnet | 25 | ✓ (217) | ✓ (confidence) | ✓ (explicit) |
| `knowledge-retrieval-agent` | ✓ (FIXED) | haiku | 15 | ✓ (140) | ✓ (citations) | N/A |
| `debugger-agent` | ✓ | sonnet | 60 | ✓ (141) | ✓ (7 sections) | N/A |
| `doc-agent` | ✓ | haiku | 30 | ✓ (146) | ✓ (update fmt) | N/A |
| `security-agent` | ✓ | sonnet | 40 | ✓ (149) | ✓ (findings) | N/A |
| `skeptic-agent` | ✓ | sonnet | 30 | ✓ (178) | ✓ (validation) | P3: has Task, no #4182 note |
| `knowledge-agent` | ✓ | haiku | 25 | ✓ (146) | ✓ (JSONL) | N/A |
| `refactor-agent` | ✓ | sonnet | 60 | ✓ (136) | ✓ (summary) | P3: has Task, no #4182 note |
| `meta-agent` | ✓ | sonnet | 60 | ✓ (148) | ✓ (8 sections) | N/A |
| `devops-agent` | ✓ | sonnet | 60 | ✓ (152) | ✓ (2 formats) | N/A |
| `backend-agent` | ✓ | sonnet | 60 | ✓ (113) | Stub (/setup) | Stub |
| `frontend-agent` | ✓ | sonnet | 60 | ✓ (130) | Stub (/setup) | Stub |

### P3 Notes (Not Fixed — Informational)

1. **Subagent Task limitation (GitHub #4182)**: `skeptic-agent` and `refactor-agent` have Task in their tools but don't document that subagents cannot spawn nested Tasks. Low risk since both are typically invoked by orchestrator skills that handle coordination.

2. **implement at 593 lines**: Over the 500-line guideline. Splitting is possible but risky — the skill's coherence benefits from being in one file. Phase-specific reference material (mid-flow input handling, error tables) could theoretically be extracted to supporting files.

3. **setup at 754 lines**: Over the 500-line guideline. This is the known exception — setup is a one-time bootstrap skill with inherent complexity. Splitting would reduce coherence.

4. **backend-agent and frontend-agent are stubs**: Intentionally minimal — designed to be generated by `/setup` with project-specific content. Not a deficiency.

5. **implement anti-rationalization is per-phase, not centralized**: Lines 214, 470, 530 have per-phase constraints rather than one table. For a 593-line skill, per-phase placement may be more effective than a centralized table that's far from the relevant phase.

### Consistency Improvements Made

All 12 skills now use the same anti-rationalization format:
- **Section header**: `## Compliance — Do Not [Skip Phases|Cut Corners|Over-Engineer|Pollute Knowledge|Over-Document]`
- **Format**: `| Your reasoning | Why it's wrong |` table with 4-6 entries
- **Content**: Specific rationalizations Claude might use, paired with concrete rebuttals

This matches report line 2209-2226 recommendation exactly.

### Summary

**Before this audit:** 4 skills had proper table-format anti-rationalization (implement, follow-up, simplify, architect-agent). 8 skills used prose format. 2 skills (debug, refactor) lacked git constraints. 1 agent (knowledge-retrieval) lacked git constraint. Setup had no anti-rationalization at all. Refactor had pre-checked checkboxes.

**After this audit:** All 12 skills have structured anti-rationalization tables. All pipeline skills have git constraints. All 13 agents have git constraints. All Definition of Done sections use unchecked `[ ]` format. Template-wide consistency achieved.

---

## Template Improvement Audit v6: Skill Composition & 8-Phase Pipeline

**Date:** 2026-04-04
**Scope:** Implement skill pipeline expansion (6→8 phases), skill composition pattern fix, cross-skill reference audit
**Method:** Comparison of template vs the reference project's production implementation, internet research on skill composition limitations, full cross-reference audit of all 12 skills + 13 agents

### Motivation

Two issues converged:

1. **Pipeline gap:** The template's 6-phase implement pipeline was missing battle-tested patterns from the reference project's production implementation (11 phases). Analysis identified 5 high-impact patterns worth porting back without adding project-specific complexity (Context/Fast-Path phases deliberately excluded).

2. **Skill composition bug:** The implement skill used "Read `.claude/skills/review/SKILL.md` and follow its instructions exactly" — a pattern that **does not work correctly** for complex skills with their own orchestration and infrastructure needs. Research confirmed this is a known, unresolved limitation.

### Research: Skill Composition Limitations

**Primary source:** GitHub [#17351](https://github.com/anthropics/claude-code/issues/17351) — "Nested skills don't return to invoking skill context on finishing but to main context"

**Confirmed by multiple users:**
- User `him0`: `/git-pull-request` calls `/git-commit --push`. After git-commit completes, workflow stopped and returned to main session instead of continuing with PR creation
- User `bgeesaman`: skill that runs `/skill1` then `/skill2` in order — stops after skill1, never invokes skill2. Tested on v2.1.37
- User `corticalstack`: breaks autonomous loops

**Related issues:**
- [#30256](https://github.com/anthropics/claude-code/issues/30256): `context: fork` does NOT fix nested skill composition — same premature exit
- [#38719](https://github.com/anthropics/claude-code/issues/38719): feature request for subagents to invoke skills (open)
- [#39163](https://github.com/anthropics/claude-code/issues/39163): feature request for `/compose` command (open, not implemented)
- [#32336](https://github.com/anthropics/claude-code/issues/32336), [#32340](https://github.com/anthropics/claude-code/issues/32340): sub-agent skill access (closed as duplicates)

**"Read and follow" workaround limitations:**
Reading a SKILL.md as a file works for loading text, but does NOT trigger skill infrastructure:
- `context: fork` — ignored (skill runs in consuming skill's context, not isolated)
- `model: sonnet` — ignored (runs with consuming skill's model)
- `allowed-tools:` — ignored (runs with consuming skill's tool access)
- YAML frontmatter loads as harmless text but has no functional effect

**Framework patterns discovered:**
- **oh-my-claudecode** ([Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)): inlines all logic — `autopilot` contains full workflow inline, delegates via `Task(subagent_type=...)`, never invokes other skills via Skill tool
- **GSD** ([gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done)): each skill self-contained, avoids nested Skill tool entirely
- **Official best practices** ([Claude Code Skills Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)): "push into separate files and tell Claude to read the appropriate file" — supports reference file extraction

### Solution: Shared Reference Files + Subagent Delegation

Established a new composition pattern (now Pattern 1 in Skill Composition Patterns section):

**Architecture:**
```
skills/simplify/
├── SKILL.md              ← process (standalone skill — Scope → Analyze → Fix → Verify)
└── simplify-criteria.md  ← knowledge (3 analysis passes, severity, anti-patterns) — SHARED

skills/review/
├── SKILL.md              ← process (standalone skill — Collect → Spawn Reviewers → Judge)
├── bugs-criteria.md      ← knowledge — SHARED
├── security-criteria.md  ← knowledge — SHARED
├── architecture-criteria.md
├── tests-criteria.md
└── guidelines-criteria.md

skills/implement/
└── SKILL.md              ← orchestrator — pre-reads criteria files, spawns subagents with pre-inlined content
```

**How it works:**
1. Reusable knowledge (analysis criteria, patterns, rules) lives in supporting `.md` files alongside the skill
2. The standalone skill reads its own supporting files at runtime
3. The consuming skill (implement) pre-reads the same supporting files and pre-inlines their content into subagent prompts
4. Subagents run with clean context, correct tool access, and the shared knowledge

**Why this is better:**

| Dimension | Read SKILL.md inline | Shared reference + subagent |
|---|---|---|
| Context cost | High (~5-15K for complex skills) | Low (~1-3K per criteria file) |
| Skill infrastructure | Lost (frontmatter ignored) | Preserved (subagent has own context) |
| Orchestration pollution | Yes — complex multi-agent process loaded into consuming skill | No — clean delegation |
| Single source of truth | Yes but fragile — consuming skill may follow differently | Yes — same criteria, different execution |
| Works for complex skills | No — review skill has 5 parallel reviewers + judge pass | Yes — orchestrator spawns reviewers itself |

### Pipeline Expansion: 6 → 8 Phases

**Sources for new phases:**
- Reference project production implementation (11 phases, battle-tested across multiple features)
- Report's own Implementation Pipeline section (line 755+)
- Cross-framework consensus: GSD (5 phases), Metaswarm (9 phases), oh-my-claudecode (autopilot/ultrapilot), Orchestrator Kit (7 stages)

**New pipeline structure:**

| # | Phase | Status | Source |
|---|---|---|---|
| 1 | Discover (WAIT) | Unchanged | — |
| 2 | Architect → Validate | Simplified — approval moved out | Reference project (separate Approval phase) |
| 3 | **Approval (WAIT)** | **NEW** — structured summary with per-task files, user decisions carried forward, risk assessment | Reference project production, Metaswarm (Design Review Gate), Superpowers (per-section approval) |
| 4 | Implement (delegated) | Enhanced — scope-aware wave ordering | Reference project (API→codegen→Web ordering) |
| 5 | Validate (automated) | Enhanced — startup check + test granularity | Reference project (runtime check), report line 968 (startup check recommendation) |
| 6 | **Simplify (automated)** | **NEW** — spawns subagent with shared criteria, reverts if CI breaks | Reference project (Phase 8), report audit v4 (simplify rated 9/10) |
| 7 | Review (with fix loops) | Enhanced — inline parallel review, no skill-calls-skill | Skill composition fix |
| 8 | **Ship & Finalize (WAIT)** | **NEW (merged)** — adjustment routing + docs + learnings + improvements + cleanup | Reference project (Ship + Finalize phases) |

#### Phase 3: Approval (new) — rationale

The template previously bundled approval into Phase 2 as a brief "Should I proceed?" The reference version presents a structured summary:
1. What we're building (2-3 sentences)
2. Implementation tasks (numbered, one-line each)
3. Per-task file changes
4. Key decisions & trade-offs
5. User decisions carried forward (verbatim from Phase 1)
6. Risk assessment
7. Validation summary (mirages detected)

This gives the user enough context for informed approval without reading the full spec. The report's Human-in-the-loop section (line 1088) identifies spec approval as a **mandatory gate**.

#### Phase 5: Validate (enhanced) — rationale

**Runtime startup check (Step 4):** Static checks (lint, build, test) miss DI failures, missing providers, env validation crashes. The reference project's production experience and the report's recommended pipeline (line 968-973) both confirm this. Boot the app for 15 seconds, check for runtime errors, kill.

**Test coverage granularity (Step 5):** Replaced the generic "test coverage check" with structured 3-tier coverage:
- **5a: Unit tests** — adjacent to changed source files, always checked
- **5b: Integration tests** — mandatory when touching data access, entity changes, multi-service logic
- **5c: E2E tests** — only for NEW endpoints, not modifications

Source: Reference project production (separate unit/integration/e2e checks with specific triggers per type).

#### Phase 6: Simplify (new) — rationale

Uses the shared reference pattern: `simplify-criteria.md` contains the 3 analysis passes (Reuse, Quality, Efficiency), AI anti-pattern detection, severity classification. The implement skill pre-reads this file and spawns a subagent with pre-inlined criteria.

Safe by design: if full-check fails after simplification, all changes are reverted (`git checkout -- .`).

Report audit v4 (line 3615) rated simplify 9/10 after the rewrite: "the most dramatic improvement — the previous 89-line version was essentially a basic checklist."

#### Phase 8: Ship & Finalize (new) — rationale

**Adjustment routing (Step 3):** Classifies user tweaks as big/medium/small and routes accordingly. Without this, the template either re-runs the whole pipeline for a typo or skips re-validation for a big change.

| Size | Signal | Action |
|---|---|---|
| Big | Data model, API contract, new endpoints | Re-architect → re-implement |
| Medium | New logic, needs research | Explore → maybe architect → implement |
| Small | Styling, typo, CI fix | Direct fix → validate |

Source: Reference project production (Ship phase with 3-tier routing).

**Doc updates (Step 4):** Scan diff against documentation sources, patch stale examples. Prevents doc drift — "the #1 source of confusion in future sessions."

**Learning extraction (Step 5):** Structured signals table for capturing user corrections, CI gotchas, architectural deviations. Saves to `.claude/.artifacts/knowledge/` and memory.

**Improvement suggestions (Step 6):** Proposes changes to rules, skills, and agent prompts based on pipeline friction. Creates a positive feedback loop where each implementation improves the harness.

Source: Reference project production (Finalize phase), report's Self-Improving Knowledge section.

### Cross-Skill Reference Audit

Audited all 12 skills + 13 agents for skill composition issues:

| File | Cross-references found | Issue? | Fix |
|---|---|---|---|
| `implement/SKILL.md` | `Read .claude/skills/review/SKILL.md and follow` (line 521) | **Yes** — review is a complex multi-agent orchestrator; "read and follow" loses infrastructure | Replaced with inline parallel reviewer spawning using pre-inlined criteria files |
| `implement/SKILL.md` | `Read .claude/skills/simplify/SKILL.md and follow` (Phase 6) | **Yes** — same issue | Replaced with subagent delegation using shared `simplify-criteria.md` |
| `implement/SKILL.md` | `run /simplify on changed files` (TodoWrite) | **Yes** — references skill invocation | Changed to `spawn simplify agent` |
| `follow-up/SKILL.md` | Spawns `reviewer-agent` directly | No | Correct pattern — uses agent, not skill |
| `review/SKILL.md` | Reads own criteria files | No | Correct pattern — supporting files in own directory |
| `refactor/SKILL.md` | "use `/simplify`", "use `/implement`" | No | Routing recommendations, not invocations |
| `debug/SKILL.md` | "use `/implement`", "use `/follow-up`" | No | Escalation suggestions, not invocations |
| `spec/SKILL.md` | "use `/follow-up`", "use `/implement`" | No | Routing recommendations |
| `onboard/SKILL.md` | "use `/follow-up`", `/debug`, `/implement`" | No | Routing recommendations |
| `ui-review/SKILL.md` | "use `/implement`", "/debug`" | No | Routing recommendations |
| All 13 agents | No skill references | No | Agents don't invoke skills |

**Result:** 3 issues found, all in `implement/SKILL.md`. All fixed. Zero remaining skill-calls-skill patterns in the template.

### Files Changed

| File | Change | Lines before → after |
|---|---|---|
| `skills/implement/SKILL.md` | 6→8 phase pipeline, inline review process, subagent simplify delegation | 593 → 755 |
| `skills/simplify/SKILL.md` | Extracted criteria to supporting file, simplified process | 280 → 162 |
| `skills/simplify/simplify-criteria.md` | **NEW** — shared reference file with 3 analysis passes, severity, anti-patterns | 0 → 131 |
| `report.md` (Known Limitations) | Expanded workaround with 3 ranked approaches + evidence links | — |
| `report.md` (Skill Composition Pattern 1) | Replaced "file-reading" with "shared reference + subagent delegation", added Pattern 1b | — |
| `report.md` (Composition selection guide) | Updated Pattern 1 recommendation | — |
| `report.md` (this section) | Added audit v6 | — |

### Updated Template Ratings

| File | Previous Rating | New Rating | Change |
|---|---|---|---|
| `implement/SKILL.md` | 9/10 | 9.5/10 | +0.5 (8-phase pipeline, no broken composition, inline review with criteria) |
| `simplify/SKILL.md` | 9/10 | 9/10 | = (same quality, better architecture — criteria extracted to supporting file) |

### Remaining Concerns

1. **implement at 755 lines** — further over the 500-line guideline. Phase 6 (Simplify) and Phase 8 (Ship & Finalize) are the longest sections. Could extract the agent delegation template (Step 3 of Phase 4, ~30 lines) and the adjustment routing table (Step 3 of Phase 8, ~15 lines) to supporting files if line count becomes a problem. However, splitting a pipeline orchestrator reduces coherence — the model needs to see the full flow to follow phase transitions correctly.

2. **Review criteria files loaded twice** — when `/review` is run standalone AND when `/implement` Phase 7 runs, the same criteria files are read. This is by design (each execution needs them in context), but creates a ~50K token overhead if both run in the same session. Not a practical concern since they run in different contexts (fork vs main).

3. **No automated test for composition patterns** — the audit was manual. A pre-commit hook or CI check could grep for `Read .claude/skills/.*SKILL.md` and flag potential composition issues. Not implemented — the pattern is now documented, which should prevent recurrence.

---

## Template Improvement Audit v7: Refactor Skill & Agent Cross-Pollination

### Methodology

Same approach as v6 (implement skill audit):
1. Compare template refactor skill + agent against the reference project's production versions
2. Identify gaps and improvements
3. Validate each suggestion against framework ecosystem and research
4. Implement only validated improvements

### Comparison: Template vs Reference

| Aspect | Template (before) | Reference | Gap |
|---|---|---|---|
| **Skill-agent relationship** | Disconnected — skill (133 lines) has full inline logic, agent (253 lines) is standalone. Running `/refactor` only executes the skill; agent sits unused | Skill (50 lines) delegates via `agent: refactor-agent` field | Template skill and agent duplicate each other |
| **Risk classification** | Agent has risk levels but no quantitative scoring | Agent counts consumers via grep, 10+ = HIGH regardless of transformation type | Template lacks quantitative impact scoring |
| **Model selection** | Skill: `model: opus`. Agent: `model: sonnet` | Skill: no model (inherits). Agent: no model (inherits) | Opus is too expensive for mechanical refactoring |
| **Failure handling** | Agent stops on first failure. Skill has "3 failures → AskUserQuestion" with no skip option | Agent: 3 attempts → revert → mark BLOCKED → continue to next step | Template blocks entire session on one stuck step |
| **Data safety** | No protection against destructive DB/Docker commands | Explicit prohibition on DROP TABLE, docker volume rm, TRUNCATE, etc. | Template missing safety guardrail |
| **Project conventions** | Skill mentions CLAUDE.md only for test commands | Agent reads `docs/code-guidelines.md` and `docs/project-structure.md` before analysis | Template can flag intentional patterns as smells |
| **Architecture-specific smells** | Generic smell catalog | NestJS + React specific smells (business logic in controllers, prop drilling, useEffect concerns) | No gap — template is intentionally generic (customized during /setup) |

### Improvements Applied (6 fixes)

#### Fix 1: Connect skill to agent via Agent tool spawn (HIGH priority)

**Problem:** Template has both `skills/refactor/SKILL.md` (133 lines) and `agents/refactor-agent.md` (253 lines) but they're completely disconnected. User runs `/refactor`, only the skill executes — the agent definition is wasted.

**The reference project's approach:** Uses `agent: refactor-agent` in skill frontmatter. However, this field is **undocumented and unreliable** ([#17283](https://github.com/anthropics/claude-code/issues/17283), [#8501](https://github.com/anthropics/claude-code/issues/8501)).

**Our fix:** Rewrote skill as a thin orchestrator (5 phases) that spawns the refactor-agent via the Agent tool — the same pattern established in v6 for implement→simplify. Skill handles scope/context/approval, agent handles analysis and execution.

**Evidence:**
- GitHub [#17283](https://github.com/anthropics/claude-code/issues/17283): `agent:` frontmatter feature request (not implemented)
- GitHub [#8501](https://github.com/anthropics/claude-code/issues/8501): skill documentation gaps
- v6 audit: established shared-reference + subagent delegation as the recommended composition pattern
- dev.to: "Refactoring Agent Skills: Context Explosion to Fast Workflow" — progressive disclosure pattern

#### Fix 2: Add Change Impact Scoring (MEDIUM priority)

**Problem:** Agent had no quantitative way to assess risk. "LOW/MEDIUM/HIGH" was purely subjective.

**The reference project's approach:** `grep -r "SymbolName" | wc -l` to count consumers. 10+ consumers = HIGH.

**Our fix:** Added Step 2 (Change Impact Scoring) to agent Phase 1. Consumer count thresholds: 1-3 LOW, 4-9 MEDIUM, 10+ HIGH. Added escalation override: any public API/export/shared type change is HIGH regardless of count.

**Evidence:**
- Springer: "Enhanced Code Reviews Using Change Impact Analysis" (2024) — CIA reduces maintenance costs across all maintenance types
- CodeScene: production tool using call graph + history mining for risk scoring
- testsigma.com: "Change Impact Analysis in Software Testing" — four-parameter risk scoring model

#### Fix 3: Change model from opus to sonnet (MEDIUM priority)

**Problem:** Skill used `model: opus` — expensive for mechanical transformations like extract-function, rename, move-to-file.

**Our fix:** Changed to `model: sonnet` on both skill and agent.

**Evidence:**
- dev.to: "Claude Opus 4.6 vs Sonnet 4.6 Coding Comparison" — Sonnet handles ~90% of refactoring; Opus only wins for 15+ file architectural refactoring
- nxcode.io: "Claude Opus or Sonnet for Coding? Decision Guide 2026" — Sonnet recommended for scoped, isolated work
- GSD framework: maps all executors (including refactoring) to sonnet, reserves opus for planning only

#### Fix 4: Add continue-on-blocked pattern (MEDIUM priority)

**Problem:** Agent stopped on first test failure. Template skill offered "3 failures → AskUserQuestion" but all options (try different approach, show state, escalate) halt the session.

**The reference project's approach:** 3 attempts → revert → mark BLOCKED → continue to next step. Report all blocked steps at the end.

**Our fix:** Added "Blocked Step Protocol" to agent Phase 3. After 3 failed attempts: revert via Edit, mark BLOCKED with failure report, continue to next transformation. Blocked steps collected and reported in Phase 4 summary.

**Evidence:**
- smartscope.blog: "Claude Code 2.0 Checkpoint Patterns" — atomic commit + rollback + continuation
- Spring Retry patterns: distinguish transient vs permanent failures, `@Recover` annotation for fallback
- dzone.com: "Retry Pattern Examples & Recommendations" — fail fast on permanent failures, don't block entire workflow

#### Fix 5: Add data safety rule (LOW priority)

**Problem:** No protection against destructive database/Docker commands in the agent (which is the one running Bash).

**Our fix:** Added explicit prohibition matching the reference project's pattern: `docker volume rm`, `podman volume rm`, `docker compose down -v`, `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`.

**Evidence:**
- OWASP Docker Security Cheat Sheet — destructive container operations as security concern
- in-com.com: "Database Refactoring Without Breaking Everything" — schema changes are persistent, global, irreversible
- Industry consensus: data destruction rules should be hard constraints, not guidelines

#### Fix 6: Read project conventions before analysis (LOW priority)

**Problem:** Agent jumped straight to smell detection without understanding project-specific patterns. Could flag intentional designs as smells.

**Our fix:** Added Step 0 to agent Phase 1: "Read project convention files referenced in prompt or CLAUDE.md before analyzing code." Kept generic (not hardcoded to specific file paths).

**Evidence:**
- Claude Code Best Practices docs: CLAUDE.md is auto-loaded, but referenced convention files need explicit reading
- HumanLayer: "Writing a Good CLAUDE.md" — skills should leverage conventions, not duplicate them
- Builder.io: "How to Write a Good CLAUDE.md" — convention files reduce false positives in analysis

### Self-Review: 5 Logical Issues Found and Fixed

After the initial 6-fix rewrite, a self-review pass found 5 additional logical issues. Each was validated against framework patterns and research before fixing.

#### Issue 1: `git checkout -- .` contradicts Git Constraint (HIGH)

**Problem:** Skill Phase 5 (line 112) uses `git checkout -- .` for revert, but Git Constraint (line 117) says "Do NOT run `git checkout`." Direct self-contradiction.

**Research:** The template's own `simplify/SKILL.md` (lines 113-115) uses `git checkout -- <file>` for reverts without contradiction — it frames the constraint as agent-only. The `hooks/dangerous-command-blocker.sh` blocks `git checkout .` in agents but allows it at skill level. The design boundary is: agents never touch git, skills orchestrate version control.

**Fix:** Reworded Git Constraint to explicitly permit `git checkout -- .` in Phase 5 as an orchestration-level revert, while maintaining the prohibition on `git add`, `git commit`, `git push`.

**Evidence:**
- Template `simplify/SKILL.md` lines 113-115 — same revert pattern without contradiction
- Template `hooks/dangerous-command-blocker.sh` lines 17, 28 — enforcement at agent level only
- GSD framework — reverts handled by orchestrator, never by executor agents

#### Issue 2: Lost backpressure integration (MEDIUM)

**Problem:** The old refactor skill had backpressure (`source .claude/hooks/backpressure.sh && run_silent "Tests" "<cmd>"`). The rewrite dropped it — agent runs tests with raw output that could flood its 60-turn context window.

**Research:** `backpressure.sh` already exists in the template at `hooks/backpressure.sh`. Report line 3254 confirms it was previously integrated into the refactor skill. On success: outputs "Tests passed" (~5 tokens). On failure: outputs only errors, capped at 150 lines. The HumanLayer comparison (report line 131 area) identified the lack of backpressure as a key gap.

**Fix:** Added backpressure to agent Phase 3 test commands (pre-check and post-check) with fallback to `tail -80` if unavailable. Also added backpressure reference to skill Phase 4 execution prompt.

**Evidence:**
- Template `hooks/backpressure.sh` — existing implementation
- Report line 3254 — "Integrated into 5 skills (implement, follow-up, refactor, simplify, debug)"
- Community research: test output flooding is a known context-rot vector in long agent sessions

#### Issue 3: TypeScript-specific grep example (LOW)

**Problem:** Agent Phase 1 Step 2 had `grep -r "SymbolName" src/ --include="*.ts" -l | wc -l` — hardcodes `src/` path and `*.ts` extension. Template should be project-agnostic.

**Research:** The agent has the Grep tool (ripgrep wrapper) in its toolset, which supports `output_mode: "count"` and language-agnostic `glob` parameter. The template's `architect-agent.md` (lines 77-92) already shows the correct pattern: use Glob/Grep dynamically based on project conventions rather than hardcoded paths.

**Fix:** Replaced bash grep example with `Grep(pattern="SymbolName", output_mode="count")` and a note to adjust glob filter based on project language.

**Evidence:**
- Template `architect-agent.md` lines 77-92 — correct dynamic exploration pattern
- Claude Code Grep tool docs — supports `output_mode: "count"` and `glob` parameter natively
- Ripgrep `--type` flag handles language detection without hardcoded extensions

#### Issue 4: "When to Stop & Ask" misleading title (LOW)

**Problem:** Agent section titled "When to Stop & Ask" but agent tools are `[Read, Write, Edit, Glob, Grep, Bash, Task, WebSearch]` — no `AskUserQuestion`. Agent cannot communicate with user directly.

**Research:** This is by design — the orchestrating skill owns user communication (same boundary as git). The skill has `AskUserQuestion` in its allowed-tools and uses it in Phase 3 (Approval). The agent returns structured output with HIGH risk flags; the skill reads them and asks the user. Report lines 2739-2741 document this pattern: "subagents shouldn't touch git because the parent skill manages shipping" — same principle applies to user interaction.

**Fix:** Renamed section to "When to Stop & Report Back" to accurately reflect the agent's capabilities.

**Evidence:**
- Report lines 2739-2741 — agent/skill boundary design pattern
- Skill Phase 3 (lines 76-78) — skill handles AskUserQuestion on agent's behalf
- Claude Code agent architecture — subagents return to orchestrator, don't communicate with user

#### Issue 5: Analysis-only prompt may not override agent execution (MEDIUM)

**Problem:** Skill Phase 2 spawns refactor-agent with "ANALYSIS ONLY — do NOT make any changes yet." But the agent definition has Phase 3 (Atomic Application) as part of its natural flow. Prompt-level mode overrides are unreliable.

**Research:** Report line 2241 documents the exact failure mode: "Claude tends to shortcut pipeline phases when changes seem 'simple'" — the inverse (executing when told not to) is equally possible. The implement skill handles this by using **different agents** for different phases (architect-agent for planning, backend/frontend-agent for execution). Two solutions considered:

- **Option A**: Split into separate `refactor-analyzer-agent.md` (read-only tools) and `refactor-agent.md` (full tools). Structurally safe — analyzer physically cannot write.
- **Option B**: Keep one agent, add explicit phase-skip + tool-restriction instructions to prompt. Simpler, relies on prompt compliance but with multiple reinforcing instructions.

Chose Option B — the architect-agent works similarly (has Write/Edit but is told to only produce a plan) and this avoids adding another agent file.

**Fix:** Expanded Phase 2 prompt from vague "ANALYSIS ONLY" to explicit instructions: "Execute ONLY your Phase 1 and Phase 2. Skip Phase 3 and Phase 4 entirely. Do NOT use Write or Edit tools during this invocation. Return the plan as your final output."

**Evidence:**
- Report line 2241 — documents pipeline phase shortcutting failure mode
- Template `implement/SKILL.md` — uses different agents per phase (architect, backend, frontend)
- Template `architect-agent.md` — works correctly with prompt-level "plan only" instruction (validates Option B)
- smartscope.blog: "Claude Code 2.0 Checkpoint Patterns" — mode-specific invocations as a design pattern

### Files Changed (Final)

| File | Change | Lines before → after |
|---|---|---|
| `skills/refactor/SKILL.md` | Rewritten as orchestrator: 5-phase pipeline with Agent tool spawning, model opus→sonnet, approval gate, anti-rationalization table. Then: git constraint fix, backpressure in Phase 4 prompt, explicit analysis-only Phase 2 | 133 → 153 |
| `agents/refactor-agent.md` | Added: data safety rule, project conventions step, Change Impact Scoring, Blocked Step Protocol. Then: backpressure in test commands, generic Grep tool, "Stop & Report Back" rename | 253 → 243 |
| `report.md` (this section) | Added audit v7 with 6 initial improvements + 5 self-review fixes | — |

### Updated Template Ratings

| File | Previous Rating | New Rating | Change |
|---|---|---|---|
| `skills/refactor/SKILL.md` | 8.5/10 | 9.5/10 | +1.0 (orchestrator pattern, sonnet model, approval gate, anti-rationalization table, git constraint fix, backpressure, explicit analysis-only) |
| `agents/refactor-agent.md` | 8/10 | 9/10 | +1.0 (impact scoring, blocked step protocol, data safety, project conventions, backpressure, generic grep, accurate section titles) |

### Remaining Concerns

1. **Skill spawns agent twice** — Phase 2 (analysis) and Phase 4 (execution) are separate Agent calls. This is intentional: the skill needs to review the plan and handle approval between analysis and execution. But it means 2x agent startup overhead. Acceptable trade-off for user control over HIGH risk steps.

2. **Agent consumer count heuristic is simple** — Grep-based counting doesn't distinguish direct imports from re-exports, test-only usage, or type-only imports. More sophisticated analysis (AST-based, call graph) is beyond what a refactoring agent should do. The simple heuristic catches the most dangerous cases (widely-used symbols).

3. **No architecture-specific smell catalogs in template** — intentionally generic. Project-specific smells (NestJS, React, Django, etc.) should be added by `/setup` based on detected tech stack, not baked into the template.

4. **Option B (prompt-level analysis-only) is not structurally enforced** — the agent could theoretically still use Write/Edit despite being told not to. If this proves unreliable in practice, upgrade to Option A (separate `refactor-analyzer-agent.md` with read-only tools). The implement skill's multi-agent pattern provides the blueprint.

---

## Template Improvement Audit v8: Review Skill & Agent Cross-Pollination

**Date:** 2026-04-04
**Methodology:** Same as audit v7 — compare template review skill/agent against the reference project's production installation, validate improvements against report.md findings and internet research, implement only validated changes, self-review for logical issues.

**Files compared:**
- Template: `claude-harness-template/skills/review/SKILL.md` + `claude-harness-template/agents/reviewer-agent.md`
- Reference: `reference-project/.claude/skills/review/SKILL.md` + `reference-project/.claude/agents/reviewer-agent.md`

### Comparison Table

| Aspect | Template (before) | Reference | Assessment |
|---|---|---|---|
| **Architecture** | Skill → 5 reviewer-agents (flat) | Skill → Task(reviewer-agent) → Task(5 sub-tasks) (nested) | **Template is correct.** The reference project's nested Task pattern violates known limitation #4182/#19077 — subagents cannot spawn sub-tasks. The template's flat architecture is the right pattern. |
| **Skill-Agent connection** | Descriptive only ("spawn 5 agents") | Uses `Task` tool with inline prompts | **Template gap.** No explicit Agent() code blocks — same disconnection issue fixed in refactor (audit v7). |
| **Criteria files** | External .md files loaded by skill, passed to agents | Inline in reviewer-agent (bloats to 494 lines) | **Template is better.** Criteria as separate files is cleaner and under 500-line limit. |
| **Adaptive batching** | Yes (>8 files / >400 LOC → batch mode) | No | **Template is better.** Backed by "Lost in the Middle" research (Liu et al., 2023). |
| **Data Safety Rule** | Missing | MANDATORY rule on skill + agent | **Template gap.** Agent has Bash access — needs defense-in-depth. |
| **[NEW]/[PRE-EXISTING] tagging** | No distinction | Tags findings | **Template gap.** Industry standard (SonarQube, CodeRabbit). |
| **Build verification** | Not mentioned | Runs `pnpm run full-check` in parallel | **Template gap.** Backpressure already in all other skills except review. |
| **Fix loop** | Review only | Review → Fix → Re-review (max 3 rounds) | **Design choice.** Template is generic — doesn't know about project-specific implementing agents. Not adopted. |
| **Confidence threshold** | >=80 (strict) | >=70 (looser) | **Both valid.** Template's stricter threshold reduces noise. Kept as-is. |
| **Output format** | Structured Markdown | JSON arrays | **Markdown preferred.** LLMs produce Markdown natively, fault-tolerant, no parse failures. Research: AGENTS.md spec, GitHub blog on agents.md both use Markdown. |
| **Orchestrator identity** | Implicit | "You are a router, not an explorer" | **Template gap.** Clarifying role prevents skill from reviewing code itself. |

### Improvements Implemented (5)

#### Fix 1 (HIGH): Explicit Agent() spawning code in skill

**Problem:** Skill described agent spawning in prose ("Five independent Agent tasks execute in parallel") but had no concrete `Agent(subagent_type="reviewer-agent")` code blocks. Same disconnection issue fixed in refactor skill (audit v7 Fix 1).

**Research:** The refactor skill already proves explicit Agent() invocations work. Claude Code skills deep-dive analysis confirms skills are prompts that Claude interprets — explicit code blocks give concrete templates vs requiring inference. The review skill was the only multi-agent skill without explicit invocation code.

**Fix:** Added 5 explicit `Agent(subagent_type="reviewer-agent", prompt="""...""")` code blocks in Standard Mode, with DIMENSION, CRITERIA, CHANGED FILES, PROJECT CONTEXT, and DIFF CONTEXT fields. Updated Batched Mode to reference the same pattern. Updated Parallel Execution Strategy to describe the flat architecture explicitly.

**Evidence:** Refactor skill audit v7 Fix 1 (same pattern); [Claude Skills Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)

#### Fix 2 (MEDIUM): Data Safety Rule in reviewer-agent

**Problem:** Reviewer-agent has `tools: [Read, Glob, Grep, Bash]` — Bash access means it CAN execute destructive commands even though it's instructed to "review only."

**Research:** Docker's AI agent security blog documents data destruction by LLM-generated scripts. Datadog and NVIDIA NeMo Guardrails both recommend marking all functions for reversibility. The template already has a `dangerous-command-blocker` hook as enforcement, but the agent prompt is the guidance layer (defense-in-depth). Already validated in refactor audit v7 Fix 5.

**Fix:** Added to Critical Constraints: "No destructive operations: Do NOT run commands that modify or delete data (DROP, DELETE, docker volume rm, rm -rf). You have Bash for grep/analysis only."

**Evidence:** [Docker AI Agent Runtime Security](https://www.docker.com/blog/secure-ai-agents-runtime-security/); [Datadog LLM Guardrails](https://www.datadoghq.com/blog/llm-guardrails-best-practices/); refactor audit v7 Fix 5

#### Fix 3 (MEDIUM): [NEW] vs [PRE-EXISTING] finding tagging

**Problem:** Template review output didn't distinguish between findings in changed code (introduced by this PR) vs pre-existing issues (already in codebase). All findings treated equally, making it hard to prioritize what the developer should fix NOW vs what's tech debt.

**Research:** SonarQube's entire quality philosophy ("Clean as You Code") is built on this distinction. Their [official documentation](https://docs.sonarsource.com/sonarqube-server/user-guide/about-new-code) states: "SonarQube differentiates the analysis results on new code from overall code." Default quality gates apply conditions to new code only. CodeRabbit, Coverity, and CodeClimate all implement the same pattern. Industry consensus: developers can only act on issues they introduced; pre-existing issues create noise.

**Fix:**
- Skill: Added DIFF CONTEXT field to all Agent() prompts. Updated judge pass to preserve tags and prioritize [NEW] findings.
- Agent: Added "Diff context" to Input Contract. Updated Output Format to include `[NEW/PRE-EXISTING]` in finding headers and `**Origin:**` field. Added "New findings: [count] | Pre-existing: [count]" to Dimension Summary.

**Evidence:** [SonarQube New Code](https://docs.sonarsource.com/sonarqube-server/user-guide/about-new-code); [CodeRabbit vs SonarQube Comparison](https://dev.to/rahulxsingh/coderabbit-vs-sonarqube-ai-review-vs-static-analysis-2026-48if)

#### Fix 4 (MEDIUM): Build verification with backpressure

**Problem:** Review skill was the only skill in the template without build/test verification. All other skills (implement, follow-up, refactor, simplify, debug) integrate backpressure.sh. The 5 reviewer agents check code quality but cannot detect build failures or test regressions.

**Research:** CI/CD best practices universally recommend running build verification in parallel with other analysis. Running tests is idempotent (read-only verification). The parallel-code-review skill by dgalarza demonstrates this pattern. Backpressure compresses output to ~5 tokens on success, preventing context bloat.

**Fix:** Added "Build Verification (parallel with reviewers, both modes)" section after criteria file loading. Uses backpressure.sh with fallback. Feeds pass/fail result into judge pass — a failing build is automatically a CRITICAL [NEW] finding.

**Evidence:** [CI/CD Best Practices](https://www.blazemeter.com/blog/ci-cd-best-practices-improve-code-quality); report.md line 3254 (backpressure integration); [Parallel Code Review Skill](https://playbooks.com/skills/dgalarza/claude-code-workflows/parallel-code-review)

#### Fix 5 (LOW): Orchestrator identity instruction

**Problem:** Skill didn't explicitly state its role as coordinator. Without this, Claude might read and review code itself instead of delegating to the 5 reviewer-agents, which defeats the multi-agent architecture.

**Research:** The reference project's review skill has "You are a router, not an explorer. Do not read source code yourself." The implement skill (audit v6) uses similar orchestrator identity patterns. Clear role definition prevents scope creep in orchestrator skills.

**Fix:** Added "Your Role — Orchestrate, Don't Review" section: "You are a coordinator. You delegate review work to reviewer-agent instances via the Agent tool and validate their outputs in the judge pass. You do NOT review code yourself."

**Evidence:** Reference project production pattern; implement skill orchestrator identity (audit v6)

### Improvement Rejected (1)

#### JSON output format for sub-reviewers — NOT ADOPTED

**Reason:** LLMs produce Markdown natively and fault-tolerantly. JSON has fragility (malformed output, missing quotes, trailing commas). The judge pass consumer is also an LLM that parses Markdown natively. AGENTS.md specification, GitHub's analysis of 2,500+ repos, and Shipyard multi-agent guide all use Markdown for inter-agent communication.

**Evidence:** [AGENTS.md Specification](https://agents.md/); [GitHub Blog on agents.md](https://github.blog/ai-and-ml/github-copilot/how-to-write-a-great-agents-md-lessons-from-over-2500-repositories/); [Markdown as Protocol for Agentic UI](https://fabian-kuebler.com/posts/markdown-agentic-ui/)

### Key Architectural Finding

**The reference project's nested Task architecture is broken.** The reference project's reviewer-agent spawns 5 sub-tasks via the Task tool, but this violates known limitation #4182/#19077 — subagents cannot spawn sub-tasks. The spawning either fails silently or degrades to serial single-context execution, negating the parallelism benefit and reintroducing the "Lost in the Middle" attention degradation that multi-agent review is designed to solve.

The template's flat architecture (skill spawns 5 leaf agents directly) is the correct pattern given Claude Code's current limitations.

**Evidence:** [GitHub #4182](https://github.com/anthropics/claude-code/issues/4182); [GitHub #19077](https://github.com/anthropics/claude-code/issues/19077); report.md Known Limitations section (line 48-49)

### Self-Review: 5 Issues Found and Fixed

**Issue 1 (initial): Build verification placement ambiguity**

**Problem:** Build verification section was placed under the Batched Mode heading (as a `####` subsection), making it ambiguous whether it applied to Standard Mode too.

**Fix:** Moved to after criteria file loading section with heading "Build Verification (parallel with reviewers, both modes)" — clearly applies to both modes.

**Issue 2 (MEDIUM): "Read criteria files first" positioned after code that uses them**

**Problem:** The `#### For both modes: Read criteria files first` section appeared AFTER the Standard Mode and Batched Mode Agent() code blocks that already reference `[content of bugs-criteria.md]`. The heading says "first" but its position says "after" — a sequencing contradiction.

**Research:** Every other skill in the template loads reference files before spawning agents. Implement skill (line 167): "pre-inlined — read them first, paste contents." Refactor skill: Phase 1 reads all files, Phase 2 spawns agent. report.md line 207: "Pass pre-read file contents in the prompt" — core GSD/Citadel pattern. report.md line 1010: "Pre-read review criteria files" listed before spawning.

**Fix:** Moved criteria loading to `#### Step 0: Load criteria files (both modes)` BEFORE Standard Mode. Removed the old misplaced section.

**Issue 3 (LOW): Build failure forced as [NEW] may be incorrect**

**Problem:** Line 158 said "CRITICAL finding" (no tag), line 167 said "CRITICAL [NEW] finding" (forced tag). Inconsistent, and a pre-broken build would be [PRE-EXISTING].

**Research:** GitHub Actions shows "This check was failing before the pull request" for pre-broken builds. SonarQube's New Code analysis only counts issues introduced since baseline. The skill's own tagging rule says unchanged-code findings are [PRE-EXISTING].

**Fix:** Reconciled both lines to: "CRITICAL finding — tag [NEW] if base branch build passes, or [PRE-EXISTING] if already broken."

**Issue 4 (LOW): Agent prompts pass content but agent re-reads files**

**Problem:** Agent() prompts say `CHANGED FILES: [list of files with their full content]` but reviewer-agent Step 2 says "Read the full file" — appears to duplicate work.

**Research:** report.md line 207, 418, 828 all confirm pre-inlining is the correct pattern. The "5x duplication" isn't real — each agent has its own context window. The agent's Read is for surrounding context (imports, dependencies) not already in the prompt.

**Fix:** Added clarifying note to reviewer-agent Step 2: "The orchestrator pre-inlines changed file contents in your prompt; use Read only for files NOT already provided."

**Issue 5 (LOW): Definition of Done missing [NEW]/[PRE-EXISTING] tagging**

**Problem:** Checklist covered confidence scoring and severity but not origin tagging — a first-class feature of the review output.

**Research:** report.md line 405: "Every skill needs a Definition of Done section" with clear exit criteria. report.md line 2978: precedent for fixing incomplete DoD sections.

**Fix:** Added checklist item: `- [ ] Findings tagged as [NEW] or [PRE-EXISTING] based on diff context`

### Files Changed

| File | Changes | Lines |
|---|---|---|
| `skills/review/SKILL.md` | Added: orchestrator identity, explicit Agent() code blocks, DIFF CONTEXT for tagging, build verification with backpressure, [NEW]/[PRE-EXISTING] in judge pass and output. Self-review: moved criteria loading before Agent blocks, fixed build tag to conditional, added DoD item | 269 → 339 |
| `agents/reviewer-agent.md` | Added: data safety rule, diff context in input contract, [NEW]/[PRE-EXISTING] in output format and summary. Self-review: clarified pre-inlined content in Step 2 | 137 → 142 |
| `report.md` (this section) | Added audit v8 with 5 improvements, 1 rejection, 1 self-review fix | — |

### Updated Template Ratings

| File | Previous Rating | New Rating | Change |
|---|---|---|---|
| `skills/review/SKILL.md` | 9/10 | 9.5/10 | +0.5 (explicit Agent spawning, orchestrator identity, build verification, [NEW]/[PRE-EXISTING] tagging in judge pass) |
| `agents/reviewer-agent.md` | 9/10 | 9.5/10 | +0.5 (data safety rule, diff context input, [NEW]/[PRE-EXISTING] output tagging) |

### Remaining Concerns

1. **Skill line count growing** — At 339 lines, the review skill is approaching the 500-line soft limit. The 5 explicit Agent() code blocks add ~50 lines. If more features are added, consider extracting the batched mode logic into a supporting file.

2. **[NEW]/[PRE-EXISTING] tagging depends on diff quality** — If the skill can't produce a clean git diff (e.g., reviewing files by path without a branch comparison), all findings default to [NEW]. This is acceptable — the tagging adds value when available, doesn't break anything when not.

3. **Build verification requires CLAUDE.md validation command** — If CLAUDE.md hasn't been generated yet (pre-setup), there's no validation command to run. The skill should gracefully skip this step. Currently handled implicitly by the "from CLAUDE.md" placeholder.

---

## Template Improvement Audit v9: Follow-Up Skill Cross-Pollination

Compared template `/follow-up` skill against the reference project's production installation to identify transferable improvements.

### Methodology

1. Read both skills (template: 430 lines, reference: 359 lines)
2. Identified 18 differences across frontmatter, escalation signals, validation, delegation, learnings, and structural sections
3. Validated each difference against report.md findings and internet research
4. Implemented 4 improvements, rejected 5 project-specific patterns

### Comparison Summary

| Area | Template | Reference | Winner |
|------|----------|--------|--------|
| Escalation signals | 8 signals | 9 signals (adds OCP violation) | Reference |
| Learn & Improve | "save as learning" (generic) | Typed memory: `feedback`/`project` | Reference |
| Fix loop handoff | "Fixed" + "Still failing" | Adds "CI status" subsection | Reference |
| Description | Mentions complexity levels | Explicit exclusions ("Do NOT use for...") | Reference |
| Frontmatter | `context: main`, `allowed-tools` | Neither field present | Template |
| Validation | Backpressure + tee fallback | Only `tee` fallback | Template |
| Compliance, DoD, Examples, Prior Context, Task Tracking | All present (71 lines) | All missing | Template |

### Implemented Improvements (4)

#### 1. [HIGH] Open-Closed Principle Violation as 9th Escalation Signal

**Problem:** Template's 8 hard escalation signals missed a class of risky changes: modifications to existing behavior that affect all consumers.

**Research:** OCP literature (Wikipedia, DevIQ, Stackify) unanimously frames "change by modification" as fundamentally riskier than "change by extension." Stackify: "modifications can create regressions that can theoretically exist anywhere within the entire system." This is not project-specific — it applies to any codebase.

**Fix:** Added to Hard Escalation Signals table: `| **Open-closed principle violation** | Modifies existing behavior for all consumers; regression risk is unbounded, needs rollback strategy |`

**Evidence:**
- [Open-Closed Principle - Wikipedia](https://en.wikipedia.org/wiki/Open%E2%80%93closed_principle)
- [OCP - DevIQ](https://deviq.com/principles/open-closed-principle/)
- [SOLID Design Open Closed Principle - Stackify](https://stackify.com/solid-design-open-closed-principle/)
- Report line 2990: existing signals "match scope control research" — OCP is the same class of risk signal

#### 2. [HIGH] Typed Memory Categories in Learn & Improve

**Problem:** Template said "save as learning" with no guidance on WHERE to save, causing ad-hoc decisions and poor retrieval quality.

**Research:** arXiv:2512.13564 ("Memory in the Age of AI Agents") + ICLR 2026 MemAgents workshop confirm typed memory (episodic/semantic/procedural) outperforms unstructured storage. mem0.ai State of AI Agent Memory 2026 confirms graph/typed memory is production-standard. Claude Code natively supports `feedback` and `project` memory types.

**Fix:** Replaced generic "save as learning" with typed categories:
- User corrections/preferences → `feedback` memory (persists across sessions)
- Discovered problems/workarounds → `project` memory (shared context)
- Validation failure resolutions → `feedback` memory (operational knowledge)

**Evidence:**
- [Memory in the Age of AI Agents (arXiv:2512.13564)](https://arxiv.org/abs/2512.13564)
- [State of AI Agent Memory 2026 - mem0.ai](https://mem0.ai/blog/state-of-ai-agent-memory-2026)
- [3 Types of Long-term Memory AI Agents Need - MachineLearningMastery](https://machinelearningmastery.com/beyond-short-term-memory-the-3-types-of-long-term-memory-ai-agents-need/)
- Report line 2201: Claude Code native memory supports `memory: user|project|local` frontmatter

#### 3. [MEDIUM] CI Status Subsection in Fix Loop Handoff

**Problem:** Template's structured handoff when stuck only had "Fixed" and "Still failing" sections — no at-a-glance triage view.

**Research:** The reference project's production handoff includes `Lint: PASS/FAIL — Types: PASS/FAIL — Build: PASS/FAIL — Tests: N/M passing`. Provides immediate triage without re-reading error logs.

**Fix:** Added `### CI status` subsection to the Phase 3 Step 6 structured handoff template.

#### 4. [MEDIUM] Improved Description with Explicit Exclusions

**Problem:** Template description mentioned complexity levels but lacked explicit exclusions, reducing skill routing accuracy.

**Research:** fp8.co Claude Code Skills guide + Dean Blank's mental model article confirm explicit exclusions in descriptions improve activation rates (20% → 90%). The reference project's description adds "new endpoints/pages, auth/permissions changes, or changes requiring architecture decisions."

**Fix:** Expanded description to include explicit exclusions: "Do NOT use for new features, new entities, new endpoints/pages, auth/permissions changes, new modules, or changes requiring architecture decisions."

**Evidence:**
- [Claude Code Skills Complete Developer Guide (fp8.co)](https://fp8.co/articles/Claude-Code-Skills-Complete-Developer-Guide)
- [A Mental Model for Claude Code Skills (Dean Blank)](https://levelup.gitconnected.com/a-mental-model-for-claude-code-skills-subagents-and-plugins-3dea9924bf05)

### Rejected Improvements (5 — all project-specific)

| Reference Pattern | Why Rejected |
|----------------|-------------|
| Scope detection (API-only/Web-only/Both) | Monorepo-specific; template must stay generic |
| Hardcoded port ranges in cleanup | Project-specific (`lsof -ti :4200-4299`) |
| Named agents (api-agent/web-agent) | Projects name their own agents during `/setup` |
| Hardcoded codegen/validation commands | Template correctly references CLAUDE.md |
| BullMQ examples in escalation signals | Too specific; generic wording is correct |

### Key Architectural Finding

The reference project lost 6 template sections during customization (~71 lines / 17%): Compliance table, Task Tracking (TodoWrite), Definition of Done, When to Use vs /implement comparison, Prior Context loading, and Examples. This validates the need for the `/upgrade` skill (report section 20) — manual customization strips useful generic content that should survive project-specific adaptation.

### Self-Review: 3 Issues Found and Fixed

#### Issue 1 (MEDIUM): OCP escalation signal lacked detection heuristic

**Problem:** All other 8 escalation signals are mechanically detectable (grep for new files, count modules). OCP was the only one requiring semantic judgment with no examples.

**Research:** The reference project's version has the same gap. OCP literature (Wikipedia, DevIQ, Stackify) identifies three concrete patterns: changing public method signatures, modifying shared middleware/validation, altering switch/if routing logic instead of adding handlers. These are observable in diffs.

**Fix:** Added inline examples: "e.g., changing a public method signature, altering shared validation/middleware, modifying switch/if routing logic instead of adding a handler"

#### Issue 2 (MEDIUM): `project` memory wrong for workarounds

**Problem:** Line 292 lumped "discovered problems" and "workarounds" together as `project` memory. But workarounds ("test runner fails without NODE_ENV=test") are operational behavioral guidance, not project state.

**Research:** The reference project's production version already splits this correctly — problems → `project`, workarounds → `feedback`. Claude Code memory system defines `feedback` as "guidance about how to approach work" which matches workarounds exactly. `project` memory is for high-level state that decays fast. arXiv:2512.13564 confirms different memory types serve different retrieval needs.

**Fix:** Split into two bullets: discovered problems → `project` memory, workarounds/patterns that failed → `feedback` memory.

#### Issue 3 (HIGH): Troubleshooting table said "3 fix rounds" but process says "Max 2"

**Problem:** Pre-existing inconsistency. Troubleshooting table (line 403) said "Validation fails after 3 fix rounds" but Phase 3 Step 6 (line 210) says "Max 2 fix rounds" and AskUserQuestion text (line 222) says "after 2 fix rounds."

**Research:** Report line 1162 confirms max 2 for follow-up validation. Report line 1193 confirms "Max 2 rounds (validation)" for follow-up. The reference project's production version already uses "2" in its troubleshooting table. The "3" was a copy-paste error from `/implement` pipeline (which uses max 3).

**Fix:** Changed troubleshooting table from "3 fix rounds" to "2 fix rounds."

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/follow-up/SKILL.md` | 430 lines | 438 lines | +8 lines (4 initial improvements + 3 self-review fixes) |

### Updated Ratings

| File | Before | After | Reason |
|------|--------|-------|--------|
| `skills/follow-up/SKILL.md` | 9/10 | 9.5/10 | +0.5 (OCP escalation signal with examples, typed memory categories split correctly, CI status in handoff, improved description, fix round consistency) |

---

## Template Improvement Audit v10: All Remaining Skills

**Date:** 2026-04-04
**Scope:** 8 skills — spec, simplify, features, debug, setup, onboard, learnings, ui-review
**Method:** 8 parallel research agents (audit) → 7 parallel validation agents (evidence check) → 7 parallel implementation agents + direct edits

### Methodology

1. Identified all template skills not yet audited (8 of 12 — implement/refactor/review/follow-up already done in v6-v9)
2. For 3 skills with reference project counterparts (spec, simplify, features): cross-pollination comparison
3. For 5 template-only skills (debug, setup, onboard, learnings, ui-review): internal quality review
4. Each finding validated against report.md, framework patterns, and internet research
5. Validated fixes implemented across all files

### Summary

| Skill | Type | Findings | Confirmed | Rejected | Implemented |
|-------|------|----------|-----------|----------|-------------|
| **spec** | Cross-pollination | 9 | 8 | 1 (S7: YAML frontmatter) | 8 |
| **simplify** | Cross-pollination | 4 | 0 | 0 | 0 (already clean) |
| **features** | Cross-pollination | 5 | 3 | 2 (F1: table is fine, F2: statuses fine) | 3 |
| **debug** | Quality review | 6 | 5 | 1 (D3: Write auto-creates dirs) | 5 |
| **setup** | Quality review | 5 | 3 | 2 (T4: low priority, T5: claim accurate) | 3 |
| **onboard** | Quality review | 5 | 5 | 0 | 5 |
| **learnings** | Quality review | 5 | 5 | 0 | 5 |
| **ui-review** | Quality review | 5 | 5 | 0 | 5 |
| **Total** | — | **44** | **34** | **10** | **34** |

### Implemented Fixes by Skill

#### Spec Skill (8 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| S1 | HIGH | Added `$ARGUMENTS` + empty-argument AskUserQuestion handling | All other skills use $ARGUMENTS; report line 474 |
| S2 | HIGH | Added Phase 0: Initialize (dir creation, duplicate detection, prior context) | Report line 2973; implement skill has same pattern |
| S3 | MED | Added confirmation step when no gray areas (not silent auto-proceed) | GSD discuss-phase auto-mode pattern; safety-first |
| S4 | MED | Added AskUserQuestion empty-answer plain-text fallback | 6+ active Claude Code bugs: #10400, #29733, #10229, #29547, #12672 |
| S5 | MED | Added multiSelect for gray area triage | AskUserQuestion multiSelect confirmed as real parameter |
| S6 | MED | Added Scope Creep Guard (observational, not enforcing) | Report line 181 (skeptic-agent flags scope creep); O'Reilly AI agent guardrails |
| S8 | MED | Changed to dynamic `<feature-name>-spec.md` naming | Previous FEATURE_SPEC.md would overwrite on second run |
| S9 | MED | Added max 2 follow-up question rounds | Report line 713 (max 3 rounds standard); 2 for spec since simpler than fix loops |

**Rejected:** S7 (YAML frontmatter in spec output) — frontmatter is for Claude Code infra files, not user-facing spec documents. No other planning artifact uses it.

#### Features Skill (3 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| F3 | MED | Added cross-reference note to `/spec` for detailed specs | Skills should reference each other at natural handoff points |
| F4 | MED | Added `move <id> <status>` command for status transitions | Previously no way to mark features as in-progress or blocked via command |
| F5 | MED | Added routing hint on `next` output: "Ready to spec? `/spec [name]`" | Reference project pattern; limited to `next` to avoid "clippy syndrome" |

**Rejected:** F1 (per-file storage) — single table is deliberately lightweight, doesn't conflict with spec files. F2 (draft/approved statuses) — couples two independent skills unnecessarily.

#### Debug Skill (5 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| D1 | HIGH | Added "Do NOT use for..." exclusions to frontmatter description | Report line 4452: explicit exclusions improve routing 20%→90% |
| D2 | HIGH | Added typed memory categories to Document step (project/feedback) | Follow-up skill pattern; arXiv:2512.13564 confirms typed memory effectiveness |
| D4 | MED | Defined "inconclusive" + fixed status flow to branching notation | MIT/UCSD debugging courseware; internal inconsistency fixed |
| D5 | MED | Added conditional codegen check in Step 6 Verify | Follow-up skill Phase 3 Step 3 pattern; conditional to avoid noise |
| D6 | MED | Added `$ARGUMENTS` + Bug Report section with AskUserQuestion | Standard pattern across all pipeline skills |

**Rejected:** D3 (directory creation guard) — Write tool auto-creates directories. Tested and confirmed.

#### Setup Skill (3 fixes + 2 new files)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| T1 | HIGH | Extracted `conflict-resolution.md` (241 lines) + `verification-checks.md` (41 lines) | Report line 70: "SKILL.md should be under 500 lines." Reduced from 855→589 lines (31%) |
| T2 | MED | Report note: /upgrade skill was consolidated into setup's Re-Running flow | Skills cannot call skills (known limitation); setup already has merge algorithm |
| T3 | MED | Added AskUserQuestion fallback for undetectable projects in Phase 1.1 | Edge case: empty repos, documentation-only repos, unsupported languages |

**Rejected:** T4 (merge verification) — current Read-and-check is adequate for AI. T5 ("same algorithm" wording) — claim is literally accurate.

#### Onboard Skill (5 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| O1 | HIGH | Added "Do NOT use for..." exclusions to description | Follow-up pattern; fp8.co routing research |
| O2 | HIGH | Fixed DoD contradiction: <2000→<1000 lines, added --focus escape hatch | Internal inconsistency between compliance section and DoD |
| O3 | MED | Changed `model: opus` → `model: sonnet` | Sonnet achieves 97-99% of Opus coding at 5x lower cost; scanning doesn't need deep reasoning |
| O4 | MED | Added Arguments section defining --depth and --focus | argument-hint advertised flags but never defined them |
| O5 | MED | Added Edge Cases section (empty repo, permissions, large repos) | Lightweight graceful degradation instead of heavy retry pattern |

#### Learnings Skill (5 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| L1 | HIGH | Added "Relationship to Built-in Memory" section | Report lines 2200-2212: native memory for preferences, JSONL for structured technical learnings |
| L2 | HIGH | Aligned JSONL schema between skill and knowledge-retrieval-agent | Schema mismatch: skill had `session`/`verified`, agent expected `context`/`timestamp` |
| L3 | MED | Rewrote description: "Use when..." + "Do NOT use for..." | Report line 404: description pattern |
| L4 | MED | Added `files`/`keywords` tags to JSONL schema | Report lines 2106-2127: Metaswarm selective retrieval pattern |
| L5 | MED | Made session documents optional Phase 4 with `--no-session-doc` flag | Clarified ownership; session docs are secondary output, not always needed |

#### UI-Review Skill (5 fixes)

| # | Sev | Fix | Evidence |
|---|---|---|---|
| U1 | HIGH | Fixed `allowed-tools`: replaced "Playwright" with 11 actual MCP tool names | "Playwright" matches nothing; tools are `mcp__plugin_playwright_playwright__*` |
| U2 | HIGH | Replaced impossible capabilities with realistic ones | WAVE, color picker, screen reader are not available via MCP; replaced with browser_evaluate, browser_snapshot, browser_press_key |
| U3 | HIGH | Added Phase 0 Playwright availability check | Try browser_navigate to about:blank; provide install instructions on failure |
| U4 | MED | Replaced DevTools timing with Performance API via browser_evaluate | performance.getEntriesByType('navigation') is standard Web API |
| U5 | MED | Added screenshot save with explicit `filename` parameter | browser_take_screenshot accepts filename param; no base64 needed |

### Key Architectural Findings

1. **UI-review was fundamentally broken** — `allowed-tools: [Playwright]` matched no real tool. The skill would silently lack all Playwright capabilities. Fixed with explicit MCP tool names.

2. **Setup exceeded 500-line limit by 71%** — Extracted 282 lines into 2 supporting files using the progressive disclosure pattern (same as review skill's criteria files). Reduced to 589 lines.

3. **Learnings skill overlapped with built-in memory** — Added explicit differentiation: native auto-memory for preferences/context, JSONL for structured technical learnings with categories, counters, and file/keyword tags for selective retrieval.

4. **JSONL schema was mismatched** between learnings skill and knowledge-retrieval-agent — the agent expected fields that didn't exist (`context`, `timestamp`). Aligned both to skill's schema + new `files`/`keywords` tags.

5. **Simplify skill was already clean** — Template version is strictly superior to the reference project's version. All improvements were already applied in prior audits.

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/spec/SKILL.md` | 311 lines | 341 lines | +30 (8 fixes: $ARGUMENTS, Phase 0, multiSelect, scope guard, dynamic naming, max rounds) |
| `skills/features/SKILL.md` | 138 lines | 146 lines | +8 (3 fixes: move command, cross-reference, routing hint) |
| `skills/debug/SKILL.md` | 206 lines | 219 lines | +13 (5 fixes: description, typed memory, inconclusive def, codegen, $ARGUMENTS) |
| `skills/setup/SKILL.md` | 855 lines | 589 lines | -266 (extracted to 2 supporting files + fallback added) |
| `skills/setup/conflict-resolution.md` | — | 241 lines | NEW (extracted from setup Phase 1.5) |
| `skills/setup/verification-checks.md` | — | 41 lines | NEW (extracted from setup Phase 4.1) |
| `skills/onboard/SKILL.md` | 236 lines | 248 lines | +12 (5 fixes: description, DoD, model, arguments, edge cases) |
| `skills/learnings/SKILL.md` | 266 lines | 272 lines | +6 (5 fixes: memory section, schema, description, session docs optional) |
| `skills/ui-review/SKILL.md` | 195 lines | 197 lines | +2 (5 fixes: tools, capabilities, pre-flight, performance, screenshots) |
| `agents/knowledge-retrieval-agent.md` | 86 lines | 85 lines | -1 (schema alignment with learnings skill) |

### Updated Ratings

| File | Before | After | Reason |
|------|--------|-------|--------|
| `skills/spec/SKILL.md` | 8/10 | 9.5/10 | +1.5 ($ARGUMENTS, initialization, multiSelect, scope guard, dynamic naming, max rounds, fallback) |
| `skills/features/SKILL.md` | 8.5/10 | 9/10 | +0.5 (move command, cross-references, routing hint) |
| `skills/debug/SKILL.md` | 8.5/10 | 9.5/10 | +1.0 (description exclusions, typed memory, inconclusive definition, codegen, $ARGUMENTS) |
| `skills/setup/SKILL.md` | 7.5/10 | 8.5/10 | +1.0 (line count reduction 855→589, supporting file extraction, undetectable project fallback) |
| `skills/onboard/SKILL.md` | 8/10 | 9/10 | +1.0 (description exclusions, DoD fix, model cost reduction, arguments defined, edge cases) |
| `skills/learnings/SKILL.md` | 7/10 | 8.5/10 | +1.5 (memory differentiation, schema alignment, selective retrieval tags, optional session docs) |
| `skills/ui-review/SKILL.md` | 5/10 | 8.5/10 | +3.5 (was fundamentally broken; fixed tools, capabilities, pre-flight, performance, screenshots) |
| `skills/simplify/SKILL.md` | 9/10 | 9/10 | No change needed (already clean) |

---

## Plan Skill Creation & Task Complexity Research (Audit v11)

### Context

Created a new `/plan` skill (`skills/plan/SKILL.md` + `skills/plan/plan-criteria.md`) to produce file-level implementation plans saved to `.artifacts/planning/plan-<slug>.md`. Plans are generated by architect-agent, validated by skeptic-agent, and referenced by all downstream agents in the `/implement` pipeline.

Initial version used file count as the sole complexity signal (1-3 = Small, 4-8 = Medium, 9+ = Large). Research revealed this is the weakest predictor of task difficulty.

### Research Findings: Task Complexity Estimation

**Core insight:** "File count is a smell detector, not a complexity detector" (already established in follow-up skill, line 1084). A 2-file migration + API contract change is harder than a 10-file rename propagation. Research confirms this across multiple sources.

#### Evidence from SWE-bench and Academic Research

| Source | Finding | Implication |
|--------|---------|-------------|
| SWE-bench Verified Difficulty Analysis (Ganhotra 2025) | Files modified scale only 2x easy→hard, but edit scatter (hunks) scales 5x and LOC scales 11x | Edit scatter and change distribution predict difficulty better than file count |
| SWE-bench Pro (Scale AI, arxiv:2509.16941) | Cross-file coordinated reasoning is the primary failure driver; codebase familiarity matters enormously | Cross-boundary scope and pattern availability are Tier 1 signals |
| FeatureBench (ICLR 2026, arxiv:2602.10975) | Claude 4.5 Opus: 74.4% on SWE-bench (bug fixes) vs 11.0% on FeatureBench (new features) — 7x gap | Task type (new vs extend vs fix) is the strongest single predictor |
| Agent Psychometrics (ICLR 2026 Workshop, arxiv:2604.00594) | IRT-based decomposition: issue ambiguity + repo context + solution structure predict difficulty; scaffold quality (planning) independently reduces effective difficulty | Good planning reduces actual task difficulty; ambiguity count is a valid complexity signal |
| Agentic Refactoring (arxiv:2511.04824) | Agents succeed on consistency edits (84% merge for docs) but fail on structural changes (55% for performance) | Task category predicts difficulty; structural > surface changes |
| Anthropic Agent Autonomy Research | On harder tasks, Claude asks clarification 2x more often; complexity correlates with agent uncertainty | Agent's own uncertainty during discovery is a valid difficulty signal |
| Rethinking Autonomy (arxiv:2508.11824) | Risk taxonomy: suggestive (reversible) → generative (VCS-reversible) → autonomous (potentially irreversible) | Reversibility is a top-tier complexity dimension |

#### Complexity Dimensions Ranked by Predictive Power

**Tier 1 — Strong Predictors (use all):**
1. **Hard escalation signals** — new entity/migration, new API endpoint, auth changes, new subsystem, 3+ modules coordinated, OCP violation, async work, external integration, ambiguous intent. ANY of these → Large regardless of file count.
2. **Task type** — bug fix/rename (low) vs extend-existing (medium) vs new feature/greenfield (high). Predicts 7x difficulty gap per FeatureBench.
3. **Cross-boundary scope** — number of architectural layers crossed. Single module vs 2 layers vs 3+ layers/cross-stack.
4. **Reversibility** — pure source changes vs stateful side effects (migrations, API contracts, external calls).
5. **Pattern availability** — strong exemplar exists vs partial pattern vs greenfield design.

**Tier 2 — Moderate Predictors (use as modifiers):**
6. **Edit scatter** — concentrated changes vs distributed across many distinct locations. SWE-bench shows 5x scaling easy→hard.
7. **Ambiguity count** — number of unresolved gray areas discovered during Phase 1.
8. **Hotspot density** — proportion of changes touching high-fanout files (routing, config, barrel exports).
9. **Consumer count** — how many downstream files depend on code being changed. 1-3 LOW, 4-9 MEDIUM, 10+ HIGH (from refactor skill).

**Tier 3 — Weak Predictors:**
10. **File count** — only 2x scaling in SWE-bench data. Useful as a supporting signal, not a primary gate.
11. **Estimated LOC** — rough proxy, unreliable for planning.

#### Scoring Formula Applied

```
difficulty_score = (
    task_type_weight          # 0-2: fix/rename=0, extend-existing=1, new-feature/greenfield=2
  + cross_boundary_score      # 0-2: single module=0, 2 layers=1, 3+ layers=2
  + reversibility_score       # 0-2: source-only=0, new files + tests=1, stateful side effects=2
  + edit_scatter_score        # 0-2: concentrated=0, moderate=1, highly distributed=2
  + pattern_availability      # 0-2: strong exemplar=0, partial=1, no pattern=2
)
# 0-3: Small | 4-6: Medium | 7+: Large
# Hard escalation signals override to Large regardless of score
```

**Validation examples:**
- 10-file rename propagation: task=0 + boundary=0 + reversible=0 + scatter=1 + pattern=0 = **1 (Small)** ✓
- 2-file DB migration + API contract: hard signal (migration) → **Large** ✓
- 5-file OAuth feature with existing auth patterns: task=1 + boundary=1 + reversible=0 + scatter=1 + pattern=0 = **3 (Small/Medium boundary)** ✓
- New payment subsystem across 8 files: hard signal (new subsystem) → **Large** ✓

### Additional Improvements Applied to Plan Skill

From cross-referencing the explore audit, report.md findings, and internet research:

| # | Improvement | Evidence Source |
|---|-------------|----------------|
| 1 | Anti-rationalization table (6 entries) | report.md lines 2242-2286: "most underappreciated failure mode" |
| 2 | Multi-dimensional effort scaling (replacing file count) | SWE-bench, FeatureBench, follow-up skill pattern |
| 3 | Mode detection (auto/assumptions/interactive) | report.md lines 798-804, consistency with implement skill |
| 4 | Deduplicated validation checklist (single source in plan-criteria.md) | Audit inconsistency: drift risk from two copies |
| 5 | Empty $ARGUMENTS handling | report.md line 4549 pattern |
| 6 | Definition of Done section | report.md line 407: standard across all skills |
| 7 | Max iteration escalation with user options | Audit: implement has escalation, plan skill didn't |
| 8 | Rollback field on every plan step | Galileo/Zylos research: 80% faster recovery |
| 9 | Progressive delivery for Large tasks | report.md lines 3619, 3925-3936; Codex plan mode |
| 10 | Prior context loading (existing plans, specs, learnings) | report.md lines 2973-2974 |
| 11 | Mirage detection (skeptic must grep for file/function existence) | report.md line 210: "skeptic validates against real codebase" |

### Plan Skill Structure (from Frameworks Research)

Cross-referenced plan formats from 6 frameworks:

| Framework | Plan Format | Key Pattern Adopted |
|-----------|-------------|---------------------|
| Cline deep planning | 8-section `implementation_plan.md` (Overview, Types, Files, Functions, Classes, Dependencies, Testing, Implementation Order) | Merged into Steps + Files Affected table + Test Scenarios |
| Codex plan mode | `<proposed_plan>` with "decision-complete" standard | Plan must leave zero decisions to the implementer |
| Codex update_plan tool | JSON steps with `pending/in_progress/completed` status | Status field in plan header |
| GSD | Researcher → planner → plan-checker loop | Architect → skeptic validation, max 3 iterations |
| Cursor | `todo_write` with one `in_progress` at a time | Progressive TodoWrite in implement skill |
| Aider architect mode | Free-form prose from architect → editor executes | Two-agent pattern (architect generates, executor implements) |

### Files Created/Changed

| File | Action | Lines |
|------|--------|-------|
| `skills/plan/SKILL.md` | Created | 320 |
| `skills/plan/plan-criteria.md` | Created | 155 |
| `skills/implement/SKILL.md` | Modified | Phase 2-3 refactored to reference plan skill + criteria file |
| `README.md` | Modified | Added plan skill to counts and directory tree |
| `skills/setup/SKILL.md` | Modified | Added plan/ to skills copy list, updated counts |

---

## Template Improvement Audit v11: Follow-Up Token Optimization

**Date:** 2026-04-06
**Scope:** `/follow-up` skill — delegation enforcement, simplify phase, review quality
**Method:** 3-source triangulation (internet research, report.md analysis, codebase exploration)
**Trigger:** Production observation — follow-up orchestrator implementing 10+ file Medium changes directly, consuming excessive orchestrator tokens instead of delegating

### Implemented Fixes

| # | Severity | Fix | Evidence |
|---|----------|-----|----------|
| 1 | HIGH | Added coordinator statement: "You delegate implementation work to subagents. You do NOT write code directly — except Trivial." Follow-up was the only orchestrator skill without this identity block. | All other orchestrator skills (implement, review, deep-simplify, refactor) have explicit coordinator statements. Report.md L4294: "Without it, Claude will read and review code itself." |
| 2 | HIGH | Added 3 anti-rationalization rows about delegation: "I'll implement directly", "I'll quickly edit myself", "Spawning agent is overkill" | Thread showed orchestrator doing `Write` and `Update` for a Medium change. Implement skill has equivalent rows (lines 395-401). |
| 3 | MEDIUM | Added Phase 3: Simplify — spawns sonnet agent with `simplify-criteria.md` for Medium changes, safe revert if CI fails | Implement has Phase 5 (Simplify) between implementation and review. Follow-up lacked this quality pass. |
| 4 | MEDIUM | Upgraded review agents to use structured criteria files from `.claude/skills/review/` instead of ad-hoc inline descriptions | Implement Phase 6 Stage C and standalone /review both pre-inline criteria files. Follow-up was using ad-hoc dimension descriptions. Report.md L598-614 on shared criteria files. |
| 5 | LOW | Added `## Tests — MANDATORY` section to Small and Medium implementation agent prompts | Implement-reference agent template has mandatory Tests section. Follow-up agents lacked test requirements. |

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/follow-up/SKILL.md` | 499 lines | 483 lines | Coordinator statement, simplify phase, criteria-based review, test-mandatory agents, delegation anti-rationalization |

### Key Findings
- Follow-up was the only orchestrator skill that allowed direct code writing beyond trivial edits — all other skills had explicit coordinator identity statements
- The absence of a simplify phase meant AI-generated anti-patterns went straight from implementation to validation without a quality pass
- Ad-hoc review dimensions in follow-up produced lower-quality reviews than the structured criteria files used by implement and standalone review
- Anthropic's own guidance (internet research) supports selective delegation with complexity thresholds — the Trivial carve-out for direct implementation is correct and aligned with official docs

## Template Improvement Audit v12: Follow-Up Phase 4 Boundary Enforcement

**Date:** 2026-04-06
**Scope:** Follow-up skill Phase 4 (Validate) — boundary enforcement between validation and review phases
**Method:** 3-source triangulation (internet research, report.md analysis, codebase exploration)

### Context

In production usage, the follow-up orchestrator was observed overstepping Phase 4 boundaries: after an implementation agent completed a seeder task, the orchestrator entered Phase 4 validation and began deep manual code analysis — finding bugs (wrong variable: `lawyerUserId` instead of `clientUser.id`), discovering missing database tables, running migrations, and fixing all issues directly without delegation. This work belongs in Phase 5 (Review) and violates the orchestrator's coordinator role.

Root cause: Phase 4 lacked explicit scope constraints. While Phase 2 had a coordinator identity statement (added in Audit v11), Phase 4 had no equivalent — leaving an implicit permission for source code analysis during validation.

### Implemented Fixes

| # | Severity | Fix | Evidence |
|---|----------|-----|----------|
| 1 | HIGH | Added Phase 2 Step 3: Completion Check — verifies implementation agent completed its task via `git diff --name-only` and `git status --short` without reading source code | implement skill has explicit verification gate (diff + file existence check); follow-up had none. Absence caused orchestrator to compensate by reading code. |
| 2 | HIGH | Added Phase 4 orchestrator identity constraint: "run commands, do NOT read source code or find bugs — that is Phase 5's job" | Direct precedent: review skill received "Orchestrate, Don't Review" in Audit v8 (L4295-4303) because without it Claude reviewed code itself. Same pattern, same fix. |
| 3 | HIGH | Rewrote Phase 4 Step 6 Fix Loop — removed blanket "fix directly" option for type/build/test errors. Retained Trivial exception (1-3 line fixes). All other failures delegated to fixer agent with raw error output. | implement-reference Phase 6 Stage A explicitly says "do NOT diagnose or read source files yourself." Follow-up Phase 4 had no equivalent prohibition. Internet research: Builder-Validator pattern (claudefa.st), Response Awareness methodology both confirm validators should be read-only. |
| 4 | MEDIUM | Added anti-rationalization entry: "I noticed a bug during validation — I'll fix it now" → wrong because bug-finding is Phase 5's job | Compliance table had no entry covering Phase 4 → Phase 5 boundary. implement skill has per-phase compliance entries. |
| 5 | MEDIUM | Simplified Phase 4 Step 5 (Test Coverage Check) to file-existence checks only — no longer instructs orchestrator to grep for function names or evaluate coverage quality | implement skill confines test verification to file-system checks. Evaluating whether tests "cover" changes requires reading source code — which is Phase 5 review work. |

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/follow-up/SKILL.md` | 484 lines | 486 lines | Phase 2 completion check, Phase 4 identity constraint, fix loop rewrite, anti-rationalization entry, test coverage simplification |

### Key Findings
- The absence of an orchestrator identity constraint in Phase 4 is the direct cause of validation-phase scope creep — same root cause as Audit v8 (review skill). When the boundary is implicit, the orchestrator defaults to "help" by reading code.
- Phase 4 (Validate) and Phase 5 (Review) serve architecturally distinct purposes: Phase 4 is mechanical/deterministic (command pass/fail), Phase 5 is semantic/contextual (fresh-context agents finding bugs). Collapsing them wastes Phase 5's fresh-context advantage.
- The Trivial fix exception in Phase 4 Step 6 is load-bearing: without it, a typo fix that causes a 1-line type error would require spawning a fixer agent — disproportionate overhead. The exception is scoped to 1-3 lines to prevent creep.
- Internet research (14 sources) unanimously agrees: validation = deterministic gate, review = contextual judgment. This is a named anti-pattern in Builder-Validator patterns (claudefa.st), Response Awareness methodology, and AddyOsmani's production patterns.

## Template Improvement Audit v13: Setup Cleanup Skipped on Compare & Update

**Date:** 2026-04-06
**Scope:** Setup skill — Phase 5 cleanup not reached after Compare & Update flow
**Method:** Phase 1-fast (obvious bug from production thread)

### Context

When running `/setup` in "Compare & update" mode (Step 2B), the orchestrator completed file comparisons and applied the user's choice (restore template version of follow-up skill), then asked "Is there anything else?" The user said "good" and the session ended — without ever reaching Phase 4 (Verify) or Phase 5 (Cleanup). This left `.claude/.artifacts/template-source/` in the project, which is a bootstrap artifact that should be removed after setup completes.

Root cause: Steps 2A, 2B, and 2C all ended with the soft instruction "Then proceed to Phase 4 (Verify) and Phase 5 (Cleanup) as normal." This was too easy for the orchestrator to skip when the conversational flow naturally wound down after the user approved file changes.

### Implemented Fixes

| # | Severity | Fix | Evidence |
|---|----------|-----|----------|
| 1 | HIGH | Replaced 3 soft "proceed to Phase 4/5" instructions with hard directives: "DO NOT end the conversation or ask 'anything else?' here. You MUST proceed to Phase 4 and Phase 5 now — template-source cleanup is mandatory." | Production thread showed orchestrator ending session at exactly these transition points. |
| 2 | MEDIUM | Added compliance table entry: "The user said 'good' — setup is done, I can stop" → wrong because Phase 5 cleanup has not run yet | Same failure mode as Audit v11/v12: absent constraints = implicit permission to skip. |

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/setup/SKILL.md` | 992 lines | 995 lines | 3 hard transition gates + 1 compliance entry |

### Key Findings
- Soft transition instructions ("proceed to X as normal") are unreliable at conversation-boundary points where the user's natural language ("good", "looks good") can be interpreted as session completion
- The same pattern (absent hard constraint → orchestrator skips phase) recurs across skills — Audit v8 (review), v11 (follow-up coordinator), v12 (Phase 4 boundary), now v13 (setup cleanup). Hard negative constraints ("DO NOT") are more reliable than positive ones ("proceed to")
- Bootstrap artifacts left behind can cause confusion in future sessions — the template-source directory makes the setup skill think it's a re-run

## Template Improvement Audit v14: Follow-Up Context Exhaustion & Phase Skipping

**Date:** 2026-04-06
**Scope:** Follow-up skill (context management, phase compliance, delegation enforcement)
**Method:** 3-source triangulation (internet research, report.md analysis, codebase exploration)
**Trigger:** Production thread showed follow-up orchestrator: (1) accumulating massive context in Phase 1, (2) fixing type errors directly in Phase 4 instead of delegating, (3) skipping Phase 3 (Simplify) and Phase 5 (Review) entirely for a Medium change.

### Implemented Fixes

| # | Severity | Fix | Evidence |
|---|----------|-----|----------|
| 1 | HIGH | Added strategic compact point after Phase 2 — write state checkpoint to `.claude/.artifacts/follow-up-state.md`, suggest `/compact` to user | implement skill has this pattern (lines 148-154). ECC framework documents strategic compaction. Report L1953-1964 confirms. |
| 2 | HIGH | Added strategic compact point before Phase 5 for Medium changes — update state, suggest `/compact` before review agents spawn | Report: "After review+fix cycle → Compact." Thread confirms phases 3+5 skipped due to context exhaustion. |
| 3 | HIGH | Strengthened Phase 4 fix loop delegation — default to delegate, Trivial-only exception explicitly scoped to overall-Trivial changes. New anti-rationalization entry. | Thread: Medium change, orchestrator made 6+ direct edits in Phase 4. Report Audits v8/v11/v12 confirm drift pattern. |
| 4 | HIGH | Added hard "DO NOT" phase transition directives at Phase 2→3, 3→4, 4→5 boundaries | Report Audits v8/v11/v12/v13: same phase-skipping pattern across 4 audits. Hard negatives > soft positives. |
| 5 | MEDIUM | Phase 5 reviewers read their own criteria files — orchestrator no longer pre-reads 5 criteria files into its context | Codebase: criteria pre-read adds 5 files at worst possible time. implement doesn't pre-read at orchestrator level. |
| 6 | MEDIUM | Phase 3 simplify agent reads its own criteria file (consistency fix from review) | Review finding: Phase 3 still pre-read criteria, inconsistent with Phase 5 pattern after fix #5. |
| 7 | MEDIUM | Medium reviewer agents now include severity/verdict instruction matching Small reviewer | Review finding: Medium agents missing "Report findings with severity" instruction present in Small reviewer prompt. |

### Files Changed

| File | Before | After | Change |
|------|--------|-------|--------|
| `skills/follow-up/SKILL.md` | 487 lines | 497 lines | Strategic compact points, hard transitions, delegation mandate, criteria delegation to agents |

### Key Findings
- Context exhaustion is the root cause of phase skipping — the orchestrator runs out of usable context before reaching later phases (Simplify, Review). Strategic compact points between phases are the primary mitigation.
- The same orchestrator-drift pattern (directly implementing instead of delegating) recurs across audits v8, v11, v12, now v14. The Trivial direct-fix exception was being misapplied to Small/Medium changes — making it explicit ("overall complexity must be Trivial") is the fix.
- Soft phase transitions ("proceed to X") fail under context pressure. Hard negative constraints ("DO NOT present summary or ask 'anything else?'") are reliably more effective — confirmed across 5 audits now.
- Pre-reading criteria files into orchestrator context before delegating to review agents is counterproductive — it adds context at the worst possible time (after Phases 1-4 have already consumed most of the budget). Agents should read their own criteria.
