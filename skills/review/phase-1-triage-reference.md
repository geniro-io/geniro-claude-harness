# Phase 1 Triage Reference

Detailed contract for `/geniro:review` Phase 1 (Triage & Context Collect). SKILL.md retains a 2-3 line summary + a pointer here.

State.md `phase: triage` during this phase.

## Contents

- §0 Step 0 — Workspace setup
- §1 Input parsing + PR thread-state fetch
- §2 Scope resolution
- §3 PR-ref input parsing
- §3.5 Workflow integrations (issue-tracker fetch)
- §4 Peer-PR scout (PR-ref input only)
- §5 reserved — scope resolution is covered under §2 above
- §6 Custom-instructions load
- §7 Step 0.5 — Round-N counter (+ re-review gate: scope / depth / repeat-finding handling)
- §8 Step 0.6 — PLAN CONTEXT load (schema-aware)
- §9 Step 0.7 — Risk-tier stratification
- §10 Step 0.8 — Memory layer load
- §11 Mode AUQ — review depth
- §12 Size triage

---

## 0. Step 0 — Workspace setup

Step 0 fires BEFORE input-mode detect, scope resolution, PR-ref parsing, workflow-integration fetch, peer-PR scout, and L4 / L3 / L2 helper calls. Workspace decision determines the working tree the rest of Phase 1 inspects; running PR-diff parsing or peer-PR `gh pr list` against the wrong worktree pollutes state.md with cwd-bound results.

Sub-step order: **read prior approvals** (0-pre, before any detection) → **passive detection** (0a, no AUQ) → **decide action** (0b, auto-continue or AUQ). The approvals read comes first so a Round 2+ re-run honors the workspace the user already approved instead of detecting fresh and relocating it.

### 0-pre — Read prior approvals (FIRST, before passive detection)

Two situations reach this sub-step, and they are NOT the same. A **compaction-resume** is an in-flight run of this skill resuming mid-phase — a non-terminal `state.md` for the current run exists; here every prior-turn pick (workspace AND depth) is re-applied without re-asking, so a compaction never loses an answer. A **fresh Round 2+ re-run** is the user invoking `/geniro:review` again — there is no in-flight `state.md` (the prior round's is terminal), only the durable `from-review-<branch>.md` handoff; this is a new user-invoked run, so its review-intent gates (depth at §11, and the re-review scope gate at §7) are ASKED again — the user chooses depth and scope per run, never inheriting them from a completed prior round. The ONE pick re-applied on BOTH is the **workspace location**: re-asking it every re-run risks the silent-relocation bug this sub-step exists to prevent (a live Round 2 run once created a worktree at a default location while the user's Round 1 pick named a different one). Read the persisted picks BEFORE passive detection (0a) and any workspace action.

