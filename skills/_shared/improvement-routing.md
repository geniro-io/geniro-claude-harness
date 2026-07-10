# Improvement Routing (canonical)

## Contents

- §Candidate bar — four binary gates + significance floor + cap (worth-gating; runs before target-routing)
- §Routing table — improvement type → target file
- §Decision logic when target is ambiguous
- §ADR target — when to use it (sparingly)
- §Why code rules go to `.claude/rules/`, not CLAUDE.md
- §Reflection-agent feed — how to source candidates (agent via `/geniro:reflect` vs inline)
- §Presentation — surface the routed suggestions one candidate at a time

When an improvement pass — `/geniro:reflect`, or a skill's inline candidate-drafting step — finds a project-scope improvement, first gate it through the §Candidate bar (is it worth persisting at all?), then classify the survivors by **routing target** using the table below. **Project scope only** — do NOT route to plugin-internal files (`${CLAUDE_PLUGIN_ROOT}/agents/*.md`, `${CLAUDE_PLUGIN_ROOT}/skills/**`, `${CLAUDE_PLUGIN_ROOT}/hooks/**`); the plugin is installed globally and overwritten on update. Plugin-file improvements belong to a separate channel — submit a PR to the plugin repo OR edit your local plugin install directly (out of scope for the improvement pass).

## Candidate bar

A rule is a permanent tax: it loads into every future session and dilutes compliance with every rule already in place (§"Why code rules go to `.claude/rules/`, not CLAUDE.md" below carries the budget arithmetic for CLAUDE.md — the same economics apply to every rule target). The reflection step is therefore not asked to "find something": an open-ended improvement pass returns candidates even when the work taught nothing — the same over-reporting effect documented for reviewers — so **zero candidates is the correct and common outcome**.

The bar gates WORTH; the §Routing table below routes TARGET (the §"Decision logic when target is ambiguous" ladder resolves only ambiguous targets). Bar first, routing second — a candidate that fails the bar never survives to the routed output.

### Four binary gates — all must pass

Run each gate as its own binary judgment, and write the reasoning before the verdict. When a gate is uncertain, it fails — a borderline rule taxes every future session, while a dropped candidate costs nothing because the underlying observation can still be emitted as a learning.

1. **Evidence** — the candidate cites what grounds it. What counts as evidence depends on the candidate's source:
   - **Task-derived** (a /implement, /review, /refactor, or /debug run): a concrete incident from this task — an observed failure, a user correction, or real wasted-time friction — with a citation (file:line, the finding, or the correction itself). A smooth run yields no task-derived candidates — these lessons are extracted from failures, not from things that went fine.
   - **Discovery-derived** (/onboard's just-authored map, /plan's just-approved spec): the verified fact itself is the evidence — cite its source (the map section / spec section that states it) AND the gate-4 dedup verdict (`ADD`, or `UPDATE` when an existing rule is stale or partial). Discovery sources have no failures to cite; their bar is verified + not already fully covered by a rule file, and they remain subject to gates 2-4 like any other candidate.
2. **Counterfactual** — without this rule, a competent future session would plausibly repeat the failure or pay the cost again. Drop what the agent gets right or cheaply derives at the moment it matters — standard engineering practice, base-model knowledge, a fact one obvious file read away. Keep what it would otherwise re-derive every session: build/test/lint commands and stack identity are derivable from the code, but re-derivation each session is exactly the recurring cost a CLAUDE.md line removes — which is why the §Routing table sends commands there. This is the official CLAUDE.md line test: "would removing this cause mistakes? If not, cut it."
3. **Generality** — the rule is statable as `WHEN <condition> → <action>` where the WHEN-clause matches situations beyond the just-finished task. Restate the lesson one level up; if it cannot be restated above the specific scenario, it is an episodic learning at most, never a rule.
4. **Dedup verdict** — grep `CLAUDE.md`, `.claude/rules/*`, and `.geniro/instructions/*` for the candidate's keywords and emit an explicit verdict: `ADD` (nothing covers it), `UPDATE <file:line>` (an existing rule covers it partially — propose amending that rule, not adding a sibling), or `NOOP` (already covered — drop). NOOP is the expected default.

