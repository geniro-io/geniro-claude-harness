# Fable-5 loop/memory article — borrows implementation plan

**Source article:** explainx.ai/blog/fable-5-loop-design-self-correction-memory-guide-2026 ("Designing Loops with Claude Fable 5: Self-Correction and Memory Guide", Y. Thakker, 2026-06-10).

**Grounding:** every claim below was verified against live code by a 15-agent workflow (5 axes × map→propose→critique) on 2026-06-14, then spot-re-verified. Each proposal was adversarially stress-tested against Geniro doctrine (never-ship / always-ask / orchestrator-owns-judgment / no-hard-caps / never-silently-drop) before inclusion. Items that failed doctrine were rejected, not softened (see §Non-goals).

**User decision:** implement Tier A + Tier B as one cohesive change. Tier C (doc-only) is included as an optional appendix.

---

## Contents

- [Unifying thesis](#unifying-thesis)
- [What we already exceed (no work)](#what-we-already-exceed-no-work)
- [The six items](#the-six-items)
- [Sequencing](#sequencing)
- [Non-goals (rejected by doctrine)](#non-goals-rejected-by-doctrine)
- [Cross-cutting compliance checklist](#cross-cutting-compliance-checklist)
- [Appendix — Tier C](#appendix--tier-c-optional)

---

## Unifying thesis

Five of the six items are **one defect class**: `/plan` (producer) authors a contract field — `Done Condition` (section 11), `Validation` (section 9), `budget` (frontmatter), the L2 `trust` enum — that the consumer (`/implement`, or the memory layer) **verifiably ignores at runtime**. The article's lens — *"a well-designed rubric performs more work than the model"* — names what we built but never wired. Our own producer/consumer-lockstep rule (CLAUDE.md §State Files) already classifies a producer field with no consumer as a bug, so this is gap-fill, not new architecture.

The article's *autonomy* framing (iterate-until-rubric-satisfied, automatic grader agent) is deliberately **not** borrowed — it would remove the human gate at every loop exit. Every item below only ever *opens* an existing human gate or surfaces a passive signal; none auto-ships, auto-aborts, or moves a decision into a subagent.

---

## What we already exceed (no work)

- **Verifier sub-agents > self-critique** — fresh context-blind per-finding verifier with refute-by-default + actionability bar (`skills/_shared/finding-verification.md`, `agents/reviewer-agent.md` §verify-finding mode); `--deep` is the article's 3-vote majority verbatim (`skills/_shared/deep-mode.md`). `/implement` first-layer reviewers are independent forks, not self-critique (`skills/implement/SKILL.md` §Phase 3 anti-rationalization). **Ship nothing.**
- **Memory progression Fail→Investigate→Verify→Distill→Consult** — `verified` already means "ran a command", trust enum `{verified, retrieved, inferred}` is a strict superset of the article's binary, Consult = knowledge-retrieval agent at Phase 1 + `query-learnings` ranking. **Matches.** The one missing piece (a *coverage* metric) is item A2.
- **Compaction** — `lib/archive-stale.sh` archives by quality (`score<0.1 AND age>180d AND access==0`), never-delete, audit-trail — better than the article's calendar cadence. **Exceeds.**

---

## The six items

Each item lists: **What** · **Where** (content-anchored, no line numbers per `feedback_no_hardcoded_line_refs`) · **Reshape constraints** (doctrine guards — these are non-negotiable) · **Files** · **Tests/docs** · **Risk**.

### A1 — Activate the spec's Done Condition as a static check in `/implement`

- **What:** `/implement` Phase 3's `architecture` dimension checks spec-compliance only as *diff-vs-scope*; it never statically asks "does this diff achieve, or visibly progress toward, the spec's Done Condition signal?" The static check (#10 "Done Condition Met") exists but only in `/review`'s `spec-compliance` dimension, which `/implement` does not load. Wire it into the criteria `/implement` actually loads.
- **Where:** `skills/_shared/review-criteria/architecture-criteria.md` §spec-compliance sub-check — add a `Done Condition` paragraph that **references** (single-source, does not re-inline) `skills/_shared/review-criteria/spec-compliance-criteria.md` §10 "Done Condition Met".
- **Reshape constraints:**
  - Static diff-inspection only — **no command execution** (that is B1's job).
  - Single-source via cross-reference to §10; do not copy the regex ontology.
  - Honors the prose-fallback already in §10 (skip when PLAN CONTEXT lacks structured frontmatter; emit `open_questions[]` instead).
- **Files:** `architecture-criteria.md` (1 file).
- **Tests/docs:** none (criteria prose loaded by the reviewer-agent). No CLAUDE.md change.
- **Risk:** minimal — one cross-reference paragraph, no new behavior path, no execution.

### A2 — Surface a verification-coverage metric on the memory archiver

- **What:** The article's central memory insight — the *fraction* of memory that is verified-vs-guessed (66% vs 17%) is the differentiator. We have the `trust` field but **no site computes a verified-fraction**. Add a read-only `verified: N/total (P%)` line riding the archiver's existing per-entry iteration and the session-start hook's existing `systemMessage`.
- **Where:** `lib/archive-stale.sh` §stderr report (it already does `group_by` per `type` over the `processed` set) — add a `group_by((.trust // "inferred"))` tally + coverage ratio. `hooks/session-start-restore.sh` §`systemMessage` build — append the one-line suffix.
- **Reshape constraints:**
  - Denominator uses `(.trust // "inferred")` (three buckets `{verified, retrieved, inferred}`; **no phantom "absent" bucket** — absent folds into inferred, matching every canonical site).
  - Tally over the **live (non-deprecated)** set `((.deprecated // false) == false)` so archived guesses don't dilute the number.
  - Guard divide-by-zero on the existing `stale_count==0` idiom → print `coverage: n/a`.
  - **Passive** — surface the ratio for the human; **never** auto-route to `/debug` or auto-fire any skill.
  - Opt-out via `.geniro/safety.json memory.show_coverage` (default on), mirroring `memory.auto_archive_stale`.
  - Read-only — the hook still **never** writes state.md (its documented invariant); the only write is the existing learnings.jsonl auto-archive.
- **Files:** `lib/archive-stale.sh`, `hooks/session-start-restore.sh`, CLAUDE.md (§Memory Layers note + §allowlist `memory.show_coverage` row), `tests/lib/archive-stale.sh` + `tests/hooks/session-start-restore.sh` (new assertions).
- **Risk:** low — purely additive read-only instrumentation; the divide-by-zero and opt-out are the only edge cases, both bound to existing idioms.

### A3 — Activate `budget` as a soft escalation signal in `/implement`

- **What:** `/plan` authors `budget.{max_files_to_edit, max_lines_changed}`, but `/implement`'s early "Cost / scope drift" escalation measures against the codebase-explorer `change_scope` tier, **not the user's declared number**. A user who writes "max 10 files" gets a tier-based heuristic that may never trip. Feed the user's own number into the existing not-converging AUQ.
- **Where:** `skills/implement/SKILL.md` §Phase 2 Step 6 early-escalation triggers ("Cost / scope drift" bullet) — add the `budget`-breach signal feeding the **same** AUQ.
- **Reshape constraints:**
  - **Signal into the existing escalation, never a stop** — no auto-abort, no mid-edit block, never presented as a hard ceiling (honors "No hard kill caps").
  - **Dedupe** with the existing tier-based scope-drift trigger — one scope-drift escalation per run, whichever fires first; AUQ names which bound was crossed.
  - **`null`/absent budget disarms** the trigger (not a degenerate zero-ceiling).
  - **Plain-English AUQ** — "this is turning out larger than the size you set in the spec", never surface `max_files_to_edit` / `budget` raw field names (fresh-user test).
- **Files:** `skills/implement/SKILL.md` (Step 6), CLAUDE.md `/implement` row (one clause).
- **Risk:** low — the dedup + once-per-run + null-disarm neutralize the only failure mode (a too-tight user budget nagging). It's the user's own number, so not an imposed restriction.

### B2 — Annotate the Ship AUQ with unmet machine-checkable Done-Condition clauses

- **What:** Extend A1 from static-diff to a clause grader at ship time: when a Done-Condition clause is *machine-checkable* (matches the validator's `stopping_condition` ontology) and **affirmatively unsatisfied** (e.g. "PR approved" — not yet true), annotate the **existing** Ship-mode AUQ so the user decides with their own criteria in view.
- **Where:** `skills/implement/SKILL.md` §Ship sub-step AUQ — add the clause-check annotation. New helper `skills/_shared/done-condition-check.md` defines the clause→evidence mapping only (test-runner `ALL_GREEN`, reviewer-clean, PR-state) — pure evidence cross-reference, **no judgment authority**, orchestrator reads it.
- **Reshape constraints:**
  - **Advisory, escalate-on-doubt, never an exit precondition** — on a satisfied/clean check, proceed silently; **do not fire an AUQ with nothing to decide** (mirrors spec-challenge implement-mode skip-when-clean).
  - **Ontology-bound** to the existing `stopping_condition` regex set (`validator-checks.md`: `tests? (pass|green)`, `PR (approved|merged)`, `telemetry…shows`, `shipped/released to`). Un-parseable / free-text clauses stay human-eyeball-only — never auto-graded.
  - **Fold into the existing Ship AUQ** — an annotation on its question text, not a second parallel gate (one decision, one gate).
  - **Can only open a gate, never close one** — a satisfied Done Condition still routes through the unchanged commit-grade Ship AUQ; the check never widens into ship authorization.
  - **Orchestrator-inline** — no grader agent.
- **Files:** `skills/implement/SKILL.md` (Ship sub-step), `skills/_shared/done-condition-check.md` (new helper), CLAUDE.md `/implement` row.
- **Dependency:** conceptually after A1 (both read section 11); independent edit sites.
- **Risk:** medium — the ontology-binding is what prevents free-text false-nags; must be held tight.

### B1 — Optional per-criterion `verify:` command in the spec, executed at `/implement` completion

- **What:** The most article-faithful move ("rubric performs work"). The only command `/implement` runs is the project-global `TEST_COMMAND` — zero link to the spec's own acceptance criteria. A feature can pass the global suite while not meeting its measurable criterion. Add an optional `verify:` command per criterion in the spec's Validation section (section 9); `/implement` runs each once at end-of-Phase-2 and attaches evidence.
- **Where:** Producer — `skills/plan/spec-template.md` §9 Validation (add optional `verify:` per criterion) + `skills/plan/validator-checks.md` (shape-only check: if present, must be a non-empty string). Consumer — `skills/implement/SKILL.md` §Phase 2 end-of-phase (after suite goes `ALL_GREEN`, the **orchestrator** runs each `verify:` string).
- **Reshape constraints:**
  - **Orchestrator runs the `verify:` strings** via its own Bash — do **not** overload `test-runner-agent` (its single-command leaf contract is a deliberate safety boundary; its anti-rationalization forbids it orchestrating). No agent-report schema changes, sidestepping the lockstep cost on the agent side.
  - **Reuse the existing verdict taxonomy verbatim** — `{ALL_GREEN, HAS_FAILURES, INFRA_ERROR}`. Connection-refused / server-down → `INFRA_ERROR` (already routes to escalate-AUQ); assertion non-zero → `HAS_FAILURES` (existing gate). No new taxonomy, no new control structure.
  - **Bounded single-shot** — run once and report; **not** an iterate-to-green optimizer. The existing 3-retry fix loop already bounds convergence.
  - **A failing `verify:` surfaces to the user, never auto-resolves** — feed the same message-first escalation-AUQ digest; the human stays the ship decider.
  - **No progressive rubric-tightening** (a tightening-threshold loop is a new control structure with no consumer — explicitly out of scope).
  - **Schema-lockstep** — this is the one new *producer* field; `spec-template.md` + `validator-checks.md` + `/implement` consumption move together (memory: state-file schema propagates new fields). `MIGRATION.md` gets an entry (new optional spec field, backward-compatible: absent `verify:` = today's behavior).
- **Files:** `skills/plan/spec-template.md`, `skills/plan/validator-checks.md`, `skills/implement/SKILL.md`, `MIGRATION.md` (new entry), CLAUDE.md `/plan` + `/implement` rows, `tests/` for the validator shape-check if a validator test exists.
- **Risk:** medium-high (largest blast radius — producer schema + consumer + migration). Backward-compatible by design (optional field).

### B3 — `## Carried-over` digest on `/review` re-runs (progressive-tightening, doctrine-safe)

- **What:** The round counter is the one place Geniro actually iterates, so the article's "progressive tightening" lands here. Problem: a MEDIUM the user *consciously declined* re-surfacing identically every round trains alert-fatigue and erodes review trust. Fix it **without** silently dropping anything.
- **Where:** `skills/review/phase-1-triage-reference.md` §re-review AUQ (round ≥2) — add the carry-over option + the `repeat-of-prior-round` marker via the existing `PRIOR-ROUND FINDINGS:` slot. `skills/review/SKILL.md` §4.1/Phase 5 stratify — add the `## Carried-over from round N` tier + promote-on-new-signal rule.
- **Reshape constraints:**
  - **Not an admission-bar raise** — that makes findings vanish (forbidden: "users notice when their MEDIUMs vanish") and adds a second auto-decided scope lever next to the always-ask hardening.
  - A repeat unfixed/unchanged finding **demotes to a visible collapsed `## Carried-over from round N` digest** (sibling of `## Deferred — sub-threshold`) — **never dropped, never removed from the handoff body**.
  - **Promotes back to active `## Findings` only on a new signal** — fresh convergence, newly-reachable code path, or a Phase 4.2 verifier `confirmed` absent last round. New findings keep the standard multi-signal gate.
  - **The user authorizes the de-emphasis** — fold the carry-over-vs-keep-active choice into the **existing** round-≥2 re-review AUQ (which already always-fires); persist to `approvals[]` category `rereview_repeat_handling`; re-apply on compaction-resume; **never inherit silently** across a fresh re-run.
  - `repeat-of-prior-round` is a **marker, not a filter** — drives *which section* renders, never *whether*.
  - Author note: the round counter increments only on same-`pr-ref` re-runs (a fresh PR gets a fresh bar) — record so a future author doesn't "fix" it.
- **Files:** `skills/review/phase-1-triage-reference.md`, `skills/review/SKILL.md`, CLAUDE.md `/review` row (Carried-over tier mention).
- **Risk:** medium — must stay bound to the existing visible-deferral machinery and the always-ask AUQ; the marker-not-filter rule is the load-bearing guard.

---

## Sequencing

Three waves; within a wave, items touch disjoint subsystems and can be done in any order.

| Wave | Items | Rationale |
|------|-------|-----------|
| **0 — isolated** | A2 (memory coverage), B3 (`/review` carried-over) | Disjoint subsystems (lib+hook; `/review`). Clean standalone wins that validate nothing downstream depends on. |
| **1 — `/implement` reads existing spec fields** | A1 (Done Condition static), A3 (budget signal), B2 (Done Condition Ship-AUQ) | All activate *existing* `/plan` fields — **no producer schema change**. A1 before B2 (both read section 11). |
| **2 — one new producer field** | B1 (`verify:` command) | The only schema-lockstep change; do last, after the cheaper activations prove the dead-field-activation pattern and after B2 establishes the Done-Condition consumption path. |

Recommended commit granularity: one commit per item (per `skill-prose.md` migration-audit guidance "one skill per commit"), so each is independently revertable. Run `bash tests/run-all.sh` + `tests/authoring/lint-skills.sh` before each commit.

---

## Non-goals (rejected by doctrine)

| Article idea | Why rejected |
|---|---|
| Autonomous `/goal` iterate-until-rubric spine | Removes the human gate at loop exit (invariant #5 "Escalation gates, not silent abort"). |
| Automatic grader agent decides pass/fail | Moves the decision into a subagent — violates orchestrator-owns-judgment. |
| Hierarchical loop-of-loops | Against no-unbounded-looping; Geniro is flat per-skill loops + one-shot handoffs by design. |
| Session-count compaction cadence ("every 10 sessions") | Calendar instead of staleness — regresses against score-based archival (recently-useful entries archived, stale entries in low-session repos missed). |
| Hard budget / cost ceiling stop | "No hard kill caps" — budget may only be a signal into escalation (that's A3). |
| Progressive rubric-tightening loop | New control structure with no consumer; conflicts with single-shot-spec → retry-to-green. |

---

## Cross-cutting compliance checklist

Apply to every item before its commit:

- [ ] **Plain-English user-facing strings** (fresh-user test) — every new AUQ `question`/`header`/option label; no `budget`/`max_files_to_edit`/`approvals[]`/phase-number jargon leaks.
- [ ] **Content-anchored references** in skill bodies — section/anchor names, never line numbers.
- [ ] **State-file schema lockstep** — B1 only: `spec-template.md` + `validator-checks.md` + `/implement` consumption + `MIGRATION.md` move together.
- [ ] **Tests for hook/lib changes** — A2 only: new assertions in `tests/lib/archive-stale.sh` + `tests/hooks/session-start-restore.sh`.
- [ ] **No new caps/forbids without opt-in** — A3 budget is user-authored (OK); A2 coverage is opt-out via `safety.json` (OK).
- [ ] **Doc updates** — CLAUDE.md rows + (B1) MIGRATION.md entry + (A2) §allowlist row.
- [ ] **Authoring rules** — `.claude/rules/skill-authoring.md` (no plugin-internal narration shipping to consumers), `.claude/rules/skill-structure.md` (file-size, anti-rat ≤15 rows), `.claude/rules/skill-prose.md` (voice).
- [ ] **Green gate** — `bash tests/run-all.sh` passes; `tests/authoring/lint-skills.sh` no new hard-fails.

---

## Appendix — Tier C (optional)

**C1 — Record the deliberate non-coverage in `ARCHITECTURE.md`.** ~12 lines: a "patterns we deliberately decline" subsection documenting (a) flat per-skill loops + one-shot handoffs (no outer maintenance loop), anchored by the fact "every SKILL.md `/geniro:` reference is a one-shot handoff, none drive another skill's iterations"; (b) quality-threshold archival, never a fixed every-N-sessions cadence — "a session counter targets the calendar, not actual staleness", anchored by the `archive-stale.sh` score<0.1/age>180d/access==0 predicate (anchor by predicate, not line number). Ends the recurring re-proposal churn that *this very analysis* is an instance of. Near-free; the only failure mode is doc drift if the flat-loop architecture later changes (low — flat-loop is foundational).
