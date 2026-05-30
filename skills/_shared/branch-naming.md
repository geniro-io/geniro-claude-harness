# Branch / worktree slug derivation

**Status:** Authoritative for deriving the slug used in branch names (`git checkout -b <slug>`), worktree paths (`.claude/worktrees/<slug>/`), and the `BRANCH_MATCHES_TASK_SLUG` signal. Consumed by `/geniro:implement` (Phase 1 Step 0 workspace setup) and `/geniro:review` (Phase 1 triage worktree creation).

## When to use

A skill needs a short, filesystem-safe, human-readable slug for a working branch or worktree, derived from whatever task context is available. Resolve it once and reuse it for the branch name, the worktree directory, and slug-match checks.

## Slug source order

Walk this order and take the first that yields a non-empty value:

1. **`$ARGUMENTS`** — when the invocation names a target explicitly (a Linear/Jira ticket ID, a short phrase). Use the ticket ID verbatim if present (`PROJ-123`), otherwise the first meaningful token group.
2. **`spec.title`** — the spec.md frontmatter `title:` when a spec is in scope.
3. **Suggested branch** — any `suggested-branch:` / `branch:` hint carried in spec.md frontmatter or a handoff file.
4. **Fallback** — the first 3–5 significant words of the task description.

## Normalization

Turn the chosen source into a slug:

- Lowercase; replace runs of non-alphanumeric characters with a single hyphen; trim leading/trailing hyphens.
- Cap length at ~40 characters (cut on a word boundary).
- Drop filler words (`the`, `a`, `and`, `to`, `for`) only when needed to fit the cap.
- Preserve a ticket ID intact when one is present — never hyphen-split `PROJ-123`.

Example: task "Add rate-limiting to the upload endpoint" → `rate-limiting-upload-endpoint`. Ticket "PROJ-123: fix flaky login test" → `proj-123-fix-flaky-login-test`.

## Branch-format-rule conformance

When `BRANCH_FORMAT_RULE` is set (extracted from `.geniro/instructions/global.md` — e.g. a required `<type>/<ticket>-<desc>` shape, a ticket-prefix requirement, or a regex), the slug MUST conform to that pattern BEFORE it is used to create a branch:

- Compose the required components around the normalized slug (e.g. `feat/proj-123-rate-limiting-upload-endpoint`).
- If the rule requires a ticket ID and none is in scope, surface the gap to the user rather than inventing one.
- A worktree directory path may use the bare normalized slug even when the branch name carries the full formatted shape; keep the two consistent enough that slug-match checks still succeed.

## Slug-match check (`BRANCH_MATCHES_TASK_SLUG`)

To decide whether the current branch already corresponds to the task, substring-match the normalized slug against `CURRENT_BRANCH` (case-insensitive). A match means the branch was created for this task; skip re-creating a branch and continue on it. The ticket ID alone is a sufficient match when one is in scope.
