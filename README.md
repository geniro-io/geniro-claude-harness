# Geniro Claude Plugin

A production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks. Provides 5 agents, 11 skills, and 8 safety hooks + statusline + update check out of the box.

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
2. **Run setup** — analyzes your stack and generates a tailored thin-map `CLAUDE.md` + `.geniro/instructions/user-preferences.md`:
   ```
   /geniro:setup
   ```
3. **Map the codebase** (optional, recommended for larger repos) — produces `.geniro/planning/_CODEBASE_MAP.md`:
   ```
   /geniro:onboard
   ```
4. **Plan a feature** — spec-first planning, turns a vague idea into an approved `spec.md`:
   ```
   /geniro:plan add user authentication with JWT tokens
   ```
5. **Implement** — consumes the spec.md (or inline-task if /plan wasn't run), 2-phase autonomous loop:
   ```
   /geniro:implement
   ```
6. **Review your work** before shipping:
   ```
   /geniro:review
   ```

From there, pick the right skill for each task: `/geniro:debug` to investigate bugs (authors a fix proposal + reproduction test, escalates to `/geniro:implement` to ship), `/geniro:refactor` for zero-behavior-change restructuring, `/geniro:investigate` for codebase Q&A.

## How it works

The plugin itself ships globally — agents, skills, and hooks live inside the installed plugin and never pollute your repo. The only thing written into your project is a single `.geniro/` directory that acts as the working memory across sessions:

```
.geniro/
├── planning/               # specs, plans, _CODEBASE_MAP.md, _FEATURES.md, _project.md, _focus-*.md
│   └── <task-dir>/         # M4/M5 task-bound: spec.md, plan.md, state.md, milestone-N.md
├── state/                  # M1 §T1 session-bound + handoff
│   ├── <skill>/<slug>/state.md  # M7 /debug, M8 /refactor, M9 /onboard, M9 /investigate
│   ├── setup/state.md      # M10a /setup singleton
│   └── handoff/            # M1 §T2 inter-skill: from-<producer>-<branch>.md
├── knowledge/              # learnings.jsonl (L2 episodic) + session summaries
├── instructions/           # L4 procedural: global.md, code-style.md, user-preferences.md,
│                           # per-skill.md, review-extra/<slug>.md
├── actions/                # T3 user-authored workflow helpers (Slack/PR/release)
├── docs/                   # M10a §3.4 spin-out targets (hooks.md, mcp.md, agent-runtime.md)
└── workflow/               # optional integrations (issue tracker, PR flow)
```

`.geniro/` is gitignored by default, except `workflow/`, `instructions/`, and `actions/` which are meant to be committed so the team shares the same rules and integrations.

### Typical workflow

```
  /geniro:plan  →  /geniro:implement  →  /geniro:review
  (spec-first      (2-phase autonomous     (multi-dim code review
   planning)        execute + ship)         before merge)
```

For investigation and maintenance:

```
  /geniro:debug          /geniro:refactor       /geniro:investigate
  (scientific-method     (zero-behavior-change   (parallel research
   bug investigation)     restructuring)          agents Q&A)
```

Each skill reads from and writes to `.geniro/` so context survives across compaction, branches, and sessions:

- **Plan → implement** — `/geniro:plan` writes an approved `spec.md` to `.geniro/planning/<task-dir>/`; `/geniro:implement` consumes it (or accepts inline-task input as a fallback). For Big tasks, `/geniro:plan` Phase 5 milestone-mode emits sibling `milestone-N.md` files.
- **Knowledge accumulates + auto-prunes** — every pipeline + discovery skill auto-emits L2 entries to `knowledge/learnings.jsonl` per M2 §5.3 trigger table. Types: `discovery` / `pitfall` / `diagnosis` / `convention` / `decision` (M2 baseline), plus P-X8 additions `discarded_hypothesis` (/debug Phase 1 ELIMINATED hypotheses), `retry_failure_sequence` (/implement, /debug, /refactor when retry_count ≥ 2), `user_rejected_suggestion` (any skill, AUQ rejection signal). Future runs query before investigating; `query-learnings --score-min N` ranks by recency × trust × access (P-X8-4). **Auto-archive on SessionStart** (default ON, opt-out via `safety.json memory.auto_archive_stale: false`): flips `deprecated: true` on entries matching `age > 180d AND score < 0.1 AND access_count == 0` — never deletes (audit trail). Hash-gated к skip unchanged runs; mkdir-locked для multi-tab safety.
- **Rules persist** — `/geniro:instructions` manages `.geniro/instructions/`, and every relevant skill applies the canonical loader at `skills/_shared/load-custom-instructions.md` on every run (Step 0 + phase-boundary refresh) to read `global.md` + per-skill file + `code-style.md` + `user-preferences.md` (M10b), with an observable echo line after each Read (so "always use snake_case for DB columns" only has to be said once, and you can SEE that the rules were loaded).
- **State survives compaction** — long pipelines checkpoint to M1 §T1 state files (`<task-dir>/state.md` or `state/<skill>/<slug>/state.md`); the M3 SessionStart hook re-injects them after every `compact|resume|startup` event. Within-skill state files are slug-scoped per `skills/_shared/within-skill-state-handoff.md` so parallel sessions on different branches don't clobber each other.

## Skills (11 total — post-M4 redesign)

### `/geniro:setup` (M10a) — AI-driven project setup

4-phase singleton bootstrap (Detect → Interview → Generate → Validate → Done). Scans codebase via lockfile/config presence; interviews you for preferences that can't be auto-detected; generates a **thin-map** CLAUDE.md + `.geniro/instructions/user-preferences.md` (L4). Phase 3 P-M10-3 split methodology: sections >40 LOC default to spin out to `.geniro/docs/<topic>.md`. Phase 4 verification subagent + 3-retry escalation loop. L2 `discovery` emit on done.

```
/geniro:setup
/geniro:setup --reset-prefs        # reset preference categories only
```

### `/geniro:plan` (M5) — Spec-first planning

9-phase loop (mode-detect → explore → clarify ≤5 questions → 2-3 approaches → 10-section approval → write → mechanical validate → user approve → hand-off). Produces an approved `spec.md` in `.geniro/planning/<task-dir>/` with goal-state frontmatter (budget / checkpoints / forbidden_actions / approval_required_for). Milestone-mode for Big tasks emits sibling `milestone-N.md` files.

```
/geniro:plan add user authentication with JWT tokens
/geniro:plan migrate from Sequelize to Prisma
```

### `/geniro:implement` (M4) — Autonomous implementation

2-phase loop: Analyze → Implement → Self-review-and-Ship. Consumes `spec.md` from `/plan` (or inline-task fallback when `/plan` hasn't been run). Single solo execution path with 5-dim parallel self-review (bugs / security / architecture / tests / code-quality). Absorbs post-ship tweaks from the legacy `/follow-up`.

```
/geniro:implement                              # consume spec.md from /plan
/geniro:implement add a CHANGELOG entry        # inline-task fallback
```

### `/geniro:review` (M6) — Parallel multi-agent code review

6-phase reporter loop (triage → mechanical pre-pass → 9-dim LLM reviewers → filter → stratify → persist → action-gate). Dimensions: bugs / security / architecture / tests / optimizations / guidelines / conventions (+design when UI files present, +pr-metadata when input was a PR ref, +spec-compliance when PLAN CONTEXT non-none). Phase 1.5 mechanical pre-pass (lint / schema / secret scan) feeds prior-context. Phase 5b auto-emits `pitfall` L2 entries on cross-reviewer convergence ≥3. Optional `--simplify` flag prepends Reuse/Quality/Efficiency criteria (absorbs deleted `/deep-simplify`). Optional `--tdd` flag tightens validation budget + F→P test-gate.

```
/geniro:review                                # review uncommitted changes
/geniro:review src/auth/ src/middleware/      # review specific files/dirs
/geniro:review HEAD~3..HEAD                   # review а commit range
/geniro:review #1234 --tdd                    # PR review with TDD-mode draft-review posting gate
```

### `/geniro:debug` (M7) — Scientific-method bug investigation

3-phase loop (Investigate → Propose → Ship). Phase 1 observes / hypothesizes / tests / isolates root cause; Phase 2 authors a text fix proposal + F→P reproduction test (no production-source edits); Phase 3 persists T2 hand-off at `.geniro/state/handoff/from-debug-<branch>.md` and escalates к `/geniro:implement`. §1.7 stall gate (5 inconclusive → AUQ); §2.5 fix-fail gate (2 attempts → AUQ). Phase 3 §3.3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}`. **Never ships code.**

```
/geniro:debug login returns 500 after password reset
/geniro:debug memory leak in WebSocket handler after 1000 connections
/geniro:debug tests pass locally but fail in CI on the date formatting step
```

### `/geniro:refactor` (M8) — Safe code restructuring

3-phase loop (Plan → Apply → Verify) with **zero-behavior-change guarantee**. Phase 1 classifies tier via canonical `_shared/effort-scaling.md` (Trivial / Small / Medium / Big); runs orchestrator-inline smell detection per `_shared/refactor-patterns.md`. Phase 2 runs orchestrator-inline per-step execution with per-step regression check + Blocked Step Protocol (3 retries → revert + continue). Phase 3 runs independent reviewer + custom reviewers; PRODUCT-DECISION → ESCALATE к /implement (4-option ADR-aware AUQ). Auto-emits L2 `discovery` + `pitfall`. **Never ships code** — diff IS the deliverable; user commits manually or runs `/geniro:implement`.

```
/geniro:refactor extract payment logic from OrderService into PaymentService
/geniro:refactor consolidate duplicate validation across controllers
/geniro:refactor convert callback-based auth module to async/await
```

### `/geniro:onboard` (M9) — Rapid codebase orientation

2-phase loop (Discover → Map). Scans codebase structure and produces `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` with the canonical 8-section template (M1:508 underscore-prefixed L3 registry). Phase 1 applies P-M9-2 ≤50-file scan cap (user-confirmable expansion via AUQ). Phase 2 calls `update-semantic` (M2 §6.1 bounded auto-incremental L3 write), emits L2 `discovery`, fires Next-step AUQ routing to /plan / /investigate / /implement / `_FEATURES.md`. `--focus` / `--depth` retained as scope-limiters on the full 8-section template.

```
/geniro:onboard
/geniro:onboard --focus api
```

### `/geniro:investigate` (M9) — Deep codebase Q&A

3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present). Phase 1 classifies $ARGUMENTS into 9-type taxonomy + 5-step JIT retrieval cadence. Phase 2 spawns 1-3 parallel research agents (Codebase Analyst / Git Historian / Internet Researcher — literal classified set, never over-spawned). Phase 3 synthesizes, spawns fresh reviewer-agent, presents with Sources + Open questions, fires save-routing AUQ (CLAUDE.md / ADR / learnings.jsonl). L2 `discovery` emit with trust label (`verified` if code-grounded; `retrieved` if WebFetch/WebSearch load-bearing). **Never ships code.**

```
/geniro:investigate how does the caching layer invalidate stale entries?
/geniro:investigate what happens when а WebSocket connection drops mid-transaction?
/geniro:investigate why was the ORM switched from Sequelize to Prisma?
```

### `/geniro:instructions` (M10b) — Custom instruction management

3-phase stateless CRUD (parse → execute → done) over `.geniro/instructions/`. 5 operations: list / create / edit / validate / delete. 11-scope set: `global`, `code-style`, `user-preferences`, `review-extra/<slug>`, and per-skill (`implement`, `plan`, `review`, `debug`, `refactor`, `onboard`, `investigate`). §10 `validate` mode (P-M10-2 closure): structural + reference + per-scope lint with CRITICAL/HIGH/MEDIUM/LOW severities; catches refs to dropped skills and outdated phase names.

```
/geniro:instructions list
/geniro:instructions create implement
/geniro:instructions create review-extra sql-bindings    # add а custom code-review dimension
/geniro:instructions edit user-preferences
/geniro:instructions validate
/geniro:instructions delete debug
```

### `/geniro:actions` (M10c) — Custom workflow-helper management

3-phase stateless CRUD + runner over `.geniro/actions/`. 6 operations: list / create / edit / run / delete / validate. **P-M10-1 minimal enforcement (Q4):** `risk_class: low | medium | high` mandatory frontmatter field; run-mode AUQ ladder gates by risk class (`low` skips AUQ, `medium` 1-click confirm, `high` Cancel-as-recommended default). §Phase 8 `validate` mode shares the P-M10-2 rule set with `/instructions validate review-extra`. L2 `discovery` emit on successful runs with `external-send: true`.

```
/geniro:actions list                                       # show all custom actions
/geniro:actions create pr-notify-slack                     # interview-driven scaffold
/geniro:actions edit pr-notify-slack                       # external edit + re-validate
/geniro:actions run pr-notify-slack 1234                   # invoke by exact slug + args
/geniro:actions run "post release notes к slack"          # invoke by free-text (picker)
/geniro:actions pr-notify-slack 1234                       # bare-slug fast path (defaults to run)
/geniro:actions validate                                   # lint all .geniro/actions/*.md
/geniro:actions delete pr-notify-slack
```

When invoked from а linked git worktree, `run` falls back to the main worktree's registry (with confirmation); `delete` refuses cross-worktree deletion.

### `/geniro:update` (M10d) — Update plugin

5-phase stateless loop (Pre-check → Update → Post-check → Migration → Done). Pre-update version-confirm AUQ. User-content snapshot at Pre-check + survival diff at Post-check (catches silent corruption). 4-retry exponential backoff (2s/4s/8s/16s) on network errors. Hash-check sanity mode. **§Phase 4 MIGRATION.md reader** (Q6 most-ambitious option) — for each user-affected breaking change, surfaces "Show me how к fix" / "Skip for now" / "Cancel walk"; NEVER auto-applies fixes. Restart-session warning always emitted.

```
/geniro:update
/geniro:update --dry-run                     # preview without invoking update
```

## Skills deleted in M4 redesign

The pre-M4 surface had 18 skills. The current 11-skill set absorbed or dropped 8:

| Deleted | Replacement |
|---|---|
| `/geniro:brainstorm` | Merged → `/geniro:plan` (M5) |
| `/geniro:decompose` | Merged → `/geniro:plan` (M5, milestones as output mode) |
| `/geniro:follow-up` | Absorbed → `/geniro:implement` (handles any size via spec input) |
| `/geniro:deep-simplify` | Optional `--simplify` flag on `/geniro:review` (M6) |
| `/geniro:features` | Manual `_FEATURES.md` или via `/geniro:plan` |
| `/geniro:learnings` | Auto-step в `/geniro:implement` Phase 3 + every pipeline skill |
| `/geniro:cleanup` | Dropped — niche |
| `/geniro:vendor` | Dropped — no cloud-runner requirement |

## Safety Hooks

All hooks run automatically after installation. Per-project bypass via `.geniro/safety.json`.

| Hook | Protection |
|------|-----------|
| **File protection** | Blocks writes к `.env`, `*.key`, `*.pem`, lock files, credentials, `*.tfstate`, `*.vault*` |
| **Git guardrails** | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch |
| **`.geniro/` deletion guard** | Blocks bulk `rm -rf .geniro/`, `git worktree remove`, `git add -f` on `.geniro/` paths |
| **Session-start restore** (M3) | `SessionStart` hook (`matcher: "compact\|resume\|startup"`) re-injects active task state.md + L4 instructions trio + CLAUDE.md so context survives compaction |
| **Evidence-on-completion** | `Stop` hook (warn-only) — scans last assistant message for completion phrases that lack an Evidence Block |
| **TDD-order enforcement** | PreToolUse `Edit\|Write` (hard-block) — when TDD state shows phase=RED, blocks edits к production-code files |
| **State-helper enforcement** | PreToolUse warn-mode — surfaces when а direct `Edit`/`Write` targets а canonical state path; suggests `atomic_state_write` |
| **Plan-mode write-guard** (M5) | PreToolUse hard-block — restricts Writes к `.geniro/planning/**` and `.geniro/state/**` while а `/plan` run is active |

## Updating

The plugin auto-updates via the Claude Code marketplace. To manually update:

```bash
claude plugin update geniro-claude-plugin@geniro-claude-harness
```

Or run `/geniro:update` inside Claude Code — preserves user content, walks any breaking changes in MIGRATION.md, and emits а restart-session warning. The status line shows an arrow when updates are available.

## Plugin Structure

```
geniro-claude-plugin/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # 11-skill canonical inventory
├── agents/                      # 9 specialized agent definitions
├── skills/                      # 11 reusable workflow definitions
│   ├── setup/                   # M10a AI-driven project setup
│   ├── plan/                    # M5 spec-first planning
│   ├── implement/               # M4 autonomous implementation
│   ├── review/                  # M6 multi-dim code review
│   ├── debug/                   # M7 scientific-method investigation
│   ├── refactor/                # M8 zero-behavior-change restructuring
│   ├── onboard/                 # M9 codebase mapping
│   ├── investigate/             # M9 codebase Q&A
│   ├── instructions/            # M10b L4 rules CRUD
│   ├── actions/                 # M10c workflow-helper CRUD + runner
│   ├── update/                  # M10d plugin update
│   └── _shared/                 # canonical helpers (atomic-state-write, spawn-agent,
│                                # load-custom-instructions, query/emit-learnings, etc.)
├── hooks/                       # 8 safety hooks + statusline + update check
│   ├── hooks.json               # Hook configuration
│   ├── geniro-check-update.js   # Update detection (SessionStart)
│   ├── geniro-statusline.js     # Status line renderer
│   └── *.sh                     # Safety hook scripts
├── architecture/                # M1-M10 design specs + P-X cross-cutting (e.g. P-X8 self-learning extensions)
├── CLAUDE.md                    # Plugin instructions (auto-loaded)
└── MIGRATION.md                 # Per-release breaking-change notes (consumed by /update)
```

## Credits

Patterns synthesized from analysis of: [Metaswarm](https://github.com/Chachamaru127/claude-code-harness), [GSD](https://github.com/cline/gsd), Citadel, claude-pipeline, [ECC](https://github.com/anthropics/claude-code), [SuperClaude](https://github.com/NexonAI/superclaude), Orchestrator Kit, Claude Forge, gstack, OMC, Beads, [Ruflo](https://github.com/ruvnet/ruflo), and the official Claude Code `/code-review` plugin.

## License

[Apache License 2.0](LICENSE)

---

Made with care by the [Geniro](https://github.com/geniro-io) team.
