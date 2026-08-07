---
name: analyze-thread
description: "Use when post-hoc analyzing saved Claude conversation threads for pipeline errors — wrong subagent tier, missed parallel-spawn, schema-invalid tool args, premature completion, instruction drift, hallucinated tools. Also audits coverage: whether every custom-instruction file and block (rules, constraints, additional steps, data sources, verification surface, memory backend) loaded and took effect, whether every declared phase, phase-body read, and step ran, whether custom reviewers were wired in, and whether an approval question was skipped or asked outside the tool. Takes one or more thread paths, or with no argument analyzes the last few work-bearing threads across every project; a multi-thread run merges findings with a recurrence count. Auto-detects JSONL session logs or markdown exports. 4-phase loop: Parse → Detect (mechanical + LLM-judge) → Filter → Present with per-finding AUQ. Emits a handoff to /improve-template. Skip for live debugging (/geniro:debug) or diff review (/geniro:review)."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[thread path(s) | thread count | empty = last 3 threads]"
---

# /analyze-thread — post-hoc Claude thread failure analyzer

## Contents

- Phases
- Subagent model tiering
- State persistence
- Loop invariants
- Anti-rationalization
- Budgets & quality gates
- ACI per-phase tool surface
- Definition of done
- Phase 1 (parse) · Phase 2 (detect) · Phase 3 (filter) · Phase 4 (present)
- Modifier handling
- Task execution entry / state recovery
- REFERENCE

---

You are the orchestrator for analyzing a saved Claude conversation thread and surfacing the errors Claude made while running a multi-phase pipeline. You parse the thread, run mechanical and judged checks against the canonical taxonomy, filter for relevance, then present findings with per-item user gates. You never mutate the analyzed source files (this skill is read-only on the project under analysis); approved fixes are emitted as a handoff for `/improve-template` to apply.

**Input:** one or more thread file paths, a thread count, or nothing — an empty argument analyzes the last 3 work-bearing threads across every project (§Phase 1 Step 1).
**Output:** a findings report printed to chat + (on user approval) a handoff at `.geniro/state/handoff/from-analyze-thread-<branch>.md` that `/improve-template` consumes.

**Phase bodies.** This file is the spine — role, invariants, gates, phase map. **Read the phase's Steps on entry to that phase**, from `.claude/skills/analyze-thread/`: `phase-1-2-parse-detect.md` (Phases 1-2) · `phase-3-4-filter-present.md` (Phases 3-4). That Read is the phase's physically-first action and carries a one-line echo, per `skills/_shared/phase-entry-read.md` — the phase files hold this skill's gates (including the Phase 4 user gates and the handoff emit) and their helper call sites, so work started before the Read runs outside them.

**After a compaction:** re-Read the phase file for whatever phase is running before continuing it — only the front-loaded prefix re-attaches, so a mid-phase summary can drop the Steps while leaving this spine intact. If which phase was running is also gone, re-invoke `/analyze-thread` with the same argument — the §State persistence checkpoint makes that a resume, not a re-run.

---

## Phases

1. **Parse** — resolve the thread set (one path, or the last N threads machine-wide), then per thread: auto-detect format (JSONL session log vs markdown export/paste), normalize into an events list, extract spawn-sites / tool-calls / approval gates, detect whether the thread is a Geniro skill run, and build the expectation set — what that run declared it would load, enter, and ask.
2. **Detect** — per thread, run mechanical checks (deterministic grep/jq over normalized events, including the coverage checks that compare the expectation set against what the trace shows) then one LLM-judge pass over that thread's excerpts with the canonical taxonomy and that thread's expectation set seeded into the judge prompt.
3. **Filter** — orchestrator-inline relevance pass: merge the same defect across threads into one finding carrying its recurrence count, then drop REDUNDANT and FALSE-POSITIVE; keep TRUE-POSITIVE and UNCERTAIN.
4. **Present** — show grouped findings table; for every UNCERTAIN finding fire `AskUserQuestion` (fix / skip / challenge); for TRUE-POSITIVE findings default to "include in handoff" but let the user deselect; final AUQ chooses handoff destination.

A batch run changes what each phase iterates over, never the phase contract: the same checks, filter tags, and gates apply per thread, and only Phase 3's merge step is batch-specific.

The canonical taxonomy and per-check detection logic live in `.claude/skills/analyze-thread/checks-reference.md`. SKILL.md keeps the phase narrative; the reference holds the per-check spec.

---

## Subagent model tiering

