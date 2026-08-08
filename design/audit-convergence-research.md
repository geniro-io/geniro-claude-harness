# Why whole-repo audits don't converge — measurements and options

Tracked deliberately. `design/scratch/` is gitignored, so research written there dies with the
container — which is itself one of the findings below. `design/` is out of `/audit-plugin`'s default
scope, so this file is evidence for a decision, never a subject of review.

Status: **no decision taken.** Measurements are current as of r9 (2026-08-08); the options are
candidates, not a plan.

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

The repo holds 329 tracked `.md`/`.sh` files. Each round rewrites a quarter to a third of it.

### The audit is its own largest input

Of the 84 files r9 touched, **64 (76%) had already been edited by an earlier audit round.**

### The ledger's suppression almost never fires

15 rows entered r9. **Exactly one matched** (`implement/phase-1-analyze.md`, `dead-text`,
`accepted`) — a 6.7% hit rate against 97 findings raised.

The reason is structural, not a tuning problem. `ledger_fingerprint` keys on ~100 characters of
context around the cited line, and a `fixed` row is recorded with the **pre-fix** fingerprint. The
fix then rewrites that passage, so the key no longer addresses anything. Only `rejected` and
`accepted` rows — where the text is left untouched — can match at all. That is 26 of 42 rows; the
other 16 cannot suppress by construction.

### Audit pull requests carry no signal beyond the diff

PRs #75, #76, #77, #81, #92, #93, #96. Checked #92, #93, #96 for reviews and comments: **zero of
each.** Every one was opened and merged within 2–20 minutes by the same agent that wrote the report.
A PR therefore holds a title, a body written by that same agent, and a diff already present in local
git.

## Why it repeats

1. **The audit produces the next audit's input.** 76% file overlap round-over-round. Every prose
   edit is fresh surface for the next reviewer reading it cold. Positive feedback, not convergence.
2. **Prose has no oracle.** "These could merge", "this reads better" is unfalsifiable and therefore
   inexhaustible. This pipeline's own measurement: prose edits survive at 6%, code edits at 86%.
3. **LLM non-determinism.** Same reviewer, same file, different finding set — measured at up to 15%
   accuracy variation and a 70% best-to-worst gap for code review
   ([arXiv:2502.20747](https://arxiv.org/html/2502.20747)), and not reducible to decoding settings
   ([arXiv:2408.04667](https://arxiv.org/pdf/2408.04667)). Fatal for fingerprint keying: the same
   concern reworded and cited from a different line is a different key.
4. **Self-referential evaluation.** One model writes the rules, follows them, and judges compliance.
   Self-improvement holds where answers are checkable and degrades where they are not
   ([arXiv:2607.07663](https://arxiv.org/pdf/2607.07663)).
5. **Reports are discarded.** ~43 KB per round — the Filtered section, the per-dimension verdicts,
   the health summary — is gitignored and lost. The ledger is a lossy 7-column compression of it.

## Verdicts on two proposals

**Read past PRs to learn what was already reviewed — rejected.** The PRs are empty of human
judgment (0 reviews, 0 comments), and their only substance is a diff `git log` already serves
offline, in a fresh container, with no API round-trip. The coverage signal a PR would carry is
available more cheaply from local history.

**Delete the ledger in favour of PR history — rejected.** A PR records what was *changed*. It cannot
record what was *considered and declined*, which is the only class of row that suppresses anything
(26 of 42). With reports gitignored, the ledger is the sole store of negative decisions that
survives a round. Its hit rate is bad; its replacement candidate has none.

## Candidate remedies

| Option | Mechanism | Cost |
|---|---|---|
| Churn prior | For a no-oracle finding, consult local `git log` on the cited file; suppress by default when an audit fix touched it within the last N rounds, at the same bar as the 3-run rule | Small; offline; targets the measured 76% directly |
| Retain reports | Commit past reports (at minimum Filtered + verdicts) to a tracked, audit-excluded path | Small; reverses the memory loss in cause 5 |
| Fingerprint both sides | Record a `fixed` row with both pre-fix and post-fix fingerprints so a re-raise on the rewritten passage still matches | Small; recovers the 16 dead rows |
| Diff-scoped audit | Default the run to changes since the last audit tag; full sweep behind a flag. What Semgrep's [diff-aware scanning](https://docs.semgrep.dev/faq/comparisons/sonarqube) and SonarQube's [incremental analysis](https://docs.sonarsource.com/sonarqube-server/2026.1/discovering/code-analysis/incremental-analysis) do for the same problem | Large; changes `/audit-plugin`'s default behavior |

A whole-repo prose audit over 329 files will produce roughly a hundred findings every time. That is
a property of the question being asked, not a defect being detected.
