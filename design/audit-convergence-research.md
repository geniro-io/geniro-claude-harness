# Why whole-repo audits didn't converge — the measurements behind the redesign

Tracked deliberately. `design/scratch/` is gitignored, so research written there dies with the
container. `design/` is out of `/audit-plugin`'s default scope, so this file is evidence, never a
subject of review.

Status: **acted on.** The suppression ledger and the cosmetic tier were removed and the reviewers
were narrowed; this file is why. It is not a changelog of the edit — read the skill for current
behavior.

## What was measured

### Findings per round never trended down

| Round | Findings | Files changed | Lines |
|---|---|---|---|
| 2026-07-29 | 138 | 140 | +3584 / −1079 |
| 2026-07-30 | 121 | 97 | +4165 / −1630 |
| 2026-08-07 | 87 | 95 | +2108 / −1268 |
| 2026-08-07 | 130 | 124 | +1228 / −912 |
| r8 | 38 | 61 | +726 / −157 |
| r9 | 97 | 84 | +1024 / −385 |

The repo holds 329 tracked `.md`/`.sh` files. Each round rewrote a quarter to a third of it.

### The audit was its own largest input

Of the 84 files r9 touched, **64 (76%) had already been edited by an earlier audit round.**

### The ledger's key could not hold

15 rows entered r9. **Exactly one matched** — a 6.7% hit rate against 97 findings raised.

Both halves of the key were LLM-produced and neither was stable:

- **The fingerprint** hashed ~100 characters of context around the cited line, and a `fixed` row was
  recorded with the *pre-fix* fingerprint. The fix then rewrote that passage, so the key addressed
  nothing. Only `rejected` and `accepted` rows could match at all — 26 of 42.
- **The class slug** was worse. **28 distinct slugs across 42 rows**, nearly all singletons, against
  a contract requiring verbatim reuse across rounds. The ledger's own documentation named the
  problem it could not solve: "an LLM reviewer has no stable rule id."

### Audit pull requests carried no signal beyond the diff

PRs #75, #76, #77, #81, #92, #93, #96. Checked #92, #93, #96 for reviews and comments: **zero of
each**, every one opened and merged within 2–20 minutes by the same agent that wrote the report. A
PR held a title, a body by that same agent, and a diff already in local git — which is why reading
PR history was considered as a ledger replacement and rejected.

### Most findings were never taste questions

Classifying r9's 97 findings by whether a command could decide them: ~11 of 11 T0/T1 (guard bypasses,
found by executing probes — an exhaustive vector × guard matrix decides these), ~16 of 19 T3 (both
sides of every "file says 5, actual is 6" claim are in the repo), ~25 of 46 T4, ~1 of 17 T5.
**Roughly 55–60% were mechanically decidable**, and were being asked of an LLM.

## Why it repeated

1. **The audit produced the next audit's input.** 76% file overlap round-over-round. Every prose edit
   is fresh surface for the next reviewer reading it cold.
2. **Prose has no oracle.** "These could merge" is unfalsifiable and therefore inexhaustible. Prose
   edits survived at 6%, code edits at 86%.
3. **LLM non-determinism.** Same reviewer, same file, different finding set — up to 15% accuracy
   variation and a 70% best-to-worst gap ([arXiv:2502.20747](https://arxiv.org/html/2502.20747)),
   not reducible to decoding settings ([arXiv:2408.04667](https://arxiv.org/pdf/2408.04667)). Fatal
   for any content-keyed memory: the same concern reworded is a different key.
4. **Self-referential evaluation.** One model wrote the rules, followed them, and judged compliance.
   Self-improvement holds where answers are checkable and degrades where they are not
   ([arXiv:2607.07663](https://arxiv.org/pdf/2607.07663)).

## What the evidence pointed at

Determinism is a property of the **question**, not of the memory. An open question has an unbounded
answer set and any sample of it varies; a closed question has one answer every run. The ledger was
memory bolted onto an open question, which is why no repair to it would have worked.

The proof was already in the repo: the D1 deterministic battery — 1,629 lines of lint, 54 suites —
never churned. A check that passes keeps passing and needs no memory to stay quiet. Not one of its
findings ever appeared in the ledger.

So the reviewers' most valuable output is a **check**, not a fix, and their remaining job is the
question no command can answer: whether a mechanic should exist at all.

One caveat that shaped the scope: a lint freezes today's taste into CI, where an LLM's varying taste
at least sometimes stays quiet. Only classes decidable *without* taste are candidates. And the
distinction is hard-versus-advisory, not lint-versus-reviewer — `heading-case` appeared in the ledger
despite `lint-prose-and-links.sh` already checking it, because that check is advisory and the next
reviewer re-raised it as prose.

Industry precedent for the residual whole-repo problem, not adopted here but the obvious next lever:
Semgrep's [diff-aware scanning](https://docs.semgrep.dev/faq/comparisons/sonarqube) and SonarQube's
[incremental analysis](https://docs.sonarsource.com/sonarqube-server/2026.1/discovering/code-analysis/incremental-analysis)
exist because a full sweep of a legacy corpus always produces a wall of findings.