Follow the canonical rule in `skills/_shared/model-tiering.md`. This skill has exactly one subagent spawn — the Phase 2 LLM-judge — and it OMITs `model=` so it inherits orchestrator tier (judging the thread is reasoning-grade work).

---

## State persistence

After completing each phase, write a checkpoint to `.geniro/state/analyze-thread/<slug>/state.md` (compute `<slug>` per `skills/_shared/within-skill-state-handoff.md` § Slug rules — base it on the analyzed thread, never the project name; §Task execution entry gives the single- and batch-mode forms). Use `atomic_state_write` per `skills/_shared/atomic-state-write.md` — direct Edit/Write to state paths trips the `enforce-state-helper` hook.

The full T1.5 frontmatter opens on line 1 per the helper § Producer contract. Plain-text `Branch:` / `Worktree:` / `Timestamp:` header lines push the `---` fence off line 1 and fail `validate_state_file` with exit 2 — the validator that §Task execution entry runs before every resume, so a checkpoint written that way is one this skill cannot read back.

```yaml
---
tier: T1.5
producer: analyze-thread
schema-version: 1
branch: <git branch --show-current OR detached-<short-sha>>
worktree: <git rev-parse --show-toplevel>
timestamp: <ISO-8601 UTC>
phase: <last completed phase>
status: in-progress
non-resumable-actions: []
---
```

Body: `Mode: [single | batch]`; one line per thread (`<thread_id> · <path> · <format> · <geniro-run> · <findings raw>`); one line per skipped thread with its reason; the Phase 2 raw findings count and the Phase 3 post-merge kept count.

On skill start: compute `<slug>`, then `Glob(".geniro/state/analyze-thread/<slug>/state.md")`. If present, run the helper § Consumer contract (Case A/B/C/D mismatch handling). After "proceed", read the file and resume from the next incomplete phase.

---

## Loop invariants

1. **Read-only on the analyzed source.** The thread file and any project files it references are never mutated by this skill. Mutating skills are `/improve-template` (template fixes) and `/geniro:implement` (consumer-code fixes) — both consume the handoff this skill emits.
2. **Mechanical before judged.** Phase 2 runs mechanical checks first because they are cheap, deterministic, and high-precision; the LLM-judge pass is then seeded with mechanical results so it does not re-discover them.
3. **One LLM-judge spawn per thread, all spawned in ONE assistant response, each carrying the taxonomy inline.** Splitting into per-check spawns multiplies cost without improving signal, and serializing judge calls across turns multiplies wall-clock by the thread count.
4. **A defect in N threads is one finding, not N.** Phase 3 merges the same check firing on the same root cause across threads into a single finding whose recurrence count is evidence of severity, not a duplicate to discard. Recurrence is the batch's whole point: one thread cannot distinguish an instruction the model happened to skip once from an instruction it skips systematically.
5. **Never analyze this session's own log.** Its trace has no conclusion to judge, and analyzing the run that is doing the analyzing yields findings about the analysis in progress. Identify it by session id, not by timestamp (§Phase 1 Step 1).
6. **Filter before user.** Phase 3 drops REDUNDANT and FALSE-POSITIVE findings BEFORE the Phase 4 presentation. The user sees only TRUE-POSITIVE + UNCERTAIN. Filtered items appear in a separate "Filtered" section for transparency.
7. **Per-finding AUQ for UNCERTAIN, batch AUQ for confidence-high.** Mechanical-detected with high confidence go into the default-approve bucket the user can deselect; LLM-judged with low/medium confidence each get their own AUQ.
8. **No silent auto-default.** Empty AUQ answers indicate an upstream tool bug and must be re-asked — never auto-default to "skip".
9. **The declared side of a coverage check comes from the analyzed trace, never from this checkout.** The I- and K-class checks ask what is *missing* — a skipped instruction load, an unentered phase, a gate that never fired — so they need to know what the run promised. That promise is recorded in the thread itself: the injected skill body, and the tool_results of the instruction files the run read. Reading the analyzing machine's own `skills/` or `.geniro/instructions/` instead compares one project's run against another project's rules, which is the normal case in a batch and produces findings that are pure fiction. `checks-reference.md` §8 has the field list and the three documented degradations.
10. **No declaration, no finding.** A coverage check with an empty declared side reports nothing. A project that declares no data sources cannot fail to consult one; a thread with no Geniro run has no phases to skip. Absence of an expectation is the check's clean path, not a gap to fill by inference — inventing the declared side turns a silent run into a wall of fictional "missing" rows.

