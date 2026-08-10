# Release plugin

One skill: `/geniro:tag`.

## Safety hooks

| Hook | Blocks | Bypass ID |
|---|---|---|
| `hooks/block-bulk-tag-push.sh` | `git push --tags` in any form, including `git -C dir push --tags` | `bulk-tag-push` |

A bypass ID listed in `.plugin/safety.json` `allow_patterns` turns its hook off
for the whole project. An alias that supplies `--tags` from its expansion is
out of the hook's reach — the flag never reaches the command string.

## Skills deleted

| Removed | Use instead |
|---|---|
| `/geniro:publish` | the CI job the tag triggers |
| `/geniro:changelog` | `/geniro:tag` Phase 1 |
