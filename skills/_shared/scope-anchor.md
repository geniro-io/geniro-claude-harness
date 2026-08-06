# Scope anchor

Canonical rule for what a skill operates on when the user does not explicitly name a target. Referenced from `/geniro:review`, `/geniro:debug`, `/geniro:refactor`, `/geniro:implement`, `/geniro:onboard`, and `/geniro:investigate`. Define the rule here once; do not paste it into the calling skills.

## Contents

- The rule — what a skill operates on when no target is named
- Subagent spawn anchor — the WORKTREE slot every codebase-work spawn carries
- Forbidden subagent-spawn moves
- Forbidden discovery moves (when no target was supplied)
- Anti-rationalization

## The rule

**Default scope is the current cwd's working tree on the currently checked-out branch.**

Concretely, when no target is supplied in `$ARGUMENTS`:

1. Use `git rev-parse --show-toplevel` to anchor to the current worktree's root.
2. Use `git branch --show-current` to anchor to the currently checked-out branch. Returns empty in detached-HEAD state — fall through to `git rev-parse HEAD` (commit SHA) as the equality anchor when this happens. Spawn-anchor slots and verify-instructions follow the same fallback.
3. Targetable artifacts in priority order:
 - **Working tree (highest priority):** unstaged + staged changes (`git status --short`, `git diff`, `git diff --cached`).
 - **Branch diff (only if working tree is clean):** diff of the current branch against its **base branch** — `git diff <base>...HEAD`. The base branch is resolved as follows, in order:
 - (a) if the invocation supplies an explicit PR ref, the base is `gh pr view <ref> --json baseRefName`'s `baseRefName` (the actual base of that PR, which is NOT necessarily `main`);
 - (b) otherwise, the base is the remote's default branch via `git symbolic-ref --short refs/remotes/origin/HEAD` (typically `origin/main` or `origin/master` — whichever the remote actually points HEAD at);
 - (c) if no remote or `origin/HEAD` is unset, fall back to whichever of local `main` / `master` exists.
 - **No-op (if the branch is even with the base):** there is nothing to review — report "no changes to review against <base>" and stop. Do NOT widen the search to other branches or PRs to invent something to operate on.
4. The user's `pwd` at skill invocation is authoritative — even if a sibling worktree exists, do NOT switch to it.

## Subagent spawn anchor

