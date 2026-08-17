# Deep mode — shared contract

Canonical cross-skill contract for the opt-in `--deep` quality mode. `/geniro:review`, `/geniro:plan`, `/geniro:implement`, and `/geniro:debug` each expose `--deep`; this file owns the rules common to all four. Each consuming skill's own `deep-mode-reference.md` owns its skill-specific layers — which phases deepen, and what each pass does.

## Contents

- §1 — What deep mode is (and is not)
- §2 — Activation + state
- §3 — The two layers (recall + precision) + the canonical script skeletons
- §4 — Workflow mitigations (mandatory)
- §5 — Fail-safe ladder
- §6 — Boundary preservation inside the workflow
- §7 — Anti-rationalization

---

## 1. What deep mode is

Deep mode raises **quality** — recall (find more) and precision (validate more reliably) — by multiplying the agent fan-out and running it inside an internal `Workflow(...)`. It does NOT raise speed: under the Workflow concurrency cap (`min(16, cores-2)` concurrent agents per workflow), running a stage 3× fills the same waves at roughly 3-5× the token cost without shrinking wall-clock. Deep mode is opt-in for exactly this reason — it is not the default. When `deep-mode: false` (default), every phase runs its standard single-pass path and deep mode adds zero overhead.

## 2. Activation + state

