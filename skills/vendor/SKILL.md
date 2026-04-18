---
name: geniro:vendor
description: "Copy the plugin into .claude/ with a geniro- prefix for cloud runners that can't use the marketplace. Translates hooks.json into .claude/settings.json, rewrites \${CLAUDE_PLUGIN_ROOT} references, and extends .geniro/.geniro-state.json with a vendor manifest so /geniro:setup can detect drift and resync on plugin updates."
context: main
model: sonnet
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent, AskUserQuestion]
argument-hint: "[--sync to resync | --fresh to force fresh vendoring]"
---

# /geniro:vendor — Vendor Plugin Into Project

Vendoring copies every plugin asset (skills, agents, hooks) into the project's `.claude/` directory with a `geniro-` filename prefix so the plugin works on environments that cannot install marketplace plugins — cloud runners, sandboxed CI, offline development, or when pinning the plugin to a known commit.

The trade-off: project-scope skill names cannot contain colons, so slash commands change from `/geniro:setup` to `/geniro-setup` after vendoring. The marketplace plugin must also be uninstalled to avoid hooks firing twice (see Mutual Exclusivity below).

### When to vendor

- **Cloud runners** (CI, ephemeral cloud agents) cannot install marketplace plugins. Vendoring puts the entire plugin in `.claude/` so a fresh checkout has everything it needs.
- **Pinning** — vendoring captures the exact commit of the plugin in your repo. Plugin upgrades become explicit (`/geniro-vendor --sync`) instead of silent.
- **Offline development** — no marketplace fetch required at session start.
- **Local edits** — backend-agent.md and frontend-agent.md are designed to be tailored per project. Vendoring makes those edits version-controllable.

### When NOT to vendor

- Single-developer machines with reliable marketplace access — use `/geniro:update` instead.
- Projects that already have a different `.claude/` overlay you don't want to merge with.

## Path Constraints

**NEVER use `~` in file paths passed to Read, Write, Edit, or Glob tools.** The `~` character is NOT expanded by these tools — it creates a literal `~` directory in the working directory. Always use `${CLAUDE_PLUGIN_ROOT}` for plugin files or absolute paths for project files.

If a step fails, do NOT improvise by constructing paths manually. Report the error and stop.

## Mutual Exclusivity with the Marketplace Plugin

Vendored mode and marketplace-installed mode MUST NOT both be active at the same time. When both are present, hook command strings differ (`${CLAUDE_PLUGIN_ROOT}/...` vs `.claude/hooks/geniro-...`), so Claude Code's deduplication treats them as distinct hooks and runs each one twice — silently corrupting state and doubling token cost. After vendoring, uninstall the marketplace plugin. Before removing a vendored copy, run `/geniro-cleanup`, which restores the original `settings.json` from the pre-vendor backup.

## Argument Handling

Parse `$ARGUMENTS`:

- **No arguments** (or `--fresh`): fresh vendor operation. If `.geniro/.geniro-state.json` already shows `mode: "vendored"`, warn and offer to switch to the resync flow instead of clobbering.
- **`--sync`**: resync flow. Read the vendor state, compare stored hashes against the current plugin source, re-apply drifted files. Tailored files surface a merge prompt; verbatim files are re-copied silently.

## Phase 0: Preflight

1. Verify `${CLAUDE_PLUGIN_ROOT}` resolves and contains `agents/`, `skills/`, `hooks/`, and `.claude-plugin/plugin.json`. If anything is missing, stop with an error — the plugin source is not where this skill expects it.

   ```bash
   for d in agents skills hooks .claude-plugin; do
     [ -e "${CLAUDE_PLUGIN_ROOT}/$d" ] || { echo "missing: $d"; exit 1; }
   done
   [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] || exit 1
   ```

2. Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and extract the `version` field. Hold it for Phase 5.
3. If `.geniro/.geniro-state.json` exists, read it and inspect the top-level `mode` field:
   - `mode == "vendored"`: route to **Phase 8: Resync Flow**. Show the user a drift report and ask what to do.
   - Anything else (or absent): continue to Phase 1.
4. Check whether the marketplace plugin is currently installed (informational — used to tailor the Phase 7 reminder language). The presence of `${CLAUDE_PLUGIN_ROOT}` itself implies it is, but the user may have a separate vendor source.
5. Confirm `.claude/` exists or can be created in the current working directory. If the working directory is not a git repo root or project root, warn the user that vendoring will write to whatever directory `claude` was launched from.

## Phase 1: Scope Confirmation

