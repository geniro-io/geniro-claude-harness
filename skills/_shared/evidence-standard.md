# Evidence Standard

Authoritative for evidence-attached findings, completion claims, and reviewer-agent CRITICAL/HIGH dispositions.

This file is the single source of truth. Skills cite this file; do NOT inline-paste the schema or the forbidden-phrases list.

## Contents

- Why this exists — the three hallucinated-success failure modes
- When evidence is required — the claim classes that need a block
- Evidence Block schema — the verbatim shape, plus §What counts as an artifact (the five kinds)
- Forbidden phrases — the tokens the Stop hook scans, and scoping a claim to its command
- Stop hook reliability disclaimer — why the hook is a reminder, not the gate
- Anti-rationalization

## Why this exists

LLM orchestrators and subagents reliably hallucinate success when not held to captured artifacts. Three observed failure modes:

- An agent claims "tests pass" without ever running `pytest` (or the project's test command) — the PASS is inferred from the diff, not from a green run.
- An orchestrator carries a cached PASS across phases after Edit/Write mutations have invalidated it (the cache PASS no longer reflects the current tree).
- A reviewer agent claims "the build is broken on main" without running the build — the claim is reasoning-from-the-diff, not observation.

Evidence Block schema + verification cache invalidation rules + per-skill consumption gates are the layered defense.

## When evidence is required

- Any "done", "passing", "validated", "ready to ship", "shipped" claim by the orchestrator or any subagent.
- Every CRITICAL or HIGH finding emitted by reviewer agents (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`). MEDIUM findings should attach evidence when available; CRITICAL/HIGH without evidence are downgraded or dropped.
- Every hypothesis confirmation in `/geniro:debug` — debug consumes this artifact-kind contract per its loop invariant #6.
- Any cross-phase cache-PASS carry — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md`.
- Any memory write claiming `trust: verified` — the captured-artifact bar governs L2 learnings too; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` § Evidence bar for `trust: verified`.

## Evidence Block schema

Every claim that requires evidence attaches this block in the verbatim shape below — the fixed shape is what lets the Stop hook and every downstream reader find the command, the exit code, and the tail:

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

Kind 6 covers claims about the world outside the repo, where no local probe can settle the question. It admits only what a reader can re-open and check: a URL that resolves plus the quoted passage the claim rests on. A remembered fact, a summarized page, or a URL without the quote is a hypothesis — the failure mode is a confidently-worded recollection that no longer matches what the source says.

Reasoning, "the symptom matches", "the agent reported PASS", and "the user described it verbally" are NOT evidence — they are hypotheses that still need verification. Symptom-matching is correlation; only a captured artifact (kind 1, 3, or 4) confirms causation. An artifact showing that every failing case shares an attribute establishes a discriminator, not a cause; before that reading reaches a deliverable, run the one probe whose result differs depending on which reading is true.

**A negative result is evidence only after the probe is shown able to return a positive.** Before reporting "there is no X" or "that window is clean", run the same probe against a case that must match — a known-present value, a time range with known activity — and cite that positive alongside the empty result. Without it, an empty result establishes that the probe found nothing, not that nothing is there.

A passing-test claim serves the same underlying requirement — show that the probe fired — and adds one condition on top of kind 1: the tail must show a non-zero observed test count (e.g. "N passed", "N tests", "N collected"), not just exit code 0. vitest, jest, and pytest exit 0 when zero test files match ("No test files found" / "no tests ran"), so a green exit with no collected tests is a false-green for a *passing* claim — the count is what shows the probe fired. Capture the run summary line carrying the count, not the exit code alone.

**A limit on your own reach is a claim and carries the same artifact requirement.** Attempt the read once with the tools you have and cite the failure before routing it to the user — the missing-data gates open on a failed attempt, not on an assumption, and the environment this session can reach — the repo, its logs, its configured services — is yours to probe before declaring the data out of reach.

## Forbidden phrases

The `Stop` hook (`require-evidence-on-completion.sh`) scans final responses for these tokens. Do NOT use them without an attached Evidence Block in the same message:

- `"Great!"`, `"Perfect!"`, `"Done!"` — performative success without proof.
- `"ready to ship"`, `"all tests pass"`, `"validation complete"`, `"shipped"` — completion claims without proof.

Replace with the captured Evidence Block + a one-line summary that cites the exit code and tail.

**Scope the claim to what the command covered.** State a check claim at the width of the command that produced it — a vet run over two packages supports "vet passes on the logger package and one service", not "vet passes"; an artifact covering the verified subset of an open checklist supports "all HIGH-severity cells verified live; 13 lower-severity items tracked", not "verification is complete". The claim keeps that width in every artifact it lands in: chat, ship report, commit message, PR body. A claim wider than its Evidence Block outruns its own proof, and a reader of the PR cannot see which command ran — an unscoped claim is a forbidden phrase even with an Evidence Block attached.

Uncertainty markers (`"should"`, `"probably"`, `"seems to"`) are weak completion language too, but the hook does NOT scan them — they produced too many false positives on benign sentences ("Should I run tests?"). Treat them as authoring guidance, not an enforced gate.

## Stop hook reliability disclaimer

Stop hooks fire only approximately 50–80% of the time, so treat `require-evidence-on-completion.sh` as a soft reminder layer, not as the enforcement gate. PreToolUse `Edit|Write` is enforced by `enforce-tdd-order.sh`, which reads the state file at `.geniro/state/tdd/state-<slug>.md` per the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`. THAT pair (hook + state file) is the authoritative TDD-order enforcement; the Stop hook is warn-only. Analogously, the Evidence Standard's true enforcement is the per-skill consumption — every reviewer-agent finding requires an Evidence Block at emit-time, and orchestrators independently re-run validation per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` rather than trusting prior PASS reports.

## Anti-rationalization

| Rationalization | Counter |
|---|---|
| "I ran the tests 5 minutes ago, the cache PASS still applies." | See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` — any `Edit` or `Write` between cache-write and cache-read invalidates the PASS. The cache is not a clock; it is a pre-mutation snapshot. |
| "The build is obviously fine, I don't need to run it." | If you didn't run it in this message, you cannot claim it passes. Reasoning-from-the-diff is the exact failure mode the standard exists to prevent. |
| "I'll cite an old log file as evidence." | Evidence must be captured in this message (or be a user-provided artifact in this turn). Stale artifacts don't count — the tree may have mutated since. |
| "The agent reported PASS, I'll forward that as evidence." | Subagent PASS reports are inputs, not evidence. The orchestrator MUST attach the captured command output (or independently re-run per `verification-cache.md`) before forwarding the claim. |
| "It's a CRITICAL finding but I'm confident — I'll skip the Evidence Block." | Reviewer-agent findings without an Evidence Block are downgraded or dropped at the relevance-filter step. Confidence does not substitute for artifact. |
| "The test command exited 0, so the tests pass." | Exit 0 is not proof of a passing run — vitest, jest, and pytest exit 0 on "No test files found" / zero collected. A passing claim requires the observed count in the tail ("N passed"). A backgrounded run's exit code especially must be paired with the summary line; a clipped or empty summary is not a green. |
