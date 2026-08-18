# Evidence standard

Authoritative for evidence-attached findings, completion claims, and reviewer-agent CRITICAL/HIGH dispositions.

This file is the single source of truth. Skills cite this file — the schema and the forbidden-phrases list live only here.

## Contents

- Why this exists — the three hallucinated-success failure modes
- When evidence is required — the claim classes that need a block
- Evidence Block schema — the verbatim shape, plus §What counts as an artifact (the six kinds) and §Evidence ladder (how far one reaches)
- Forbidden phrases — the tokens a claim may not carry unbacked, and scoping a claim to its command
- Anti-rationalization

## Why this exists

LLM orchestrators and subagents reliably hallucinate success when not held to captured artifacts. Three observed failure modes:

- An agent claims "tests pass" without ever running `pytest` (or the project's test command) — the PASS is inferred from the diff, not from a green run.
- An orchestrator carries an earlier phase's PASS forward after Edit/Write mutations have invalidated it — the green it is citing no longer reflects the current tree.
- A reviewer agent claims "the build is broken on main" without running the build — the claim is reasoning-from-the-diff, not observation.

Evidence Block schema + the cross-phase carry rule + per-skill consumption gates are the layered defense.

## When evidence is required

- Any "done", "passing", "validated", "ready to ship", "shipped" claim by the orchestrator or any subagent.
- Every CRITICAL or HIGH finding emitted by reviewer agents (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`). MEDIUM findings should attach evidence when available. A CRITICAL or HIGH without evidence is still admitted at the Phase 4.1 gate on severity alone (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5) — this standard binds at the post-verification step instead: the Phase 4.2 verifier is what supplies the missing quote, so an admitted-but-unevidenced finding is expected to carry evidence by the time it reaches the handoff, not at emit-time.
- Every hypothesis confirmation in `/geniro:debug` — debug consumes this artifact-kind contract per its loop invariant #6.
- Any PASS carried across a phase boundary. A build/lint/test PASS observed in an earlier phase stands as evidence only while nothing has changed since it was captured — any `Edit`/`Write`, a different `HEAD`, a different command, or a non-clean exit from the agent that reported it means re-run rather than carry. A PASS is a pre-mutation snapshot, not a clock.
- Any memory write claiming `trust: verified` — the captured-artifact bar governs L2 learnings too; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` § Evidence bar for `trust: verified`.

## Evidence Block schema

Every claim that requires evidence attaches this block in the verbatim shape below — the fixed shape is what lets downstream readers find the command, the exit code, and the tail:

```
## Evidence Block
Command: <verbatim command, no paraphrase>
Exit code: <integer>
Tail (last 3 lines):
  <line N-2>
  <line N-1>
  <line N>
```

### What counts as an artifact

The kinds below are the complete set. A claim requiring evidence is backed by one of them; anything outside this table is a hypothesis, not an artifact. Cite this section by name rather than re-listing the kinds — a second copy of the list is what drifts.

| # | Kind | Example |
|---|---|---|
| 1 | Captured command output (stdout/stderr + exit code) | `pnpm test src/cache/user.test.ts → exit 1, AssertionError: ...` |
| 2 | File:line citation with verified snippet (orchestrator re-read confirms the text at that range) | `src/cache/user.ts:42-58` snippet pasted |
| 3 | Log line or stack trace from the running system | `2026-04-01T12:34Z ERROR ... NullPointerException at ...` |
| 4 | Query result against the actual datastore | `SELECT count(*) FROM sessions WHERE user_id=42 → 0 rows` |
| 5 | User-provided artifact (screenshot, log paste, captured request body, env-var dump) | user pastes the request body that triggered the bug |
| 6 | External documented fact, cited by resolvable source URL and quoted at the point of use | upstream changelog entry / RFC clause / vendor doc paragraph, with the URL |

Kind 6 covers claims about the world outside the repo, where no local probe can settle the question. It admits only what a reader can re-open and check: a URL that resolves plus the quoted passage the claim rests on. A remembered fact, a summarized page, or a URL without the quote is a hypothesis — the failure mode is a confidently-worded recollection that no longer matches what the source says. It is also what a Phase 4.2 finding verifier cites for a claim the repo's own code cannot settle; trigger and resolution order: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §2.5.

### Evidence ladder — how far the artifact reaches

The kinds above are a set, not a ranking. They say what counts as an artifact; they say nothing about how much any one of them settles. Two findings can both carry a legal artifact and be nowhere near equally settled: a failing test that flips when the suspected cause is removed is close to certain, while a vendor changelog quote is someone else's report about a system nobody here observed. Both are evidence. They do not deserve the same confidence, and today they read identically.

| Rung | What you have |
|---|---|
| 1 | You ran a probe whose result differs depending on which reading is true, and it came back |
| 2 | You observed the behavior in the running system, without being able to reproduce it on demand |
| 3 | You read the source of truth directly and quoted the passage the claim rests on |
| 4 | Someone else captured the artifact and handed it to you |
| 5 | The fact is documented outside this system and you quoted it |

The ordering is for a **causal** claim — why something behaves the way it does. For a claim about what a file says, reading that file and quoting it IS rung 1; nothing sits closer to it. Rank against the claim, not against the table.

Report the rung alongside the block: `Evidence-rung: <n> — <what a higher rung would have taken>`.

The second half is the point. A rung on its own reads as a grade. A rung plus the missing step tells the reader whether the gap is closable or was simply not attempted — "rung 3, reproducing it needs a seeded tenant this environment has no way to create" and "rung 3, no probe attempted" are the same rung and call for opposite decisions. Naming the missing step is also what stops the rung from becoming a place to settle: written down, "no probe attempted" is visibly a choice rather than a limit.

Reasoning, "the symptom matches", "the agent reported PASS", and "the user described it verbally" are NOT evidence — they are hypotheses that still need verification. Symptom-matching is correlation; only a captured artifact (kind 1, 3, or 4) confirms causation. An artifact showing that every failing case shares an attribute establishes a discriminator, not a cause; before that reading reaches a deliverable, run the one probe whose result differs depending on which reading is true.

**A negative result is evidence only after the probe is shown able to return a positive.** Before reporting "there is no X" or "that window is clean", run the same probe against a case that must match — a known-present value, a time range with known activity — and cite that positive alongside the empty result. Without it, an empty result establishes that the probe found nothing, not that nothing is there.

A passing-test claim serves the same underlying requirement — show that the probe fired — and adds one condition on top of kind 1: the tail must show a non-zero observed test count (e.g. "N passed", "N tests", "N collected"), not just exit code 0. vitest, jest, and pytest exit 0 when zero test files match ("No test files found" / "no tests ran"), so a green exit with no collected tests is a false-green for a *passing* claim — the count is what shows the probe fired. Capture the run summary line carrying the count, not the exit code alone.

**A limit on your own reach is a claim and carries the same artifact requirement.** Attempt the read once with the tools you have and cite the failure before routing it to the user — the missing-data gates open on a failed attempt, not on an assumption, and the environment this session can reach — the repo, its logs, its configured services — is yours to probe before declaring the data out of reach.

**Enforcement lives in consumption, not in a hook.** This standard is enforced where evidence is produced and read: every reviewer-agent finding requires an Evidence Block at emit-time, and an orchestrator re-runs validation itself rather than trusting a prior PASS report. Nothing inspects a completion claim after the fact, so an unbacked one is never caught later — the block has to be attached when the claim is written. TDD order (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`) follows the same rule: an unenforced convention the orchestrator holds itself to, not a mechanical gate.

## Forbidden phrases

Do NOT use these tokens without an attached Evidence Block in the same message:

- `"Great!"`, `"Perfect!"`, `"Done!"` — performative success without proof.
- `"ready to ship"`, `"all tests pass"`, `"validation complete"`, `"shipped"` — completion claims without proof.

Replace with the captured Evidence Block + a one-line summary that cites the exit code and tail.

**Scope the claim to what the command covered.** State a check claim at the width of the command that produced it — a vet run over two packages supports "vet passes on the logger package and one service", not "vet passes"; an artifact covering the verified subset of an open checklist supports "all HIGH-severity cells verified live; 13 lower-severity items tracked", not "verification is complete". The claim keeps that width in every artifact it lands in: chat, ship report, commit message, PR body. A claim wider than its Evidence Block outruns its own proof, and a reader of the PR cannot see which command ran — an unscoped claim is a forbidden phrase even with an Evidence Block attached.

Where the project declares a `## Verification Surface`, read that width off the declaration instead of inferring it: the entry matching the command that ran carries the does-not-cover clause the claim is stated at, and a criterion no entry covers is reported as uncovered rather than absorbed into the nearest green command. Contract: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-surface.md`. Absent the block, scope from the command itself as above.

Uncertainty markers (`"should"`, `"probably"`, `"seems to"`) are weak completion language too, and they are authoring guidance rather than a prohibition — a benign sentence like "Should I run tests?" carries one without claiming anything.

## Anti-rationalization

| Rationalization | Counter |
|---|---|
| "I ran the tests 5 minutes ago, that PASS still applies." | Any `Edit` or `Write` since that run invalidates it, as does a different `HEAD` or a different command. A PASS is a pre-mutation snapshot, not a clock — elapsed time is not what makes it stale. |
| "The build is obviously fine, I don't need to run it." | If you didn't run it in this message, you cannot claim it passes. Reasoning-from-the-diff is the exact failure mode the standard exists to prevent. |
| "I'll cite an old log file as evidence." | Evidence must be captured in this message (or be a user-provided artifact in this turn). Stale artifacts don't count — the tree may have mutated since. |
| "The agent reported PASS, I'll forward that as evidence." | Subagent PASS reports are inputs, not evidence. The orchestrator MUST attach the captured command output (or independently re-run) before forwarding the claim. |
| "It's a CRITICAL finding but I'm confident — I'll skip the Evidence Block." | Confidence does not substitute for artifact, and the reviewer-agent contract still requires attaching one at emit-time. Skipping it does not get the finding dropped — CRITICAL/HIGH are admitted on severity alone (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/severity-calibration.md` §5) — it just reaches the Phase 4.2 verifier thinly cited, making re-grounding it the verifier's job instead of yours. |
| "The test command exited 0, so the tests pass." | Exit 0 is not proof of a passing run — vitest, jest, and pytest exit 0 on "No test files found" / zero collected. A passing claim requires the observed count in the tail ("N passed"). A backgrounded run's exit code especially must be paired with the summary line; a clipped or empty summary is not a green. |
