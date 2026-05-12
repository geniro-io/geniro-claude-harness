# Geniro Claude Plugin

A production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks. Provides 9 agents, 17 skills, and 7 safety hooks + statusline + update check out of the box.

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

## Quick Start

1. **Install** the plugin (see above) and open Claude Code in your project.
2. **Run setup** — analyzes your stack and generates a tailored `CLAUDE.md`:
   ```
   /geniro:setup
   ```
3. **Map the codebase** (optional, recommended for larger repos) — produces `CODEBASE_MAP.md`:
   ```
   /geniro:onboard
   ```
4. **Build a feature** — 8-phase pipeline with architecture, implementation, validation, and review:
   ```
   /geniro:implement add user authentication with JWT tokens
   ```
5. **Review your work** before shipping:
   ```
   /geniro:review
   ```

From there, pick the right skill for each task: `/geniro:debug` to investigate bugs (proposes the fix; hands it to `/geniro:follow-up` or `/geniro:implement`), `/geniro:follow-up` for small tweaks, `/geniro:refactor` for restructuring, `/geniro:investigate` for codebase Q&A.

## How it works

The plugin itself ships globally — agents, skills, and hooks live inside the installed plugin and never pollute your repo. The only thing written into your project is a single `.geniro/` directory that acts as the working memory across sessions:

```
.geniro/
├── .geniro-state.json      # what setup generated (used by cleanup + vendor)
├── planning/               # specs, plans, CODEBASE_MAP.md, FEATURES.md backlog
├── knowledge/              # learnings.jsonl + session summaries across runs
├── instructions/           # project-specific rules (global.md + per-skill files)
├── debug/                  # HYPOTHESES-<branch>.md scratchpad for /geniro:debug (branch-scoped)
└── workflow/               # optional integrations (issue tracker, PR flow)
```

`.geniro/` is gitignored by default, except `workflow/` and `instructions/` which are meant to be committed so the team shares the same rules and integrations.

### Typical workflow

```
  /geniro:brainstorm  →  /geniro:implement   →  /geniro:follow-up
  (refine idea into            ↑                 (small tweaks
   approved design)      /geniro:decompose        after shipping)
                         (for Big tasks —
                          splits into milestones)
```

Want to go deeper on quality?

```
  /geniro:deep-simplify   →   /geniro:review
  (reuse/quality/efficiency   (7–8 parallel reviewers:
   — zero behavior change)     bugs, security, architecture,
                               tests, optimizations,
                               guidelines, conventions,
                               +design)
```

Each skill reads from and writes to `.geniro/` so context survives across compaction, branches, and sessions:

- **Plan → implement** — `/geniro:implement`'s Phase 2 (architect + skeptic) drops a validated plan into `.geniro/planning/<branch>/plan-<slug>.md` before coding starts; for Big tasks, `/geniro:decompose` produces a master plan plus per-milestone files in the same directory.
- **Knowledge accumulates** — `/geniro:learnings` appends gotchas to `knowledge/learnings.jsonl`; future `/geniro:debug` and `/geniro:implement` runs grep it before investigating.
- **Rules persist** — `/geniro:instructions` writes rules into `.geniro/instructions/`, and every relevant skill reads `global.md` + its own file on every run (so "always use snake_case for DB columns" only has to be said once).
- **State survives compaction** — long pipelines checkpoint to `.geniro/state/follow-up/state-<branch>.md` or the planning dir, so the next turn can resume exactly where it left off. Within-skill state files are branch-scoped per `skills/_shared/within-skill-state-handoff.md` so parallel sessions on different branches don't clobber each other.

If you ever want to walk away cleanly, `/geniro:cleanup` removes everything listed in `.geniro-state.json` and leaves user-created files untouched.

## Skills

### `/geniro:setup` — AI-driven project setup

Scans your codebase, interviews you about preferences, and generates a tailored CLAUDE.md with detected tech stack, commands, and conventions.

```
/geniro:setup
```

### `/geniro:implement` — Full-featured implementation

Eight-phase pipeline: discover scope, architect a solution, get your approval, implement with parallel agents, validate, simplify, review, and ship.

```
/geniro:implement add user authentication with JWT tokens
/geniro:implement create a REST API for managing blog posts
/geniro:implement integrate Stripe payments for subscriptions
```

### `/geniro:review` — Parallel multi-agent code review

