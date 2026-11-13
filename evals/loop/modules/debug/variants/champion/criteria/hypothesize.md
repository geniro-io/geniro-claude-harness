# Debug Phase 1 — investigate

Phase file for `/geniro:debug`. The spine — invariants, budgets, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md`.

state.md `phase: investigate`. An entry-gate + context load plus an inner hypothesis-test loop. Exits to Phase 2 only when a hypothesis is confirmed, its Result: field cites an artifact per Evidence Standard, and the §1.6 independent verification confirms the root cause (or fails open with the unverified disclosure).

## Contents

- §1.1 Load instructions, snapshot and past learnings · §1.2 Observe & repro · §1.3 Build feedback loop · §1.4 Hypothesize
- §1.5 Test each hypothesis + missing-data gate + external-dependency hypothesis · §1.6 Isolate root cause · §1.7 Stall escalation gate
- Infrastructure investigation · Isolation techniques · Stall diagnosis taxonomy · Tool surface

### 1.1 Load instructions, project snapshot and past learnings

On Phase 1 entry, in order:

1. **Refresh custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: debug`, `LOAD_TIER: pipeline`, `MODE: refresh`. Compaction since the previous load may have silently dropped the rules — re-Read all files and echo per the helper's contract.
2. **Load project snapshot.** `source "${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh" && load_semantic` — default top-2 (`_project.md` + `_CODEBASE_MAP.md`); surface any fingerprint drift it reports.
3. **Query past learnings.** Run the file query `source "${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh" && query_learnings --tag <inferred from $ARGUMENTS> --limit 5` (tags only: `--scope` never matches a task path). Under a declared `## Memory Backend` block routing `learnings`, route it per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/query-learnings.md` §"Memory backend override": the orchestrator reads the backend inline, merged with the file query under `mirror`, in place of it under `replace`. Skipped if $ARGUMENTS too generic to infer tags. A matching prior diagnosis primes Phase 1 hypotheses.
**surfacing convention:** when results include `discarded_hypothesis` entries, display them with a distinct label:
```
Past investigations in this scope ruled out:
- <ext.hypothesis> (tested <ts> by <ext.tested_by>)
Past diagnoses:
- <summary> (fixed <ts>)
```
Surface these at hypothesis formation: do not re-form a hypothesis equivalent to a ruled-out one without explicit re-justification.
4. **Reconcile custom instructions, snapshot and past learnings** — `resolve-conflicts(L2/L3/L4 loaded)` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md`. Echo lines per each helper's mandatory echo contract.

5. **Workflow refs read (when spec.md is in scope).** When `$ARGUMENTS` points to a spec.md path OR a planning task-dir, parse spec.md frontmatter `workflow_refs[]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workflow-refs-schema.md` — that file owns which schema versions a reader accepts and the rule that every consumer but /geniro:implement is tracker-read-only. Use the cached `status` field as hypothesis-priming context (in-flight vs already-shipped code). On `m5-v3` the cached parent-epic status and sibling sub-task statuses are also available to prime hypotheses (e.g. a sibling already shipped a related fix, so the regression may live in shared code). Skipped silently when no spec.md is in scope.

### 1.2 Observe & repro

- Reproduce the bug consistently and capture what the failure emits. Identify what changed. Record exact repro steps.
- **If repro is unclear/missing:** `AskUserQuestion` with header "Repro info" — 2-4 concrete options (environment / steps to trigger / expected vs actual behavior). Do NOT guess.
- **Check open PRs for an existing fix.** Before forming hypotheses, scan open PRs for one that may already fix this bug (ranked by overlap with the suspect / recently-changed files + symptom-keyword match in the PR title/body). Surface matches as hypothesis-priming context; on a strong hit (file overlap AND keyword match) fire an `AskUserQuestion` (header "Existing fix") — review that PR's diff first / test it as a hypothesis / keep investigating — and persist the pick to `approvals[]` category `existing_fix_pr`. Read-only, fail-open, Scientific Mode only (Adversarial Mode's diff-only flow has no symptom or suspect files to key off). Probe mechanics and unreachable-source handling: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/prior-work-scan.md`. Debug-specific wiring: `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §8.

