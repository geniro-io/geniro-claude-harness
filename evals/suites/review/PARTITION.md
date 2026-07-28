# `/review` suite — dev vs held-out partition

Two files, one skill-creator schema (`{skill_name, evals:[{id, prompt, expected_output, files[], expectations[]}]}`).

| File | Partition | The candidate is tuned against it? | Gates promotion? |
|---|---|---|---|
| `evals.json` | **dev** | **Yes** — iterate the skill against these | No |
| `holdout.json` | **held-out** | **No** — never read while iterating | **Yes** |

The rationale for the split, and the discipline it demands, is the same one `suites/plan/PARTITION.md` states — read it there rather than from a second copy that can drift. Two things are specific to this suite.

## What these tasks are chosen to detect

`/review` carries the plugin's largest always-loaded body, so it absorbs the most risk from any instruction trim. Every task here targets a behavior whose silent loss costs the user something concrete rather than a stylistic preference: a dimension that stops firing, a finding admitted without evidence, a finding that never gets independently verified, a post that happens without its gate, a "keep it quick" hint that quietly narrows coverage.

A trim that removes a restatement should move none of these. A trim that removes a gate should move one of them sharply. That asymmetry is the whole point of the suite — it is what separates "this file got shorter" from "this file got worse".

## The no-side-effects requirement

`/review` can post to a real pull request. A suite run must never do that. Before running this suite, confirm the harness's auto-answer policy denies the "Post Draft PR review" pick — `approve-default-v1` approves by default and would post. Task 4 exists specifically to catch a run that posts without its gate, and it can only test that safely if the gate's answer is a deny.

## Task count

This is the **bootstrap** set (6 dev + 3 held-out), sized to prove the `/review` capture path end to end, not to generalize. The target is 20-50 distinct tasks per skill mined from real regression history — the git log of fix commits and past incidents are the source, and distinct *tasks* are the diversity axis, not trials-per-task. A tight confidence interval on nine tasks is deceptively narrow.
