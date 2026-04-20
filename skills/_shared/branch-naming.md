# Branch Naming

A shared procedure that builds a git branch name which follows the calling repo's convention instead of a hardcoded prefix. Callers invoke this whenever they need to create a new branch (direct `git checkout -b`, or `git worktree add -b`). Never hardcode `feat/<slug>` or `implement-<slug>` at the call site — route through this procedure so conventions stay consistent across `/geniro:implement`, `/geniro:follow-up`, and any future skill that branches.

## Caller contract

- **Callers provide:** the task description (spec title or `$ARGUMENTS`), optional explicit task ID, optional `$ARGUMENTS` string to mine for task IDs.
- **Callers receive:** the final branch name as a string (e.g., `feat/ci-22-case-radar-timeline`). Callers are responsible for passing it to `git checkout -b`, `git worktree add -b`, or equivalent.

## Procedure

### Step 1 — Check explicit overrides

Read `.geniro/instructions/global.md` and `.geniro/instructions/implement.md` if they exist. If either contains an explicit branch-naming rule (e.g., "Always prefix with `gh/`", "Use the linear ID lowercased"), apply it verbatim and skip to Step 5. Record which instruction file won.

### Step 2 — Detect the prefix from recent branches

Run:
```bash
git for-each-ref --format='%(refname:short)' --count=50 --sort=-committerdate refs/heads refs/remotes/origin
```

Match each line against the regex `^(origin/)?(feat|feature|fix|bugfix|bug|hotfix|chore|refactor|docs|doc|test|tests|perf|style|ci|build|release)/` (case-insensitive). Strip the `origin/` prefix before matching.

Count the matches grouped by prefix (`feat`, `feature`, `fix`, etc.). The winning prefix is the one with **≥ 3 matches AND a strict majority** among matched branches. If no prefix wins, fall through to Step 3.

Match the type to the task intent when possible:
- task wording about "fix", "bug", "regression" → prefer `fix` (or `bugfix`/`hotfix` if that's the winner's family)
- task wording about "refactor", "rename", "cleanup" → prefer `refactor` (or `chore` if that family wins)
- anything else → prefer `feat` (or `feature` if that family wins)

If the detected winner belongs to a different family than the task intent but the caller wants to honor the repo's convention, go with the detected winner and note the mismatch in the output.

### Step 3 — Fall-back prefix

If Step 2 produced no winner, use `feat/` as the default. Do not invent exotic prefixes.

### Step 4 — Extract the task ID

From the caller's inputs (task description, `$ARGUMENTS`, spec title), match the first occurrence of `\[?([A-Z][A-Z0-9]+-\d+)\]?` (e.g., `[CI-22]`, `ENG-123`, `ABC-7`). Lowercase the result (`CI-22` → `ci-22`). If nothing matches, the task has no ID — emit without it.

### Step 5 — Slugify the description

From the task title/description:
1. Strip any matched task-ID bracket (`[CI-22] Phase 2b — Case Radar…` → `Phase 2b — Case Radar…`).
2. Strip leading metadata markers like `Phase <N>`, `Step <N>`, `Part <N>`, `v<N>` (with an optional letter suffix such as `2b`) when they appear as the first token. `Phase 2b — Case Radar…` → `Case Radar…`. Keep the marker if it is the ONLY descriptive content (e.g., task literally called "Phase 2").
3. Lowercase. Replace non-alphanumeric runs with single hyphens. Drop leading/trailing hyphens.
4. Drop leaky filler words when they appear as full tokens: `a`, `an`, `the`, `for`, `to`, `and`, `of`, `in`, `on`, `with`, `implement`, `add`, `update` (the last three only when they're the first token and redundant with the prefix type — e.g., `feat/add-oauth` becomes `feat/oauth`).
5. Trim to **40 characters max**, cutting at the last hyphen so you don't break a word.

### Step 6 — Assemble

- If task ID present: `<type>/<task-id>-<slug>` (e.g., `feat/ci-22-case-radar-timeline`)
- If no task ID: `<type>/<slug>` (e.g., `feat/case-radar-timeline`)

Reject and re-slug if the total length exceeds **60 characters** — trim the slug further, never the task ID or prefix.

### Step 7 — Collision check

Run `git show-ref --verify --quiet "refs/heads/<branch-name>"`. If the branch already exists locally, append `-2`, `-3`, … to the slug (before any trimming) until free.

## Worked examples

| Task input | Detected prefix | Task ID | Slug | Final name |
|---|---|---|---|---|
| `[CI-22] Phase 2b — Case Radar unified timeline + domain-event ingestion` | `feat/` | `ci-22` | `case-radar-unified-timeline-domain-event` (after stripping `Phase 2b` per Step 5.2; then trimmed to 40 at last hyphen) | `feat/ci-22-case-radar-unified-timeline-domain-event` |
| `Fix intermittent 500 on /api/orders` (repo uses `fix/`) | `fix/` | — | `intermittent-500-on-api-orders` | `fix/intermittent-500-on-api-orders` |
| `Refactor auth middleware` (repo uses `refactor/`) | `refactor/` | — | `auth-middleware` | `refactor/auth-middleware` |
| `[ENG-456] Add OAuth flow` (repo uses `feature/`) | `feature/` | `eng-456` | `oauth-flow` | `feature/eng-456-oauth-flow` |

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll just use `feat/<slug>` — every repo uses that" | Step 2 exists because repos disagree. `feature/`, `fix/`, `bugfix/` are all common. Detect, don't guess. |
| "Scanning 50 refs is overkill for a one-shot branch name" | One `git for-each-ref` call is tens of ms. Picking the wrong prefix forces the user to rename the branch and re-open the PR. |
| "I'll add the `worktree-` prefix to match EnterWorktree's behavior" | Callers that want a clean branch name use `git worktree add -b <name>` + `EnterWorktree(path:)` to bypass the tool's auto-prefix. This procedure produces the desired final branch name; do not pre-mangle it. |
| "The task ID looks like `ci-22` lowercased — I'll uppercase it back" | Branch names are lowercase by convention across every major git host's UI. Uppercase works mechanically but breaks grep and tab-completion. Keep it lowercase. |
| "I'll write my own slug logic inline in the caller" | Duplicated slug logic drifts. Always invoke this procedure. If it's missing a rule you need, extend the procedure — don't fork it. |
