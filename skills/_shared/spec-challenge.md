# Spec challenge — adversarial pass over an authored spec

This file is the single source of truth. Skills cite this file; do NOT inline-paste the procedure.

An adversarial verification pass, invoked per the calling skill's contract, that hardens a `spec.md` before it is acted on — `/geniro:plan`, `/geniro:implement`, and `/geniro:resolve` each invoke it on every spec-driven run. It re-verifies the spec's load-bearing factual claims against the live code, red-teams the chosen approach, then synthesizes a verdict. The failure class it exists to catch is the factually-wrong claim that reads as plausible prose: a headline mechanism that carries no weight, a backfill predicate that matches zero rows, a write-volume estimate off by an order of magnitude — defects that survive every gate keyed on structure rather than ground truth.

## Consumers: /geniro:plan (post-write, pre-approval), /geniro:implement (Phase 1, pre-edit), /geniro:resolve (MODE: plan over its produced spec)

`/geniro:plan` invokes after writing `spec.md` and before the human approval gate, on every run. `/geniro:implement` invokes in Phase 1 after research and before the first Edit/Write, on every spec-driven run. `/geniro:resolve` invokes over the spec it emits, before handoff. Each caller passes `MODE`; the rest of the contract is identical.

## Contents

- §1 Caller contract — invocation slots + what comes back
- §2 MODE branching — the per-skill behavior table
- §3 Stage A — extract the cited-claim set
- §4 Stage B — VERIFY claims (both modes)
- §5 Stage C — the approach is not re-opened here
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
| `TASK_DIR` | The caller's task-dir; scratch output lands at `<TASK_DIR>/.spec-challenge-out.md`. |
| `EFFORT_TIER` | Informational only — the caller's native scope signal (`/geniro:plan`: spec frontmatter `effort_tier`; `/geniro:implement`: codebase-explorer `change_scope`; both `trivial\|small\|medium\|big`). Calibrates the synthesis judge's risk tolerance — never an internal gate; whether the pass runs at all is the caller's contract. |
| `SCOPE` | `full` (default, absent reads as full) or `changed-only`. `changed-only` restricts Stages A and B to claims that are new or altered since the last pass over this spec. Stages D and E still run over the whole spec, because a new claim can invalidate an old step. This is the mode every re-entry after a spec edit uses (§8 Re-entry); it exists so that re-checking a revised spec costs a fraction of the first pass instead of the whole of it. |
| `DEEP` | `true` when the calling skill is in deep mode (`deep-mode: true`), else `false` / absent. When `true`, Stage B (§4) runs each cited claim through 3 independent verifiers with majority aggregation instead of 1 — the precision layer per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` §3. Orthogonal to `MODE`; raises verification reliability, not the claim set. Missing reads as `false`. |

**Once invoked, no internal tier skip.** The helper never decides to skip itself — the invocation decision was already made by the caller's contract, and re-deciding it here would silently undo a skill-level decision. Cost stays bounded by the spec's own cited-claim set (§3): every claim is verified, with same-file claims clustered into shared verifier spawns (§4 Spawn batch), so spawn count scales sub-linearly with claim count and never with sentence count. The judge reads `EFFORT_TIER` to calibrate how hard a borderline red-team risk should weigh, never whether a stage runs.

The caller receives back:
- A verdict (per §7, MODE-specific).
- The scratch report at `<TASK_DIR>/.spec-challenge-out.md` (transient working file — the owning skill's terminal-exit cleanup removes it as part of the T1 rm set: `/geniro:plan` on `done`/`aborted`, `/geniro:implement` and `/geniro:resolve` on every terminal `phase:` write; the `/geniro:update` migration walk sweeps any `.geniro/planning` leftover from an interrupted run).
- In plan mode: a list of keep-with-modifications fixes to fold into the spec.
- In implement mode: either a silent clean-pass note OR a fired AskUserQuestion (per §8).

## 2. MODE branching

| Stage | `MODE: plan` (post-write, pre-approval) | `MODE: implement` (Phase 1, pre-edit) |
|---|---|---|
| Extract claims (§3) | yes | yes |
| VERIFY claims (§4) | yes — every claim verified, clustered per §4 | yes — same |
| ALTERNATIVES (§5) | no — the approach is not re-opened here | no — same |
| RED-TEAM (§6) | yes | yes |
| SYNTHESIZE (§7) | one judge: keep / keep-with-modifications / re-plan | one judge: clean / defects-found |
| Verdict handling (§8) | fold keep-with-modifications fixes INTO the spec; verdict feeds the human approval gate | do NOT rewrite the spec; fire an AskUserQuestion only when a claim is refuted or a blocking red-team risk exists |

The asymmetry has one root cause: in plan mode the spec is a draft the calling skill owns and is about to harden before asking the human to approve it, so folding fixes in is correct. In implement mode the spec is the user's already-approved artifact and the durable file of an upstream producer — rewriting it would force a cross-producer schema lockstep and silently re-open a design decision the user already signed off on. Implement mode verifies FACTS and never re-opens the DESIGN.

## 3. Stage A — extract the cited-claim set

Read `SPEC_PATH` fully. Build the verifiable-claim set from the three places a spec asserts something checkable against the code:

1. **Section 6 (Steps).** Each step cites ≥1 `file:line` reference (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spec-template.md` — Phase 7 validator check #3 enforces this). Each citation is a claim: "the thing this step describes lives at this file:line and behaves as stated." Meta-steps without a citation (e.g. "create a new branch") carry no factual claim — skip them.
2. **Section 4 (Assumptions).** Each assumption is an explicit factual predicate about the codebase or environment ("the `users` table has a `deleted_at` column", "the job runs at most once per minute"). Each is a claim.
3. **Frontmatter `budget` and `effort_tier`.** These are estimate-claims (write volume, time budget, row counts, tier sizing). A miscounted estimate — one off by an order of magnitude — is a defect class this pass exists to catch, so estimate-claims enter the set.
4. **Frontmatter `workflow_refs[]` linked-ticket constraints.** When the spec frontmatter carries `workflow_refs[]` (linked tracker tickets — `/geniro:implement` fetches their bodies at workspace setup, before any edit), the ticket bodies' explicit constraints are first-class fact-check inputs: locked decision tables, role / permission matrices, and "do not change X" statements. Each such constraint is a claim about what the planned change must respect, verified against the planned change here BEFORE the first edit. A ticket read only after the push cannot stop a change that contradicts it — by then the contradiction has shipped. Pulling the constraints into the claim set moves that read to the one point where it can still change the outcome.

