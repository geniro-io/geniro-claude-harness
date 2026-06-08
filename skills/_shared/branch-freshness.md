# Branch freshness — start work from the latest default branch

Canonical contract for the start-of-work synchronization gate. Work should begin on the freshest default branch: new branches/worktrees are cut from the latest default-branch tip, and a branch already in progress is offered an update before the next chunk of work begins.

Consumers: `/geniro:implement` (both modes), `/geniro:plan`, `/geniro:debug`, `/geniro:refactor` (continue mode only — these three work in place and do not create branches).

## Contents

- §1 When to invoke — the two modes
- §2 Shared sub-steps — resolve default branch + fetch (fail-open)
- §3 Mode FRESH-BASE — cut new branch/worktree from latest default
- §4 Mode FRESH-CONTINUE — offer to update a branch that is behind
- §5 Dirty working tree
- §6 Conflict handling
- §7 Approvals + fail-open
- §8 Anti-rationalization

---

## 1. When to invoke — the two modes

| Mode | Fires when | What it does |
|---|---|---|
| **FRESH-BASE** | A skill is about to CREATE a new branch or worktree (`/geniro:implement` Step 0, "New feature branch" / "Git worktree" options). | Cut the new branch/worktree from the latest default-branch tip instead of from wherever HEAD currently sits. |
| **FRESH-CONTINUE** | A skill is about to continue work on an EXISTING branch — auto-continue paths, "Current branch", any skill entered on a feature branch, OR a skill entered while on the default branch itself. | If the current branch is behind the latest default branch, offer to bring it up to date before work starts — including the on-default-branch case (remote moved ahead → offer pull, §4.1). Skip silently when already current. |

Run the gate AFTER the workspace decision is known but BEFORE the first code edit / spec write / investigation. Skip the gate entirely on a compaction-resume (the branch was already synced when the run first started — re-asking on every resume is noise).

## 2. Shared sub-steps

Both modes start here. The default-branch resolution follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` rule #3 sub-bullets (b)/(c) (origin/HEAD → local main/master), restated inline so this gate stays self-contained; it adds one terminal `"main"` offline-safety fallback beyond those sub-bullets, for a repo with no remote and no main/master branch yet. Resolve the default branch, then attempt a best-effort fetch:

```bash
# Default branch: scope-anchor rule #3(b)/(c) (origin/HEAD, then local main/master) + terminal "main" offline-safety fallback.
DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$DEFAULT_BRANCH" ]; then
  for b in main master; do
    git show-ref --verify --quiet "refs/heads/$b" && DEFAULT_BRANCH="$b" && break
  done
fi
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"

# Best-effort fetch of the default branch — fail-open when offline / no remote.
FETCH_OK=0
if git remote get-url origin >/dev/null 2>&1; then
  TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 5"; command -v gtimeout >/dev/null 2>&1 && TO="gtimeout 5"
  $TO git fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null && FETCH_OK=1
fi

# BASE = freshest known tip of the default branch.
if [ "$FETCH_OK" = 1 ] && git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH"; then
  BASE="origin/$DEFAULT_BRANCH"
else
  BASE="$DEFAULT_BRANCH"   # local fallback (last fetch/pull)
fi
```

When the fetch fails, surface one line so the user knows freshness is best-effort: `"Couldn't reach the remote — comparing against your local <DEFAULT_BRANCH> instead."` Then proceed with the local `BASE`.

## 3. Mode FRESH-BASE — cut from the latest default

The new branch/worktree is created FROM `$BASE`, not from the current HEAD:

```bash
git checkout -b "<slug>" "$BASE"                              # new branch
git worktree add -b "<slug>" "<path>" "$BASE"                # new worktree
```

Echo what happened in plain English. If the fetch advanced the remote past the local default, say so:

```bash
AHEAD="$(git rev-list --count "$DEFAULT_BRANCH..$BASE" 2>/dev/null || echo 0)"
```

- Fetched and remote was ahead: `"Created <slug> from the latest <DEFAULT_BRANCH> (pulled <AHEAD> new commit(s) from the remote)."`
- Already current / offline: `"Created <slug> from <DEFAULT_BRANCH>."`

No extra question — cutting from the latest default is the correct base, so it happens as part of branch creation.

## 4. Mode FRESH-CONTINUE — offer to update a branch that is behind

```bash
CURRENT_BRANCH="$(git branch --show-current)"
BEHIND="$(git rev-list --count "HEAD..$BASE" 2>/dev/null || echo 0)"
```

- `BEHIND == 0` → skip silently (the branch already contains everything on the default). No question.
- `CURRENT_BRANCH == DEFAULT_BRANCH` AND `BEHIND > 0` → you are on the default branch and the remote moved ahead. Fire the **update-default** AUQ (§4.1).
- otherwise (on a feature branch, behind) → fire the **catch-up** AUQ (§4.2).

### 4.1 Update-default AUQ

```
header: "Update branch"
question: "You're on <DEFAULT_BRANCH>, <BEHIND> commit(s) behind the remote. Pull the latest before starting?"
options:
  - "Pull latest (Recommended)"   -> git pull --ff-only origin <DEFAULT_BRANCH>
  - "Skip — keep going"           -> no git action
