# Geniro Plugin

Production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions

## Available Skills

The current skill set is 11 skills. The 8 deleted skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) have their replacements documented in the right-hand column; their `skills/` directories have been removed.

| Skill | Purpose |
|-------|---------|
| `/geniro:plan` | Spec-first planning — turn a vague idea or feature request into an approved `spec.md` via a 10-phase loop (mode-detect → explore → visual-companion → clarify ≤5 questions → 2-3 approaches → 10-section approval → write → mechanical validate → user approve → hand-off). Fixed 10-section schema; goal-state frontmatter (budget / checkpoints / forbidden_actions / approval_required_for / tools_required); compaction-safe `approvals[]`. Spec frontmatter gains optional `workflow_refs[]` (m5-v2) — tracker linkage (Linear/Jira/GitHub-Issues/Asana) persists from Phase 1 fetch through Phase 6 write; downstream skills read it for priming context. Phase 2 Visual Companion fires only when UI files / topic UI noun triggers (calls `_shared/ui-preview-gate.md`); approved description feeds Phase 5 sections 6 + 9. Per-section AUQs use the AskUserQuestion `preview` field — every option renders concrete content (UI ASCII / code snippet / behavior trace) rather than prose-only `Approve/Revise/Skip`; Phase 3 + Phase 4 options also carry `preview`. Section authoring is incremental (section N → AUQ → on approve, author N+1) — no pre-fill batch. Phase 7 validator runs the full check set (adds `workflow_refs_consistency`). Milestone-mode (Phase 5) emits sibling `milestone-N.md` files for Big tasks (absorbs deleted `/decompose`). NO auto-commit — commit fires at Phase 8 post-approve. |
| `/geniro:implement` | 3-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Consumes spec.md from `/plan` (or inline-task fallback when `/plan` hasn't been run yet). Phase 1 fires Step 0 workspace AUQ (passive-detect → decision tree; smart auto-continue when prior-task signals present), then spawns Knowledge-Retrieval + Codebase-Explorer subagents in parallel for research (replaces orchestrator-inline 17-file Phase-1 sweep). Phase 2 uses TodoWrite for sequential decomposition (one-in-progress invariant) + `test-runner-agent` at phase end. Phase 3 spawns the reviewer-agent set + 1 `adversarial-tester-agent` in parallel (adversarial skipped on trivial scope per Codebase-Explorer `change_scope`). Consumes T2 handoffs from `/review` and `/debug`, gating Edit/Write transitions on unresolved `open_questions[]`. Ship cleanup preserves durable artifacts (T1.5 tier — spec.md / state.md / plan-*.md / milestone-*.md). All subagents inherit orchestrator tier (OMIT `model=` at every spawn site). Absorbs post-ship tweaks from the legacy `/follow-up`. |
| `/geniro:review` | 6-phase reporter loop (triage → mechanical pre-pass → LLM reviewers → filter → stratify → persist → action-gate). **MANDATORY spawn list** — always-fire (bugs/security/architecture/tests/optimizations/guidelines/conventions/regressions) + conditional (design when UI files present / pr-metadata when input was a PR ref / spec-compliance when PLAN CONTEXT non-none AND (PR ref OR risk-tier:high)) + N custom from `.geniro/instructions/review-extra/`. The `regressions` dim catches unintended deletes + behavior changes outside stated intent via 3 signals (deleted-symbol caller-blast / intent-vs-behavior over-reach / test-coverage delta). Phase 2 step 2.2 declares `spawn_dims_declared[]` in state.md frontmatter BEFORE the parallel batch; Phase 4 §4.0 runs a post-spawn verification gate (declared-vs-actual diff). Phase 1 Step 0 smart workspace setup (passive-detect → AUQ when ambiguous; /review is read-only — never mutates tracker status; that is `/plan` and `/implement` territory). Phase 1.5 mechanical pre-pass (lint / schema / secret scan + custom-reviewer discovery) feeds prior-context to LLM reviewers. Phase 5b auto-emits `pitfall` L2 entries on cross-reviewer convergence ≥3 (absorbs deleted `/learnings`). Optional `--simplify` flag prepends Reuse/Quality/Efficiency criteria to (architecture / conventions / guidelines / bugs / optimizations) dimensions (absorbs deleted `/deep-simplify`). Phase 4.1 admits findings via a multi-signal gate: `severity >= MEDIUM` AND any-of {`convergence_count >= 2`, `Evidence-Block present + confidence >= 60`, criteria-pre-resolved marker, `confidence >= 80` advisory fallback} — replaces the legacy single-threshold filter (Claude self-confidence is documented as miscalibrating; canonical taxonomy with INCLUDES + EXCLUDES per tier lives at `skills/review/severity-calibration-reference.md`; documentation/PR-description suggestions are explicitly LOW). Phase 4.2 spawns one fresh `reviewer-agent` per HIGH-severity survivor (no tier-scaling — ALL HIGHs verified) in verify-finding mode; refuted findings demote to `## Filtered` before §4.3. Schema bumped to `m6-v2` (per-finding body carries `Validation` / `Recommended-action` / `Verification-confidence` / `Verification-evidence`; legacy `m6-v1` accepted with `confirmed + warn` fallback). Optional `--tdd` flag tightens Phase 4.3 F→P test-gate. Emits T2 hand-off at `.geniro/state/handoff/from-review-<branch>.md` with structured `open_questions[]` (status: unresolved \| resolved \| wontfix) — 3-gate chain (Phase 6 Pre-gate / Pre-Post PR guard / Consumer-side `/implement` Phase 1 Step 12) prevents posting or implementing with unresolved questions. Stratifies on hard-escalation signals from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`; inherits prior-round findings across re-runs (max 3 rounds before escalate-AUQ). **Phase 1 workflow integrations** read `.geniro/workflow/*.md` (mirrors /implement plumbing) — on Linear match with MCP available, fetches issue + parent epic + sibling sub-tasks; `LINEAR CONTEXT:` block fed to (spec-compliance + pr-metadata + architecture + regressions); fail-open if MCP unregistered. **Phase 1 peer-PR scout** top-3→top-10 candidates with `linear_bonus` ranking (+2 for parent-epic / sibling-sub-task PRs), per-sibling 200-line cap, 5K total cap; fed to (architecture + design + bugs + conventions + optimizations + spec-compliance + regressions). All reviewer-agents inherit orchestrator tier (OMIT `model=`). |
| `/geniro:debug` | 3-phase scientific-method investigation (Investigate → Propose → Ship) mirroring `/implement`. Phase 1 observes / hypothesizes / tests / isolates root cause; Phase 2 authors text fix proposal + F→P reproduction test (no production-source edits); Phase 3 persists T2 hand-off at `.geniro/state/handoff/from-debug-<branch>.md` with structured `open_questions[]` (Pre-gate fires FIRST in Phase 3 — never escalates with unresolved entries) and escalates to `/geniro:implement`. Reads spec.md frontmatter `workflow_refs[]` at Phase 1 entry when `$ARGUMENTS` points to spec or task-dir (cached tracker `status` primes hypotheses; read-only). State.md uses session-bound subdir layout `.geniro/state/debug/<slug>/state.md` + compaction-safe `approvals[]`. Stall gate (5 inconclusive → multi-component AUQ) + fix-fail gate (2 attempts → AUQ). Phase 3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}` (absorbing the legacy `/learnings` cadence for debug); L4 promotion suggestion fires when recurrence detected. Adversarial Mode (verify-changes) preserved as parallel workflow — authors F→P RED tests via `adversarial-tester-agent` (inherits orchestrator tier — OMIT `model=`), persists to `from-debug-adversarial-<branch>.md`. NEVER ships code (no `git push` / `gh pr create`). |
| `/geniro:refactor` | 3-phase loop (Plan → Apply → Verify) mirroring `/implement`. Zero-behavior-change guarantee. Phase 1 loads L4/L3/L2, reads spec.md frontmatter `workflow_refs[]` when `$ARGUMENTS` points to spec or task-dir (cached tracker `status` primes scope decisions; read-only), classifies tier via canonical `_shared/effort-scaling.md` (Trivial / Small / Medium / Big), runs orchestrator-inline smell detection (Medium+) + orchestrator-inline smell evidence (Medium+), builds plan + HIGH-step approval AUQ. Phase 2 runs orchestrator-inline per-step execution per `_shared/refactor-patterns.md` with per-step regression + Blocked Step Protocol (3 retries → revert + mark blocked + continue) + ≥30% blocked escalation. Phase 3 runs independent reviewer-agent + custom reviewers (Medium+) — all inherit orchestrator tier (OMIT `model=`), PRODUCT-DECISION → ESCALATE to /implement (Always-WAIT, 4-option ADR-aware AUQ), CRITICAL/HIGH non-PD → 1-round fix loop. State.md uses session-bound subdir layout `.geniro/state/refactor/<slug>/state.md` + compaction-safe `approvals[]` (categories `refactor_high_step` + `refactor_product_decision`). Phase 3 auto-emits L2 `discovery` + `pitfall` (absorbs `/learnings`); L4 promotion suggestion fires. NEVER ships code (no `git push` / `gh pr create`) — diff IS the deliverable, working tree IS the channel; user commits manually or runs `/geniro:implement` to ship via review gate. |
| `/geniro:onboard` | 2-phase loop (Discover → Map) mirroring `/implement`. Scans codebase structure and produces `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` with the canonical 8-section template (underscore-prefixed L3 registry). Phase 1 applies ≤50-file scan cap (default; user-confirmable expansion via AUQ persisted to state.md `approvals[]` category `expand_scope`); empty/permission-blocked repos route to terminal `routed`/`aborted`. Phase 2 writes the map, calls `update-semantic` (bounded auto-incremental L3 write with advisory lock), emits L2 `discovery` (`trust: verified`), fires Next-step AUQ routing to /plan / /investigate / /implement / `_FEATURES.md`. State.md uses session-bound subdir layout `.geniro/state/onboard/<slug>/state.md`. `--focus` / `--depth` retained as scope-limiters on the full 8-section template. |
| `/geniro:investigate` | 3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present) mirroring `/implement`. Phase 1 classifies $ARGUMENTS into taxonomy + JIT retrieval cadence + glossary-mismatch check (with `approvals[]` category `glossary_resolve` for compaction-safe persistence). Phase 2 spawns 1-3 parallel research agents (Codebase Analyst / Git Historian / Internet Researcher — literal classified set, never over-spawned) with orchestrator re-verify of every load-bearing claim + missing-data gate AUQ. Phase 3 synthesizes draft (question-type templates), spawns fresh reviewer-agent (inherits orchestrator tier; max 1 re-review round), presents with Sources + Open questions, fires save-routing AUQ (CLAUDE.md Domain Context / ADR / learnings.jsonl / auto-memory — focused-agent workaround since /investigate has no Write tool), emits L2 `discovery` with trust label (`verified` if code-grounded; `retrieved` if WebFetch/WebSearch load-bearing). State.md uses session-bound subdir layout `.geniro/state/investigate/<slug>/state.md`. NEVER ships code (no `git push` / no `gh pr create`). |
| `/geniro:instructions` | 3-phase stateless CRUD (parse → execute → done) over `.geniro/instructions/` — the L4 procedural memory layer. operations: list / create / edit / validate / delete. scope set: `global`, `code-style`, `review-extra/<slug>` (directory-style), and per-skill (`implement`, `plan`, `review`, `debug`, `refactor`, `onboard`, `investigate`). `validate` mode: structural + reference + per-scope lint with CRITICAL/HIGH/MEDIUM/LOW severities — catches refs to dropped skills, dropped phase names, and description hygiene rules on `review-extra/<slug>.md` frontmatter. Scope-specific scaffolds on create. Chain ambiguity resolution. No subagents (CRUD too small for parallelism). NEVER ships code. |
| `/geniro:actions` | 3-phase stateless CRUD + runner over `.geniro/actions/` — user-authored workflow-helper actions (Slack/PR/release automations). operations: list / create / edit / run / delete / validate. `risk_class: low \| medium \| high` mandatory frontmatter field; create-interview includes scaffold heuristic mapping output to suggested risk class. Risk-class AUQ ladder in run mode: `low` skips AUQ, `medium` is 1-click confirm, `high` uses Cancel-as-recommended default. `validate` mode: lint rule set shared with `/instructions validate review-extra`; exit non-zero on CRITICAL/HIGH. L2 `discovery` emit on successful runs with `external-send: true` (auto-replaces dropped `/learnings`). Tool-scope intersection in run mode (action `allowed-tools` ∩ /actions `allowed-tools`). Preserved verbatim: registry index, exact-slug fast path, free-text picker, source-aware destructive-op guard, main-worktree cross-worktree confirmation. NEVER ships code (action body may; that's the action author's responsibility). |
| `/geniro:setup` | 4-phase singleton bootstrap (Detect → Interview → Generate → Validate). Singleton state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (no `<slug>/` subdir, no parallel runs). Init and re-run modes (uninstall out of scope). **Re-run mode runs a migration sweep** before generating content — reads `MIGRATION.md`, runs auto-detect for each breaking change, applies auto-fix commands silently (renames L3 files, adds missing `risk_class:` to actions, merges orphan instruction files, cleans legacy state paths, removes orphan knowledge subdirs and root-level state files), logs manual-only items to final report. Phase 1 detects tech stack via lockfile/config presence (no inference); scans project documentation; captures skill_inventory from marketplace.json or canonical skill-set fallback. Phase 2 interviews via `approvals[]`-aware AUQ batches for codebase confirmations (ambiguous detections) and optional integrations (issue tracker). Phase 3 generates project-specific CLAUDE.md (tech stack, commands, conventions, domain context — no plugin info). Phase 4 spawns verification subagent (model: sonnet; tools=[Read, Bash, Glob, Grep] — NO Write/Edit) with verification checklist; 3-retry loop → AUQ escalation. L2 `discovery` emit on Done. Generated CLAUDE.md contains only project-specific content. Restart-session warning emitted only on re-run with plugin-version delta. |
| `/geniro:update` | 4-phase stateless loop (Pre-check → Update → Post-check → Migration). Phase 1 Step 3 pre-update version-confirm AUQ (explicit gate before shell call). User-content snapshot at Pre-check + survival diff at Post-check (catches silent corruption). 4-retry exponential backoff (2s/4s/8s/16s) on network errors. Hash-check sanity mode (sentinel files; manifest-mode hook reserved for future). Phase 4 MIGRATION.md reader + walk — per-entry AUQ with "Fix it for me (Recommended)" / "Show me how" / "Skip" / "Cancel walk"; auto-fix runs maintainer-written commands from MIGRATION.md `Auto-fix:` field, then re-runs auto-detect to verify. Cancel-as-recommended AUQ pattern for hash-fail and content-tamper warnings. Restart-session warning always emitted (`/update` IS a version transition). `--dry-run` flag previews without invoking update. |

**Skills deleted:**

| Deleted | Replacement |
|---|---|
| `/geniro:brainstorm` | Merged → `/geniro:plan` |
| `/geniro:decompose` | Merged → `/geniro:plan` (milestones as output mode) |
| `/geniro:follow-up` | Absorbed → `/geniro:implement` (handles any size via spec input) |
| `/geniro:deep-simplify` | Optional flag on `/geniro:review` |
| `/geniro:features` | Manual `FEATURES.md` or via `/geniro:plan` |
| `/geniro:learnings` | Auto-step in `/geniro:implement` Phase 3 and `/geniro:debug` |
| `/geniro:cleanup` | Dropped — niche |
| `/geniro:vendor` | Dropped — no cloud-runner requirement |

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## State Files

Every state file under `.geniro/` belongs to exactly one tier and must be written through the atomic-write helpers — not direct `Edit`/`Write` calls.

| Tier | Paths | Helper |
|------|-------|--------|
| **T1 — TASK ephemeral** (transient working artifacts, targeted `rm -f` at Phase Ship cleanup) | `.geniro/planning/<task-dir>/.{kr,ce,tr,adversarial,research}-out.md` (subagent OUTPUT_PATH reports) · `.geniro/planning/<task-dir>/.research-<facet>.md` (per-facet research outputs from /plan Phase 1) · `.geniro/planning/<task-dir>/notes.md` (scratch) · `.geniro/planning/<task-dir>/playwright-verify.png` (visual-verify artifacts) | `atomic_state_write` |
| **T1.5 — TASK durable** (survives Phase Ship; design artifacts user may want to keep) | `.geniro/planning/<task-dir>/{spec,state}.md` · `.geniro/planning/<task-dir>/plan-*.md` · `.geniro/planning/<task-dir>/milestone-*.md` · `.geniro/state/<skill>/<slug>/state.md` (`/debug`, `/refactor`, `/onboard`, `/investigate`) · `.geniro/state/setup/state.md` singleton (`/setup`) | `atomic_state_write` |
| **T2 — HANDOFF** (inter-skill, overwritten by producer) | `.geniro/state/handoff/from-<producer>-<branch>.md` (carries structured `open_questions[]` for safety-gated consumer transitions) | `atomic_state_write` |
| **T3 — PERSISTENT CRUD** | `.geniro/instructions/*` · `.geniro/actions/*` · `.geniro/workflow/*` · `.geniro/planning/_*.md` · `.geniro/docs/*` (spin-out targets) | `atomic_state_write` (caller does optimistic mtime check first) |
| **T3 — PERSISTENT append-only** | `.geniro/knowledge/learnings.jsonl` | `atomic_state_append` |

**T1 vs T1.5 — Ship cleanup contract.** `/implement` Phase 3 Ship cleanup uses targeted `rm -f` on T1 files only; T1.5 files survive the ship so the user retains the spec, state log, and milestone breakdown for future reference, audit, or re-runs of `/implement` against the same task-dir. Skills that authored T1 artifacts (KR/CE/test-runner/adversarial OUTPUT_PATH reports) clean them at phase exit. Per memory rule: "when a producer adds an output field, every durable state-file schema between producer and consumer must be updated in lockstep" — schema changes propagate across producer and consumer state files.

**Helper invocation** (from inside a skill's Bash call):

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
atomic_state_write ".geniro/planning/<task-dir>/state.md" <<'EOF'
---
tier: T1
producer: implement
schema-version: 1
branch: <git-branch>
timestamp: <ISO-8601 UTC>
phase: implement
status: in-progress
non-resumable-actions: []
---

## Body
...
EOF
```

**Validation before resume:**

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-dir>/state.md"; then
  # Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
  ...
fi
```

**Full reference:**
- `skills/_shared/state-tier-spec.md` — canonical schema and per-tier required fields.
- `skills/_shared/atomic-state-write.md` — write helper, exit codes, mtime-check pattern.
- `skills/_shared/validate-state-file.md` — validator, exit codes, recovery AUQ template.

## Memory Layers

Every persisted fact lives in exactly one of four layers. Writers know **what** to record and **where**; readers know **which layer** answers a question. Anything that doesn't fit one of these layers is by definition out of scope for the memory subsystem.

| Layer | Name | Lifespan | Routing rule (writer intent → layer) | Path |
|-------|------|----------|---------------------------------------|------|
| **L1** | Working | Per-task | "Right now, phase X of task Y is running." | `.geniro/planning/<task-dir>/state.md` (T1) |
| **L2** | Episodic | Append-only event log | "In this run we observed event X." | `.geniro/knowledge/learnings.jsonl` |
| **L3** | Semantic | Current-state snapshot | "In this project, fact X is currently true." | `.geniro/planning/_*.md` |
| **L4** | Procedural | Stable rules | "When doing X, always do Y." | `.geniro/instructions/*.md` |

**Cross-layer precedence (when layers disagree): L4 > L3 > L2.** L4 is user-curated explicit rules (highest trust); L3 is drift-monitored current state; L2 is historical events with the lowest cross-layer trust. L1 is task-scoped and never conflicts cross-layer.

**Within-layer:** recency wins. L2 uses the `supersedes` chain. L3 uses fingerprint refresh / file mtime. L4 uses file mtime.

### Helper invocation

| Helper | Purpose |
|--------|---------|
| `_shared/load-custom-instructions.md` | Load L4 — `global.md` + `<skill>.md` + `code-style.md` |
| `lib/load-semantic.sh` | Load L3 — `_project.md` + `_CODEBASE_MAP.md` by default; `--extras "..."` for additional files; auto-runs fingerprint drift check to stderr |
| `lib/update-semantic.sh` | Bounded-write L3 — `--file <codebase-map\|features> --append "<line>"` or `--replace "<prefix>" "<new>"`. Per-file POSIX-O_EXCL lock; rc=11 if held |
| `lib/emit-learning.sh` | Append L2 — JSON on stdin, auto-sanitization, auto-dedup with supersede chain |
| `lib/query-learnings.sh` | Read L2 — flags: `--type`, `--tag`, `--scope`, `--min-trust`, `--score-min` (recency × trust × access ranking), `--include-superseded`, `--include-deprecated`, `--include-archive`, `--limit`. Also exports `record_access <dedup_key>` for access-count bumping |
| `lib/redact-secrets.sh` | Regex sanitization for any free-form text — called automatically by `emit_learning`; also reusable standalone |
| `lib/archive-stale.sh` | Walk `learnings.jsonl` and flip `deprecated: true` on entries matching score<0.1 + age>180d + access_count==0. Auto-runs on SessionStart (default ON, opt-out via `safety.json memory.auto_archive_stale: false`); `--dry-run` previews manually. Never deletes (audit trail). Multi-tab safe via mkdir-lock. |
| `lib/emit-rejection.sh` | AUQ-rejection L2 emit helper — exports `emit_rejection_if_signal()`; detects explicit-cancel/no/skip OR picked-non-recommended signals and emits `user_rejected_suggestion` to L2. Wired in /plan, /implement Phase 3 ship-mode, /actions run-mode. |

### Conflict surfacing protocol

When a load-* helper detects layers disagreeing, the calling skill prints a notice in its output and continues using the precedence-winning value. For **hard conflicts** (L4 rule directly contradicts L3 reality), the skill halts and calls `AskUserQuestion`. Both notice format and AUQ template live in `skills/_shared/resolve-conflicts.md`.

**Full reference:**
- `skills/_shared/redact-secrets.md` · `emit-learning.md` · `query-learnings.md` · `archive-stale.md` · `emit-rejection.md` · `load-semantic.md` · `update-semantic.md` — per-helper API contracts.
- `skills/_shared/resolve-conflicts.md` — cross-layer conflict notice format.

## Custom Agent Invocation

When a skill spawns a plugin-defined agent (`reviewer-agent`, `adversarial-tester-agent`) via the `Agent(subagent_type="<name>", ...)` tool, the registered form varies by runtime: interactive Claude Code with the plugin marketplace-installed registers agents under `geniro-claude-plugin:<agent>`; vendored / harness installs register them under bare `<agent>`; Claude Code SDK / cloud runners do not register them at all and the call hard-errors with `Agent type '<name>' not found. Available agents: …`.

**Apply the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every plugin-agent spawn site.** The ladder: try `Agent(subagent_type="geniro-claude-plugin:<agent>", ...)` first; on "not found", retry with bare `Agent(subagent_type="<agent>", ...)`; on "not found" again, fall back to `Agent(subagent_type="general-purpose", ...)` with the agent's `.md` body (frontmatter stripped) prepended to the prompt. Cache the resolved rung for the rest of the session — registration is fixed at session init. This is the agent-registration layer; it is independent of the MCP-tool degradation noted in the Optional MCP Dependencies section below.

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files. Per-pattern bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.
- **Git guardrails** — blocks destructive git operations (force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, filter-branch, update-ref -d)
- **`.geniro/` deletion guard** — blocks bulk deletion of `.geniro/` (which holds user-authored instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Per-file `rm -f` and deep-path `rm -rf .geniro/<top>/<sub>/` remain allowed; bulk `rm -rf .geniro/`, `rm -rf .geniro/<single-segment>`, `find .geniro -delete`, `git worktree remove`, and `git add -f` on `.geniro/` paths are blocked. The `git add -f` block exists because force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — real incident: Cursor's SCM discard wiped `.geniro/actions/*.md` after they were force-added. The correct path for tracked content is `.gitignore` negation (e.g. `!.geniro/actions/` + `!.geniro/actions/**`), never `git add -f`.
- **Session-start restore** — `hooks/session-start-restore.sh`, wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 state.md via canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton); pre-flights `validate_state_file` and degrades gracefully if the helper is missing. Emits an `additionalContext` block-set: per-source prefix · suggested files (L4 instructions trio routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md / FEATURES.md / state.md / spec.md / plan.md as direct Reads) · validation-failure recovery directive · helper-missing notice · structured non-resumable-actions warning (per-action rendering for git-push / pr-comment-posted / slack-notify-sent / release-tagged plus unknown-action fallback) · unresolved errors from state.md `## Errors` · pending Open Questions · persisted approvals from frontmatter `approvals: []` · **auto-archive of stale L2 entries (default ON, hash-gated + mkdir-locked for multi-tab safety)** · resume protocol. systemMessage one-liner emitted on every source except cold startup with no active task (overridden when auto-archive runs — user sees "auto-archived: N" suffix). Read-only on state.md — never writes; writes only to `.geniro/knowledge/learnings.jsonl` (auto-archive) and `.geniro/knowledge/.archive-stale.{hash,lock}`. Compaction-immune helpers (`query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts`) take no MODE parameter; `load-custom-instructions` and `load-semantic` accept `MODE: refresh` (procedure identical to initial-load).
- **Evidence-on-completion** — Stop hook (warn-only) — scans last assistant message for completion phrases (e.g., "shipped", "all tests pass", "ready to ship", "Done!") that lack an Evidence Block; cites `skills/_shared/evidence-standard.md`. Stop hooks fire ~50-80% of the time, so this is a soft reminder layer, not enforcement. Bypass: `evidence-stop` in `.geniro/safety.json` `allow_patterns`.
- **TDD-order enforcement** — PreToolUse `Edit|Write` (hard-block) — when `.geniro/state/tdd/state-<slug>.md` shows phase=RED, blocks `Edit`/`Write` on production-code files (test files still allowed). State file absence means the skill hasn't opted in to TDD, so no surprise blocks. Bypass: `tdd-order` in `.geniro/safety.json` `allow_patterns`.
- **State-helper enforcement** — PreToolUse `Edit|Write` (warn-mode initially; flips to hard-block in a future release) — warns when a direct `Edit`/`Write` targets a canonical state path (`.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`, `.geniro/.geniro-state.json`). Suggests `atomic_state_write` (or `atomic_state_append` for JSONL) per `skills/_shared/atomic-state-write.md`. Bypass: `enforce-state-helper` in `.geniro/safety.json` `allow_patterns`.

### Per-project allowlist for safety guardrails

Create `.geniro/safety.json` in your project to opt out of specific guardrail patterns:

```json
{
  "allow_patterns": ["force-push-with-lease", "clean-fd"]
}
```

Pattern IDs:
- **File protection** (Write/Edit): `write-env` (`.env`/`.env.*`), `write-git-internal` (`.git/*`), `write-lockfile` (pnpm-lock.yaml / package-lock.json / yarn.lock / bun.lockb / cargo.lock / Gemfile.lock / composer.lock / poetry.lock / Pipfile.lock / go.sum), `write-cert-key` (`*.pem`/`*.key`/`private-key*`), `write-credentials` (`credentials.*`/`secrets.*`), `write-tfstate`, `write-vault`
- **Git guardrails**: `force-push`, `force-push-with-lease`, `reset-hard`, `branch-delete-force`, `clean-fd`, `checkout-mass-discard`, `restore-mass-discard`, `update-ref-delete`, `filter-branch`
- **`.geniro/` deletion guard**: `rm-geniro-tree` (bulk `rm -rf .geniro/`), `rm-geniro-subdir` (`rm -rf .geniro/<top>/`), `rm-geniro-state-subdir` (`rm -rf .geniro/state/<skill>/`), `find-geniro-delete` (`find .geniro ... -delete`), `worktree-remove-with-state` (`git worktree remove`), `git-add-force-geniro` (`git add -f` on `.geniro/` paths)
- **Evidence-on-completion**: `evidence-stop` (skip the Stop-hook completion-phrase warning)
- **TDD-order enforcement**: `tdd-order` (skip the RED-phase production-code Edit/Write block)
- **State-helper enforcement**: `enforce-state-helper` (skip the warning on direct Edit/Write to `.geniro/` state paths — once block-mode is enabled, this becomes the hard-block bypass)

The allowlist is read from the nearest `.geniro/safety.json` walking up from the cwd.

## Optional MCP Dependencies

Some skills/agents unlock additional capabilities when a companion MCP server is available. They **gracefully degrade** when it isn't — install only the ones you need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `/geniro:implement` Phase 3 Ship sub-step Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console/network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The tool prefix `plugin_playwright_playwright__*` is what Claude Code exposes when Playwright comes from a sibling plugin. If absent, the visual loop and smoke-test step are skipped automatically. |

To check what's available in your environment, look for `mcp__plugin_playwright_playwright__*` tools in the agent's tool list at runtime.

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