**Turn-completion check** (deliberately un-numbered, per `skills/_shared/loop-invariants.md` §Turn-completion check): before stopping, re-read the last emitted paragraph — a stated intent to fire an AUQ, spawn the judge, or emit the handoff is not the same as having done it. Phase 4's per-finding gates and its handoff emit are exactly the seam this guards.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip Phase 1 Step 4 metadata extraction — the user said the thread is a Geniro run" | Phase 1 Step 4 detects WHICH skill ran, not WHETHER one ran. Plugin-specific checks reference skill-name-tagged anti-rationalization tables; without the skill identity, those checks misfire on every run. |
| "I'll batch all uncertain findings into one multiSelect AUQ to save user clicks" | Per-finding AUQ is what the user explicitly requested — they want to see evidence per finding and decide individually. MultiSelect collapses the evidence-review step, which is the point of UNCERTAIN. |
| "The thread is small — skip the parse step, just regex the markdown" | Phase 2's checks query the thread against the Step 3 field schema, which is what makes the mechanical pre-pass high-precision. Ad-hoc regex that ignores the schema reads different fields per check, and the false-positive rate explodes. |
| "I'll spawn one judge per check instead of one judge for all judged checks" | Invariant #3 is one judge per thread. Per-check spawns multiply token cost with no signal gain, and the judges can't cross-reference each other's findings. |
| "The LLM-judge already produced findings — skip the mechanical pre-pass" | Mechanical checks are deterministic and catch what the judge will miss (schema validation, retry-loop window matching, identical-prompt over-spawn). The judge needs mechanical results as context to avoid re-discovering them. |
| "Findings_raw is 80, but they look real — present them all" | The 60-cap is a parser-sanity tripwire, not a UX preference. 80 raw findings on one thread means either Phase 1 Step 2 misdetected the input format, so every check is reading the wrong fields, or every check is firing (taxonomy bug). Halt and have the user re-verify input. |
| "The user said 'analyze this thread', they obviously want fixes too — I'll edit the source files directly" | Read-only is invariant #1. This skill detects; `/improve-template` fixes. Cross-skill responsibility separation is documented in CLAUDE.md `## Skill routing` — collapsing it makes the analyzer a refactorer, breaking the user's mental model. |
| "I already know what's in `checks-reference.md` from training data — don't bother reading it" | The reference file is the source of truth; it can be edited by the user between runs. Loading it at Phase 2 entry ensures the detection logic matches the current taxonomy, not a stale snapshot. |
| "No argument given — I'll ask the user which thread they meant" | Every input shape resolves without a question (Phase 1 Step 1): empty means the last 3 work-bearing threads. Asking re-imposes the browse-and-paste step the batch default exists to remove, and the user who typed no argument has already told you what they want. |
| "The newest log is the freshest data — analyze it first" | The newest log is this session's own, which invariant #5 excludes: every finding it yields describes the analysis in progress rather than past work. |
| "I'll read this repo's `skills/` and `.geniro/instructions/` to see what the run should have loaded" | Invariant #9. In a batch the threads come from every project on the machine, so this repo's rules describe a different project than the thread does. Even on a single-project run the files have moved on since the thread executed, so the diff reports your own later edits as failures of the run. The declarations are in the trace. |
| "The trace shows no instruction load, so every declared file is a missing-load finding" | Check first whether the trace covers the turns where the load would have been. A compacted or mid-run thread cannot evidence a Step 0 that happened before its first recorded turn — that is `checks-reference.md` §8 degradation 1: keep the check, cap confidence at medium, and say the trace is partial. |
| "Every phase in the skill body owes a finding when I can't see it run" | A conditional phase whose trigger never fired, and a run the user stopped early, both leave phases unentered without anything being skipped. K1 fires only on a phase stepped over while its successors ran. |
| "That's 4 unloaded files and 6 unrun steps — 10 findings" | Coverage findings roll up per declaration site: one finding for the load site listing its four files, one for the phase listing its six steps. Per-item findings inflate a single systematic defect into a wall that trips the 60-finding parser tripwire and buries every other check under it. |

---

## Budgets & quality gates