A subagent's starting cwd is runtime-dependent. Claude Code passes the parent's working directory down ([Claude Code docs](https://code.claude.com/docs/en/sub-agents)); other runtimes start it at the workspace root, which is a different tree on a different branch whenever the orchestrator works in a linked worktree or on a PR head. The subagent cannot detect this — nothing in its context says which tree it belongs to — so unanchored it reviews, edits, or tests the wrong code and reports success.

**Rule.** Every `Agent(...)` spawn-prompt template that performs codebase work (review, edit, test, diff) carries one slot, populated by the orchestrator per `## The rule` above:

```
WORKTREE: [from `git rev-parse --show-toplevel`]
```

…plus one line in the prompt body:

```
Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
```

Every call carries the `cd`, not just the first: within a subagent `cd` does not persist between Bash calls ([Claude Code docs](https://code.claude.com/docs/en/sub-agents)), so a one-time `cd` is undone by the next call.

The path clause covers what `cd` cannot reach. `Read` / `Glob` / `Grep` resolve a relative path against the subagent's own cwd, not against any shell, so a discovery glob the agent writes itself scans the wrong tree while every Bash call is correctly anchored — the quiet half of the same failure.

The subagent verifies nothing beyond this. `WORKTREE` is absolute, so `cd` either lands in the right tree or fails loudly on its own; a subagent re-deriving the orchestrator's branch decision adds no information, and across a parallel batch re-derives it once per agent.

Pass `BRANCH:` only into a spawn whose agent contract actually reads it (`${CLAUDE_PLUGIN_ROOT}/agents/adversarial-tester-agent.md` reports it as the source branch). Elsewhere it is an unread slot.

**Exempt spawn sites.** Pure transformer spawns that never invoke Bash, never read files outside paths the orchestrator pre-inlines, and never touch git (e.g., a `model="haiku"` agent converting a structured spec into prose) do not need the anchor — cwd cannot matter if nothing reads it.

## Forbidden subagent-spawn moves

| Move | Why it's forbidden |
|---|---|
| `Agent(..., isolation: "worktree", ...)` from a parent that is itself in a non-primary worktree | Claude Code bug [#47548](https://github.com/anthropics/claude-code/issues/47548): `git worktree add` silently fails and the subagent operates on the parent's worktree, **switching the parent's branch** to the subagent's. No documented mitigation — do not use `isolation: "worktree"` when the parent session is in a worktree. |
| `Agent(..., isolation: "worktree", ...)` even from the primary worktree, expecting the subagent to inherit the primary's branch | Claude Code bug [#50850](https://github.com/anthropics/claude-code/issues/50850): the new isolated worktree branches from `origin/main`, not the parent's HEAD. The subagent operates on stale code. Do not pass `isolation:`; propagate `WORKTREE` explicitly via the spawn anchor instead. |

## Forbidden discovery moves (when no target was supplied)

The following commands are **target-discovery** commands. They invent a target the user did not name, and they are forbidden in the default-no-args path. Treat them as the same class of mistake as overwriting the user's uncommitted work:

- `gh pr list` to **invent a target** — discovering open PRs to review/inspect when the user supplied no target. PR mode triggers ONLY on an explicit PR ref (`#N`, bare digits, or full GitHub PR URL) supplied in `$ARGUMENTS`. **Carve-out:** read-only `gh pr list` / `gh pr view` / `gh pr diff` calls that gather peer-PR context for an *already-named* target (e.g., the review skill's peer-PR scout, or `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/pr-metadata-criteria.md`'s `gh pr list --state merged --limit 5` convention-prefix sample) are NOT discovery — they consume an existing target rather than invent one. The ban is on target-invention, not on context-gathering for a user-named target (the **Carve-out** sentence above is the canonical statement; the closing paragraph below restates the same principle for all forbidden moves).
- `gh pr view --json …` without an explicit PR ref — the `<ref>` argument must come from the user, never from `gh pr list` output.
- `git checkout <other-branch>` / `git switch <other-branch>` — moving the user off their current branch.
- `git worktree add` / `EnterWorktree(...)` — entering or creating a different worktree (the only sanctioned worktree-entry call site is the Step 0 workspace-setup AUQ ('Git worktree' option) in `/geniro:implement`, which guards against re-entry — see SKILL.md there).
- `git stash` / `git stash pop` — the user's working tree is the input, not state to be hidden.

If the user **explicitly** names a target (a PR ref, a branch name, a diff range, a file list), follow it. The forbidden list applies only to the default-no-args path where the skill would otherwise have to invent something.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just `gh pr list` to show the user options — it's helpful" | The user already told you the target by where they invoked you. Listing PRs forces them to re-pick something they already implicitly chose. The "no args" path is a target, not an absence. |
| "There are no changes on the current branch, so I'll fall back to the latest PR" | If there's nothing to operate on, report that and stop. Inventing a target is worse than no-op-ing. |
| "The user's cwd is a worktree but main has more recent changes — I'll switch" | The cwd is authoritative. Different worktrees represent intentionally separate workstreams. Never switch. |
| "I'll silently `git fetch` and compare against `origin/main` even if there's no remote" | Read-only `git fetch` is fine when a remote exists; if there is no remote, fall back to local `main` ref. Never invent a remote. |
| "Harness Auto Mode is active, so I'll preface my scope decision with 'Auto mode → proceeding without prompting'" | Scope-anchor is deterministic — there is no user gate to skip. Importing harness Auto Mode framing implies a non-existent question and makes users think the skill has an auto mode it does not (most skills don't). Just report the resolved target. |
