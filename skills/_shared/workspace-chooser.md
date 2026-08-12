# Workspace chooser — where a run does its work

Canonical contract for the start-of-work question that decides WHERE a run does its work: a new branch, the branch already checked out, a new worktree, or the current directory as-is. The option catalogue, the recommendation policy, and the persistence/ordering contract for this question were duplicated across three skills with divergent option labels, reconciled only by the `workspace` enum living in a fourth file — so a new consumer copying the nearest skill's version would widen the drift rather than close it. This file is the single point every consumer aligns to instead.

Consumers: `/geniro:implement` (Mode WORK-BASE — a run that will author the change it ships), `/geniro:review` (Mode INSPECT-HERE — a run that only inspects code that already exists), `/geniro:debug` (Mode INSPECT-HERE), and `/geniro:plan` (records a pick into `launch_config` at plan time without acting on it — the pick is applied later, by whichever `/geniro:implement` run consumes the spec).

## Contents

- §1 Signals
- §2 The option catalogue
- §3 Mode WORK-BASE
- §4 Mode INSPECT-HERE
- §5 Recommendation policy
- §6 Persistence and ordering
- §7 Anti-rationalization

---

## 1. Signals

The question reads the shared detection sequence in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/workspace-signals.md` — collect all four signals before deciding, never a divergent per-consumer reading, since implement ↔ review ↔ debug hand work to each other and depend on reading the same worktree the same way.

## 2. The option catalogue

Four canonical actions, keyed to the `workspace` enum in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §The block:

| Canonical action | Enum value | What it does |
|---|---|---|
| New branch | `new-branch` | Creates a new branch and moves the run onto it. |
| Current branch | `current-branch` | Continues on the branch already checked out. No branch or worktree is created. |
| Worktree | `worktree` | Creates a new worktree (and its branch) so the run's work is isolated from the worktree it started in. |
| Here | `here` | Works in the current directory exactly as it is — no branch or worktree action. |

A consumer renders its own question wording around these four — "New feature branch" vs. "New branch", "Git worktree" vs. "Create review worktree" — but every rendered option resolves to exactly one row above, and the enum value recorded is what round-trips through `launch_config` losslessly, not the literal label string. `header: "Workspace"` is fixed across every consumer regardless of wording.

A consuming skill may offer a SUBSET of the four rows — `/geniro:review` offers two (Worktree, Current branch), `/geniro:implement` offers three interactively (New branch, Current branch, Worktree; `here` never appears as one of those three live AUQ options, but it is reachable as a live `$ARGUMENTS` modifier (`no-worktree` / `here`, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`) that skips the question outright — typed directly or carried forward by a `/geniro:plan`-authored `launch_config` pre-set) — but may not add a fifth action or an option that satisfies none of the four rows. Inventing an option outside this table is how the labels drifted in the first place; extending the catalogue itself, not a per-skill workaround, is the fix when a consumer's real action doesn't fit.

## 3. Mode WORK-BASE

For a run that will AUTHOR the change that ships (`/geniro:implement`). A new branch or worktree is cut from the latest default-branch tip, not from wherever HEAD happens to sit — delegate to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §3 Mode FRESH-BASE for the mechanics.

## 4. Mode INSPECT-HERE

For a run that INSPECTS code that already exists (`/geniro:review`, `/geniro:debug`) rather than authoring what ships. Three rules govern it — the ones a Mode WORK-BASE-shaped copy of this question gets wrong:

1. **A created branch or worktree is cut from `HEAD`, not the default-branch tip.** Mode FRESH-BASE does not apply here. Relocating the new branch or worktree to the default tip would change the code under inspection, which is the one thing an inspection run must not do.
2. **A worktree does not carry uncommitted changes** — it checks out its branch fresh, independent of whatever is uncommitted in the worktree the run started from. `/geniro:debug` collects a dirty-tree signal ahead of this question (`baseline-dirty-paths`) and, when the tree is dirty, withholds the worktree option and says so plainly in the question text: the uncommitted work is frequently the very thing under inspection, and silently offering an option that would leave it behind is worse than not offering it — a branch created at `HEAD` in the current worktree carries the uncommitted changes forward instead. `/geniro:review` diverges: it collects no dirty-tree signal and always offers a `--detach` worktree cut at `HEAD` on a protected branch, paired with a non-worktree "review in place" option that keeps the dirty tree in view (`${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §0b rule 6). This is a documented divergence, not a gap — do not add a dirty-tree probe to `/geniro:review` to bring it in line with this rule.
3. **No offered option may change which commit is under inspection.** This is the invariant the two rules above serve. State it plainly so a future edit adding a fourth option to an inspection skill's subset has something concrete to fail against.

## 5. Recommendation policy

Exactly one option carries `(Recommended)`, appended to the label at render time — never baked into a template: the cited policy warns against leaving the question rudderless, and `/geniro:debug` and `/geniro:implement` both honor that by recommending exactly one option every time this question fires. The policy for which option earns it, and why the label is load-bearing, is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Recommended-label policy; apply it here rather than re-deriving it. `/geniro:review` is a documented exception: because review is read-only, neither worktree option is pre-selected as a forced default — its own rationale is in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md` §0b.

## 6. Persistence and ordering

- **Same write, two effects.** The pick persists to state.md `approvals[]` under a per-skill category (e.g. `review_workspace_setup`, `implement_workspace_setup`) AND rewrites state.md frontmatter `branch:` / `worktree:` to the new working tree — both inside the SAME `atomic_state_write`. A pick recorded without the frontmatter rewrite leaves a resume pointing at the tree the run left, not the tree it moved to.
- **Ordering.** The question runs before every other phase-entry call in its skill — no scope resolution, PR-side fetch, memory-layer load, or subagent spawn precedes it, because the pick decides which worktree the rest of the phase inspects. The one thing allowed to precede it is a targeted read of a single instruction (e.g. the project's branch-name-format rule, needed to validate a `new-branch` slug before offering it) — never the full custom-instructions load, which runs after the pick like everything else.
- **Freshness follows the pick.** Branch freshness runs AFTER the workspace decision is known and BEFORE the first edit, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-freshness.md` §1. A skill that ran freshness first was only ever correct by accident — it had no workspace decision yet to run it against.
- **Branch-keyed paths derive from the pick, not from a later read.** Any file path a run keys to a branch name — a handoff filename, a task-directory slug — is derived from the branch immediately after the pick settles, never from a fresh `git branch --show-current` read taken later in the run. The run may have moved worktrees since; a late re-read can silently key the path to the wrong branch.

## 7. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "I'll copy `/geniro:implement`'s option set into this inspection skill — it already covers new branch, current branch, and worktree." | §4 rule 1: a WORK-BASE catalogue cuts from the default-branch tip. Applied to an inspection run, that relocates the code under inspection — the one outcome an inspection run must never produce, regardless of which skill's option set it borrowed. |
| "The working tree is dirty, but a worktree gives a cleaner view — I'll offer it anyway and let the user decide." | §4 rule 2: the uncommitted work is frequently the very thing under inspection, and a worktree does not carry it. Offering an option that silently drops the subject of the review is worse than narrowing the choice; withhold it and say why. |
| "I'll just derive the label myself — 'Spin up a scratch branch' reads better here than any of the four rows." | §2: a friendlier label is fine, but it still has to resolve to one of the four catalogue rows. An option that doesn't is exactly how the current per-skill wording drifted apart before this file existed. |
| "I'll re-read the current branch at ship time instead of threading the Step-0 pick through — it's simpler than passing a variable." | §6: the run may have moved worktrees since the pick. A late `git branch --show-current` can key a handoff or state path to whatever branch happens to be checked out at that moment, not the one the run actually worked in. |
