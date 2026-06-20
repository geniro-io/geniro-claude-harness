# workflow_refs[] — canonical cross-skill schema

Single source of truth for the `workflow_refs[]` frontmatter contract. `/geniro:plan` produces it in a spec's frontmatter; `/geniro:implement`, `/geniro:review`, `/geniro:debug`, and `/geniro:refactor` read it. Because it is a cross-skill contract, it lives here rather than in any one skill's files — every producer and consumer cites this file so the shape and the version rule cannot drift between them.

## Per-entry shape

Each `workflow_refs[]` entry:

| Field | Required? | Purpose |
|---|---|---|
| `kind` | yes | Workflow-file slug — `linear` / `jira` / `github-issues` / `asana`. Selects the matching `.geniro/workflow/<kind>.md` contract. |
| `issue_id` | yes | Tracker-native identifier (e.g., `CI-303`, `PROJ-42`). |
| `url` | yes | Full canonical URL. Downstream consumers may open without re-derivation. |
| `fetched_at` | yes | ISO-8601 UTC. Staleness check — downstream skills re-fetch if > 1 hour old. |
| `title`, `suggested_branch`, `status` | no | Cache of last-fetched payload. /geniro:implement Step 0 uses these to pre-fill AUQ defaults without re-fetching. |
| `parent_ref` | no | Epic/parent linkage. /geniro:review Phase 1 peer-PR scout uses this for `linear_bonus` ranking. Same per-entry shape recursively. |
| `parent_ref.title` | no (m5-v3) | Parent epic title — primes the related-task chain context per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/task-chain-context.md`. |
| `parent_ref.status` | no (m5-v3) | Parent epic status at chain-fetch time. |
| `parent_ref.scope` | no (m5-v3) | Short epic scope sentence, ≤280 chars, trimmed at a sentence boundary. |
| `siblings` | no (m5-v3) | Depth-1 sibling sub-tasks under the same parent — list of `{issue_id (required), title (optional), status (optional)}`. ≤8 entries, block ≤~1200 chars; omit the key when there are none. Primes the related-task chain context. |
| `chain_fetched_at` | no (m5-v3) | ISO-8601 UTC. When the related-task chain enrichment was fetched — staleness-checked INDEPENDENTLY of `fetched_at` (/geniro:implement re-fetches the chain if > 1 hour old). |

## Schema-version compatibility

`geniro_schema_version: m5-v1` (legacy, no `workflow_refs`), `m5-v2` (`workflow_refs[]` without chain enrichment), `m5-v3` (chain-enrichment fields present), and `m5-v4` (adds the optional `launch_config` block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/launch-config-schema.md`) are ALL valid downstream. Every reader that accepts `m5-v1` OR `m5-v2` OR `m5-v3` must also accept `m5-v4` — each version's additions are purely additive and optional, so a reader rejecting a newer value would fall back to prose-mode and lose the structured tracker linkage. Strict validators (e.g., `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` check #14) verify the field shape on `m5-v2` OR `m5-v3` OR `m5-v4`; the check is skipped on legacy `m5-v1`.

## Mutation responsibility

`/geniro:plan` is a tracker reader only — its Phase 1 fetch pulls issue context to inform planning and its Phase 6 write copies the cached payload into spec.md frontmatter; both are local-write only, never a POST to the tracker. Tracker mutation (status transitions) is owned by `/geniro:implement` (kickoff + Ship). Neither skill ever CREATES tracker artifacts (tickets, issues, epics, sub-tasks) — creation is a human authoring action, not a code-execution side-effect. The other consumers of `workflow_refs[]` (`/geniro:review`, `/geniro:debug`, `/geniro:refactor`) are read-only on the tracker.