| Budget | Value | Why |
|---|---|---|
| Threads per batch | default 3; hard cap 5 | Each thread costs its own judge spawn and its own mechanical pass. Past 5 the merged report outgrows the per-finding AUQ ladder and the wall-clock stops being worth the added recurrence signal. A count above the cap is clamped, with the clamp stated to the user |
| Thread file size | hard cap 5 MB; warn at 1 MB | JSONL session logs can grow large; >5 MB likely a merged multi-session log that should be split first. In a batch, an oversize thread is skipped and named in the report rather than aborting the run |
| LLM-judge token budget | seed prompt ≤ 8 K tokens, thread excerpts ≤ 60 K tokens | The seed is the inlined short-form taxonomy, that thread's expectation set, and its mechanical findings (invariant #3). Per thread, and each judge has its own context, so a batch does not share this budget. Where the expectation set crowds the seed, summarise its blocks to their headings and boundaries rather than dropping the set — a judge holding the taxonomy but not the declared side runs every coverage check blind. Excerpts are sliced to the top-3 most-suspicious sections per check, not the full thread, to fit the 200 K context with headroom |
| Findings raw cap | 60 per thread | More than 60 raw findings on one thread = the parser misclassified the format; halt and ask user to re-check input. Applies per thread, not to the batch total |
| Findings kept cap | 25 surfaced to user | Counted AFTER the Phase 3 cross-thread merge, so a defect recurring in 3 threads consumes one slot. Past 25 the AUQ ladder becomes unworkable; if more survive, sort by recurrence × severity × confidence and truncate, noting the tail count |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Parse | Read, Bash (`scan.py`, `file`, `jq`, `wc`) | Bash runs the thread-discovery scan in batch mode, then format sniffing and JSONL parsing; Read for the thread file. Step 4b's expectation set is projected out of the same thread file — no Read of this repo's skills or instruction files, per invariant #9 |
| 2 Detect | Bash (`jq`, `grep`, `awk`), Agent | Bash for mechanical checks; Agent for the per-thread LLM-judge spawns, issued together in one response |
| 3 Filter | (orchestrator inline) | No tools — orchestrator reads the Phase 2 output, merges across threads, and tags each finding |
| 4 Present | AskUserQuestion, Bash | AUQ for the per-finding gates and the final handoff AUQ; Bash runs `atomic_state_write` for the handoff file — a direct `Write` to a `.geniro/state/` path is hard-blocked by the state-helper hook |

Glob is permitted across phases for state-file lookup and helper resolution but is not the workhorse tool.

---

## Definition of done

These are the load-bearing exit gates — the checks that, if skipped, ship a wrong result. Per-phase mechanics live in their phase sections; this list is the final correctness check, not a re-listing of every step.

- [ ] The thread set resolved from `$ARGUMENTS` with no question asked, excluded this session's own log by id, and named every clamped or skipped thread to the user
- [ ] The expectation set was built from each thread's own trace, never from this checkout, and any degradation was stated and carried into the confidence of every finding that rests on it
- [ ] Every coverage check ran against a declared side or did not run at all — no "missing" row rests on an expectation the trace never established
- [ ] Phase 2 LLM-judge ran per invariant #3 with that thread's expectation set in its seed, and a judge that returned nothing usable is reported as a mechanical-only thread, never as a full judged pass
- [ ] Phase 3 cross-thread merge ran before triage: recurring defects collapsed to one finding with `threads: [...]`, recurrence raising confidence but never severity
- [ ] The coverage scoreboard rendered for every thread whose expectation set was non-empty, each gap citing the finding that carries its evidence
- [ ] Every UNCERTAIN finding got its own AUQ, fired sequentially rather than batched into one multiSelect
- [ ] Handoff written via `atomic_state_write` when the user chose to emit, with one `open_questions[]` entry per kept finding
- [ ] State file cleaned up per the helper § Cleanup contract
- [ ] No mutations to the analyzed thread file or any project file outside `.geniro/state/`

---

## PHASE 1: PARSE

`Steps: phase-1-2-parse-detect.md §Phase 1` (Steps 1-5). Resolve the thread set from `$ARGUMENTS` with no question asked, auto-detect format, normalize into an events list, extract spawn-sites / tool-calls / approval gates, and build the expectation set — what the run declared it would load, enter, and ask. Exit when the Phase 1 checkpoint records, per thread: format, event count, geniro-run flag, and the expectation set with its degradation level.

## PHASE 2: DETECT

`Steps: phase-1-2-parse-detect.md §Phase 2` (Steps 1-3). Run mechanical checks first, then spawn one LLM-judge per thread — all in one assistant response — seeded with the taxonomy, the expectation set, and the mechanical findings. Exit when every raw finding carries its `thread_id`, and a judge spawn that returned nothing usable is noted as a mechanical-only thread rather than presented as fully judged.

## PHASE 3: FILTER (orchestrator-inline)

`Steps: phase-3-4-filter-present.md §Phase 3` (Steps 1-2). Merge the batch's recurring findings into one row each, then tag every finding TRUE-POSITIVE / UNCERTAIN / REDUNDANT / FALSE-POSITIVE. No subagent. Exit when every finding is tagged and the checkpoint records the kept and filtered counts.

