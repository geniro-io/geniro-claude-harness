# Architecture Decisions

Consolidated reference of design decisions that govern how skills, hooks, helpers, and state files work in the geniro-claude-plugin. Each section distills one milestone's key rulings; historical rationale and proposal tracking have been removed.

---

## State Files (M1)

Every state write uses `atomic_state_write` (tmp + fsync + rename + fsync-dir); enforced by PreToolUse hook.

**Four tiers:**

| Tier | Purpose | Path pattern |
|------|---------|-------------|
| T1 Task — ephemeral | Transient working artifacts; targeted `rm -f` at Phase Ship | `planning/<task-dir>/.{kr,ce,tr,adversarial,research}-out.md` (subagent OUTPUT_PATH reports), `planning/<task-dir>/.research-<facet>.md` (per-facet `/plan` research), `planning/<task-dir>/notes.md`, visual-verify artifacts |
| T1.5 Task — durable | Survives Phase Ship; design artifacts the user may want to keep | `planning/<task-dir>/{spec,state}.md`, `planning/<task-dir>/plan-*.md`, `planning/<task-dir>/milestone-*.md`, `state/<skill>/<slug>/state.md`, `state/setup/state.md` singleton |
| T2 Handoff | Inter-skill; carries structured `open_questions[]` for safety-gated consumer transitions | `state/handoff/from-<producer>-<branch>.md` |
| T3 Persistent | CRUD / append-only | `instructions/`, `actions/`, `workflow/`, `planning/_*.md`, `knowledge/learnings.jsonl` |

- T1 vs T1.5 split lets Ship cleanup keep design intent (spec, state log, milestones) while removing only transient subagent-report scratch files.
- Validation failure opens a hard AUQ (delete-and-restart / open-in-editor / skip-emergency) — no silent partial reads.
- Concurrency by convention: T1/T1.5 use slug-scoped paths, T2 uses branch-scoped paths, T3 CRUD uses optimistic mtime check. No filesystem locks.
- `_`-prefixed files under `planning/` are persistent T3; validators enforce tier by frontmatter, not filename.
- T2 handoffs carry a structured `open_questions[]` frontmatter array per `_shared/state-tier-spec.md` §T2 — each entry has `{id, source, question, related_findings/related_hypotheses, status: unresolved|resolved|wontfix, resolution}`. Consumer skills (e.g., `/implement` Phase 1 Step 12) gate Edit/Write transitions on the array being empty-of-unresolved; producer Pre-gates (`/review` Phase 6, `/debug` Phase 3) and Pre-Post-PR guards refuse to ship state with unresolved entries.
- `/debug` handoffs (m7-v2+) additionally carry a producer-specific `authored_tests[]` array — each entry `{id, path, intent, mode, f_to_p_status, related_hypotheses, targeted_source, confidence}`. Consumed by `/implement` Phase 1 Step 12 via `_shared/debug-handoff.md` Scan/Extract/Verify/Decide protocol: prefer frontmatter, fall back to body parse for m7-v1 legacy; resolve paths against the consumer's worktree; surface suggest-only relocation block when MISSING. The array is informational (not a gate) so authored tests survive cross-worktree consumption without losing producer intent.

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
- Phase 3 spawns the reviewer-agent set + 1 `adversarial-tester-agent` in parallel (adversarial skipped on trivial scope per Codebase-Explorer `change_scope`); max 3 review rounds, then escalation AUQ.
- Phase 1 Step 12 parses every T2 handoff (`from-review-<branch>.md`, `from-debug-<branch>.md`) for `open_questions[]`; refuses to leave Phase 1 while any entry has `status: unresolved` — gates Edit/Write transitions cold. For debug handoffs additionally invokes `_shared/debug-handoff.md` Scan/Extract/Verify/Decide protocol: extracts `authored_tests[]` (m7-v2+) or falls back to body parse (m7-v1), verifies each path against the consumer's worktree, surfaces suggest-only relocation block when MISSING. Authored-tests are informational (not a gate); Phase 2 reads them to prime TodoWrite decomposition so every authored test surfaces as an acceptance gate in its relevant todo.
- Ship cleanup preserves durable T1.5 artifacts (spec.md / state.md / plan-*.md / milestone-*.md); targeted `rm -f` removes only T1 scratch.
- All subagents declare `model: inherit`; spawn sites OMIT `model=`. The orchestrator's session tier (Opus / Sonnet / Haiku) propagates to every spawn.
- Every side-effect (commit, push, PR creation) writes to `non-resumable-actions[]` before executing.

