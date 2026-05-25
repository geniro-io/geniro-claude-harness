# Architecture Decisions

Consolidated reference of design decisions that govern how skills, hooks, helpers, and state files work in the geniro-claude-plugin. Each section distills one milestone's key rulings; historical rationale and proposal tracking have been removed.

---

## State Files (M1)

Every state write uses `atomic_state_write` (tmp + fsync + rename + fsync-dir); enforced by PreToolUse hook.

**Three tiers:**

| Tier | Purpose | Path pattern |
|------|---------|-------------|
| T1 Task | Ephemeral, per-session | `planning/<task-dir>/` or `state/<skill>/<slug>/` or `state/<skill>/state.md` (singletons) |
| T2 Handoff | Inter-skill | `state/handoff/from-<producer>-<branch>.md` |
| T3 Persistent | CRUD / append-only | `instructions/`, `actions/`, `workflow/`, `planning/_*.md`, `knowledge/learnings.jsonl` |

- Validation failure opens a hard AUQ (delete-and-restart / open-in-editor / skip-emergency) — no silent partial reads.
- Concurrency by convention: T1 uses slug-scoped paths, T2 uses branch-scoped paths, T3 CRUD uses optimistic mtime check. No filesystem locks.
- `_`-prefixed files under `planning/` are persistent T3; validators enforce tier by frontmatter, not filename.

---

## Memory Layers (M2)

Four-layer taxonomy: L1 Working / L2 Episodic / L3 Semantic / L4 Procedural.

- **Writer intent** — not file location — determines the layer.
- **Cross-layer precedence** when layers disagree: L4 > L3 > L2. Within-layer, recency wins.
- CLAUDE.md is outside the memory model — the plugin never writes to it.
- L3 files live under `planning/_*.md`; `.fingerprint.json` hashes detect drift.
- Hard conflict (L4 rule contradicts L3 reality) halts the skill and opens an AUQ per `_shared/resolve-conflicts.md`.

---

## Compaction Survival (M3)

SessionStart hook re-establishes context across `compact|resume|startup`. `clear` is explicitly excluded (respects user intent).

- Hook only emits pointers and directives in `additionalContext` — it does NOT load helpers itself. The model executes the refresh protocol on its next turn.
- Side-effects already completed (git push, PR comment, Slack notify) are surfaced as hard-imperative do-not-repeat warnings via `non-resumable-actions[]` in state frontmatter.
- Cold startup with no active T1 task suppresses the `systemMessage` one-liner.
- Hook is read-only on state.md; only writes to `learnings.jsonl` (auto-archive path).

---

## /implement (M4)

Collapsed to 2 phases: Analyze → Implement + Self-review + Ship.

- When a spec.md is provided, `/implement` skips its own analysis — spec is the source of truth.
- Inline-task fallback exists for when `/plan` has not been run — pure semantic parse of `$ARGUMENTS`.
- Phase 2 fix loop max 3 retries; on failure → AUQ with `debug-handoff / accept-failures / abort`.
- Self-review spawns 5 parallel reviewer-agents (bugs / security / architecture / tests / code-quality); max 3 review rounds, then escalation AUQ.
- Every side-effect (commit, push, PR creation) writes to `non-resumable-actions[]` before executing.

---

## /plan (M5)

Renamed from /brainstorm; absorbs /decompose; produces canonical spec.md.

- Fixed 10-section spec.md schema — downstream consumers (`/implement`, `/review`) depend on this exact structure.
- Each user answer and approach pick is immediately persisted to `approvals[]` for compaction safety.
- Milestone-mode fires when task is classified Big: emits sibling `milestone-N.md` files alongside `spec.md`.
- No auto-commit — commit fires at Phase 8 (post-approve) only.

---

## /review (M6)

Reporter-only (never applies fixes); absorbs /deep-simplify as `--simplify` flag.

- Phase 1.5 mechanical pre-pass (lint / schema / secret scan) runs before LLM reviewers; findings fed as prior-context to avoid double-surfacing.
- `guidelines` collapsed into `conventions` dimension — was previously a duplication.
- `--simplify` adds Reuse/Quality/Efficiency criteria to 5 dimensions; does not add a dimension or fix loop — reporter behavior preserved.
- Cross-reviewer convergence at >=3 reviewers auto-promotes to a `pitfall` L2 entry.
- T2 handoff emitted at `from-review-<branch>.md`; downstream applies fixes.

---

## /debug (M7)

3 phases: Investigate → Propose → Ship (escalates to `/implement`).

