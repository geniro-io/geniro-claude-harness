---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
  - ".claude/skills/**/*.md"
---

# Skill & agent authoring — voice, tone, and prose

Positive-guidance companion to `.claude/rules/skill-authoring.md` (negative-space) and `.claude/rules/skill-structure.md` (mechanical). This file covers how prose inside skill / agent / reference files should be written so the orchestrator model parses it efficiently and follows it reliably.

Sources for the rules below: Anthropic [`skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md), [Skill best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), and the [Claude Code skills reference](https://code.claude.com/docs/en/skills), which is where §Rule placement's compaction budget comes from. Where a rule rests on published measurement, the section says so; where it rests on taste, it says that too. Treat an unlabelled rule as taste.

## Voice

- **Imperative form.** "Read X." / "Apply the procedure in Y." / "Spawn the agent with these slots."
  - Not "Claude should consider reading X." / "It may be useful to apply Y." / "You can spawn the agent."
- **Second-person collapses to imperative.** "You read the spec" → "Read the spec." Cuts a word, removes ambiguity about who acts.
- **No first-person plural.** No "we", "us", "our team". The skill body addresses ITS reader (a future orchestrator session); the authoring team's identity is irrelevant at runtime.
- **Third-person in descriptions** (frontmatter only). "Processes Excel files and generates reports." Anthropic's docs are explicit: inconsistent point-of-view in descriptions causes discovery problems.

## Explain WHY, don't shout MUST

Per Anthropic's `skill-creator` verbatim: *"If you find yourself writing ALWAYS or NEVER in all caps, or using super rigid structures, that's a yellow flag — if possible, reframe and explain the reasoning so that the model understands why the thing you're asking for is important."*

The dividing line: **explain WHY for rules the model would otherwise rationalize around** — anti-patterns, escape hatches, error semantics, anything whose cost is invisible at the call site. **State WHAT for routine procedure** — file paths, command syntax, slot tables, phase ordering. A reason bolted onto a routine imperative is filler; a bare imperative on a rule the model can talk itself out of gets talked out of. The reframed form costs ~10-15 tokens more per rule and buys the ability to apply the constraint to edge cases the original wording didn't anticipate.

| Bare imperative that invites drift | Reframed with the reason |
|---|---|
| "NEVER skip the test run." | "Run the test suite once at end-of-phase. The Phase 3 review pre-condition assumes green tests; skipping leaves the review reading stale code." |
| "ALWAYS use atomic_state_write." | "Write state.md via `atomic_state_write` — direct `Edit`/`Write` calls bypass the state-helper enforcement hook and corrupt mid-crash." |
| "Spawn the reviewers in parallel." | "Spawn every reviewer dimension in ONE assistant response — separate turns serialize execution and double wall-time." |

Routine procedure needs none of that: "Spawn the agent with `subagent_type: reviewer-agent`." / "Read `<task-dir>/.kr-out.md`." / "Set `phase: ship` on entry." Appending "because the state machine expects it" to any of those buys nothing — the state machine is documented in its own section.

**Caps and MUST have exactly one home**: the right-hand cell of an anti-rationalization row, where the left cell is the rationalization the model might generate and the right cell has to confront it bluntly. Caps there are fine when accompanied by reasoning. Caps in normal prose are the yellow flag.

**Prefer the positive form** — "write one-line comments" over "never write verbose comments" — and pair any prohibition you keep with what to do instead. Anti-rationalization rows already have this shape: the left cell names the drift, the right cell states the correct move. Treat this one as a stylistic preference rather than a measured effect: no instruction-following benchmark isolates it, and the circulated evidence for priming-by-prohibition comes from a moral-dilemma study on sub-4B models. Keep the prohibition form where a positive rewrite would blur a data-loss or external-effect bar.

## Assume a capable model

Write instructions at the altitude of goal + constraint, not mechanics. The model already knows standard tooling, shell idioms, platform quirks, and general engineering practice — spelling those out costs tokens, goes stale, and (worse) primes the model toward one specific mechanism when a better one exists for the environment it's actually running in.

- "Poll until the server responds or ~30 seconds elapse" — the model picks a loop shape that works on its platform. Don't prescribe the loop, the sleep interval, or a `timeout`-command wrapper.
- "Bound the fetch so an offline remote can't hang the run" — not a snippet probing for `timeout` vs `gtimeout`.

Detail earns its place only where the model reliably gets it wrong without it (the explain-WHY cases: anti-patterns, escape hatches, error semantics) or where the value is a project contract (exact paths, schemas, thresholds, canonical option labels). Litmus: would a competent engineer joining the project need this sentence, or just the goal? If just the goal, write just the goal.

## One default + escape hatch

Per Anthropic best-practices: *"Don't present multiple approaches unless necessary. Bad: 'You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or...' Good: 'Use pdfplumber for text extraction... For scanned PDFs requiring OCR, use pdf2image with pytesseract instead.'"*

Pattern: state the default authoritatively, then call out the one specific case where the escape hatch applies.

| Anti-pattern (menu of equivalents) | Default + escape hatch |
|---|---|
| "You can run tests with pytest, jest, vitest, or go test depending on the project." | "Use the test command from CLAUDE.md §'Essential Commands'." |
| "Reviewers may spawn at haiku, sonnet, or opus tier." | "Reviewers inherit the orchestrator's tier (OMIT `model=`). Custom reviewers declare their own tier in `.geniro/instructions/review-extra/<slug>.md` frontmatter — honor that." |
| "Worktree creation is optional. You can also work in the current branch, on a feature branch, or in a worktree." | "Create a worktree by default; the `no-worktree` modifier in `$ARGUMENTS` skips it." |

The escape-hatch form is shorter, more deterministic, and easier to verify in the anti-rationalization table.

## Terminology consistency

Pick one term per concept and use it across the entire skill file. Per Anthropic: *"Consistency helps Claude understand and follow instructions."* Mixed terminology fragments the model's attention across synonyms it has to mentally unify.

| Concept | Pick one | Don't mix |
|---|---|---|
| Git working tree | `worktree` | `worktree` + `checkout` + `tree` + `clone-of-the-repo` |
| Plugin shared helper | `helper` (or `shared helper`) | `helper` + `utility` + `lib script` + `tool` |
| User-approval prompt | `AUQ` (after first definition) or `AskUserQuestion` | `AUQ` + `prompt` + `confirmation dialog` |
| Subagent spawn | `spawn` | `spawn` + `invoke` + `call` + `delegate` |
| Sub-step | `Step N.M` consistently throughout | `Step 0.5` + `Sub-step 0b` + `Phase 1 §3` for the same thing |

Unify a concept's synonyms before commit.

## Leading words

When a rule restates one quality across a phase ("fast, deterministic, low-overhead" re-explained at every step), collapse the restatement into a single concept word the model already holds from pretraining — a *tight loop*, a *tracer bullet*, a *frontier* — and repeat the word, not the sentence. The word anchors the same behavior at every occurrence for fewer tokens than the restatement, and recruits the priors the model already attaches to the concept. Reach for an existing concept first: a coined word recruits no priors and has to be re-defined at every use.

| Before (quality restated per step) | After (leading word) |
|---|---|
| "Phase 2 checks must be fast, deterministic, and low-overhead. After each fix, re-run the checks quickly; every re-run should be cheap and produce the same result." | "Phase 2 is a tight loop: cheap, deterministic checks re-run after every fix. Keep each check inside the tight loop." |

## Rule placement

**Front-load everything the model must check every turn**, and keep the tail for detail it can look up. The governing mechanic is compaction, and it is documented, not inferred. Per the [Claude Code skills reference](https://code.claude.com/docs/en/skills) verbatim: *"Claude Code re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens… older skills can be dropped entirely after compaction if you have invoked many in one session."*

Two consequences an author has to design around:
- **A skill over ~5,000 tokens loses its tail for the rest of the session at the first compaction.** A long, multi-phase, subagent-heavy run is exactly where compaction is the expected case — so the invariants and the anti-rationalization table, the content that most needs to survive, is the content most at risk if it sits at the bottom.
- **A skill invoked early in a busy session can be dropped in full.** The budget fills from the most recent invocation backwards.

Placement rules for a SKILL.md:
- **Top (inside the first ~5,000 tokens):** role statement, phases overview, loop invariants, budgets, the tool surface, and the anti-rationalization table. These are the rules the model checks every turn and the ones that must survive a summary.
- **Below that:** per-phase Steps with detail, the REFERENCE list, state recovery. Refer to these by name from the invariants at the top so the model jumps to a phase rather than scanning for it.

If a critical invariant lives past the boundary, move it into the Loop invariants section and cite it by `#N` from the phase that needs it. Where a skill genuinely cannot fit its load-bearing rules in 5,000 tokens, the remedy is re-invoking it after compaction, which the same doc recommends.

**What this rule is not founded on.** The usual citation is [Liu et al. 2024](https://aclanthology.org/2024.tacl-1.9/)'s U-shaped "lost in the middle" attention curve. Chroma's 2025 replication across current frontier models found no notable position effect on retrieval, so do not move content on the theory that the middle of a file is unreadable. Move it because the tail may not be re-attached.

## Token budget awareness

**A reference file's cost is its size times its load frequency.** A file loaded on every run of a skill is part of that skill's always-on budget; only a conditionally-loaded file is cheap. Before moving detail into a reference, state which runs will not load it — if the honest answer is "none", the move saves nothing and adds a tool round-trip. The same test kills the tempting move on an `agents/*.md` body, which is injected as the subagent's system prompt in full: relocating a rule there converts free prompt tokens into the same tokens plus a Read the agent might skip.

**What the evidence prices is rule count and rule applicability, not word count.** Rules that are plausible but do not apply to the task in hand measurably degrade rule-guided reasoning, while an equivalent volume of inert text costs comparatively little — the expensive operation is forcing the model to adjudicate which of several similar-looking rules binds right now. Where many rules bind at once the failure mode is omission: the model acts as if the dropped rule was never written, rather than executing it poorly. So partitioning beats deleting. Path-scope a rule set so it loads only for the work it governs and the same words stop competing.

Practical heuristics, in priority order:
- **Scope before you cut.** A rule that applies to one kind of task belongs behind a path scope or a conditional load, not in the always-on body.
- **Restatement summaries** (a paragraph ending "in other words, …") — drop. The reader read the preceding paragraph.
- **Hedge clauses** ("this may or may not", "depending on the situation") — commit to the condition or drop the line.
- **Defensive disclaimers** ("Note that this only applies if X") — fold into the rule itself as a single-clause conditional.
- **Inline pseudo-code and multi-paragraph step explanations** → move to a reference file, but only once you have named the runs that skip it. Otherwise you have relocated the cost and added a round-trip.

Reference files have no token-budget pressure until loaded — be generous there. SKILL.md needs to be lean.

## Time-sensitive content

Don't inline deprecated procedures or obsoleted patterns in the main body. Per Anthropic: wrap them in collapsible HTML:

```markdown
<details>
<summary>Legacy v1 API (deprecated 2025-08; will be removed in next major version)</summary>

[old procedure]

</details>
```

The orchestrator can still find it via grep if needed, but it doesn't compete for attention with the current procedure.

## User-facing output uses plain English

### The fresh-user test

The single test that governs every user-facing string: **a fresh user with the plugin installed but no architecture docs loaded — no `CLAUDE.md`, no `state-tier-spec.md`, no `MEMORY.md` — must be able to act on the string without first learning a Geniro-specific identifier.** If the user has to learn `T2` / `FIX-NOW` / `phase: triage` / `m5-v2` / `KR` to understand what the orchestrator is doing or what the question is asking, the string is wrong — restate the identifier's meaning inline OR drop the identifier and substitute the plain-English form.

The test has two dimensions; a user-facing string must pass both:

- **No untranslated identifiers (vocabulary).** The jargon dimension — `T2` / `FIX-NOW` / `phase: triage` must be restated inline or dropped.
- **No assumed hidden context (completeness).** The string must explain the situation it is about. A question or report line is wrong if it can only be understood by someone who saw the subagents' output. Example: a review gate asking *"How should we handle the implicit entity-default @Filter at the 3 call sites?"* fails even though every word is plain English — the user was never shown what that code does, why it is a concern, or what the options mean. For decisions that carry finding or investigation context, render the self-contained explanation to a chat message first, then fire a lean question, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering.

This test applies to **everything the orchestrator surfaces to the user**:

- Chat narration (step echoes, progress updates, transition messages).
- `TodoWrite` labels (subject + description).
- `AskUserQuestion` `header` / `question` / `description` / option `label` / option `preview`.
- Status echoes ("Loading X..." / "Spawning Y...").
- Final report sections (Ship report, Review report, Investigate answer).
- Error messages surfaced to chat (NOT the underlying state-file `## Errors` body section — that's a structured artifact for downstream consumers).

Why this is a recurring failure mode: skill body prose is **author-facing** — it uses compact identifiers because skill authors read them hundreds of times. When the orchestrator narrates a step, it tends to echo the skill body verbatim. The fix is at the source — keep authoring shorthand out of strings the model is likely to echo.

### Translation tables

Cover the categories below. Extend when new internal vocabulary appears in skills.

**Memory-system abbreviations.**

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `L1` / working memory / working state | "task state" / "session state" |
| `L2` / episodic memory / learnings | "past learnings" / "prior knowledge" |
| `L3` / semantic memory / snapshot | "project snapshot" / "codebase map" |
| `L4` / procedural memory / instructions | "custom instructions" / "project rules" |

**State-tier abbreviations.**

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `T1` / ephemeral state | "scratch files" / "transient working files" |
| `T1.5` / durable task state | "task artifacts" |
| `T2` / handoff | "handoff" (drop the `T2` prefix entirely — the word "handoff" carries the semantic) |
| `T3` / persistent state | "persistent state" (drop `T3`) |

**Subagent shorthand.**

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `KR` / `KR subagent` / `KR output` | "knowledge-retrieval agent" / "knowledge-retrieval output" |
| `CE` / `CE subagent` / `CE output` | "codebase-explorer agent" / "codebase-explorer output" |
| `TR` / `TR subagent` / `TR output` | "test-runner agent" / "test-runner output" |

**Internal phase / step labels.** Phase / step numbering (`Phase 4.3`, `Phase 5.3`, `Step 12`, `Phase 6 Pre-gate`) is meaningful only to skill authors. The user knows what the orchestrator is DOING, not which numbered step it's on. When cross-referencing a step internally, anchor by the concept ("the open-question gate"), not the number ("Phase 6 Pre-gate").

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `Phase 4.3` / `Phase 4.3 test-gate` | "test-confirmation gate" / "confirming tests before writing code" |
| `Phase 5.3` / `Phase 5.3 auto-emit` | "recording the pattern as a learning" |
| `Step 0 workspace AUQ` | "workspace setup question" |
| `Step 12 handoff resolution` | "resolving open questions from the prior review" |
| `Phase 6 Pre-gate` | "the open-question gate" |
| `Step 0a` / `Step 0b` / `Step 0c` | "detecting current context" / "deciding the action" / "asking for confirmation" |
| `B1` / `b2/5` / batch labels | "file group 2 of 5" or content-anchored ("the queue-service files") |

**Decision-type tags.** The `FIX-NOW` / `PRODUCT-DECISION` / `TESTABLE` / `INTENT-CHECK` taxonomy is reviewer-internal; `ROOT-CAUSE` / `SYMPTOM` / `UNKNOWN` is debug-internal. Both are jargon to a fresh user.

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `FIX-NOW` | "automatic fix" / "I can fix this directly" |
| `TESTABLE` | "this can be verified with a test" |
| `PRODUCT-DECISION` | "needs your decision" / "judgment call required" |
| `INTENT-CHECK` | "needs you to confirm intent" |
| `ROOT-CAUSE` | "root cause" |
| `SYMPTOM` | "surface symptom" / "downstream effect" |
| `UNKNOWN` (cause) | "cause not yet identified" |

**Frontmatter field references.** YAML field names (`approvals[]`, `non-resumable-actions[]`, `workflow_refs[]`, `open_questions[]`) are storage identifiers. Users care what they MEAN, not how they're stored.

| Internal term | Plain-English form for user-facing prose |
|---|---|
| `approvals[]` (frontmatter) | "decisions you've made in this run" / "saved choices" |
| `non-resumable-actions[]` | "external actions that can't be undone (push, PR open)" |
| `workflow_refs[]` | "linked tracker tickets" |
| `open_questions[]` | "open questions from the prior review/debug" |
| `related_findings[]` | "findings this question gates" |

**Helper / function / hook names.** Implementation identifiers (`atomic_state_write`, `load_semantic`, `query_learnings`, `emit_learning`, `update_semantic`, `SessionStart`, `PreToolUse`, `Stop`) belong in author-facing prose, never narration. If the user needs to know a helper ran (e.g., to follow up on a failure), describe what it DID, not which function did it: "Couldn't refresh the project snapshot" beats "load_semantic returned rc=11".

**Schema versions.** `m5-v1` / `m5-v2` / `m6-v1` are internal versioning markers. Don't surface unless the user must act on a version difference (e.g., re-author a spec after a breaking migration) — and even then, describe the action ("this spec uses the older format and needs re-authoring"), not the version number.

**State-machine phase enum values.** `phase: analyze`, `phase: implement`, `phase: persist`, `phase: triage`, `phase: classify` are storage values. Describe what's HAPPENING, not which enum state the machine is in: "Analyzing the change scope" not "Now in `phase: analyze`".

**Reviewer dimension slugs.** Some are already plain-English (`bugs`, `security`, `architecture`, `tests`). Slug forms with hyphens (`spec-compliance`, `pr-metadata`, `code-quality`) need light expansion in narration: "specification compliance" / "PR metadata check" / "code quality" — same words, drop the slug-style hyphenation.

### What's exempt

The rule applies to NARRATIVE prose surfaced to the user. It does NOT apply to:

- **Filesystem paths** (`.kr-out.md`, `.geniro/state/handoff/from-review-<branch>.md`, `_CODEBASE_MAP.md`). Paths are identifiers that carry semantic weight through prefixes and extensions. Keep them.
- **YAML / JSON keys inside code blocks** rendered to the user. Frontmatter examples and schema illustrations show literal keys.
- **Architectural sections that document the layer / tier / subagent system itself** — `CLAUDE.md` §Memory Layers / §State Files, `skills/_shared/state-tier-spec.md`, anti-rationalization rows discussing layer precedence. Those address skill authors, not end users.
- **Skill body declarative prose** that references system architecture for authors (e.g., a parenthetical "writes a handoff per state-tier-spec.md §T2"). The orchestrator reads these but doesn't typically echo them verbatim — it paraphrases.
- **`## Errors` body sections** in state files. Structured artifacts for downstream consumers; the chat-surfaced version of the same error MUST follow the plain-English rule.

### Step titles ARE user-facing

When the model executes Step 5 in a phase, it typically echoes the step title in its narration. So `5. **Load custom instructions.**` is fine; `5. **Load L4 instructions.**` is not. This is the most common leak vector — fix step titles first when auditing a skill. Section headers (`### 2.1 ...`) are the same — the model paraphrases them into narration.

### Anti-rationalization

| Rationalization | What's actually wrong |
|---|---|
| "The user can grep the architecture docs if they don't understand `T2`." | The user is in a chat session waiting for the orchestrator's narration to be self-explanatory. Forcing them to context-switch into doc archaeology to understand a progress message is the failure mode the fresh-user test exists to prevent. |
| "Spelling out `knowledge-retrieval agent` every time bloats the prose." | A 3-word phrase per occurrence is the cost of clarity. Skill body has the bandwidth; the user-facing surface is the load-bearing constraint. |
| "The skill body uses `Phase 4.3` everywhere — I'll just keep it for consistency in echoes." | Consistency with author-facing vocab IS the problem. The model echoes author-facing vocab verbatim because it sees no signal not to. Use plain English in step titles AND in any narration-template the model is likely to surface. |
| "`PRODUCT-DECISION` is a precise term; the plain-English form 'needs your decision' loses precision." | Precision in vocabulary is for author-side coordination (mapping findings to gates). The user-facing AUQ doesn't need the taxonomy label — it needs the user to act on the decision. The label is overhead at the user surface. |
| "`(Internal: L4 procedural memory layer)` parentheticals preserve the cross-reference without confusing the user." | They DO confuse the user — the model still echoes the parenthetical in narration. The rule is binary at the user surface: either it's plain English, or it's not. Cross-references for skill authors live in the architecture docs, not in step titles. |

## Examples — diverse and canonical

Per Anthropic [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): *"A set of diverse, canonical examples that effectively portray the expected behavior rather than stuffing edge cases into prompts."*

- **2-3 examples per concept**, not 8-10.
- Each example should exercise a *different* part of the rule (happy path / one common variation / one failure-mode escape hatch). Three near-identical examples teach the model one pattern; three distinct ones teach the rule.
- Don't dump every edge case. Edge cases that come up in practice get a row in the anti-rationalization table instead.
