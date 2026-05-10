# Evidence Standard

Authoritative for evidence-attached findings, completion claims, and reviewer-agent CRITICAL/HIGH dispositions. Consumers: `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` (hypothesis confirmation), `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` and `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` (every CRITICAL/HIGH finding), `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` and `${CLAUDE_PLUGIN_ROOT}/skills/follow-up/SKILL.md` (completion / Ship claims).

This file is the single source of truth. Skills cite this file; do NOT inline-paste the schema or the forbidden-phrases list.

## Why this exists

LLM orchestrators and sub-agents reliably hallucinate success when not held to captured artifacts. Three observed failure modes:

- An agent claims "tests pass" without ever running `pytest` (or the project's test command) — the PASS is inferred from the diff, not from a green run.
- An orchestrator carries a cached PASS across phases after Edit/Write mutations have invalidated it (the cache PASS no longer reflects the current tree).
- A reviewer agent claims "the build is broken on main" without running the build — the claim is reasoning-from-the-diff, not observation.

Evidence Block schema + verification cache invalidation rules + per-skill consumption gates are the layered defense.

## When evidence is required

- Any "done", "passing", "validated", "ready to ship", "shipped" claim by the orchestrator or any sub-agent.
- Every CRITICAL or HIGH finding emitted by reviewer agents (`${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md`). MEDIUM findings should attach evidence when available; CRITICAL/HIGH without evidence are downgraded or dropped.
- Every hypothesis confirmation in `/geniro:debug` (already enforced by the artifact-kind table in `${CLAUDE_PLUGIN_ROOT}/skills/debug/SKILL.md` § Evidence Standard).
- Any cross-phase cache-PASS carry — see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md`.

## Evidence Block schema

Every claim that requires evidence MUST attach this block, verbatim shape:

```
## Evidence Block
Command: <verbatim command, no paraphrase>
Exit code: <integer>
Tail (last 3 lines):
  <line N-2>
  <line N-1>
  <line N>
```

What counts as an artifact:

| # | Kind | Example |
|---|---|---|
| 1 | Captured command output (stdout/stderr + exit code) | `pnpm test src/cache/user.test.ts → exit 1, AssertionError: ...` |
| 2 | File:line citation with verified snippet (orchestrator re-read confirms the text at that range) | `src/cache/user.ts:42-58` snippet pasted |
| 3 | Log line or stack trace from the running system | `2026-04-01T12:34Z ERROR ... NullPointerException at ...` |
| 4 | Query result against the actual datastore | `SELECT count(*) FROM sessions WHERE user_id=42 → 0 rows` |
| 5 | User-provided artifact (screenshot, log paste, captured request body, env-var dump) | user pastes the request body that triggered the bug |

Reasoning, "the symptom matches", "the agent reported PASS", and "the user described it verbally" are NOT evidence — they are hypotheses that still need verification. Symptom-matching is correlation; only a captured artifact (kind 1, 3, or 4) confirms causation.

## Forbidden phrases

The `Stop` hook (`require-evidence-on-completion.sh`) scans final responses for these tokens. Do NOT use them without an attached Evidence Block in the same message:

- `"should"`, `"probably"`, `"seems to"` — uncertainty without verification.
- `"Great!"`, `"Perfect!"`, `"Done!"` — performative success without proof.
- `"ready to ship"`, `"all tests pass"`, `"validation complete"`, `"shipped"` — completion claims without proof.

Replace with the captured Evidence Block + a one-line summary that cites the exit code and tail.

## Stop hook reliability disclaimer

Stop hooks fire approximately 50–80% of the time per multi-framework data; ECC migrated AWAY from Stop hooks for enforcement after observing the same gap. Treat `require-evidence-on-completion.sh` as a soft reminder layer, not as the enforcement gate. PreToolUse `Edit|Write` is enforced by `enforce-tdd-order.sh`, which reads the state file at `.geniro/state/tdd/state-<slug>.md` per the procedure in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/tdd-cycle.md`. THAT pair (hook + state file) is the authoritative TDD-order enforcement; the Stop hook is warn-only. Analogously, the Evidence Standard's true enforcement is the per-skill consumption — every reviewer-agent finding requires an Evidence Block at emit-time, and orchestrators independently re-run validation per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` rather than trusting prior PASS reports.

## Anti-rationalization

| Rationalization | Counter |
|---|---|
| "I ran the tests 5 minutes ago, the cache PASS still applies." | See `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` — any `Edit` or `Write` between cache-write and cache-read invalidates the PASS. The cache is not a clock; it is a pre-mutation snapshot. |
| "The build is obviously fine, I don't need to run it." | If you didn't run it in this message, you cannot claim it passes. Reasoning-from-the-diff is the exact failure mode the standard exists to prevent. |
| "I'll cite an old log file as evidence." | Evidence must be captured in this message (or be a user-provided artifact in this turn). Stale artifacts don't count — the tree may have mutated since. |
| "The agent reported PASS, I'll forward that as evidence." | Sub-agent PASS reports are inputs, not evidence. The orchestrator MUST attach the captured command output (or independently re-run per `verification-cache.md`) before forwarding the claim. |
| "It's a CRITICAL finding but I'm confident — I'll skip the Evidence Block." | Reviewer-agent findings without an Evidence Block are downgraded or dropped at the relevance-filter step. Confidence does not substitute for artifact. |

## Definition of Done

A consumer skill correctly applies the Evidence Standard when:

- [ ] Every completion claim ("done", "passing", "validated", "shipped", "ready to ship") in orchestrator output is followed by an Evidence Block in the same message.
- [ ] Every CRITICAL/HIGH reviewer-agent finding carries an Evidence Block at emit-time (relevance-filter drops findings missing it).
- [ ] No forbidden-phrase token appears in final output without an accompanying Evidence Block.
- [ ] Cross-phase PASS carries cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/verification-cache.md` and verify no intervening mutation.
- [ ] Evidence is captured in the current message — no stale artifacts, no reasoning-only claims.
