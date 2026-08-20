# PR review-thread + CI I/O — shared contract

Single source for reading unresolved PR review threads and failing CI checks, and for writing replies / resolving threads. `/geniro:resolve` calls both sides — the read side in its Phase 1, the write side once its Phase 3 ship gate answers. The I/O logic lives here so a caller never has to re-derive the `gh` shapes or the thread-node-id ↔ numeric-comment-id mapping.

---

## 1. Resolve the PR ref

The caller passes a PR ref (`#N` / URL) or asks this helper to detect it from the branch:

```bash
gh pr view --json number,url,headRefOid,headRefName,baseRefName,title,body 2>/dev/null
```

A non-zero exit (no PR for the branch, `gh` unavailable, no GitHub remote) is **fail-open**: the caller surfaces a plain-English caveat and fires an `AskUserQuestion` (header: `"No PR ref"`) — "Provide a PR ref inline" / "Stop here" — rather than aborting silently. Capture `number` (N), the `owner/repo` (from the URL or `gh repo view --json owner,name`), and `headRefOid` (the head SHA — pin it so a later push can be diffed against the state read here).

## 2. Read side: unresolved review threads

One GraphQL call returns every review thread with its node id (for §5 resolve), the top comment's numeric id (for §4 reply), author, body, and location:

```bash
gh api graphql -F owner="$OWNER" -F repo="$REPO" -F number="$N" -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:100){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id isResolved isOutdated path line
          comments(first:20){ nodes{ databaseId author{login} body } }
        }
      }
      reviews(first:50){ nodes{ state body author{login} submittedAt } }
    }
  }
}'
```

- **Keep only `isResolved == false` threads** — already-resolved threads are skipped (idempotency; a re-run never re-triages a closed thread).
- **Humans AND bots both kept.** Bot logins keep their suffix (`coderabbitai[bot]`, `greptile-apps[bot]`, `sourcery-ai[bot]`, `codeant-ai[bot]`); tag the item `is_bot: true` for the verifier's prior context, but do NOT filter them out.
- Per thread, capture: `thread_id` (the `id` — a `PRRT_…` node id), `comment_id` (the FIRST comment's `databaseId` — the reply anchor), `author`, `path`, `line`, and the concatenated comment bodies (the thread conversation).
- `reviews[]` with `state: CHANGES_REQUESTED` carry a summary `body` not tied to a thread — surface them as context items (no `thread_id`; they cannot be resolved via API, only the author dismisses a formal review).
- Paginate on `pageInfo.hasNextPage` (typical PR: 1-3 calls).
- **Page sizes.** `reviewThreads(first:100)` is the API's per-page maximum and is paginated above, so no thread is lost. The two nested connections are NOT paginated and therefore truncate: `comments(first:20)` takes a thread's first 20 comments — the reply anchor plus the conversation the triage reads — and drops the tail of a longer thread; `reviews(first:50)` takes the first 50 formal reviews and drops the newest ones on a PR carrying more. Both bounds sit far above a typical PR; when one is actually hit, add `pageInfo`-driven pagination on that connection rather than raising the number — 100 is the API ceiling.

## 3. Read side: failing CI checks

```bash
gh pr checks "$N" --json name,state,bucket,link,startedAt 2>/dev/null
```

- **Failing = `bucket == "fail"`** (covers `FAILURE` / `ERROR` / `TIMED_OUT` / `CANCELLED` conclusions). Skip `pass` / `pending` / `skipping`.
- For each failing check, pull its output for the verifier — title + summary, and annotations when present (best-effort; a check with no annotation has `path: null`):

```bash
gh api "/repos/$OWNER/$REPO/commits/$HEAD_SHA/check-runs" \
  --jq '.check_runs[] | select(.conclusion=="failure" or .conclusion=="timed_out") | {id,name,output:{title:.output.title,summary:.output.summary}}'
gh api "/repos/$OWNER/$REPO/check-runs/$CHECK_RUN_ID/annotations" \
  --jq '.[] | {path,start_line,annotation_level,message}' 2>/dev/null   # best-effort
```

A CI item carries no `thread_id` — a check goes green on the next push, there is nothing to resolve. A CI item becomes a fix and a line in the caller's report; it never produces a reply (§7).

## 4. Write side: reply to a thread

Post the drafted reply as a reply to the thread's top comment:

```bash
gh api --method POST "/repos/$OWNER/$REPO/pulls/$N/comments/$COMMENT_ID/replies" \
  -f body="$REPLY_DRAFT"
```

`$COMMENT_ID` is the numeric `databaseId` captured in §2. Never echo a token; `gh` reads auth from its own store.

## 5. Write side: resolve a thread

```bash
gh api graphql -F threadId="$THREAD_ID" -f query='
mutation($threadId:ID!){ resolveReviewThread(input:{threadId:$threadId}){ thread{ isResolved } } }'
```

Resolve ONLY a thread whose verdict is `fix` and whose fix the caller has confirmed is in the pushed diff. A declined thread gets a reply (§4) but stays OPEN — resolving it would hide the disagreement from the reviewer, whose call it is to accept the push-back or not.

## 6. MCP fallback + fail-open

**Default: the §2 `gh api graphql` call.** The one escape hatch — when the GitHub MCP server is registered, the read side may use `mcp__github__pull_request_read` instead, consuming `reviewThreads[]` + `reviews[]` from its payload (same fields). There is no MCP equivalent for §4/§5 writes in the base server, so the write side always uses `gh`.

Every call here is **fail-open**: a failed read sets the affected snapshot to null and the caller proceeds with a caveat (a resolve run with no thread data degrades to "nothing to triage"); a failed write marks that item skipped and reports it — never a hard stop, never a silent success.

## 7. Caller contract

- **Read side (`/geniro:resolve` Phase 1):** read-only, and the run's first contact with the PR. Fetch before any analysis, so the verdicts are assigned against the code the comments describe.
- **Write side (`/geniro:resolve` Phase 3):** an external write to a public surface — the caller gates it behind an `AskUserQuestion` (the ship gate), exactly like `gh pr create` / `git push`. This helper performs the write; it does NOT own the gate. After a successful reply, the caller appends a `pr-comment-posted` entry to state.md `non-resumable-actions[]`.
- **Item fields:** the read side populates the caller's inventory (`${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §1); `thread_id` flows to §5 here, `comment_id` to §4. A thread is resolved only after the caller has confirmed the fix is in the pushed diff.