Persist to state.md body sections `## Symptom` and `## Reproduction Steps` (per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

### 1.3 Build feedback loop

**This is the step that decides the run.** Everything else is mechanical: a tight signal that goes red on this bug is what hypothesis tests, bisection and instrumentation consume, and reading code is no substitute for one. Spend disproportionate effort here.

Read credentials from environment variables, never a literal in the command, since the command is saved to the handoff. When a human must drive the repro, give them a bash script of step / capture prompts so the loop stays structured; sign-in stays a human step.

**Intermittent?** Raise the reproduction rate (loop the trigger 100×, add load, widen timing windows, pin time, RNG seed and filesystem state): 50% is debuggable, 1% is not. Record the attempt and its outcome in `## Feedback Loop` — the §2.4 repro-infeasible escape hatch opens only after that record exists.

The loop is done when one command, already run at least once with its invocation and captured output recorded, is:
- **Red-capable** — drives the real bug path and asserts the user's exact symptom: red on this bug, green once fixed. "Runs without erroring" does not count; the wrong bug yields the wrong fix.
- **Deterministic** — the same failure signature across 3 runs; for an intermittent bug, a pinned, high reproduction rate per the paragraph above. Three different signatures mean a flake or two bugs: note it in state.md.
- **Fast** — ≤30s, ideally ≤5s.
- **Agent-runnable** — unattended, apart from the step script.
- **Captured** — Evidence Standard kind 1, 3, 4, or 5 (command output, not the static file:line citation of kind 2). "I see it crash" is not captured.

Reading code to build a theory before this command exists is the tell: return here.

When repeated attempts keep landing on a different failure signature, or produce no captured signal at all, there is no loop. Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a redacted captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop. Ask it as one `AskUserQuestion`, header "Repro signal", one option per item. Route the answer: (a) or (b) → back to §1.3 with what arrived; (c) → §1.5 tagged local logging, reverted at Cleanup, or instrumentation the user applies themselves; a decline or empty answer → the §1.7 stall gate, whose Abandon goes to Phase 3 with partial findings.

**Minimise.** Once the loop is red on the right bug, cut inputs, config, data and steps one at a time, re-running after each cut, until removing any remaining element turns the loop green. Minimising can drop a second cause, so keep the command as first run beside the minimised one — /geniro:implement re-runs the original after the fix.

Persist to state.md `## Feedback Loop`: Original command (un-minimised) / Command (the minimised form) / Expected output / Actual output / Re-run cost / Determinism (including any rate-raising attempt + outcome for intermittent bugs).

> **NOT the reproduction test.** That is a unit/integration test in the project framework that ships with the fix as the regression guard. The feedback loop is a scratch signal, reverted at Cleanup; its original command survives as the handoff's `original_repro` (§3.1).

### 1.4 Hypothesize

Based on Observation + Feedback Loop output, form **2-3 competing hypotheses**. Each must be testable against the feedback loop — each hypothesis test toggles one variable, re-runs the loop, and observes whether the captured signature changes. State each hypothesis as a falsifiable prediction — "if <X> is the cause, then <toggling Y> changes the captured signature in <way Z>". A hypothesis whose prediction you cannot state is a vibe, not a hypothesis — sharpen it or discard it.

**Consider infrastructure causes alongside code causes** per § Infrastructure investigation below — when the symptom matches any signal on that section's list, at least one hypothesis has to be an infrastructure hypothesis.

Persist to state.md `## Hypotheses` body section, one block per hypothesis (Hypothesis / Evidence For / Evidence Against / Status: pending → testing → confirmed | rejected | inconclusive / Test Plan / Result — per the body-section schema in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §2).

**Render the ranked hypothesis list to chat before testing begins** — plain narration, NOT a gate: do not fire AskUserQuestion and do not block for a response. The user often re-ranks the list instantly from domain knowledge or names a hypothesis already ruled out, and a correction that arrives before the first test costs nothing.

> **Inconclusive** means the test could not distinguish whether the hypothesis is true or false. It is NOT a rejection — you need a better test or more data.

### 1.5 Test each hypothesis + missing-data gate

- Design a minimal test per hypothesis: the Test Plan names the applicable sources for the fact under test — declared `## Data Sources` entries whose `confirms:` hint matches, plus the built-in sources (code, logs, the running system) — resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §3 before falling back to a fresh probe. The test must produce a captured run artifact per Evidence Standard (kind 1, 3, 4, or 5 — command output, log line, query result, or user-provided artifact; not the static file:line citation of kind 2).
- **External-dependency hypothesis:** when the fact under test is behavior of a dependency, an external API, a runtime, or a version change — something this repo's code cannot settle — resolve it in the 3-tier order canonical at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.5 (installed source on disk → registry/official docs → web search), stopping at the first source that settles it; a hypothesis about this repo's own code stays on the sources above, unchanged. Cross-check any external claim against the version this project actually has installed, read from the lockfile — a fix in a later release is not evidence about the version running here.
- Add logging, breakpoints, or unit tests to gather evidence. Tag every debug log line with one unique per-run prefix (e.g. `[DBG-a4f2]`) — §3.4 cleanup then reduces to a single grep. For performance symptoms, logs are the wrong instrument: capture a baseline measurement first (timing harness, profiler, query plan — § Isolation techniques) and test hypotheses against the number.
- Do NOT implement a fix yet — you're gathering data.
- **Missing-data gate:** when a probe you actually ran — including a data-source resolution per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §3 — failed to reach the data the test requires (production logs, runtime state, third-party API responses, DB rows behind credentials, screenshots), do NOT mark the hypothesis inconclusive by default. `AskUserQuestion` with header "Missing data": 2-4 concrete options for the specific artifact needed, the paste options, an "I don't have it" path, and — when the data sits behind a source the session can't currently reach — a sign-in-and-retry option phrased as an offer, not a diagnosis (the run cannot tell "not signed in" from "not configured"). An empty or absent answer (no interactive user present) is unresolved, never a user decision. On any unresolved outcome — "I don't have it", "Skip this hypothesis", a retry that still can't reach the source, an empty answer — append an `open_questions[]` entry with `atomic_state_append_list_item` (`id: q<N>`, `source: phase-1-missing-data-gate`, `related_hypotheses: [<H-ID>]`, `status: unresolved`; `question`, `context` and `options` taken from the prompt, the probe that failed and the set just offered), shaped per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 `open_questions` so the §3.0 pre-gate renders it in full rather than the terse fallback. Write the Result: as an unconfirmed fact naming the source (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/data-sources.md` §5), not a bare "inconclusive".
- Record results: confirmed / rejected / inconclusive. Every Result: field cites an artifact per Evidence Standard — a "confirmed" carrying a narrative-only Result is rejected, because the next phase builds a fix proposal on it.

**Record a past learning for each rejected hypothesis.** For each hypothesis transitioning to `Status: rejected` (eliminated by a test that produced contradicting evidence), call `emit-learning` with type `discarded_hypothesis`, required `ext.{hypothesis, evidence_against, tested_by}`, trust `verified`. Scope = the file/module the hypothesis targeted. The emit is per-rejection (multiple rejections in one Phase 1 = multiple emits). Canonical payload shape: `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §9.

**Sliding-window cap.** `discarded_hypothesis` is a capped bookkeeping type: before each emit, prune per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §Sliding-window caps on bookkeeping types, which owns the window size, the flip-then-append order and the locking — uncapped, discarded-hypothesis chatter drowns out `diagnosis` entries at retrieval.

`rejected` is a normal outcome of hypothesis testing — emit fires in the happy path. `inconclusive` does NOT emit (the data is ambiguous; recording it would seed noise). `confirmed` does NOT emit a `discarded_hypothesis` (it emits a `diagnosis` later at Phase 3 §3.3).

state.md `phase: investigate` throughout. `## Hypotheses` body section grows iteratively.

### 1.6 Isolate root cause

Once a hypothesis is confirmed, identify the exact code location and trace the flow to why the bug happens, not just where (§ Isolation techniques). Tag the finding `[ROOT-CAUSE]` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`; `[UNKNOWN]` means the loop never closed (stall gate), `[SYMPTOM]` means re-enter with a new hypothesis.

**Verify the root cause independently.** The confirming test came from the same context that isolated this location, so spawn one `geniro:finding-verifier-agent` (SKILL.md §Subagent model tiering, **session**; never a fan-out) to re-read the confirmed `Result:` evidence cold and judge whether it supports the `[ROOT-CAUSE]` claim. `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2 / §3.6 / §6 apply, except the finding body is only the title, the isolated `path:lines`, the `[ROOT-CAUSE]` tag, and the `Result:` evidence verbatim. Satisfy the rest of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md`: the prompt states the verifier is read-only (the spawn takes no tool-restriction argument) and carries the output schema.

The verdict follows `${CLAUDE_PLUGIN_ROOT}/agents/finding-verifier-agent.md` § Output schema (`validation: confirmed | refuted | clarified`, `evidence: <literal quote>`):

- `confirmed` → Phase 2.
- `refuted` or `clarified` → `Status:` back to `testing`; re-enter §1.5 with the verifier's `evidence` as the next test (outside §1.7's counter). A second consecutive `refuted`/`clarified` on the same claim ends the loop, mirroring §2.5's 2-attempt cap: write `phase: phase-1-verification-stalled` with timestamp + both verdicts via `atomic_state_write` first, so a compaction resume re-surfaces this gate rather than re-running both spawns. Render both verdicts to chat per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, then `AskUserQuestion` (header "Root cause"): try a different hypothesis (§1.4, `phase: investigate`, resets the count) / proceed with `Validation: unverified` and `Verification-evidence` naming both disputed verdicts / abort (`phase: aborted`, terminal). Persist the pick to `approvals[]` category `verification_stalled`, `root_cause` as the disambiguator.
- Spawn failure (ladder exhausted, or still empty after one inherit-tier retry) → Phase 2 with `Validation: unverified` and one chat line: "Couldn't independently verify the root cause; proceeding on the investigation's own evidence".

Persist `Validation: confirmed | unverified` and `Verification-evidence` (the quote, or the disclosed reason) to state.md `## Root Cause`; §3.4 Cleanup deletes it only after §3.1 has read it into the handoff.

### 1.7 Stall escalation gate

When the hypothesis loop fails to converge — defined as **5 inconclusive hypothesis tests across all hypotheses** (enough attempts for the scientific-method loop to isolate a cause, few enough that a genuinely stuck investigation surfaces to the user before more turns are burned) — fire the stall gate before declaring the bug unsolvable:

1. **Do not silently report "cannot determine cause".**
2. Apply the 8-category diagnose-by-missing-component taxonomy (`## Stall diagnosis taxonomy` below).
3. **Render the investigation status to chat first** per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` § Message-first rendering — what was tested (per-hypothesis results as a short `☐`/`✔` checklist) and which component categories remain unexplored — then fire the lean `AskUserQuestion` with header "Stall": the most likely missing-component categories plus an explicit "Abandon — present partial findings" option (past the question tool's option cap, chain a second question per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Cap-extension). "Abort" comes via the AUQ "Other" option.
4. state.md marks `phase: phase-1-escalated` with timestamp + inconclusive-test count + categorized stall hypothesis. Transitions:
- User picks a surfaced missing-component category → `phase: investigate` (resume hypothesis loop with new data).
- User picks "Abandon — present partial findings" → write `phase: ship` (NOT the terminal yet) and proceed to Phase 3 with a stall-flagged findings summary; Phase 3 exit writes whichever terminal §3.2 resolves to. Writing the terminal at the gate would strand a compaction-resume as "complete" before the summary + handoff are produced.
- User picks "Abort" (via "Other") → `phase: aborted` (terminal).

**Persist the stall as an `open_questions[]` entry** — `atomic_state_append_list_item` on state.md frontmatter, mirrored to the body `## Open Questions` — with `id: q<N>`, `source: phase-1-stall-gate`, shaped per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §T2 `open_questions`: `question` the verbatim stall question, `context` the step-3 ☐/✔ checklist plus the categories still unexplored, `evidence` the citable Result of each checklist hypothesis (file/lines or command/log site, Result quoted verbatim), `options` the step-3 categories + Abandon, `related_hypotheses` the inconclusive IDs, `status: unresolved`. A picked category resolves it (`resolution.resolved_by: debug`, `resolution.asked_in_phase: phase-1-stall-gate`); Abandon or Abort leaves it `unresolved` for the §3.0 pre-gate to surface again.

---

## Infrastructure investigation

When the symptom matches any signal in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §3, form at least one infrastructure hypothesis alongside the code hypotheses. That section owns the signal list, the investigation checklist, and the hypothesis quality bar — read it rather than deciding from memory which symptoms qualify.

---

## Isolation techniques

Pick the one technique the confirmed root cause calls for — never all three on the same hypothesis: binary search to narrow a large region, `git bisect` to find the regression range when a known-good revision exists, profiling for quantitative symptoms.

---

## Stall diagnosis taxonomy

When the §1.7 stall gate fires, classify the stall as a missing component (8-category taxonomy A-H: missing instruction / source-of-truth / tool / validator / permission rule / sandbox signal / eval / recovery path). Full table in `${CLAUDE_PLUGIN_ROOT}/skills/debug/debug-state-reference.md` §5; the rendering and persistence rules are §1.7 above.

---

## Tool surface

- Read / Grep / Glob, plus read-only Bash: `git status` / `log` / `diff` / `blame` / `bisect`, `gh pr list` / `view` / `diff` for the §1.2 open-PR scan, test re-runs without code edits, log inspection, profiler invocations, and third-party CLIs such as `psql -c` against a test DB when configured. Web search and fetch serve §1.5's external-dependency hypothesis. `AskUserQuestion`, and the declared memory backend's read tool.
- Edit / write for EXPERIMENTS only — debug scripts, logging statements, scratch test files, `.geniro/state/debug/<slug>/` artifacts.
- Subagent spawns: `codebase-research-agent` for codebase mapping and flow tracing (Loop Invariant S1); `finding-verifier-agent` for the §1.6 root-cause verification (always-on).
- Blocked: production-source writes and edits that are not reverted before handoff — permitted only as the reverted experiments above (tagged debug logging, scratch files); `git push`, `gh pr create`, branch switching beyond the Step 0.2 workspace pick.