Spawns 7–8 specialized reviewers (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files are present) in parallel with confidence-scored findings. Optional **TDD mode** authors a failing test that reproduces each bug-class finding (F→P verified — red today, green after fix) and gates PR comments on confirmed findings only. On PR-ref input, prompts to run the review in a dedicated `.claude/worktrees/pr-<N>-review/` worktree so any authored tests or commits land on the PR's head branch — silently reuses an existing worktree if one is already in `git worktree list`, or if the session is already inside the matching one.

```
/geniro:review                               # review uncommitted changes
/geniro:review src/auth/ src/middleware/      # review specific files/dirs
/geniro:review HEAD~3..HEAD                   # review a commit range
/geniro:review #1234 --tdd                    # PR review with TDD-mode posting gate
```

### `/geniro:debug` — Scientific-method bug investigation

Systematic debugging: observe → hypothesize → test → isolate → propose fix → author repro test & verify → escalate → document. Never applies the fix itself; escalates to `/geniro:follow-up` or `/geniro:implement`. Tracks all hypotheses and rejects speculation.

```
/geniro:debug login returns 500 after password reset
/geniro:debug memory leak in WebSocket handler after 1000 connections
/geniro:debug tests pass locally but fail in CI on the date formatting step
```

### `/geniro:follow-up` — Quick post-implementation changes

For small changes that skip architecture. Assesses complexity, implements, validates, reviews, and ships. Escalates to `/geniro:implement` if scope is too large.

```
/geniro:follow-up rename the "users" endpoint to "accounts"
/geniro:follow-up add created_at timestamp to the response DTO
/geniro:follow-up fix the typo in the error message on line 42
```

### `/geniro:deep-simplify` — Three-pass parallel code review

Spawns 3 agents (reuse, quality, efficiency) on changed files. Applies P1/P2 fixes and reverts if CI breaks. Zero behavior change guaranteed.

```
/geniro:deep-simplify                        # review uncommitted changes
/geniro:deep-simplify src/services/          # review specific directory
```

### `/geniro:refactor` — Safe code restructuring

Incremental refactoring with continuous test verification. Detects code smells, applies transformations atomically, guarantees zero behavior change.

```
/geniro:refactor extract payment logic from OrderService into PaymentService
/geniro:refactor consolidate duplicate validation across controllers
/geniro:refactor convert callback-based auth module to async/await
```

### `/geniro:investigate` — Deep codebase Q&A

Parallel research agents explore codebase structure, git history, and internet sources to produce evidence-backed answers.

```
/geniro:investigate how does the caching layer invalidate stale entries?
/geniro:investigate what happens when a WebSocket connection drops mid-transaction?
/geniro:investigate why was the ORM switched from Sequelize to Prisma?
```

### `/geniro:features` — Feature backlog management

Track features with status, priority, and complexity. Create detailed specs with codebase scouting and adaptive questioning.

```
/geniro:features list                          # show all tracked features
/geniro:brainstorm dark mode support           # standalone ideation → design doc
/geniro:features add dark mode support         # ideation + backlog registration
/geniro:features next                          # pick the next feature to work on
/geniro:features complete dark mode support    # mark as done
```

Both `/geniro:brainstorm` and `/features add` use the same canonical brainstorming loop — the difference is whether the result is registered in FEATURES.md backlog (`/features add`) or remains a standalone draft (`/geniro:brainstorm`).

### `/geniro:onboard` — Rapid codebase orientation

Scans structure, files, patterns, and conventions. Produces a CODEBASE_MAP.md with architecture, module relationships, critical paths, and entry points.

```
/geniro:onboard
/geniro:onboard focus on the API layer
```

### `/geniro:instructions` — Custom instruction management

Create, list, edit, validate, and delete project-specific rules that customize how skills behave.

```
/geniro:instructions list
/geniro:instructions create "always use snake_case for database columns"
/geniro:instructions create "skip review for test files" --scope review
/geniro:instructions delete no-orm-rule
```

### `/geniro:actions` — Create, edit, run, and remove custom workflow actions

Scaffold custom workflow-helper actions (Slack pings, PR inspections, release summaries) into `.geniro/actions/` and run, edit, or delete them through the parent skill. Custom actions are NOT top-level slash commands — they're only reachable through `/geniro:actions <verb>` (e.g., `run` to execute the body, `edit` to modify the file, `delete` to remove it). The bare-slug fast path `/geniro:actions <slug>` is shorthand for `run <slug>` when the slug exists.

