<!-- Generated from skills/plan/loop-phase-4-approaches.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 4 — Approaches

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

## Contents

- 4.1 Approach generation
- 4.1.5 Design it twice (Big tier, interface shape)
- 4.2 Independent stress-test (adversarial weighing)
- 4.2.5 Build-vs-buy library reuse (per approach)
- 4.3 Present approaches — message-first
- 4.4 Persistence

State.md `phase: approaches` during this phase.

### 4.1 Approach generation

Model synthesizes Phase 1 explore + Phase 3 answers into 2-3 distinct approaches when the design genuinely admits more than one shape; when it admits exactly one, present that one and name why the alternatives collapse. A filler alternative is worse than a single option — the gate becomes a choice between the real approach and a strawman, and it flips the §8.5 `≤1 approach` skip so a fabricated option set is written to past learnings. Each approach:
- **Name** (3-5 word label)
- **Summary** (2-3 sentences)
- **Trade-off** (1 sentence: gain vs give-up)
- **Effort estimate** (Trivial / Small / Medium / Big per effort-scaling.md)

**A materially cheaper shape is a real approach, not filler.** Price the objective at less than full scope as one of the 2-3 candidates, not a fourth: a strict subset carrying most of the value, or reaching it through configuration or an existing mechanism instead of new code. Include one whenever it is genuinely on the table. The filler bar rejects a strawman *of the same shape*, built to pad the option count; a cheaper shape is its opposite — the only candidate that can shrink the work, and the one nobody proposes because the request implies the full build. Give it the same `Trade-off:` line as every other approach, naming what it gives up. Every candidate here still has to be buildable — this phase's output becomes a spec, so "build nothing" is not an approach but a Phase 3 conclusion, routed at §3.1.

### 4.1.5 Design it twice (Big tier, interface shape)