Present the scope and consequences via `AskUserQuestion`. Show this exact summary so the user knows what they're agreeing to:

```
Vendoring will:
- Copy 15 skills to .claude/skills/geniro-*/
- Copy 14 agents to .claude/agents/geniro-*-agent.md
- Copy 11 hook scripts to .claude/hooks/geniro-*
- Translate plugin hooks.json into .claude/settings.json
  (backup saved to .claude/settings.json.pre-vendor-backup)
- Rewrite ${CLAUDE_PLUGIN_ROOT} references in all copied files to .claude/ paths
- Extend .geniro/.geniro-state.json with a vendor manifest

Consequences:
- Slash commands become /geniro-setup, /geniro-implement, /geniro-vendor, etc.
  (NOT /geniro:setup — project-scope skills cannot have colons in names)
- The marketplace plugin MUST be uninstalled after vendoring to avoid doubled
  hooks. Hooks fire twice if both copies are active — silent corruption.
- Agent subagent_type lookups are unchanged (YAML names stay the same, only
  filenames are prefixed).
- Run /geniro-cleanup or /geniro:cleanup to revert.
```

Then call `AskUserQuestion` with question `"Proceed with vendoring?"` and options:

- `"Yes, vendor the plugin now"` — Recommended
- `"No, cancel"`

If the user cancels, stop immediately and report no changes were made.

## Phase 2: Build File Manifest

Enumerate every source file and compute its destination + sha256 hash. Write the manifest to a temporary file (e.g. `/tmp/geniro-vendor-manifest.tsv`) for use in Phases 3, 5, and 8. The manifest format is three tab-separated columns: `src	dst	sha256`.

```bash
manifest=/tmp/geniro-vendor-manifest.tsv
: > "$manifest"
{
  find "${CLAUDE_PLUGIN_ROOT}/skills" -type f
  find "${CLAUDE_PLUGIN_ROOT}/agents" -type f -name '*.md'
  find "${CLAUDE_PLUGIN_ROOT}/hooks" -type f -not -name 'hooks.json'
} | while read -r src; do
  rel="${src#${CLAUDE_PLUGIN_ROOT}/}"
  hash=$(shasum -a 256 "$src" | awk '{print $1}')
  # destination derived per the prefix rule below
  printf '%s\t%s\t%s\n' "$rel" "$dst" "$hash" >> "$manifest"
done
```

For every source path, compute:
- The hash: `shasum -a 256 "$src" | awk '{print $1}'`
- The destination by applying the **prefix rule** to the basename and reattaching it to the relative path under `.claude/`.

Skill files keep their internal directory structure (e.g. `skills/setup/reference/template.md` becomes `.claude/skills/geniro-setup/reference/template.md`) — only the top-level skill directory name and any leaf basenames that already lived under `agents/` or `hooks/` get prefix treatment. Subdirectories inside a skill are preserved verbatim.

### The Prefix Rule (canonical — defined here, referenced elsewhere)

> A vendored filename is derived from its source basename as follows: if the basename already starts with `geniro-` or `geniro_`, the destination basename is unchanged; otherwise the destination basename is `geniro-${basename}`. This rule applies uniformly to skill directory names, agent filenames, and hook script filenames. Do NOT double-prefix files like `geniro-check-update.js` or `geniro-statusline.js`.

Phases 3 and 4 both invoke **the prefix rule** by name. Do not re-derive or re-state it.

## Phase 3: Copy and Rewrite

Copy each source family. Apply **the prefix rule** (Phase 2) for filename derivation. First, define the executable form of the prefix rule — a single bash function that every loop in this phase (and the sed-script generator below) calls by name. This is the canonical implementation; nothing else in this skill re-derives the logic.

```bash
# Executable form of the prefix rule defined in Phase 2.
# Defined once; called from every copy loop and hook translator below.
prefix_basename() {
  case "$1" in
    geniro-*|geniro_*) printf '%s' "$1" ;;
    *) printf 'geniro-%s' "$1" ;;
  esac
}
```