5. **Every quantity the spec states, wherever it appears.** A count, total, size, or cardinality is a claim even when it sits in step prose rather than in `budget` — "37 events are live", "40 files overlap", "seven call sites", "cited 11 times". Verify a quantity by **re-deriving it**, never by re-reading the citation next to it: a citation and the number it is offered in support of come from two different reads, and nothing joins them unless this stage does. A quantity with no list behind it is unverifiable by construction — record it as such and say so, because a step whose scope is a bare number is a step nobody can confirm is finished.

6. **Every current-state claim.** Assertions about what exists, what is already built, what shipped, what runs in production — "the surface does not exist", "the invite logic is already well built", "this event is live", "the job has never been deployed". Code is not the maximum source for these: resolve them against the repo AND, per the `## Data Sources` handling in §4, against the declared source whose `confirms:` hint matches. Two failure shapes to test for specifically, because both read as diligence: a "does not exist" grounded on one keyword grep (the concept may exist under another name), and an "already done" grounded on the absence of a TODO.

7. **Every load-bearing premise the spec relies on without stating.** Walk the chosen approach and name what has to be true for it to work at all — the property is addressable, the config file is the one actually read, the daemon may perform this operation, binaries exist to be protected. These are the claims nobody wrote down, so nothing downstream can select them for checking; enumerating them here is the only point in the pipeline where they become checkable. Add each to the set with `source: unstated premise` and verify it like any other. When a premise cannot be settled from code or a declared source, it enters §6 as a red-team risk rather than being dropped.

