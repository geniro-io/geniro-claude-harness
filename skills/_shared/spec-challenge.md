# Spec challenge — adversarial pass over an authored spec

This file is the single source of truth. Skills cite this file; do NOT inline-paste the procedure.

An adversarial verification pass, invoked per the calling skill's contract, that hardens a `spec.md` before it is acted on — `/geniro:plan` gates the invocation on Big effort tier or deep mode; `/geniro:implement` and `/geniro:resolve` invoke it on every spec-driven run. It re-verifies the spec's load-bearing factual claims against the live code, (in plan mode) generates competing alternative approaches and red-teams the chosen one, then synthesizes a verdict. The failure class it exists to catch is the factually-wrong claim that reads as plausible prose: a headline mechanism that carries no weight, a backfill predicate that matches zero rows, a write-volume estimate off by an order of magnitude — defects that survive every gate keyed on structure rather than ground truth.

## Consumers: /geniro:plan (post-write, pre-approval), /geniro:implement (Phase 1, pre-edit), /geniro:resolve (MODE: plan over its produced spec)

`/geniro:plan` invokes after writing `spec.md` and before the human approval gate, when its Big-tier-or-deep gate fires. `/geniro:implement` invokes in Phase 1 after research and before the first Edit/Write, on every spec-driven run. `/geniro:resolve` invokes over the spec it emits, before handoff. Each caller passes `MODE`; the rest of the contract is identical.

## Contents

- §1 Caller contract — invocation slots + what comes back
- §2 MODE branching — the per-skill behavior table
- §3 Stage A — extract the cited-claim set
- §4 Stage B — VERIFY claims (both modes)
- §5 Stage C — ALTERNATIVES (plan mode only)
- §6 Stage D — RED-TEAM the chosen approach (both modes)
- §7 Stage E — SYNTHESIZE the verdict
- §8 Verdict handling per MODE
- §9 Echo contract
- §10 Anti-rationalization
- §11 Definition of Done

---

## 1. Caller contract

Caller invokes:

> Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-challenge.md` with `MODE: <plan|implement>`, `SPEC_PATH: <path to spec.md>`, `TASK_DIR: <planning task-dir>`, `EFFORT_TIER: <caller scope signal>`, `DEEP: <true|false>`.

| Slot | Meaning |
|---|---|
| `MODE` | `plan` (post-write, pre-approval) or `implement` (Phase 1, pre-edit). Branches per-skill behavior — see §2. |
| `SPEC_PATH` | Path to the `spec.md` to challenge. |
| `TASK_DIR` | Planning task-dir; scratch output lands at `<TASK_DIR>/.spec-challenge-out.md`. |
| `EFFORT_TIER` | Informational only — the caller's native scope signal (`/geniro:plan`: effort tier `Trivial\|Small\|Medium\|Big`; `/geniro:implement`: codebase-explorer `change_scope` `trivial\|small\|medium\|big`). Calibrates the synthesis judge's risk tolerance — never an internal gate; whether the pass runs at all is the caller's contract. |
| `DEEP` | `true` when the calling skill is in deep mode (`deep-mode: true`), else `false` / absent. When `true`, Stage B (§4) runs each cited claim through 3 independent verifiers with majority aggregation instead of 1 — the precision layer per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3. Orthogonal to `MODE`; raises verification reliability, not the claim set. Missing reads as `false`. |

**Once invoked, no internal tier skip.** The helper never decides to skip itself — the invocation decision was already made by the caller's contract, and re-deciding it here would silently undo a skill-level decision. Cost stays bounded by the spec's own cited-claim set (§3): one verifier per cited claim, scaling to claim count rather than every sentence — a spec citing few claims gets a small batch, one citing many gets a larger one. The judge reads `EFFORT_TIER` to calibrate how hard a borderline red-team risk should weigh, never whether a stage runs.

The caller receives back:
- A verdict (per §7, MODE-specific).
- The scratch report at `<TASK_DIR>/.spec-challenge-out.md` (transient working file — the owning skill's terminal-exit cleanup removes it as part of the T1 rm set: `/geniro:plan` on `done`/`aborted` in MODE: plan, `/geniro:implement` on every terminal `phase:` write in MODE: implement; the `/geniro:update` migration walk sweeps any leftover from an interrupted run).
- In plan mode: a list of keep-with-modifications fixes to fold into the spec.
- In implement mode: either a silent clean-pass note OR a fired AskUserQuestion (per §8).

## 2. MODE branching

| Stage | `MODE: plan` (post-write, pre-approval) | `MODE: implement` (Phase 1, pre-edit) |
|---|---|---|
| Extract claims (§3) | yes | yes |
| VERIFY claims (§4) | yes — one verifier per cited claim | yes — same |
| ALTERNATIVES (§5) | yes — generate competing approaches, score head-to-head | SKIP — the approach is already approved and locked |
| RED-TEAM (§6) | yes | yes |
| SYNTHESIZE (§7) | one judge: keep / keep-with-modifications / re-plan | one judge: clean / defects-found |
| Verdict handling (§8) | fold keep-with-modifications fixes INTO the spec; verdict feeds the human approval gate | do NOT rewrite the spec; fire an AskUserQuestion only when a claim is refuted or a blocking red-team risk exists |

The asymmetry has one root cause: in plan mode the spec is a draft the calling skill owns and is about to harden before asking the human to approve it, so folding fixes in is correct. In implement mode the spec is the user's already-approved artifact and the durable file of an upstream producer — rewriting it would force a cross-producer schema lockstep and silently re-open a design decision the user already signed off on. Implement mode verifies FACTS and never re-opens the DESIGN.

## 3. Stage A — extract the cited-claim set

Read `SPEC_PATH` fully. Build the verifiable-claim set from the three places a spec asserts something checkable against the code:

1. **Section 6 (Steps).** Each step cites ≥1 `file:line` reference (per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` — Phase 7 validator check #3 enforces this). Each citation is a claim: "the thing this step describes lives at this file:line and behaves as stated." Meta-steps without a citation (e.g. "create a new branch") carry no factual claim — skip them.
2. **Section 4 (Assumptions).** Each assumption is an explicit factual predicate about the codebase or environment ("the `users` table has a `deleted_at` column", "the job runs at most once per minute"). Each is a claim.
3. **Frontmatter `budget` and `effort_tier`.** These are estimate-claims (write volume, time budget, row counts, tier sizing). A miscounted estimate — one off by an order of magnitude — is a defect class this pass exists to catch, so estimate-claims enter the set.
4. **Frontmatter `workflow_refs[]` linked-ticket constraints.** When the spec frontmatter carries `workflow_refs[]` (linked tracker tickets — `/geniro:implement` fetches their bodies at workspace setup, before any edit), the ticket bodies' explicit constraints are first-class fact-check inputs: locked decision tables, role / permission matrices, and "do not change X" statements. Each such constraint is a claim about what the planned change must respect, verified against the planned change here BEFORE the first edit. A ticket read only after the push cannot stop a change that contradicts it — by then the contradiction has shipped. Pulling the constraints into the claim set moves that read to the one point where it can still change the outcome.

Record each claim with its source location and the literal asserted fact. This bounded set is the input to §4 — one verifier per claim, no more. Verifier count scales to the claim count, mirroring how `/geniro:review` verifies every survivor over a pre-bounded survivor set.

If the spec cites zero verifiable claims (e.g. a pure meta-step spec), skip §4 and note it in the scratch report; §5/§6/§7 still run.

## 4. Stage B — VERIFY claims (both modes)

Spawn one verifier per cited claim. This stage reuses the `/geniro:review` per-finding verifier contract — read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` fully and mirror it. The two differences from `/geniro:review` are the polarity and the source of the "finding":

**Polarity flip.** The `/geniro:review` verifier asks "does the claimed DEFECT exist in the cited code?" The spec-claim verifier asks "is this asserted FACT true in the cited code?" Frame the spec claim as the thing under test; `validation: confirmed` means the fact holds, `validation: refuted` means the cited code contradicts the asserted fact, `validation: clarified` means the fact is partly true but the spec's framing is off (e.g. the column exists but is nullable when the step assumes NOT NULL).

**Refute by default.** Mirror the `/geniro:review` stance: the verifier's job is to disprove the claim, not to rubber-stamp it. A claim survives only when the cited code, read directly, bears it out.

### Input contract per verifier

Pre-inline isolated context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`. Each verifier receives ONLY its own claim plus, mirroring `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2:

- The single claim: source location (Section 6 step / Section 4 assumption / frontmatter field) + the literal asserted fact.
- The cited code slice — read the file at the claim's `file:line` and inline it, using the slice cap in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2. For a Section 4 assumption or a frontmatter estimate with no `file:line`, grep the relevant symbol/table/path and inline the matched region within the same cap.
- 1-hop caller grep — `grep -rn "<symbol>"` for the cited symbol, capped per §2.
- 1-2 sibling tests for the same symbol — grep `test/ tests/ __tests__/ spec/`, capped per §2.
- **A matching declared-source result, when one applies.** Some claims assert state that lives outside the code — a tracker status, a DB row, a deploy / feature-live flag (the `workflow_refs[]` linked-ticket constraints of §3 (Stage A) item 4 and any Section 4 assumption about external state). For those, code is not the maximum source. Before the spawn, the orchestrator applies `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`: if the project declares a `## Data Sources` entry whose `confirms:` hint matches the claim's domain, the orchestrator pre-runs that read-only-screened source and inlines its result into THIS verifier's evidence alongside the code slice. The verifier then confirms the claim against the maximum applicable set — code plus the declared source — not code alone. This is additional evidence to the same verifier, NOT a new verifier per source: the one-verifier-per-claim bound (§3) is unchanged. Fail-open — a source that's unavailable, can't be screened read-only, or errors is omitted with a one-line caveat in the verifier's input, never blocks the spawn. A code-only claim with no matching declared source runs exactly as before.