```bash
# Skills: recursive copy with directory rename
for skill_dir in "${CLAUDE_PLUGIN_ROOT}/skills"/*/; do
  name=$(basename "$skill_dir")
  dest_name=$(prefix_basename "$name")
  mkdir -p ".claude/skills"
  cp -r "$skill_dir" ".claude/skills/${dest_name}"
done

# Agents: flat copy with filename prefix
mkdir -p .claude/agents
for f in "${CLAUDE_PLUGIN_ROOT}/agents"/*.md; do
  base=$(basename "$f")
  dest_name=$(prefix_basename "$base")
  cp "$f" ".claude/agents/${dest_name}"
done

# Hooks: flat copy, skip hooks.json (translated separately in Phase 4)
mkdir -p .claude/hooks
for f in "${CLAUDE_PLUGIN_ROOT}/hooks"/*; do
  base=$(basename "$f")
  [ "$base" = "hooks.json" ] && continue
  dest_name=$(prefix_basename "$base")
  cp "$f" ".claude/hooks/${dest_name}"
done
chmod +x .claude/hooks/*.sh 2>/dev/null
```

After all copies, rewrite `${CLAUDE_PLUGIN_ROOT}` references inside the vendored files. Do NOT use a catch-all `${CLAUDE_PLUGIN_ROOT}` → `.claude` substitution — a catch-all would emit unprefixed paths like `.claude/hooks/secret-protection-output.sh` and silently strand every hook at the wrong location. Instead, enumerate every source basename and emit one explicit `sed -e` clause per basename, routing each through `prefix_basename`:

```bash
# Build a sed script that rewrites every source path explicitly using the prefix rule.
SED_SCRIPT=$(mktemp)
for f in "${CLAUDE_PLUGIN_ROOT}/hooks"/*; do
  base=$(basename "$f")
  [ "$base" = "hooks.json" ] && continue
  dest=$(prefix_basename "$base")
  printf 's|\${CLAUDE_PLUGIN_ROOT}/hooks/%s|.claude/hooks/%s|g\n' "$base" "$dest" >> "$SED_SCRIPT"
done
for f in "${CLAUDE_PLUGIN_ROOT}/agents"/*.md; do
  base=$(basename "$f")
  dest=$(prefix_basename "$base")
  printf 's|\${CLAUDE_PLUGIN_ROOT}/agents/%s|.claude/agents/%s|g\n' "$base" "$dest" >> "$SED_SCRIPT"
done
for d in "${CLAUDE_PLUGIN_ROOT}/skills"/*/; do
  name=$(basename "$d")
  dest=$(prefix_basename "$name")
  printf 's|\${CLAUDE_PLUGIN_ROOT}/skills/%s|.claude/skills/%s|g\n' "$name" "$dest" >> "$SED_SCRIPT"
done
```

**macOS sed quirk**: BSD `sed -i` requires a backup-extension argument. Always invoke as `sed -i '' -f "$SED_SCRIPT"` on macOS, otherwise the command silently no-ops or fails. On Linux, `sed -i -f "$SED_SCRIPT"` is correct. Detect the platform with `uname` if portability matters; otherwise use `sed -i ''` since this skill is most often run on macOS development machines.

```bash
# Apply the generated script to every copied file (macOS sed requires the empty '' backup arg)
find .claude/skills .claude/agents .claude/hooks -type f \( -name '*.md' -o -name '*.sh' -o -name '*.js' \) \
  -exec sed -i '' -f "$SED_SCRIPT" {} +
# Keep $SED_SCRIPT on disk — Phase 4 reuses it to rewrite .claude/settings.json after the hook merge.
```

Every path is rewritten via the per-basename script, so the prefix rule is consulted exactly once per source file and never inlined.

Then rewrite skill YAML `name:` fields. Skill names in project scope cannot contain colons:

```bash
find .claude/skills -name SKILL.md -exec \
  sed -i '' -e 's/^name: geniro:/name: geniro-/' {} \;
```

**Agent YAML `name:` fields stay UNCHANGED.** Subagent lookups by `subagent_type` (e.g. `architect-agent`) must continue to resolve, so only the filename gets prefixed. Do not touch the YAML inside agent files.

## Phase 4: Hook Translation

Hook translation runs in three ordered steps: (1) back up and stage `.claude/settings.json`, (2) merge the plugin's hooks block into it in Python without touching paths, (3) run the Phase 3 `$SED_SCRIPT` over `.claude/settings.json` so the prefix rule stays authored exactly once (in bash). Python never reimplements the prefix rule.

1. If `.claude/settings.json` exists, back it up:

   ```bash
   cp .claude/settings.json .claude/settings.json.pre-vendor-backup
   ```

   If it doesn't exist, create a stub: `echo '{"hooks": {}}' > .claude/settings.json`.