Record each claim with its source location, its kind (`citation` / `assumption` / `estimate` / `ticket-constraint` / `quantity` / `current-state` / `unstated-premise`) and the literal asserted fact. This bounded set is the input to §4 — every claim verified, none sampled. Spawn count scales with the claim set through §4's clustering, mirroring how `/geniro:review` verifies every survivor over a pre-bounded survivor set.

The kinds exist because the pipeline's other gates key on citation: a claim carrying a `file:line` gets checked by the Phase 7 validator's citation check and lands in this set through item 1, and every kind added in items 5-7 is one that was previously invisible to both. Verifying only what carries a citation verifies only the claims that were easy to write.

If the spec cites zero verifiable claims (e.g. a pure meta-step spec), skip §4 and note it in the scratch report; §6 and §7 still run.

## 4. Stage B — VERIFY claims (both modes)

Verify every cited claim, clustering claims that cite the same file into shared verifier spawns (see §Spawn batch). This stage reuses the `/geniro:review` per-finding verifier contract — read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` fully and mirror it, including its §4 spawn-batch shape (the cluster cap is canonical there). The two differences from `/geniro:review` are the polarity and the source of the "finding":

**Polarity flip.** The `/geniro:review` verifier asks "does the claimed DEFECT exist in the cited code?" The spec-claim verifier asks "is this asserted FACT true in the cited code?" Frame the spec claim as the thing under test; `validation: confirmed` means the fact holds, `validation: refuted` means the cited code contradicts the asserted fact, `validation: clarified` means the fact is partly true but the spec's framing is off (e.g. the column exists but is nullable when the step assumes NOT NULL).

**Refute by default.** Mirror the `/geniro:review` stance: the verifier's job is to disprove the claim, not to rubber-stamp it. A claim survives only when the cited code, read directly, bears it out.

### Input contract per verifier

Pre-inline isolated context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`. Each verifier receives ONLY its own cluster's claims — for each member claim, mirroring `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2:

- The claim: source location (Section 6 step / Section 4 assumption / frontmatter field) + the literal asserted fact.
- The cited code slice — read the file at the claim's `file:line` and inline it, using the slice cap in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2. For a Section 4 assumption or a frontmatter estimate with no `file:line`, grep the relevant symbol/table/path and inline the matched region within the same cap.
- **For a `quantity` claim, the derivation instead of a slice.** Pass the population the number is supposed to describe and require the verifier to re-derive the count from it — enumerate the matches, the rows, the sites — and return the list alongside the number. A quantity confirmed by re-reading the prose that asserts it is not confirmed. Where the population is itself unbounded (an open-ended sweep), the verdict is `unverified` with the reason, never `confirmed`.
- **For a `current-state` claim, the negative evidence too.** A claim that something does not exist is confirmed only by a search whose terms the verifier chose independently of the spec's — the spec's own grep is what produced the claim, so re-running it proves nothing. Require at least one alternative spelling, symbol, or adjacent concept to have been searched, and require the search to be named in the evidence.
- **For an `unstated-premise` claim, the consequence.** State what breaks if the premise is false, so a refutation carries its own blast radius into §6 rather than arriving as an isolated fact.
- 1-hop caller grep — `grep -rn "<symbol>"` for the cited symbol, capped per §2.
- 1-2 sibling tests for the same symbol — grep `test/ tests/ __tests__/ spec/`, capped per §2.
- **A matching declared-source result, when one applies.** Some claims assert state that lives outside the code — a tracker status, a DB row, a deploy / feature-live flag (the `workflow_refs[]` linked-ticket constraints of §3 (Stage A) item 4 and any Section 4 assumption about external state). For those, code is not the maximum source. Before the spawn, the orchestrator applies `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md`: if the project declares a `## Data Sources` entry whose `confirms:` hint matches the claim's domain, the orchestrator pre-runs that read-only-screened source and inlines its result into THIS verifier's evidence alongside the code slice. The verifier then confirms the claim against the maximum applicable set — code plus the declared source — not code alone. This is additional evidence to the same verifier, NOT a new verifier per source: the claim stays in its existing spawn. Fail-open — a source that's unavailable, can't be screened read-only, or errors is omitted with a one-line caveat in the verifier's input, never blocks the spawn. A code-only claim with no matching declared source runs exactly as before.

