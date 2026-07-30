# Geniro Claude Plugin

A production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks. Provides specialist subagents, skills, and safety hooks + statusline + update check out of the box.

Built and maintained by the [Geniro](https://github.com/geniro-io) team.

## Install

```bash
claude plugin marketplace add geniro-io/geniro-claude-harness
claude plugin install geniro --scope user
```

### Upgrading from v4.x — reinstall required

v5.0.0 renames the plugin `geniro-claude-plugin` → `geniro`, so commands render as `/geniro:plan` instead of the doubled `/geniro-claude-plugin:geniro:plan`. `claude plugin update` resolves ids exactly and cannot migrate across a rename, so an existing install needs replacing once:

```bash
claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
claude plugin marketplace update geniro-claude-harness
claude plugin install geniro@geniro-claude-harness --scope user
```

Restart the session afterward. Project files under `.geniro/` — instructions, actions, planning artifacts, learnings — are untouched.

`--scope user` installs the plugin globally so it's available in every directory (this is the default, but pinning it keeps the install global). Avoid `--scope project` for the plugin itself — a project-scoped install loads only inside that one project, and on the next update it can shadow the global install record and make the plugin disappear from your other directories. To share the marketplace with teammates instead, use the project-scoped marketplace config below — not a project-scoped plugin install.

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
2. **Run setup** — analyzes your stack and generates a tailored thin-map `CLAUDE.md`:
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
5. **Implement** — consumes the spec.md (or inline-task if /plan wasn't run), 3-phase autonomous loop:
   ```
   /geniro:implement
   ```
6. **Review your work** before shipping:
   ```
   /geniro:review
   ```

From there, pick the right skill for each task: `/geniro:debug` to investigate bugs (authors a fix proposal + reproduction test, escalates to `/geniro:implement` to ship), `/geniro:refactor` for zero-behavior-change restructuring, `/geniro:investigate` for codebase Q&A.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for all design decisions — state tiers, memory layers, per-skill rulings, and operational rules.

## How it works

The plugin itself ships globally — agents, skills, and hooks live inside the installed plugin and never pollute your repo. The only thing written into your project is a single `.geniro/` directory that acts as the working memory across sessions:

```
.geniro/
├── planning/               # specs, plans, _CODEBASE_MAP.md, _FEATURES.md, _project.md, _focus-*.md
│   └── <task-dir>/         # task-bound: spec.md, plan.md, state.md, milestone-N.md
├── state/                  # session-bound + handoff
│   ├── <skill>/<slug>/state.md  # /debug, /refactor, /onboard, /investigate, /resolve
│   ├── setup/state.md      # /setup singleton
│   └── handoff/            # inter-skill: from-<producer>-<branch>.md
├── knowledge/              # learnings.jsonl (L2 episodic) + session summaries
├── instructions/           # L4 procedural: global.md, memory.md, code-style.md,
│                           # per-skill.md, review-extra/<slug>.md
├── actions/                # T3 user-authored workflow helpers (Slack/PR/release)
└── workflow/               # optional integrations (issue tracker, PR flow)
```

`.geniro/` is gitignored by default, except `workflow/`, `instructions/`, and `actions/` which are meant to be committed so the team shares the same rules and integrations.

### Model tier symmetry

Every plugin subagent inherits your orchestrator's model tier by default. If you're running Claude Code on Opus, your code reviewers run on Opus. If you're on Sonnet for cost control, your reasoning subagents run on Sonnet. You set the tier once at session start with `/model`; the plugin doesn't second-guess. The carve-outs are explicit safety/cost contracts documented in `skills/_shared/model-tiering.md`: the `test-runner-agent` and `knowledge-retrieval-agent` pin Sonnet (purely mechanical work), and the `/geniro:setup` verification subagent pins Sonnet because its workload is a fixed check-and-report the orchestrator re-decides from (its read-only floor is stated in the spawn prompt — the Agent tool has no per-spawn tool allowlist).

### Typical workflow

```
  /geniro:plan  →  /geniro:implement  →  /geniro:review
  (spec-first      (3-phase autonomous     (multi-dim code review
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
- **Knowledge accumulates + auto-prunes** — every pipeline + discovery skill auto-emits L2 entries to `knowledge/learnings.jsonl`. Types: `discovery` / `pitfall` / `diagnosis` / `convention` / `decision`, plus `discarded_hypothesis` (/debug Phase 1 ELIMINATED hypotheses), `retry_failure_sequence` (/implement, /debug, /refactor when retry_count >= 2), `user_rejected_suggestion` (any skill, AUQ rejection signal). Future runs query before investigating; `query-learnings --score-min N` ranks by recency x trust x access x recurrence. **Auto-archive on SessionStart** (default ON, opt-out via `safety.json memory.auto_archive_stale: false`): flips `deprecated: true` on entries matching `age > 180d AND score < 0.1 AND access_count == 0` — never deletes (audit trail). Hash-gated to skip unchanged runs; mkdir-locked for multi-tab safety.
- **Rules persist** — `/geniro:instructions` manages `.geniro/instructions/`, and every relevant skill applies the canonical loader at `skills/_shared/load-custom-instructions.md` on every run (Step 0 + phase-boundary refresh) to read `global.md` + `memory.md` + per-skill file + `code-style.md`, with an observable echo line after each Read (so "always use snake_case for DB columns" only has to be said once, and you can SEE that the rules were loaded). Instruction files carry typed sections: `## Rules` (standing constraints), `## Additional Steps` → `### After <phase>` (project-specific steps run at a skill phase boundary — e.g. duplicate an approved plan into OpenSpec), `## Constraints` (hard gates), `## Data Sources` (read-only sources to cross-check facts against), and `## Memory Backend`. Ask `/geniro:instructions` in plain English ("run X after ship", "verify status from my DB", "store learnings in my MCP") and it fills the right section.
- **Memory is pluggable** — by default agent learnings (L2) live in `.geniro/knowledge/learnings.jsonl`. To route them through a custom backend — a memory MCP, a vector store, a knowledge graph — add a `## Memory Backend` block to the dedicated `memory.md` file (via `/geniro:instructions` — its own scope, kept separate from behavioral rules) naming the `write` + read-only `read` MCP tools (or actions) and a `mode` (`mirror` = keep the local file too, the default; `replace` = backend only). The orchestrator routes the `emit-learning` / `query-learnings` call-sites through the declared backend, redacting before any external store, read-only-screened and fail-open to the local file (`skills/_shared/memory-backend.md`).
- **State survives compaction** — long pipelines checkpoint to T1 state files (`<task-dir>/state.md` or `state/<skill>/<slug>/state.md`); the SessionStart hook re-injects them after every `compact|resume|startup` event. Within-skill state files are slug-scoped per `skills/_shared/within-skill-state-handoff.md` so parallel sessions on different branches don't clobber each other.

### Custom instructions from an external directory

By default the plugin reads your custom instructions — `global.md`, `code-style.md`, and per-skill files like `implement.md` — from `.geniro/instructions/` in your repo. For clean fresh-clone or ephemeral environments where you don't want to commit those files, point the plugin at a directory **outside** the repo instead. Two ways to set it, highest precedence first:

**1. Environment variable (recommended)** — the reliable channel: the plugin reads it from the shell environment its Bash steps run in, so it always takes effect. Best for CI / per-environment setup:

```bash
export GENIRO_INSTRUCTIONS_DIR=/etc/geniro/instructions
```

**2. Plugin install option (convenience)** — when you enable the plugin, Claude Code prompts for an `instructions_dir` (a directory), which it exports as `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_DIR`. Point it at your external folder; the plugin uses it whenever the environment variable above is unset. If it doesn't take effect for instruction loading in your runtime, set `GENIRO_INSTRUCTIONS_DIR` instead — that channel always works.

The directory holds the instruction files **flat** — no `.geniro/instructions/` subpath:

```
/etc/geniro/instructions/
├── global.md
├── code-style.md
├── implement.md
└── review.md
```

When an external directory is active it **replaces** the in-repo `.geniro/instructions/` (the two are not merged), and only the skills read from it — editing the files with `/geniro:instructions` still updates the in-repo copy, which you manage yourself. If the configured path is missing, the plugin warns and falls back to the in-repo default, so a bad path never blocks a run.

## Skills (13 total)

### `/geniro:setup` — AI-driven project setup

4-phase singleton bootstrap (Detect → Interview → Generate → Validate). Scans codebase via lockfile/config presence; interviews you for preferences that can't be auto-detected; generates a **thin-map** CLAUDE.md (tech stack / commands / conventions / domain context). To keep it thin, every inline section has to justify why it belongs in CLAUDE.md rather than in a doc of its own. Phase 4 verification subagent + 3-retry escalation loop. L2 `discovery` emit on done.

```
/geniro:setup
```

### `/geniro:plan` — Spec-first planning

12-phase loop (mode-detect → problem-discovery (`--prd` only) → explore → visual-companion → clarify (uncapped grill, checkpoint-bounded) → 2-3 approaches → grouped approval → write → mechanical validate → spec-challenge → user approve → handoff). Produces an approved `spec.md` in `.geniro/planning/<task-dir>/` with goal-state frontmatter (budget / checkpoints / forbidden_actions / approval_required_for) and optional `workflow_refs[]` tracker linkage. Phase 2 Visual Companion for UI-shaped tasks previews the UI before any code is written — a text description, or, when the plan artifact is on, a rendered HTML mockup published onto the plan page with a short text summary beside it, revised through the same approve/rewrite loop; Phase 5 groups section approval into 3 dependency-ordered cluster gates (Goal & scope / Approach & steps / Safety & done) instead of one prompt per section — each cluster authored as a unit and rendered to a full chat message in a friendly visual language (a progress tracker showing where you are in the approval journey, a one-sentence summary of what you're deciding, an in/out scope map / steps flow diagram / done-condition checklist, and plain-English per-section explanations with evidence cites), then gated by ONE lean AskUserQuestion per cluster (Approve all / Explain a section further / Revise specific sections / Cancel — Explain gives a deeper walkthrough before you decide); the chat message is the rendering surface (the AUQ `preview` side-box is too small for digests, code, and diagrams), which drops the questions you answer at Phase 5 from ~11 to 3. Phase 3 asks clarifying questions one at a time (uncapped, bounded by a checkpoint). Phase 4 stress-tests the generated approaches with independent codebase-grounded critic agents (tier-scaled) before recommending one, so the Recommended marker reflects feasibility evidence rather than the author's confidence. An optional `--artifact` flag builds a live, collapsible visual artifact of the plan and publishes it to a private claude.ai page that updates as the plan develops (native-only). Milestone-mode for Big tasks emits sibling `milestone-N.md` files.

```
/geniro:plan add user authentication with JWT tokens
/geniro:plan migrate from Sequelize to Prisma
```

### `/geniro:implement` — Autonomous implementation

3-phase loop: Analyze → Implement → Self-review-and-Ship. Consumes `spec.md` from `/plan` (or inline-task fallback when `/plan` hasn't been run). Phase 1 fires Step 0 workspace AUQ (passive-detect → auto-continue when prior-task signals present), spawns Knowledge-Retrieval + Codebase-Explorer subagents in parallel for research. Phase 2 uses TodoWrite for sequential decomposition (one-in-progress invariant) + `test-runner-agent` at phase end. Phase 3 spawns the reviewer-agent set + 1 `adversarial-tester-agent` in parallel (adversarial skipped on trivial scope); low-priority findings never force fix rounds — after the loop converges, a minor-findings gate asks whether to fix them now or leave them listed in the ship report. When the run wrote or changed tests, Phase 3 then runs an always-on (skip-when-clean) test-quality gate that surfaces the audit of those tests — does each test assert everything it claims, does every spec-required behavior have a covering test, are any tests redundant or weakly asserted — as a visible decision before Ship (advisory; no extra agent). Consumes T2 handoffs from `/review` and `/debug`, gating Edit/Write transitions on unresolved `open_questions[]`; questions that need your decision render as self-contained visual explanations in chat before a lean question. Ship cleanup preserves durable T1.5 artifacts (spec.md / state.md / milestone-*.md). All subagents inherit orchestrator tier.

```
/geniro:implement                              # consume spec.md from /plan
/geniro:implement add a CHANGELOG entry        # inline-task fallback
```

### `/geniro:review` — Parallel multi-agent code review

Reporter loop — six numbered phases plus a mechanical pre-pass (triage → mechanical pre-pass → LLM reviewers → filter → stratify → persist → action-gate). **MANDATORY spawn list:** always-fire (bugs / security / architecture / tests / optimizations / conventions / regressions — conventions covers style rubrics, repo-modal patterns, and authored-rule citations when the repo has rule files) + conditional (design when UI files present / pr-metadata when input was a PR ref / spec-compliance when PLAN CONTEXT non-none AND the input was a PR ref or the change is high-risk) + N custom from `.geniro/instructions/review-extra/`. Phase 2 declares `spawn_dims_declared[]` in state.md before the parallel batch; Phase 4 §4.0 verifies declared-vs-actual to catch silent skips. Phase 1 Step 0 smart workspace setup; /review is read-only — never mutates tracker status. Phase 1.5 mechanical pre-pass (lint / schema / secret scan + custom-reviewer discovery). Every filter survivor is independently re-verified by a fresh reviewer before it reaches you; findings that need your decision render as self-contained visual explanations in chat (what the code does, why it matters, evidence, your options — with a progress tracker across the decision queue) before a lean question; Phase 5.3 auto-emits `pitfall` L2 entries on cross-reviewer convergence ≥3. Emits a handoff with structured `open_questions[]` (3-gate chain prevents posting or implementing with unresolved questions). Whenever the review finds bugs a test can confirm, it offers to author failing tests for them — your approval gates the authoring, and a separate consent gate covers any commit/push of those tests; the test offer never filters the posted finding set. Optional `--deep` runs each dimension three times and majority-verifies findings where the call is contested (higher quality, higher cost). All reviewer-agents inherit orchestrator tier.

```
/geniro:review                                # review uncommitted changes
/geniro:review src/auth/ src/middleware/      # review specific files/dirs
/geniro:review HEAD~3..HEAD                   # review a commit range
/geniro:review #1234                          # PR review with draft-review posting gate
```

### `/geniro:resolve` — PR-feedback triage to fix-plan

Read-only PR-feedback triage → fix-plan producer (4-phase loop: Fetch & Triage → Analyze & Verify → Clarify → Emit). Reads an open PR's unresolved review threads (human + bot) AND failing CI checks via `_shared/pr-threads.md`; per item classifies intent, verifies it against the code, reproduces the bug-claim / CI failure, and assigns a verdict (fix / answer-only / needs-clarification / wontfix), with each fix/wontfix adversarially re-verified. Ambiguous items render as a self-contained chat explanation before a lean question. Emits a comment-keyed `spec.md` (standard schema + a `## Comment Resolution Map` section) and a handoff carrying `open_questions[]` + a `comment_resolutions[]` array, which `/geniro:implement` consumes to apply the fixes and — action-gated, at its Ship step — post the drafted replies + resolve the threads. **Never edits code, never posts to the PR** (the read-only producer boundary; `allowed-tools` omits Edit/Write).

```
/geniro:resolve #1234                         # triage an open PR's feedback into a fix plan
/geniro:resolve                               # infer the PR from the current branch
```

### `/geniro:debug` — Scientific-method bug investigation

3-phase loop (Investigate → Propose → Ship). Phase 1 observes / hypothesizes / tests / isolates root cause; Phase 2 authors a text fix proposal + F→P reproduction test (no production-source edits); Phase 3 persists T2 handoff at `.geniro/state/handoff/from-debug-<branch>.md` and escalates to `/geniro:implement`. Stall gate (5 inconclusive → AUQ); fix-fail gate (2 attempts → AUQ); decision gates render the investigation context (root cause, evidence, fix options) as a self-contained chat explanation before a lean question. Phase 3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}`. **Never ships code.**

```
/geniro:debug login returns 500 after password reset
/geniro:debug memory leak in WebSocket handler after 1000 connections
/geniro:debug tests pass locally but fail in CI on the date formatting step
```

### `/geniro:refactor` — Safe code restructuring

3-phase loop (Plan → Apply → Verify) with **zero-behavior-change guarantee**. Phase 1 classifies tier via canonical `_shared/effort-scaling.md` (Trivial / Small / Medium / Big); runs orchestrator-inline smell detection per `_shared/refactor-patterns.md`. Phase 2 runs orchestrator-inline per-step execution with per-step regression check + Blocked Step Protocol (3 retries → revert + continue). Phase 3 runs independent reviewer + custom reviewers; PRODUCT-DECISION → ESCALATE to /implement (4-option ADR-aware AUQ, rendered as a self-contained explanation in chat first); HIGH-risk steps are approved from a rendered steps-flow + per-step risk summary. Auto-emits L2 `discovery` + `pitfall`. **Never ships code** — diff IS the deliverable; user commits manually or runs `/geniro:implement`.

```
/geniro:refactor extract payment logic from OrderService into PaymentService
/geniro:refactor consolidate duplicate validation across controllers
/geniro:refactor convert callback-based auth module to async/await
```

### `/geniro:onboard` — Rapid codebase orientation

2-phase loop (Discover → Map). Scans codebase structure and produces `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` with the canonical 8-section template (underscore-prefixed L3 registry). Phase 1 applies a <=50-file scan cap (user-confirmable expansion via AUQ). Phase 2 calls `update-semantic` (bounded auto-incremental L3 write), emits L2 `discovery`, prints next-step suggestions (/plan / /investigate / /implement / `_FEATURES.md`). `--focus` / `--depth` retained as scope-limiters on the full 8-section template; `--cap N` raises the 50-file read budget.

```
/geniro:onboard
/geniro:onboard --focus api
```

### `/geniro:investigate` — Deep codebase Q&A

3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present). Phase 1 classifies $ARGUMENTS into 9-type taxonomy + 5-step JIT retrieval cadence; pure external "docs lookup" questions suggest the native `/deep-research` workflow instead, while anything needing code or git evidence stays here. Phase 2 spawns 1-3 parallel research agents (Codebase Analyst / Git Historian / Internet Researcher — literal classified set, never over-spawned). Phase 3 synthesizes, spawns fresh reviewer-agent, presents with Sources + Open questions, fires save-routing AUQ (CLAUDE.md / ADR / learnings.jsonl). L2 `discovery` emit with trust label (`verified` if code-grounded; `retrieved` if WebFetch/WebSearch load-bearing). **Never ships code.**

```
/geniro:investigate how does the caching layer invalidate stale entries?
/geniro:investigate what happens when a WebSocket connection drops mid-transaction?
/geniro:investigate why was the ORM switched from Sequelize to Prisma?
```

### `/geniro:reflect` — Session-history rule mining

On-demand session-history miner, in three input shapes. Empty selects the recent work-bearing sessions and a search string grep-matches the sessions that mention it — both locate past Claude Code transcripts on disk and spawn one read-only analyst per session. `--this-session` mines the session you are running in instead: nothing is read from disk, and the corrections are extracted inline because the running session lives only in the orchestrator's context. All three then synthesize one reflection-agent pass against the candidate bar + prior declines, so the judgment stays in an isolated agent either way. Approved candidates route per the improvement-routing ladder (CLAUDE.md / `.claude/rules/` / `.geniro/instructions/` / learnings); declines are recorded so they stop re-surfacing. Stateless and read-only; zero candidates is a valid outcome. Mining past transcripts needs Claude Code's on-disk layout; `--this-session` reads no transcript and runs anywhere.

```
/geniro:reflect
/geniro:reflect ci-flakiness            # grep-match sessions touching a topic
/geniro:reflect --this-session          # mine the corrections from this running session
```

### `/geniro:instructions` — Custom instruction management

3-phase stateless CRUD (parse → execute → done) over `.geniro/instructions/`. 5 operations: list / create / edit / validate / delete. 13-scope set: `global`, `code-style`, `memory`, `review-extra/<slug>`, and per-skill (`implement`, `plan`, `review`, `resolve`, `debug`, `refactor`, `onboard`, `investigate`, `reflect`). `validate` mode: structural + reference + per-scope lint with CRITICAL/HIGH/MEDIUM/LOW severities; catches refs to dropped skills and outdated phase names.

```
/geniro:instructions list
/geniro:instructions create implement
/geniro:instructions create review-extra sql-bindings    # add a custom code-review dimension
/geniro:instructions validate
/geniro:instructions delete debug
```

### `/geniro:actions` — Custom workflow-helper management

3-phase stateless CRUD + runner over `.geniro/actions/`. 6 operations: list / create / edit / run / delete / validate. `risk_class: low | medium | high` mandatory frontmatter field; run mode executes the action directly with no confirmation gate — invoking it is the authorization, and `risk_class` is metadata for the list view, delete warning, and lint. `validate` mode shares the rule set with `/instructions validate review-extra`. L2 `discovery` emit on successful runs with `external-send: true`.

```
/geniro:actions list                                       # show all custom actions
/geniro:actions create pr-notify-slack                     # interview-driven scaffold
/geniro:actions edit pr-notify-slack                       # external edit + re-validate
/geniro:actions run pr-notify-slack 1234                   # invoke by exact slug + args
/geniro:actions run "post release notes k slack"          # invoke by free-text (picker)
/geniro:actions pr-notify-slack 1234                       # bare-slug fast path (defaults to run)
/geniro:actions validate                                   # lint all .geniro/actions/*.md
/geniro:actions delete pr-notify-slack
```

When invoked from a linked git worktree, `run` falls back to the main worktree's registry (with confirmation); `edit`/`delete` operate on the main-repo copy (with the delete confirmation; a lean question appears only when a differing branch-local copy also exists).

### `/geniro:update` — Update plugin

4-phase stateless loop (Pre-check → Update → Post-check → Migration). Pre-update version-confirm AUQ. User-content snapshot at Pre-check + survival diff at Post-check (catches silent corruption). 4-retry exponential backoff (2s/4s/8s/16s) on network errors. Hash-check sanity mode. **Phase 4 MIGRATION.md reader** — for each user-affected breaking change, offers "Fix it for me (Recommended)" / "Show me how to fix" / "Skip for now" / "Cancel walk"; "Fix it for me" runs only the maintainer-written `Auto-fix:` command for that entry, then re-verifies. Restart-session warning always emitted.

```
/geniro:update
/geniro:update --dry-run                     # preview without invoking update
```

## Flags & presets

Some skills take flags and modifiers that change how a run behaves. Most answer a setup question in advance so the run starts without stopping; a couple do the opposite and add a check-in the default run does not have; a few change what the run does and ask nothing either way. None of them touches the safety gates (adopting a new dependency, blowing past the planned scope, unresolved questions from a prior review, a real merge conflict, pushing to a shared branch) — those always stop for you regardless of any flag.

- **`/geniro:plan`** — `--prd` (run a problem-first discovery interview), `--deep` (wider approach search + claim verification), `--artifact` (build a live visual plan page). Plan also accepts the implement launch modifiers (`worktree` / `no-worktree` / `current-branch` / `new-branch`, the ship choices `commit only` / `draft only` / `ready-for-review` / `stop after review`, and `freshness:merge|rebase|skip`) and saves them into the spec so `/geniro:implement` runs hands-free.
- **`/geniro:implement`** — workspace (`new-branch` / `current-branch` / `worktree` / `no-worktree`), `--deep` (deeper self-review + pre-edit fact-check), `--no-adversarial`, and ship choices (`don't push` / `draft only` / `ready-for-review` / `stop after review`). A spec written by `/plan` can pre-answer the setup choices among these at once.
- **`/geniro:review`** — `--deep` (multi-angle review + extra verification), `--plan <path>` (check the diff against a spec), and the workspace modifiers.

Full catalog for `/geniro:plan`, `/geniro:implement` and `/geniro:review` — every flag, the values it takes, and how it changes where the run stops to ask you something — in [`skills/_shared/flags-reference.md`](skills/_shared/flags-reference.md); that file covers those three skills only. Flags on the other skills are declared in each skill's `argument-hint` and documented in its body (e.g. `/geniro:debug --deep`).

## Skills deleted

The current skill set absorbed or dropped 8 earlier skills:

| Deleted | Replacement |
|---|---|
| `/geniro:brainstorm` | Merged → `/geniro:plan` |
| `/geniro:decompose` | Merged → `/geniro:plan` (milestones as output mode) |
| `/geniro:follow-up` | Absorbed → `/geniro:implement` (handles any size via spec input) |
| `/geniro:deep-simplify` | Dropped — covered by `/geniro:review` standard dimensions |
| `/geniro:features` | Manual `_FEATURES.md` or via `/geniro:plan` |
| `/geniro:learnings` | Auto-step in `/geniro:implement` Phase 3 + every pipeline skill |
| `/geniro:cleanup` | Dropped — niche |
| `/geniro:vendor` | Dropped — no cloud-runner requirement |

## Safety Hooks

All hooks run automatically after installation. Per-project bypass via `.geniro/safety.json`.

| Hook | Protection |
|------|-----------|
| **File protection** | Blocks writes to `.env`, `*.key`, `*.pem`, lock files, credentials, `*.tfstate`, `*.vault*` |
| **Git guardrails** | Blocks destructive git: force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, update-ref -d, filter-branch, remote-branch deletion (`git push --delete` / colon-refspec, bypass `push-delete`) |
| **`.geniro/` deletion guard** | Blocks bulk `rm -rf .geniro/`, `git worktree remove`, `git add -f` on `.geniro/` paths |
| **Session-start restore** | `SessionStart` hook (`matcher: "compact\|resume\|startup"`) re-injects active task state.md + L4 instructions set + CLAUDE.md so context survives compaction |
| **Evidence-on-completion** | `Stop` hook (warn-only) — scans last assistant message for completion phrases that lack an Evidence Block |
| **TDD-order enforcement** | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` (hard-block) — when TDD state shows phase=RED, blocks edits to production-code files, including shell-side writes |
| **State-helper enforcement** | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` (hard-block) — blocks direct writes to canonical state paths under `.geniro/`, including Bash-side writes (redirection, `tee`, `sed -i`, `cp`/`mv`, `dd of=`); suggests `atomic_state_write` / `atomic_state_append` |
| **Security pattern scan** | PreToolUse `Edit\|Write\|MultiEdit\|NotebookEdit` AND `Bash` (hard-block) — regex scan of edit content and shell commands for high-signal security anti-patterns: `eval`/`exec`, pickle, unsafe `yaml.load`, `shell=True`, `curl \| sh`, TLS bypass, XSS sinks, weak hashes |
| **Gate-render enforcement** | PreToolUse `AskUserQuestion` (hard-block) — blocks a question that references content "above" OR carries finding-gate evidence shorthand (a PRODUCT-DECISION tag, convergence wording, or a finding-ID like `F5`/`M1b`) when no visible message precedes it in the turn, so decision gates can't fire blind |

## Updating

The plugin auto-updates via the Claude Code marketplace. To manually update:

```bash
claude plugin update geniro@geniro-claude-harness
```

Or run `/geniro:update` inside Claude Code — preserves user content, walks any breaking changes in MIGRATION.md, and emits a restart-session warning. The status line shows an arrow when updates are available.

## Using with Cursor

The repository doubles as a Cursor plugin: `.cursor-plugin/plugin.json` shares `skills/` with Claude Code and points Cursor at its own agent and hook ports under `cursor/` (`cursor/agents/` — generated Cursor-frontmatter copies of the 7 agents; `cursor/hooks.json` — the safety and session-restore hooks adapted through `cursor/hooks/claude-hook-shim.sh`). Install by symlinking the repo to `~/.cursor/plugins/local/geniro` or importing it as a team-marketplace plugin. Full install steps, what works, and what stays Claude-Code-only (`/reflect`'s past-session shapes, `/update`, structured decision gates): [`cursor/README.md`](cursor/README.md).

## Plugin Structure

```
geniro/
├── .claude-plugin/
│   ├── plugin.json              # Plugin manifest
│   └── marketplace.json         # Marketplace manifest (plugin source entry)
├── agents/                      # 7 specialized agent definitions (reviewer / adversarial-tester / knowledge-retrieval / codebase-explorer / codebase-research / reflection / test-runner)
├── skills/                      # 13 reusable workflow definitions
│   ├── setup/                   # AI-driven project setup
│   ├── plan/                    # spec-first planning
│   ├── implement/               # autonomous implementation
│   ├── review/                  # multi-dim code review
│   ├── resolve/                 # PR-feedback triage → fix plan
│   ├── debug/                   # scientific-method investigation
│   ├── refactor/                # zero-behavior-change restructuring
│   ├── onboard/                 # codebase mapping
│   ├── investigate/             # codebase Q&A
│   ├── reflect/                 # session-history rule mining
│   ├── instructions/            # L4 rules CRUD
│   ├── actions/                 # workflow-helper CRUD + runner
│   ├── update/                  # plugin update
│   └── _shared/                 # canonical helpers (atomic-state-write, spawn-agent,
│                                # load-custom-instructions, query/emit-learnings, etc.)
├── hooks/                       # 9 safety hooks + statusline + update check
│   ├── hooks.json               # Hook configuration
│   ├── geniro-check-update.js   # Update detection (SessionStart)
│   ├── geniro-statusline.js     # Status line renderer
│   └── *.sh                     # Safety hook scripts
├── lib/                         # shell helpers the skills and hooks source
│                                # (atomic-state-write, validate-state-file,
│                                # emit/query-learnings, load/update-semantic, ...)
├── .cursor-plugin/plugin.json   # Cursor manifest (shares skills/, points at cursor/)
├── cursor/                      # Cursor runtime port
│   ├── agents/                  # generated Cursor-format agents (scripts/build-cursor-agents.sh)
│   ├── hooks.json               # Cursor hook wiring (camelCase events)
│   └── hooks/claude-hook-shim.sh# Cursor→Claude hook I/O adapter
├── ARCHITECTURE.md              # Consolidated design decisions (state/memory/skills)
├── CLAUDE.md                    # Plugin instructions (auto-loaded)
└── MIGRATION.md                 # Per-release breaking-change notes (consumed by /update)
```

## Credits

Patterns synthesized from analysis of: [Metaswarm](https://github.com/Chachamaru127/claude-code-harness), [GSD](https://github.com/cline/gsd), Citadel, claude-pipeline, [ECC](https://github.com/anthropics/claude-code), [SuperClaude](https://github.com/NexonAI/superclaude), Orchestrator Kit, Claude Forge, gstack, OMC, Beads, [Ruflo](https://github.com/ruvnet/ruflo), and the official Claude Code `/code-review` plugin.

## License

[Apache License 2.0](LICENSE)

---

Made with care by the [Geniro](https://github.com/geniro-io) team.