**Ship consent (separate from side-effect logging).** Logging a side-effect to `non-resumable-actions[]` records that it happened; it does not authorize it. Commit / push / PR-create are outward-facing actions that each require their own confirmation gate (`/implement` Ship-mode AUQ). An approval scoped to one decision does not satisfy a different one: a `/review` action-gate pick ("/implement findings") authorizes applying the fixes, never the downstream commit/push. A push to a feature branch that already has an open PR is outward-facing (CI re-runs, reviewers see new commits), so it is gated like a shared-branch push when the run was entered via a handoff.

**Handoffs carry work, not authority.** A `/review` → `/implement` (or `/debug` → `/implement`) handoff transfers findings and unresolved `open_questions[]` — restrictions and to-dos — never ship authorization. The consumer applies its own gates; it is not pre-authorized by the producer's action-gate pick. See `skills/_shared/reporter-boundary.md` §2.

**Shortcut-judgment does not suspend a skill's contract.** A continuation run ("I already explored this in the /review I just ran") may not skip a skill's mandated parallel spawns (Phase-1 knowledge-retrieval + codebase-explorer) or gates (Ship-mode AUQ) on a "pure ceremony / context already held" rationalization. The spawns and gates fire regardless of inherited context; a continuation that skips them inherits the upstream run's blind spots. Enforced by `skills/_shared/reporter-boundary.md` and each skill's own gates.

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

