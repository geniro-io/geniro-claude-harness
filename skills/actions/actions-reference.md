# Actions — shared procedures

The two procedures more than one sub-command uses. Read this file whenever a sub-command body points at a section here; a `list` run needs §Target resolution's Step 1 only, `create` and `edit` need §Validation gate, and `run` / `delete` / `validate` need both.

## Contents

- Target resolution — Steps 1-4: build the registry, exact-slug fast path, free-text picker, canonical-copy resolution (used by `run` / `edit` / `delete` / `validate`)
- Validation gate — every create/validate check decided by `validate-action-file.sh` and what to do with each verdict (used by `create` / `edit` / `validate`)

---

## Target resolution

Resolve which action file a sub-command operates on. The resolver returns three named values: `<resolved-path>` (absolute or repo-relative), `<resolved-slug>` (basename minus `.md`), and `<source>` (`local` or `main-worktree`).

### Step 1 — Build the registry index

Resolve `PRIMARY_ROOT` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the snippet sets a shell variable used by the dual-glob below.

Dual-glob both `./.geniro/actions/*.md` (local) and `<PRIMARY_ROOT>/.geniro/actions/*.md` (main); tag each entry with `<source>` (`local` or `main-worktree`). When cwd IS the main worktree the two globs resolve to the same path — dedupe by absolute path before tagging. When the same slug exists in both, **local wins** — drop the main-worktree entry. This is the canonical registry build; `list` and `validate` reference this step directly for their whole-directory scans.

### Step 2 — Exact-slug fast path (literal or normalized)

Compute `<lookup>` from input: if already a valid kebab slug, `<lookup> = <input>`; otherwise normalize (trim, lowercase, whitespace-runs → hyphens). If `<lookup>` matches a registry entry's `name`:

- **Source = local, sub-command = `run` or `validate`:** return `(<resolved-path>, <resolved-slug>, local)`. No AUQ.
- **Source = local, sub-command = `edit` or `delete`:** do not return yet — continue to Step 4. The Step 1 registry dropped any same-slug main-worktree entry (local wins), so only Step 4's direct both-locations check can see the second copy.
- **Source = main-worktree, sub-command = `run`:** confirm via AUQ before returning (cross-worktree confirmation; `<source>` was tagged in Step 1):
- **Question:** "Action `<lookup>` exists in the main worktree at `<PRIMARY_ROOT>/.geniro/actions/<lookup>.md`. Use it?"
- **Options:** `Use the main-worktree copy` / `Cancel`
- **Source = main-worktree, sub-command = `edit` or `delete`:** no gate here; Step 4 resolves which copy is operated on.
- **Source = main-worktree, sub-command = `validate`:** return `(<resolved-path>, <resolved-slug>, main-worktree)` without AUQ — `validate` is read-only.

### Step 3 — Free-text matching path

If Step 2 did not resolve, score every entry by semantic fit (orchestrator scores in-context). Take the top 3 candidates by score.

Present an AUQ picker with up to 3 candidate options plus a final "Other" option. When "Other" is picked, surface free-text and loop. Cap loop at **3 rounds**; then surface "Could not narrow down — try `/geniro:actions list` for exact slugs" and stop.

### Step 4 — Canonical-copy resolution (`edit` / `delete` only)

For `edit` and `delete`, after Step 2 or Step 3 resolves `<resolved-slug>`, check BOTH `./.geniro/actions/<resolved-slug>.md` AND `<PRIMARY_ROOT>/.geniro/actions/<resolved-slug>.md` directly on disk — not the Step 1 registry, whose local-wins dedupe hides the main copy — before returning:

- Slug exists ONLY at `<PRIMARY_ROOT>` → operate there directly.
- Slug exists ONLY locally (cwd copy, e.g. a committed branch-local file) → operate on the local copy.
- Slug exists in BOTH with identical contents → operate on the main-repo copy without asking. Contents differ → one AUQ:
- **Question:** "`<resolved-slug>` exists in both the main repo checkout and this worktree, and the two copies differ (`run` currently uses this worktree's copy). Which copy should I <edit|delete>?"
- **Options:** `Main repo copy (Recommended)` / `This worktree's branch copy` / `Cancel`

`delete` still passes through its own destructive-op confirmation regardless of which copy is targeted.

---

## Validation gate

Fires after `create` writes the file, after `edit` returns from the external editor, and once per file in `validate` mode. One call decides every check in `validate-action-file.sh`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/validate-action-file.sh"
validate_action_file "<resolved-path>"
```

The helper prints one TAB-separated row per FAILED check — `<SEVERITY>`, `<check-id>`, `<line-or-dash>`, `<message>` — and nothing at all for a clean file. Exit codes: `0` clean · `1` MEDIUM/LOW findings only · `2` at least one CRITICAL or HIGH · `64` no path was passed · `65` the path is not a readable file. The rows are the report and the exit code is the verdict, so gate on the code and render the rows.

What each check asserts, and the description-length cap it enforces, live in the helper — `${CLAUDE_PLUGIN_ROOT}/lib/validate-action-file.sh`. Do not hand-run the conditions and do not restate them: a hand-run table is re-interpreted on every create and every validate, and the interpretation is what drifts. The authoring-side statement of the same rules is `${CLAUDE_PLUGIN_ROOT}/skills/actions/skill-template.md` §Authoring rules.

### Verdict handling

| Exit code | What to do |
|---|---|
| `0` | Proceed to the sub-command's confirmation line. |
| `1` | Render the rows as warnings and proceed — a MEDIUM never blocks a write the user asked for. |
| `2` | Do not proceed. Render every row verbatim (severity, check, line, message), then apply the entry-mode rollback below. |
| `64` / `65` | The validator did not run, so nothing was checked. Treat it as blocking, say so in those words, and surface the helper's stderr — reporting an unrun check as a pass would ship an unvalidated action. |

**Entry-mode rollback on a blocking verdict.** The failure path is parametric on how the run reached this gate:

- **Entry mode `create`** (the write just materialized a fresh draft): `rm -f "$PRIMARY_ROOT"/.geniro/actions/<name>.md`. The file did not exist before this run, so removing it loses nothing. Re-run `/geniro:actions create <name>`.
- **Entry mode `edit-in-place`** (`edit`, or `create`'s "Edit in place" branch): leave the file exactly as the user left it — it holds pre-existing user work. Re-run `/geniro:actions edit <name>`.

Report the failing rows and let the user fix them; auto-fixing would silently rewrite user-authored content. Re-validate up to 3 retry rounds.