```
/geniro:actions list                                       # show all custom actions
/geniro:actions create pr-notify-slack                     # interview-driven scaffold of a new action
/geniro:actions edit pr-notify-slack                       # open existing action for external edit + re-validate
/geniro:actions run pr-notify-slack 1234                   # invoke by exact slug + positional args
/geniro:actions run "post release notes to slack"          # invoke by free-text description (resolved via picker)
/geniro:actions pr-notify-slack 1234                       # bare-slug fast path: defaults to run when slug exists
/geniro:actions delete pr-notify-slack                     # remove a custom action
```

By default `.geniro/actions/` is committed (team-shared). Remove the `!.geniro/actions/` lines from `.gitignore` to keep them local-only. When invoked from a linked git worktree, `run` falls back to the main worktree's registry (with confirmation) if the action isn't present locally; `delete` refuses cross-worktree deletion and asks you to switch to main first.

### `/geniro:brainstorm` — refine an idea into an approved design

Standalone ideation layer (no backlog commitment). Runs the canonical 8-phase
brainstorming loop (HARD-GATE → Explore → Visual companion → Clarifying →
Approaches → Section approval → Design doc → Self-review → User re-review),
then offers a hand-off menu (Implement / Decompose / Add to backlog / Stop).

Cites `skills/_shared/brainstorming-loop.md` (8-phase loop) and `skills/_shared/design-doc-detect.md` (auto-detect existing design via path + HTML marker + YAML frontmatter — no flags).

For backlog-tracked ideation, use `/geniro:features add` (same loop + F-id registration).

### `/geniro:learnings` — Extract session learnings

Captures patterns, gotchas, decisions, and anti-patterns from completed work into categorized memory with reusability gates.

```
/geniro:learnings
/geniro:learnings focus on the auth refactor decisions
```

### `/geniro:vendor` — Vendor plugin into project

Copies the plugin into `.claude/` with a `geniro-` prefix so it runs on cloud runners, sandboxed CI, or offline environments where the marketplace isn't available. After vendoring, slash commands change from `/geniro:setup` to `/geniro-setup`.

```
/geniro:vendor                               # vendor fresh
/geniro:vendor --sync                        # resync after plugin update
/geniro:vendor --fresh                       # force re-vendor from scratch
```

### `/geniro:cleanup` — Remove plugin files

Removes all geniro-claude-plugin files from the project. Uses plugin state to preserve user-created files. Includes confirmation before any deletion.

```
/geniro:cleanup
```

### `/geniro:update` — Update plugin

Updates to the latest version. The status line shows an arrow when updates are available.

```
/geniro:update
```

## The Pipeline: /geniro:implement

```
/geniro:implement add user authentication
```

1. **Discover** — Clarify scope, edge cases, decisions
2. **Architect** — Design solution; skeptic agent validates; you approve
3. **Approval** — Full plan presented; you confirm before coding starts
4. **Implement** — Backend and frontend agents build in parallel
5. **Validate** — Automated checks (lint, build, test, startup)
6. **Simplify** — 3 parallel agents review for reuse, quality, efficiency
7. **Review** — Code quality review across 7–8 dimensions with fix cycles
8. **Ship** — Present results; you decide to commit/push/PR

## Safety Hooks

All hooks run automatically after installation:

| Hook | Protection |
|------|-----------|
| `db-guard` | Prevents `DROP DATABASE`, `DELETE FROM` without WHERE |
| `file-protection` | Prevents writing to `.env`, `.pem`, secrets |
| `block-dangerous-git` | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch (per-project opt-out via `.geniro/safety.json`) |
| `post-compact-notification` | `SessionStart` hook (`matcher: "compact"`) — re-injects suggested files (CLAUDE.md, `.geniro/instructions/global.md`, active `<skill>.md`, `code-style.md`, planning state) so custom rules and workflow context survive compaction |
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
├── agents/                      # 14 specialized agent definitions
├── skills/                      # 15 reusable workflow definitions
│   ├── setup/                   # AI-driven project setup
│   ├── implement/               # 8-phase feature pipeline
│   ├── review/                  # 7–8 dimension code review
│   ├── vendor/                  # Vendor into .claude/ for cloud runners
│   └── ...
├── hooks/                       # 7 safety hooks + statusline + update check
│   ├── hooks.json               # Hook configuration
│   ├── geniro-check-update.js   # Update detection (SessionStart)
│   ├── geniro-statusline.js     # Status line renderer
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
