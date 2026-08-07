---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
  - ".claude/skills/**/*.md"
---

# Skill & agent authoring — voice, tone, and prose

How prose inside a skill / agent / reference file is written so the orchestrator parses it efficiently and follows it reliably. Companions: `.claude/rules/skill-authoring.md` (what never ships), `.claude/rules/skill-structure.md` (mechanical structure).

## Voice

- **Imperative.** "Read X." — not "Claude should consider reading X."
- **Second person collapses to imperative.** "You read the spec" → "Read the spec."
- **No first-person plural.** The body addresses its reader, a future orchestrator session; the authoring team is not present at runtime.
- **Third person in frontmatter descriptions.** "Processes Excel files and generates reports." Mixed point-of-view in a description degrades skill discovery.

## Explain WHY, don't shout MUST

**Explain WHY for rules the model can rationalize around** — anti-patterns, escape hatches, error semantics, anything whose cost is invisible at the call site. **State WHAT for routine procedure** — paths, syntax, slot tables, phase order. A reason bolted onto routine procedure is filler; a bare imperative on a rule the model can talk itself out of gets talked out of.

| Bare imperative that invites drift | Reframed with the reason |
|---|---|
| "NEVER skip the test run." | "Run the test suite once at end-of-phase. The Phase 3 review pre-condition assumes green tests; skipping leaves the review reading stale code." |
| "ALWAYS use atomic_state_write." | "Write state.md via `atomic_state_write` — direct `Edit`/`Write` bypasses the state-helper enforcement hook and corrupts mid-crash." |
| "Spawn the reviewers in parallel." | "Spawn every reviewer dimension in ONE assistant response — separate turns serialize execution and double wall-time." |

Routine procedure needs none of it: "Read `<task-dir>/.kr-out.md`." / "Set `phase: ship` on entry."

Caps and MUST have exactly one home: the right-hand cell of an anti-rationalization row, where the left cell is the rationalization and the right cell has to confront it bluntly. Caps in normal prose are the yellow flag.

