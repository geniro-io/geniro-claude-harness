# Debug deep mode — reference

Debug-specific layers of the opt-in `--deep` quality mode. The cross-skill contract — activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, and the shared anti-rationalization — lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`; read it first. This file covers only what `/geniro:debug` deepens.

`--deep` raises the quality of debug's INVESTIGATION: more candidate hypotheses (recall) and more reliable fix→test verification (precision). It does not change debug's phases, gates, the no-ship boundary, or the handoff contract.

## Contents

- §1 — Activation
- §2 — Recall: Phase 1.4 hypothesis fan-out
- §3 — Precision: Phase 2.4 fix/reproduction verification (3-vote)
- §4 — Fail-safe + boundary
- §5 — Anti-rationalization

---

## 1. Activation

`/geniro:debug --deep <bug>` sets `deep-mode: true`. Semantic parse at Phase 0 Step 0.2 — matches `--deep` / `deep` / `deep mode` — strip the token before mode-detect routing so it never enters the Scientific-vs-Adversarial decision. Deep mode composes with the mode switch: Scientific+Deep and Adversarial+Deep are both valid.

**The HYBRID chooser** fires only when `--deep` is absent:

- **`--deep` present** → deep-mode true; skip the chooser entirely.
- **Compaction-resume** → skip the chooser; depth was persisted on the original run and the session-start restore hook re-applies it.
- **Empty `$ARGUMENTS`** (the Phase 0 mode AskUserQuestion fires) → add the "Debug depth" question as a SECOND question in that same AskUserQuestion call, answered together with the mode pick.
- **Otherwise** (the common path — non-empty input, no `--deep`) → fire a STANDALONE "Debug depth" chooser at Phase 0, before the Phase 1.1 memory load.

**The "Debug depth" question** (mirrors `/geniro:review` §11 — no `(Recommended)` marker; depth is a per-run cost-vs-thoroughness pick where the alternative is only costlier, never safer):

- **Header:** "Debug depth"
- **Question:** "How deep should the investigation go?"
- **Options:**
  - "Standard" — "Single-pass hypothesis generation, and one verification that the fix resolves the reproduction test."
  - "Deep — wider hypotheses + 3-vote verify" — "3× independent hypothesis generation (union + dedup) plus a 3-vote majority verification that the fix turns the reproduction test red→green; higher quality at higher token cost."

An empty answer defaults to Standard (`deep-mode: false`).

**Persistence.** At the Phase 0 frontmatter initialization (the earliest `atomic_state_write`), write `deep-mode: <true|false>` to state.md frontmatter and append `{category: deep_mode_choice, picked: <deep|standard>, at: <ISO-8601 UTC>}` to `approvals[]`. A missing `deep-mode` field reads as false. The session-start restore re-applies the saved choice from `approvals[]` on resume — which is why the resume path skips the chooser. When false (default), Phase 1.4 and Phase 2.4 run their standard single-pass paths and deep mode adds zero overhead.

## 2. Recall — Phase 1.4 hypothesis fan-out

Standard Phase 1.4 synthesizes the Observation + Feedback Loop output into 2-3 competing hypotheses in one inline pass — the same context that later tests them, so the candidate set reflects one author's first instinct. Deep mode replaces that single synthesis with a 3× fan-out inside an internal `Workflow(...)`:

- **Generate** — spawn 3 independent hypothesis generators in parallel, each receiving the same Observation + Feedback Loop context (and the §1.1 past-learnings primer, including any surfaced `discarded_hypothesis` dead-ends). Each generator returns 2-3 hypotheses with mechanism + targeted file/module.
- **Union + dedup** — union the candidates, then drop near-identical ones in-script. **Dedup key = hypothesis mechanism + targeted file/module** — two hypotheses naming the same mechanism against the same module collapse to one. Dedup runs BEFORE the §1.5 test loop consumes the set, so a duplicated hypothesis never consumes a test slot twice and three generators agreeing with themselves never inflates a confidence signal.
- **Feed the standard test loop** — the deduped candidate set enters the unchanged §1.5 test loop. **Testing stays orchestrator-inline** — it captures real evidence artifacts per the Evidence Standard (file:line snippet, captured command output, log line, query result, user-provided artifact), and recall multiplies GENERATION, not testing. The missing-data gate, the per-rejection `discarded_hypothesis` L2 emit, and the Evidence-Standard `Result:` requirement all apply unchanged.

**Why 3× raises recall:** a single synthesis pass is non-deterministic and surfaces a subset of the plausible hypotheses; three independent passes surface overlapping-but-different subsets whose union catches a root-cause angle any one pass missed.

## 3. Precision — Phase 2.4 fix/reproduction verification (3-vote)

Standard Phase 2.4 judges "does the monkey-patched fix turn the F→P test red→green" with a single orchestrator-inline read of the re-run output. Deep mode gives that judgment **3 INDEPENDENT verifiers** and aggregates by majority:

- Each verifier independently answers two questions against the fix proposal + the authored F→P test: (1) does the monkey-patched fix genuinely turn the reproduction test red→green, and (2) is the test a STRONG regression guard — does it assert the bug's observable behavior rather than a weak proxy that would pass even with the bug present? Each verifier receives the same isolated input (fix proposal, test source, pre/post-fix run output), NOT the other verifiers' outputs — independence is load-bearing.
- **Majority of 3** tolerates one bad vote. A verifier whose output won't parse **abstains** (counts toward neither side; parse defensively — a parse failure is never a refute). Quorum < 2 parseable votes → run one fresh single-pass verifier for that judgment (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §5).
- A majority "fix does not resolve / test too weak" verdict routes back into the standard §2.5 fix-loop (fix-fail counter increments as usual); a majority "resolved + strong guard" verdict advances to Phase 3 exactly as the standard single-pass judgment would.

**This precision layer is NATIVE to debug.** Plan and implement delegate their precision layer to the shared spec-challenge helper, but that helper's `MODE` enum is `plan | implement` only — debug has no spec.md to fact-check and no spec-challenge entry. So debug's precision layer is built directly against the fix proposal + F→P test inside this skill, not delegated.

**The `adversarial-tester-agent` stays a SINGLE spawn even in deep mode.** It already hunts edge cases exhaustively and AUTHORS tests; tripling test authoring triples authored-test churn for little recall gain. Deep mode multiplies hypothesis generation and the fix-verification votes, and keeps the adversarial-tester a single spawn.

## 4. Fail-safe + boundary

**Fail-safe.** Standard single-pass is the floor (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §5):

- Phase 1.4 fan-out workflow fails → fall back to the single inline 2-3 hypothesis synthesis.
- Phase 2.4 verifier workflow fails → fall back to the single-pass monkey-patch verify.
- Per-judgment quorum fails (≥2 verifiers abstained) → one fresh single-pass verifier.

Each degrades with a plain-English caveat (`Deep mode couldn't run the extra passes for <stage> — fell back to a single pass.`), never a hard stop. A shallower-than-requested investigation is still a valid investigation.