```

### 4.2 Catch-up AUQ

```
header: "Sync branch"
question: "Your branch is <BEHIND> commit(s) behind <DEFAULT_BRANCH>. Bring it up to date before starting this work?"
options:
  - "Merge <DEFAULT_BRANCH> in (Recommended)"  -> git merge --no-edit "$BASE"
  - "Rebase onto <DEFAULT_BRANCH>"             -> git rebase "$BASE"
  - "Skip — keep going"                        -> no git action
```

Add this one-line caveat under the rebase option so the user can choose well: rebase rewrites this branch's commits, so it is best for a branch you have NOT pushed yet — a pushed branch would then need a force-push (which the git guardrail blocks), so prefer Merge there.

## 5. Dirty working tree

Check before merging / rebasing / pulling:

```bash
DIRTY="$(git status --porcelain 2>/dev/null | head -1)"
```

When `DIRTY` is non-empty and the user picked an action that moves HEAD, do NOT run it against uncommitted changes — chain one more question:

```
header: "Uncommitted work"
question: "You have uncommitted changes. Stash them, run the update, then restore?"
options:
  - "Stash, update, restore (Recommended)"  -> git stash push -u; <action>; git stash pop
  - "Skip the update — keep my changes"     -> no git action
```

If `git stash pop` reports a conflict, leave the tree as-is and tell the user their stashed changes conflicted with the update and need manual resolution — do not auto-resolve.

## 6. Conflict handling

Merge and rebase can conflict. Keep the tree in a known-good state — never leave the skill running on a half-merged tree:

- Merge conflict (`git merge` exits non-zero): run `git merge --abort`, then surface `"<DEFAULT_BRANCH> has changes that conflict with this branch. Resolve manually with 'git merge <DEFAULT_BRANCH>' before continuing — proceeding without the update for now."` Continue the skill on the un-merged branch.
- Rebase conflict (`git rebase` exits non-zero): run `git rebase --abort`, surface the same message phrased for rebase, and continue.

The update is an offer, not a hard gate — a conflict that the user must resolve by hand does not block the skill's actual work.

## 7. Approvals + fail-open

**Persist the pick.** For skills with a state.md, append the answer to frontmatter `approvals[]` with category `branch_freshness` (picked value + ISO-8601 timestamp + resolved `behind` count). On compaction-resume the gate is skipped, so this record is the audit trail of what was chosen.

**Fail-open.** Skip the entire gate with a single one-line notice — never block the skill's work — when any of these hold: not inside a git repository, detached HEAD (`git symbolic-ref -q HEAD` empty), no commits yet, or any required git command errors. Freshness is a convenience, not a correctness gate.

## 8. Anti-rationalization

| Rationalization | Why it is wrong |
|---|---|
| "The branch is behind by only one commit — just merge it automatically to save a question." | The update moves the user's HEAD and can conflict. Moving someone's branch without consent is the kind of surprise the AUQ gate exists to prevent. Offer; never auto-run. |
| "Fetch is slow — skip it and compare against local <DEFAULT_BRANCH>." | Local default is only as fresh as the last manual pull, so "latest" would be a lie. Attempt the fetch with the timeout; fall back to local only when it actually fails, and say so. |
| "On a merge conflict I'll resolve it so work isn't blocked." | A skill auto-resolving someone's merge conflict produces silent, unreviewed history. Abort, surface the conflict, and continue on the un-merged branch — the user resolves it deliberately. |
| "Re-ask the catch-up question on every compaction-resume to be safe." | The branch was synced when the run first started; re-asking on resume is noise. The gate fires once per fresh start, recorded in `approvals[]`. |
| "I'm on the default branch (main/master), not a feature branch — this freshness gate is about feature branches, so skip it." | FRESH-CONTINUE covers the default branch too (§4.1): on the default branch with the remote ahead, fire the update-default AUQ and offer to pull. Computing `BEHIND` (§4) does not depend on which branch you are on — run the comparison regardless of HEAD, and only the `BEHIND == 0` result skips silently. Skipping because "this is main" plans/works against a stale tree. |
