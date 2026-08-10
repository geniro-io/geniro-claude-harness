## D5 — Logic & syntax correctness

**Scope split:** 5a (markdown logic) covers `skills/`, `agents/`, `.claude/skills/`; 5b (shell logic) covers `hooks/`, `lib/`, `tests/`, `cursor/hooks/`, `scripts/`. Spawn as two reviewers. **Method:** LLM reviewers; every claim must survive a re-read of the cited code.

5a checks (markdown):
1. **Contradictions.** Phase A states X, phase B assumes not-X; an invariant the steps violate; a budget table disagreeing with the step that enforces it.
2. **Unfireable gates.** Conditions comparing against fields no schema carries; gates whose trigger can never occur; branches conditioned on a flag, mode, or option the skill no longer ships (check `argument-hint` and the modifier table, not only the body); gates an earlier gate always pre-empts; AUQ flows with no path to one of their documented outcomes.
3. **Tool-surface mismatches.** Body instructs using a tool absent from `allowed-tools`; AskUserQuestion specs exceeding 4 options; spawn prompts using slots never filled.
4. **State-machine holes.** `phase:`/`status:` enum values written but never read (or read but never written); terminal states unhandled by resume logic.
5. **Broken procedures.** Steps referencing outputs of steps that don't produce them; counters that reset on compaction while the skill claims compaction-safety.
6. **Turn-completion seams.** A step that emits content and then owes a tool call — a gate render followed by its question, a spawn batch followed by its collection, an echo attesting to a Read — where the wording lets the run come to rest between the two. The underlying model has a documented early-stopping failure mode on exactly this seam: it ends on a statement of intent and the promised call never happens, which reads as a completed step from every angle except the user's. Flag a step whose obligation spans a turn boundary with nothing closing it, and one that states intent as its own completion criterion. The canonical closure and its recovery are in `skills/_shared/gate-rendering.md` §Turn-completion guard and `skills/_shared/loop-invariants.md` — flag the site that lacks it, never the contract.

5b checks (shell):
1. **Quoting & word-splitting** on user-controlled or file-derived values; unquoted globs.
2. **Regex correctness** in guard hooks — false negatives (bypassable patterns, line-by-line matching of multi-line constructs) and false positives (legit commands blocked).
3. **Exit-code semantics** — hooks must exit 2 to block / 0 to allow per their contract; helpers' documented rc values match reality.
4. **Trap/lock hygiene** — locks released on SIGINT/SIGTERM; mktemp cleaned; partial writes impossible (atomic mv).
5. **Portability** — BSD/GNU divergence (`grep -P`, `stat -c`, `sed -i`, `tac`); `#!/usr/bin/env bash`.
6. **Input validation** — env-var overrides sanitized; malformed JSON stdin handled (fail-open vs fail-closed chosen deliberately and matching the hook's safety role).

Tier mapping: bypassable guard / data-loss path → T0; behavioral bug → T1; latent-but-unreachable → T4.

