# /geniro:refactor — Phase 3: verify

Phase body for `${CLAUDE_PLUGIN_ROOT}/skills/refactor/SKILL.md`. Read on entry to Phase 3, and again on any resumption of it, including after a compaction. The spine keeps the state machine, the loop invariants, the anti-rationalization table, the budgets, §Git constraint and the tool surface — this file carries the Steps. Bare `§3.M` refs below point at this file's own sub-sections; `§ <name>` refs name a section inside the cited helper, and a `Phase 1 §1.M` / `Phase 2 §2.M` ref points at the sibling phase file (`refactor/SKILL.md` for Phase 1, `refactor/phase-2-apply.md` for Phase 2).

## Contents

- 3.1 Diff sanity (all tiers)
- 3.2 Independent reviewer-agent + custom reviewers (Medium+)
- 3.3 Orchestrator disposition logic — PRODUCT-DECISION escalation, the ADR path, the 1-round fix loop
- 3.4 Completion summary
- 3.5 Emit learnings + the recurring-pattern rule-capture offer
- 3.6 Cleanup

---

## Phase 3 — verify

state.md `phase: verify`. Diff sanity + independent review + completion summary + L2 emit + cleanup. No `git push` / `gh pr create` — refactor never ships code, only produces a working-tree diff (deliverable) and a state-file audit trail.

### 3.1 Diff sanity (all tiers)

Run `git diff --name-only` and `git diff --stat`. Cross-check state.md `## Plan steps` rows' `files_affected` aggregated list against the actual diff — flag mismatches.

If final regression failed AND user picked "Revert all changes", state.md is already `phase: reverted` — skip to cleanup (no review needed).

### 3.2 Independent reviewer-agent + custom reviewers (Medium+)

Skipped for Trivial and Small per Step 3.

**Resolve `PRIMARY_ROOT` first.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` via Bash before invoking the custom-reviewer helper — the helper requires the slot in scope to dual-glob local + main-worktree `review-extra/` files, and a linked worktree's `.geniro/instructions/` is gitignored and may be empty.

For Medium and Big: spawn a fresh reviewer-agent (focus areas — accidental public-API changes / test assertion mutations / invariant drift / new coupling / dead-code removal that had references) PLUS any custom reviewers discovered via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` (matched by `paths:` filter against changed files). All spawns go in ONE parallel batch — same assistant response. The reviewer-agent reads `bugs-criteria.md`, `architecture-criteria.md`, `tests-criteria.md` itself; do NOT pre-read into orchestrator context.

Full spawn template (acceptance criteria, pre-inlined `code-style.md`, focus areas, criteria-file list, output schema) in `${CLAUDE_PLUGIN_ROOT}/skills/refactor/refactor-reference.md` §3.

### 3.3 Orchestrator disposition logic

**PRODUCT-DECISION findings → escalate (always wait for the user, every tier):**

Escalate every PRODUCT-DECISION finding to `/geniro:implement`; never gate-and-fix it in-skill (SKILL.md §Anti-rationalization carries why).

Gate every PRODUCT-DECISION finding per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question-reference.md` § Single-finding gate (`header: "Escalate"`): render the finding to a chat message first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — the opener, conversational lead, why-it-matters with evidence cite, and visual per the reference's § Finding-type visual map — then fire the lean `AskUserQuestion`. 4 fixed options (ADR-eligibility determines whether 4th option included):

1. **Run /geniro:implement on this finding (Recommended)** — exit /geniro:refactor; user runs /geniro:implement separately to apply a behavioral fix. state.md → `phase: routed` (terminal — recovery treats as complete; the decision was handed to /geniro:implement). Without a terminal write here the run would resume re-surfacing an already-resolved escalation.
2. **Revert this refactor and start over** — `git restore --source=HEAD -- <each path from git diff --name-only>` (per SKILL.md §Git constraint) with user confirmation. state.md → `reverted` (terminal).
3. **Document and keep the diff as-is — accept the open decision** — keep the working-tree diff, note the deferred decision in completion summary. state.md → `verify-summary-only` (terminal). The user takes the responsibility of resolving the decision later.
4. **(ADR-eligible only)** **Document as ADR** — spawn a focused ADR-drafting agent (OMIT `model=` — inherits the orchestrator's session tier per the canonical model-tiering rule and the table row in SKILL.md §Subagent model tiering) to draft the ADR per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/improvement-routing.md` § ADR template; write to `docs/adr/NNNN-<slug>.md` (next sequential N; create directory if missing, after `AskUserQuestion` confirmation). state.md → `adr-documented` (terminal).

