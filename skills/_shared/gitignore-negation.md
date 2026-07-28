# `.gitignore` re-include — keep a `.geniro/` subdirectory committed

Canonical procedure for keeping one or more `.geniro/` subdirectories tracked in git while the rest of that tree stays ignored. Consumers: `/geniro:setup` (the `workflow` + `instructions` directories it creates) and `/geniro:actions` (the `actions` directory). Define once here; each consumer passes its own directory list rather than inlining a second copy.

## Caller contract

| Slot | Meaning |
|---|---|
| `PRIMARY_ROOT` | Main worktree path, resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A inside the same Bash call (Mode A owns the recompute-per-call rule). The negation belongs beside the content it negates, so it targets the primary worktree's `.gitignore`. |
| `<DIRS>` | The `.geniro/` subdirectories that must stay committed, space-separated — e.g. `workflow instructions` or `actions`. |

## Procedure

Substitute `<DIRS>` for the caller's directory list; everything else is invariant.

```bash
GI="$PRIMARY_ROOT/.gitignore"
if [ -f "$GI" ]; then
  # A bare `.geniro/` line ignores the whole tree and defeats every negation below — drop it first.
  sed -i.bak '/^\.geniro\/$/d' "$GI" && rm -f "$GI.bak"
  add_line() { grep -qxF "$1" "$GI" 2>/dev/null || printf '%s\n' "$1" >> "$GI"; }
  add_line ".geniro/*"
  add_line "!.geniro/"
  for d in <DIRS>; do
    add_line "!.geniro/$d/"
    add_line "!.geniro/$d/**"
  done
fi
```

Four lines are appended — `.geniro/*`, `!.geniro/`, `!.geniro/<dir>/`, and `!.geniro/<dir>/**` — with the last two repeating per directory. Each line is appended only when absent, so re-runs are idempotent.

Write only when `.gitignore` already exists — creating one from scratch would start ignoring files the project deliberately tracks.

A user who wants one of these directories ignored deletes its two `!` lines by hand.

## Why negation rather than `git add -f`

Force-adding ignored files makes them visible in IDE Source Control panels, and a single "Discard All Changes" click then becomes a one-click data-loss vector — in a real incident that click wiped user-authored `.geniro/actions/*.md` files after they had been force-added. `.gitignore` negation is the supported path for `.geniro/` content that should be tracked; the `.geniro/` deletion guard hook blocks `git add -f` on those paths for the same reason.
