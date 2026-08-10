# Release plugin

One skill ships here: `/geniro:deploy`.

## Safety

Force pushes to protected branches are blocked by a hook. Pushes that would
delete a remote branch are blocked by the same pre-push guard.

## Skills deleted

| Removed | Use instead |
|---|---|
| `/geniro:rollout` | `/geniro:deploy` |
| `/geniro:verify-release` | `/geniro:deploy` Phase 2 |