- **Flag:** `--deep` in `$ARGUMENTS` (semantic parse — matches `--deep`, `deep`, `deep mode`) sets deep mode.
- **Chooser:** when `--deep` is absent, surface a depth question (Standard / Deep) as its OWN question. Where a skill already fires an AUQ before its deepened phases, fold the depth question into it rather than spend a new standalone gate: `/geniro:review`'s Phase 1 Mode AUQ *is* the depth question; `/geniro:plan` asks it once at its Phase 3 grill wrap-up (no new standalone gate); `/geniro:implement` folds it into the Step 0 workspace AUQ. `/geniro:debug` has no early always-fire AUQ (its only always-fire gate runs after the phases depth would deepen), so it fires a standalone Phase 0 depth chooser on the common path, and instead folds the depth question into the Phase 0 empty-input mode AUQ when that one fires — the one case where a dedicated gate is warranted because no host exists. On a path where the host AUQ does not fire — `/geniro:plan` on a Trivial task (Phase 3 skipped), `/geniro:implement` on an auto-continue or resume path (Step 0 AUQ skipped), `/geniro:debug` on a compaction-resume (depth already persisted) — depth falls back to flag-only there (the `--deep` flag is always available; on resume, depth was already persisted on the original run). A `--deep` flag pre-resolves depth to Deep, so the question is skipped. Keep the depth question as its own question rather than crowding one flat option list, and keep any single question within the 4-option AUQ cap.
- **State:** persist `deep-mode: <true|false>` to state.md frontmatter (and any handoff frontmatter the skill writes) per the producer fields in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`; a missing field reads as `false`. Persist the activation to `approvals[]` with category `deep_mode_choice` so the session-start restore hook re-applies it across a compaction or resume.
- **Composition:** deep mode is an orthogonal axis — it changes HOW MANY passes run and how they aggregate, never the skill's output contract (gates, boundaries, atomic-write ownership). It composes with any other mode flag the skill exposes.

## 3. The two layers

Deep mode deepens along two independent axes; a skill may use either or both. Its `deep-mode-reference.md` says which phase uses which, and whether it adopts the efficiency refinements below.

- **Recall layer** — run a generative/analytic stage N× (typically 3×) in parallel, then UNION + DEDUP the passes in-script before the skill consumes them. **Prefer diverse decomposition over identical repetition:** point each pass at a DISTINCT region of the stage's space — distinct lenses (as `/geniro:plan`'s approach panel does), or distinct angles (common-path / boundaries-and-error-paths / interaction-with-surrounding-code) — rather than re-running one identical prompt N×. Identical passes harvest only the temperature tail of one distribution: high overlap, low marginal recall per pass, heavy dedup churn. Distinct passes search where the others do not, so each pass buys new territory at the same token cost. A single pass is non-deterministic and surfaces a subset; independent passes surface overlapping-but-different subsets whose union catches what any one missed. Dedup BEFORE any cross-pass agreement signal is computed — otherwise one producer agreeing with itself inflates that signal (each skill's reference gives its dedup key); with diverse passes, agreement ACROSS angles is a stronger reliability signal than identical clones agreeing.
- **Precision layer** — validate each candidate (a finding, a cited claim, an approach) with INDEPENDENT verifiers aggregated by majority. Each verifier receives the same isolated input, NOT the other verifiers' outputs — independence is load-bearing. A majority of 3 tolerates one hallucinated vote, so a single false-confirm or false-refute can't flip the disposition. A verifier whose output won't parse **abstains** (counts toward neither side); if fewer than 2 parseable votes remain, quorum fails → run one fresh single-pass verifier. Never flip a disposition on abstentions. **Signal-gate the vote count where the skill has corroborating signal** (its reference says whether it does): run ONE verifier first and accept its single verdict when it is high-confidence AND agrees with the upstream signal that already corroborates the candidate (a confirm of a candidate several independent producers converged on, or a refute of a lone low-stakes candidate); escalate to the full 3 independent verifiers only when the disposition is contested or expensive — the first vote is low-confidence, CONTRADICTS the upstream signal, or would drop a high-stakes candidate. One vote never drops a high-stakes candidate. This keeps the majority's hallucination-tolerance exactly where a flipped disposition is costly while spending the extra votes only on the genuinely-contested minority (`N + 2·contested·N` votes instead of `3N`). The majority-aggregation rules above apply whenever 3 votes run.

### Script skeletons

Both skeletons below are canonical for every skill's deep `Workflow(...)`. A consuming `deep-mode-reference.md` supplies its own stage set, angle or lens names, dedup key, and escalation predicate, and cites this section instead of re-inlining the script. Apply every §4 mitigation at both fan-outs.

**Recall — N angle-scoped passes per stage, unioned and deduped in-script:**

```
phase('Deep pass — angle-diverse')
const ANGLES = ['common-path', 'boundaries-and-errors', 'interaction']   // 3 distinct, stage-agnostic angles
const perStage = await pipeline(
  STAGES,                                                  // the skill's declared stage set (dimensions, lenses, ...)
  s => parallel(ANGLES.map(angle => () =>
    agent(passPrompt(s, angle, ctx), { label: `${s.slug}:${angle}`, phase: 'Deep pass — angle-diverse' }))),
  (anglePasses, s) => dedupeWithinStage(anglePasses, s)     // union + dedup IN-SCRIPT → one per-stage set (seen-in: N/3)
)
return perStage                                            // raw JSON text from agents, parsed in-script
```

The in-script dedup is load-bearing, not an optimization: it runs BEFORE any cross-stage agreement signal is computed, so one stage's repeated passes can never inflate that signal (§3 recall layer). Record the within-stage tally (`seen-in: N/3`) as a distinct, weaker signal than cross-stage agreement.

**Precision — first vote, then escalate only where the call is contested:**

```
phase('Deep verify — signal-gated')
const verified = await parallel(candidates.map(c => () => (async () => {
  const first = parseVote(await agent(verifierPrompt(c, 0), { label: `verify:${c.id}:v0`, phase: 'Deep verify — signal-gated' }))
  if (!needsEscalation(first, c)) return { ...c, verdict: first }        // high-confidence + agrees with upstream signal → accept 1 vote
  const rest = await parallel([1,2].map(i => () =>                       // contested / high-stakes → full 3-vote majority
    agent(verifierPrompt(c, i), { label: `verify:${c.id}:v${i}`, phase: 'Deep verify — signal-gated' })))
  return { ...c, verdict: majority([first, ...rest]) }                   // majority() parses defensively; parse-fail = abstain
})()))
return verified.filter(v => v.verdict !== 'refuted')                     // survivors continue down the skill's own path
```

`needsEscalation(first, candidate)` is the one skill-specific piece — each consuming reference cites this clause rather than restating it, adding only its own contested/high-stakes clauses. Every predicate carries these two clauses at minimum: the first vote abstained (parse failure), or its `confidence <= 3`. `confidence` is the 1-5 coarse scale its owner defines (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §3: 1 = "low — could be wrong", 5 = "certain — direct evidence") — only a 4 or 5 is trusted alone; 1-3 still needs the majority's tolerance for one bad vote. The remaining clauses express what that skill treats as contested or high-stakes, per the §3 precision layer.

## 4. Workflow mitigations (mandatory)

Deep mode invokes the Workflow tool from inside the skill — sanctioned because the skill body instructs it (the Workflow opt-in rule covers "a skill whose instructions tell you to call Workflow"). Every deep workflow observes these, because each one prevents a specific, observed failure:

1. **Raw JSON, not schema.** Use `agent(prompt)` returning raw JSON text and parse it defensively in-script — never `agent({schema})`. The dynamic-Workflow StructuredOutput tool-call drops roughly two-thirds of the time on long / converged agents, so a schema-typed vote silently vanishes. Parse defensively (tolerate code fences and leading prose); a parse failure is an abstention, never a refute. Surface a per-agent parse-ok tally in the workflow's return value so you know which slices to re-inspect.
2. **Re-assert the skill's boundary in every agent prompt.** Each prompt restates the spawned agent's read-only contract: no `Edit`/`Write`, no `git`/`gh` mutation, no `.geniro/` state writes — the orchestrator owns every `atomic_state_write`. The workflow parallelizes the fan-out, not the contract (§6).
3. **Path constants outside template literals.** A bare `${...}` inside a workflow backtick template literal is read as JS interpolation and crashes the script — `${CLAUDE_PLUGIN_ROOT}`, a literal bash `${var^^}`, etc. Build such strings as plain constants before the literal, or write them in plain words inside prompts.
4. **OMIT `model=` at every spawn by default** — voters and passes inherit the orchestrator tier; deep mode's cost knob is the opt-in flag itself, not a cheaper tier for the agents. Pass `model="<tier>"` at every spawn instead when the calling skill's run carries `--subagent-model` — the user's own election for the run, not the cheaper-tier shortcut this mitigation guards against (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §`--subagent-model`).
5. **Agent registration.** The `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` prefixed→bare→general-purpose ladder is awkward inside a single `agent({agentType})` call. Resolve by passing the session-resolved registration rung as `agentType`, or by spawning `general-purpose` with the agent body (frontmatter stripped) inlined into the prompt. If registration fails inside the workflow runtime, fail-safe to the non-workflow single-pass path (§5).
6. **No `run_in_background` on the Workflow call.** The Workflow tool has no `run_in_background` parameter — workflows always run in the background. That parameter belongs to `Bash`/`Agent`; passing it to the Workflow call fails with a schema error and the deep stage never starts. Omit it.

## 5. Fail-safe ladder

Standard single-pass behavior is the **floor** — deep mode is never weaker than standard. Degrade in order:

1. Workflow errors / returns an unparseable aggregate / agent registration fails → fall back to the standard single-pass path for that stage. Surface a plain-English caveat: `Deep mode couldn't run the extra passes for <stage> — fell back to a single pass.`
2. Per-candidate vote quorum fails (≥2 verifiers abstained) → one fresh single-pass verifier for that candidate.
3. A single pass within a stage fails → the stage still returns the union of the surviving passes; note the reduced count in the caveat. Never drop the stage.

