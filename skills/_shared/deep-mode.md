# Deep mode — shared contract

Canonical cross-skill contract for the opt-in `--deep` quality mode. `/geniro:review`, `/geniro:plan`, `/geniro:implement`, and `/geniro:debug` each expose `--deep`; this file owns the rules common to all four. Each consuming skill's own `deep-mode-reference.md` owns its skill-specific layers — which phases deepen, and what each pass does.

## Contents

- §1 — What deep mode is (and is not)
- §2 — Activation + state
- §3 — The two layers (recall + precision)
- §4 — Workflow mitigations (mandatory)
- §5 — Fail-safe ladder
- §6 — Boundary preservation inside the workflow
- §7 — Anti-rationalization

---

## 1. What deep mode is

Deep mode raises **quality** — recall (find more) and precision (validate more reliably) — by multiplying the agent fan-out and running it inside an internal `Workflow(...)`. It does NOT raise speed: under the Workflow concurrency cap (`min(16, cores-2)` concurrent agents per workflow), running a stage 3× fills the same waves at roughly 3-5× the token cost without shrinking wall-clock. Deep mode is opt-in for exactly this reason — it is not the default. When `deep-mode: false` (default), every phase runs its standard single-pass path and deep mode adds zero overhead.

## 2. Activation + state

- **Flag:** `--deep` in `$ARGUMENTS` (semantic parse — matches `--deep`, `deep`, `deep mode`) sets deep mode.
- **Chooser:** when `--deep` is absent, surface a depth question (Standard / Deep) as its OWN question. Where a skill already fires an AUQ before its deepened phases, fold the depth question into it rather than spend a new standalone gate: `/geniro:review` folds it into its Phase 1 Mode AUQ alongside author-tests; `/geniro:plan` folds it into the Phase 3 clarify batch; `/geniro:implement` folds it into the Step 0 workspace AUQ. `/geniro:debug` has no early always-fire AUQ (its only always-fire gate runs after the phases depth would deepen), so it fires a standalone Phase 0 depth chooser on the common path, and instead folds the depth question into the Phase 0 empty-input mode AUQ when that one fires — the one case where a dedicated gate is warranted because no host exists. On a path where the host AUQ does not fire — `/geniro:plan` on a Trivial task (Phase 3 skipped), `/geniro:implement` on an auto-continue or resume path (Step 0 AUQ skipped), `/geniro:debug` on a compaction-resume (depth already persisted) — depth falls back to flag-only there (the `--deep` flag is always available; on resume, depth was already persisted on the original run). A `--deep` flag pre-resolves depth to Deep, so the question is skipped. Keep the depth question as its own question rather than crowding one flat option list, and keep any single question within the 4-option AUQ cap.
- **State:** persist `deep-mode: <true|false>` to state.md frontmatter (and any handoff frontmatter the skill writes) per the producer fields in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md`; a missing field reads as `false`. Persist the activation to `approvals[]` with category `deep_mode_choice` so the session-start restore hook re-applies it across a compaction or resume.
- **Composition:** deep mode is an orthogonal axis — it changes HOW MANY passes run and how they aggregate, never the skill's output contract (gates, boundaries, atomic-write ownership). It composes with any other mode flag the skill exposes.

## 3. The two layers

Deep mode deepens along two independent axes; a skill may use either or both. Its `deep-mode-reference.md` says which phase uses which.

- **Recall layer** — run a generative/analytic stage N× (typically 3×) in parallel, then UNION + DEDUP the passes in-script before the skill consumes them. A single pass is non-deterministic and surfaces a subset; independent passes surface overlapping-but-different subsets whose union catches what any one missed. Dedup BEFORE any cross-pass agreement signal is computed — otherwise one producer agreeing with itself inflates that signal (each skill's reference gives its dedup key).
- **Precision layer** — give each candidate (a finding, a cited claim, an approach) 3 INDEPENDENT verifiers and aggregate by majority. Each verifier receives the same isolated input, NOT the other verifiers' outputs — independence is load-bearing. A majority of 3 tolerates one hallucinated vote, so a single false-confirm or false-refute can't flip the disposition. A verifier whose output won't parse **abstains** (counts toward neither side); if fewer than 2 parseable votes remain, quorum fails → run one fresh single-pass verifier. Never flip a disposition on abstentions.

## 4. Workflow mitigations (mandatory)

Deep mode invokes the Workflow tool from inside the skill — sanctioned because the skill body instructs it (the Workflow opt-in rule covers "a skill whose instructions tell you to call Workflow"). Every deep workflow observes these, because each one prevents a specific, observed failure:

1. **Raw JSON, not schema.** Use `agent(prompt)` returning raw JSON text and parse it defensively in-script — never `agent({schema})`. The dynamic-Workflow StructuredOutput tool-call drops roughly two-thirds of the time on long / converged agents, so a schema-typed vote silently vanishes. Parse defensively (tolerate code fences and leading prose); a parse failure is an abstention, never a refute. Surface a per-agent parse-ok tally in the workflow's return value so you know which slices to re-inspect.
2. **Re-assert the skill's boundary in every agent prompt.** Each prompt restates the spawned agent's read-only contract: no `Edit`/`Write`, no `git`/`gh` mutation, no `.geniro/` state writes — the orchestrator owns every `atomic_state_write`. The workflow parallelizes the fan-out, not the contract (§6).
3. **Path constants outside template literals.** A bare `${...}` inside a workflow backtick template literal is read as JS interpolation and crashes the script — `${CLAUDE_PLUGIN_ROOT}`, a literal bash `${var^^}`, etc. Build such strings as plain constants before the literal, or write them in plain words inside prompts.
4. **OMIT `model=` at every spawn.** Voters and passes inherit the orchestrator tier (`model: inherit`). Tier-pinning to control cost defeats the user's session `/model` choice — the cost knob is the opt-in flag, not a silent downgrade of the agents.
5. **Agent registration.** The `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` prefixed→bare→general-purpose ladder is awkward inside a single `agent({agentType})` call. Resolve by passing the session-resolved registration rung as `agentType`, or by spawning `general-purpose` with the agent body (frontmatter stripped) inlined into the prompt. If registration fails inside the workflow runtime, fail-safe to the non-workflow single-pass path (§5).

## 5. Fail-safe ladder

Standard single-pass behavior is the **floor** — deep mode is never weaker than standard. Degrade in order:

1. Workflow errors / returns an unparseable aggregate / agent registration fails → fall back to the standard single-pass path for that stage. Surface a plain-English caveat: `Deep mode couldn't run the extra passes for <stage> — fell back to a single pass.`
2. Per-candidate vote quorum fails (≥2 verifiers abstained) → one fresh single-pass verifier for that candidate.
3. A single pass within a stage fails → the stage still returns the union of the surviving passes; note the reduced count in the caveat. Never drop the stage.