### Significance floor

Every surviving candidate carries `Significance: critical | general`:

- `critical` — prevents recurrence of a CRITICAL/HIGH-class failure per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §1.
- `general` — the WHEN-clause spans most future tasks of its kind across the project.

A candidate that is neither critical nor general is dropped — it never becomes a rule candidate. No separate routing is needed: the underlying observation still rides the owning skill's own learnings-emit step.

### Cap

At most 3 candidates per run. On overflow keep the 3 highest-significance and drop the rest (their observations still ride the owning skill's own learnings-emit step — no separate routing). Same-significance ties keep the strongest Evidence. The cap is a forcing function — ranking is the filter: being forced to keep only the strongest 3 exposes which candidates were padding.

## Routing table

| What was discovered | Route to | Why |
|---|---|---|
| New/changed build, test, or lint command | **CLAUDE.md** | Loaded every turn for every agent — commands must be always at hand |
| Tech stack or project structure change | **CLAUDE.md** | Future sessions need current project shape |
| Project-wide gate that must survive compaction (e.g. "never commit without approval") | **CLAUDE.md** | Reserved for critical compaction-surviving guidance |
| **File-pattern-scoped** code rule (e.g., language-specific, directory-specific) | **`.claude/rules/<scope>.md`** with YAML frontmatter `paths: [glob, ...]` (Anthropic-native, **file-scoped** — auto-loads only when Claude reads/writes a matching file) | **Loaded only when the matching files are touched — keeps CLAUDE.md lean and avoids "rule bloat" that dilutes compliance for every CLAUDE.md rule. The native Claude Code analog of Cursor's `.mdc` auto-attach.** |
| **Cross-cutting code-style / convention rule that should apply to ALL code-writing and ALL review (regardless of file pattern)** | **`.geniro/instructions/code-style.md`** (Geniro cross-skill scope; authored via `/geniro:instructions create code-style`) | Loaded by `implement` (Phase 1 / Phase 3 entry), `refactor` (Phase 1 / Phase 3 entry), `review` (Phase 1 entry); pre-inlined into reviewer-agent prompts for the conventions / design / architecture dimensions. Use this when the rule is style-adjacent and applies project-wide, not gated on a glob. |
| Quality gate, workflow step, or hard constraint the user enforced for **skill behavior** (e.g. "always run codegen after editing DTOs", "max PR size 500 lines") | **`.geniro/instructions/<skill>.md`** (or `global.md` if cross-skill) | Geniro-specific **skill-scoped** — loads when the matching skill runs, not on every file edit |
| Pattern that should be enforced automatically without LLM judgment | **Project rules/hooks** (CI, lint, project-local hooks) | Automated enforcement beats manual memory |
| Non-obvious gotcha, workaround, or debugging insight | **Knowledge** (`.geniro/knowledge/learnings.jsonl`, path resolved per `_shared/primary-worktree.md`) | Searchable across sessions via `lib/query-learnings.sh` (loaded at every pipeline skill's Phase 1) |
| Architectural decision with rationale (lightweight, internal) | **Knowledge** (`.geniro/knowledge/learnings.jsonl`, path resolved per `_shared/primary-worktree.md`) | Provides context for future changes in the same area |
| Architectural decision that is **(1) hard to reverse, (2) surprising without context, AND (3) the result of genuine trade-offs** — including refactor candidates explicitly REJECTED with rationale | **ADR** (`docs/adr/NNNN-<slug>.md` or `docs/decisions/NNNN-<slug>.md`) | Survives team turnover and shipped code; the durable record for "why we chose / rejected X" when learnings.jsonl is too transient |
| User preference or correction about how to collaborate | **Memory** (native auto-memory) | Auto-retrieved by Claude in future sessions |

## Decision logic when target is ambiguous

The §Routing table names the target for each discovery type; this ladder resolves only the case where a candidate could fit more than one. Apply in order — first match wins, so the priority ordering IS the tie-break:

1. Enforceable by a linter / formatter / CI check / hook without LLM judgment → **Project rules/hooks** (automation beats every memory-based target).
2. Needs file-pattern scoping (fires only when matching files are read/written) → **`.claude/rules/<scope>.md`** with `paths:` glob — chosen before the broader instruction targets below.
3. Cross-cutting code-style with no file pattern → **`.geniro/instructions/code-style.md`**; a skill-behavior gate / workflow step → **`.geniro/instructions/<skill>.md`**.
4. Project-wide command, structure fact, or compaction-surviving gate every agent needs every turn → **CLAUDE.md**.
5. Hard-to-reverse AND surprising-without-context AND genuine-trade-off decision (incl. a refactor candidate REJECTED with rationale) → **ADR**; any lighter reusable insight → **Knowledge**.
6. Collaboration preference / correction → **Memory** (native auto-memory).
7. Uncertain TARGET → default **Knowledge** (lowest risk, still searchable). Resolves target ambiguity only — a candidate of uncertain WORTH already failed the §Candidate bar and never reaches the ladder.

## ADR target — when to use it (sparingly)

Architecture Decision Records survive code, sessions, and team turnover. Use them only when **all three** criteria hold:

1. **Hard to reverse** — undoing the decision later requires non-trivial migration (e.g., choice of database engine, auth model, monorepo vs polyrepo, sync vs async API).
2. **Surprising without context** — a future reader (human or agent) would ask "why did we do this?" and not infer the answer from the code alone.
3. **Genuine trade-offs** — the decision had real alternatives with real upsides; this is not "we picked the obvious option."

If any criterion fails → use **Knowledge** (`learnings.jsonl`) instead. Most architectural choices are NOT ADRs — bias toward learnings.

### Where to write

- Look for an existing `docs/adr/` or `docs/decisions/` directory (per `/geniro:setup` Phase 1 detect-output step §1.6).
- If none exists, propose creating `docs/adr/` only after user confirms via `AskUserQuestion`.
- Filename: `NNNN-<short-slug>.md` where NNNN is the next sequential number (zero-padded). Use Glob to find the highest existing NNNN.

### ADR template (when creating)

```markdown
# NNNN. <Decision title — verb + object>

**Status:** Accepted | Superseded by NNNN | Rejected
**Date:** YYYY-MM-DD

## Context
What was the situation that forced a decision? What constraints applied?

## Decision
What did we choose? State it as a single sentence at the top.

## Alternatives considered
- **Option A** — pros / cons / why rejected
- **Option B** — pros / cons / why rejected

## Consequences
What do we accept by choosing this? What becomes harder? What becomes easier?

## References
- Related ADRs (NNNN), commits, learnings, or external sources
```

### Skills that route to ADR

- `/geniro:investigate` save-routing step — "Save key findings to memory" gains an ADR sub-option when the finding meets all 3 criteria.
- `/geniro:debug` — root causes traced to an undocumented architectural choice trigger an ADR proposal alongside the L2 emit.
- `/geniro:refactor` — refactor candidates explicitly REJECTED by the user (PRODUCT-DECISION findings, escalated work) propose an ADR capturing "why we did NOT do X." 4th AUQ option fires only when ADR-eligibility criteria met (hard to reverse + surprising without context + genuine trade-offs).
- `/geniro:reflect` — the on-demand improvement walk presents ADR alongside CLAUDE.md / `.claude/rules/` / instructions / knowledge targets, grouped per usual.

## Why code rules go to `.claude/rules/`, not CLAUDE.md

CLAUDE.md is loaded **every turn for every agent**, so its budget is finite — Anthropic's official guidance is **<200 lines** and "rule bloat" is a documented anti-pattern: each added line dilutes compliance for *every* CLAUDE.md rule, including the high-value ones. Code rules / coding conventions / style patterns only need to fire **when matching files are read or written** — Anthropic-native `.claude/rules/<scope>.md` files with `paths:` YAML frontmatter provide exactly that file-scoped auto-attach. Anthropic, Cursor, GitHub Copilot, and the AGENTS.md spec have all converged on this split: always-on global file + path-scoped rules files.

### Three-tier rules: file-scoped, skill-scoped, cross-skill

| Mechanism | Path | Triggers when | Use for |
|---|---|---|---|
| **Anthropic-native rules file** | `.claude/rules/<scope>.md` with `paths: [glob, ...]` frontmatter | Claude reads/writes a file matching the glob | Code rules, coding conventions, style/naming patterns, file-pattern constraints, language-specific rules |
| **Geniro instructions file** | `.geniro/instructions/<skill>.md` (or `global.md`) | The matching skill (`implement` / `plan` / `review` / `debug` / `refactor` / `onboard` / `investigate`) starts a run | Skill-behavior customization: extra workflow steps, quality gates, hard constraints applied at skill phase boundaries |
| **Geniro cross-skill code-style file** | `.geniro/instructions/code-style.md` | A Geniro pipeline skill (`implement` / `refactor` / `review`) starts a code-writing or review phase | Cross-cutting code-style / convention rules that apply to ALL code writing and ALL review (regardless of file pattern). Pre-inlined into 3 style-adjacent reviewer-agent dimensions (conventions, design, architecture). |

The three are complementary, not overlapping — choose by the trigger you want (the table's "Triggers when" column). CLAUDE.md stays reserved for commands, tech-stack/structure facts, and project-wide gates that must survive context compaction.

## Reflection-agent feed

Two ways to source the improvement candidates that feed §Presentation. Match the source to how rich the change signal is:

- **Reflection agent** — `/geniro:reflect` (user-invoked, on-demand) spawns `${CLAUDE_PLUGIN_ROOT}/agents/reflection-agent.md` to synthesize candidates in an isolated context from recent work — a diff, a finding set, or session-transcript extracts. An isolated read beats inline synthesis here: the session that produced the work carries its author's blind spots; a fresh agent catches durable lessons the author's own reasoning skips.
- **Inline** — when the orchestrator already holds the whole artifact it just authored and there is no fresh diff to discover (`/plan`'s approved spec, `/onboard`'s codebase map). Draft the candidates inline against the §Candidate bar + routing table above. A separate agent re-reading a self-authored artifact adds cost without the anti-anchoring benefit, so inline is the right call there.

### Spawn slots (reflection-agent mode)

Pass the agent: **mode**, **the change** (a diff summary + changed files, a finding set + the diff it was raised against, or session-transcript extracts), **project context + rule-file paths** to dedupe against (`CLAUDE.md`, `.claude/rules/*`, `.geniro/instructions/*`), and **prior declines** for the scope (`query-learnings --type user_rejected_suggestion --tag auq-rejection --scope <scope>`, or `none`). Spawn via the registration ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` — OMIT `model=`. The agent returns candidates that passed the §Candidate bar per its Output Format; it never writes.

Run the spawn synchronously. `/geniro:reflect` is on-demand — the candidate walk IS its deliverable, so there is no later decision gate the spawn could delay.

### Anchor + echo (both sources)

The improvement pass must prove it fired — a step that trails off as housekeeping after the visible deliverable is the documented drop vector (same failure mode the L2 emit's caller contract fixes, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract"). Run it as a named step before the caller's finalize prompt, and echo one plain line — `Reviewed for improvements: <N> candidate(s)` — as a self-check that it fired. The echo is unconditional, including at N=0: zero is the majority outcome, so a silent zero is indistinguishable from a dropped step. When the candidate list is empty, skip only the §Presentation prompt — the echo still fires.

### Coexistence with recurrence rule-capture

A candidate tagged `Recurrence-eligible: yes` restates a learning already seen 3+ times — route it to the rule-capture path (the `AskUserQuestion` header "Capture as rule", hand-off to `/geniro:instructions create`), NOT to the §Presentation prompt. This avoids prompting the user twice for the same rule. Two cases:

- A skill with a **standalone recurrence offer** (`/refactor`'s and `/debug`'s recurring-pattern rule offers per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/recurrence-rule-capture.md`) fires that offer at its own site; any §Presentation walk covering the same run dedupes against it so the same rule is never offered twice.
- A caller with **no standalone recurrence offer** (`/geniro:reflect`) routes a `Recurrence-eligible: yes` candidate straight to `/geniro:instructions create`, and sends the rest to §Presentation.

## Presentation

Surface candidates **one at a time** in the shared visual gate language (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §"Visual rendering language"; the two-step render-then-question shape and render-exists check per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering). A rule is a permanent tax on every future session (§Candidate bar), so the user has to see exactly what each rule says, where it lands, and what incident justifies it before approving — a single bundled "apply all" prompt hides that detail and trains the user to rubber-stamp or dismiss the whole batch.

Draft each candidate as `target / file / change / why`, then walk them in descending `Significance` order (the §Candidate bar caps the walk at 3). For each candidate, render a self-contained chat message, then fire its own lean `AskUserQuestion`:

- **Tracker** (only when ≥2 candidates remain) — `● Rule 1 of 2 · ○ Rule 2`, per the gate-rendering tracker.
- **Opener** — one sentence naming the candidate, e.g. `**Rule 1 of 2** — a testing rule this run exemplifies.`
- **What I'd write** — the candidate's `change` (the `WHEN <condition> → <action>` body) shown verbatim in a fenced block, exactly as it would land in the file. The rule text itself, not a paraphrase of it.
- **Where** — the routed `target` + `file` in plain English, e.g. "appends to your project's API-testing rules (`.claude/rules/api-testing.md`)". Name the file and what kind of rule store it is.
- **Why** — the candidate's durable value followed by its Evidence citation from the §Candidate bar, both expanded to plain English, so the user judges the incident behind the proposal rather than the proposal alone. Frame a `Dedupe: UPDATE <file:line>` verdict as amending the existing rule at that location, not adding a sibling.
- **A visual** — the smallest aid that shows the rule's effect (the rule rendered as it will read in the file, or a before/after of the behavior it guards).

Then the lean question (header `Rule N of M`, or just `Rule N` when only one candidate remains), options:
- **"Write this rule"** — apply this one candidate (pre-select `Recommended` when `Significance: critical`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy).
- **"Skip this rule"** — decline just this candidate and continue to the next.
- **"Skip the rest"** — decline this candidate and all remaining ones; ends the walk.

Write each approved candidate before rendering the next — for `.geniro/instructions/` and `code-style.md` targets, hand off to `/geniro:instructions create`; for CLAUDE.md / `.claude/rules/` / ADR / learnings, the orchestrator writes via the atomic state helpers. On a `Skip this rule` / `Skip the rest` / explicit decline, log it via `emit_rejection_if_signal` (`${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh`) so the declined suggestion does not re-surface next run.

An empty candidate list opens no `AskUserQuestion` — skip the walk entirely — but the `Reviewed for improvements: 0 candidate(s)` echo still fires (per §"Anchor + echo").

A read-only caller routes instead of applies — it runs the same one-at-a-time render, but the per-candidate options become "Capture this rule" / "Skip this rule" / "Skip the rest", handing instruction-scoped picks to `/geniro:instructions create` and listing CLAUDE.md / `.claude/rules/` / ADR picks in chat for the user to apply (it writes no project file).