Each verifier does NOT receive other claims, the orchestrator's reasoning, or which spec section the claim came from beyond what it needs — isolated context prevents anchoring and sycophancy (the documented multi-judge failure mode).

### Output contract per verifier

Emit exactly one structured result, grounded per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`:

```yaml
validation: confirmed | refuted | clarified
confidence: 1 | 2 | 3 | 4 | 5
evidence: "<literal quote from the cited file:line that confirms or refutes the asserted fact>"
```

`evidence` MUST be a literal quote from the cited file. A paraphrase-only verdict ("the code looks consistent with the claim") is refused and re-prompted — "the agent reported PASS" is not evidence per the evidence standard.

### Spawn batch

Compose the verifier prompt to reuse `agents/reviewer-agent.md` verify-finding mode as-is — frame the spec claim as the "finding body" and state the polarity flip ("verify the asserted FACT is true, not that a defect exists") in the prompt. No agent edit is needed: the agent's verify-finding mode accepts 1-3 same-file findings, and a single claim-like body — the degenerate one-finding form spec-challenge always uses — plus cited slice + caller grep + sibling tests already yields the `validation / confidence / evidence` schema; the polarity lives in the prompt framing, not the agent's schema.

Spawn via the runtime-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (prefixed `geniro:reviewer-agent` → bare → general-purpose-with-body). OMIT `model=` so verifiers inherit the orchestrator's tier per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Send ALL verifier spawns in ONE assistant response — separate turns serialize execution and double wall-time; the parallel-spawn invariant applies here exactly as in `/geniro:review` Phase 4.2.

Aggregate: any `refuted` claim is a defect; `clarified` is a soft defect (the spec's framing needs a fix); `confirmed` claims pass. A claim that no source — code or declared — could confirm is recorded as unverified/unconfirmed (handled by the existing disposition, never silently accepted as fact). Record each result in the scratch report.

### Deep mode — 3× verify + majority (`DEEP: true`)

When the caller passes `DEEP: true`, each cited claim gets **3 independent verifiers** instead of 1, run inside an internal `Workflow(...)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` (observe its §4 mandatory mitigations — raw JSON not schema, re-assert the read-only contract in every prompt, OMIT `model=`, path constants outside template literals). Each verifier receives the identical isolated input the single-pass verifier gets (its one claim + cited slice + caller grep + sibling tests); independence is load-bearing, so a verifier never sees the others' votes. Aggregate per claim by majority:

- Tally the three dispositions across the parseable votes.
- ≥2 `refuted` → the claim is a **hard defect** (`refuted`).
- else ≥2 `clarified` → the claim is a **soft defect** (`clarified`) — the spec's framing needs a fix. Single-pass treats any `clarified` as a soft defect, so a `clarified` majority must surface one too: collapsing it into a pass would make deep mode WEAKER than single-pass, which the floor invariant (deep-mode.md §5) forbids.
- else → the claim **passes** (`confirmed`).
- A verifier whose raw output won't parse **abstains** — counts toward neither side; the ≥2 thresholds are over the parseable votes. If <2 parseable votes remain (≥2 abstained), quorum fails → run ONE fresh single-pass verifier for that claim and take its verdict (deep-mode.md §5 ladder).

The verdict feeds §7 exactly as the single-pass result does — deep mode changes the vote count, not the downstream handling. If the workflow errors or agent registration fails, fail-safe to the single-pass batch above and note `Deep mode couldn't run the extra spec-check passes — fell back to a single pass.` in the scratch report (deep-mode.md §5).

## 5. Stage C — ALTERNATIVES (plan mode only)

