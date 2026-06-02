# Phase 1 Triage Reference

Detailed contract for `/geniro:review` Phase 1 (Triage & Context Collect). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: triage` during this phase.

## Contents

- §0 Step 0 — Workspace setup
- §1 Input mode detection (3-mode routing)
- §2 Scope resolution
- §3 PR-ref input parsing
- §3.5 Workflow integrations (issue-tracker fetch)
- §4 Peer-PR scout (PR-ref input only)
- §5 reserved — scope resolution is covered under §2 above
- §6 L4 instructions load
- §7 Step 0.5 — Round-N counter
- §8 Step 0.6 — PLAN CONTEXT load (schema-aware)
- §9 Step 0.7 — Risk-tier stratification
- §10 Step 0.8 — Memory layer load
- §11 Mode AUQ (Standard vs TDD)
- §12 Size triage

---

## 0. Step 0 — Workspace setup

Step 0 fires BEFORE input-mode detect, scope resolution, PR-ref parsing, workflow-integration fetch, peer-PR scout, and L4 / L3 / L2 helper calls. Workspace decision determines the working tree the rest of Phase 1 inspects; running PR-diff parsing or peer-PR `gh pr list` against the wrong worktree pollutes state.md with cwd-bound results.

Two sub-steps: **passive detection** (0a, no AUQ) → **decide action** (0b, auto-continue or AUQ).

### 0a — Detect current context (passive)

Collect these signals before deciding:

| Signal | How detected |
|---|---|
| `CURRENT_BRANCH` | `git branch --show-current` |
| `CURRENT_TOPLEVEL` | `git rev-parse --show-toplevel` |
| `IN_WORKTREE` | `CURRENT_TOPLEVEL` is registered in `git worktree list --porcelain` AND is NOT the porcelain `bare` row or the main worktree row. Porcelain registry is the source of truth; the `.claude/worktrees/<slug>/` path convention is a sanity check, NOT the primary signal. |
| `PROTECTED_BRANCH` | `CURRENT_BRANCH ∈ {main, master, develop, trunk}` (per-project override via `.geniro/safety.json`) |
| `EXISTING_REVIEW_STATE` | Glob `.geniro/state/handoff/from-review-<CURRENT_BRANCH>.md` ⇒ "prior /geniro:review run on this branch" |
| `REVIEW_HANDOFF` | Alias for `EXISTING_REVIEW_STATE` — re-running /geniro:review means the user is in fix-up or follow-up review mode |
| `DEBUG_HANDOFF` | Path `.geniro/state/handoff/from-debug-<CURRENT_BRANCH>.md` exists ⇒ "/geniro:debug just authored repro tests for this branch" |
| `IMPLEMENT_TASK_STATE` | Glob `.geniro/planning/*/state.md`; any state.md whose frontmatter `branch:` equals `CURRENT_BRANCH` ⇒ "active or completed /geniro:implement run on this branch" |
| `TARGET_PR_NUMBER` | If `$ARGUMENTS` carries a PR ref: extract `<N>`. Else null. |
| `TARGET_WORKTREE_NAME` | If `TARGET_PR_NUMBER` is set: `pr-<N>-review`. Else null (no target). |
| `IN_TARGET_WORKTREE` | `IN_WORKTREE == true` AND `CURRENT_TOPLEVEL` basename matches `TARGET_WORKTREE_NAME`. Only meaningful when `TARGET_WORKTREE_NAME` is non-null. |
| `INPUT_SHAPE` | One of `pr-ref` / `branch` / `diff-range` / `files` / `empty` — derived by quick `$ARGUMENTS` inspection (definitive routing happens in §1). |

### 0b — Decide action

Decision tree (first match wins; evaluate top-down):

```
1. IN_TARGET_WORKTREE == true (PR-ref input, already in the correct review worktree)
   ⇒ AUTO-CONTINUE silently. Sanity-check `git rev-parse HEAD` vs PR headRefOid
     (deferred to §3 parsing — mismatch surfaces as warning later, never blocks).

2. IN_WORKTREE == true
   AND CURRENT_BRANCH ∈ continuing-work set:
     • REVIEW_HANDOFF == true, OR
     • DEBUG_HANDOFF == true, OR
     • IMPLEMENT_TASK_STATE == true, OR
     • (TARGET_PR_NUMBER set AND CURRENT_BRANCH substring-matches the PR head ref)
   ⇒ AUTO-CONTINUE in current worktree. NO workspace AUQ. Echo:
        "Continuing in worktree '<dir>' on '<branch>'.
         Detected signal(s): <REVIEW_HANDOFF | DEBUG_HANDOFF | IMPLEMENT_TASK_STATE | branch match>."

3. IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND any of {REVIEW_HANDOFF, DEBUG_HANDOFF, IMPLEMENT_TASK_STATE} == true
   ⇒ AUTO-CONTINUE on current branch. NO workspace AUQ. Echo:
        "Continuing on '<branch>' (detected <signal>).
         Reverse with: re-run with 'worktree' modifier in arguments."

4. INPUT_SHAPE == pr-ref
   AND IN_WORKTREE == true
   AND IN_TARGET_WORKTREE == false
   AND no continuing-work signals match
   ⇒ User is in some other worktree but launched /geniro:review for an unrelated PR.
      Fire 3-option AUQ (header: "Worktree mismatch"):
        A) "Continue here in '<dir>'" — recommended if user explicitly cd'd here
        B) "Exit to repo root and create new worktree '<TARGET_WORKTREE_NAME>'" —
           call ExitWorktree, then standard new-worktree flow (5b below)
        C) "Abort — I'm in the wrong place" — terminal, no-op

5. INPUT_SHAPE == pr-ref
   AND IN_WORKTREE == false
   AND no continuing-work signals match
   ⇒
   5a) If `git worktree list --porcelain` already lists `.claude/worktrees/<TARGET_WORKTREE_NAME>`:
       skip create. `EnterWorktree(path: ".claude/worktrees/<TARGET_WORKTREE_NAME>")`.
       NO AUQ.
   5b) Otherwise: fire 2-option AUQ (header: "Git workspace"):
        A) "Create review worktree (Recommended)" — runs:
             git fetch origin pull/<N>/head:<TARGET_WORKTREE_NAME>
             git worktree add .claude/worktrees/<TARGET_WORKTREE_NAME> <TARGET_WORKTREE_NAME>
             EnterWorktree(path: ".claude/worktrees/<TARGET_WORKTREE_NAME>")
        B) "Review in current location" — continue in current cwd.

6. INPUT_SHAPE ∈ {branch, diff-range, files, empty}
   AND IN_WORKTREE == false
   AND PROTECTED_BRANCH == true
   AND no continuing-work signals match
   ⇒ Fire 2-option AUQ (header: "Git workspace"):
        A) "Create review worktree (Recommended)" — runs:
             git worktree add .claude/worktrees/review-<short-slug> <CURRENT_BRANCH>
             EnterWorktree(...)
           Slug source: spec.title (if resolvable) / `$ARGUMENTS` first token / branch name. Per
           `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md`.
        B) "Review on '<branch>'" — continue in current cwd. State.md notes the protected-branch decision.

7. Default — INPUT_SHAPE ∈ {branch, diff-range, files, empty}
   AND IN_WORKTREE == false
   AND PROTECTED_BRANCH == false
   AND no continuing-work signals match
   ⇒ NO workspace AUQ. Auto-continue on current branch — files-mode and diff-range mode
     operate on cwd-relative file paths; creating a worktree adds friction without value.
```

**Inline modifier overrides** (parsed from `$ARGUMENTS`; modifiers ALWAYS win over auto-detection):

| Modifier in $ARGUMENTS | Effect |
|---|---|
| `worktree` / `new-worktree` | Force the worktree-creation path (rule 5b or 6a) regardless of `IN_WORKTREE` or input shape. |
| `no-worktree` / `here` | Force in-place execution; skip worktree creation even when rule 5 or 6 would otherwise fire. |
| `current-branch` / `current branch` | Force auto-continue on current branch regardless of signals (skips rules 4-6 entirely). |
| `new-branch` / `new branch` | Force fresh-worktree creation path even if a "continuing" signal is detected. |

Conflicting modifiers (e.g., `worktree` AND `no-worktree` both present): last-occurrence wins (right-to-left scan). Emit soft notice naming both detected variants.

### 0c — Approvals-persistence

When the workspace AUQ fires, persist the answer to state.md `approvals[]`:

```yaml
approvals:
  - category: review_workspace_setup
    picked: "Create review worktree (Recommended)"
    timestamp: <ISO-8601>
```

On compaction-resume or Round 2+ re-runs of /geniro:review on the same branch, Step 0 reads `approvals[]` and re-applies the prior answer without re-prompting.

Workflow status transitions (e.g., "Move <issue_id> to In Review?") are NOT part of Step 0 — /geniro:review is a read-only reporter and never mutates external tracker state. Tracker IDs detected from `$ARGUMENTS` / PR body / spec.md frontmatter are read-only context for downstream reviewer dimensions (spec-compliance + pr-metadata + architecture) per §3.5; they are not user-prompted in Step 0. Workflow status mutation belongs to `/geniro:implement` only — Step 0c (kickoff) and Phase 3 Ship (completion); `/geniro:plan`, `/geniro:debug`, `/geniro:refactor`, and `/geniro:review` are all read-only tracker consumers.

### 0d — Execution after AUQ

After AUQ resolves and `approvals[]` is persisted:

1. **Workspace action** — execute worktree create / EnterWorktree / no-op per `review_workspace_setup` pick.
2. State.md frontmatter `branch:` and `worktree:` updated to reflect the new working tree before Phase 1 §1 (input mode detect) runs.

Do NOT use `EnterWorktree(name: ...)` — that path auto-creates with `worktree-` prefix and defeats the `.claude/worktrees/<slug>/` convention. Use `EnterWorktree(path: ".claude/worktrees/<slug>")`.

### 0e — Edge cases

| Case | Behavior |
|---|---|
| User picks "Other" with custom text on the workspace AUQ | Treat as "Review in current location" semantically; no worktree mutation; echo custom text into state.md `## Workspace decision` body block. |
| Multiple continuing signals match (review handoff AND debug handoff) | Both satisfy rule 2 or 3. Echo both signal names; behavior identical. |
| Stale T2 handoff (older than 30 days) | Still triggers rule 2 / 3. Emit soft notice: `"Note: review handoff is N days old."` |
| `IN_WORKTREE == true` AND `IN_TARGET_WORKTREE == true` but PR `headRefOid` mismatches current `HEAD` | Auto-continue per rule 1. Mismatch surfaces as warning in §3 PR-ref parsing, never blocks. User can re-run with `new-branch` modifier to force a fresh fetch. |

After Step 0 settles, every subsequent Phase 1 step and downstream phases run from the new cwd. Cross-session writes (`.geniro/state/handoff/from-review-<branch>.md`, `learnings.jsonl`) auto-route to the main worktree's `.geniro/` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, so they survive worktree teardown.

---

## 1. Input mode detection (3-mode routing)

The pre-step routes `$ARGUMENTS` to exactly one of OUTGOING / INCOMING / pr-ref-driven flow:

| Mode | Trigger | Routing |
|---|---|---|
| OUTGOING (default) | empty `$ARGUMENTS`, branch name, file paths, or diff range | Phase 1.5 mechanical pre-pass |
| INCOMING | PR ref + computed `K > 0` unresolved threads (after AUQ pick) OR anchored NL signals ("process review on #N", "respond to review #N", "incoming review #N") | `incoming-mode-reference.md` Phase I |
| PR ref + K=0 / K=unknown | `gh` fetch fail-open or no unresolved threads | OUTGOING (skips AUQ) |

**PR-ref resolution.** Parse `<owner>/<repo>/<number>` from `$ARGUMENTS`. For a full PR URL, parse the path segments directly; for bare PR number (`#1234` or `1234`), resolve `<owner>/<repo>` from the current repo via `gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'`.

**Thread-state fetch.** MCP-preferred: `mcp__github__pull_request_read` with the resolved owner/repo/number; consume `reviewThreads[]` from the returned payload directly. Fallback when MCP is unavailable:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -F cursor=null -f query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor} nodes{isResolved isOutdated path line}}}}}'
```

Paginate with `endCursor` until `hasNextPage == false` (loop the call, concatenate `nodes[]` across pages — typical PR completes in 1-3 calls, stays under rate-limit budget). Compute `K = count(nodes where isResolved == false && isOutdated == false)`. Outdated threads are excluded from K (referenced code rewritten; comment stale).

**Fail-open behavior.** If the fetch fails (no network, missing token scope, rate limit, pagination loop errored mid-stream): set K to `unknown`, default routing to OUTGOING, surface `PR review-thread fetch failed — defaulting to Outgoing without thread-state awareness` under `## Caveats` in the final report (mirrors Phase 1.5 / 4.2 / 4.3 fail-open).

**INCOMING AUQ.** When K > 0, fire `AskUserQuestion` (do NOT print options as plain text) with header `"Mode"`: `"PR #N has K unresolved threads. Pick mode:"` (substitute the computed K — do NOT render the literal `K`) with options `"Outgoing — author my own review"` / `"Incoming — process reviewer feedback"`.

There is **NO `--incoming` flag**. Explicit override into INCOMING is via the anchored natural-language signals above. Bare keywords without a PR-ref anchor route to OUTGOING.

### 1.1 Existing PR review ingest (formal reviews + inline bot comments)

The thread-state fetch above reads thread STATE (`isResolved`/`isOutdated`/`path`/`line`) for dedup only — it never reads comment BODIES. Automated reviewers (CodeRabbit, Greptile, Sourcery, and other bots) post findings as review-thread comments; a real incident had /geniro:review declare a PR "CLEAN — ship-ready" while CodeRabbit had already flagged a Major bug in scope. Fetch those bodies so they reach the LLM reviewers as prior-context.

Two distinct surfaces carry prior findings: (a) the top-level **formal review** (`reviews(){ state body author }` — APPROVED / CHANGES_REQUESTED / COMMENTED with a summary body, posted by humans AND bots), and (b) **inline review-thread comments** (anchored to `path:line`, mostly bots). A real incident had a run address only the failing-CI commit and inline comments while a teammate's posted formal review — carrying two advisory findings beyond the inline ones — went unread. Read BOTH so neither surface is silently dropped.

For a target PR ref (skip entirely when `INPUT_SHAPE != pr-ref` — OUTGOING runs have no PR to query), extend the thread-state GraphQL to also select comment author + body, OR run a second `gh` call. MCP-preferred path: the `mcp__github__pull_request_read` payload already carries thread comments — read `comments[].author.login` + `comments[].body` from each `reviewThreads[]` node, and the formal reviews too — read `reviews[].state` + `reviews[].body` + `reviews[].author.login`. Fallback GraphQL:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviews(first:50){nodes{state body author{login} submittedAt}} reviewThreads(first:100){nodes{isResolved isOutdated path line comments(first:10){nodes{author{login} body}}}}}}}'
```

Keep only comments whose `author.login` ends in `[bot]` OR matches a known reviewer-bot list (`coderabbitai`, `greptile-apps`, `sourcery-ai`, `codeant-ai`). For the formal **reviews**, the bot-only filter does NOT apply — keep every review whose `state` is `CHANGES_REQUESTED` or `COMMENTED` and whose `body` is non-empty (human reviewers' summaries are the highest-signal surface and must not be filtered out). Skip `APPROVED` reviews with empty bodies. For each kept review capture `{author, state, excerpt}` where `excerpt` is the first ~400 chars of `body` trimmed at a sentence boundary. Cap formal reviews at ~5 / ~2500 chars, newest first. For each kept inline comment, capture a short excerpt: `{path, line, author, excerpt}` where `excerpt` is the first ~280 chars of `body` trimmed at a sentence boundary (drop CodeRabbit's collapsible-HTML scaffolding and `<details>` blocks before trimming). Cap the snapshot at ~12 comments / ~4000 chars total — keep the highest-severity-worded comments first (lines containing `Major` / `Critical` / `Potential issue` / `bug` outrank `nitpick` / `suggestion`).

Persist to state.md frontmatter:

```yaml
pr-bot-comments-snapshot:                # null when no PR ref or fetch failed/empty
  - path: src/api/seeders.ts
    line: 42
    author: coderabbitai[bot]
    excerpt: "Major: seeder runs before migration completes — race on first boot."
pr-formal-reviews-snapshot:              # null when no PR ref or none with bodies
  - author: teammate-login
    state: CHANGES_REQUESTED
    excerpt: "Requesting changes: the new retry path never caps attempts — unbounded backoff under sustained 5xx..."
```

Render two sibling blocks in the spawn prompts of the bugs / architecture / regressions / security dims (per SKILL.md §2.3): a `## Existing PR review comments` block (from `pr-bot-comments-snapshot:`), each entry `- <author> @ <path>:<line> — <excerpt>`; and a `## Existing PR formal reviews` block (from `pr-formal-reviews-snapshot:`), each entry `- <author> (<state>) — <excerpt>`. Each block is omitted when its snapshot is null.

**Fail-open.** No PR ref → set both `pr-bot-comments-snapshot: null` and `pr-formal-reviews-snapshot: null`, skip. Fetch error (network / scope / rate limit) or zero kept entries → set the corresponding snapshot key (`pr-bot-comments-snapshot` and/or `pr-formal-reviews-snapshot`) to `null` and surface `PR review ingest failed — reviewers run without prior formal-review / inline-bot context` under `## Caveats` (mirrors the thread-state fail-open). Never block on this fetch.

---

## 2. Scope resolution

Follow `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md`. The base branch is whatever scope-anchor resolves (PR base, remote `origin/HEAD`, or local `main`/`master` fallback) — do NOT hardcode `main`. Report the resolved target on its own (e.g., "Reviewing working tree — 3 files" or "Reviewing branch diff against `origin/master` — 2 commits, 5 files"). NEVER invoke `gh pr list` to **invent a target** — PR mode triggers ONLY on explicit PR-ref forms.

Read-only `gh pr list` / `gh pr view` / `gh pr diff` calls that gather peer-PR context for an *already-named* target ARE allowed (consume a user-supplied PR ref rather than invent one).

**Harness Auto Mode.** `/geniro:review` has NO auto mode of its own. Do NOT promote "Auto Mode Active" reminder into transcript framing — review has no auto mode.

---

## 3. PR-ref input parsing

For a PR ref, strip leading `#` and resolve with:

- `gh pr diff <number-or-url>` to materialize the diff
- `gh pr view <number-or-url> --json baseRefName,headRefName,body,title,headRefOid,url,isDraft,author,labels` for base/head context, head SHA pin, PR URL, PR body+title (the PR body feeds PLAN CONTEXT below), plus the draft state, author user, and label set

The draft/author/labels feed the pr-metadata reviewer's Common-False-Positives detection (bot-author / draft / release-please-label PRs excluded from rubric-strict checks). Capture the original PR ref, `headRefOid`, and canonical `url` — all three persisted to the state file for Phase 6 Action gate's "Post Draft PR review" option and for `commit_id` pinning (prevents line-anchor drift if PR updates mid-review).

If `gh` is unavailable or the PR cannot be fetched, report the error and stop — do NOT fall back silently to unstaged changes; do NOT run `gh pr list` to "find a related PR".

---

## 3.5. Workflow integrations (issue-tracker fetch)

Read `.geniro/workflow/*.md` integrations, apply each file's argument-detection regex against `$ARGUMENTS` / `pr.title` / `pr.body`, and on a match fetch tracker context via the registered MCP server. Fail-open when the MCP server is unregistered: degrade to regex-only ID detection, surface a `## Caveats` one-liner, never block. Read-only from /geniro:review's perspective; status/comment updates remain in /geniro:implement Ship per `${CLAUDE_PLUGIN_ROOT}/skills/setup/workflow-templates/linear.md` § AI-Disclosure Prefix.

Skipped when `.geniro/workflow/` directory is absent OR empty (workflow not configured by /geniro:setup). Other inputs (files / diff range / branch / PR ref) ALL eligible — tracker IDs surface in `$ARGUMENTS` independently of PR-ref-driven flow.

### 3.5.1 Detection

Workflow files live in the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` (Mode A). Glob both locations — cwd-local wins on collision:

1. `ls ./.geniro/workflow/*.md <PRIMARY_ROOT>/.geniro/workflow/*.md 2>/dev/null` — merge the two listings, deduplicating by basename (cwd-local entry wins when a file exists in both locations; uncommitted local edits beat the primary copy). If zero matches across both, skip entirely.
2. For each unique workflow file, read it and extract the `## Argument Detection` regex patterns (Linear's: `https://linear\.app/.+/issue/([A-Z]+-\d+)` URL form, `\b[A-Z]{2,}-\d+\b` bare-ID form).
3. Apply patterns against (a) `$ARGUMENTS`, (b) `pr.title`, (c) `pr.body` — in that order. First match wins. Multiple matches in one source are deduplicated to the first.
4. Persist the matched tracker ID to state.md frontmatter:
- Linear: `linear-task-ref: <ENG-123|null>` (defaults to `null` when no match).

### 3.5.2 MCP fetch

When a tracker ID is detected AND the corresponding MCP server is registered (heuristic: any tool prefixed `mcp__linear__*` appears in the orchestrator's tool list at runtime — exact tool names depend on the installed MCP server):

1. Fetch the issue: title, description, acceptance criteria (parse `## Acceptance criteria` / numbered AC list from description body), labels, priority, parent issue ID, assignee.
2. **Sub-task fetch (parent epic linkage):** if the fetched issue has a non-null `parent` field, fetch the parent issue AND list its children. Persist:
- `linear-parent-ref: <ENG-100|null>` to state.md frontmatter (the parent issue ID).
- Build `linear-sibling-task-ids:` slot (in-memory only — not state.md frontmatter): list of sibling sub-task IDs from the parent's children. Consumed by peer-PR scout's Linear-relatedness bonus.
3. Build `LINEAR CONTEXT:` block — schema:
```
LINEAR CONTEXT:
ID: <ENG-123>
Title: <verbatim>
Description: <first ~800 chars, trimmed at sentence boundary if longer>
Acceptance Criteria:
- <AC1>
- <AC2>
…
Labels: <comma-separated>
Priority: <Urgent|High|Medium|Low|None>
Parent: <ENG-100|none>
Sibling sub-tasks (from parent): <ENG-101, ENG-102, …|none>
```
Total cap ~2000 chars — trim Description first, then AC list (keep first 5 ACs), then Labels.

### 3.5.3 Inline routing

`LINEAR CONTEXT:` block is pre-inlined into Phase 2 spawn prompts for the listed reviewers only:

- **spec-compliance** — Acceptance Criteria become the rubric (in addition to PLAN CONTEXT section 9). Each AC must be reflected by a test reference or boundary assertion in the diff.
- **pr-metadata** — Title/body alignment with issue title; issue ID prefix presence enhanced from regex-only to verified-existence check.
- **architecture** — Parent epic + sibling sub-task IDs enable cross-PR coordination signals (see expanded peer-PR scout).

Other dims (bugs / security / tests / optimizations / guidelines / conventions / design) do NOT see LINEAR CONTEXT — they review the code under per-file rubrics where tracker context is noise.

### 3.5.4 Fail-open behavior

| Failure mode | Slot value | Caveat surfaced |
|---|---|---|
| Workflow directory absent | | none — silent (workflow not configured) |
| Tracker ID detected but MCP server unregistered | `LINEAR CONTEXT: none — MCP unavailable (degraded to regex-only ID detection)` | `## Caveats` one-liner |
| MCP fetch error (network / scope / rate limit) | `LINEAR CONTEXT: none — MCP fetch failed (fail-open)` | `## Caveats` one-liner with error reason |
| Sub-task list fetch fails (parent fetch ok) | `Sibling sub-tasks: none — child fetch failed` (partial block) | `## Caveats` one-liner |
| Parent issue absent from fetched issue (top-level epic) | `Parent: none` (legitimate, no caveat) | none |

Read-only — never writes to Linear; never mutates git state. Latency ~1-3s per fetch on healthy network (1-2 fetches: main issue + optional parent).

---

## 4. Peer-PR scout (PR-ref input only)

Skip for files / diff range / branch. Mechanism:

- `gh pr list --state open --base <baseRefName> --json number,title,headRefName,author,updatedAt,files --limit 30`
- Compute file-path intersection between current PR's changed files and each sibling. `gh pr diff <N> --name-only` for file-name list (re-derived from parsing captured diff text or separate call).
- **Score each candidate sibling** (extended beyond pure file-overlap):
- `file_overlap`: integer count of intersecting changed files.
- `linear_bonus`: +2 if sibling's PR title OR body contains a Linear ID matching `linear-parent-ref` OR appearing in `linear-sibling-task-ids:` from (parent epic OR sibling sub-task linkage). Bonus is additive: PR can earn +2 for parent-match AND +2 for sibling-sub-task-match (total +4).
- `total_score = file_overlap + linear_bonus`.
- Keep **top-10** by `total_score` (ties broken by `updatedAt` descending). Drop candidates with `total_score == 0` (no file overlap AND no Linear linkage — irrelevant). When is skipped (no workflow), `linear_bonus` is always 0 and this reduces to pure file-overlap top-10.
- For each kept sibling: `gh pr view <peer-N> --json title,headRefName,url` + `gh pr diff <peer-N> | head -200` (bounded to **200 lines** per sibling — tightened from 300 to compensate for higher count).
- Build `PEER-PR CONTEXT:` block: one entry per sibling, annotated with `(file_overlap=N, linear_bonus=±N)` so reviewers can weigh signal strength. Total cap ~**5000 chars** — drop lowest-`total_score` sibling first if exceeded.
- Pre-inline into reviewer prompts: architecture, design, **bugs, conventions, optimizations, spec-compliance, regressions** (expanded from architecture + design only). Skipped for tests + security + guidelines + pr-metadata (orthogonal or target-PR-specific).

Fail-open: if `gh pr list` fails or zero overlap-and-bonus surviving, render slot as `none — gh unavailable (fail-open)` (error case) or `none — no relevant open peer PRs` (legitimate empty result).

Read-only — never writes files, never mutates git state. Latency ~1-3s base + ~200ms per kept sibling (vs ~300ms in pre-expansion 3-sibling cap).

---

(§5 reserved — scope resolution is covered under §2 above.)

---

## 6. L4 instructions load

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: review`, `LOAD_TIER: pipeline`, `MODE: initial-load`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `review.md`, and `code-style.md` (3 files, pipeline tier); the §Echo contract requires one observable line per file. Both are mandatory.

---

## 7. Step 0.5 — Round-N counter

Round-N awareness so reviewers can focus on what prior rounds missed.

1. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. Compute the state-file path `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`.
2. Read the state file if present. If absent, set `prior-round-summary: none — first review` and `round: 1`.
3. If present AND state-file's `pr-ref:` matches the current run's `pr-ref` (both literal "none" counts as a match): set `round: <prior round + 1>` (defaulting prior to `1` when absent). Capture prior `prior-round-summary:` value into in-memory variable for threading into reviewer prompts as `PRIOR-ROUND FINDINGS:`. Also capture `pr-body:` value into `prior-pr-body` for the pr-metadata reviewer's drift check.
4. If `round >= 3` after increment, fire `AskUserQuestion` (header `"Round-N gate"`, question `"This is round N of review on the same target. Continue or escalate?"`) with options `"Continue review (Recommended)"` / `"Escalate to user — structured handoff"`. On Escalate: write a `## Handoff` to state file, persist `round:` and `prior-round-summary:`, exit cleanly without spawning reviewers (terminal `escalated`).
5. Persist `round:` and `prior-round-summary:` to the state file. Consumed by every Phase 2 reviewer prompt as the `PRIOR-ROUND FINDINGS:` slot.

---

## 8. Step 0.6 — PLAN CONTEXT load (schema-aware)

Per `plan-context-reference.md`. If `$ARGUMENTS` contains `--plan <path>`, OR PR body contains `geniro-plan: <path>`, OR walk-up `.geniro/planning/*/spec.md` resolves, OR project files exist (`docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`): load.

Schema-aware:
1. Read first 20 lines. If `geniro_kind: design-doc` + `geniro_schema_version` is either `m5-v1` OR `m5-v2` → structured-section parser (11 sections + frontmatter goal-state; `m5-v2` additionally exposes `workflow_refs[]` if present).
2. Else fall back to prose detection with ~3000-char cap.

PLAN CONTEXT body inlined in spec-compliance reviewer spawn prompt only (Phase 2). Other dimensions don't see it.

---

## 9. Step 0.7 — Risk-tier stratification

Size-only triage (>8 files / >400 LOC) misses high-stakes small diffs. Stratify by risk tier alongside size.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` § "Step 1: Check for Hard Escalation Signals" — single source of truth for the 9 canonical signals (new entity / new endpoint or route / auth or permissions changes / new module / 3+ modules coordinated / open-closed violation / new async or background work / new external integration or env vars / ambiguous intent).
2. Scan changed files + diff content for matches.
3. If ANY signal matches → `risk-tier: high`. Otherwise → `risk-tier: standard`.
4. Persist to state.md frontmatter.

