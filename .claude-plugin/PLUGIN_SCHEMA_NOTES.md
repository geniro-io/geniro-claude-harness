# Plugin manifest schema notes

Contributor reference for editing the two manifests in this directory:

- `plugin.json` — the plugin manifest (identity + metadata).
- `marketplace.json` — the marketplace manifest that lists this plugin as a source.

These notes document the Claude-Code plugin-manifest rules **as they apply to Geniro's actual files** — what is required, what is intentionally omitted, and the symptom you'll see if you trip a rule. Read this before changing either file so you don't regress a constraint that the validator or installer enforces.

## Contents

- Design principle: convention over declaration
- `plugin.json` field rules
- `marketplace.json` field rules
- Component declaration (hooks, agents, skills, commands, statusline)
- MCP servers — opt-out by omission
- Version field — format and sync
- Pre-commit checklist

## Design principle: convention over declaration

Geniro relies on Claude Code's **auto-discovery** of components from convention directories. `plugin.json` carries identity/metadata ONLY — it contains zero component fields (`hooks`, `agents`, `skills`, `commands`, `statusLine`, `mcpServers` are all absent). Each component type is found by directory/file convention instead:

| Component | Where Geniro keeps it | How it's wired |
|---|---|---|
| Skills | `skills/<slug>/SKILL.md` | Auto-discovered by directory convention. |
| Agents | `agents/<name>.md` | Auto-discovered by directory convention. |
| Hooks | `hooks/hooks.json` | Auto-discovered by the `hooks/hooks.json` convention path — NOT declared in `plugin.json`. |
| Statusline + update check | root `settings.json` (`statusLine`) + `hooks/hooks.json` (`SessionStart`) | Statusline command lives in `settings.json`, NOT in `plugin.json`. |
| Commands | (none — Geniro ships no `commands/` directory) | n/a |

Keep this split intact. If you add a component field to `plugin.json` that duplicates an auto-discovered path, you risk double-registration or a validator complaint. The default and correct path is to add files in the convention directory, not to extend `plugin.json`.

## `plugin.json` field rules

Geniro's `plugin.json` (verbatim shape):

```json
{
  "name": "geniro-claude-plugin",
  "description": "...",
  "version": "<semver>",
  "author": { "name": "Geniro", "email": "hello@geniro.io" },
  "repository": "https://github.com/geniro-io/geniro-claude-harness",
  "license": "Apache-2.0",
  "keywords": ["harness", "setup", "multi-agent", "code-review", "safety-hooks"]
}
```

| Field | Required? | Type | Rule | Symptom if wrong |
|---|---|---|---|---|
| `name` | Required | string | Lowercase, hyphenated; must match the `plugins[].name` in `marketplace.json`. No reserved words (`anthropic`, `claude` as the whole name). | Name mismatch → marketplace can't resolve the plugin; install fails to find it. |
| `description` | Recommended | string | One-line summary shown in plugin listings. | Missing → bare listing, no install break. |
| `version` | Required | string | Semver `MAJOR.MINOR.PATCH` (see Version field section). | Non-semver or missing → update-check hook reads `'unknown'` and can't compare; some validators reject. |
| `author` | Optional | object | Object with `name` (+ optional `email`). It is an OBJECT, not a string. | Passing a bare string where an object is expected → schema/validation error. |
| `repository` | Optional | string | Plugin source URL. | None. |
| `license` | Optional | string | SPDX identifier (`Apache-2.0`). | None. |
| `keywords` | Optional | array of strings | Must be a JSON array, never a single string. | A string instead of an array → schema-validation failure (a value that must be an array must not be a string). |

**The array-vs-string rule is the most common trip.** Any field whose value is conceptually a list (`keywords`, and component arrays if you ever add them) must be a JSON array `[...]`, even with one element. Writing `"keywords": "harness"` instead of `"keywords": ["harness"]` fails validation. Same for `author`: it is an object literal, not a display string.

## `marketplace.json` field rules

Geniro's `marketplace.json` (verbatim shape):

```json
{
  "name": "geniro-claude-harness",
  "owner": { "name": "Geniro", "email": "hello@geniro.io" },
  "plugins": [
    {
      "name": "geniro-claude-plugin",
      "description": "...",
      "source": "./",
      "category": "development"
    }
  ]
}
```

