# `.gitignore` re-include — keep a `.geniro/` subdirectory committed

Canonical procedure for keeping one or more `.geniro/` subdirectories tracked in git while the rest of that tree stays ignored. Consumers: `/geniro:setup` (the `workflow` + `instructions` directories it creates) and `/geniro:actions` (the `actions` directory). Define once here; each consumer passes its own directory list rather than inlining a second copy.

## Caller contract

| Slot | Meaning |
|---|---|
| `PRIMARY_ROOT` | Main worktree path, resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A inside the same Bash call (Mode A owns the recompute-per-call rule). The negation belongs beside the content it negates, so it targets the primary worktree's `.gitignore`. |
| `<DIRS>` | The `.geniro/` subdirectories that must stay committed, space-separated — e.g. `workflow instructions` or `actions`. |

## Procedure

Edit `$PRIMARY_ROOT/.gitignore` — and only when it already exists, since creating one from scratch would start ignoring files the project deliberately tracks. Keep the in-place edit portable to BSD as well as GNU userland; this plugin ships to both.

Drop any bare `.geniro/` line first: git cannot re-include a path whose parent directory is excluded, so that one line ignores the whole tree and defeats every negation below.

Then append, in this order and each line only when it is absent (so re-runs are idempotent): `.geniro/*`, `!.geniro/`, then `!.geniro/<dir>/` and `!.geniro/<dir>/**` per directory in `<DIRS>`. The order is load-bearing — git takes the last matching pattern, so each negation must follow the `.geniro/*` line it re-includes from.

A user who wants one of these directories ignored deletes its two `!` lines by hand.

## Why negation rather than `git add -f`

Force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — in a real incident that click wiped user-authored `.geniro/actions/*.md` files after they had been force-added. `.gitignore` negation is the supported path for `.geniro/` content that should be tracked; the `.geniro/` deletion guard hook blocks `git add -f` on those paths for the same reason.