1. Resolve the prior state/handoff for this branch (`<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A, plus the resumed `state.md` on a compaction-resume). When neither exists, this is a first run — skip to 0a with no inherited picks.
2. Read these `approvals[]` categories: `review_workspace_setup` (workspace location/action), `deep_mode_choice` (review depth), and `rereview_repeat_handling` (how unchanged repeat findings are presented this round). The workspace pick is **binding** for this run — re-applied on both a compaction-resume and a fresh re-run (anti-relocation, per above). The depth pick and the repeat-handling pick are binding **only on a compaction-resume**; on a fresh re-run they are prior-round context, not a decision for this run, so the §11 depth gate and the §7 re-review gate (which carry both) ask again rather than inheriting them across separate invocations.
3. **Honor the recorded workspace location exactly** — re-enter the same worktree path the prior round approved; do not substitute a different location. The persisted pick names a specific tree, not just "use a worktree": re-applying it at a fresh default location is the silent-relocation failure this sub-step prevents.
4. **Re-ask only when the recorded pick no longer applies** — the approved worktree was deleted, or the branch moved off the commit it was created from. In that case fire the workspace AUQ fresh (the Case-mismatch UX below still governs); a stale pick is re-decided, never silently swapped for a default.
5. Narrate the inheritance and proceed by run-type. On a **compaction-resume**: narrate `Continuing the workspace and depth choices from the interrupted run: <workspace pick>, <depth pick>.`, skip the 0b AUQ branches, execute the inherited workspace action in 0d, and let §11 skip the depth question (already answered this run). On a **fresh Round 2+ re-run**: narrate only `Continuing in the workspace you approved last round: <workspace pick>.`, skip the 0b workspace AUQ branches, execute the inherited workspace action in 0d — but the depth (§11) and re-review scope + repeat-handling (§7) gates DO fire this run; never suppress them with the prior round's `deep_mode_choice` or `rereview_repeat_handling`.

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
        A) "Create review worktree" — runs:
             git fetch origin pull/<N>/head:<TARGET_WORKTREE_NAME>
             git worktree add .claude/worktrees/<TARGET_WORKTREE_NAME> <TARGET_WORKTREE_NAME>
             EnterWorktree(path: ".claude/worktrees/<TARGET_WORKTREE_NAME>")
        B) "Review in current location" — continue in current cwd.

6. INPUT_SHAPE ∈ {branch, diff-range, files, empty}
   AND IN_WORKTREE == false
   AND PROTECTED_BRANCH == true
   AND no continuing-work signals match
   ⇒ Fire 2-option AUQ (header: "Git workspace"):
        A) "Create review worktree" — runs:
             git worktree add --detach .claude/worktrees/review-<short-slug> <CURRENT_BRANCH>
             # --detach: <CURRENT_BRANCH> is already checked out in this (main) worktree,
             # so a non-detached add would fail "already used by worktree". A read-only
             # review only needs the tree at that commit, not a second branch checkout.
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

**The workspace decision is never silent when the tree calls for an AUQ.** Cases 4, 5b, and 6 MUST fire their `AskUserQuestion` and WAIT — creating or switching a worktree without asking is the failure this step exists to prevent. A long autonomous / heavy-effort / workflow run does not relax this; the AUQ binds inside every wrapper per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/reporter-boundary.md`. Because /geniro:review is read-only, neither option in the 5b / 6 worktree AUQ is pre-selected (no `(Recommended)` marker): a worktree gives full file context for a deep review but is never the forced default — the user picks per run, or sets it once via the `worktree` / `no-worktree` modifier.

**Inline modifier overrides** (parsed from `$ARGUMENTS`; a modifier overrides auto-detection — an explicit modifier is direct user intent and outranks any inferred signal):

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
    picked: "Create review worktree"
    timestamp: <ISO-8601>
```

On a compaction-resume or a Round 2+ re-run, the recorded **workspace** answer is read and re-applied in §0-pre — BEFORE passive detection and any workspace action — so the persisted workspace pick binds before the tree is detected fresh (depth and re-review scope are re-asked on a fresh re-run per §0-pre, not inherited).

Workflow status transitions (e.g., "Move <issue_id> to In Review?") are NOT part of Step 0 — /geniro:review is a read-only reporter and never mutates external tracker state. Tracker IDs detected from `$ARGUMENTS` / PR body / spec.md frontmatter are read-only context for downstream reviewer dimensions (spec-compliance + pr-metadata + architecture) per §3.5; they are not user-prompted in Step 0. Workflow status mutation belongs to `/geniro:implement` only — Step 0c (kickoff) and Phase 3 Ship (completion); `/geniro:plan`, `/geniro:debug`, `/geniro:refactor`, and `/geniro:review` are all read-only tracker consumers.

### 0d — Execution of the workspace decision

After the workspace decision is made (AUQ-resolved this round, or inherited per §0-pre) and `approvals[]` is persisted:

1. **Workspace action** — execute worktree create / EnterWorktree / no-op per `review_workspace_setup` pick.
2. State.md frontmatter `branch:` and `worktree:` updated to reflect the new working tree before Phase 1 §1 (input mode detect) runs.

Do NOT use `EnterWorktree(name: ...)` — that path auto-creates with `worktree-` prefix and defeats the `.claude/worktrees/<slug>/` convention. Use `EnterWorktree(path: ".claude/worktrees/<slug>")`.

### 0e — Edge cases

| Case | Behavior |
|---|---|
| User picks "Other" with custom text on the workspace AUQ | Treat as "Review in current location" semantically; no worktree mutation; echo custom text into state.md `## Workspace decision` body block. |
| Multiple continuing signals match (review handoff AND debug handoff) | Both satisfy rule 2 or 3. Echo both signal names; behavior identical. |
| Stale T2 handoff (older than the current work) | Still triggers rule 2 / 3. Emit soft notice: `"Note: review handoff is N days old."` |
| `IN_WORKTREE == true` AND `IN_TARGET_WORKTREE == true` but PR `headRefOid` mismatches current `HEAD` | Auto-continue per rule 1. Mismatch surfaces as warning in §3 PR-ref parsing, never blocks. User can re-run with `new-branch` modifier to force a fresh fetch. |

After Step 0 settles, every subsequent Phase 1 step and downstream phases run from the new cwd. Cross-session writes (`.geniro/state/handoff/from-review-<branch>.md`, `learnings.jsonl`) auto-route to the main worktree's `.geniro/` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`, so they survive worktree teardown.

---

## 1. Input parsing + PR thread-state fetch

The pre-step resolves the review target from `$ARGUMENTS`, and for a PR ref fetches thread state that feeds downstream dedup and review-ingest:

| Input shape | Routing |
|---|---|
| empty `$ARGUMENTS`, branch name, file paths, or diff range | Phase 1.5 mechanical pre-pass |
| PR ref (`#1234` / PR URL) | resolve owner/repo/number → thread-state + existing-review fetch below → Phase 1.5 |

/geniro:review always authors a review of the target. It does not process reviewer comments left on your own PR — that is the author's job, done via the PR itself or by routing an actionable comment to `/geniro:implement`.

**PR-ref resolution.** Parse `<owner>/<repo>/<number>` from `$ARGUMENTS`. For a full PR URL, parse the path segments directly; for bare PR number (`#1234` or `1234`), resolve `<owner>/<repo>` from the current repo via `gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'`.

**Thread-state fetch.** Feeds the `resolved-threads-snapshot:` (Phase 1 item 4 — Post-drill already-on-PR dedup) and the existing-review ingest (§1.1). MCP-preferred: `mcp__github__pull_request_read` with the resolved owner/repo/number; consume `reviewThreads[]` from the returned payload directly. Fallback when MCP is unavailable:

```bash
gh api graphql -F owner=<owner> -F repo=<repo> -F number=<N> -F cursor=null -f query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor} nodes{isResolved isOutdated path line}}}}}'
```

Paginate with `endCursor` until `hasNextPage == false` (loop the call, concatenate `nodes[]` across pages — typical PR completes in 1-3 calls, stays under rate-limit budget). Record each thread's `isResolved` / `isOutdated` / `path` / `line` — resolved threads feed the snapshot; outdated threads are excluded (referenced code rewritten, comment stale).

**Fail-open behavior.** If the fetch fails (no network, missing token scope, rate limit, pagination loop errored mid-stream): skip the snapshot (`resolved-threads-snapshot: null`), proceed with the review, and surface `PR review-thread fetch failed — reviewing without thread-state awareness` under `## Caveats` in the final report (mirrors Phase 1.5 / 4.2 / 4.3 fail-open).

### 1.1 Existing PR review ingest (formal reviews + inline bot comments)

The thread-state fetch above reads thread STATE (`isResolved`/`isOutdated`/`path`/`line`) for dedup only — it never reads comment BODIES. Automated reviewers (CodeRabbit, Greptile, Sourcery, and other bots) post findings as review-thread comments; a real incident had /geniro:review declare a PR "CLEAN — ship-ready" while CodeRabbit had already flagged a Major bug in scope. Fetch those bodies so they reach the LLM reviewers as prior-context.

Two distinct surfaces carry prior findings: (a) the top-level **formal review** (`reviews(){ state body author }` — APPROVED / CHANGES_REQUESTED / COMMENTED with a summary body, posted by humans AND bots), and (b) **inline review-thread comments** (anchored to `path:line`, mostly bots). A real incident had a run address only the failing-CI commit and inline comments while a teammate's posted formal review — carrying two advisory findings beyond the inline ones — went unread. Read BOTH so neither surface is silently dropped.

For a target PR ref (skip entirely when `INPUT_SHAPE != pr-ref` — a branch / diff / file-path input has no PR to query), extend the thread-state GraphQL to also select comment author + body, OR run a second `gh` call. MCP-preferred path: the `mcp__github__pull_request_read` payload already carries thread comments — read `comments[].author.login` + `comments[].body` from each `reviewThreads[]` node, and the formal reviews too — read `reviews[].state` + `reviews[].body` + `reviews[].author.login`. Fallback GraphQL:

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

### 2.1 Scope-exclusion transparency

When the review's scoped file set is a proper subset of the PR's changed files — fewer files than `gh pr diff <ref> --name-only` shows — a reader cannot tell "excluded because reviewed elsewhere" from "missed." The common cause is a stacked PR: when the PR's `baseRefName` (§3) is not the repo default branch, scope-anchor resolves scope to the base-relative delta, so the ancestor commits' files — still visible on the PR's GitHub "Files changed" — are deliberately out of scope (they belong to the ancestor PR and are reviewed there). A second cause is the §7 re-review delta gate — when the user picked "Only changes since the last review", the non-delta files are out of scope because they were reviewed in a prior round (round N−1); label those exclusions as "reviewed in round N−1", NOT as ancestor-PR exclusions. Surface the exclusion:

- **Excluded files:** the files in `gh pr diff <ref> --name-only` (what the PR shows the reader) MINUS the file set the reviewer agents were actually given (the resolved review scope the orchestrator already holds). Do NOT recompute the reviewed set from `git diff <baseRefName>...HEAD` — that result drifts as the base branch moves (a merged or reset base can make it equal the full diff). When the excluded set is empty, render no note.
- **Ancestor PR:** `gh pr list --state open --head <baseRefName> --json number,title,url --limit 1`, falling back to `--state all` when empty — the PR whose head IS this base (`--head`, not the peer-PR scout's `--base`, which finds children/siblings).
- **Ancestor findings:** reuse the §1.1 thread-state GraphQL against the ancestor PR number to COUNT its review threads (resolved + unresolved) — do NOT persist the result to the target PR's `pr-bot-comments-snapshot:` / `pr-formal-reviews-snapshot:` (those hold the target's prior-review context fed to reviewers).

Rendered as the Phase 6 report `## Summary` `Scope:` bullet (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.6). Computed in-memory at report time from `gh pr diff <ref> --name-only` and the scope the reviewers were given — no new frontmatter field. Fail-open: no `--head` match → render "<M> files excluded — owning PR not identified; confirm they were reviewed separately"; `gh` unavailable, or a compaction dropped the in-memory reviewed-file set → omit the note (the review's scoped findings still hold).

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

Skip for files / diff range / branch.

**The PEER-PR CONTEXT slot value has exactly two legal sources** — (a) the literal result of running the scoring procedure below to completion, starting from the live `gh pr list` call, or (b) the literal fail-open string (`none — gh unavailable (fail-open)` / `none — no relevant open peer PRs`). A scout exists to DISCOVER open sibling PRs the orchestrator does not already know about; synthesizing the slot from PRs already mentioned in context (merged/closed PRs the run happened to reference, prior-round handoff content) is not a scout — it cannot surface an unknown open sibling, and it feeds reviewers a fabricated peer set. If `gh pr list` did not run this round, the only legal value is the fail-open string, never a hand-assembled block.

Mechanism:

- `gh pr list --state open --base <baseRefName> --json number,title,headRefName,author,updatedAt,files --limit 30`
- Compute file-path intersection between current PR's changed files and each sibling. `gh pr diff <N> --name-only` for file-name list (re-derived from parsing captured diff text or separate call).
- **Score each candidate sibling** (extended beyond pure file-overlap):
- `file_overlap`: integer count of intersecting changed files.
- `linear_bonus`: +2 if sibling's PR title OR body contains a Linear ID matching `linear-parent-ref` OR appearing in `linear-sibling-task-ids:` from (parent epic OR sibling sub-task linkage). Bonus is additive: PR can earn +2 for parent-match AND +2 for sibling-sub-task-match (total +4).
- `total_score = file_overlap + linear_bonus`.
- Keep **top-10** by `total_score` (ties broken by `updatedAt` descending). Drop candidates with `total_score == 0` (no file overlap AND no Linear linkage — irrelevant). When workflow integration is skipped (no workflow file), `linear_bonus` is always 0 and this reduces to pure file-overlap top-10.
- For each kept sibling: `gh pr view <peer-N> --json title,headRefName,url` + `gh pr diff <peer-N> | head -200` (~200 lines per sibling — bounds total context against the higher sibling count).
- Build `PEER-PR CONTEXT:` block: one entry per sibling, annotated with `(file_overlap=N, linear_bonus=±N)` so reviewers can weigh signal strength. Total cap ~**5000 chars** — drop lowest-`total_score` sibling first if exceeded.
- Pre-inline the SAME slot value into all 7 receiving reviewer prompts identically — architecture, design, bugs, conventions, optimizations, spec-compliance, regressions (expanded from architecture + design only). Feeding the block to a subset is a distribution miss the user did not consent to; the slot content is one computed value shared verbatim across the 7. Skipped for tests + security + guidelines + pr-metadata (orthogonal or target-PR-specific). The slot is part of each receiving dim's pre-inlined context per SKILL.md §2.3; a dim spawned without it is detectable against the §2.3 spawn-context contract and the §4.0 post-spawn verification gate.

Fail-open: if `gh pr list` fails or zero overlap-and-bonus surviving, render slot as `none — gh unavailable (fail-open)` (error case) or `none — no relevant open peer PRs` (legitimate empty result).

Read-only — never writes files, never mutates git state. Latency ~1-3s base + ~200ms per kept sibling (vs ~300ms in pre-expansion 3-sibling cap).

---

(§5 reserved — scope resolution is covered under §2 above.)

---

## 6. Custom-instructions load

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: review`, `LOAD_TIER: pipeline`, `MODE: initial-load`. The helper's §Procedure prescribes imperative `Read` directives on `global.md`, `review.md`, and `code-style.md` (3 files, pipeline tier); the §Echo contract requires one observable line per file. Both are mandatory.

---

## 7. Step 0.5 — Round-N counter

Round-N awareness so reviewers can focus on what prior rounds missed.

1. Resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A. Compute the state-file path `<PRIMARY_ROOT>/.geniro/state/handoff/from-review-<branch>.md`.
2. Read the state file if present. If absent, set `prior-round-summary: none — first review` and `round: 1`.
3. If present AND state-file's `pr-ref:` matches the current run's `pr-ref` (both literal "none" counts as a match): set `round: <prior round + 1>` (defaulting prior to `1` when absent). Capture prior `prior-round-summary:` value into in-memory variable for threading into reviewer prompts as `PRIOR-ROUND FINDINGS:`. Also capture `pr-body:` value into `prior-pr-body` for the pr-metadata reviewer's drift check.

   **Round-counter + carry-over set are scoped to the SAME target.** The round counter increments only on a `pr-ref:` match — a fresh PR (different `pr-ref`) is round 1, so this branch does not run and the prior round's findings are NOT carried over. This is deliberate: a new target earns a fresh review bar, and a carried-over digest must never leak across different PRs. A future author should not "fix" the same-`pr-ref` condition into an always-increment counter — that would carry a digest from one PR into an unrelated one.

   **`repeat-of-prior-round` marker (round ≥2 only).** When this branch runs, mark each prior-round finding so Phase 4/5 can route it. A current-round finding is `repeat-of-prior-round` when it matches a prior-round finding by dedup key (`path:line + finding-title`) AND nothing about it strengthened since last round — same severity, no fresh cross-reviewer convergence, no per-finding verifier `confirmed` verdict that was absent last round, and the cited code path is no more reachable than before. This marker rides the `PRIOR-ROUND FINDINGS:` slot threaded into reviewer prompts; it is a presentation router consumed by `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 stratify (which section a repeat renders in), NEVER a filter that decides whether it renders. A finding that was fixed in the prior round and no longer reproduces is simply absent from the current reviewers' output — it is not a `repeat-of-prior-round` carry-over.
4. If `round >= 3` after increment, fire `AskUserQuestion` (header `"Review rounds"`, question `"This is round N of review on the same target (substitute the actual round number for N). Continue or escalate?"`) with options `"Continue review (Recommended)"` / `"Escalate to user — structured handoff"`. On Escalate: write a `## Handoff` to state file, persist `round:` and `prior-round-summary:`, exit cleanly without spawning reviewers (terminal `escalated`).
5. **Re-review gate (round ≥ 2, fresh re-run only).** When `round >= 2` AND this is a fresh user-invoked re-run (NOT a compaction-resume — §0-pre distinguishes them by the in-flight `state.md`), the scope, depth, and repeat-finding handling of this round are the user's to choose, never auto-decided or inherited from the prior round. After any round-≥3 escalation clears, fire ONE `AskUserQuestion` carrying these three questions before spawning reviewers:
   - **Re-review scope** (header `"Re-review scope"`, question `"This branch was reviewed before (round N). What should this round cover?"`) — options `"Re-review the whole PR"` / `"Only changes since the last review"`. The delta option scopes the review to `<prior-reviewed-head>..HEAD`, where `<prior-reviewed-head>` is the handoff `pr-head-sha:` the prior round reviewed; when that SHA is absent or unreachable, fall back to whole-PR and note it under `## Caveats`. Prior-round findings thread into reviewers as the `PRIOR-ROUND FINDINGS:` slot under either scope. Persist `approvals[]` category `rereview_scope_choice`.
   - **Review depth** — the §11 Standard/Deep question, asked here so the re-review is a single decision point; persist `deep_mode_choice`. §11 then sees depth answered this run and does not re-prompt.
   - **Repeat findings** (header `"Repeat findings"`, question `"Some issues from the last review weren't fixed and would surface again unchanged. How should I show them this round?"`) — options `"Move unchanged repeats into a collapsed 'Carried-over' section"` (the default-friendly choice: a repeat that re-surfaces identically and was not fixed last round is still kept and still in the handoff, just grouped into a collapsed `## Carried-over from round N` digest so it stops crowding the active list) / `"Keep every repeat in the main findings list"` (foreground unchanged repeats alongside new ones). Persist `approvals[]` category `rereview_repeat_handling`. This choice routes presentation only — under EITHER pick every repeat finding stays in the report and the handoff; a repeat that strengthened since last round (fresh convergence, a newly-reachable code path, or a per-finding verifier confirmation that was absent before) is promoted to the active `## Findings` list regardless of this pick, per `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 stratify.
   Never auto-decide any of the three: an orchestrator narrating "I'll review only the unreviewed delta" (or silently re-reviewing the whole PR), or quietly collapsing repeats into a digest the user never authorized, is the exact drift this gate prevents. On a compaction-resume this gate does NOT re-fire — re-apply the saved picks per §0-pre.

   **AUQ-cap handling.** Each of the three questions carries 2 options, well under the 4-option-per-question cap. If the runtime limits questions-per-call below three, CHAIN a second `AskUserQuestion` carrying the overflow question — never drop or merge the scope / depth / repeat-handling questions to fit. Chaining keeps all three decisions in one logical gate.
6. Persist `round:` and `prior-round-summary:` to the state file. Consumed by every Phase 2 reviewer prompt as the `PRIOR-ROUND FINDINGS:` slot.

### 7.1 Carried-over stratification (Phase 5 mechanics)

Detailed contract for the `## Carried-over from round N` tier named in `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Phase 5 stratify. Applies only on a round ≥2 re-run where the user picked the collapse option at the §7 re-review gate (`rereview_repeat_handling` = the carried-over choice); when the user kept every repeat in the main list, this stratification is skipped and all findings render in `## Findings` as usual.

**What demotes.** A kept finding admitted by the standard Phase 4.1 multi-signal gate that ALSO carries the `repeat-of-prior-round` marker (§7 step 3) demotes from active `## Findings` into a collapsed `## Carried-over from round N` digest — a sibling of `## Deferred — sub-threshold`. The finding keeps its full per-finding body block (every field from the handoff per-finding schema), its severity, and its place in the handoff; only its rendering section changes. It is never dropped, never removed from the report, never removed from the handoff body.

**What promotes (overrides the demotion).** A repeat finding promotes back to active `## Findings` — even when the user chose collapse — when ANY new signal appeared this round:

- fresh cross-reviewer convergence that was not present last round (its `convergence_count` rose);
- a code path that became newly reachable since last round (the finding now triggers under current config / flags / role where it did not before);
- a per-finding verifier `confirmed` verdict (Phase 4.2) that was absent last round.

A finding lacking the `repeat-of-prior-round` marker — i.e. genuinely new this round — keeps the standard multi-signal admission gate unchanged and renders in active `## Findings`. The marker drives section, never admission.

**Gate preservation under demotion (load-bearing).** Demotion is presentation-only and must never strip a finding's gate:

- A demoted finding that is a needs-your-decision item (`Decision Type: PRODUCT-DECISION`) still carries `step0_status: pending` and is still surfaced by the open-decision gate (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §3) — collapsing its presentation does not exempt it from the decision the user owes.
- A demoted finding referenced by an `open_questions[]` entry keeps that entry; the open-question gate chain (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §2.5 Pre-gate, the Pre-Post guard §7.0, and the /geniro:implement consumer-side resolution) is unchanged.
- A demoted finding stays in the Post drill's eligible set (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-handoff.md` §7.1) exactly as `## Deferred — sub-threshold` items do — once the user chooses to post, the carried-over digest is postable like any other section. The marker-not-filter rule extends to every gate: demotion changes which section the user reads it in, never whether a gate fires for it.

**Section render.** `## Carried-over from round N` opens with one plain-English sentence ("These N issues were raised in an earlier review round and weren't fixed; they're unchanged, so they're grouped here rather than repeated in the main list."), then the per-finding body blocks. The handoff `## Summary` `Disposition:` line gains a `<C> carried-over` count alongside `<D> deferred`.

---

## 8. Step 0.6 — PLAN CONTEXT load (schema-aware)

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-context.md`. If `$ARGUMENTS` contains `--plan <path>`, OR PR body contains `geniro-plan: <path>`, OR walk-up `.geniro/planning/*/spec.md` resolves, OR project files exist (`docs/spec.md`, `docs/plan.md`, `PLAN.md`, `SPEC.md`): load.

Schema-aware:
1. Read first 20 lines. If `geniro_kind: design-doc` + `geniro_schema_version` is either `m5-v1` OR `m5-v2` → structured-section parser (11 sections + frontmatter goal-state; `m5-v2` additionally exposes `workflow_refs[]` if present).
2. Else fall back to prose detection with ~3000-char cap.

PLAN CONTEXT body inlined in the spec-compliance and regressions reviewer spawn prompts (Phase 2). Other dimensions don't see it.

---

## 9. Step 0.7 — Risk-tier stratification

Size-only triage (>8 files / >400 LOC) misses high-stakes small diffs. Stratify by risk tier alongside size.

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` § "Step 1: Check for Hard Escalation Signals" — single source of truth for the 9 canonical signals (new entity / new endpoint or route / auth or permissions changes / new module / 3+ modules coordinated / open-closed violation / new async or background work / new external integration or env vars / ambiguous intent).
2. Scan changed files + diff content for matches.
3. If ANY signal matches → `risk-tier: high`. Otherwise → `risk-tier: standard`.
4. Persist to state.md frontmatter.

**Downstream knobs (4):**
- Phase 4.1 severity threshold: per SKILL.md §4.1 signal #4 (advisory-fallback confidence ≥80, relaxed to ≥70 at `risk-tier: high`) — the single source for the numeric values.
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

## 11. Mode AUQ — review depth

Depth (Standard vs Deep) controls how many reviewer/verifier passes run (`deep-mode` boolean).

After triage, surface the depth question via `AskUserQuestion` (do NOT print options as plain text). It fires on a user-invoked run when `$ARGUMENTS` lacks `--deep` AND depth was not already chosen THIS run — a `--deep` flag pre-resolves depth to Deep (no AUQ); a round ≥2 re-review already asked depth in the §7 re-review gate (no second prompt); a compaction-resume inherits the in-flight run's answer. It does NOT inherit a prior *completed* run's `deep_mode_choice` across a fresh re-invocation — depth is a per-run choice, so a fresh re-run always asks (via §7 on a re-review, or here on a first run). "Chosen this run" means a `deep_mode_choice` written in the CURRENT invocation (by the §7 gate or this AUQ); a value carried over from a prior completed round does NOT satisfy the skip — on a fresh re-run the orchestrator ignores the inherited `deep_mode_choice` rather than reading it as this run's answer, so the gate is never silently suppressed by stale state even if §7 did not fire.

- **Header:** "Review depth"
- **Question:** "How deep should the review go?"
- **Options:**
- "Standard" — one reviewer pass per dimension; findings filtered and verified once.
- "Deep — 3× passes + 3-vote verify" — runs each check 3× and verifies findings with a 3-agent majority vote; higher quality (finds more, validates more reliably) at higher token cost. Posts the same finding set as Standard.

Neither option carries a `(Recommended)` suffix — depth is a per-run pick where the alternative is only costlier, never safer (Deep authors no fix), so the user weighs cost against thoroughness each run. If the question is dismissed (empty answer), default to the cheaper value: Standard (`deep-mode: false`).

Persist the pick: frontmatter `deep-mode: <true|false>` + `approvals[]` category `deep_mode_choice`, so the session-restore hook re-applies depth on a compaction-resume (only — a fresh `/geniro:review` re-invocation re-asks depth per §0-pre, never inheriting the prior completed run's pick). Deep contract: `${CLAUDE_PLUGIN_ROOT}/skills/review/deep-mode-reference.md`.

---

## 12. Size triage

After context settled, classify files when diff has >8 files or >400 LOC:

- **Trivial**: Renames, formatting-only, import reordering, generated files, lock files → skip full review (mention in summary as "triaged out").
- **Substantive**: Logic changes, new code, API changes, security-sensitive → full review.

Done inline by orchestrator (read each diff hunk, classify) — no subagent.

The size threshold also controls Phase 2 Standard vs Batched mode (≤8 files AND ≤400 LOC → Standard, all reviewers see all files; >8 files OR >400 LOC → Batched, files split into ~5-file batches).