**ADR-eligibility check (before adding 4th option):** include the "Document as ADR" option ONLY when the rejected refactor candidate meets all three criteria from `improvement-routing.md` § ADR target: (1) hard to reverse, (2) surprising without context, (3) result of genuine trade-offs. Examples that qualify: rejecting "split this god-class into 3 modules because the team prefers single-file feature ownership" (the *rejection* is the durable decision); rejecting "switch from inheritance to composition here because the existing inheritance is load-bearing for the plugin system." Examples that do NOT qualify: rejecting a duplicate-extraction smell because the duplication is intentional (Rule of Three not yet met) — that's a learning, not an ADR. If unsure, omit the ADR option; routing to Knowledge is always safe.

**Approvals-persistence:** before firing the PRODUCT-DECISION AUQ, check state.md frontmatter `approvals[]` for a prior entry with `category: refactor_product_decision` matching the finding (use finding `path:lines` + decision-type as disambiguator). If found, use prior `picked` value. If not found, fire AUQ → on user pick, append to `approvals[]` via `atomic_state_write` BEFORE executing the chosen action.

Fire one `AskUserQuestion` per PRODUCT-DECISION finding; chain across findings — never batch multiple findings into a single question.

**CRITICAL or HIGH (non-PRODUCT-DECISION) findings → fix loop (max 1 round):**

Orchestrator-inline addresses specific findings (Edit per finding); then re-spawn reviewer-agent fresh on the updated diff. After 1 round, if still failing — surface to user via AUQ header "Findings remain" with options: "Escalate to /geniro:implement" / "Document remaining findings and keep the diff as-is" / "Revert all changes". state.md → `verify-escalated` with timestamp + 1-round fix attempt summary.

**MEDIUM findings only → note in completion summary; proceed.**

**No findings → proceed.**

### 3.4 Completion summary

Output the markdown block directly in chat. No persistence to a handoff file — diff IS the deliverable.

On the Trivial and Small tiers, drop the "Filtered smells" and "Review Findings" sections entirely: neither the smell-evidence filter nor the reviewer batch runs at those tiers, so both would render empty.

```markdown
## Refactor Complete

### Transformations Applied (N)
- [file:line] — [what changed] — risk: [LOW/MEDIUM/HIGH] — consumers: N

### Blocked Steps (N)
- [file:line] — [what was attempted] — reason: [failure summary]

### Filtered smells (intentional patterns) (N)
- [smell] — [reason filtered]

### Review Findings
- CRITICAL: N, HIGH: M, MEDIUM: K
- Disposition: [proceeded / 1-round fix loop / escalated / ADR documented]

### Validation
- Tests: PASS/FAIL
- Baseline delta: [before→after test count]

### Files Modified: N
- [file path]: [one-line summary]

### Deferred
- [low-priority item deferred, or a HIGH-risk step you declined]

### Next steps
[The diff is in your working tree. Commit it yourself, or run `/geniro:implement` to ship with a review gate.]
```

### 3.5 Emit learnings

At Phase 3 exit:

- **`emit-learning`** — called by /geniro:refactor for two emit types per canonical contract:
- **`discovery`** — emit when a pattern was extracted to a shared utility/component (typical /geniro:refactor outcome). Required `ext.{area, insight}` per typed-extension table. Default trust `verified`.
- **`pitfall`** — emit when the refactor revealed a footgun (a seemingly-safe pattern that actually breaks under specific conditions). Required `ext.{trap, mitigation}`. Default trust `verified`.
- **Echo + ordering:** after a successful emit, echo `Recorded learning: <summary>` to the user, and fire the emit before declaring Phase 3 done — per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract". A silent emit trailing the phase's done declaration is the documented drop vector.

**Offer to capture a recurring pattern as a project rule** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/recurrence-rule-capture.md` with `LEARNING_NOUN: pattern`, the refactor scope routing (`discovery` pattern extracted → `code-style.md`; `discovery` architectural insight → `global.md`; `pitfall` refactor-specific footgun → `refactor.md`; otherwise the user picks), and rejection args `"/geniro:refactor" "refactor/<scope>" "promote_pattern_to_rule"`. The helper reads the just-emitted entry's `recurrence_count` back (routed to the memory backend under a `## Memory Backend` block per its §0) and gates the offer on `>= 3`.

### 3.6 Cleanup

After Phase 3 completes:

- **All tiers:** `rm -rf .geniro/state/refactor/<slug>/` (cwd-relative — within-skill resume-from-compaction state per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` § "Artifacts NOT in scope") for the current branch's slug only, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Cleanup contract — the whole slug dir, so any scratch written under it goes with `state.md` (nothing there is read after the run, and the migration sweep does not scan `.geniro/state/`). Useful content already saved (transformations, discoveries) via L2 emit + chat summary. Do NOT delete sibling slugs from concurrent refactor sessions on other branches.
- **No handoff file to delete or persist**.
- Kill any background processes started during the run (test watchers, profilers).

Cleanup is best-effort — failed commands silently OK.
