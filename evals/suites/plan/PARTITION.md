# `/plan` suite — dev vs held-out partition

Two files, one skill-creator schema (`{skill_name, evals:[{id, prompt, expected_output, files[], expectations[]}]}`):

| File | Partition | The candidate is tuned against it? | Gates promotion? |
|---|---|---|---|
| `evals.json` | **dev** | **Yes** — iterate the skill against these | No |
| `holdout.json` | **held-out** | **No** — never read while iterating | **Yes** |

## Why a held-out partition exists

The maintainer iterates `/plan` against the suite, then promotes on it — which **overfits the skill to its own eval**. Reserving tasks the candidate is never tuned against, and gating promotion on that held-out partition, closes the p-hacking that `attempt_no` alone does not (plan §11, §15, decision 11).

This is a **net-new, independently-motivated control** (Anthropic's "build evaluations" held-out-test-set guidance), **not** skill-creator's 60/40 split — that split is its *trigger-classifier / description-optimization* train/test partition (`run_loop.py`, stratified by `should_trigger`), a different mechanism with no held-out **quality**-eval precedent (plan §3, §11).

## Discipline

- **Do not read `holdout.json` while iterating the skill.** Treat it as a locked exam. Reading the held-out tasks to debug a regression silently converts them into dev tasks and destroys the control.
- A promotion verdict is only valid when the **primary metric clears its task-clustered CI on the held-out partition** (plan §6 step 7, §9).
- The ids are namespaced (dev `1..99`, held-out `101+`) so a row's task id alone tells you which partition produced it.

## Task count

This is the **bootstrap** set (6 dev + 3 held-out). The target is **20–50 distinct tasks per skill mined from real regression history** (`MEMORY.md`, the git log of fix commits, past CI incidents) — distinct *tasks* are the diversity axis, not trials-per-task (the variance axis). Growing toward that count, and the A-vs-A null calibration that sizes trials-per-task, is Phase D work (plan §11, decision 4). A tight CI on this small a sample is **deceptively narrow** and will not generalize.
