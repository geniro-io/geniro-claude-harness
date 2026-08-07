# /analyze-thread — Phase 3 & Phase 4

Phase bodies for `.claude/skills/analyze-thread/SKILL.md`. Read on entry to Phase 3; re-read on entry to Phase 4 and on any resumption of either, including after a compaction — the spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done, this file carries the Steps.

## Contents

- Phase 3 — Filter (Steps 1-2)
- Phase 4 — Present (Steps 1-6, incl. the per-finding gate and the handoff emit)

---

## PHASE 3: FILTER (orchestrator-inline)

**Purpose:** Merge the batch, then triage raw findings to TRUE-POSITIVE / UNCERTAIN / drop the rest. No subagent — this is reasoning over Phase 2's structured output.

### Step 1: Merge across threads (batch only)

Collapse findings that share a `check_id` AND the same underlying defect into ONE finding carrying `threads: [<thread_id>, ...]`. Same check on a genuinely different root cause stays separate — the test is whether one fix in one place resolves every occurrence. Keep each thread's evidence range under its own thread id; a merged finding's evidence reads `<thread_id>:<event range>` per occurrence.

Recurrence then feeds triage: a defect confirmed in 2+ threads is systematic rather than incidental, so it enters Step 2 one confidence level higher (low → medium, medium → high) and sorts above single-thread findings of equal severity. It never raises severity — how often a defect happens and how much damage it does are independent.

In single mode this step is a no-op; every finding carries one thread id.

### Step 2: Tag each finding

For each finding, the orchestrator tags one of four:

| Tag | When | Action |
|---|---|---|
| **TRUE-POSITIVE** | High confidence + evidence event range cleanly matches the check spec + no contradicting context | Keep; default-include in Phase 4 handoff |
| **UNCERTAIN** | Medium/low confidence, OR evidence range ambiguous, OR judge tagged as "plausible but contestable" | Keep; per-item AUQ in Phase 4 |
| **REDUNDANT** | Duplicate of another finding **within the same thread** (same root cause, different surface symptom), OR mechanical-and-judge both flagged the same event range | Drop; merge evidence into the surviving finding. The same defect in a DIFFERENT thread is never redundant — Step 1 already merged it and its recurrence is the signal (invariant #4) |
| **FALSE-POSITIVE** | The mechanical regex matched a benign case (e.g., A6 over-spawn flagged a TodoWrite that legitimately listed 5 parallel items), OR the judge flagged something that contradicts a documented exception in the skill body | Drop; log reason for Phase 4 transparency section |

For NOVEL findings: always UNCERTAIN unless the rationale ties to a documented anti-rationalization row in some skill body's table — then TRUE-POSITIVE.

Write Phase 3 checkpoint with `findings-kept: <count>`, `filtered: <count + reasons summary>`, and in a batch `merged: <raw count> → <merged count>`.

---

## PHASE 4: PRESENT (WAIT — user gates)

**Purpose:** Show the user grouped findings, gate UNCERTAIN ones individually, and emit the handoff.

### Step 1: Print the findings table

Group by category. Within each category, sort by recurrence (most threads first), then severity (blocker → warning → nit), then confidence (high → low).

```
## Analysis: <thread basename, or "N threads" in batch mode>

Analyzed:
- <thread_id> · <date> · <project label> · <title> · <events> events · Geniro-run: <yes/no — skill: <name>>
- (one line per thread; in single mode this is one line)
Skipped: <thread_id> (still being written) · <thread_id> (7.2 MB, over the 5 MB cap)

### Coverage — what the run declared vs. what it did
| What | Declared | Ran | Gaps |
|---|---|---|---|
| Custom instruction files | 4 | 3 | code-style.md never loaded (finding #2) |
| Instruction blocks applied | 9 | 7 | 1 additional step never ran, 1 data source never consulted (#4, #7) |
| Phases entered | 6 | 6 | — |
| Phase bodies read on entry | 6 | 4 | Phases 3 and 5 ran without reading their steps (#1) |
| Approval questions | 5 | 4 | the ship gate never fired (#3) |
| Custom reviewers wired in | 2 | 2 | — |

### Confirmed findings (default-include)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Suggested fix target |
|---|---|---|---|---|---|---|---|
| 1 | 3/3 | Subagent spawning | A1 missed parallel-spawn | warning | high | a1f42fdd:12-14 · d34948e9:88-91 · 0cd65de4:40-44 | skills/review/SKILL.md §Phase 2 |
| ...

### Uncertain findings (gated below)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Rationale |
| 5 | 1/3 | Context | H1 first-vs-last contradiction | warning | medium | a1f42fdd:4 vs 198 | judge: "user asked X early, agent did not-X at the end without acknowledgement" |
| ...

### Filtered (transparency)
- a1f42fdd check_id=A6 event-range=22-23 — FALSE-POSITIVE: TodoWrite legitimately listed 5 items, not duplicate spawns
- a1f42fdd check_id=E4 event-range=87 — REDUNDANT: same root cause as finding #3
```

Drop the `Threads` column in single mode — a column reading `1/1` on every row is noise.

The coverage table is a scoreboard, not a second findings list: every gap cites the finding carrying its evidence, and a gapless row still renders, because "6 of 6 phases ran" is the result the user came for on a clean run. Render it only where the expectation set is non-empty. In a batch, one table per thread — Phase 3's merge applies to findings, and averaging two runs' coverage hides which one had the gap. Name the degradation level under the table when there was one: a `4 / 3` on a partial trace means a load was not visible, not that it did not happen.

### Step 2: Gate uncertain findings

For EACH uncertain finding, render it to chat first and then fire a lean `AskUserQuestion` — the message-first shape in `skills/_shared/per-finding-question.md` §Message-first rendering (do NOT batch into one multiSelect — per-finding gating is what the user asked for):

1. **Render the finding to a chat message before the question fires**, as its own separate assistant message: a plain-English title using the check's `Name` column from `checks-reference.md` (never the bare `<check_id>` — that identifier fails the fresh-user test on its own), what the trace shows, why it matters, the evidence excerpt, and the three options below with their consequences.
2. **Then fire a lean `AskUserQuestion`** that points at the chat message rather than restating its rationale:
   - **Question:** "Finding #<N> (<plain-English name>; seen in <M> of <T> threads): keep, drop, or challenge?"
   - **Options:**
     - "Keep — include in handoff"
     - "Drop — false positive"
     - "Challenge — show me the full evidence excerpt and re-decide" (loops back with the full thread slice)

Process answers in sequence. Add KEPT items to the confirmed list; record DROPPED items in the filtered section.

### Step 3: Final user gate on confirmed list

Skipped under `--no-handoff`: the modifier already answered the handoff-destination question in the negative, so asking again is redundant. Print the confirmed list, then go to Step 6.

Print the updated confirmed list (including newly-promoted UNCERTAIN items). Fire ONE final `AskUserQuestion`:

- **Question:** "Confirmed findings ready. How to hand off?"
- **Options:**
  - "Emit handoff and launch /improve-template now (Recommended)"
  - "Emit handoff only — I'll run /improve-template later"
  - "Drop specific findings before handoff" — loops back with multiSelect over the confirmed list
  - "Skip — no handoff; the printed report is enough"

### Step 4: Emit the handoff

If the user chose either of the first two options, write `.geniro/state/handoff/from-analyze-thread-<branch>.md` via `atomic_state_write`. Emit each kept finding as a machine-readable `open_questions[]` frontmatter entry per the T2 contract in `skills/_shared/state-tier-spec.md` §T2 (each entry needs `id` / `source` / `question` / `status`; `severity`, `recurrence`, and `suggested_action` are producer-specific extensions). The body `## Open questions` block is a human-readable mirror only — the frontmatter array is the source of truth a consumer parses.

```yaml
---
tier: T2
producer: analyze-thread
schema-version: 1
branch: <current branch>
timestamp: <ISO-8601 UTC>
consumer: improve-template
source_threads:                        # one entry per analyzed thread; single mode has one
  - id: <thread_id>
    path: <path>
findings_count: <N>
open_questions:
  - id: q1
    source: <check_id>                 # the check that surfaced the finding, e.g. A1
    question: "<one-line finding summary>"
    context: |                         # OPTIONAL — 2-6 line problem framing
      <category> — <what the trace shows>. Suggested target: <file>.
    related_findings: []               # finding has no /review F-id; leave empty
    severity: <blocker|warning|nit>    # producer-specific extension
    recurrence: <M>/<T>                # producer-specific extension — threads hit / threads analyzed
    suggested_action: <one sentence — usually "rewrite instruction at <anchor>" or "add anti-rationalization row" or "extend Phase N gate">
    status: unresolved
  # (one entry per kept finding: q2, q3, ...)
---

## Open questions
- [ ] q1 (<check_id> — <category>, seen in <M>/<T> threads): <one-line>. Target: <file>. Evidence: <thread_id>:<range>. Suggested action: <one sentence>.

(one bullet per kept finding, mirroring the frontmatter entry by `id`)
```

`/improve-template` reads this handoff when invoked with the `process-handoff` argument (its mode-detection → handoff-ingestion path) and routes each parsed finding to its appropriate flow (Phase 1-fast / full pipeline depending on complexity).

### Step 5: If "launch now", invoke /improve-template

Print a one-line summary of the handoff and call `/improve-template` with `$ARGUMENTS` set to "process handoff from analyze-thread". `/improve-template` will pick up the handoff file from its standard read location.

If the user chose "emit handoff only" or "skip": print the handoff path and the exact command (`/improve-template process-handoff`) for them to run later.

### Step 6: Cleanup

`rm -rf .geniro/state/analyze-thread/<slug>/` per the helper § Cleanup contract — the whole slug directory, and only this run's slug, never globbing sibling slugs.

The handoff file at `.geniro/state/handoff/from-analyze-thread-<branch>.md` is T2 and survives until `/improve-template` consumes it (per the standard handoff lifecycle in `skills/_shared/state-tier-spec.md`).