Fail-safe is silent-degrade-with-a-caveat, never a hard stop. A run that went shallower than requested is still a valid run.

## 6. Boundary preservation inside the workflow

A workflow is an execution wrapper, not a contract override — why that binds, and the failure mode it prevents, is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` §"Why this binds" (written for the reporter skills; the same mechanism applies to every skill). Inside the deep workflow all of the skill's invariants still bind, re-asserted in each step (§4 item 2): the spawned agents stay read-only (findings / verdicts / critiques only — no `Edit`/`Write`/`git`/`gh`); the ORCHESTRATOR, not the workflow agents, owns every `atomic_state_write`; the skill's gates and approval options are unchanged; a no-ship skill still never ships. Deep mode changes pass count and aggregation, nothing else.

## 7. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Deep mode runs everything 3× in parallel, so it finishes faster." | It buys quality, never latency — §1 has the concurrency-cap arithmetic. Sell it to the user as thoroughness. |
| "I'm inside a Workflow now, so the skill's no-Edit / no-ship boundary is just guidance." | The workflow parallelizes the fan-out, not the contract. Every skill invariant binds inside every workflow step (§6). The contract evaporating under the wrapper is the documented failure this prevents. |
| "Two verifiers abstained and one refuted — that's a majority to drop." | Abstentions count toward neither side. One refute out of one parseable vote is not a majority — quorum failed, so fail-safe to a single fresh single-pass verifier. Never demote on abstentions. |
| "The deep workflow errored — abort the run." | Standard single-pass is the floor. A workflow failure degrades to single-pass with a caveat, never a hard stop (§5). A shallower-than-requested run is still valid. |
| "Run one verifier on every candidate to save tokens — the upstream signal already vetted them." | The single-vote path is gated, not blanket: a low-confidence first vote, a verdict that contradicts the upstream signal, or any refute that would drop a high-stakes candidate MUST escalate to the full 3 (§3). Blanket single-vote re-introduces the single-hallucination flip the majority exists to prevent. |
| "The lone verifier refuted the high-stakes candidate with confidence — drop it, one clean vote." | One vote never drops a high-stakes candidate. A first-vote refute of a CRITICAL/HIGH candidate, or of one several producers converged on, is precisely the contested case that escalates to 3. A single hallucinated refute dropping a real defect is the failure this gate prevents. |
