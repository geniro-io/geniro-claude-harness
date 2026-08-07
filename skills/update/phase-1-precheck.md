# Update Phase 1 — Pre-check

Phase file for `/geniro:update`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md`.

### Step 0 — Load custom instructions

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: update`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory. Per-skill `update.md` and `code-style.md` are NOT loaded — this is a meta-skill that updates the plugin itself, so the pipeline-tier files don't apply (helper §Caller contract `rules-only` list).

### Step 1 — Read current version

Read `version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` into `CURRENT_VERSION`. Abort when it cannot be read — the already-on-latest check, the major-bump test, and the final report all compare against it, and an "unknown" baseline makes each of them silently wrong rather than absent.

### Step 1.5 — Legacy install-id check

An install still recorded under the legacy `geniro-claude-plugin` id cannot be updated in place — `claude plugin update` resolves ids exactly, and that id no longer exists in the marketplace. Detect it before spending a network round-trip on a command that cannot succeed:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LEGACY=$(python3 -c "
import json
try:
    d = json.load(open('$CLAUDE_USER_DIR/plugins/installed_plugins.json'))
    print('yes' if any(k.startswith('geniro-claude-plugin@') for k in d.get('plugins', {})) else 'no')
except Exception:
    print('no')
")
```

When `LEGACY=yes`, print the reinstall block below verbatim and terminate with `aborted: plugin renamed — reinstall required` (Termination case: legacy install id). Do not attempt the update, and do not run the reinstall yourself — it uninstalls the plugin currently executing this skill, so the user runs it:

```
The plugin was renamed geniro-claude-plugin → geniro. Update in place is not
possible across an id change. Run these three commands, then restart the session:

  claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
  claude plugin marketplace update geniro-claude-harness
  claude plugin install geniro@geniro-claude-harness --scope user

Your project files under .geniro/ are untouched — instructions, actions,
planning artifacts, and learnings all survive the reinstall.
Commands change from /geniro-claude-plugin:geniro:<skill> to /geniro:<skill>.
```

### Step 2 — Resolve `$CLAUDE_USER_DIR`, `$PRIMARY_ROOT`, and snapshot user content

Resolve `PRIMARY_ROOT` by running the Mode A resolver in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (single-sourced there — do not inline a copy). The snapshot must capture user-authored content in the primary worktree, not whichever worktree the orchestrator currently sits in: `/geniro:update` is typically run from `main`, but a session in a linked worktree would otherwise compare the wrong tree.

Then take the baseline snapshot:

```bash
CLAUDE_USER_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REGISTRY="$CLAUDE_USER_DIR/plugins/installed_plugins.json"
# PRIMARY_ROOT is set by the Mode A resolver, which runs inside THIS Bash call.

# --- paste the definitions from ${CLAUDE_PLUGIN_ROOT}/skills/update/user-content-snapshot.md here ---

_gu_snapshot "$PRIMARY_ROOT" > "$(_gu_snapshot_file "$PRIMARY_ROOT")" || true
```

The redirect is best-effort — a benign trailing `find`/read status must not read as failure. Survival is verified by the `phase-3-postcheck.md` §User-content survival check diff, not by this exit code.

### Step 3 — Confirm the update with the user

Use `AskUserQuestion`:

- **Question:** `Update the Geniro plugin? Current version: v<CURRENT_VERSION>. This will run marketplace + plugin update, verify integrity, and walk MIGRATION.md.`
- **Options:**
- `Confirm update` — Run the update flow (Recommended)
- `Cancel` — Exit without updating

On `Cancel` → terminate with `info: update cancelled by user`. On `Confirm update` → transition to Phase 2.

If `--dry-run` was passed in `$ARGUMENTS`, **skip the AUQ entirely** and instead read `${CLAUDE_PLUGIN_ROOT}/MIGRATION.md` (the currently-installed copy, before any marketplace fetch — `$PLUGIN_PATH` is not set until `phase-2-update.md` §Discover new plugin path, which dry-run skips); print "what would happen" and exit. `--dry-run` does NOT modify any files.