A verifier does NOT receive claims outside its cluster, the orchestrator's reasoning, or which spec section a claim came from beyond what it needs — isolated context prevents anchoring and sycophancy (the documented multi-judge failure mode). The cluster cap in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4 bounds the cross-claim anchoring surface a shared spawn opens.

### Output contract per verifier

Emit exactly one structured result, grounded per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`:

```yaml
validation: confirmed | refuted | clarified
confidence: 1 | 2 | 3 | 4 | 5
evidence: "<literal quote from the cited file:line that confirms or refutes the asserted fact>"
```

`evidence` is a literal quote from the cited file. A paraphrase-only verdict ("the code looks consistent with the claim") is refused and re-prompted — "the agent reported PASS" is not evidence per the evidence standard.

### Spawn batch

Group claims by cited file path per the spawn-batch shape in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4 — the cluster cap is canonical there; a same-file cluster amortizes one file read and one caller grep across its members. A claim without a `file:line` citation (a Section 4 assumption or frontmatter estimate verified by grep) spawns singly — it has no shared file slice to amortize, the same reason `/geniro:review`'s sentinel findings never cluster.

Compose the verifier prompt for `${CLAUDE_PLUGIN_ROOT}/agents/finding-verifier-agent.md` — frame each spec claim as a finding body and state the polarity flip ("verify the asserted FACT is true, not that a defect exists") in the prompt. The agent's input contract already covers this shape: it takes a cluster of claim-like bodies (a solo claim is the degenerate one-member cluster) plus cited slice, caller search, and sibling tests, and returns one `validation / confidence / evidence` block per claim, keyed by source location, on either polarity. The polarity lives in the prompt framing, never in the agent's schema.

Spawn via the runtime-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (prefixed `geniro:finding-verifier-agent` → bare → general-purpose-with-body). OMIT `model=` so verifiers inherit the orchestrator's tier per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Send ALL verifier spawns in ONE assistant response — separate turns serialize execution and double wall-time; the parallel-spawn invariant applies here exactly as in `/geniro:review` Phase 4.2.

Aggregate: any `refuted` claim is a defect; `clarified` is a soft defect (the spec's framing needs a fix); `confirmed` claims pass. A claim that no source — code or declared — could confirm is recorded as unverified/unconfirmed (handled by the existing disposition, never silently accepted as fact). Record each result in the scratch report.

### Deep mode — 3× verify + majority (`DEEP: true`)

When the caller passes `DEEP: true`, each cited claim gets **3 independent verifiers**, run inside an internal `Workflow(...)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/deep-mode.md` (observe its §4 mandatory mitigations — raw JSON not schema, re-assert the read-only contract in every prompt, OMIT `model=`, path constants outside template literals). Clustering applies to the single-pass batch only — deep mode verifies each claim individually, mirroring `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4's deep-mode rule. Each verifier receives the identical isolated input a single-pass verifier gets for that claim (the claim + cited slice + caller grep + sibling tests); independence is load-bearing, so a verifier never sees the others' votes. Aggregate per claim by majority:

