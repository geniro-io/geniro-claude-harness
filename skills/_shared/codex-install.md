# Codex install — detect, source, install, refresh

The `codex` CLI mechanics for getting Geniro into OpenAI Codex. Consumers: `/geniro:setup` §3.8 (installs) and `/geniro:update` Phase 3 Step 6 (refreshes an existing install, or installs one). Each caller owns its own gating and reporting.

## Names

`<plugin>` and `<marketplace>` are the `name` fields of `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` under the plugin root the caller resolved.

## Detect

Requires `codex` on PATH. Query with `codex plugin list --json -m <marketplace>`: the plain-text `codex plugin list` also pulls OpenAI's remote catalog and shows a filesystem path for Git installs too, so it cannot tell the source type.

- The plugin in `installed` is installed; its entry carries `enabled` and `marketplaceSource.sourceType`.
- The plugin in `available` means the marketplace is configured and the plugin is not installed.
- Both lists empty means the marketplace is not configured.

A non-zero exit or unparsable output is a failure to report, not an absent install.

## Install source

A source is needed only when Detect found the marketplace not configured — §Install skips `marketplace add` otherwise. Take `installLocation` from `$CLAUDE_USER_DIR/plugins/known_marketplaces.json` for the marketplace whose checkout's `.claude-plugin/plugin.json` names this plugin; otherwise the resolved plugin root. Accept a source only when it is a checkout — never one under `plugins/cache/`: Codex records the path, and a removed versioned cache dir breaks every `codex plugin` command. A local source needs no network. When a source is needed and no such source exists, do not install: the caller reports that and sends the user to `${CLAUDE_PLUGIN_ROOT}/README.md` §Using with Codex to install by hand.

## Install

Run `codex plugin marketplace add "<source>"` — skipped when Detect found the marketplace configured — then `codex plugin add <plugin>@<marketplace>`. Report the "Installed plugin root" line it prints, and pass on any error output rather than dropping it. Re-run Detect and record the version it shows. On success the user needs two facts: trust the plugin's hooks once in Codex's `/hooks`, and run skills as `$geniro:<slug>`.

## Refresh

For a plugin already installed. When the entry has `enabled: false`, change nothing and report "installed but disabled — left as is": `codex plugin add` re-enables a disabled plugin. Otherwise branch on `marketplaceSource.sourceType`:

- `local` — `codex plugin add <plugin>@<marketplace>` re-copies the plugin from the source.
- `git` — `codex plugin marketplace upgrade <marketplace>` refreshes the marketplace and reinstalls the plugin.

Re-run Detect and record the version it shows, or the error on failure.

A failed install or refresh is reported and never blocks the caller's phase.