SKIP entirely in `implement` mode — the approach is approved and locked; generating competitors would re-open a settled decision.

In `plan` mode, generate 2 competing approaches that solve the same objective by a different mechanism than the spec's chosen approach, then score all candidates (the spec's approach + the competitors) head-to-head on the same axes the calling skill used to pick its approach (feasibility against the verified claims, blast radius, reversibility, cost). The output is a ranked comparison, not a new spec. Its purpose is to stress the chosen approach: if a competitor scores clearly higher once the §4 verification results are factored in, that is a signal toward the `re-plan` verdict in §7.

## 6. Stage D — RED-TEAM the chosen approach (both modes)

Red-team the spec's chosen approach against its own stated objective and the verified-claim results from §4. Hunt for:

- A headline mechanism that carries no actual weight — present in the prose, load-bearing in the framing, but inert in the design (the dead-weight-mechanism defect class).
- A predicate, filter, or migration that operates on an empty or wrong set (the zero-rows-matched defect class).
- An estimate that is order-of-magnitude wrong once the verified facts are applied (the write-volume-miscount defect class).
- A step whose stated precondition is refuted by a §4 result — the step cannot execute as written.
- Missing rollback/recovery for a step that mutates durable state.

Classify each red-team finding as **blocking** (the approach cannot proceed as written) or **non-blocking** (a hardening fix that does not invalidate the approach). Record findings with the file:line or §4 result that grounds each one — a red-team finding without a concrete anchor is a hypothesis, not a defect.

## 7. Stage E — SYNTHESIZE the verdict

One judge reads the §4 verification results, the §5 comparison (plan mode), and the §6 red-team findings, and emits a single verdict. The judge weighs a borderline red-team risk against `EFFORT_TIER` — a Big task tolerates less residual risk than a Trivial one. Ground the verdict per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`: every defect cited in the verdict carries the literal file:line quote or §4 result that supports it.

**plan mode** — one of:
- `keep` — no refuted claims, no blocking red-team finding, no competitor clearly superior. The spec is sound as written.
- `keep-with-modifications` — `clarified`/non-blocking findings exist; list the specific fixes to fold into the spec.
- `re-plan` — a refuted load-bearing claim, a blocking red-team finding, or a competitor that scores clearly higher invalidates the chosen approach. The spec needs re-authoring at the approach level.

**implement mode** — one of:
- `clean` — every claim confirmed, no blocking red-team finding.
- `defects-found` — ≥1 claim refuted OR a blocking red-team finding exists.

## 8. Verdict handling per MODE

**plan mode.** The helper hardens the spec but does NOT approve it. On `keep-with-modifications`, the calling skill re-authors the affected spec sections to fold the fixes in and re-runs its own validator. On `re-plan`, the calling skill re-enters its approach-generation phase. The verdict then feeds the human approval gate — the human approves the hardened spec, not this helper.

**implement mode.** Do NOT rewrite the spec — it is the user's approved artifact and rewriting an upstream producer's durable file would force a cross-producer schema lockstep. Verify FACTS; never re-open the approved DESIGN DECISION.

- `clean` verdict → emit a silent advisory note in the scratch report and proceed to the first Edit/Write. Do NOT fire an AskUserQuestion on a clean pass — a question with nothing to decide is noise, and the always-WAIT-restraint norm reserves the AUQ for a real decision.
- `defects-found` verdict → fire ONE AskUserQuestion before the first Edit/Write:

```
header: "Spec check"
question: "Re-checking the approved spec against the current code turned up <N> issue(s): <one-line summary>. How do you want to proceed?"
options:
  - "Proceed anyway"            -> ignore the findings, continue implementing as specified
  - "Fix the spec, then proceed"-> hand back to /geniro:plan to repair the refuted claim(s), then resume
  - "Abort — re-plan via /geniro:plan" -> stop; the approach needs rethinking before any code is written