- Tally the three dispositions across the parseable votes.
- ≥2 `refuted` → the claim is a **hard defect** (`refuted`).
- else ≥2 `clarified` → the claim is a **soft defect** (`clarified`) — the spec's framing needs a fix. Single-pass treats any `clarified` as a soft defect, so a `clarified` majority must surface one too: collapsing it into a pass would make deep mode WEAKER than single-pass, which the floor invariant (deep-mode.md §5) forbids.
- else → the claim **passes** (`confirmed`).
- A verifier whose raw output won't parse **abstains** — counts toward neither side; the ≥2 thresholds are over the parseable votes. If <2 parseable votes remain (≥2 abstained), quorum fails → run ONE fresh single-pass verifier for that claim and take its verdict (deep-mode.md §5 ladder).

The verdict feeds §7 exactly as the single-pass result does — deep mode changes the vote count, not the downstream handling. If the workflow errors or agent registration fails, fail-safe to the single-pass batch above and note `Deep mode couldn't run the extra spec-check passes — fell back to a single pass.` in the scratch report (deep-mode.md §5).

## 5. Stage C — the approach is not re-opened here

This helper never generates competing approaches, in either mode. Approach search and comparison belong to the caller's own approach phase, which runs earlier, with the user in the loop and an independent codebase-grounded critic already weighing feasibility — by the time a spec reaches this pass the user has picked an approach and approved the sections built on it.

What survives is the signal, not the search: a `re-plan` verdict (§7) comes from a refuted load-bearing claim or a blocking red-team finding — evidence that the chosen approach cannot work — never from a freshly-invented competitor scoring higher on a rubric.

## 6. Stage D — RED-TEAM the chosen approach (both modes)

Red-team the spec's chosen approach against its own stated objective and the verified-claim results from §4. Hunt for:

- A headline mechanism that carries no actual weight — present in the prose, load-bearing in the framing, but inert in the design (the dead-weight-mechanism defect class).
- A predicate, filter, or migration that operates on an empty or wrong set (the zero-rows-matched defect class).
- An estimate that is order-of-magnitude wrong once the verified facts are applied (the write-volume-miscount defect class).
- A step whose stated precondition is refuted by a §4 result — the step cannot execute as written.
- Missing rollback/recovery for a step that mutates durable state.

Classify each red-team finding as **blocking** (the approach cannot proceed as written) or **non-blocking** (a hardening fix that does not invalidate the approach). Record findings with the file:line or §4 result that grounds each one — a red-team finding without a concrete anchor is a hypothesis, not a defect.

## 7. Stage E — SYNTHESIZE the verdict

One judge reads the §4 verification results and the §6 red-team findings, and emits a single verdict. The judge weighs a borderline red-team risk against `EFFORT_TIER` — a Big task tolerates less residual risk than a Trivial one. Ground the verdict per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`: every defect cited in the verdict carries the literal file:line quote or §4 result that supports it.

**plan mode** — one of:
- `keep` — no refuted claims, no blocking red-team finding. The spec is sound as written.
- `keep-with-modifications` — `clarified`/non-blocking findings exist; list the specific fixes to fold into the spec.
- `re-plan` — a refuted load-bearing claim or a blocking red-team finding invalidates the chosen approach. The spec needs re-authoring at the approach level.

**implement mode** — one of:
- `clean` — every claim confirmed, no blocking red-team finding.
- `defects-found` — ≥1 claim refuted OR a blocking red-team finding exists.

## 8. Verdict handling per MODE

**plan mode.** The helper hardens the spec but does NOT approve it. On `keep-with-modifications`, the calling skill re-authors the affected spec sections to fold the fixes in and re-runs its own validator. On `re-plan`, the calling skill re-enters its approach-generation phase. The verdict then feeds the human approval gate — the human approves the hardened spec, not this helper.

**implement mode.** Do NOT rewrite the spec — it is the user's approved artifact and rewriting an upstream producer's durable file would force a cross-producer schema lockstep. Verify FACTS; never re-open the approved DESIGN DECISION.

**Record every refuted claim in state.md, and keep recording them after this pass ends.** Not rewriting the spec is correct; leaving the refutation only in chat is not. Append one entry per refuted or clarified claim to the calling skill's state.md `## Spec Divergences` body section via `atomic_state_write`: the claim as the spec states it, what the code actually shows, and the evidence quote.

