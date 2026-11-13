# /analyze-thread — Phase 3 & Phase 4

Phase bodies for `.claude/skills/analyze-thread/SKILL.md`. Read on entry to Phase 3, again on entry to Phase 4, and on any resumption (including after a compaction).

## Contents

- Phase 3 — Filter (Steps 1-3, incl. the `fix_kind` classification)
- Phase 4 — Present (Steps 1-6, incl. the per-finding gate and the handoff emit)

---

## PHASE 3: FILTER (orchestrator-inline)

**Purpose:** Merge the batch, triage raw findings to TRUE-POSITIVE / UNCERTAIN / drop the rest, and say what kind of change fixes each survivor. No subagent — this is reasoning over Phase 2's structured output.

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
| **REDUNDANT** | Duplicate of another finding **within the same thread** (same root cause, different surface symptom), OR mechanical-and-judge both flagged the same event range | Drop; merge evidence into the surviving finding. The same defect in a DIFFERENT thread is never redundant — Step 1 already merged it and its recurrence is the signal (the cross-thread-recurrence invariant) |
| **FALSE-POSITIVE** | The mechanical regex matched a benign case (e.g., A6 over-spawn flagged "duplicate" prompts that in fact targeted different `subagent_type`s — see `checks-reference.md` §6), OR the judge flagged something that contradicts a documented exception in the skill body | Drop; log reason for Phase 4 transparency section |

For NOVEL findings: always UNCERTAIN unless the rationale ties to a documented anti-rationalization row in some skill body's table — then TRUE-POSITIVE.

### Step 3: Assign `fix_kind`

Read `.claude/rules/skill-prose.md` first, every run, even when no finding looks like text: it is the yardstick for "changes nothing as written" and "rewrite the instruction" below. Give every kept finding exactly one `fix_kind` — the kind of environment change that would stop the defect recurring, which decides what `/improve-template` builds. Start from the default in `checks-reference.md` §9 and move off it only on trace evidence.

| `fix_kind` | The fix is | Example `suggested_action` |
|---|---|---|
| `DETERMINISTIC-CHECK` | a mechanical check — lint rule, test, CI step (not a hook: `HOOKS.md` §Removed guards) — that decides the violation without a model | add a lint over `<path>` that rejects `<pattern>` |
| `WIRE` | connecting something that exists but never fired — a declared step, helper, or check not wired in, silently broken, or buried below reference (the fix moves it) | call `<helper>` at `<anchor>`, where the skill declares it but never reaches it |
| `NAV-POINTER` | a one-line pointer to what the agent could not find or kept re-searching for | add one line to `<file>` pointing at `<path>` |
| `TOOL-CHANGE` | changing a tool, command, or agent so the expensive or looping call stops | run `<command>` through the test-runner agent, or cap its output with `<flag>` |
| `REMOVE-RULE` | deleting or merging a rule or step that changes nothing or conflicts with another | delete `<rule>` at `<anchor>` — it changed nothing in N threads |
| `PROSE` | rewriting or adding instruction text — only when no kind above fits | rewrite the instruction at `<anchor>` |

A rule is **loaded** when its file was listed as `Read: <path>` and then Read (or was Read directly in a Read-only load) — cite that Read, not the check that flags a missing one. For every `PROSE` or `REMOVE-RULE` finding, name the lever that failed — from the trace, not the check ID — and take its fix:

| Trace shows (rule loaded, then violated) | Lever | `fix_kind`: fix |
|---|---|---|
| A pointer is present but its target was never Read (K2, I1) | pointer wording | `WIRE`: sharpen the pointer's condition; inline the target if a sharpened pointer already failed |
| The rule was Read; its step was skipped while neighbouring reference was applied (K7) | buried step | `WIRE`: move the step above that reference, its text unchanged |
| "Done" claimed with work still open, later steps visible (D3, E2, a K7 tail) | vague completion criterion | 1 thread: `PROSE`, a checkable per-item exit criterion. 2+: `DETERMINISTIC-CHECK` or `WIRE` where the early exit leaves a mechanical signature (an open item, an unrun Definition-of-Done step); otherwise Filtered, bound stated |
| A prohibition held early in the run and broke late (H1, late E1) | negation | 1 thread: `PROSE`, the required behaviour restated. 2+: `DETERMINISTIC-CHECK` that rejects the forbidden act, or `WIRE`; otherwise Filtered, bound stated |
| The rule was Read and echoed, but the trace matches default behaviour (I8, H7) | no-op | `REMOVE-RULE` |
| Two loaded statements disagree, or the rule's caveat sits in a file the run never Read | scatter / duplication | `REMOVE-RULE`: one home; the rest cite it |
| The rule sits deep in a steering load ≥30% of input, or past the compaction boundary | sprawl | `NAV-POINTER`, or `WIRE` the rule into the spine |
| The step ran and came back shallow | none (capability bound) | No writing fix; state the bound in the Filtered section |

