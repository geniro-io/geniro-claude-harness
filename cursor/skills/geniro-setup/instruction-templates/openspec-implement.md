<!-- Generated from skills/setup/instruction-templates/openspec-implement.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

## Additional Steps

### After ship

<!--
After the implementation PR merges, archive the corresponding OpenSpec change (merge its requirement
deltas into the durable specs) using THIS repo's own tooling. Additive and fail-open. /geniro:setup
installed this block because it detected `openspec/`.
-->

This project uses OpenSpec. When the work for an OpenSpec-tracked change has shipped and merged, archive that change so its requirement deltas fold into the durable `openspec/specs/`. Use the repo's own tooling — run `/opsx:archive` (or `openspec archive <change-id>` when the CLI is installed) — do not hand-merge the deltas; the tooling is the authority on the merge shape. The change-id is the one the plan's `### After user-approve` step created (cross-linked from the Geniro spec). Skip when no OpenSpec change corresponds to this work, or when the PR has not yet merged (archive runs post-merge). Fail-open: an archive failure surfaces a caveat but never blocks the ship.