Keep the section live for the rest of the run. A claim is just as refuted when a failing test, a rendered screen, or the user's own push-back disproves it mid-implementation as when a verifier does here — and those arrive after this pass has finished, which is exactly when the record stops being written. Every later consumer reads this section rather than re-deriving it: the PR body and the final report, which otherwise restate the spec's number as measured fact, and any `/geniro:review` that loads the spec as plan context and would score the implementation against a claim already known to be false. The failure this prevents is narrow and real — a figure disproved mid-run, corrected in conversation, and then written into a public pull request under a sentence promising every number was measured.

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

## 8.5 Re-entry — a spec that changed after a pass owes another one

**Every edit to spec content re-enters this helper with `SCOPE: changed-only` before the spec reaches an approval gate.** That covers all three edit paths: the keep-with-modifications fixes this helper's own verdict folds in, the calling skill's validator auto-revision rounds, and each round of user-requested changes at the approval gate.

The rule exists because the two checks are not interchangeable and only one of them was re-running. A structural validator re-reads shape — sections present, citations formatted, schema keys complete — and a re-authored spec passes it trivially, because re-authoring preserves shape by construction. Nothing in that pass reads code. So a spec could be fact-checked once, then legitimately rewritten (by this helper's own fixes, or by up to three rounds of user revisions), and reach approval with every added sentence unverified while reporting a clean validator. Observed outcome: a red-team verdict forces a spec rewrite, and the **newly authored** step — the one written in response to the strongest objection, and therefore the least examined — is the step the implementation later refutes.

Deciding what is "changed": diff the current spec against the copy in `<TASK_DIR>/.spec-challenge-out.md` from the previous pass. A claim is in scope when it is new, when its asserted fact changed, or when its citation moved. A claim whose text is byte-identical and whose cited file has not been written since the last pass carries its previous verdict forward — record the carry-forward explicitly rather than silently reusing it, so the scratch report shows what was re-checked and what was inherited.

Two bounds keep this from looping. Re-entry does not itself trigger further re-entry when its verdict folds in no new content — a pass that returns `keep` / `clean` ends the chain. And the caller's existing max-3-revision-round cap governs the outer loop unchanged; re-entry rides inside a round rather than adding rounds.

## 9. Echo contract

Print one plain-English line per stage as it runs, so the user can see the pass progress. Plain English — no internal stage letters or schema versions:

- Extract: `Challenging the spec — found <N> cited claims to verify against the code.`
- Verify: `Verifying <N> cited claims against the code...`
- Red-team: `Red-teaming the chosen approach for dead-weight mechanisms, empty predicates, and miscounted estimates...`
- Synthesize: `Verdict: <plain verdict> — <one-line reason>.`

On a clean implement-mode pass, the final line is the only user-visible output: `Spec checks out against the current code — proceeding.`

## 10. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "This is a Trivial task — skip the challenge to save time." | Every caller invokes on every spec-driven run, so there is no tier for which skipping is the contract. A small spec with one wrong `file:line` is the cheap-but-fatal case the pass exists to catch; the cost is bounded to the spec's cited claims, which for a small spec is a small batch. Tier calibrates the judge's risk tolerance, not whether the pass runs. |
| "The spec was just written/approved, so its claims are probably correct — confirm them." | "Probably correct" is the exact posture the pass refutes. The three defects that motivated this pass all lived in an approved spec that read as plausible. Re-read the cited code; a claim survives only when the code bears it out. |
| "Verifying every cited claim is too many spawns — sample the load-bearing ones." | The claim set is already pre-bounded to file:line citations + assumptions + estimates, and same-file claims already share spawns (§4 Spawn batch), so spawn count is sub-linear in claim count. Wall-time is ~max(spawn-time) because the batch is parallel. Sampling reintroduces the miss the pass eliminates. |
| "A verifier said the claim looks consistent — that's a confirm." | "Looks consistent" is a paraphrase, not evidence. The output contract requires a literal quote from the cited file. Refuse the paraphrase-only verdict and re-prompt — the evidence standard forbids reasoning-as-evidence. |
| "In implement mode a claim is refuted, so I'll just fix the spec and keep going." | Implement mode does not rewrite the user's approved spec — that re-opens a signed-off design and forces a producer-schema lockstep. Fire the AskUserQuestion and let the user choose proceed / fix-via-plan / abort. The helper verifies facts; the user owns the design. |
| "The implement-mode pass came back clean — I'll surface a confirmation question anyway." | A question with nothing to decide is noise and breaks the always-WAIT-restraint norm. On a clean pass, emit the silent advisory line and proceed. Reserve the AUQ for a real refuted-claim-or-blocking-risk decision. |
| "I'll fold the keep-with-modifications fixes in plan mode but skip re-running the validator." | The calling skill's validator is what guarantees the folded edits did not break the spec's schema. Skipping it ships an unvalidated spec into the human approval gate, defeating the harden-before-approve purpose. Re-run it after folding. |
| "The chosen approach may not be the best one — generate two competitors here and score them head-to-head." | Not this pass's job (§5). The caller's approach phase already searched the field with the user present and a codebase-grounded critic weighing feasibility; by here the user has picked an approach and approved the sections resting on it. Competitors invented at the last gate re-open a settled decision on a rubric rather than on evidence, and cost the most on exactly the runs that need this pass least. A `re-plan` still fires — off a refuted load-bearing claim or a blocking red-team finding. |
| "The red-team found a risk but I can't pin it to a file:line — report it anyway." | A red-team finding without a concrete anchor (file:line or a §4 result) is a hypothesis. Unanchored findings inflate the defect count and erode trust in the verdict. Anchor it or drop it. |
| "Pass the full spec to each verifier so it has complete context." | Shared context anchors verifiers toward agreement — the documented multi-judge failure mode. Each verifier sees ONLY its one claim plus the isolated cited slice, caller grep, and sibling tests. Independence is load-bearing. |
| "I can settle this claim faster by reading the cited lines myself than by spawning a verifier." | You wrote the claim, so you pick the span that shows it — and a span chosen to display a fact rarely contains the branch that refutes it. Observed twice: a 19-line window anchored on the cited line, excluding the short-circuit eight lines above that decided the behavior; and a self-check reporting "all three confirmed" on a passage that says the opposite of what the claim asserted, which then hardened into a `forbidden_actions` entry. A verifier reading cold picks its own span. Speed is not the constraint here — every claim in the batch verifies in parallel. |
| "The claim is about something outside the code, so there is nothing to verify against." | External state is where the most expensive wrong claims live — what shipped, what is live, what has ever been deployed. Check the repo's own evidence for it (a submit config, a lockfile, a committed native directory) and the project's declared `## Data Sources` before exempting anything. Record a genuinely unreachable fact as `unverified` and carry it into §6 as a risk; an exemption is a verdict of last resort, not a category. |

## 11. Definition of Done

The stages above define the procedure; these are the exit gates that stay checkable once the pass is over.

- [ ] Every extracted claim got its own verdict from the parallel verifier batch (claims clustered per §4 Spawn batch, all spawns in ONE assistant response), each verifier seeing only its cluster's isolated slices — and every returned verdict carries a literal quote from the cited file, never a paraphrase.
- [ ] Every red-team finding is anchored to a file:line or a §4 result; an unanchorable one was dropped rather than reported.
- [ ] plan mode: keep-with-modifications fixes are folded into the spec, the calling skill re-ran its validator afterwards, and this helper issued no approval.
- [ ] implement mode: the spec is byte-identical to what it was on entry; the proceed / fix / abort AUQ fired only on `defects-found`, and its pick is in `approvals[]`.
- [ ] One plain-English echo line per stage that ran.