```

Persist the pick to the calling skill's state.md `approvals[]` so a compaction-resume does not re-ask.

## 9. Echo contract

Print one plain-English line per stage as it runs, so the user can see the pass progress. Plain English — no internal stage letters or schema versions:

- Extract: `Challenging the spec — found <N> cited claims to verify against the code.`
- Verify: `Verifying <N> cited claims against the code...`
- Alternatives (plan only): `Generating <M> competing approaches and scoring them head-to-head...`
- Red-team: `Red-teaming the chosen approach for dead-weight mechanisms, empty predicates, and miscounted estimates...`
- Synthesize: `Verdict: <plain verdict> — <one-line reason>.`

On a clean implement-mode pass, the final line is the only user-visible output: `Spec checks out against the current code — proceeding.`

## 10. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "This is a Trivial task — skip the challenge to save time." | The caller's gate already decided this run warrants the pass — skipping internally would silently undo a decision made at the skill level. A small spec with one wrong `file:line` is the cheap-but-fatal case the pass exists to catch; the cost is bounded to the spec's cited claims, which for a small spec is a small batch. Tier calibrates the judge's risk tolerance, not whether the pass runs. |
| "The spec was just written/approved, so its claims are probably correct — confirm them." | "Probably correct" is the exact posture the pass refutes. The three defects that motivated this pass all lived in an approved spec that read as plausible. Re-read the cited code; a claim survives only when the code bears it out. |
| "Verifying every cited claim is too many spawns — sample the load-bearing ones." | The claim set is already pre-bounded to file:line citations + assumptions + estimates, mirroring how `/geniro:review` verifies every survivor over a bounded set. Wall-time is ~max(spawn-time) because the batch is parallel. Sampling reintroduces the miss the pass eliminates. |
| "A verifier said the claim looks consistent — that's a confirm." | "Looks consistent" is a paraphrase, not evidence. The output contract requires a literal quote from the cited file. Refuse the paraphrase-only verdict and re-prompt — the evidence standard forbids reasoning-as-evidence. |
| "In implement mode a claim is refuted, so I'll just fix the spec and keep going." | Implement mode does not rewrite the user's approved spec — that re-opens a signed-off design and forces a producer-schema lockstep. Fire the AskUserQuestion and let the user choose proceed / fix-via-plan / abort. The helper verifies facts; the user owns the design. |
| "The implement-mode pass came back clean — I'll surface a confirmation question anyway." | A question with nothing to decide is noise and breaks the always-WAIT-restraint norm. On a clean pass, emit the silent advisory line and proceed. Reserve the AUQ for a real refuted-claim-or-blocking-risk decision. |
| "I'll fold the keep-with-modifications fixes in plan mode but skip re-running the validator." | The calling skill's validator is what guarantees the folded edits did not break the spec's schema. Skipping it ships an unvalidated spec into the human approval gate, defeating the harden-before-approve purpose. Re-run it after folding. |
| "Alternatives generation is slow — skip it in plan mode too." | Alternatives is the stage that catches "a clearly better approach exists once the facts are checked." Skipping it means a refuted-fact-driven re-plan signal is lost. It runs in plan mode; it is correctly skipped only in implement mode, where the approach is locked. |
| "The red-team found a risk but I can't pin it to a file:line — report it anyway." | A red-team finding without a concrete anchor (file:line or a §4 result) is a hypothesis. Unanchored findings inflate the defect count and erode trust in the verdict. Anchor it or drop it. |
| "Pass the full spec to each verifier so it has complete context." | Shared context anchors verifiers toward agreement — the documented multi-judge failure mode. Each verifier sees ONLY its one claim plus the isolated cited slice, caller grep, and sibling tests. Independence is load-bearing. |

## 11. Definition of Done

- [ ] Stage A extracts claims from Section 6 citations, Section 4 assumptions, frontmatter `budget`/`effort_tier`, and (when present) frontmatter `workflow_refs[]` linked-ticket constraints.
- [ ] Stage B spawns exactly one verifier per cited claim, all in ONE assistant response, via the spawn-agent ladder with `model=` omitted.
- [ ] Each verifier receives isolated context (cited slice + 1-hop caller grep + 1-2 sibling tests) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 caps and emits `validation / confidence / evidence` with a literal file:line quote.
- [ ] Stage C (ALTERNATIVES) runs in plan mode and is skipped in implement mode.
- [ ] Stage D red-team findings are each anchored to a file:line or a §4 result and classified blocking / non-blocking.
- [ ] Stage E verdict is MODE-correct (plan: keep / keep-with-modifications / re-plan; implement: clean / defects-found) and grounded per the evidence standard.
- [ ] plan mode folds keep-with-modifications fixes into the spec and the calling skill re-runs its validator; the helper does NOT approve.
- [ ] implement mode never rewrites the spec; fires the proceed / fix / abort AUQ only on `defects-found`, stays silent on `clean`, and persists the pick to `approvals[]`.
- [ ] One plain-English echo line per stage; a clean implement-mode pass surfaces only the proceeding line.
- [ ] When `DEEP: true`, Stage B runs 3 verifiers per claim with majority aggregation (parse-fail = abstain; quorum <2 → single-pass fallback) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md`; `DEEP: false`/absent runs the single-pass batch unchanged.
