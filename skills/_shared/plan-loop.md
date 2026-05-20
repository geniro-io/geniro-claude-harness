# Brainstorming Loop

Canonical 8-phase ideation pattern. Consumers: `skills/brainstorm/SKILL.md`, `skills/features/SKILL.md` `add` subcommand. Each consumer wraps the loop with skill-specific Phase 9 hand-off (Geniro has fan-out menu vs superpowers' linear hand-off; the divergence is intentional — this shared rule does NOT include the hand-off).

This file is the single source of truth. Skills cite this file; do NOT inline-paste the loop logic.

## HARD-GATE

> Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY task regardless of perceived simplicity.

The gate is binding for Phases 1–8 of this loop. The consumer's Phase 9 hand-off is the only authorized release point.

## Phase 1 — Explore project context

Spawn parallel `Agent(subagent_type="Explore", ...)` calls per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (runtime-degradation rule) and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` (per-agent input scoping). Each agent receives a focused slice of the topic (e.g. one for existing similar features, one for data model, one for UI patterns) — do NOT hand all sub-questions to one agent.

**Required output:** at least 2 file paths cited with line numbers, OR an explicit "no related code found in this codebase" written verbatim. A vague "I looked around and didn't see anything" does NOT satisfy the requirement — re-run the explore step with sharper sub-queries.

The consolidated explore output is the input substrate for Phase 2 (UI signal detection) and Phase 3 (clarifying questions).

## Phase 2 — Visual companion (CONDITIONAL)

**Trigger heuristic.** Fire this phase if EITHER of the following holds:

- Phase 1 explore-agent surfaced any path matching the UI-file globs defined in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` § When to run.
- The user's topic string contains a UI noun: `page`, `screen`, `modal`, `form`, `dashboard`, `button`, `view`, `panel`, `widget` (case-insensitive, word-boundary match).

**Skip silently when no UI signal.** Do NOT fire the AUQ when the topic is clearly backend-only (e.g. "rate limiter", "cron job", "DB migration"). Silent skip is correct here; firing the AUQ for a backend-only topic is an anti-pattern (cognitive cost, no upside).

**On trigger,** fire `AskUserQuestion` per the gate pattern in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`:

- `header`: `"UI sketch"`.
- `question`: `"Topic looks UI-shaped — want a textual UI sketch alongside the dialogue?"`.
- `options[]`:
  - `label`: `"Yes, sketch via ui-preview-gate"` — `description`: `"Run the textual UI preview procedure before continuing dialogue. Captures visual intent in user-approved language so Phase 5 design sections inherit it."`.
  - `label`: `"No, prose-only design"` — `description`: `"Continue Phase 3 dialogue without a visual companion. Choose this when the topic is mostly logic/data and visuals are secondary."`.

**On Yes** → cite and run `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` end-to-end. The approved description becomes a Phase 5 section input.

**On No** → continue to Phase 3.

## Phase 3 — Clarifying questions

`AskUserQuestion`, **ONE at a time, max 5 total questions** across the phase. Per-question shape follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` AUQ conventions (single-select unless explicitly multi-select).

Categories, in order — each question probes a single dimension:

1. **Purpose** — what user/system problem does this solve?
2. **Constraints** — what's fixed (existing API, performance budget, deadline)?
3. **Success criteria** — how do we know it's done?
4. **Scope boundary** — what's in / out for this iteration?
5. **Rollout** — flag-gated, gradual, or full-cut?

Skip a category when Phase 1 explore output already answers it definitively (cite the file path that resolved the question in your internal note). NEVER batch two categories into one question — that breaks the "one dimension per question" rule and produces noisy options.

If the user's answer to question N invalidates a later question (e.g. "Purpose=internal-tool-only" makes the "Rollout" question moot), skip the moot question and explain in one line why it's being skipped.

## Phase 4 — Propose 2–3 approaches with tradeoffs

`AskUserQuestion` picker. Recommended option **first**. Each option's `description` body contains:

- **Rough fit** — one phrase tying the approach to the user's Phase 3 answers.
- **Key tradeoff** — one sentence naming the dominant cost (e.g. "buys speed at the cost of tighter coupling to the auth module").

Two options is acceptable when the design space is narrow. Three is the practical max — more than 3 indicates the Phase 3 dialogue did not narrow scope enough; loop back to Phase 3 with a tighter scope-boundary question.

## Phase 5 — Present design + section-by-section approval

Each section is its own AUQ — **one section, one approval**. Sections scale to topic complexity:

- **Trivial** (config tweak, copy edit, single-file refactor): 1–2 sections (e.g. "Change" + "Risks").
- **Small** (single endpoint, single component): 2–3 sections.
- **Medium / Big** (cross-module, new data, new UI flow): 4–6 sections covering architecture, components, data flow, error handling, testing, rollout — pick the subset relevant to the topic.

**FORBIDDEN: presenting all sections at once with one AUQ at the end.** This is an anti-pattern (cognitive load on the user; any section needing changes forces a batched edit across all sections). Section-by-section approval enables surgical revisions and surfaces disagreement at the section that triggered it.

After every section AUQ:

- **Approve** → continue to next section.
- **Revise** → capture the user's edit, re-render the section, re-AUQ. Cap 3 revision rounds per section (mirrors `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` Step 3 cap). On round 4, surface "this section isn't converging — re-open Phase 3 / Phase 4?" via AUQ.
- **Skip section** → only when the user explicitly says the section is N/A. Record "skipped per user — <reason>" in the design doc.

## Phase 6 — Write design doc

Path: `.geniro/planning/<branch>/<YYYY-MM-DD>-<topic-slug>-design.md`. Resolve `<branch>` from the current git branch (slugify per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` if available). `<topic-slug>` is lowercase-hyphenated, max 40 chars, derived from the topic string.

The doc MUST contain **ALL THREE detection markers** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` (defense in depth):

1. **YAML frontmatter at top** (line 1):

   ```
   ---
   geniro_kind: design-doc
   ---
   ```

2. **HTML comment after the H1** (within the first 20 lines):

   ```
   # <Topic Title>

   <!-- geniro:design-doc -->
   ```

3. **Path placement** under `.geniro/planning/**/*.md` — already enforced by the path rule above.

Write all three markers unconditionally — do not "optimize" by writing only one. The defense-in-depth rationale is in `design-doc-detect.md`.

After write, commit the file with message `design: <topic>`. Do not amend prior commits; create a fresh commit.

## Phase 7 — Spec self-review

The orchestrator (this skill, NOT a spawned agent) re-reads the committed design and audits for:

- **Placeholders** — `TODO`, `XXX`, `<...>`, `TBD`, `???`.
- **Contradictions** — section A says X, section B says not-X. Read each section against every other section.
- **Ambiguous wording** — "fast", "secure", "easy to use" without measurable criteria.
- **Scope creep** — content beyond Phase 3 success criteria + Phase 5 approved sections.

**Output:** pass/fail + enumerated list of issues with file:line references.

**On fail:** revise the affected sections, re-commit (new commit, not amend), and re-run Phase 7. **Cap 2 self-review rounds.** After round 2, surface remaining issues to the user as part of Phase 8 — do not silently ship them.

The self-review and Phase 8 user re-review catch DIFFERENT defect classes. The orchestrator catches mechanical defects (placeholders, contradictions, scope creep) the user might miss after long dialogue. The user catches intent defects (wrong abstraction, missing constraint they assumed was obvious) the orchestrator can't see. Both required.

## Phase 8 — Post-spec user re-review

`AskUserQuestion`:

- `header`: `"Spec review"`.
- `question`: `"Spec committed to <path>. Review it before hand-off?"` (substitute the actual path).
- `options[]`:
  - `label`: `"Approve & continue"` — `description`: `"Spec matches intent. Release the HARD-GATE and proceed to consumer's Phase 9 hand-off."`.
  - `label`: `"Request changes — I'll list them"` — `description`: `"Loop back through Phase 5 with my enumerated changes. Cap 3 rounds total per ui-preview-gate revision-cap idiom."`.
  - `label`: `"Re-open Phase 5 sections"` — `description`: `"Return to Phase 5 entry point — I want to re-walk one or more sections."`.

**On "Approve"** → release HARD-GATE; return control to the consumer's Phase 9.

**On "Request changes"** → fire a follow-up AUQ "Which changes? (free text)" via the `Other` option, capture the enumerated list, loop back to Phase 5 entry. **Cap 3 rounds total** for this Phase 8 → Phase 5 → Phase 6 → Phase 7 → Phase 8 cycle. After round 3, fire AUQ "Spec isn't converging — proceed with current version / cancel and revisit later" — do NOT loop a 4th time.

**On "Re-open"** → return to Phase 5 entry point. Re-running Phase 5 from scratch is acceptable; partial section re-runs are also acceptable if the user names specific sections.

## Definition of Done

- [ ] Phase 1 produced ≥2 file citations OR explicit "no related code found".
- [ ] Phase 2 trigger heuristic evaluated; AUQ fired if and only if a UI signal was present.
- [ ] Phase 3 used `AskUserQuestion` ONE-AT-A-TIME, ≤5 questions, single dimension per question.
- [ ] Phase 4 presented 2–3 approaches with Recommended first; each option had rough-fit + key-tradeoff body.
- [ ] Phase 5 used section-by-section AUQ; NO single AUQ batched all sections.
- [ ] Phase 6 wrote the design doc to `.geniro/planning/<branch>/<YYYY-MM-DD>-<topic-slug>-design.md` with ALL THREE markers (YAML frontmatter + HTML comment + path placement).
- [ ] Phase 6 committed the design (commit message `design: <topic>`).
- [ ] Phase 7 self-review ran; placeholders/contradictions/ambiguities/scope-creep checked; cap 2 rounds respected.
- [ ] Phase 8 user re-review AUQ fired; user picked one of the three options.
- [ ] HARD-GATE released only on Phase 8 "Approve".

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "This task is too simple to need a design" | "Simple" projects are where unexamined assumptions cause the most wasted work. Design can be short (Phase 5 trivial = 1–2 sections); presenting and approving is mandatory. The HARD-GATE applies to EVERY task regardless of perceived simplicity. |
| "I'll skip Phase 8 user re-review, my self-review is enough" | Agent self-review and user re-review catch different defect classes — placeholders/contradictions vs intent/missing-constraint. Auto-dropping Phase 8 repeats the medium-gate failure mode (auto-handling a gate the user has unique context for). |
| "I'll batch all sections into one Phase 5 AUQ to save round-trips" | Forbidden. Section-by-section approval enables surgical revisions; batched AUQ forces batched edits across every section if any one needs changes. The round-trip cost is real but cheap; the batched-edit cost on a single disagreement is much higher. |
| "I'll skip Phase 2 visual companion silently for ALL topics to be safe" | Silent skip is correct ONLY when no UI signal fires. The trigger heuristic must evaluate; firing-when-no-signal and skipping-when-signal are both bugs. |
| "Phase 7 is enough; no need to bother the user with Phase 8" | Same failure mode as auto-dropping medium-gate. The user catches what the orchestrator cannot see. |
| "I'll write the design doc with only the YAML frontmatter — that's enough" | Defense in depth requires all three markers (path + HTML comment + frontmatter). See `design-doc-detect.md` § Why defense in depth — each marker survives a different user action. |
| "Phase 4 — 4 or 5 approaches gives the user more choice" | More than 3 indicates Phase 3 didn't narrow scope; the right move is loop back to Phase 3, not flood Phase 4 with options. |
