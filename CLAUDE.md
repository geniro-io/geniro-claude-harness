# Geniro Plugin

Production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions

## Available Skills

Post-M10 — 18 skills → 11 (master plan §22). The 8 deleted skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) have their replacements documented in the right-hand column; their `skills/` directories were removed synchronously with M10 completion.

| Skill | Purpose |
|-------|---------|
| `/geniro:plan` (M5) | Spec-first planning — turn а vague idea or feature request into an approved `spec.md` via а 9-phase loop (mode-detect → explore → clarify ≤5 questions → 2-3 approaches → 10-section approval → write → mechanical validate → user approve → hand-off). Fixed 10-section P-M5-1 schema; goal-state frontmatter (budget / checkpoints / forbidden_actions / approval_required_for / tools_required); compaction-safe `approvals[]` (M1 P-M1-1). Milestone-mode (Phase 5 §5.3) emits sibling `milestone-N.md` files для Big tasks (absorbs deleted `/decompose`). NO auto-commit (D1 fix — commit fires at Phase 8 post-approve). |
| `/geniro:implement` (M4) | M4 2-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Consumes spec.md from `/plan` (или inline-task fallback when `/plan` hasn't been run yet). Single solo execution path с 5-dim parallel self-review (bugs / security / architecture / tests / code-quality). Absorbs post-ship tweaks from the legacy `/follow-up`. |
| `/geniro:review` (M6) | M6 6-phase reporter loop (triage → mechanical pre-pass → 9-dim LLM reviewers → filter → stratify → persist → action-gate). Dimensions: bugs / security / architecture / tests / optimizations / guidelines / conventions (+design when UI files present, +pr-metadata когда input was а PR ref, +spec-compliance when PLAN CONTEXT non-none AND (PR ref OR risk-tier:high)). Phase 1.5 NEW mechanical pre-pass (lint / schema / secret scan) feeds prior-context к LLM reviewers. Phase 5b auto-emits `pitfall` L2 entries on cross-reviewer convergence ≥3 (absorbs deleted `/learnings`). Optional `--simplify` flag prepends Reuse/Quality/Efficiency criteria к 5 dimensions (absorbs deleted `/deep-simplify`; no new dim, no fix-loop — Reporter behavior preserved). Optional `--tdd` flag tightens Phase 4b validation budget + Phase 4c F→P test-gate. Emits T2 hand-off at `.geniro/state/handoff/from-review-<branch>.md` (M1 §T2 schema + M3 body sections) — downstream consumers (/implement, manual) apply fixes. Stratifies on hard-escalation signals from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`; inherits prior-round findings across re-runs (max 3 rounds before escalate-AUQ). |
| `/geniro:debug` (M7) | M7 3-phase scientific-method investigation (Investigate → Propose → Ship) mirroring `/implement`. Phase 1 observes / hypothesizes / tests / isolates root cause; Phase 2 authors text fix proposal + F→P reproduction test (no production-source edits); Phase 3 persists T2 hand-off at `.geniro/state/handoff/from-debug-<branch>.md` и escalates к `/geniro:implement`. State.md uses M1 §T1 session-bound subdir layout `.geniro/state/debug/<slug>/state.md` + M3 body sections + compaction-safe `approvals[]` (M1 P-M1-1). §1.7 stall gate (5 inconclusive → P-M7-2 8-component AUQ) + §2.5 fix-fail gate (2 attempts → AUQ). Phase 3 §3.3 auto-emits L2 `diagnosis` с `ext.{symptom, root_cause, fix}` (absorbing the legacy `/learnings` cadence для debug); L4 promotion suggestion fires when recurrence detected. Adversarial Mode (verify-changes) preserved as parallel workflow — authors F→P RED tests via `adversarial-tester-agent`, persists к `from-debug-adversarial-<branch>.md`. NEVER ships code (no `git push` / `gh pr create`). |
| `/geniro:refactor` (M8) | M8 3-phase loop (Plan → Apply → Verify) mirroring `/implement`. Zero-behavior-change guarantee preserved (master plan §34). Phase 1 loads L4/L3/L2, classifies tier via canonical `_shared/effort-scaling.md` (Trivial / Small / Medium / Big — Q2 adoption), spawns smell-detection refactor-agent (Medium+) + relevance-filter (Medium+), builds plan + HIGH-step approval AUQ. Phase 2 spawns refactor-agent (model: opus when max_risk=HIGH else sonnet) к execute approved plan one transformation at а time с per-step regression + ≥30% blocked escalation. Phase 3 runs independent reviewer + custom reviewers (Medium+), PRODUCT-DECISION → ESCALATE к /implement (Always-WAIT, 4-option ADR-aware AUQ), CRITICAL/HIGH non-PD → 1-round fix loop. State.md uses M1 §T1 session-bound subdir layout `.geniro/state/refactor/<slug>/state.md` + M3 body sections + compaction-safe `approvals[]` (P-M1-1 — categories `refactor_high_step` + `refactor_product_decision`). Phase 3 §3.5 auto-emits L2 `discovery` + `pitfall` per M2 §5.3 (absorbs `/learnings`); L4 promotion suggestion fires. NEVER ships code (no `git push` / `gh pr create`) — diff IS the deliverable, working tree IS the channel; user commits manually или runs `/geniro:implement` к ship через review gate. |
| `/geniro:onboard` (M9) | M9 2-phase loop (Discover → Map) mirroring `/implement`. Scans codebase structure и produces `<PRIMARY_ROOT>/.geniro/planning/_CODEBASE_MAP.md` с the canonical 8-section template (M1:508 underscore-prefixed L3 registry). Phase 1 applies P-M9-2 ≤50-file scan cap (default; user-confirmable expansion via AUQ persisted к state.md `approvals[]` category `expand_scope` per P-M1-1); empty/permission-blocked repos route к terminal `routed`/`aborted`. Phase 2 writes the map, calls `update-semantic` (М2 §6.1 bounded auto-incremental L3 write с advisory lock), emits L2 `discovery` (M2 §5.3 row /onboard — `trust: verified`, replaces deleted /learnings per master plan §69), fires Next-step AUQ routing к /plan / /investigate / /implement / `_FEATURES.md`. State.md uses M1 §T1 session-bound subdir layout `.geniro/state/onboard/<slug>/state.md` + M3 body sections. Drops pre-M9 `--quick` mode entirely (Q4); `--focus` / `--depth` retained as scope-limiters on the full 8-section template. |
| `/geniro:investigate` (M9) | M9 3-phase loop (Classify+Scope → Investigate+Verify → Synthesize+Review+Present) mirroring `/implement`. Phase 1 classifies $ARGUMENTS into 9-type taxonomy + 5-step JIT retrieval cadence (P-M9-1) + glossary-mismatch check (с P-M1-1 `approvals[]` category `glossary_resolve` для compaction-safe persistence). Phase 2 spawns 1-3 parallel research agents (Codebase Analyst / Git Historian / Internet Researcher — literal classified set, never over-spawned) с orchestrator re-verify of every load-bearing claim + missing-data gate AUQ. Phase 3 synthesizes draft (5 question-type templates), spawns fresh reviewer-agent (sonnet default; max 1 re-review round), presents с Sources + Open questions, fires save-routing AUQ (CLAUDE.md Domain Context / ADR / learnings.jsonl / auto-memory — focused-agent workaround since /investigate has no Write tool), emits L2 `discovery` с trust label (`verified` if code-grounded; `retrieved` if WebFetch/WebSearch load-bearing — P-M2-3 + P-M9-3 minimal scope, no envelope wrapping). State.md uses M1 §T1 session-bound subdir layout `.geniro/state/investigate/<slug>/state.md` + M3 body sections. NEVER ships code (no `git push` / no `gh pr create`). |
| `/geniro:instructions` (M10b) | M10b 3-phase stateless CRUD (parse → execute → done) over `.geniro/instructions/` — the L4 procedural memory layer (M2 §5.4). 5 operations: list / create / edit / validate / delete. 11-scope set: `global`, `code-style`, `user-preferences` (NEW from M10a), `review-extra/<slug>` (directory-style), и per-skill (`implement`, `plan`, `review`, `debug`, `refactor`, `onboard`, `investigate`). §10 `validate` mode (P-M10-2 closure): structural + reference + per-scope lint with CRITICAL/HIGH/MEDIUM/LOW severities — catches refs к dropped skills, dropped phase names, и P-M10-2 description hygiene rules on `review-extra/<slug>.md` frontmatter. Scope-specific scaffolds on create. 2-level chain replaces pre-M10 3-chain ambiguity resolution. No subagents (CRUD too small for parallelism). NEVER ships code. |
| `/geniro:actions` (M10c) | M10c 3-phase stateless CRUD + runner over `.geniro/actions/` — user-authored workflow-helper actions (Slack/PR/release automations). 6 operations: list / create / edit / run / delete / validate. P-M10-1 minimal enforcement (Q4): `risk_class: low \| medium \| high` mandatory frontmatter field; Q5 added к create-interview with scaffold heuristic mapping Q3 output к suggested risk class. §Phase 5.3 risk-class AUQ ladder в run mode: `low` skips AUQ, `medium` is 1-click confirm, `high` uses Cancel-as-recommended default. §Phase 8 `validate` mode (NEW — OQ-M10b-1 closure): 13-rule lint shared с `/instructions validate review-extra`; exit non-zero on CRITICAL/HIGH. L2 `discovery` emit on successful runs with `external-send: true` (auto-replaces dropped `/learnings`). Tool-scope intersection в run mode (action `allowed-tools` ∩ /actions `allowed-tools`). Preserved verbatim: registry index, exact-slug fast path, free-text picker, source-aware destructive-op guard, main-worktree cross-worktree confirmation. NEVER ships code (action body may; that's the action author's responsibility). |
| `/geniro:setup` (M10a) | M10a 4-phase singleton bootstrap (Detect → Interview → Generate → Validate → Done). Singleton state file at `<PRIMARY_ROOT>/.geniro/state/setup/state.md` (M1 §T1 third path-root variant — no `<slug>/` subdir, no parallel runs). Init и re-run modes (uninstall out of scope). Phase 1 detects tech stack via lockfile/config presence (no inference); scans project documentation; captures skill_inventory from marketplace.json или 11-skill fallback. Phase 2 captures preferences via P-M1-1 `approvals[]`-aware AUQ batches (categories: `ship_mode_default`, `default_branch`, `default_reviewer_set`, `communication_style`, `claude_md_section_<id>`); `--reset-prefs` resets preference subset only. Phase 3 P-M10-3 split methodology: section-by-section AUQ (sections >40 LOC default к spin out к `.geniro/docs/<topic>.md`); preferences land в `.geniro/instructions/user-preferences.md` (L4 procedural per Q8 — P-M2-1 closure); CLAUDE.md becomes а thin map. Phase 4 spawns verification subagent (model: sonnet; tools=[Read, Bash, Glob, Grep] — NO Write/Edit) с 8-checklist; 3-retry loop → AUQ escalation. L2 `discovery` emit on Done (auto-replaces dropped `/learnings`). Generated CLAUDE.md skill table lists exactly 11 skills — no references к dropped skills. Restart-session warning emitted only on re-run с plugin-version delta. |
| `/geniro:update` (M10d) | M10d 5-phase stateless loop (Pre-check → Update → Post-check → Migration → Done). §Phase 1 Step 3 pre-update version-confirm AUQ (D1 fix — explicit gate before shell call). User-content snapshot at Pre-check + survival diff at Post-check (D2 fix — catches silent corruption). 4-retry exponential backoff (2s/4s/8s/16s) per CLAUDE.md network rules (D4 fix). Hash-check sanity mode (sentinel files; manifest-mode hook reserved для future). §Phase 4 MIGRATION.md reader + walk (D3, Q6 most-ambitious option) — schema specced в `architecture/M10d-update-redesign.md` §5; user-affected entries surface "Show how к fix" / "Skip for now" / "Cancel walk" AUQ; NEVER auto-applies fixes. Cancel-as-recommended AUQ pattern (M10c §6.3) для hash-fail и content-tamper warnings. Restart-session warning always emitted (vs M10a §10.3 conditional — `/update` IS а version transition). `--dry-run` flag previews without invoking update. NEVER touches user content в `.geniro/instructions/` или `.geniro/actions/` (snapshot-and-verify only). |

**Skills deleted в M4 redesign** (master plan §60):

| Deleted | Replacement |
|---|---|
| `/geniro:brainstorm` | Merged → `/geniro:plan` (M5) |
| `/geniro:decompose` | Merged → `/geniro:plan` (M5, milestones as output mode) |
| `/geniro:follow-up` | Absorbed → `/geniro:implement` (handles any size via spec input) |
| `/geniro:deep-simplify` | Optional flag on `/geniro:review` (M6) |
| `/geniro:features` | Manual `FEATURES.md` или via `/geniro:plan` |
| `/geniro:learnings` | Auto-step в `/geniro:implement` Phase 3 (M4 §13.2) и `/geniro:debug` (M7) |
| `/geniro:cleanup` | Dropped — niche |
| `/geniro:vendor` | Dropped — no cloud-runner requirement |

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## State Files

Every state file under `.geniro/` belongs to exactly one tier and must be written through the atomic-write helpers — not direct `Edit`/`Write` calls.

| Tier | Paths | Helper |
|------|-------|--------|
| **T1 — TASK** (ephemeral, deleted at Phase Ship) | `.geniro/planning/<task-dir>/*` (M4 `/implement`, M5 `/plan`) · `.geniro/state/<skill>/<slug>/state.md` (M7 `/debug`, M8 `/refactor`, M9 `/onboard`, M9 `/investigate`) · `.geniro/state/setup/state.md` singleton (M10a `/setup`) | `atomic_state_write` |
| **T2 — HANDOFF** (inter-skill, overwritten by producer) | `.geniro/state/handoff/from-<producer>-<branch>.md` | `atomic_state_write` |
| **T3 — PERSISTENT CRUD** | `.geniro/instructions/*` · `.geniro/actions/*` · `.geniro/workflow/*` · `.geniro/planning/_*.md` · `.geniro/docs/*` (M10a §3.4 spin-out targets) | `atomic_state_write` (caller does optimistic mtime check first) |
| **T3 — PERSISTENT append-only** | `.geniro/knowledge/learnings.jsonl` | `atomic_state_append` |

**Helper invocation** (from inside a skill's Bash call):

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.sh"
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
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.sh"
if ! validate_state_file ".geniro/planning/<task-dir>/state.md"; then
  # Open recovery AskUserQuestion (delete-and-restart / open-in-editor / update-worktree-path / skip-emergency)
  ...
fi
```

**Full reference:**
- `skills/_shared/state-tier-spec.md` — canonical schema and per-tier required fields.
- `skills/_shared/atomic-state-write.md` — write helper, exit codes, mtime-check pattern.
- `skills/_shared/validate-state-file.md` — validator, exit codes, recovery AUQ template.
- `architecture/M1-state-files.md` — design rationale.

## Memory Layers (M2)

Every persisted fact lives in exactly one of four layers. Writers know **what** to record and **where**; readers know **which layer** answers a question. Anything that doesn't fit one of these layers is by definition out of scope for the memory subsystem.

| Layer | Name | Lifespan | Routing rule (writer intent → layer) | Path |
|-------|------|----------|---------------------------------------|------|
| **L1** | Working | Per-task | "Right now, phase X of task Y is running." | `.geniro/planning/<task-dir>/state.md` (M1 T1) |
| **L2** | Episodic | Append-only event log | "In this run we observed event X." | `.geniro/knowledge/learnings.jsonl` |
| **L3** | Semantic | Current-state snapshot | "In this project, fact X is currently true." | `.geniro/planning/_*.md` |
| **L4** | Procedural | Stable rules | "When doing X, always do Y." | `.geniro/instructions/*.md` |

**Cross-layer precedence (when layers disagree): L4 > L3 > L2.** L4 is user-curated explicit rules (highest trust); L3 is drift-monitored current state; L2 is historical events with the lowest cross-layer trust. L1 is task-scoped and never conflicts cross-layer.

**Within-layer:** recency wins. L2 uses the `supersedes` chain. L3 uses fingerprint refresh / file mtime. L4 uses file mtime.

### Helper invocation

| Helper | Purpose |
|--------|---------|
| `_shared/load-custom-instructions.md` | Load L4 — `global.md` + `<skill>.md` + `code-style.md` (already in use pre-M2) |
| `_shared/load-semantic.sh` | Load L3 — `_project.md` + `_CODEBASE_MAP.md` by default; `--extras "..."` for additional files; auto-runs fingerprint drift check to stderr |
| `_shared/update-semantic.sh` | Bounded-write L3 — `--file <codebase-map\|features> --append "<line>"` or `--replace "<prefix>" "<new>"`. Per-file POSIX-O_EXCL lock; rc=11 if held |
| `_shared/emit-learning.sh` | Append L2 — JSON on stdin, auto-sanitization, auto-dedup with supersede chain |
| `_shared/query-learnings.sh` | Read L2 — flags: `--type`, `--tag`, `--scope`, `--min-trust`, `--include-superseded`, `--include-deprecated`, `--include-archive`, `--limit` |
| `_shared/redact-secrets.sh` | Regex sanitization for any free-form text — called automatically by `emit_learning`; also reusable standalone |

### Conflict surfacing protocol

When a load-* helper detects layers disagreeing, the calling skill prints a notice in its output and continues using the precedence-winning value. For **hard conflicts** (L4 rule directly contradicts L3 reality), the skill halts and calls `AskUserQuestion`. Both notice format and AUQ template live in `skills/_shared/resolve-conflicts.md`.

**Full reference:**
- `architecture/M2-memory-layers.md` — full layer model, lifecycle, and reflection-cycle triggers.
- `skills/_shared/redact-secrets.md` · `emit-learning.md` · `query-learnings.md` · `load-semantic.md` · `update-semantic.md` — per-helper API contracts.
- `skills/_shared/resolve-conflicts.md` — cross-layer conflict notice format.

## Custom Agent Invocation

When a skill spawns a plugin-defined agent (`reviewer-agent`, `relevance-filter-agent`, `adversarial-tester-agent`, `refactor-agent`, `architect-agent`) via the `Agent(subagent_type="<name>", ...)` tool, the registered form varies by runtime: interactive Claude Code with the plugin marketplace-installed registers agents under `geniro-claude-plugin:<agent>`; vendored / harness installs register them under bare `<agent>`; Claude Code SDK / cloud runners do not register them at all and the call hard-errors with `Agent type '<name>' not found. Available agents: …`.

**Apply the runtime-degradation rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every plugin-agent spawn site.** The ladder: try `Agent(subagent_type="geniro-claude-plugin:<agent>", ...)` first; on "not found", retry with bare `Agent(subagent_type="<agent>", ...)`; on "not found" again, fall back to `Agent(subagent_type="general-purpose", ...)` with the agent's `.md` body (frontmatter stripped) prepended to the prompt. Cache the resolved rung for the rest of the session — registration is fixed at session init. This is the agent-registration layer; it is independent of the MCP-tool degradation noted in §Optional MCP Dependencies below.

## Safety Hooks (Active)

This plugin provides safety hooks that run automatically:
- **File protection** — blocks writes to `.env`, `*.key`, `*.pem`, lock files. Per-pattern bypass: `write-env`, `write-git-internal`, `write-lockfile`, `write-cert-key`, `write-credentials`, `write-tfstate`, `write-vault`.
- **Git guardrails** — blocks destructive git operations (force-push, reset --hard, branch -D, clean -fd, mass-discard checkout/restore, filter-branch, update-ref -d)
- **`.geniro/` deletion guard** — blocks bulk deletion of `.geniro/` (which holds user-authored instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Per-file `rm -f` and deep-path `rm -rf .geniro/<top>/<sub>/` remain allowed; bulk `rm -rf .geniro/`, `rm -rf .geniro/<single-segment>`, `find .geniro -delete`, `git worktree remove`, and `git add -f` on `.geniro/` paths are blocked. The `git add -f` block exists because force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — real incident: Cursor's SCM discard wiped `.geniro/actions/*.md` after they were force-added. The correct path for tracked content is `.gitignore` negation (e.g. `!.geniro/actions/` + `!.geniro/actions/**`), never `git add -f`.
- **Session-start restore (M3)** — `hooks/session-start-restore.sh`, wired as `SessionStart` with `matcher: "compact|resume|startup"` (Anthropic-canonical; `PostCompact` itself does not support `additionalContext`). `clear` is explicitly unmatched — user reset respected. Resolves the active T1 state.md via M1-canonical slug match + frontmatter `branch:` fallback across all three layouts (planning task-dir / state-per-skill slug / state singleton); pre-flights `validate_state_file` and degrades gracefully if the helper is missing. Emits an `additionalContext` block-set per M3 §6: per-source prefix · suggested files (L4 instructions trio routed through `load-custom-instructions.md` MODE: refresh; CLAUDE.md / FEATURES.md / state.md / spec.md / plan.md as direct Reads) · validation-failure recovery directive · helper-missing notice · structured non-resumable-actions warning (per-action rendering for git-push / pr-comment-posted / slack-notify-sent / release-tagged plus unknown-action fallback) · unresolved errors from state.md `## Errors` · pending Open Questions · persisted approvals from frontmatter `approvals: []` · resume protocol. systemMessage one-liner emitted on every source except cold startup with no active task. Read-only — never writes state.md. Compaction-immune helpers (`query-learnings`, `emit-learning`, `update-semantic`, `resolve-conflicts`) take no MODE parameter; `load-custom-instructions` and `load-semantic` accept `MODE: refresh` (procedure identical to initial-load).
- **Evidence-on-completion** — Stop hook (warn-only) — scans last assistant message for completion phrases (e.g., "shipped", "all tests pass", "ready to ship", "Done!") that lack an Evidence Block; cites `skills/_shared/evidence-standard.md`. Stop hooks fire ~50-80% of the time, so this is a soft reminder layer, not enforcement. Bypass: `evidence-stop` in `.geniro/safety.json` `allow_patterns`.
- **TDD-order enforcement** — PreToolUse `Edit|Write` (hard-block) — when `.geniro/state/tdd/state-<slug>.md` shows phase=RED, blocks `Edit`/`Write` on production-code files (test files still allowed). State file absence means the skill hasn't opted in to TDD, so no surprise blocks. Bypass: `tdd-order` in `.geniro/safety.json` `allow_patterns`.
- **State-helper enforcement** — PreToolUse `Edit|Write` (warn-mode initially; flips to hard-block in M1 PR-final) — warns when a direct `Edit`/`Write` targets a canonical state path (`.geniro/state/`, `.geniro/planning/`, `.geniro/knowledge/`, `.geniro/instructions/`, `.geniro/actions/`, `.geniro/workflow/`, `.geniro/.geniro-state.json`). Suggests `atomic_state_write` (or `atomic_state_append` for JSONL) per `skills/_shared/atomic-state-write.md`. Bypass: `enforce-state-helper` in `.geniro/safety.json` `allow_patterns`.
- **Plan-mode write-guard (M5)** — `hooks/plan-mode-write-guard.sh`, PreToolUse `Edit|Write` (hard-block). When а `/geniro:plan` run is active (detected via `.geniro/planning/*/state.md` с frontmatter `producer: plan` AND `status: in-progress` AND mtime within `PLAN_LOCK_FRESHNESS_SEC` — 4h default, env-overridable), restricts `Write` к `.geniro/planning/**` OR `.geniro/state/**`. Pairs с Layer 1 enforcement (Edit removed от /plan's `allowed-tools`). Belt + suspenders per M5 §19. Stale state files (>4h) treat /plan as abandoned к prevent permanent lockout. Bypass: `plan-mode-mutation` в `.geniro/safety.json` `allow_patterns`.

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
- **State-helper enforcement**: `enforce-state-helper` (skip the warning on direct Edit/Write to `.geniro/` state paths — once block-mode is enabled in PR-final, this becomes the hard-block bypass)
- **Plan-mode write-guard**: `plan-mode-mutation` (skip the /plan-active write-scope check; allows Write к paths outside `.geniro/planning/**` and `.geniro/state/**` even when а /plan state.md is in-progress)

The allowlist is read from the nearest `.geniro/safety.json` walking up from the cwd.

## Optional MCP Dependencies

Some skills/agents unlock additional capabilities when a companion MCP server is available. They **gracefully degrade** when it isn't — install only the ones you need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `/geniro:implement` (M4) Phase 3 Ship sub-step Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console/network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The tool prefix `plugin_playwright_playwright__*` is what Claude Code exposes when Playwright comes from a sibling plugin. If absent, the visual loop and smoke-test step are skipped automatically. |

To check what's available in your environment, look for `mcp__plugin_playwright_playwright__*` tools in the agent's tool list at runtime.

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
