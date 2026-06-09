---
globs: "skills/**/*.md, agents/**/*.md"
---

# Skill & agent authoring — voice, tone, and prose

Positive-guidance companion to `.claude/rules/skill-authoring.md` (negative-space) and `.claude/rules/skill-structure.md` (mechanical). This file covers how prose inside skill / agent / reference files should be written so the orchestrator model parses it efficiently and follows it reliably.

Sources for the rules below: Anthropic [`skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md), [Skill best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Liu et al. 2024 "Lost in the Middle"](https://aclanthology.org/2024.tacl-1.9/), and observed prompt-length degradation thresholds ([particula.tech](https://particula.tech/blog/optimal-prompt-length-ai-performance), [mlops.community](https://mlops.community/blog/the-impact-of-prompt-bloat-on-llm-output-quality)).

## Voice

- **Imperative form.** "Read X." / "Apply the procedure in Y." / "Spawn the agent with these slots."
  - Not "Claude should consider reading X." / "It may be useful to apply Y." / "You can spawn the agent."
- **Second-person collapses to imperative.** "You read the spec" → "Read the spec." Cuts a word, removes ambiguity about who acts.
- **No first-person plural.** No "we", "us", "our team". The skill body addresses ITS reader (a future orchestrator session); the authoring team's identity is irrelevant at runtime.
- **Third-person in descriptions** (frontmatter only). "Processes Excel files and generates reports." Anthropic's docs are explicit: inconsistent point-of-view in descriptions causes discovery problems.

## Explain WHY, don't shout MUST

Per Anthropic's `skill-creator` verbatim: *"If you find yourself writing ALWAYS or NEVER in all caps, or using super rigid structures, that's a yellow flag — if possible, reframe and explain the reasoning so that the model understands why the thing you're asking for is important."*

Reframing patterns:

| Yellow flag | Reframed |
|---|---|
| "NEVER skip the test run." | "Run the test suite once at end-of-phase. The Phase 3 review pre-condition assumes green tests; skipping leaves the review reading stale code." |
| "ALWAYS use atomic_state_write." | "Write state.md via `atomic_state_write` — direct `Edit`/`Write` calls bypass the state-helper enforcement hook and corrupt mid-crash." |
| "MUST resolve approvals before continuing." | "Resolve the AUQ before continuing — empty answers indicate an upstream tool bug and must be re-asked, not auto-defaulted." |

The reframed form costs ~10-15 tokens more per rule but the model can apply the underlying constraint to edge cases the original didn't anticipate. That's the point: instructions that explain reasoning generalize; instructions that shout don't.

**Acceptable use of caps / MUST**: anti-rationalization tables, where the left cell is the rationalization the model might generate and the right cell needs to confront it bluntly. Caps in the *right* cell of an anti-rationalization row are fine when accompanied by reasoning. Caps in *normal prose* are the yellow flag.

## State what, not why (in normal prose)

The complement to the "explain WHY" rule above: explain reasoning when the rule is non-obvious or counter-intuitive; otherwise state the action directly. Per [Claude Code skill docs](https://code.claude.com/docs/en/skills) verbatim:

> *"State what to do rather than narrating how or why, and apply the same conciseness test you would for CLAUDE.md content. Once a skill loads, its content stays in context across turns, so every line is a recurring token cost."*

Reconciliation between this rule and the previous one: explain WHY for rules the model would otherwise rationalize around (anti-patterns, escape-hatches, error semantics). State WHAT for routine procedure (file paths, command syntax, slot tables, phase ordering).

| Routine procedure → state what | Non-obvious rule → explain why |
|---|---|
| "Spawn the agent with `subagent_type: reviewer-agent`." | "Spawn the agent in parallel with the other 4 dimensions in ONE assistant response — separate turns serialize execution and double wall-time." |
| "Read `<task-dir>/.kr-out.md`." | "OMIT `model=` at every spawn site — plugin agents declare `model: inherit` and the runtime arg defeats the user's session-level `/model` choice." |
| "Set `phase: ship` on entry." | (Don't write "set phase to ship because the state machine expects ..." — the state machine is documented in §State machine; the imperative is enough.) |

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

When unsure, grep the file for the concept's synonyms and unify before commit.

## Lost-in-the-middle: rule placement

[Liu et al. 2024](https://aclanthology.org/2024.tacl-1.9/) measured U-shaped attention bias — relevant information at the beginning or end of a long context outperforms information in the middle. For a 500-line SKILL.md, the most-attended slots are the first ~100 lines and the last ~100 lines. The middle ~300 lines hold detail.

Placement rules:
- **Top third (lines 1-150 of a 500-line file):** role statement, phases overview, loop invariants, budgets, ACI tool surface. These are the rules the model checks every turn.
- **Bottom third (lines ~350-500):** anti-rationalization table, REFERENCE list, task execution entry / state recovery. These are the safety net + lookup table.
- **Middle third (lines ~150-350):** per-phase Steps with detail. Reference these by name from the invariants in the top third, so the model jumps to the relevant phase rather than scanning.

If a critical invariant lives in the middle third, the model will under-weight it. Move it to the Loop invariants section in the top third and refer to it by `#N` from the relevant phase.

## Token budget awareness

Reasoning degrades measurably past ~3,000 tokens of input ([particula.tech](https://particula.tech/blog/optimal-prompt-length-ai-performance), [mlops.community](https://mlops.community/blog/the-impact-of-prompt-bloat-on-llm-output-quality)). A target-size SKILL.md (~500 lines, the cap being a guideline not a hard limit) is ≈ 4-6K tokens — already at the degradation threshold. Reference files cost only when loaded, so move detail there aggressively.

Practical heuristics for trimming SKILL.md without losing content:
- **Inline pseudo-code** → move to reference.md, reference it by anchor.
- **Multi-paragraph explanation of a single step** → keep one paragraph; move the rest to reference.md.
- **Hedge clauses** ("this may or may not", "depending on the situation") — either commit to the condition or drop the line.
- **Restatement summaries** (paragraph ending with "in other words, ...") — drop. The reader just read the preceding paragraph.
- **Defensive disclaimers** ("Note that this only applies if X") — fold into the rule itself with a single-clause conditional.

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

## Migration audit — qualitative violations in current skills

Run a manual prose review on each skill in this order:

1. `skills/debug/SKILL.md` — highest density; likely contains caps-MUST violations and stale hedging clauses.
2. `skills/investigate/SKILL.md` — Phase 1 taxonomy section likely has menu-of-options violations.
3. `skills/refactor/SKILL.md` — Smell-detection section likely mixes terminology (`smell` / `code-smell` / `refactor target`).
4. `skills/review/SKILL.md` — dimension grid likely has terminology inconsistency between `dim` / `dimension` / `reviewer` / `dim-spec`.
5. `skills/implement/SKILL.md` — already partially audited during the recent rewrite; check Step 0 area for menu-of-options patterns.

For each, walk the file once and look for:

- `NEVER` / `ALWAYS` / `MUST` in caps outside the anti-rationalization table → reframe with reasoning.
- Menu-of-options paragraphs ("you can use X, Y, or Z") → collapse to default + escape hatch.
- Mixed terminology for one concept → grep, pick one term, replace others.
- Restatement-summary paragraphs ("in summary", "to recap", "in other words") → delete; the reader just read the preceding section.
- Critical invariants buried in the middle third → promote to Loop invariants in the top third.
- Multi-paragraph explanations of a single step → keep one paragraph, push the rest to reference.md.

Don't try to do all 5 in one pass. Tackle one skill per commit; let each pass uncover patterns that inform the next.

This audit is one-time; the prose rules above are forever. New edits self-enforce via the patterns documented in each section.
