# Plan deep mode — reference

Plan-specific layers of the opt-in `--deep` quality mode. The cross-skill contract — activation pattern, the mandatory Workflow mitigations, the fail-safe ladder, and the shared anti-rationalization — lives in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`; read it first. This file covers only what `/geniro:plan` deepens and how.

`--deep` raises the quality of plan's ANALYSIS: it finds a better approach (recall) and validates the spec's facts more reliably (precision). It does not change the spec schema, the gate structure, or the approval contract.

## Contents

- §1 — Activation
- §2 — Recall: Phase 4 approach panel
- §3 — Precision: Phase 4 feasibility critics (3× + majority)
- §4 — Precision: Phase 7.5 spec-challenge (3× verify)
- §5 — Workflow shape
- §6 — Fail-safe
- §7 — Anti-rationalization

---

## 1. Activation

`/geniro:plan --deep <topic>` sets `deep-mode: true`. Semantic parse at Phase 0 mode-detect (alongside `--prd`) — matches `--deep` / `deep` / `deep mode`. Plan has no posting-mode AUQ to fold a chooser into, so deep mode is flag-only per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §2 (a dedicated Deep AUQ would spend a gate plan is deliberately frugal with). Persist `deep-mode:` to state.md frontmatter and the activation to `approvals[]` category `deep_mode_choice`. When false (default), Phase 4 and Phase 7.5 run their standard single-pass paths and deep mode adds zero overhead.

## 2. Recall — Phase 4 approach panel

Standard Phase 4.1 synthesizes the Phase 1 explore + Phase 3 answers into 2-3 approaches in one inline pass — the same context that later ranks them, so the candidate set reflects one set of blind spots. Deep mode replaces that single synthesis with a judge-panel `Workflow(...)`:

- **Generate** — spawn 3-4 approach generators in parallel, each pinned to a DISTINCT lens so the candidate set spans the design space rather than one author's first instinct: `minimal-change` (smallest diff that satisfies the objective), `reuse-first` (maximize existing-abstraction reuse), `risk-first` (minimize blast radius / maximize reversibility), and a domain-relevant fourth where it applies (e.g. `performance-first`). Each generator receives the same Phase 1 explore + Phase 3 answer context.
- **Dedup + score** — union the candidates, drop near-identical ones in-script (same core mechanism + same touched surface = one), then a scoring pass ranks the deduped set on the §4.3 axes (feasibility, blast radius, reversibility, cost).
- **Synthesize** — the orchestrator takes the top 2-3 ranked candidates into the standard §4.2 critic stage and the §4.3 approach AUQ. The user still picks from 2-3 rendered approaches; deep mode raises the odds those 2-3 are the best of a wider field.

Recall dedup runs BEFORE the §4.2 critics, so a duplicated approach never consumes a critic slot twice.

## 3. Precision — Phase 4 feasibility critics (3× + majority)

Standard §4.2 spawns tier-scaled critics (Trivial skip / Medium 1 comparative / Big 1-per-approach), and a single `blocking` verdict demotes an approach. Deep mode overrides the tier-scaling: **every candidate approach gets 3 independent `codebase-research-agent` critics**, and the feasibility verdict is by majority:

- Each critic independently stress-tests its assigned approach against the codebase (the same `RESEARCH_QUESTION` / `DELIVERABLE_SHAPE` as standard §4.2), returning per-approach risks classified `blocking | major | minor`.
- An approach is demoted from `Recommended`-eligible only when **≥2 of its 3 critics** return a `blocking` risk — a lone blocking call no longer demotes (it may be a hallucinated blocker); record it as a `major` caveat instead.
- If ≥2 critics flag blocking on EVERY candidate, loop back to Phase 3 with a tighter scope question (the standard all-blocked rule, now majority-gated).
- Parse-fail = abstain; quorum < 2 → one fresh single-pass critic for that approach (deep-mode.md §5).

Majority matters here because §4.2's purpose is to make the `Recommended` marker reflect feasibility evidence, not author confidence — and a single critic that hallucinates a blocker would otherwise demote the best approach.

## 4. Precision — Phase 7.5 spec-challenge (3× verify)

Deep mode needs no plan-side logic here — it passes `DEEP: true` to the always-on spec-challenge. Phase 7.5 already invokes `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with `MODE: plan`; in deep mode add `DEEP: true`, and the helper runs each cited claim through 3 verifiers with majority aggregation (its §4 Deep-mode subsection — single-sourced there so plan and implement deepen the spec-check identically). The verdict handling (keep / keep-with-modifications / re-plan) is unchanged — deep mode only hardens the FACT verification that feeds the verdict.

