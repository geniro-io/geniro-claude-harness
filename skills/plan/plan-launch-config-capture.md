# Plan — launch-config batched capture

Step 2 of `plan-auq-reference.md` §5b, read only on the "Let me choose each setting" pick.

The three always-present settings (workspace / branch handling / ship mode), plus — when the spec has a linked tracker ticket (state.md `## Workflow Refs` / held `workflow_refs[]` non-empty) — the kickoff tracker-status setting, all fit inside the 4-question-per-call tool cap and fire together in ONE AUQ call; with no linked tracker ticket only the three always-present questions fire. An empty answer on a field falls back to that field's recommended default (the user already opted in), so no field can block.

```yaml
questions:
  - header: "Workspace"
    question: "Where should /implement do the work?"
    options:
      - label: "New branch"                  # Recommended → workspace: new-branch
        description: "Cut a fresh branch from the latest default branch."
      - label: "Current branch"
        description: "Work in place on the current branch."
      - label: "Worktree"
        description: "Cut a separate worktree so the current checkout is untouched."
      - label: "Here"
        description: "Work in the current directory as-is, no branch change."
  - header: "Branch sync"
    question: "If the branch is behind the default branch, how should /implement catch it up?"
    options:
      - label: "Rebase"                       # Recommended → branch_freshness: rebase
        description: "Replay your commits on top of the latest default branch."
      - label: "Merge"
        description: "Merge the latest default branch into yours."
      - label: "Skip"
        description: "Leave the branch as-is; don't update it before working."
  - header: "Ship mode"
    question: "How should /implement finish — what should it do at ship time?"
    options:
      - label: "Draft PR"                     # Recommended → ship_mode: draft-pr
        description: "Push and open a draft pull request."
      - label: "PR ready for review"
        description: "Push and open a pull request marked ready for review."
      - label: "Commit only, don't push"
        description: "Commit locally; don't push or open a PR."
      - label: "Stop after review"
        description: "Stop before any commit or push."
  - header: "Task status"                    # only when a tracker ticket is linked
    question: "When /geniro:implement starts, move the linked tracker task to In Progress?"
    options:
      - label: "Yes — move to In Progress"        # Recommended → tracker_status: move-to-in-progress
        description: "/geniro:implement confirms the kickoff move on its own. It still skips the move when the task is already In Progress."
      - label: "No — leave the status unchanged"   # → tracker_status: leave-unchanged
        description: "/geniro:implement won't change the tracker status at kickoff."
```

Map the picks to the `launch_config:` block values (`workspace` / `branch_freshness` / `ship_mode`, plus `tracker_status` when the tracker-status question fired) per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md` §"The block". Omit `tracker_status` from the block when no tracker ticket was linked (the question did not fire). Hold the block for the §8.4 spec rewrite.
