# Architecture Decisions

Consolidated reference of design decisions that govern how skills, hooks, helpers, and state files work in the geniro-claude-plugin. Each section distills one milestone's key rulings; historical rationale and proposal tracking have been removed.

---

## State Files (M1)

Every state write uses `atomic_state_write` (tmp + fsync + rename + fsync-dir); enforced by PreToolUse hook.

**Four tiers:**

| Tier | Purpose | Path pattern |
|------|---------|-------------|
| T1 Task — ephemeral | Transient working artifacts; targeted `rm -f` at Phase Ship | `planning/<task-dir>/.{kr,ce,tr,adversarial}-out.md` (subagent OUTPUT_PATH reports), `planning/<task-dir>/notes.md`, visual-verify artifacts |
| T1.5 Task — durable | Survives Phase Ship; design artifacts the user may want to keep | `planning/<task-dir>/{spec,state}.md`, `planning/<task-dir>/plan-*.md`, `planning/<task-dir>/milestone-*.md`, `state/<skill>/<slug>/state.md`, `state/setup/state.md` singleton |
| T2 Handoff | Inter-skill; carries structured `open_questions[]` for safety-gated consumer transitions | `state/handoff/from-<producer>-<branch>.md` |
| T3 Persistent | CRUD / append-only | `instructions/`, `actions/`, `workflow/`, `planning/_*.md`, `knowledge/learnings.jsonl` |

- T1 vs T1.5 split lets Ship cleanup keep design intent (spec, state log, milestones) while removing only transient subagent-report scratch files.
- Validation failure opens a hard AUQ (delete-and-restart / open-in-editor / skip-emergency) — no silent partial reads.
- Concurrency by convention: T1/T1.5 use slug-scoped paths, T2 uses branch-scoped paths, T3 CRUD uses optimistic mtime check. No filesystem locks.
- `_`-prefixed files under `planning/` are persistent T3; validators enforce tier by frontmatter, not filename.
- T2 handoffs carry a structured `open_questions[]` frontmatter array per `_shared/state-tier-spec.md` §T2 — each entry has `{id, source, question, related_findings/related_hypotheses, status: unresolved|resolved|wontfix, resolution}`. Consumer skills (e.g., `/implement` Phase 1 Step 12) gate Edit/Write transitions on the array being empty-of-unresolved; producer Pre-gates (`/review` Phase 6, `/debug` Phase 3) and Pre-Post-PR guards refuse to ship state with unresolved entries.

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

3 phases: Analyze → Implement → Self-review-and-Ship.

- Phase 1 fires Step 0 workspace AUQ (passive-detect of `CURRENT_BRANCH`, `IN_WORKTREE`, prior-task signals → 7-rule decision tree; auto-continue when "continuing-work" signals are present, AUQ only when ambiguous).
- Phase 1 spawns `knowledge-retrieval-agent` + `codebase-explorer-agent` in parallel (subagent delegation replaces the orchestrator-inline 17-file Phase-1 sweep that drove the 370K-token context bloat).
- When a spec.md is provided, `/implement` consumes the spec frontmatter (including `workflow_refs[]` when `geniro_schema_version: m5-v2`). Inline-task fallback exists when `/plan` has not been run.
- Phase 2 uses TodoWrite for sequential decomposition (one-in-progress invariant); `test-runner-agent` runs at phase end. Phase 2 fix loop max 3 retries; on failure → AUQ with `debug-handoff / accept-failures / abort`.
- Phase 3 spawns 5 reviewer-agents + 1 `adversarial-tester-agent` in parallel (6 total; adversarial skipped on trivial scope per Codebase-Explorer `change_scope`); max 3 review rounds, then escalation AUQ.
- Phase 1 Step 12 (NEW) parses every T2 handoff (`from-review-<branch>.md`, `from-debug-<branch>.md`) for `open_questions[]`; refuses to leave Phase 1 while any entry has `status: unresolved` — gates Edit/Write transitions cold.
- Ship cleanup preserves durable T1.5 artifacts (spec.md / state.md / plan-*.md / milestone-*.md); targeted `rm -f` removes only T1 scratch.
- All subagents declare `model: inherit`; spawn sites OMIT `model=`. The orchestrator's session tier (Opus / Sonnet / Haiku) propagates to every spawn.
- Every side-effect (commit, push, PR creation) writes to `non-resumable-actions[]` before executing.

---

## Subagent model selection

- All plugin-defined subagents declare `model: inherit` in frontmatter.
- Spawn sites in skill SKILL.md files OMIT `model=` argument — passing `model="inherit"` at the call site fails Agent-tool input validation (the enum is `sonnet|opus|haiku`); the runtime resolver picks up the orchestrator's tier ONLY when `model=` is unset.
- User-authored custom reviewers (`.geniro/instructions/review-extra/*.md`) may declare an explicit `model:` field to opt OUT of inherit; absent declaration means inherit.
- Cloud-runner / headless-CI fallback table preserved in `skills/_shared/model-tiering.md` §"Tier table as fallback" for environments where `model: inherit` resolution is unsupported.
- Two carve-outs deliberately retain hardcoded tier:
  - `/geniro:setup` Phase 4 verification subagent → `model="sonnet"` (safety contract — runs under tightly constrained `tools=[Read, Bash, Glob, Grep]` with NO Write/Edit; the hardcoded floor is the safety contract, not the model preference).
  - `_shared/ui-preview-gate.md` UI-description spawn → `model="haiku"` (mechanical transformation of spec/plan into structured description — not reasoning work; speed floor matters).

