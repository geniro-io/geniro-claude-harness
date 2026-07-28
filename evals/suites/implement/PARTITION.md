# `/implement` suite — dev vs held-out partition

Two files, one skill-creator schema (`{skill_name, evals:[{id, prompt, expected_output, files[], expectations[]}]}`).

| File | Partition | The candidate is tuned against it? | Gates promotion? |
|---|---|---|---|
| `evals.json` | **dev** | **Yes** — iterate the skill against these | No |
| `holdout.json` | **held-out** | **No** — never read while iterating | **Yes** |

The rationale for the split, and the discipline it demands, is the same one `suites/plan/PARTITION.md` states — read it there rather than from a second copy that can drift. Three things are specific to this suite.

## What these tasks are chosen to detect

`/implement` is the only skill that writes code and the only one that can take an irreversible action, so its failure modes are the expensive ones. The tasks target two classes. First, a gate that stops firing: pushing without the ship question, treating the word "push" in the original request as an approval, editing a test instead of the code under it. Second, a phase that degrades quietly: a self-review that spawns serially, a fix loop that never escalates, a final report claiming work the diff does not contain.

## Why this skill is the most sensitive to instruction changes

At roughly 13,000 words, `/implement` loses most of its body at the first compaction — Claude Code re-attaches only the first ~5,000 tokens. A run long enough to compact is therefore executing later phases from a summary rather than from the phase's own steps. Tasks 102 and 103 are the ones most likely to surface that: both are long enough to compact, and both check whether a rule stated below the re-attach boundary still holds afterwards.

## The no-side-effects requirement

`/implement` can commit, push, and open pull requests. A suite run must never do any of those. Before running this suite, confirm the harness's auto-answer policy DENIES the ship-mode question — `approve-default-v1` approves by default, which on this suite means a real push. Task 101 tests the gate directly and is only safe to run under a denying policy.

## Task count

This is the **bootstrap** set (6 dev + 3 held-out), sized to prove the `/implement` capture path end to end, not to generalize. The target is 20-50 distinct tasks per skill mined from real regression history — the git log of fix commits and past incidents are the source, and distinct *tasks* are the diversity axis, not trials-per-task. A tight confidence interval on nine tasks is deceptively narrow.
