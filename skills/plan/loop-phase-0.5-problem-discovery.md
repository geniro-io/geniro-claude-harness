# Phase 0.5 — Problem discovery (opt-in, fires only on `--prd`)

A phase file of the `/geniro:plan` loop. The spine — HARD-GATE, gate presentation contract, echo contract, phase order, terminal states, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`.

State.md `phase: problem-discovery` during this phase. **Fires only when `prd_mode: true`** (set in Phase 0.1 from a `--prd` flag in `$ARGUMENTS`). When `prd_mode` is unset, skip this phase entirely — the loop transitions Phase 0 → Phase 1 unchanged.

This phase runs a problem-first discovery interview BEFORE explore and clarify, so the eventual spec is grounded in a validated problem rather than a presumed solution. Unlike the Phase 3 clarifying questions (asked one at a time), the six discovery dimensions are a fixed independent interview set, so batch them into AUQ calls (≤4 questions per call; chain a second call past the cap rather than drop a question — the 4-question-per-call tool limit applies here too) to keep the upfront interview compact.

### 0.5.1 Interview dimensions

Ask one question per dimension, batched per the cap rule above (two calls of ≤4 questions):

| Dimension | What it captures | Why it's load-bearing |
|---|---|---|
| Problem statement | The problem in one sentence, framed as the pain — not a feature ("users abandon checkout at the address step", not "add address autocomplete"). | A solution chosen before the problem is named bakes in the wrong assumption. |
| Evidence | What proves the problem is real — a metric, a support-ticket count, a recorded session, a quote. | Distinguishes a real problem from a guessed one; an unevidenced problem routes to "gather evidence first". |
| Target user + job-to-be-done | Who has the problem and the job they are trying to get done. | Scopes the solution to a user and a job, not "everyone, vaguely". |
| Hypothesis | A testable "if we do X, then metric Y moves by Z" statement. | Makes success falsifiable — the spec can be validated against it. |
| Success metrics | The 1-3 metrics that confirm the problem is solved. | Feeds spec section 9 (Validation) and section 11 (Done Condition). |
| Prioritization | Rough MoSCoW split (Must / Should / Could / Won't) of the candidate scope. | Pre-sorts scope before Phase 5; the Must set seeds section 2 (Scope — Included), the Won't set seeds section 3 (Scope — Excluded). |

Apply the Gate presentation contract: when a dimension needs framing the user can't act on from a one-line option (why the dimension is load-bearing, an example of a good answer), render that framing to a chat message first, then fire the batched AUQ with short option labels. Offer a free-text "Other" path on every question; for the open-ended dimensions (problem statement, evidence, hypothesis) the user will usually type rather than pick a canned option, so the canned options are illustrative anchors, not an exhaustive menu. When the user has no evidence, capture that honestly: record "evidence: none yet" and surface a one-line note that the problem is unvalidated — do not invent evidence.

### 0.5.2 Persistence

Append one entry to state.md frontmatter `approvals[]` per answered question via `atomic_state_write`, category `prd_<dim>` (e.g., `prd_problem_statement`, `prd_evidence`, `prd_target_user`, `prd_hypothesis`, `prd_success_metrics`, `prd_prioritization`). Same entry shape as Phase 3 (category / prompt / options / picked / at / asked_in_phase). Persisting here is non-negotiable: a context reset mid-plan would otherwise lose the entire problem framing, and the SessionStart re-injector renders `approvals[]` so a resumed session re-reads the answers and skips re-asking.

Also append a `## Problem Framing` body section to state.md capturing the synthesized free-text answers (problem / evidence / user + job / hypothesis / metrics / MoSCoW), so Phase 6 can copy it into the spec without re-deriving from `approvals[]`:

```markdown
## Problem Framing
- problem: <one-sentence pain statement>
- evidence: <metric / ticket count / quote, OR "none yet — unvalidated">
- target_user: <who> — job: <job-to-be-done>
- hypothesis: if <X> then <metric Y> moves by <Z>
- success_metrics: <1-3 metrics>
- moscow:
    must: [...]
    should: [...]
    could: [...]
    wont: [...]
```

### 0.5.3 Feed-forward

The problem framing feeds two downstream sites:

- **Phase 1 explore** — inline the `## Problem Framing` body into research-agent prompts under a `## Problem Framing` section, so research targets the named problem and its evidence rather than a presumed solution.
- **Phase 3 clarify + Phase 5 section authoring** — the Must/Should set seeds section 2 (Scope — Included); the Won't set seeds section 3 (Scope — Excluded); the success metrics seed section 9 (Validation) and section 11 (Done Condition); the problem statement and evidence populate the spec's optional `## Problem & Evidence` body section (Phase 6).

Section 1 (Objective) stays a single declarative goal sentence — NOT the problem statement (the validator's `single_objective` check enforces this). The problem framing lives in the separate `## Problem & Evidence` section; the Objective is the solution-goal derived from it.

### 0.5.4 Transition

After the interview persists, transition `phase: explore` and proceed to Phase 1 normally. Phase 1 now carries the problem framing as added context. All subsequent phases run unchanged except for the two feed-forward sites above and the Phase 6 `## Problem & Evidence` write.