2. Read `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json` and merge its `hooks` block into `.claude/settings.json` with an explicit matcher-aware algorithm. Claude Code's settings.json hook schema has TWO nested arrays per event: an outer list of matcher entries, and an inner `hooks` array per matcher entry. Merging naively will either duplicate matcher entries or clobber user hooks — both are silent corruption. Pass `CLAUDE_PLUGIN_ROOT` to Python via the environment (the heredoc is single-quoted to protect `$` sequences inside the Python body, so shell expansion does not happen inside the heredoc):

   ```bash
   CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" python3 <<'PY'
   import os, json, pathlib
   root = os.environ["CLAUDE_PLUGIN_ROOT"]
   src_hooks = json.loads(pathlib.Path(f"{root}/hooks/hooks.json").read_text())
   dst_path = pathlib.Path(".claude/settings.json")
   dst = json.loads(dst_path.read_text()) if dst_path.exists() else {"hooks": {}}
   dst.setdefault("hooks", {})

   for event, plugin_entries in src_hooks.get("hooks", {}).items():
       dst_event = dst["hooks"].setdefault(event, [])
       for p_entry in plugin_entries:
           p_matcher = p_entry.get("matcher")
           # Find an existing matcher entry with the same matcher string
           target = next((e for e in dst_event if e.get("matcher") == p_matcher), None)
           if target is None:
               # No existing entry for this matcher — append the plugin entry whole
               dst_event.append(p_entry)
               continue
           # Matcher exists — extend its inner hooks list, dedup by command string
           existing_cmds = {h.get("command") for h in target.setdefault("hooks", [])}
           for p_hook in p_entry.get("hooks", []):
               if p_hook.get("command") not in existing_cmds:
                   target["hooks"].append(p_hook)

   dst_path.write_text(json.dumps(dst, indent=2) + "\n")
   PY
   ```

   At this point `.claude/settings.json` still contains `${CLAUDE_PLUGIN_ROOT}/hooks/<original-basename>` in every merged command string. Path rewriting happens in the next step.

3. Rewrite paths in `.claude/settings.json` using the same `$SED_SCRIPT` generated in Phase 3. This is the second pass of the canonical prefix-aware script — the prefix rule remains authored exactly once (inside `prefix_basename` in Phase 3) and is reused here verbatim:

   ```bash
   sed -i '' -f "$SED_SCRIPT" .claude/settings.json
   rm -f "$SED_SCRIPT"
   ```

4. Validate the result: `python3 -m json.tool .claude/settings.json >/dev/null` (or `jq empty .claude/settings.json`). If validation fails, restore from `settings.json.pre-vendor-backup` and stop.

The merged `hooks` block must keep every plugin matcher (`PreToolUse` for Bash and Edit|Write, `PostToolUse`, `PreCompact`, `SessionStart`, `PostCompact`) and every `timeout` and `statusMessage` field. Only the `command` strings change. Example translation for the `db-guard` entry:

- Source: `"\"${CLAUDE_PLUGIN_ROOT}\"/hooks/db-guard.sh"`
- Vendored: `".claude/hooks/geniro-db-guard.sh"`

And for the already-prefixed `geniro-check-update.js` entry:

- Source: `"node \"${CLAUDE_PLUGIN_ROOT}/hooks/geniro-check-update.js\""`
- Vendored: `"node .claude/hooks/geniro-check-update.js"` (no double prefix — see **the prefix rule**)

The merge algorithm in step 2 preserves user-owned hooks: new matcher entries are appended to each event array, existing matcher entries have their inner `hooks` list extended with command-level dedup. Order within a matcher entry follows the append order, so db-guard and secret-protection guards authored in `hooks.json` continue to run in the sequence the plugin ships.

## Phase 5: Write Vendor State

Update `.geniro/.geniro-state.json`:

- If the file exists, read it, merge in the new top-level `mode` field and `vendor` block, and preserve every other field (`plugin_version`, `installed_at`, `install_mode`, `features_enabled`, `files`).
- If the file does not exist (unusual — `/geniro:setup` typically creates it), construct a minimal one containing `installed_at`, `mode`, and `vendor`.

### Allow the vendor state file through `.gitignore`

`/geniro:setup` writes `.gitignore` with `.geniro/*` plus explicit negations for `.geniro/workflow/` and `.geniro/instructions/`. The state file `.geniro/.geniro-state.json` is not negated by default, so `git add .geniro/.geniro-state.json` would be a silent no-op and the whole "cloud runner clones the repo and resyncs on plugin update" workflow would break — the state file simply would not exist on the runner. Before writing the state file, ensure `.gitignore` has the negation line:

```bash
# Ensure the vendor state file is trackable even though .geniro/* is ignored
grep -q '^\!\.geniro/\.geniro-state\.json$' .gitignore 2>/dev/null || \
  echo '!.geniro/.geniro-state.json' >> .gitignore
```

