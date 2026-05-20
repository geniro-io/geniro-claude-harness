# Geniro Plugin

Production-grade Claude Code plugin with AI-driven setup, multi-agent workflows, and safety hooks.

## Getting Started

Run `/geniro:setup` to analyze your codebase and generate a tailored configuration:
- Project-specific CLAUDE.md with detected tech stack, commands, and conventions

## Available Skills

Post-M4 redesign — 18 skills → 11 (master plan §22). The 8 deleted skills (`/brainstorm`, `/decompose`, `/follow-up`, `/deep-simplify`, `/features`, `/learnings`, `/cleanup`, `/vendor`) have their replacements documented in the right-hand column. Deletions land synchronously with M4 + M5–M10; until then the legacy skill directories may still exist on disk but are not listed below.

| Skill | Purpose |
|-------|---------|
| `/geniro:plan` (M5 — placeholder until M5 ships) | Turn а vague idea or feature request into an **approved spec.md**. Big tasks also emit 3-7 milestones (per-milestone spec.md files). Absorbs the legacy `/brainstorm` + `/decompose`. |
| `/geniro:implement` (M4) | M4 2-phase autonomous loop: Analyze → Implement → Self-review-and-Ship. Consumes spec.md from `/plan` (или inline-task fallback when `/plan` hasn't been run yet). Single solo execution path с 5-dim parallel self-review (bugs / security / architecture / tests / code-quality). Absorbs post-ship tweaks from the legacy `/follow-up`. |
| `/geniro:review` | Parallel 7–10 agent code review (bugs, security, architecture, tests, optimizations, guidelines, conventions, +design when UI files present, +pr-metadata when input was a PR ref, +spec-compliance when PLAN CONTEXT non-none AND (PR ref OR risk-tier: high)). Stratifies on hard-escalation signals from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md`; inherits prior-round findings across re-runs (max 3 rounds before escalate-AUQ). M6 will add an optional `--simplify` flag absorbing the legacy `/deep-simplify`. |
| `/geniro:debug` | Scientific-method bug investigation с hypothesis tracking. Auto-emits L2 `diagnosis` к learnings.jsonl (absorbing the legacy `/learnings` cadence для debug). |
| `/geniro:refactor` | Restructure code с zero behavior change guarantee. |
| `/geniro:onboard` | Rapid codebase mapping и orientation. |
| `/geniro:investigate` | Deep codebase Q&A с parallel research agents. |
| `/geniro:instructions` | Manage custom instruction files — create, list, edit, validate, delete. Scopes: `global`, the pipeline skills, `code-style` (cross-cutting style rules loaded at every code-writing & review step), и `review-extra` (directory-style scope at `.geniro/instructions/review-extra/<slug>.md` — one file per custom code-review dimension loaded alongside the built-in reviewers). |
| `/geniro:actions` | Create, edit, run, и remove custom workflow-helper actions stored в `.geniro/actions/` (Slack/PR/release automations). |
| `/geniro:setup` | AI-driven project setup — scans codebase, interviews you, generates CLAUDE.md. |
| `/geniro:update` | Update plugin к latest version. |

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
| **T3 — PERSISTENT CRUD** | `.geniro/instructions/*` · `.geniro/actions/*` · `.geniro/workflow/*` · `.geniro/planning/_*.md` · `.geniro/.geniro-state.json` | `atomic_state_write` (caller does optimistic mtime check first) |
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

When a skill spawns a plugin-defined agent (`reviewer-agent`, `relevance-filter-agent`, `adversarial-tester-agent`, `refactor-agent`, `architect-agent`, `skeptic-agent`, `knowledge-retrieval-agent`, `backend-agent`, `frontend-agent`) via the `Agent(subagent_type="<name>", ...)` tool, the registered form varies by runtime: interactive Claude Code with the plugin marketplace-installed registers agents under `geniro-claude-plugin:<agent>`; `/geniro:vendor`-ed projects register them under bare `<agent>`; Claude Code SDK / harness / cloud runners do not register them at all and the call hard-errors with `Agent type '<name>' not found. Available agents: …`.

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

The allowlist is read from the nearest `.geniro/safety.json` walking up from the cwd.

## Optional MCP Dependencies

Some skills/agents unlock additional capabilities when a companion MCP server is available. They **gracefully degrade** when it isn't — install only the ones you need.

| MCP | Used by | Enables | Install |
|-----|---------|---------|---------|
| **Playwright** (`mcp__plugin_playwright_playwright__*`) | `frontend-agent` Phase 3.5(b) visual self-critique; `/geniro:implement` Phase 7 Pre-Ship Visual Verification | Screenshot loop at 375/768/1440, console/network sanity checks, keyboard-nav verification, smoke-test of the shipped change | Install the `playwright` marketplace plugin alongside this one. The tool prefix `plugin_playwright_playwright__*` is what Claude Code exposes when Playwright comes from a sibling plugin. If absent, the visual loop and smoke-test step are skipped automatically. |

To check what's available in your environment, look for `mcp__plugin_playwright_playwright__*` tools in the agent's tool list at runtime.

## Updating

This plugin updates automatically via the Claude Code marketplace. To manually check:
```
claude plugin update geniro-claude-plugin@geniro-claude-harness
```