- Phase 1 STALL gate: 5 inconclusive steps → 8-component AUQ.
- Phase 2 fix-loop gate: max 2 fix attempts; on third → AUQ.
- Adversarial Mode (verify-changes) is a co-equal parallel workflow; delegates RED-phase test authoring to `adversarial-tester-agent`.
- Phase 3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}`; L4 promotion suggestion fires on recurrence.
- NEVER ships code (no `git push` / `gh pr create`).

---

## /refactor (M8)

3 phases: Plan → Apply → Verify. Zero-behavior-change guarantee.

- Adopts canonical 4-tier effort-scaling (Trivial/Small/Medium/Big).
- All review/execution runs orchestrator-inline (no dedicated subagents).
- Blocked-step protocol: max 3 retries per step → mark BLOCKED and continue; >=30% blocked → escalation AUQ.
- PRODUCT-DECISION findings escalate to `/implement` via AUQ (always-wait, 4-option ADR-aware).
- NEVER ships code — diff is the deliverable.

---

## /onboard + /investigate (M9)

Discovery surface; two skills.

- `/onboard` ≤50-file scan cap by default; expansion requires explicit AUQ approval.
- `/investigate` formalizes 5-step JIT retrieval cadence: classify → scope → select agents → run parallel → orchestrator re-verify.
- L2 trust label: `verified` for code-grounded, `retrieved` for WebFetch/WebSearch sourced.
- Both use M1 session-bound T1 layout (`state/<skill>/<slug>/state.md`).

---

## /setup (M10a)

Singleton bootstrap; one state file at `state/setup/state.md`.

- Re-run mode runs a MIGRATION.md sweep before generating content — auto-fix then re-detect.
- Generated CLAUDE.md is project-specific only (tech stack, commands, conventions, domain) — no plugin info.
- Verification subagent (Read/Bash/Glob/Grep only — NO Write/Edit) runs an 8-checklist; 3-retry loop → AUQ escalation.
- Detect phase is observation-only; Write/Edit forbidden until Generate phase.

---

## /instructions (M10b)

Stateless CRUD over `.geniro/instructions/` (L4 procedural layer).

- No state file — every invocation is a single transaction.
- `validate` catches: refs to dropped skills, dropped phase names, `review-extra/` frontmatter hygiene, 200-LOC soft cap warning.
- 10 scopes: `global`, `code-style`, `review-extra/<slug>`, and per-skill (implement, plan, review, debug, refactor, onboard, investigate).
- No subagent spawns — CRUD is too small for parallelism.

---

## /actions (M10c)

Stateless CRUD + runner over `.geniro/actions/`.

- `risk_class` (low/medium/high) is mandatory frontmatter. Run-mode gate: low = no AUQ, medium = 1-click confirm, high = Cancel-as-recommended.
- Tool-scope intersection in run mode: action's `allowed-tools` ∩ skill's `allowed-tools`.
- L2 `discovery` emit fires on successful runs where `external-send: true`.
- Any action calling `mcp__github__*`, network, or `Bash(curl ...)` must declare `risk_class: high`.

---

## /update (M10d)

Stateless update wrapper + integrity check + MIGRATION.md reader.

- MIGRATION.md walk is per-entry, one AUQ per step; "Fix it for me (Recommended)" as first option.
- User-content survival check: hash-check `.geniro/instructions/` and `.geniro/actions/` after update.
- Network errors use 4-retry exponential backoff (2s/4s/8s/16s); after 4 → abort.
- Restart-session warning always emitted after successful update.

---

## Self-Learning (P-X8)

Three additional L2 entry types + score-based query ranking.

- `discarded_hypothesis`: emitted by `/debug` Phase 1; sliding-window cap 5 per scope.
- `user_rejected_suggestion`: emitted by `emit-rejection.sh` after qualifying AUQ resolution.
- `retry_failure_sequence`: emitted when retries >=2 in `/implement`, `/debug`, `/refactor`.
- Score-based ranking: recency × trust × access-count. Stale entries (score < 0.1, age > 180d, access_count == 0) auto-archived at SessionStart.

---

## Operational Rules (from report.md)

- Hook blocking requires `exit 2`, not `exit 1` — `exit 1` is fail-open.
- SKILL.md must stay under 500 lines; extract reference material to sibling files.
- Beyond ~150 total CLAUDE.md instructions, compliance degrades uniformly (context rot).
- Skills cannot call other skills — use shared reference files + subagent delegation.
- Subagents cannot spawn sub-tasks; all orchestration happens at the top-level skill.
- MCP auth (OAuth) is silently lost after compaction; scheduled tasks cannot access MCP.