Fail-safe is silent-degrade-with-a-caveat, never a hard stop. A run that went shallower than requested is still a valid run.

## 6. Boundary preservation inside the workflow

A workflow wrapper tempts the model to treat the workflow as the authority and the skill body as advisory — the skill's contract then evaporates (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md` documents this for the reporter skills; the same mechanism applies to every skill). Inside the deep workflow, all of the skill's invariants still bind, re-asserted in each step: the spawned agents stay read-only (findings / verdicts / critiques only — no `Edit`/`Write`/`git`/`gh`); the ORCHESTRATOR, not the workflow agents, owns every `atomic_state_write`; the skill's gates and approval options are unchanged; a no-ship skill still never ships. Deep mode changes pass count and aggregation, nothing else.

## 7. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Deep mode runs everything 3× in parallel, so it finishes faster." | Parallelism does not reduce wall-clock under the `min(16, cores-2)` cap — 3× the agents fill the same waves (no speedup) or spill into more (slowdown). Deep mode is a thoroughness lever, never a latency one. Sell it as quality. |
| "I'm inside a Workflow now, so the skill's no-Edit / no-ship boundary is just guidance." | The workflow parallelizes the fan-out, not the contract. Every skill invariant binds inside every workflow step (§6). The contract evaporating under the wrapper is the documented failure this prevents. |
| "Use agent({schema}) for the votes — structured output is cleaner." | The StructuredOutput tool-call drops ~⅔ of the time on long / converged agents, silently losing votes and findings. Return raw JSON text and parse defensively; a parse failure is an abstention, not a refute. |
| "Two verifiers abstained and one refuted — that's a majority to drop." | Abstentions count toward neither side. One refute out of one parseable vote is not a majority — quorum failed, so fail-safe to a single fresh single-pass verifier. Never demote on abstentions. |
| "The deep workflow errored — abort the run." | Standard single-pass is the floor. A workflow failure degrades to single-pass with a caveat, never a hard stop (§5). A shallower-than-requested run is still valid. |
| "Pin the voters to a cheaper tier to control deep mode's cost." | OMIT `model=` — voters inherit the orchestrator tier. Tier-pinning defeats the user's session `/model` choice; the cost knob is the opt-in flag itself. |
