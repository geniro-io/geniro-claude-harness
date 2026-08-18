<!-- Generated from skills/actions/subcommand-edit.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Actions — `edit` sub-command (Phase 5)

Sub-command body for `${CLAUDE_PLUGIN_ROOT}/skills/actions/SKILL.md`. Read on Phase-1 dispatch to `edit`. The spine keeps the invariants, the anti-rationalization table, the tool surface and the termination mapping — this file carries the Steps.

## Phase 5: `edit` sub-command

### Step 1 — Resolve target

Apply `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Target resolution. Its Step 4 resolves which copy to edit — the canonical main-repo copy by default, the local branch copy when only it exists or the user picks it.

### Step 2 — Open for external editing

Snapshot the file before handing it off — `cp "<absolute-path>" "<absolute-path>.pre-edit.bak"` — so the auto-validation's "Revert to pre-edit version" option (Step 3) has a restore target; without it that option has nothing to restore.

Print absolute path: `Edit: <absolute-path-to-resolved-file>`.

AUQ to wait for the user's "done" signal:

- **Question:** "Have you finished editing `<absolute-path>`?"
- **Options:**
- `Done — re-run validation` — Re-read the file and run the validation gate with `edit-in-place` entry mode
- `Cancel` — Stop without re-validating; leave the file as the user left it, and remove the snapshot: `rm -f "<absolute-path>.pre-edit.bak"`

### Step 3 — Re-validate (on Done) + auto-validate

Run `${CLAUDE_PLUGIN_ROOT}/skills/actions/actions-reference.md` §Validation gate with **entry mode = `edit-in-place`**. The file is NOT deleted on a blocking verdict — pre-existing user work is preserved.

**Auto-validation surfacing:** on a blocking verdict, surface the rows + AUQ:

- **Question:** "Auto-validation found issues: <list>. What next?"
- **Options:** `Open editor again` / `Save anyway despite warnings` / `Revert to pre-edit version` (restore via `mv "<path>.pre-edit.bak" "<path>"`)

The auto-validation does NOT block save; it surfaces. User remains in control. On any terminal pick here (Save anyway / Revert), remove the snapshot: `rm -f "<path>.pre-edit.bak"`.

On a clean verdict, remove the snapshot — `rm -f "<path>.pre-edit.bak"` — then print: `Edited \`<resolved-path>\`. Run with \`/geniro:actions run <resolved-slug>\`.` When the edited copy is the main-repo one and the current directory is a different worktree, append: "Written to the main repo checkout, so it survives if this worktree is removed."