| Field | Required? | Type | Rule | Symptom if wrong |
|---|---|---|---|---|
| `name` | Required | string | Marketplace identifier (`geniro-claude-harness`) — distinct from the plugin's own `name`. This is the marketplace, not the plugin. | Wrong name → `claude plugin update geniro-claude-plugin@geniro-claude-harness` can't locate the marketplace. |
| `owner` | Optional | object | Object with `name` (+ optional `email`), same object-not-string rule as `plugin.json` `author`. | String instead of object → validation error. |
| `plugins` | Required | array | Must be a JSON array of plugin entries, even with one plugin. | A single object instead of an array → schema failure. |
| `plugins[].name` | Required | string | Must equal `plugin.json` `name` (`geniro-claude-plugin`). | Mismatch → marketplace lists a plugin the installer can't map to the manifest. |
| `plugins[].source` | Required | string | `"./"` — the plugin lives at the repo root (the manifest dir's parent). | Wrong source path → install fetches the wrong directory or fails. |
| `plugins[].description` | Optional | string | Listing blurb. | None. |
| `plugins[].category` | Optional | string | Marketplace category (`development`). | None. |

**`marketplace.json` carries NO `version` field.** Because `source: "./"` points at the same repo, the installable version comes from `plugin.json`. Do not add a `version` to the marketplace entry — it would be a second source of truth that drifts (see Version field section).

## Component declaration (hooks, agents, skills, commands, statusline)

- **Hooks are NOT declared in `plugin.json`.** They live in `hooks/hooks.json`, keyed by event (`PreToolUse`, `Stop`, `SessionStart`). Each hook command references `${CLAUDE_PLUGIN_ROOT}` so paths resolve in the installed location. Adding a `hooks` field to `plugin.json` is redundant and risks double-registration — keep all hook wiring in `hooks/hooks.json`.
- **Agents and skills are NOT declared in `plugin.json`.** They are auto-discovered from `agents/*.md` and `skills/<slug>/SKILL.md`. Adding the files registers them; no manifest edit needed.
- **The statusline is NOT in `plugin.json`.** It is configured in root `settings.json` under `statusLine` (`node "${CLAUDE_PLUGIN_ROOT}/hooks/geniro-statusline.js"`). Don't move it into `plugin.json`.
- **No `commands/` directory exists.** Geniro exposes slash commands through skills (`/geniro:plan`, etc.), not via a `commands/` tree. There is no `commands` field to maintain.

**Symptom of getting component declaration wrong:** if you "helpfully" add explicit `hooks`/`agents`/`skills` arrays to `plugin.json` pointing at the same files, the runtime may register each component twice (hooks fire twice, agents appear duplicated) or reject the manifest if the inline shape differs from the file-convention shape. The safe rule: components go in their convention directories; `plugin.json` stays metadata-only.

## MCP servers — opt-out by omission

Geniro ships **no MCP servers of its own** and has **no `.mcp.json`** in the repo. The `mcpServers` field is simply absent from `plugin.json`.

- For this plugin, omission is the correct opt-out — there is no validator error from leaving `mcpServers` out entirely.
- Do NOT add an empty `"mcpServers": {}` object speculatively. If a future Claude-Code validator version requires an explicit empty object to distinguish "no MCP servers" from "field missing," add `"mcpServers": {}` (an empty OBJECT, not `[]` and not `""`) — that empty-object form is the canonical opt-out that avoids the validator error. Until a validator actually demands it, keep the field absent to match the current working manifest.
- Optional MCP companions that Geniro skills *consume* (e.g. Playwright) are documented in `CLAUDE.md` §Optional MCP Dependencies and installed by the user as sibling plugins — they are not declared in this plugin's manifest.

## Version field — format and sync

- `plugin.json` `version` is the **single source of truth for the installed-side version** (format is semver `MAJOR.MINOR.PATCH`; see `plugin.json` for the current value). The qualifier matters: the installed version comes from `plugin.json`, but whether an update PROMPT fires also depends on a matching GitHub Release tag existing (see the hook mechanics below).
- The update-check hook (`hooks/geniro-check-update.js`) compares two versions. The **installed** side (`getInstalledVersion`) reads `manifest.version` from the local `plugin.json`. The **latest** side (`getLatestVersion`) primarily queries the GitHub Releases API (`/repos/geniro-io/geniro-claude-harness/releases/latest`) and reads `tag_name` with a leading `v` stripped; only if that call fails does it fall back to fetching the `version` field from `plugin.json` on the `main` branch. `compareVersions` then does the semver comparison to decide whether to surface an update. A non-semver or missing version makes the installed side read `'unknown'`, breaking the comparison and the update prompt. Because the primary path reads release tags, no GitHub Release tag means no update prompt even when `main`'s `plugin.json` is ahead — until the fallback path catches the bump.
- `marketplace.json` deliberately has no `version`. Because its `source` is `"./"`, the version is whatever `plugin.json` says. Keeping version in exactly one file means there is nothing to sync and nothing to drift.

**Sync rule:** bump `version` in `plugin.json` ONLY. If you ever add a second copy (e.g. a `version` in the marketplace entry, or a `package.json`), you create two sources that drift — the update hook reads the installed version from `plugin.json` (and its release-tag fallback re-reads the same field on `main`), so a stale duplicate elsewhere silently misreports. Don't introduce a second version field. For the update PROMPT to fire on a bump, cut a matching GitHub Release tag — the hook's primary path reads `tag_name`, not `plugin.json`.

**Symptom of a bad version:** wrong/absent semver → the SessionStart update-check can't compare, so users never see "update available," or a stricter validator rejects the manifest at install time.

## Pre-commit checklist

Before committing a change to either manifest:

1. **JSON validity** — `jq -e . .claude-plugin/plugin.json` and `jq -e . .claude-plugin/marketplace.json` both exit 0. A trailing comma or unquoted key fails install outright.
2. **Names match** — `plugin.json` `name` == `marketplace.json` `plugins[0].name` == `geniro-claude-plugin`.
3. **Arrays are arrays** — `keywords` and `plugins` are `[...]`; `author` and `owner` are `{...}`. No string-where-array (or string-where-object) regressions.
4. **No component fields crept into `plugin.json`** — `grep -E '"(hooks|agents|skills|commands|statusLine)"' .claude-plugin/plugin.json` returns nothing; components stay in their convention directories.
5. **`mcpServers`** — still absent (or, only if a validator now demands it, an empty object `{}`).
6. **Version** — `plugin.json` `version` is valid semver and is the only `version` field across `.claude-plugin/`.
