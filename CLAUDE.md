# Geniro Plugin

Production-grade Claude Code plugin: AI-driven setup, multi-agent workflows, safety hooks. One `skills/` directory ships to two runtimes, Claude Code and Cursor.

## Available Skills

Each skill's own frontmatter description is the routing surface Claude Code loads at discovery. This table is a map for orientation, not the contract.

| Skill | Purpose |
|-------|---------|
| `/geniro:plan` | Spec-first planning: vague idea → clarify grill → critic-tested approaches → approved 11-section `spec.md`. |
| `/geniro:implement` | 3-phase autonomous executor (Analyze → Implement → Self-review-and-Ship), consuming a spec or an inline task. |
| `/geniro:review` | Read-only 6-phase review of a diff, branch, or PR: parallel single-dimension reviewers, then fresh-agent verification of every survivor. Never edits code. |
| `/geniro:resolve` | Read-only PR-feedback triage → comment-keyed `spec.md` + handoff for `/implement`, which applies the fixes and posts the replies. |
| `/geniro:debug` | Scientific-method bug investigation → fix proposal + failing reproduction test, then handoff. Never edits production source. |
| `/geniro:refactor` | Zero-behavior-change restructuring with per-step regression checks. Never ships — the working-tree diff is the deliverable. |
| `/geniro:onboard` | Rapid orientation in an unfamiliar codebase → `_CODEBASE_MAP.md`. |
| `/geniro:investigate` | Evidence-based Q&A over code, git history, and the internet. Never ships code. |
| `/geniro:reflect` | Mines past session transcripts for durable project-rule candidates. |
| `/geniro:instructions` | CRUD over `.geniro/instructions/` — the project-rules layer. |
| `/geniro:actions` | CRUD + runner over `.geniro/actions/` — user-authored workflow helpers. |
| `/geniro:setup` | Singleton bootstrap: detect the stack, interview, generate a project CLAUDE.md, verify it. |
| `/geniro:update` | Pulls the latest plugin version with integrity checks and a per-entry `MIGRATION.md` walk. |

Full per-skill descriptions, every flag, and the eight deleted skills with their replacements: `README.md`.