- Fixed 11-section spec.md schema — downstream consumers (`/implement`, `/review`) depend on this exact structure.
- Frontmatter gains optional `workflow_refs[]` (m5-v2 schema) — tracker linkage (Linear / Jira / GitHub-Issues / Asana) persists from Phase 1 fetch through Phase 6 write. Per-entry shape: `{kind, issue_id, url, fetched_at, title?, suggested_branch?, status?, parent_ref?}`. Downstream readers accept both `m5-v1` (treat field as absent) and `m5-v2`.
- Phase 2 Visual Companion fires only on UI trigger (Phase 1 surfaced UI files OR topic carries UI noun) — calls `_shared/ui-preview-gate.md` for a textual UI preview before any code is written; approved description feeds Phase 5 sections 6 + 9.
- Phase 5 section approval is grouped into 3 dependency-ordered cluster gates (Goal & scope: sections 1-3 / Approach & steps: sections 4-7 / Safety & done: sections 8-11) instead of one AUQ per section. Each cluster is authored as a unit and rendered to a full chat message in the Visual rendering language — progress tracker (`✔/●/○` over the approval journey), one-sentence opener, friendly per-section digests (lead sentence / Why with evidence cite / How it gets built / You'll see), a visual per section type, light heading icons — then gated by ONE lean AskUserQuestion per cluster (Approve all / Explain a section further / Revise specific sections → section-picker / Cancel; Explain is a reading aid that renders a deeper walkthrough, writes no approvals, and never counts toward the 3 revision rounds). The chat message is the rendering surface: the AUQ `preview` side-box is a narrow, truncating panel too small for digests, code, and diagrams — this is the message-first Gate presentation contract (`skills/plan/plan-loop.md` §"Gate presentation contract"). The visual language itself is canonical in `skills/_shared/gate-rendering.md` (shared with the finding gates of /review, /implement, /debug, /refactor); plan keeps its instantiation — the approval-journey stops and per-section cluster visuals — in plan-loop.md / plan-reference.md. Drops the questions the user answers at Phase 5 from ~11 (one per section) to 3 (one per cluster). Phase 3 / Phase 4 / Phase 8 follow the same contract — rich content renders to a chat message, then a lean AUQ captures only the decision; Phase 3 still batches independent clarifying questions into one call (≤4, chain past the cap).
- Cluster authoring is incremental in dependency order (author cluster N → render to chat → lean AUQ → on approve, author cluster N+1) — this preserves cross-section issue-catching while avoiding BOTH the over-gating of a per-section design (one low-content gate per section → click-through fatigue) AND the redundancy of re-asking each section after it was already rendered to chat (the lean per-cluster AUQ captures the whole cluster in one decision). Each section's pick still persists immediately to `approvals[]` under category `section_<id>` for compaction safety — granularity is unchanged (the per-cluster AUQ writes one entry per section it covers), only the AUQ delivery is grouped, so Phase 6.4 compaction re-author and the session-start restore hook need no change.
- Each user answer and approach pick is immediately persisted to `approvals[]` for compaction safety.
- Milestone-mode fires when task is classified Big: emits sibling `milestone-N.md` files alongside `spec.md`.
- Phase 7 mechanical validator runs 14 checks (adds `workflow_refs_consistency` — warns when `.geniro/workflow/<kind>.md` missing; fails on structural field-presence violations; skipped on m5-v1).
- No auto-commit — commit fires at Phase 8 (post-approve) only.

---

## /review (M6)

Reporter-only (never applies fixes, never mutates tracker status — that is `/plan` and `/implement` territory); absorbs /deep-simplify as `--simplify` flag.

- MANDATORY spawn list: always-fire (bugs / security / architecture / tests / optimizations / guidelines / conventions / regressions) + conditional (design / pr-metadata / spec-compliance) + N custom from `.geniro/instructions/review-extra/`. The list is no longer permissive — Phase 2 step 2.2 declares `spawn_dims_declared[]` in state.md before the parallel batch, and Phase 4 §4.0 runs a post-spawn verification gate (declared-vs-actual diff) to catch silent skips. The `regressions` dim (added in m6-v2) catches unintended deletes + behavior changes outside stated intent via 4 signals — deleted-symbol caller-blast, intent-vs-behavior over-reach (PLAN/PR/commit message as intent source), test-coverage delta, and parallel-path symmetry (a guard/filter/fix applied to one branch of a type/cadence split but not its parallel counterpart).
- spec-compliance treats the spec as the **primary intent rubric but a fallible artifact**, not ground truth. Before flagging a diff omission as a defect, the reviewer grounds the divergence against live code (§Spec-premise validation in `_shared/review-criteria/spec-compliance-criteria.md`): a divergence can mean the diff is wrong (standard code-omission finding at normal severity) OR the spec is wrong (the code correctly departed from a stale spec premise). Spec-defect divergences cap at MEDIUM and route to `[INTENT-CHECK]` — the user decides whether to fix the spec or the code — never a HIGH/CRITICAL omission against the implementation. This mirrors the spec-challenge doctrine (`_shared/spec-challenge.md`) used pre-approval in `/plan` (Phase 7.5) and pre-edit in `/implement` (Step 12.5): re-verify the spec's facts against code, never rewrite the spec, skip-when-clean. `reviewer-agent` Step 1.5 carries the same fallibility caveat for every dimension that reads PLAN CONTEXT.
- Phase 4.1 admits findings via a multi-signal gate (replacing the single `confidence >= 80%` threshold which production data flagged as miscalibrating — Claude self-confidence is documented as "nearly random" by Greptile and ~+25% overconfident at the 90%+ band per arXiv 2405.02917). KEEP rule: `severity >= MEDIUM` AND any-of {`convergence_count >= 2`, `Evidence-Block present + confidence >= 60`, criteria-pre-resolved marker (e.g., simplify P1/P2), `confidence >= 80` advisory fallback}. Tier-aware: high tier relaxes the fallback to `confidence >= 70`. Sub-threshold findings persist to a `## Deferred — sub-threshold` body section; never posted to PR. The Confidence field is now advisory documentation per `skills/_shared/severity-calibration.md` §4 — convergence and evidence-grounding are the load-bearing primary signals. Canonical severity rubric with INCLUDES + EXCLUDES per tier (CRITICAL/HIGH/MEDIUM/LOW) lives in the same reference file §1, consumed by `reviewer-agent.md` + all 12 per-dim criteria files; documentation/PR-description/cosmetic suggestions are explicitly LOW (never MEDIUM). Decision-type is an orthogonal admission axis: a finding tagged `[PRODUCT-DECISION]` is kept and surfaced — and, on a Post, inline-commented to its line — regardless of severity via §4.1 Path B (a LOW PRODUCT-DECISION is the user's call, not the reviewer's, mirroring `/refactor`'s always-WAIT PRODUCT-DECISION escalation); severity stays as scored, never inflated.
- Phase 4.2 spawns one fresh `reviewer-agent` per §4.1 survivor (CRITICAL / HIGH / MEDIUM) in `verify-finding` mode (no tier-scaling, no severity-scaling — every survivor verified regardless of `risk-tier` or `--tdd`). The §4.1 multi-signal gate already constrains the survivor set to findings with Evidence-Block-grade citations (signal #2 mandatory for MEDIUM; Loop Invariant #6 mandates Evidence at every kept severity), so every survivor has a concrete file:line for the verifier to re-read. Each verifier receives isolated context (the finding body + cited code slice + 1-hop caller grep) NOT the full reviewer bundle — independence prevents anchoring per multi-judge research. Verifier emits `Validation: confirmed | refuted | clarified` + `Recommended-action` + `Verification-confidence` (1-5) + `Verification-evidence` (literal file:line quote). Refuted findings demote to `## Filtered` before §4.3 F→P gate; clarified findings update `Decision Type:` to the verifier's `Recommended-action`. Phase 6 §7.0 fail-closed guard now re-checks all 3 invariants (`open_questions[].status`, PRODUCT-DECISION `step0_status:`, kept-finding `Validation:`) before any `gh api POST /reviews` — defense-in-depth at the external-effect boundary.
- Phase 1 Step 0 smart workspace setup (passive-detect → AUQ only when ambiguous); mirrors `/implement` Step 0 contract but without the workflow-status-mutation question.
- Finding-decision gates (open-decision gate, Pre-gate, PR-comment per-finding gate) follow the shared message-first contract (`skills/_shared/per-finding-question.md` §"Message-first rendering") and render in the same visual language as `/plan`'s approval gates (`skills/_shared/gate-rendering.md`): the finding renders to a self-contained chat block first — decision-queue tracker when ≥2 decisions are queued, one-sentence opener, conversational digest with evidence cite (expanding reviewer shorthand into plain English), a visual per finding type (§Finding-type visual map) — then a lean AskUserQuestion captures the decision. The `preview` side-box is never the rendering surface (it truncates with no scroll and is often absent in interactive sessions). Same contract used by `/implement`, `/refactor`, `/debug`; it also covers the consolidated gates — `/review`'s Action gate renders a wrap-up message first, `/implement`'s fix-loop finding resolution and test-failure escalation render-first, `/debug`'s open-question pre-gate renders each entry as a rich block, and `/refactor`'s HIGH-risk step approval renders a steps-flow + per-step risk table before its lean question.
- Phase 1.5 mechanical pre-pass: lint / schema / secret scan + custom-reviewer discovery (the `review-extra/<slug>.md` set is resolved here so Phase 2 has zero cognitive load for it).
- `guidelines` is preserved as a separate dimension in the mandatory list (the prior M6-v1 collapse into `conventions` was reversed during v3 — both surface distinct defect classes).
- `--simplify` adds Reuse/Quality/Efficiency criteria to a subset of dimensions; does not add a dimension or fix loop — reporter behavior preserved.
- Cross-reviewer convergence at >=3 reviewers auto-promotes to a `pitfall` L2 entry.
- T2 handoff emitted at `from-review-<branch>.md` with structured `open_questions[]` frontmatter (status: `unresolved | resolved | wontfix`). 3-gate safety chain prevents posting or implementing with unresolved questions: Phase 6 Pre-gate (producer-side) + Pre-Post-PR guard (defensive, before `gh api` POST) + Consumer-side `/implement` Phase 1 Step 12 (refuses to leave Phase 1 with unresolved entries).
- All reviewer-agents inherit orchestrator tier (OMIT `model=`); user-authored custom reviewers may opt out via frontmatter declaration.

---

## /debug (M7)

3 phases: Investigate → Propose → Ship (escalates to `/implement`).

- Phase 1 STALL gate: 5 inconclusive steps → 8-component AUQ.
- Phase 2 fix-loop gate: max 2 fix attempts; on third → AUQ.
- Adversarial Mode (verify-changes) is a co-equal parallel workflow; delegates RED-phase test authoring to `adversarial-tester-agent`.
- Phase 3 auto-emits L2 `diagnosis` with `ext.{symptom, root_cause, fix}`; on `recurrence_count >= 3` (after a dedupe check against existing project rules) fires an AskUserQuestion offering to capture the recurring diagnosis as a project rule via `/geniro:instructions create` (user-curated, no auto-write; declines logged via `emit-rejection.sh`).
- T2 handoff carries a structured `authored_tests[]` frontmatter array (m7-v2+) alongside `open_questions[]`. Each entry pins the path + intent + F→P status of every reproduction test the run produced, so `/implement` Phase 1 Step 12 can extract, verify, and surface relocation suggestions for tests that exist in the debug source worktree but not the consumer's worktree. The handoff body's `**Reproduction test:**` (scientific) / `**Test file:**` (adversarial) lines remain as human-readable mirrors. Schema-version `m7-v1` legacy handoffs fall back to body-string parsing via `_shared/debug-handoff.md`.
- Reporter-only: NEVER ships code (no `git push` / `gh pr create`). The reproduction test is the only on-disk deliverable; the handoff file is the channel.

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
- Score-based ranking: recency × trust × access-count × recurrence. A learning's `recurrence_count` (incremented on each dedup-key re-emit by `emit-learning.sh`; absent treated as 1) folds in as a log-dampened factor `1 + ln(max(n,1))`, so absent/1 has no effect. Stale entries (score < 0.1, age > 180d, access_count == 0) auto-archived at SessionStart.

---

## Operational Rules (from report.md)

- Hook blocking requires `exit 2`, not `exit 1` — `exit 1` is fail-open.
- SKILL.md must stay under 500 lines; extract reference material to sibling files.
- Beyond ~150 total CLAUDE.md instructions, compliance degrades uniformly (context rot).
- Skills cannot call other skills — use shared reference files + subagent delegation.
- Subagents cannot spawn sub-tasks; all orchestration happens at the top-level skill.
- MCP auth (OAuth) is silently lost after compaction; scheduled tasks cannot access MCP.