## PHASE 4: PRESENT (WAIT — user gates)

`Steps: phase-3-4-filter-present.md §Phase 4` (Steps 1-6). Print the grouped findings + coverage table, gate every UNCERTAIN finding one at a time (message-first render, then a lean AUQ), fire the final handoff-destination gate, emit the handoff, then clean up. Exit when every UNCERTAIN finding has an answered gate, the handoff (if chosen) is written via `atomic_state_write`, and the slug's state directory is removed.

---

## Modifier handling

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `--mechanical-only` | Skip Phase 2 Step 2 LLM-judge spawn; only mechanical checks run. Cheaper and faster but loses every judged check — including the judged coverage checks (`checks-reference.md` §4) that read whether a loaded rule actually changed anything. What survives is whether files loaded and phases ran, not whether their content took effect; say so when reporting coverage under this modifier. Pairs well with a large batch, where the judges dominate cost. |
| `--no-handoff` | Phase 4 Steps 3-4 skipped; the findings report is printed, cleanup runs, and no handoff file is written. Useful when the user wants to read findings without committing to fix anything. |
| `--strict` | Tighten Phase 3 filter: treat medium-confidence findings as TRUE-POSITIVE not UNCERTAIN (skips per-item AUQ, includes them by default). Use when running on a thread the user already trusts to be problematic. |
| `--lenient` | Loosen Phase 3 filter: treat high-confidence judged findings as UNCERTAIN (forces AUQ). Use on threads where many findings are likely benign. |
| `--format=jsonl` / `--format=markdown` | Skip Phase 1 Step 2 auto-detect and force the format. Use when sniffing misclassifies. |

---

## Task execution entry / state recovery

On invocation:

1. Resolve the thread set per Phase 1 Step 1, then compute `<slug>`: the thread's short id in single mode, `batch-<newest thread's short id>` in batch mode (never the project name, and never a bare timestamp — a slug must be stable enough for a resume to find it).
2. `Glob(".geniro/state/analyze-thread/<slug>/state.md")` — if found, run the helper's Case A/B/C/D mismatch UX before resuming.
3. If validating fails (per `skills/_shared/validate-state-file.md`), fire the recovery AUQ from that helper.
4. On clean start: print "Analyzing <basename> — phase 1 of 4", or "Analyzing <N> threads — phase 1 of 4", and proceed.

On resume from a checkpoint: skip completed phases, print "Resuming at phase N of 4", continue.

---

## REFERENCE

- `.claude/skills/analyze-thread/phase-1-2-parse-detect.md` — Phase 1 + Phase 2 Steps (Read on entry to Phase 1)
- `.claude/skills/analyze-thread/phase-3-4-filter-present.md` — Phase 3 + Phase 4 Steps, incl. the per-finding gate and the handoff emit (Read on entry to Phase 3)
- `.claude/skills/analyze-thread/checks-reference.md` — canonical check taxonomy + per-check detection logic; §8 defines the expectation set the coverage checks compare against
- `skills/_shared/load-custom-instructions.md` — the load / echo / refresh contract the I-class checks measure a run against
- `skills/_shared/phase-entry-read.md` — the phase-body Read and echo contract behind K2
- `skills/_shared/gate-rendering.md` — gate render-then-ask shape and the lean-question conventions behind K3-K6, K8
- `skills/_shared/skip-visibility.md` — the subagent load report and the assessed sentinel, the two proofs an echo cannot carry
- `.claude/skills/find-threads/scan.py` — the thread-discovery engine batch mode calls. Its module docstring documents every output column, the config-dir roots it scans, and the work-bearing classification. Add a new config dir by exporting `FIND_THREADS_EXTRA_ROOTS` (colon-separated), which overrides its `EXTRA_ROOTS` default
- `skills/_shared/within-skill-state-handoff.md` — slug rules + Case A/B/C/D resume UX
- `skills/_shared/atomic-state-write.md` — state-file write helper (mandatory)
- `skills/_shared/validate-state-file.md` — pre-resume validator + recovery AUQ
- `skills/_shared/state-tier-spec.md` — T1 / T1.5 / T2 lifecycle (handoff lives at T2)
- `skills/_shared/spawn-agent.md` — bare/prefixed/general-purpose degradation ladder
- `skills/_shared/model-tiering.md` — `model=` vs OMIT rules
- `skills/_shared/per-finding-question.md` — message-first per-finding gate protocol (the shape Phase 4 Step 2 fires)
- `.claude/skills/improve-template/SKILL.md` — handoff consumer