A loaded rule still violated in 2+ threads may not be `PROSE`: the text was in context and lost, so the lever leads to a check, pointer, `WIRE` (a step move included) or removal, not new wording; a row with none left goes to Filtered with the bound stated. A correct safety rule that was ignored (an approval gate, say) keeps its place: `WIRE`, `DETERMINISTIC-CHECK`, or `TOOL-CHANGE`.

Write Phase 3 checkpoint with `findings-kept: <count>`, `filtered: <count + reasons summary>`, and in a batch `merged: <raw count> → <merged count>`.

---

## PHASE 4: PRESENT (WAIT — user gates)

**Purpose:** Show the user grouped findings, gate UNCERTAIN ones individually, and emit the handoff.

**On entry, Read `.claude/skills/analyze-thread/analyze-thread-definition-of-done.md`** — this is the terminal phase, and that file is the run-completion checklist to walk before the handoff (or the skip) closes the run.

### Step 1: Print the findings table

Group by category. Within each category, sort by recurrence (most threads first), then severity (blocker → warning → nit), then confidence (high → low).

```
## Analysis: <thread basename, or "N threads" in batch mode>

Analyzed:
- <thread_id> · <date> · <project label> · <title> · <events> events · Geniro-run: <yes/no — skill: <name>>
- (one line per thread; in single mode this is one line)
Skipped: <thread_id> (still being written) · <thread_id> (7.2 MB, over the size cap)

### Coverage — what the run declared vs. what it did
| What | Declared | Ran | Gaps |
|---|---|---|---|
| Custom instruction files | 4 | 3 | code-style.md never loaded (finding #2) |
| Instruction blocks applied | 9 | 7 | 1 additional step never ran, 1 data source never consulted (#4, #7) |
| Phases entered | 6 | 6 | — |
| Phase bodies read on entry | 6 | 4 | Phases 3 and 5 ran without reading their steps (#1) |
| Approval questions | 5 | 4 | the ship gate never fired (#3) |
| Custom reviewers wired in | 2 | 2 | — |

### Cost — where the tokens went
| Phase | Calls | Peak context | Share of re-read context | Largest driver |
|---|---|---|---|---|
| Phase 1 | 22 | 61K | 4% | — |
| Phase 3 | 140 | 209K | 71% | 3 oversized results (#4) · 11-call search streak (#6) |
Steering files: 31% of input (#7) · Session cost: $17.13 · Subagents: 4 spawns, 410K tokens

### Confirmed findings (default-include)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Fix kind | Suggested fix target |
|---|---|---|---|---|---|---|---|---|
| 1 | 3/3 | Custom-instruction loading | I1 declared instruction file never loaded | blocker | high | a1f42fdd:12-14 · d34948e9:88-91 · 0cd65de4:40-44 | WIRE | skills/review/SKILL.md §Phase 1 |
| ...

### Uncertain findings (gated below)
| # | Threads | Category | Check | Severity | Confidence | Evidence | Fix kind | Rationale |
|---|---|---|---|---|---|---|---|---|
| 5 | 1/3 | Context | H1 first-vs-last contradiction | warning | medium | a1f42fdd:4 vs 198 | PROSE | judge: "user asked X early, agent did not-X at the end without acknowledgement" |
| ...

### Filtered (transparency)
- a1f42fdd check_id=A6 event-range=22-23 — FALSE-POSITIVE: the "duplicate" prompts targeted different `subagent_type` values (reviewer-agent for `bugs` vs `security`)
- a1f42fdd check_id=E4 event-range=87 — REDUNDANT: same root cause as finding #3
```

Drop the `Threads` column in single mode — a column reading `1/1` on every row is noise.

The coverage and cost tables are scoreboards, not second findings lists: every gap or driver cites the finding carrying its evidence, and a clean row still renders, because "6 of 6 phases ran" is the result the user came for. In a batch, one table of each per thread — averaging two runs hides which one had the gap. Render coverage only where the expectation set is non-empty; name the degradation level under it when there was one, since a `4 / 3` on a partial trace means a load was not visible, not that it did not happen.