**Downstream knobs (4):**
- Phase 4.1 severity threshold: standard ≥80; high ≥70.
- Phase 4.2 verifier coverage: every §4.1 survivor (CRITICAL / HIGH / MEDIUM) verified — no tier-scaling, no severity-scaling; same coverage at standard and high tier.
- spec-compliance dimension default-on when risk-tier:high (otherwise gated on PR ref).
- Phase 1.5 mechanical pre-pass secret scan strictness — risk-tier:high adds patterns: AWS access keys / GCP service-account JSON / Azure SAS tokens / SSH OPENSSH key markers. Standard tier scans only the 4 baseline patterns.

---

## 10. Step 0.8 — Memory layer load

| Helper | Inputs | Outputs |
|---|---|---|
| `load-custom-instructions` MODE: refresh | scope = `review` + `global` + `code-style` (3 files) | concatenated rule body |
| `load-semantic` MODE: refresh | top-2: `_project.md` + `_CODEBASE_MAP.md` | inlined + fingerprint drift check |
| `query-learnings` | tags inferred from changed-file paths | top-K matching L2 entries (default K=5; filter superseded/deprecated) |
| `resolve-conflicts` | transitive | hard conflict → AUQ |

---

## 11. Mode AUQ (Standard vs TDD)

Fires only when `$ARGUMENTS` contains neither `--tdd` nor `--standard`. After triage, surface one `AskUserQuestion` (do NOT print options as plain text):