---

## /plan (M5)

Renamed from /brainstorm; absorbs /decompose; produces canonical spec.md.

- Fixed 10-section spec.md schema — downstream consumers (`/implement`, `/review`) depend on this exact structure.
- Frontmatter gains optional `workflow_refs[]` (m5-v2 schema) — tracker linkage (Linear / Jira / GitHub-Issues / Asana) persists from Phase 1 fetch through Phase 6 write. Per-entry shape: `{kind, issue_id, url, fetched_at, title?, suggested_branch?, status?, parent_ref?}`. Downstream readers accept both `m5-v1` (treat field as absent) and `m5-v2`.
- Phase 2 Visual Companion fires only on UI trigger (Phase 1 surfaced UI files OR topic carries UI noun) — calls `_shared/ui-preview-gate.md` for a textual UI preview before any code is written; approved description feeds Phase 5 sections 6 + 9.
- Per-section AUQs use the AskUserQuestion `preview` field — every option renders concrete content (UI ASCII / code snippet / behavior trace); chat-side companion is a one-line "Section: X — focus an option to inspect" announcement. Phase 3 + Phase 4 options also carry `preview`.
- Section authoring is incremental (section N → AUQ → on approve, author N+1) — no pre-fill batch (the redundancy the user observed in M5-v1).
- Each user answer and approach pick is immediately persisted to `approvals[]` for compaction safety.
- Milestone-mode fires when task is classified Big: emits sibling `milestone-N.md` files alongside `spec.md`.
- Phase 7 mechanical validator runs 14 checks (adds `workflow_refs_consistency` — warns when `.geniro/workflow/<kind>.md` missing; fails on structural field-presence violations; skipped on m5-v1).
- No auto-commit — commit fires at Phase 8 (post-approve) only.

---

## /review (M6)

Reporter-only (never applies fixes, never mutates tracker status — that is `/plan` and `/implement` territory); absorbs /deep-simplify as `--simplify` flag.

- MANDATORY spawn list: 7 always (bugs / security / architecture / tests / optimizations / guidelines / conventions) + up to 3 conditional (design / pr-metadata / spec-compliance) + N custom from `.geniro/instructions/review-extra/`. The list is no longer permissive — Phase 2 step 2.2 declares `spawn_dims_declared[]` in state.md before the parallel batch, and Phase 4 §4.0 runs a post-spawn verification gate (declared-vs-actual diff) to catch silent skips.
- Phase 1 Step 0 smart workspace setup (passive-detect → AUQ only when ambiguous); mirrors `/implement` Step 0 contract but without the workflow-status-mutation question.
- Phase 1.5 mechanical pre-pass: lint / schema / secret scan + custom-reviewer discovery (the `review-extra/<slug>.md` set is resolved here so Phase 2 has zero cognitive load for it).
- `guidelines` is preserved as a separate dimension in the mandatory list (the prior M6-v1 collapse into `conventions` was reversed during v3 — both surface distinct defect classes).
- `--simplify` adds Reuse/Quality/Efficiency criteria to 5 dimensions; does not add a dimension or fix loop — reporter behavior preserved.
- Cross-reviewer convergence at >=3 reviewers auto-promotes to a `pitfall` L2 entry.
- T2 handoff emitted at `from-review-<branch>.md` with structured `open_questions[]` frontmatter (status: `unresolved | resolved | wontfix`). 3-gate safety chain prevents posting or implementing with unresolved questions: Phase 6 Pre-gate (producer-side) + Pre-Post-PR guard (defensive, before `gh api` POST) + Consumer-side `/implement` Phase 1 Step 12 (refuses to leave Phase 1 with unresolved entries).
- All reviewer-agents inherit orchestrator tier (OMIT `model=`); user-authored custom reviewers may opt out via frontmatter declaration.

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
- Phase 2 Codebase Analyst spawn IS `codebase-research-agent` (general-purpose plugin agent for cross-skill codebase research; `model: inherit`); Git Historian and Internet Researcher remain `general-purpose` Agent() spawns because of their distinct tool surfaces (git read-verbs / WebSearch+WebFetch).
- L2 trust label: `verified` for code-grounded, `retrieved` for WebFetch/WebSearch sourced.
- Both use M1 session-bound T1 layout (`state/<skill>/<slug>/state.md`).

`codebase-research-agent` is the cross-skill codebase-research substrate — used ad-hoc by `/plan`, `/debug`, `/implement` Phase 2, `/review` Phase 1, `/refactor` Phase 1, `/onboard` Phase 1 for any "map a subsystem / trace a flow / locate a definition" query that would otherwise flood the orchestrator's context with file contents. Replaces the built-in `Explore` subagent (Haiku-pinned, exposed to [anthropics/claude-code#38928](https://github.com/anthropics/claude-code/issues/38928) MCP-overflow bug). Canonical guidance + invocation contract: `skills/_shared/context-isolation-checklist.md` § Codebase research.

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