Cost rows come from the numbers H4-H7 recorded in Phase 2 (`checks-reference.md` §3 H-class): one row per declared phase, or a single `whole thread` row when there are none. Peak context is the largest per-call context in the phase; the share column divides the phase's summed per-call context by the thread's, because every call re-reads the whole context. Take the session cost from the log's last `cost-state` event (each one is cumulative) when present and omit it otherwise. A markdown export or a log without usage fields gets one line saying the cost table is unavailable, not an empty table.

### Step 2: Gate uncertain findings

For EACH uncertain finding, render it to chat first and then fire a lean `AskUserQuestion` — the message-first shape in `skills/_shared/per-finding-question.md` §Message-first rendering (do NOT batch into one multiSelect — per-finding gating is what the user asked for):

1. **Render the finding to a chat message before the question fires**, as its own separate assistant message: a plain-English title using the check's `Name` column from `checks-reference.md` (never the bare `<check_id>`), what the trace shows, why it matters, the evidence excerpt, the kind of fix it would get in plain words (a new check, a pointer, a tool change, a rule removal, or rewritten text), and the three options below with their consequences.
2. **Then fire a lean `AskUserQuestion`** that points at the chat message rather than restating its rationale:
   - **Question:** "Finding #<N> (<plain-English name>; seen in <M> of <T> threads): keep, drop, or challenge?"
   - **Options:**
     - "Keep — include in handoff"
     - "Drop — false positive"
     - "Challenge — show me the full evidence excerpt and re-decide" (loops back with the full thread slice)

Process answers in sequence. Add KEPT items to the confirmed list; record DROPPED items in the filtered section.

### Step 3: Final user gate on confirmed list

Under `--no-handoff` the destination question is already answered: print the confirmed list and go to Step 6. Otherwise print the updated confirmed list (including newly-promoted UNCERTAIN items). Fire ONE final `AskUserQuestion`:

- **Question:** "Confirmed findings ready. How to hand off?"
- **Options:**
  - "Emit handoff and launch /improve-template now (Recommended)"
  - "Emit handoff only — I'll run /improve-template later"
  - "Drop specific findings before handoff" — loops back with multiSelect over the confirmed list
  - "Skip — no handoff; the printed report is enough"

### Step 4: Emit the handoff

If the user chose either of the first two options, write `.geniro/state/handoff/from-analyze-thread-<branch>.md` via `atomic_state_write`. Emit each kept finding as a machine-readable `open_questions[]` frontmatter entry per the T2 contract in `skills/_shared/state-tier-spec.md` §T2 (each entry needs `id` / `source` / `question` / `status`; `severity`, `recurrence`, `fix_kind`, and `suggested_action` are producer-specific extensions). The body `## Open questions` block is a human-readable mirror only — the frontmatter array is the source of truth a consumer parses.

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
    fix_kind: <DETERMINISTIC-CHECK|WIRE|NAV-POINTER|TOOL-CHANGE|REMOVE-RULE|PROSE>   # Step 3
    suggested_action: <one sentence in the shape of its fix_kind>
    status: unresolved
  # (one entry per kept finding: q2, q3, ...)
---

## Open questions
- [ ] q1 (<check_id> — <category>, seen in <M>/<T> threads): <one-line>. Target: <file>. Evidence: <thread_id>:<range>. Fix kind: <fix_kind>. Suggested action: <one sentence>.

(one bullet per kept finding, mirroring the frontmatter entry by `id`)
```

`suggested_action` takes the shape of its `fix_kind` (the Step 3 table's last column), so the consumer reads a concrete edit rather than a request for more instruction text; a `PROSE` or `REMOVE-RULE` one opens with its lever. `/improve-template` reads this handoff when invoked with the `process-handoff` argument and routes each parsed finding through its complexity gate.

### Step 5: If "launch now", invoke /improve-template

Print a one-line summary of the handoff and call `/improve-template` with `$ARGUMENTS` set to "process handoff from analyze-thread".

If the user chose "emit handoff only" or "skip": print the handoff path and the exact command (`/improve-template process-handoff`) for them to run later.

### Step 6: Cleanup

`rm -rf .geniro/state/analyze-thread/<slug>/` per the helper § Cleanup contract — the whole slug directory, and only this run's slug, never globbing sibling slugs.

The handoff file at `.geniro/state/handoff/from-analyze-thread-<branch>.md` survives until `/improve-template` consumes it (`skills/_shared/state-tier-spec.md` §T2).
