# Scope Anchor

Canonical rule for what a skill operates on when the user does not explicitly name a target. Referenced from `/geniro:review`, `/geniro:debug`, `/geniro:follow-up`, `/geniro:refactor`, and `/geniro:deep-simplify`. Define the rule here once; do not paste it into the calling skills.

## The rule

**Default scope is the current cwd's working tree on the currently checked-out branch.**

Concretely, when no target is supplied in `$ARGUMENTS`:

1. Use `git rev-parse --show-toplevel` to anchor to the current worktree's root.
2. Use `git branch --show-current` to anchor to the currently checked-out branch.
3. Targetable artifacts are: unstaged changes (`git status --short`), staged changes, and the diff of the current branch against `origin/main` (or `main` if no remote) — i.e., `git diff main...HEAD` and `git diff` for working tree.
4. The user's `pwd` at skill invocation is authoritative — even if a sibling worktree exists, do NOT switch to it.

## Forbidden discovery moves (when no target was supplied)

The following commands are **target-discovery** commands. They invent a target the user did not name, and they are forbidden in the default-no-args path. Treat them as the same class of mistake as overwriting the user's uncommitted work:

- `gh pr list` — discovering open PRs to review/inspect. PR mode triggers ONLY on an explicit PR ref (`#N`, bare digits, or full GitHub PR URL) supplied in `$ARGUMENTS`.
- `gh pr view --json …` without an explicit PR ref — the `<ref>` argument must come from the user, never from `gh pr list` output.
- `git checkout <other-branch>` / `git switch <other-branch>` — moving the user off their current branch.
- `git worktree add` / `EnterWorktree(...)` — entering or creating a different worktree (the only sanctioned worktree-entry call site is `/geniro:implement` Phase 1 Step 10 Option C, which guards against re-entry — see SKILL.md there).
- `git stash` / `git stash pop` — the user's working tree is the input, not state to be hidden.

If the user **explicitly** names a target (a PR ref, a branch name, a diff range, a file list), follow it. The forbidden list applies only to the default-no-args path where the skill would otherwise have to invent something.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just `gh pr list` to show the user options — it's helpful" | The user already told you the target by where they invoked you. Listing PRs forces them to re-pick something they already implicitly chose. The "no args" path is a target, not an absence. |
| "There are no changes on the current branch, so I'll fall back to the latest PR" | If there's nothing to operate on, report that and stop. Inventing a target is worse than no-op-ing. |
| "The user's cwd is a worktree but main has more recent changes — I'll switch" | The cwd is authoritative. Different worktrees represent intentionally separate workstreams. Never switch. |
| "I'll silently `git fetch` and compare against `origin/main` even if there's no remote" | Read-only `git fetch` is fine when a remote exists; if there is no remote, fall back to local `main` ref. Never invent a remote. |