Fires only on the Big tier when the decision is the shape of an interface or module boundary (a new public contract, a module's seam, a service API) — the one decision where the first design in mind is rarely the best and rework is costliest. Then read `${CLAUDE_PLUGIN_ROOT}/skills/plan/loop-phase-4-design-twice.md`, before finalising the §4.1 list.

### 4.2 Independent stress-test (adversarial weighing)

The model that generated the §4.1 approaches also ranks them in the §4.3 AUQ — same blind spots, so its `Recommended` pick re-confirms its own bias. Before ranking, get an independent codebase-grounded challenge, so `Recommended` reflects feasibility evidence rather than the author's confidence.

Effort-tier-scaled (tier already detected in Phase 1.2 — the critic cost lands only where a wrong approach is expensive):

| Tier | Stress-test spawns |
|---|---|
| Trivial | Skipped — single narrow approach, no ranking risk |
| Small | Skipped — too narrow to warrant a critic; if Phase 4 produced ≥2 genuinely competing approaches, treat as Medium (1 comparative critic) |
| Medium | 1 `codebase-research-agent` — stress-tests all approaches comparatively in one spawn |
| Big | 1 `codebase-research-agent` per approach (2-3 in parallel) — each independently challenges its assigned approach |

Spawn per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research, all in a single assistant response (parallel-spawn rule), per the spine §Spawn contract (OMIT `model=`). The orchestrator MAY draft the §4.3 approach render during the wait, splicing each approach's `Stress-test:` verdict in on return; the batch is drained before §4.3. Per-spawn slots:

- `RESEARCH_QUESTION`: "Stress-test approach '<name>' against this codebase: find blockers, hidden coupling, convention conflicts, and prior rejected attempts that would make it fail or cost more than its stated effort estimate. Work to disprove the approach's feasibility, not to confirm it — the approach text reads plausible because its author believed it, and plausibility is not evidence. A no-risks verdict is credible only when you list the surfaces you checked and found clean." (Medium tier: enumerate all approaches in one question.)
- `DELIVERABLE_SHAPE`: `"table of [{approach, risk, evidence file:line, severity: blocking|major|minor}], plus one 'Checked:' line per approach listing the files/surfaces examined — required even, and especially, when no risks were found"`
- `SCOPE_HINT`: path globs from the approach's touched surface (Phase 1 echo entries).
- `PRE_INLINED_CONTEXT`: the §4.1 approach list + relevant Phase 1 `query-learnings` entries — especially any prior `user_rejected_suggestion` for this topic-area, which is itself a blocking signal.
- `OUTPUT_PATH`: `<task-dir>/.research-critique-<approach-slug>.md` (Big) or `<task-dir>/.research-critique.md` (Medium).
- `THOROUGHNESS`: `medium`.

After the batch returns, fold the critiques into the ranking — trust a verdict only as far as its evidence:

- **Verify before demoting.** A `blocking` verdict demotes only on verified evidence: read the cited `file:line` (one targeted Read) and confirm the quoted code grounds the risk. A `blocking` row with no `file:line` citation, or whose citation does not hold on read, downgrades to `major` with the note `evidence did not verify` — an unanchored blocker is a hypothesis, not a risk, and demoting the strongest approach on one is the over-flagging failure this bar stops.
- An approach carrying a verified `blocking` risk is never the `Recommended` option — demote it. If every approach carries a verified blocking risk, loop back to Phase 3 with a tighter scope question rather than recommend a non-viable plan.
- `major` / `minor` risks annotate an approach but do not bar recommendation.
- **A clean verdict needs a checked account.** A critique reporting no risks for an approach without its `Checked:` line is silence, not feasibility evidence — treat that approach as un-stress-tested (note "stress-test inconclusive" on it in the §4.3 chat message) rather than feasibility-confirmed.
- Each approach gains a one-line `Stress-test:` verdict (top risk + evidence file:line) carried into the §4.3 chat message (per the Gate presentation contract) and the §4.4 `## Considered Alternatives` body.

Append a `## Tool log` Echo entry per spawn. The weighing is advisory and fail-open: a failed critic logs a `## Errors` entry, and every approach it covered renders "stress-test unavailable" in §4.3, ranked on the model's own judgment.

### 4.2.5 Build-vs-buy library reuse (per approach)

While designing approaches, apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/library-reuse-audit.md` MODE: plan to each component an approach would otherwise hand-write — it owns the adopt-vs-hand-write trade-off, the Trivial and manifest-less skips, and carrying the trade-off into the spec prose. No spawn and no separate adoption AUQ: the §4.3 pick is the confirmation.

A package name appears in approach prose or the spec only when the project's manifest holds it or the user named it; otherwise describe the capability generically ("an established CSV-parsing library") — an unverified name written into a spec becomes an install target downstream.

### 4.3 Present approaches — message-first

Apply the Gate presentation contract.

**Artifact** — fire the before-gate update for this site (call-site table in `loop-artifact-call-sites.md`) before the approach AUQ.

1. **Render the approaches to a chat message in the Visual rendering language** (Gate presentation contract): open with the progress tracker (`● Approach` current) and a one-sentence opener naming the decision. For each of the 2-3 approaches, the two layers of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers: name, a plain-English 1-2 sentence summary of what the user would get, and `Trade-off:` (gain vs give-up in plain words) — then a `**Technical detail:**` block holding the ASCII data-flow / architecture diagram (5-10 lines), `What changes:` (the key new/edited files), and the approach's `Stress-test:` verdict line from §4.2 (top risk + evidence `file:line`). Lead with the Recommended approach. Where no usable verdict exists, render the note in the verdict line's place: "stress-test unavailable" on an approach whose §4.2 critique did not return, "stress-test inconclusive" on an approach whose no-risks critique lacked its `Checked:` account.

2. **Ask one lean question.** Single-select; header "Approach"; one option per approach, `Recommended` first per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` (§Recommended-label policy). Option `label` = approach name; `description` = 1-line summary + trade-off; `preview` empty or a one-line recap. The `Recommended` marker follows the §4.2 ranking. With a single approach the gate is a confirm, not a pick: options are "Go with this approach" / "Explain further" (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Explain-further option) / "I want a different shape — I'll describe".

Full literal example (chat message + lean AUQ: Service-layer fan-out vs in-process Promise.all) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §3.

### 4.4 Persistence

User pick → append to `approvals[]` with category `approach_choice`. Other approaches captured to body section `## Considered Alternatives`, each carrying its §4.2 `Stress-test:` verdict line + evidence; an approach demoted for a verified blocking risk records `Why not recommended: <blocking risk + file:line>`.

**Record a rejection signal.** After appending to `approvals[]`, source `${CLAUDE_PLUGIN_ROOT}/lib/emit-rejection.sh` and invoke:

```bash
emit_rejection_if_signal \
 "/geniro:plan" "<topic>" "approach_choice" \
 "<recommended approach label>" "<picked label>" "<recommended label>"
```

Where `<topic>` = $ARGUMENTS topic OR `global` if not inferable. The helper emits `user_rejected_suggestion` only when the signal fires (picked differs from recommended, or an explicit cancel/no/skip); acceptance is a no-op. A free-text answer overriding the question is a divergent pick like any other and fires the signal. After a fired signal, echo `Recorded learning: <summary>` — the same echo §8.5 makes, so a skipped emit shows up as a missing line instead of leaving no trace at all.

**Read side:** re-rank or omit, in the §4.3 AUQ, any approach whose prior `approach_choice` rejection §1.1's second query surfaced.

Example body:

```markdown
## Considered Alternatives

### Inline Refactor (rejected)
Summary: ...
Trade-off: smaller surface change, but locks into existing module shape.
Stress-test: shared mutable cache in src/store/cache.ts:88 is read by 3 other modules — refactor would break them (severity: major).
Why rejected: violates new boundary established in Q3 2026 architecture review.
```

`## Considered Alternatives` is copied to spec.md body verbatim in Phase 6. /geniro:implement reads but not gates on it.

**Artifact** — after the approach pick persists, fire the update for this site (call-site table in `loop-artifact-call-sites.md`).

**Transition.** Once the pick, rejection signal, and artifact update are done, write `phase: section-approve` via `atomic_state_set_field` and proceed to Phase 5.
