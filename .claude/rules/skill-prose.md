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

## Explain WHY, don't shout MUST

**Explain WHY for rules the model can rationalize around** — anti-patterns, escape hatches, error semantics, anything whose cost is invisible at the call site. **State WHAT for routine procedure** — paths, syntax, slot tables, phase order. A reason bolted onto routine procedure is filler; a bare imperative on a rule the model can talk itself out of gets talked out of.

| Bare imperative that invites drift | Reframed with the reason |
|---|---|
| "NEVER skip the test run." | "Run the test suite once at end-of-phase. The Phase 3 review pre-condition assumes green tests; skipping leaves the review reading stale code." |
| "ALWAYS use atomic_state_write." | "Write state.md via `atomic_state_write` — direct `Edit`/`Write` truncates and rewrites in place, so a crash mid-write leaves a partial file." |

Caps and MUST have exactly one home: the right-hand cell of an anti-rationalization row, where the left cell is the rationalization and the right cell has to confront it bluntly. Caps in normal prose are the yellow flag.

**Phrase a rule as a requirement, not a prohibition.** Requirement-type constraints hold their compliance across a long session; prohibition-type constraints decay as context accumulates, with requirements flat over the same span ([arXiv 2604.20911](https://arxiv.org/abs/2604.20911)). A long agentic run is exactly where a prohibition is load-bearing and exactly where it fades. So "write one-line comments" beats "never write verbose comments", and any prohibition you keep pairs with what to do instead. Where the bar is a data-loss or external-effect boundary with no positive rewrite, keep the prohibition and restate it at the point of use, not only in a rules list.

## Assume a capable model

State goal + constraint, not mechanics the model derives itself: loop shapes, shell recipes, and platform quirks cost tokens, go stale, and prime one mechanism where the environment offers a better one ("Poll until the server responds or ~30 seconds elapse", not the loop shape or a `timeout` wrapper).

The **environment** is a source of truth too (`package.json` scripts, config files, the directory layout, `--help` output), and a document that restates it is a **cache**: a copy of a lookup, earning its load only when the lookup is expensive. Cache what the agent cannot find by looking: the unwritten convention, the reason behind a choice, the gotcha no config confesses; leave the one-file, one-command lookups to the environment, where they cannot go stale. Detail earns its place only where the model reliably gets it wrong without it (the explain-WHY cases) or where the value is a project contract — exact paths, schemas, thresholds, canonical option labels.

## One default + escape hatch

State the default authoritatively, then name the one case where the escape hatch applies. Never offer a menu of equivalents.

| Menu of equivalents | Default + escape hatch |
|---|---|
| "You can run tests with pytest, jest, vitest, or go test depending on the project." | "Use the test command from CLAUDE.md §'Essential Commands'." |
| "Worktree creation is optional. You can also work in the current branch, on a feature branch, or in a worktree." | "Create a worktree by default; the `no-worktree` modifier in `$ARGUMENTS` skips it." |

## Terminology consistency

One term per concept, across the whole file: `worktree` (not also `checkout` / `tree`), `spawn` (not `invoke` / `call` / `delegate`), `AUQ` after its first definition (not also `prompt` / `confirmation dialog`), `Step N.M` (not `Step 0.5` + `Sub-step 0b` + `Phase 1 §3` for one thing). Mixed synonyms fragment the model's attention across variants it has to unify.

## Leading words

When one quality gets restated at every step ("fast, deterministic, low-overhead"), collapse it into a single concept word the model already holds — a *tight loop*, a *tracer bullet*, a *frontier* — and repeat the word, not the sentence. Reach for an existing concept: a coined word recruits no priors and needs re-defining at every use.

| Quality restated per step | Leading word |
|---|---|
| "Phase 2 checks must be fast, deterministic, and low-overhead. After each fix, re-run the checks quickly; every re-run should be cheap and produce the same result." | "Phase 2 is a tight loop: cheap, deterministic checks re-run after every fix. Keep each check inside the tight loop." |

## Rule placement

**Front-load everything the model must check every turn; keep the tail for detail it can look up.** The mechanism is compaction: Claude Code re-attaches only the first ~20,000 characters of each skill after a summary (measured at that exact cutoff — `tests/authoring/lint-skills.sh`'s `REATTACH_CHARS`), and re-attached skills share a 25,000-token budget filled most-recent-first ([skills reference](https://code.claude.com/docs/en/skills)). So a skill over ~20,000 characters loses its tail for the rest of the session at the first compaction, and one invoked early in a busy session can be dropped in full — while a long, subagent-heavy run is exactly where compaction is the expected case.

The first ~20,000 characters of a SKILL.md carry `skill-structure.md` §Section ordering items 1-9 (role, phases overview, loop invariants, budgets, tool surface, contract vocabulary, anti-rationalization table); per-phase Steps, REFERENCE list, and state recovery sit below, cited by name from the invariants so the model jumps to a phase rather than scanning for it. An invariant that would land past the boundary moves into Loop invariants and gets cited by `#N` from the phase that needs it.

**When the top list alone exceeds the budget, split the file — don't ration it.** Rationing produces the worst possible outcome: every rule about how to behave survives and the work itself is lost. Build a spine that fits the re-attach budget, plus one file per phase that the skill Reads on entry to that phase.

| Spine (survives compaction) | Phase file (Read on phase entry) |
|---|---|
| Role, phase order, state machine, terminal states | The Steps of that phase |
| Loop invariants and the anti-rationalization table | Per-step detail, slot tables, output templates |
| Contract vocabulary other skills grep for (handoff field names, schema version tokens) | The procedure that produces those fields |
| A one-line "at phase N entry, Read `<skill>/phase-N-<name>.md`" | — |

Keep the `## PHASE N` heading in the spine above its pointer, so external `<skill>/SKILL.md §Phase N` citations still resolve. Prefer a phase Read over re-invoking the skill after compaction: re-invocation re-pays the whole file to recover one phase, and depends on the model noticing it should.

## Token budget awareness

**Progressive disclosure** moves reference out of the main file and behind a pointer so the top stays legible — it protects the information hierarchy more than it saves tokens. Branch test: inline what every branch needs, and push behind a pointer what only some branches reach. In-file reference that should be disclosed buries a document's steps and turns attending to them into a coin-flip: a variance lever, not just a legibility one. `agents/*.md` bodies are the exception (`skill-structure.md` §File-size limits).

**Co-location** is the within-file companion: keep a concept's definition, rules, and caveats under one heading rather than scattered, so reading one part brings its neighbours with it. The test: the document should read like documentation written for the agent. (Distinct from duplication, which repeats one meaning in two places; scattering fragments one meaning across many.)

**What degrades rule-following is rule count and applicability, not word count.** The expensive operation is adjudicating which of several similar-looking rules binds right now; an equivalent volume of inert text costs comparatively little. The failure mode is omission — the model acts as if the dropped rule was never written.

**The reduction has a ceiling, lower than it looks.** Constraint compliance falls measurably faster than knowledge retention, with the gap pronounced past roughly 60-70% reduction ([arXiv 2512.17920](https://arxiv.org/abs/2512.17920)); these files are constraint payload end to end, so compression figures measured on fact recall do not transfer. Deferral, not density, is the lever that scales.

That also disqualifies the obvious way to test a cut: "I removed it and the run still worked" is evidence about the path that ran, not about the text. A prohibition, an edge-case branch, or an ordering constraint never fails the happy path, so a pass-based removal loop strips exactly the guard prose it should keep and reports a win. Name the case the text exists for; when no such case can be named, the text may genuinely be spent.

Heuristics, in priority order:
- **Scope before you cut.** A rule that applies to one kind of task belongs behind a path scope or a conditional load, not in the always-on body — the same words stop competing.
- **Restatement summaries** (a paragraph ending "in other words, …") — drop.
- **Hedge clauses** ("may or may not", "depending on the situation") — commit to the condition or drop the line.
- **Defensive disclaimers** ("Note that this only applies if X") — fold into the rule as a single-clause conditional.

## What adding instructions buys

Rule text raises compliance on a step the model would otherwise skip. It does not raise capability on a step the model already attempts: four separate attempts to make a reviewer catch more by adding text — a prose directive, a checklist item, a required output slot, an injected context file — each moved detection by zero, while a −75% rewrite of the same criteria held detection across two task sets and two executor families (`evals/loop/experiments/`).

- **Diagnose before drafting.** A step that never runs is an instruction problem: write the rule. A step that runs and comes back shallow is a capability bound, and no wording reaches it — spend on a differently-angled second pass, or state the bound and stop.
- **A required slot proves a step ran; it does not deepen it.** Forced enumeration comes back honest, thorough, and one hop short of the defect. Add a slot to expose what a step did, never to raise how well it did it.
- **Cut boldly or not at all.** Keeping a checklist's headings while dropping its content measured worse than either the full text or a charter — mission, common false positives, severity calibration — which is the shape a criteria file compresses to without loss.

This does not license compressing constraint payload (§Token budget awareness): an enumeration of what to look for compresses to a charter, a set of rules to obey does not.

## Relevance

Check every line for **relevance**: does it still bear on what the document does? A line loses relevance by never bearing on the task (mere exposition, or a branch that should be disclosed) or by going stale as the behaviour or world it describes changes. Without a pruning discipline the default fate is **sediment**: stale layers that settle because adding feels safe and removing feels risky. Delete a stale line or procedure outright — git keeps the history, and a collapsed copy left in the file still competes for attention.

## User-facing output uses plain English

**A fresh user with the plugin installed and no architecture docs loaded must be able to act on any string the orchestrator surfaces — chat narration, todo labels, `AskUserQuestion` fields, final reports — without first learning a Geniro identifier** (`T2`, `FIX-NOW`, `phase: triage`, `m5-v2`). Read `.claude/authoring/user-facing-prose.md` before writing or editing such a string: it carries the test's two dimensions, the translation tables, the exemptions, and the anti-rationalization rows. Runtime explanations follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers (the reply-language plain layer, then a technical block).

## Examples — diverse and canonical

- **2-3 examples per concept**, not 8-10.
- Each exercises a *different* part of the rule — happy path / one common variation / one failure-mode escape hatch. Three near-identical examples teach one pattern; three distinct ones teach the rule.
- Edge cases that come up in practice get an anti-rationalization row, not another example.
