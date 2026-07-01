---
name: analyze-thread
description: "Use when post-hoc analyzing a saved Claude conversation thread file for pipeline errors — wrong subagent tier, missed parallel-spawn, schema-invalid tool args, premature completion, instruction drift, hallucinated tools. Auto-detects JSONL (Claude Code session log) or markdown (UI export / paste). 4-phase loop: Parse → Detect (mechanical + LLM-judge) → Filter → Present with per-finding AUQ. Emits a handoff to /improve-template for approved fixes. Skip for live debugging (/geniro:debug) or pending-diff code review (/geniro:review)."
context: main
model: inherit
allowed-tools: [Read, Write, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "<path to thread file>"
---

# /analyze-thread — Post-hoc Claude Thread Failure Analyzer

You are the orchestrator for analyzing a saved Claude conversation thread and surfacing the errors Claude made while running a multi-phase pipeline. You parse the thread, run mechanical and judged checks against a canonical 32-item taxonomy, filter for relevance, then present findings with per-item user gates. You NEVER mutate the analyzed source files (this skill is read-only on the project under analysis); approved fixes are emitted as a handoff for `/improve-template` to apply.

**Input:** a file path containing one Claude conversation thread.
**Output:** a markdown findings report + (on user approval) a handoff at `.geniro/state/handoff/from-analyze-thread-<branch>.md` that `/improve-template` consumes.

---

## Phases

1. **Parse** — auto-detect format (JSONL session log vs markdown export/paste), normalize into an events list, extract spawn-sites / tool-calls / approval gates, detect whether the thread is a Geniro skill run.
2. **Detect** — run mechanical checks (deterministic grep/jq over normalized events) then one LLM-judge pass over the thread excerpts with the canonical taxonomy seeded into the judge prompt.
3. **Filter** — orchestrator-inline relevance pass: drop REDUNDANT and FALSE-POSITIVE findings; keep TRUE-POSITIVE and UNCERTAIN.
4. **Present** — show grouped findings table; for every UNCERTAIN finding fire `AskUserQuestion` (fix / skip / challenge); for TRUE-POSITIVE findings default to "include in handoff" but let the user deselect; final AUQ chooses handoff destination.

The canonical taxonomy and per-check detection logic live in `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md`. SKILL.md keeps the phase narrative; the reference holds the 32-check spec.

---

## Subagent Model Tiering

Follow the canonical rule in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. This skill has exactly one subagent spawn — the Phase 2 LLM-judge — and it OMITs `model=` so it inherits orchestrator tier (judging the thread is reasoning-grade work).

The Phase 4 handoff target (`/improve-template`) is a sibling skill, not a subagent — no tier consideration applies here.

---

## State Persistence

After completing each phase, write a checkpoint to `.geniro/state/analyze-thread/state-<slug>.md` (compute `<slug>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` § Slug rules — base it on the analyzed-thread filename, not the project name):

```
Branch: <git branch --show-current OR detached-<short-sha>>
Worktree: <git rev-parse --show-toplevel>
Timestamp: <ISO-8601 UTC>
Phase [N] completed: [phase name]
Thread file: [path]
Thread format: [jsonl | markdown]
Geniro-run: [yes / no / partial]
Findings raw: [count from Phase 2]
Findings kept: [count from Phase 3]
```

Use `atomic_state_write` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — direct Edit/Write to state paths trips the `enforce-state-helper` hook.

Capital `Branch:` / `Worktree:` / `Timestamp:` are mandatory per the helper § Producer contract.

On skill start: compute `<slug>`, then `Glob(".geniro/state/analyze-thread/state-<slug>.md")`. If present, run the helper § Consumer contract (Case A/B/C/D mismatch handling). After "proceed", read the file and resume from the next incomplete phase.

---

## Loop Invariants

1. **Read-only on the analyzed source.** The thread file and any project files it references are never mutated by this skill. Mutating skills are `/improve-template` (template fixes) and `/geniro:implement` (consumer-code fixes) — both consume the handoff this skill emits.
2. **Mechanical before judged.** Phase 2 runs mechanical checks first because they are cheap, deterministic, and high-precision; the LLM-judge pass is then seeded with mechanical results so it does not re-discover them.
3. **One LLM-judge spawn per run.** A single judge sees the full thread excerpts plus the seeded mechanical findings — splitting into per-check spawns multiplies cost without improving signal (MAST showed one o1 pass at 94% accuracy / κ=0.77).
4. **Filter before user.** Phase 3 drops REDUNDANT and FALSE-POSITIVE findings BEFORE the Phase 4 presentation. The user sees only TRUE-POSITIVE + UNCERTAIN. Filtered items appear in a separate "Filtered" section for transparency.
5. **Per-finding AUQ for UNCERTAIN, batch AUQ for confidence-high.** Mechanical-detected with high confidence go into the default-approve bucket the user can deselect; LLM-judged with low/medium confidence each get their own AUQ.
6. **No silent auto-default.** Empty AUQ answers indicate an upstream tool bug and must be re-asked — never auto-default to "skip".

---

## Budgets & Quality Gates

| Budget | Value | Why |
|---|---|---|
| Thread file size | hard cap 5 MB; warn at 1 MB | JSONL session logs can grow large; >5 MB likely a merged multi-session log that should be split first |
| Mechanical-check wall-clock | 30 s ceiling | All Phase 2 mechanical checks are grep/jq one-liners; 30 s means the parse step produced a malformed events list — halt and report |
| LLM-judge token budget | seed prompt ≤ 8 K tokens, thread excerpts ≤ 60 K tokens | Excerpts are sliced to the top-3 most-suspicious sections per check, not the full thread, to fit the 200 K context with headroom |
| Findings raw cap | 60 per run | More than 60 raw findings on one thread = the parser misclassified the format; halt and ask user to re-check input |
| Findings kept cap | 25 surfaced to user | Past 25 the AUQ ladder becomes unworkable; if more survive the filter, sort by severity × confidence and truncate, noting the tail count |

---

## ACI per-phase tool surface

| Phase | Tools used | Notes |
|---|---|---|
| 1 Parse | Read, Bash (`head`, `file`, `jq`, `wc`) | Read for the thread file; Bash for format sniffing and JSONL parsing |
| 2 Detect | Bash (`jq`, `grep`, `awk`), Agent | Bash for mechanical checks; Agent for the single LLM-judge spawn |
| 3 Filter | (orchestrator inline) | No tools — orchestrator reads the Phase 2 output and tags each finding |
| 4 Present | AskUserQuestion, Write | AUQ for the per-finding gates and the final handoff AUQ; Write for the T2 handoff file (via atomic-write helper) |

Glob is permitted across phases for state-file lookup and helper resolution but is not the workhorse tool.

---

## PHASE 1: PARSE

**Purpose:** Turn the raw thread file into a normalized events list the detection phase can operate on.

### Step 1: Validate input

1. Resolve the path from `$ARGUMENTS`. If the user passed a bare filename, search the current working tree for it first, then `~/.claude/projects/` for JSONL session logs.
2. Check the file exists, is readable, and is under the 5 MB hard cap. If between 1 MB and 5 MB, warn the user before continuing — large threads slow down the judge pass.
3. If `$ARGUMENTS` is empty, fire an `AskUserQuestion` with options "Browse `~/.claude/projects/` for a recent session" / "Paste a path" / "Cancel".

### Step 2: Auto-detect format

Sniff the first 200 bytes with `head -c 200 <file>`. Detection rules:

- Begins with `{"type":"summary"` or `{"type":"user"` or `{"type":"assistant"` followed by a comma — **JSONL** (Claude Code session log).
- Begins with `# `, `## `, or `**User:**` / `**Assistant:**` block markers — **markdown**.
- Otherwise — fall back to markdown and warn the user that parsing degrades to heuristic regex.

Record the detected format in the Phase 1 checkpoint.

### Step 3: Normalize to events list

Produce an in-memory events list with this shape (one row per event):

| Field | Source — JSONL | Source — markdown |
|---|---|---|
| `idx` | line number in the .jsonl | block index in the .md |
| `role` | `.type` field (`user` / `assistant` / `tool_use` / `tool_result` / `summary`) | regex on block header (`**User:**` → user, etc.) |
| `content` | `.message.content` array | block body |
| `tool_name` | `.message.content[].name` when `tool_use` | regex on fenced ```` ```tool ```` blocks |
| `tool_input` | `.message.content[].input` JSON | regex-extracted JSON block (best-effort) |
| `timestamp` | `.timestamp` ISO field | not available — use idx as proxy |

JSONL parsing uses `jq -Rc 'fromjson?'` per the project memory rule — never bare `jq -c` (jq aborts on first parse error, silently wedging the pipeline).

### Step 4: Extract pipeline metadata

Scan the events list for Geniro-skill signals:

- Was a `/geniro:<skill>` slash command invoked? → `geniro-run: yes` + record which skill.
- Was an `Agent(subagent_type=...)` call made? → record spawn sites for Phase 2 checks A1-A7.
- Was an `AskUserQuestion` call made? → record approval gates for Phase 2 check D2.
- Was a TodoWrite call made? → record final state for Phase 2 check D3.
- Were `${CLAUDE_PLUGIN_ROOT}` / `_shared/` paths referenced? → confirms plugin-context.

Skip plugin-specific checks (the `[plugin]` rows in checks-reference.md) when `geniro-run: no` AND no plugin signals appear. Generic checks still apply.

### Step 5: Write Phase 1 checkpoint

Record: thread file path, format, byte count, events count, geniro-run flag, detected skill name (if any), spawn-site count, AUQ-gate count.

---

## PHASE 2: DETECT

**Purpose:** Run all 32 checks against the normalized events list and produce a raw findings list for filtering.

### Step 1: Run mechanical checks

For each `[M]` check in `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md` (see § Mechanical checks reference table), run the documented detection logic. Detection logic is one of three shapes:

- **jq predicate** over the JSONL events (e.g., A6 over-spawn detects identical `tool_input` across two `tool_use` events in the same assistant turn).
- **grep pattern** over the event content (e.g., G2 `--no-verify` scan).
- **windowed sequence match** over the events list (e.g., B3 infinite-loop detects same `tool_name` + same `tool_input` 3+ times in a sliding window of 5 events).

Each mechanical hit produces a draft finding: `{check_id, category, severity, confidence: high, evidence: [event_idx range], rationale}`. Mechanical confidence is always `high` — the rule either matched or it didn't.

### Step 2: Spawn the LLM-judge

ONE agent spawn. Pre-inline:
- The full canonical taxonomy from `checks-reference.md` (the 32-row table — short form).
- The mechanical findings from Step 1 (so the judge doesn't re-discover them and can use them as context).
- The top-3 most-suspicious thread excerpts per `[J]` check, sliced to keep total excerpts ≤ 60 K tokens. Suspicion ranking heuristic: events near mechanical-finding clusters, events near `AskUserQuestion` calls, events near phase-boundary narration ("Phase 3:", "shipping", "review").

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Judge thread for documented failure modes

You are reviewing a saved Claude conversation thread to detect failure modes that
were committed during execution. You do NOT fix anything — you only detect and
report. The mechanical pre-pass has already found some issues; build on those,
don't re-discover them.

### Canonical taxonomy (32 rows, [M] / [J] / scope tags)
{{taxonomy from checks-reference.md}}

### Mechanical findings already detected
{{mechanical findings from Step 1, as a table}}

### Thread excerpts (top-3 per judged check)
{{excerpts}}

### Your task

For each `[J]` check that mechanical did NOT already cover, scan the excerpts
and report findings as a JSON array, one object per finding:

{
  "check_id": "E2",
  "category": "Instruction-following & drift",
  "severity": "warning",
  "confidence": "medium",
  "evidence": [{"event_idx": 47, "excerpt": "first 200 chars"}],
  "rationale": "one-paragraph explanation"
}

Severity ladder: blocker | warning | nit.
Confidence ladder: high (unambiguous in trace) | medium (plausible but contestable) |
low (heuristic match, would need a second pair of eyes).

Also surface NOVEL findings — patterns of failure you spotted that don't fit any
of the 32 documented checks. Tag those with check_id = "NOVEL-N" and add a
`novel_pattern_name` field.

Do NOT propose fixes. Do NOT speculate on intent. Stick to what the trace shows.
Return ONLY the JSON array, no preamble.
""", description="Judge: thread failure detection")
```

### Step 3: Merge and write checkpoint

Combine mechanical findings + judge findings into a single raw list. Write checkpoint with `findings-raw: <count>`. If count exceeds the 60-cap, halt and report — that signals a parser misclassification.

---

## PHASE 3: FILTER (orchestrator-inline)

**Purpose:** Triage raw findings to TRUE-POSITIVE / UNCERTAIN / drop the rest. No subagent — this is reasoning over Phase 2's structured output.

For each raw finding, the orchestrator tags one of four:

| Tag | When | Action |
|---|---|---|
| **TRUE-POSITIVE** | High confidence + evidence event range cleanly matches the check spec + no contradicting context | Keep; default-include in Phase 4 handoff |
| **UNCERTAIN** | Medium/low confidence, OR evidence range ambiguous, OR judge tagged as "plausible but contestable" | Keep; per-item AUQ in Phase 4 |
| **REDUNDANT** | Duplicate of another finding (same root cause, different surface symptom), OR mechanical-and-judge both flagged the same event range | Drop; merge evidence into the surviving finding |
| **FALSE-POSITIVE** | The mechanical regex matched a benign case (e.g., A6 over-spawn flagged a TodoWrite that legitimately listed 5 parallel items), OR the judge flagged something that contradicts a documented exception in the skill body | Drop; log reason for Phase 4 transparency section |

For NOVEL findings: always UNCERTAIN unless the rationale ties to a documented anti-rationalization row in some skill body's table — then TRUE-POSITIVE.

Write Phase 3 checkpoint with `findings-kept: <count>` and `filtered: <count + reasons summary>`.

---

## PHASE 4: PRESENT (WAIT — user gates)

**Purpose:** Show the user grouped findings, gate UNCERTAIN ones individually, and emit the handoff.

### Step 1: Print the findings table

Group by category. Within each category, sort by severity (blocker → warning → nit) then confidence (high → low).

```
## Analysis: <thread file basename>

Format: <jsonl | markdown> · Events: <N> · Geniro-run: <yes/no/partial — skill: <name>>

### Confirmed findings (default-include)
| # | Category | Check | Severity | Confidence | Evidence | Suggested fix target |
|---|---|---|---|---|---|---|
| 1 | Subagent spawning | A1 missed parallel-spawn | warning | high | events 12-14 | skills/review/SKILL.md §Phase 2 |
| ...

### Uncertain findings (gated below)
| # | Category | Check | Severity | Confidence | Evidence | Rationale |
| 5 | Context | H1 first-vs-last contradiction | warning | medium | events 4 vs 198 | judge: "user asked X early, agent did not-X at the end without acknowledgement" |
| ...

### Filtered (transparency)
- check_id=A6 event-range=22-23 — FALSE-POSITIVE: TodoWrite legitimately listed 5 items, not duplicate spawns
- check_id=E4 event-range=87 — REDUNDANT: same root cause as finding #3
```

### Step 2: Gate uncertain findings

For EACH uncertain finding, fire `AskUserQuestion` (do NOT batch into one multiSelect — per-finding gating is what the user asked for):

- **Question:** "Finding #<N> (<check_id> — <one-line rationale>): keep, drop, or challenge?"
- **Options:**
  - "Keep — include in handoff"
  - "Drop — false positive"
  - "Challenge — show me the full evidence excerpt and re-decide" (loops back with the full thread slice)

Process answers in sequence. Add KEPT items to the confirmed list; record DROPPED items in the filtered section.

### Step 3: Final user gate on confirmed list

Print the updated confirmed list (including newly-promoted UNCERTAIN items). Fire ONE final `AskUserQuestion`:

- **Question:** "Confirmed findings ready. How to hand off?"
- **Options:**
  - "Emit handoff and launch /improve-template now (Recommended)"
  - "Emit handoff only — I'll run /improve-template later"
  - "Drop specific findings before handoff" — loops back with multiSelect over the confirmed list
  - "Skip — just save the markdown report"

### Step 4: Emit the handoff

If the user chose either of the first two options, write `.geniro/state/handoff/from-analyze-thread-<branch>.md` via `atomic_state_write`. Emit each kept finding as a machine-readable `open_questions[]` frontmatter entry per the T2 contract in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 (each entry needs `id` / `source` / `question` / `status`; `severity` + `suggested_action` are producer-specific extensions). The body `## Open questions` block is a human-readable mirror only — the frontmatter array is the source of truth a consumer parses.

```yaml
---
tier: T2
producer: analyze-thread
schema-version: 1
branch: <current branch>
timestamp: <ISO-8601 UTC>
consumer: improve-template
source_thread: <path>
findings_count: <N>
open_questions:
  - id: q1
    source: <check_id>                 # the check that surfaced the finding, e.g. A1
    question: "<one-line finding summary>"
    context: |                         # OPTIONAL — 2-6 line problem framing
      <category> — <what the trace shows>. Suggested target: <file>.
    related_findings: []               # finding has no /review F-id; leave empty
    severity: <blocker|warning|nit>    # producer-specific extension
    suggested_action: <one sentence — usually "rewrite instruction at <anchor>" or "add anti-rationalization row" or "extend Phase N gate">
    status: unresolved
  # (one entry per kept finding: q2, q3, ...)
---

## Open questions
- [ ] q1 (<check_id> — <category>): <one-line>. Target: <file>. Evidence: events <range>. Suggested action: <one sentence>.

(one bullet per kept finding, mirroring the frontmatter entry by `id`)
```

`/improve-template` reads this handoff when invoked with the `process-handoff` argument (Mode Detection → Complexity Gate handoff-ingestion path) and routes each parsed finding to its appropriate flow (Phase 1-fast / full pipeline depending on complexity).

### Step 5: If "launch now", invoke /improve-template

Print a one-line summary of the handoff and call `/improve-template` with `$ARGUMENTS` set to "process handoff from analyze-thread". `/improve-template` will pick up the handoff file from its standard read location.

If the user chose "emit handoff only" or "skip": print the handoff path and the exact command (`/improve-template process-handoff`) for them to run later.

### Step 6: Cleanup

Remove `.geniro/state/analyze-thread/state-<slug>.md` per the helper § Cleanup contract — delete only the current branch's slug, never globbing all state files.

The handoff file at `.geniro/state/handoff/from-analyze-thread-<branch>.md` is T2 and survives until `/improve-template` consumes it (per the standard handoff lifecycle in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`).

---

## Modifier handling

| Modifier in `$ARGUMENTS` | Effect |
|---|---|
| `--mechanical-only` | Skip Phase 2 Step 2 LLM-judge spawn; only mechanical checks run. Cheaper and faster but loses ~12 of the 32 checks. |
| `--no-handoff` | Phase 4 Step 4 skipped; only the markdown report is printed. Useful when the user wants to read findings without committing to fix anything. |
| `--strict` | Tighten Phase 3 filter: treat medium-confidence findings as TRUE-POSITIVE not UNCERTAIN (skips per-item AUQ, includes them by default). Use when running on a thread the user already trusts to be problematic. |
| `--lenient` | Loosen Phase 3 filter: treat high-confidence judged findings as UNCERTAIN (forces AUQ). Use on threads where many findings are likely benign. |
| `--format=jsonl` / `--format=markdown` | Skip Phase 1 Step 2 auto-detect and force the format. Use when sniffing misclassifies. |

---

## Task execution entry / state recovery

On invocation:

1. Compute `<slug>` from the analyzed thread filename (not the project name).
2. `Glob(".geniro/state/analyze-thread/state-<slug>.md")` — if found, run the helper's Case A/B/C/D mismatch UX before resuming.
3. If validating fails (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md`), fire the recovery AUQ from that helper.
4. On clean start: print "Analyzing <basename> — phase 1 of 4" and proceed.

On resume from a checkpoint: skip completed phases, print "Resuming at phase N of 4", continue.

---

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip Phase 1 Step 4 metadata extraction — the user said the thread is a Geniro run" | Phase 1 Step 4 detects WHICH skill ran, not WHETHER one ran. Plugin-specific checks reference skill-name-tagged anti-rationalization tables; without the skill identity, those checks misfire on every run. |
| "I'll batch all uncertain findings into one multiSelect AUQ to save user clicks" | Per-finding AUQ is what the user explicitly requested — they want to see evidence per finding and decide individually. MultiSelect collapses the evidence-review step, which is the point of UNCERTAIN. |
| "The thread is small — skip the parse step, just regex the markdown" | Phase 1's normalized events list is the substrate for Phase 2's mechanical checks. Skipping parse means every check turns into a bespoke regex and the false-positive rate explodes (memory: "mechanical pre-pass" is high-precision precisely because it operates on structured events). |
| "I'll spawn one judge per check instead of one judge for all judged checks" | MAST showed one o1 pass over the full thread + seeded taxonomy achieves 94% accuracy. Per-check spawns multiply token cost N times with no signal gain, and the judges can't cross-reference findings. |
| "The LLM-judge already produced findings — skip the mechanical pre-pass" | Mechanical checks are deterministic and catch what the judge will miss (schema validation, retry-loop window matching, identical-prompt over-spawn). The judge needs mechanical results as context to avoid re-discovering them. |
| "Findings_raw is 80, but they look real — present them all" | The 60-cap is a parser-sanity tripwire, not a UX preference. 80 raw findings on one thread means either the events list is malformed (Phase 1 bug) or every check is firing (taxonomy bug). Halt and have the user re-verify input. |
| "The user said 'analyze this thread', they obviously want fixes too — I'll edit the source files directly" | Read-only is invariant #1. This skill detects; `/improve-template` fixes. Cross-skill responsibility separation is documented in CLAUDE.md `## Available Skills` — collapsing it makes the analyzer a refactorer, breaking the user's mental model. |
| "I already know what's in `checks-reference.md` from training data — don't bother reading it" | The reference file is the source of truth; it can be edited by the user between runs. Loading it at Phase 2 entry ensures the detection logic matches the current taxonomy, not a stale snapshot. |
| "Empty AUQ answer = user wants to skip" | Per `feedback_canonical_rules.md` and the universal AUQ rule: empty answers indicate an upstream tool bug. Re-ask. Never auto-default. |
| "I'll inline checks-reference.md into the judge prompt because it's only 250 lines" | Inlining doubles the prompt for every run. Reference the file by path; the judge reads it once at spawn time. The 60 K-token excerpt budget assumes the taxonomy is loaded by reference, not inlined. |

---

## Definition of Done

- [ ] Phase 1: thread file located, format detected, events list normalized, geniro-run flag set, metadata extracted
- [ ] Phase 1 checkpoint written via `atomic_state_write`
- [ ] Phase 2 mechanical checks all run (per `checks-reference.md` §§1-3 — Mechanical checks A/B/C-class)
- [ ] Phase 2 LLM-judge spawn: single Agent call, OMITted `model=`, taxonomy + mechanical-results + excerpts pre-inlined
- [ ] Phase 2 checkpoint written; findings_raw count under the 60-cap
- [ ] Phase 3 orchestrator-inline filter applied; each raw finding tagged TRUE-POSITIVE / UNCERTAIN / REDUNDANT / FALSE-POSITIVE
- [ ] Phase 3 checkpoint written; findings_kept count under the 25-cap (or truncated with tail note)
- [ ] Phase 4 Step 1: findings table printed with Confirmed / Uncertain / Filtered sections
- [ ] Phase 4 Step 2: per-finding AUQ fired for each UNCERTAIN; sequential, not batched
- [ ] Phase 4 Step 3: final handoff-routing AUQ fired
- [ ] Phase 4 Step 4: handoff file written via `atomic_state_write` if user chose to emit
- [ ] Phase 4 Step 5: `/improve-template` invoked if user chose "launch now"
- [ ] Phase 4 Step 6: state-<slug>.md cleaned up per helper § Cleanup contract
- [ ] No mutations to the analyzed thread file or any project file outside `.geniro/state/` and `.geniro/state/handoff/`

---

## REFERENCE

- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/analyze-thread/checks-reference.md` — canonical 32-check taxonomy + per-check detection logic
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` — slug rules + Case A/B/C/D resume UX
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` — state-file write helper (mandatory)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/validate-state-file.md` — pre-resume validator + recovery AUQ
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` — T1 / T1.5 / T2 lifecycle (handoff lives at T2)
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — bare/prefixed/general-purpose degradation ladder
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` — `model=` vs OMIT rules
- `${CLAUDE_PLUGIN_ROOT}/.claude/skills/improve-template/SKILL.md` — handoff consumer