## Path Rules

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` is NOT expanded by these tools and creates a literal `~` directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or fully resolved absolute paths for project files.

## Never force-add `.geniro/` paths

`git add -f` on a `.geniro/` path makes ignored files visible in IDE Source Control panels, and one "Discard All Changes" click then becomes a data-loss vector — real incident: Cursor's SCM discard wiped `.geniro/actions/*.md` after they had been force-added. For content that genuinely should be tracked, use `.gitignore` negation (`!.geniro/actions/` plus `!.geniro/actions/**`). A hook blocks the force-add.

## State Files

Every state file under `.geniro/` belongs to exactly one tier and must be written through the atomic-write helpers — not direct `Edit`/`Write` calls.

| Tier | Paths | Helper |
|------|-------|--------|
| **T1 — TASK ephemeral** (transient working artifacts, targeted `rm -f` at terminal exit — Ship cleanup and every other terminal transition of the owning run) | `.geniro/planning/<task-dir>/.{kr,ce,tr,adversarial,research,spec-challenge}-out.md` (subagent OUTPUT_PATH reports) · `.geniro/planning/<task-dir>/.research-<facet>.md` (per-facet research outputs from /plan Phase 1) · `.geniro/planning/<task-dir>/notes.md` (scratch) · `.geniro/planning/<task-dir>/playwright-verify.png` (visual-verify artifacts) | `atomic_state_write` |
| **T1.5 — TASK durable** (survives Phase Ship; design artifacts user may want to keep) | `.geniro/planning/<task-dir>/{spec,state}.md` · `.geniro/planning/<task-dir>/plan-*.md` · `.geniro/planning/<task-dir>/milestone-*.md` · `.geniro/state/<skill>/<slug>/state.md` (`/debug`, `/refactor`, `/onboard`, `/investigate`, `/resolve`) · `.geniro/state/setup/state.md` singleton (`/setup`) | `atomic_state_write` |
| **T2 — HANDOFF** (inter-skill, overwritten by producer) | `.geniro/state/handoff/from-<producer>-<branch>.md` (carries structured `open_questions[]` for safety-gated consumer transitions) | `atomic_state_write` |
| **T3 — PERSISTENT CRUD** | `.geniro/instructions/*` · `.geniro/actions/*` · `.geniro/workflow/*` · `.geniro/planning/_*.md` · `.geniro/docs/*` (spin-out targets) | `atomic_state_write` (caller does optimistic mtime check first) |
| **T3 — PERSISTENT append-only** | `.geniro/knowledge/learnings.jsonl` | `atomic_state_append` |

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

Canonical schema and per-tier required fields, the terminal-exit cleanup contract, and the TDD-state carve-out: `skills/_shared/state-tier-spec.md`. Write-helper exit codes and the mtime-check pattern: `atomic-state-write.md`. Validator exit codes and the recovery prompt to open when validation fails before a resume: `validate-state-file.md`.

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

Per-helper API contracts (`emit-learning`, `query-learnings`, `load-semantic`, `update-semantic`, `archive-stale`, `redact-secrets`, `emit-rejection`) each live in `skills/_shared/<helper>.md`; the loaders are `load-custom-instructions.md` and `subagent-instruction-load.md`, and the alternate L2 backend is `memory-backend.md`. When a loader detects layers disagreeing, the notice format and the halt-and-ask template are in `skills/_shared/resolve-conflicts.md`.

## Editing plugin content — full reads, not grep

When the user asks to improve, review, or modify this plugin's skills/agents/rules, load the relevant files in FULL first by running:

```bash
scripts/dump-md.sh [path ...]   # e.g. scripts/dump-md.sh skills/implement skills/_shared
```

It prints every tracked `.md` file under the given paths (whole repo when no path) as a `===== <path> =====` header followed by the file's complete content. Do this BEFORE reaching for Grep: keyword search shows matching lines only, which misses reworded coverage of the same concept and produces false "missing" findings when auditing or extending skills. Grep stays fine for pinpointing an exact known string (an edit anchor, a cross-reference check) — not for surveying what a skill covers. Subagents doing gap analysis or skill edits get the same instruction: read full files, not grep hits.

Every improvement pass also SUBTRACTS: apply `.claude/rules/skill-prose.md` §"Assume a capable model" to the sections touched — remove over-detailed mechanics the model derives itself (platform command recipes, shell hand-holding, chewed-up substeps); excess detail primes the wrong mechanism and confuses runs. Improving a module means leaving it leaner than found, not only longer.

## Testing & CI

```bash
bash tests/run-all.sh                 # every tests/**/*.sh suite
bash tests/authoring/lint-skills.sh   # authoring lint (hard failures + advisory warnings)
```

`.github/workflows/ci.yml` runs `tests/run-all.sh` plus ShellCheck on every pull request and on pushes to `main`. The release workflow tags its bump commit `[skip ci]`, so CI never runs on the bot's version-bump push.

## Where the rest lives

| Topic | File |
|---|---|
| Safety hooks — what each one blocks, every bypass pattern ID, `.geniro/safety.json` | `HOOKS.md` |
| Design decisions, subagent model tiering, optional MCP companions, the Cursor runtime port | `ARCHITECTURE.md` |
| Skill catalogue with full descriptions and flags; the deleted skills and their replacements | `README.md` |
| Breaking changes and the per-entry upgrade walk | `MIGRATION.md` |
| Agent spawn ladder (`geniro:<agent>` → bare → `general-purpose` + inlined body) | `skills/_shared/spawn-agent.md` |
| Authoring rules for skills and agents (voice, structure, what never ships) | `.claude/rules/*.md` — path-scoped, so they load when you touch a skill or agent file |