Final shape:

```json
{
  "plugin_version": "<existing if present>",
  "installed_at": "<existing if present>",
  "install_mode": "<existing if present>",
  "features_enabled": { "...": "preserved" },
  "files": { "generated": [], "user_created": [] },
  "mode": "vendored",
  "vendor": {
    "vendored_at": "<ISO-8601 now>",
    "plugin_version": "<from plugin.json>",
    "plugin_source_sha": "<sha256 of concatenated sorted manifest hashes>",
    "prefix": "geniro-",
    "file_manifest": [
      {"src": "skills/setup/SKILL.md", "dst": ".claude/skills/geniro-setup/SKILL.md", "sha256": "..."},
      {"src": "agents/architect-agent.md", "dst": ".claude/agents/geniro-architect-agent.md", "sha256": "..."}
    ],
    "settings_backup": ".claude/settings.json.pre-vendor-backup",
    "tailored_files": ["agents/backend-agent.md", "agents/frontend-agent.md", "rules/*"]
  }
}
```

Compute `plugin_source_sha` as:

```bash
sort /tmp/geniro-vendor-manifest.tsv | awk '{print $3}' | shasum -a 256 | awk '{print $1}'
```

This single string identifies the entire vendored snapshot for fast equality checks in Phase 8.

### Frontmatter check

The Phase 3 sed pass strips colons from skill names, but verify in Phase 6 that no SKILL.md still says `name: geniro:` — a missed file there will produce a skill that Claude Code refuses to load with no error visible to the user until they try to invoke it.

## Phase 6: Verification

Run every check. If any fails, report which one and stop — do NOT attempt auto-recovery. The user must investigate.

1. **No unrewritten plugin-root references**: `grep -rl '\${CLAUDE_PLUGIN_ROOT}' .claude/` returns empty.
2. **Skill count matches source**: `find .claude/skills -name SKILL.md | wc -l` equals `find "${CLAUDE_PLUGIN_ROOT}/skills" -name SKILL.md | wc -l`.
3. **Agent count matches source**: `find .claude/agents -name 'geniro-*.md' | wc -l` equals `find "${CLAUDE_PLUGIN_ROOT}/agents" -name '*.md' | wc -l`.
4. **settings.json valid**: `python3 -m json.tool .claude/settings.json >/dev/null` exits 0.
5. **state file valid**: `python3 -m json.tool .geniro/.geniro-state.json >/dev/null` exits 0.
6. **Skill frontmatter colons stripped**: every `.claude/skills/geniro-*/SKILL.md` has `^name: geniro-` and none have `^name: geniro:`.

```bash
! grep -l '^name: geniro:' .claude/skills/geniro-*/SKILL.md 2>/dev/null
```

## Phase 7: Report and Restart

Present this report to the user verbatim, filling in the counts:

```
Vendoring complete.

Vendored:
- X skills → .claude/skills/geniro-*
- Y agents → .claude/agents/geniro-*.md
- Z hook scripts → .claude/hooks/geniro-*
- Plugin hooks → .claude/settings.json
- State recorded in .geniro/.geniro-state.json

Next steps:
1. Uninstall the marketplace plugin to avoid doubled hooks:
     claude plugin uninstall geniro-claude-plugin@geniro-claude-harness
2. Restart your Claude Code session — vendored skills only become invocable
   after a restart.
3. Your slash commands are now /geniro-setup, /geniro-implement,
   /geniro-vendor, etc.
4. Commit the vendored copy:
     git add .claude/ .geniro/.geniro-state.json .gitignore && \
       git commit -m 'chore: vendor geniro plugin'
   The .gitignore has already been updated with
   '!.geniro/.geniro-state.json' so the state file is trackable even
   though .geniro/* is otherwise ignored.

To resync after a plugin update:
  /geniro-vendor --sync   (or /geniro:vendor --sync if the marketplace plugin
                            is still installed)

To revert:
  /geniro-cleanup         (or /geniro:cleanup)
```

## Phase 8: Resync Flow

Triggered by `--sync` or by detecting `mode == "vendored"` in Phase 0.

When entered from Phase 0 (existing vendor state, no `--sync` flag), first ask the user via `AskUserQuestion` whether they want to resync now, switch to a fresh vendor (clobbering local edits), or cancel. Default to resync.

1. Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` to get the current plugin `version`.
2. Read `.geniro/.geniro-state.json` `vendor.plugin_version` and `vendor.file_manifest`.
3. Recompute the sha256 of every file currently in the plugin source. Compare against the stored manifest hashes. Files whose source hash differs from the stored value are **drifted**. If the recomputed `plugin_source_sha` matches the stored value, there is no drift at all — report "already in sync" and stop.
4. Classify each drifted file:
   - **Verbatim** — `skills/*`, `agents/*` (except backend-agent.md and frontend-agent.md), `hooks/*`. Re-copy and re-rewrite blindly using the same logic as Phases 3 and 4.
   - **Tailored** — `agents/backend-agent.md`, `agents/frontend-agent.md`, anything matching `rules/*`. Compare the vendored copy's current hash against the value stored in `vendor.file_manifest`. If they differ, the user has edited the vendored copy locally; do NOT overwrite. Surface a merge prompt via `AskUserQuestion`:
     - `"Keep mine"` — leave the vendored copy untouched, mark as resolved
     - `"Take upstream"` — overwrite with the new plugin version
     - `"Show diff and decide"` — print `diff` output, then re-ask
5. After all re-copies, re-run **Phase 4** (hook translation may have changed if `hooks.json` was updated) and **Phase 5** (write the new state file with refreshed hashes and `plugin_version`).
6. Re-run **Phase 6** verification.
7. Report what was updated, what was kept, and what was skipped.

## Compliance — Do Not Skip Phases

| Your reasoning | Why it's wrong |
|---|---|
| "I'll skip the v29 mutual-exclusion warning — the user probably already knows" | Hooks firing twice is silent corruption: state files double-written, secrets scanned twice, token cost doubled. The warning is mandatory in Phase 1 and Phase 7. |
| "I'll overwrite tailored files in resync — they're 'stale'" | User edits to backend-agent.md and frontend-agent.md encode project-specific knowledge that is the entire reason those files exist. Always surface a merge prompt; never overwrite silently. |
| "The marketplace plugin is still installed; I'll vendor anyway without warning" | Always show the uninstall reminder in Phase 7. The doubled-hooks failure mode is silent — the user will not notice until something corrupts. |
| "The user edited .claude/settings.json after vendoring; blow it away and rewrite" | Read-modify-write. Preserve user hooks. The backup at `settings.json.pre-vendor-backup` is the recovery path, not the primary write path. |
| "I'll skip hashing — just copy files" | No hashes means no drift detection in Phase 8. Resync becomes impossible and the user is forced to re-vendor from scratch every plugin update, losing local edits to tailored files. |
| "The prefix rule is simple, I'll inline it in every phase" | Define it ONCE in Phase 2 and reference it by name from Phases 3, 4, and 8. Duplicating the logic verbatim in multiple places is the exact failure mode that broke a previous template change — duplicates drift. |
| "I'll apply sed on macOS without the '' backup arg" | macOS BSD sed requires the empty backup-extension argument. Without it, the command silently no-ops and the rewrites never happen, leaving `${CLAUDE_PLUGIN_ROOT}` references in vendored files that will explode at runtime. |
| "Phase 6 verification is paranoid — skip if Phases 3-5 looked fine" | Phase 6 catches the silent failure modes (sed no-op, JSON corruption, missed rewrites) that the prior phases cannot self-detect. Skipping it ships broken vendors. |
| "I'll rename agent YAML names too, for consistency" | Agent subagent_type lookups will break. Only filenames are prefixed; agent YAML stays UNCHANGED. |

## Definition of Done

- [ ] Phase 0: Plugin source verified, plugin version captured, existing vendor state checked
- [ ] Phase 1: Scope and consequences shown; user consented via AskUserQuestion
- [ ] Phase 2: File manifest built with sha256 hashes; prefix rule defined
- [ ] Phase 3: Skills, agents, and hooks copied with prefixed names; `${CLAUDE_PLUGIN_ROOT}` references rewritten via grep-discovered targets; skill YAML names colon-stripped; agent YAML names untouched
- [ ] Phase 4: settings.json backed up; hooks.json translated and merged preserving user hooks; resulting JSON validated
- [ ] Phase 5: `.geniro/.geniro-state.json` extended with `mode: "vendored"` and `vendor` block; existing fields preserved
- [ ] Phase 6: All six verification checks passed
- [ ] Phase 7: Final report shown with marketplace-uninstall reminder and slash-command name change
- [ ] Phase 8 (only if `--sync`): drift classified, tailored conflicts surfaced via AskUserQuestion, verbatim files re-copied, state refreshed, verification re-run