## 5. Workflow shape

Two fan-outs (may be one script with two phases, or separate calls). Build path/context strings as plain constants before any backtick template literal (deep-mode.md §4, path-constants mitigation). Return raw JSON text and parse defensively — never `agent({schema})`.

```
phase('Deep approaches — panel')
const LENSES = ['minimal-change', 'reuse-first', 'risk-first', 'performance-first']
const candidates = (await parallel(LENSES.map(lens => () =>
  agent(generatorPrompt(lens, exploreCtx, clarifyCtx), { label: `gen:${lens}`, phase: 'Deep approaches — panel' })
))).filter(Boolean).flatMap(parseApproaches)         // raw JSON → approach objects; parse-fail drops that lens
const ranked = scoreAndDedup(candidates)              // in-script: dedup near-identical, rank on the §4.3 axes

phase('Deep critics — 3x feasibility')
const critiques = await parallel(top3(ranked).map(a => () =>
  parallel([0,1,2].map(i => () =>
    agent(criticPrompt(a, i), { label: `critic:${a.slug}:v${i}`, phase: 'Deep critics — 3x feasibility' })))
    .then(votes => ({ slug: a.slug, verdict: majorityFeasibility(votes) }))   // ≥2 blocking → blocking; parse-fail = abstain
))
return { ranked: top3(ranked), critiques }
```

Each generator/critic prompt re-asserts the read-only contract (no Edit/Write/git; the orchestrator owns the spec write and all `atomic_state_write`), per deep-mode.md §6. OMIT `model=` at every spawn.

## 6. Fail-safe

Per deep-mode.md §5 — the standard paths are the floor:
- approach-panel workflow fails → fall back to the single inline §4.1 synthesis (2-3 approaches);
- critic workflow fails → the standard tier-scaled §4.2 critics;
- spec-challenge deep run fails → its single-pass batch.

Each degrades with a plain-English caveat, never a hard stop. Phase 7.5 is already advisory and fail-open, so a deep spec-challenge failure is doubly safe.

## 7. Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The panel generated 4 approaches — present all 4 in the §4.3 AUQ so the user sees everything." | The AUQ cap and the gate-frugality contract still hold: render the top 2-3 ranked, deduped candidates. The panel widens the FIELD searched, not the number of options the user weighs. Dumping 4-plus options is the click-fatigue the gate contract prevents. |
| "Three generators happened to land on the same approach — that's strong signal, rank it highest." | Three lenses converging on one mechanism is correlated generation, not independent feasibility evidence. Dedup it to ONE candidate before scoring (§2); the feasibility signal comes from the §3 critics, not from generator agreement. |
| "One critic called the approach blocking — demote it, that's the safe choice." | In deep mode a single blocking vote does not demote — it takes ≥2 of 3 (§3). A lone hallucinated blocker demoting the best approach is exactly the failure majority-voting prevents; record the lone call as a `major` caveat and let the user see it. |
| "Deep mode should also write the spec 3× and pick the best draft." | Deep mode is scoped to ANALYSIS — wider approach search (recall) and harder fact-checking (precision). The spec WRITE is single-author by design; multiplying it would fork the durable artifact and break the section-approval gate. The quality lever is the approach panel + the spec-challenge, not redundant spec drafts. |