**Boundary.** Apply the 5 Workflow mitigations from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §4 at every spawn: return raw JSON text and parse defensively (never `agent({schema})`); re-assert the read-only boundary in every agent prompt; build path/context strings as plain constants OUTSIDE backtick template literals (a bare `${CLAUDE_PLUGIN_ROOT}` inside a literal is read as JS interpolation and crashes the script); OMIT `model=` so passes inherit the orchestrator tier; resolve the `adversarial-tester-agent` registration via the session-resolved rung (prefixed → bare → general-purpose with body inlined).

Every workflow agent prompt re-asserts debug's read-only contract: no `Edit`/`Write`, no `git`/`gh`, no `.geniro/` state writes. The spawned passes return hypotheses and verdicts ONLY. The ORCHESTRATOR owns every `atomic_state_write`, the fix-proposal write (text only — never applied to production source), and the reproduction-test authoring. **Debug NEVER ships** — the no-ship boundary binds inside every workflow step (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §6 + `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`). Deep mode changes pass count and aggregation, nothing else.

## 5. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "Deep mode is on, so I can apply the fix directly to save an escalation round." | Debug NEVER ships, deep mode or not. The deepening is in hypothesis recall and fix-verification precision — the deliverable is still a text fix proposal + reproduction test + handoff. Applying the fix is /geniro:implement's job; the review gate still applies (§4 boundary). |
| "One of the three verifiers refuted the fix — drop it and re-enter the fix loop." | A lone refute is not a majority. It takes ≥2 of 3 to flip the verdict (§3); a single hallucinated refute demoting a genuinely-working fix is exactly what majority voting prevents. Quorum < 2 parseable votes → one fresh single-pass verifier, not a refute. |
| "Three generators landed on the same root-cause mechanism — that's strong confirmation, mark it confirmed." | Three passes converging on one mechanism is correlated generation, not evidence. Dedup it to ONE hypothesis (§2) BEFORE the test loop; confirmation comes from a captured artifact in §1.5, never from generator agreement. |
| "I'm inside the deep Workflow, so I can let the agents author the reproduction test in parallel." | The workflow agents are read-only — they return hypotheses and verdicts only. The orchestrator owns the reproduction-test authoring and every `atomic_state_write` (§4). Parallel agents writing source or tests is the boundary the wrapper tempts you to drop. |