- **Header:** "Review mode"
- **Question:** "Run a Standard review (post all kept findings) or a TDD review (only post findings that an auto-authored failing test can reproduce)?"
- **Options:**
- "Standard review (Recommended)" — current behavior; Phase 4.3 gate opt-in per-run; Phase 6 posts all kept findings.
- "TDD review (auto-author failing tests for findings)" — Phase 4.3 gate's Recommended option flips to "Author tests…"; Phase 6 PR-comment posting filters to `[CONFIRMED-BY-TEST]` findings plus non-testable decision-types only.

If user declines (empty answer), default to Standard. `--tdd`/`--standard` flag (when present) always overrides this AUQ. Persist to `approvals[]` with category `tdd_mode_choice`.

See `${CLAUDE_PLUGIN_ROOT}/skills/review/tdd-mode-reference.md` for what TDD mode flips, edge cases, and F→P contract scope.

---

## 12. Size triage

After context settled, classify files when diff has >8 files or >400 LOC:

- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention in summary as "triaged out").
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review.

Done inline by orchestrator (read each diff hunk, classify) — no subagent.

The size threshold also controls Phase 2 Standard vs Batched mode (≤8 files AND ≤400 LOC → Standard, all reviewers see all files; >8 files OR >400 LOC → Batched, files split into ~5-file batches).