**Phrase a rule as a requirement, not a prohibition.** Requirement-type constraints hold their compliance across a long session; prohibition-type constraints decay as context accumulates, with requirements flat over the same span ([arXiv 2604.20911](https://arxiv.org/abs/2604.20911)). A long agentic run is exactly where a prohibition is load-bearing and exactly where it fades. So "write one-line comments" beats "never write verbose comments", and any prohibition you keep pairs with what to do instead. Where the bar is a data-loss or external-effect boundary with no positive rewrite, keep the prohibition and restate it at the point of use, not only in a rules list.

## Assume a capable model

Write at the altitude of goal + constraint, not mechanics. The model already knows standard tooling, shell idioms, and platform quirks — spelling those out costs tokens, goes stale, and primes the model toward one mechanism when a better one exists in the environment it is actually running in.

- "Poll until the server responds or ~30 seconds elapse" — not the loop shape, the sleep interval, or a `timeout` wrapper.
- "Bound the fetch so an offline remote can't hang the run" — not a snippet probing `timeout` vs `gtimeout`.

Detail earns its place only where the model reliably gets it wrong without it (the explain-WHY cases) or where the value is a project contract — exact paths, schemas, thresholds, canonical option labels. Litmus: would a competent engineer joining the project need this sentence, or just the goal?

## One default + escape hatch

State the default authoritatively, then name the one case where the escape hatch applies. Never offer a menu of equivalents.

| Menu of equivalents | Default + escape hatch |
|---|---|
| "You can run tests with pytest, jest, vitest, or go test depending on the project." | "Use the test command from CLAUDE.md §'Essential Commands'." |
| "Reviewers may spawn at haiku, sonnet, or opus tier." | "Reviewers inherit the orchestrator's tier (OMIT `model=`). Custom reviewers declare their own tier in `.geniro/instructions/review-extra/<slug>.md` frontmatter — honor that." |
| "Worktree creation is optional. You can also work in the current branch, on a feature branch, or in a worktree." | "Create a worktree by default; the `no-worktree` modifier in `$ARGUMENTS` skips it." |

## Terminology consistency

One term per concept, across the whole file. Mixed synonyms fragment the model's attention across variants it has to unify.

| Concept | Pick one | Don't mix |
|---|---|---|
| Git working tree | `worktree` | `worktree` + `checkout` + `tree` + `clone-of-the-repo` |
| Plugin shared helper | `helper` | `helper` + `utility` + `lib script` + `tool` |
| User-approval prompt | `AUQ` (after first definition) | `AUQ` + `prompt` + `confirmation dialog` |
| Subagent spawn | `spawn` | `spawn` + `invoke` + `call` + `delegate` |
| Sub-step | `Step N.M` | `Step 0.5` + `Sub-step 0b` + `Phase 1 §3` for the same thing |

## Leading words

When one quality gets restated at every step ("fast, deterministic, low-overhead"), collapse it into a single concept word the model already holds — a *tight loop*, a *tracer bullet*, a *frontier* — and repeat the word, not the sentence. Reach for an existing concept: a coined word recruits no priors and needs re-defining at every use.

| Quality restated per step | Leading word |
|---|---|
| "Phase 2 checks must be fast, deterministic, and low-overhead. After each fix, re-run the checks quickly; every re-run should be cheap and produce the same result." | "Phase 2 is a tight loop: cheap, deterministic checks re-run after every fix. Keep each check inside the tight loop." |

## Rule placement

**Front-load everything the model must check every turn; keep the tail for detail it can look up.** The mechanism is compaction: Claude Code re-attaches only the first 5,000 tokens of each skill after a summary, and re-attached skills share a 25,000-token budget filled most-recent-first ([skills reference](https://code.claude.com/docs/en/skills)). So a skill over ~5,000 tokens loses its tail for the rest of the session at the first compaction, and one invoked early in a busy session can be dropped in full — while a long, subagent-heavy run is exactly where compaction is the expected case.

Placement for a SKILL.md:
- **Top (first ~5,000 tokens):** role statement, phases overview, loop invariants, budgets, tool surface, cross-skill contract vocabulary, anti-rationalization table.
- **Below:** per-phase Steps with detail, REFERENCE list, state recovery. Cite them by name from the invariants so the model jumps to a phase rather than scanning for it.

An invariant that would land past the boundary moves into Loop invariants and gets cited by `#N` from the phase that needs it.

**When the top list alone exceeds the budget, split the file — don't ration it.** Rationing produces the worst possible outcome: every rule about how to behave survives and the work itself is lost. Build a spine that fits the re-attach budget, plus one file per phase that the skill Reads on entry to that phase.

| Spine (survives compaction) | Phase file (Read on phase entry) |
|---|---|
| Role, phase order, state machine, terminal states | The Steps of that phase |
| Loop invariants and the anti-rationalization table | Per-step detail, slot tables, output templates |
| Contract vocabulary other skills grep for (handoff field names, schema version tokens) | The procedure that produces those fields |
| A one-line "at phase N entry, Read `<skill>/phase-N-<name>.md`" | — |

Keep the `## PHASE N` heading in the spine above its pointer, so external `<skill>/SKILL.md §Phase N` citations still resolve. Prefer a phase Read over re-invoking the skill after compaction: re-invocation re-pays the whole file to recover one phase, and depends on the model noticing it should.

## Token budget awareness

**A reference file's cost is its size times its load frequency.** Before moving detail into a reference, name the runs that will not load it; if the honest answer is "none", the move adds a round-trip and saves nothing. The same test kills the move into an `agents/*.md` body, which is injected whole as the subagent's system prompt — relocating a rule there converts free prompt tokens into the same tokens plus a Read the agent may skip.

**What degrades rule-following is rule count and applicability, not word count.** The expensive operation is adjudicating which of several similar-looking rules binds right now; an equivalent volume of inert text costs comparatively little. The failure mode is omission — the model acts as if the dropped rule was never written. So partition before you delete: path-scope a rule set so it loads only for the work it governs, and the same words stop competing.

**The reduction has a ceiling, lower than it looks.** Constraint compliance falls measurably faster than knowledge retention, with the gap pronounced past roughly 60-70% reduction ([arXiv 2512.17920](https://arxiv.org/abs/2512.17920)); these files are constraint payload end to end, so compression figures measured on fact recall do not transfer. Deferral, not density, is the lever that scales.

That also disqualifies the obvious way to test a cut: "I removed it and the run still worked" is evidence about the path that ran, not about the text. A prohibition, an edge-case branch, or an ordering constraint never fails the happy path, so a pass-based removal loop strips exactly the guard prose it should keep and reports a win. Name the case the text exists for; when no such case can be named, the text may genuinely be spent.

Heuristics, in priority order:
- **Scope before you cut.** A rule that applies to one kind of task belongs behind a path scope or a conditional load, not in the always-on body.
- **Restatement summaries** (a paragraph ending "in other words, …") — drop.
- **Hedge clauses** ("may or may not", "depending on the situation") — commit to the condition or drop the line.
- **Defensive disclaimers** ("Note that this only applies if X") — fold into the rule as a single-clause conditional.
- **Inline pseudo-code and multi-paragraph step explanations** → move to a reference file, once you have named the runs that skip it.

Reference files carry no budget pressure until loaded — be generous there. SKILL.md stays lean.

## Time-sensitive content

Wrap a deprecated procedure in collapsible HTML rather than inlining it — still greppable, no longer competing with the current procedure for attention.

```markdown
<details>
<summary>Legacy v1 API (deprecated 2025-08; removed next major version)</summary>

[old procedure]

</details>
```

## User-facing output uses plain English

### The fresh-user test

**A fresh user with the plugin installed but no architecture docs loaded — no `CLAUDE.md`, no `state-tier-spec.md` — must be able to act on the string without first learning a Geniro-specific identifier.** If understanding it requires knowing `T2` / `FIX-NOW` / `phase: triage` / `m5-v2` / `KR`, restate the identifier's meaning inline or drop it for the plain-English form.

Both dimensions must pass:

- **No untranslated identifiers.** `T2` / `FIX-NOW` / `phase: triage` restated inline or dropped.
- **No assumed hidden context.** The string explains the situation it is about. A review gate asking *"How should we handle the implicit entity-default @Filter at the 3 call sites?"* fails even though every word is plain English — the user was never shown what that code does, why it is a concern, or what the options mean. For decisions carrying finding or investigation context, render the self-contained explanation to a chat message first, then fire a lean question, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering.

Applies to everything the orchestrator surfaces: chat narration, `TodoWrite` labels, `AskUserQuestion` `header` / `question` / `description` / option `label` / `preview`, status echoes, final report sections, and errors surfaced to chat (not the state-file `## Errors` body section — that is a structured artifact for downstream consumers).

### Translation tables

Extend when new internal vocabulary appears.

| Family | Internal term | Plain-English form for user-facing prose |
|---|---|---|
| Memory layer | `L1` / working memory | "task state" / "session state" |
| | `L2` / episodic memory / learnings | "past learnings" / "prior knowledge" |
| | `L3` / semantic memory / snapshot | "project snapshot" / "codebase map" |
| | `L4` / procedural memory / instructions | "custom instructions" / "project rules" |
| State tier | `T1` / ephemeral state | "scratch files" / "transient working files" |
| | `T1.5` / durable task state | "task artifacts" |
| | `T2` / handoff | "handoff" (drop the `T2` — the word carries the semantic) |
| | `T3` / persistent state | "persistent state" (drop `T3`) |
| Subagent | `KR` / `KR output` | "knowledge-retrieval agent" / "knowledge-retrieval output" |
| | `CE` / `CE output` | "codebase-explorer agent" / "codebase-explorer output" |
| | `TR` / `TR output` | "test-runner agent" / "test-runner output" |
| Decision type (reviewer-internal) | `FIX-NOW` | "automatic fix" / "I can fix this directly" |
| | `TESTABLE` | "this can be verified with a test" |
| | `PRODUCT-DECISION` | "needs your decision" / "judgment call required" |
| | `INTENT-CHECK` | "needs you to confirm intent" |
| Cause type (debug-internal) | `ROOT-CAUSE` | "root cause" |
| | `SYMPTOM` | "surface symptom" / "downstream effect" |
| | `UNKNOWN` | "cause not yet identified" |
| Frontmatter field | `approvals[]` | "decisions you've made in this run" / "saved choices" |
| | `non-resumable-actions[]` | "external actions that can't be undone (push, PR open)" |
| | `workflow_refs[]` | "linked tracker tickets" |
| | `open_questions[]` | "open questions from the prior review/debug" |
| | `related_findings[]` | "findings this question gates" |

**Everything else** — phase / step labels (`Phase 4.3`, `Step 0b`), state-machine enum values (`phase: analyze`), reviewer dimension slugs (`spec-compliance`), schema versions (`m5-v2`), helper / hook names (`load_semantic`, `PreToolUse`). Narrate what is happening or what a helper did, never the identifier: "Analyzing the change scope", not "Now in `phase: analyze`"; "Couldn't refresh the project snapshot", not "load_semantic returned rc=11". Surface a schema version only when the user must act on the difference, and then describe the action ("this spec uses the older format and needs re-authoring"), not the version. Cross-reference a step by its concept ("the open-question gate"), not its number.

### What's exempt

The rule governs narrative prose surfaced to the user. It does not govern:

- **Filesystem paths** (`.kr-out.md`, `_CODEBASE_MAP.md`) — their prefixes and extensions carry the semantics. Keep them.
- **YAML / JSON keys inside code blocks** rendered to the user.
- **Architectural sections documenting the layer / tier / subagent system itself** — `CLAUDE.md` §Memory Layers, `skills/_shared/state-tier-spec.md`. Those address authors.
- **Skill body declarative prose** referencing architecture for authors — the orchestrator paraphrases rather than echoes it.
- **`## Errors` body sections** in state files. The chat-surfaced version of the same error still follows the rule.

### Step titles ARE user-facing

The model echoes a step title when it executes the step. `5. **Load custom instructions.**` is fine; `5. **Load L4 instructions.**` is not. This is the most common leak vector — fix step titles first when auditing a skill. Section headers behave the same way: the model paraphrases them into narration.

### Anti-rationalization

| Rationalization | What's actually wrong |
|---|---|
| "The user can grep the architecture docs if they don't understand `T2`." | Forcing a context-switch into doc archaeology to read a progress message is the failure this test prevents. |
| "Spelling out `knowledge-retrieval agent` every time bloats the prose." | Three words per occurrence is the cost of clarity. The body has the bandwidth; the user-facing surface is the load-bearing constraint. |
| "The skill body uses `Phase 4.3` everywhere — I'll keep it for consistency in echoes." | Consistency with author-facing vocabulary IS the problem: the model echoes it verbatim because it sees no signal not to. |
| "`PRODUCT-DECISION` is precise; 'needs your decision' loses precision." | That precision serves author-side coordination, mapping findings to gates. The user needs to act on the decision, not learn the taxonomy. |
| "`(Internal: L4 procedural memory layer)` preserves the cross-reference without confusing the user." | The model echoes the parenthetical too. The rule is binary at the user surface; author cross-references live in the architecture docs. |

## Examples — diverse and canonical

- **2-3 examples per concept**, not 8-10.
- Each exercises a *different* part of the rule — happy path / one common variation / one failure-mode escape hatch. Three near-identical examples teach one pattern; three distinct ones teach the rule.
- Edge cases that come up in practice get an anti-rationalization row, not another example.
