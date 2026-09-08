# PR review-thread + CI I/O — shared contract

Single source for reading unresolved PR review threads and failing CI checks, and for writing replies / resolving threads. `/geniro:resolve` calls both sides — the read side in its Phase 1, the write side once its Phase 3 ship gate answers. The I/O logic lives here so a caller never has to re-derive the `gh` shapes or the thread-node-id ↔ numeric-comment-id mapping.

## Contents

- §1 Resolve the PR ref
- §2 Read side: unresolved review threads
- §2.5 Feedback snapshot and re-read
- §3 Read side: failing CI checks
- §4 Write side: reply to a thread
- §5 Write side: resolve a thread
- §6 MCP fallback + fail-open
- §7 Caller contract

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
gh api graphql -F owner="$OWNER" -F repo="$REPO" -F number="$N" -F cursor=null -f query='
query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id isResolved isOutdated path line
          comments(first:100){ nodes{ databaseId author{login} body } }
        }
      }
      reviews(last:100){ nodes{ id state body author{login} submittedAt } }
      comments(last:100){ pageInfo{ hasPreviousPage } nodes{ databaseId author{login} body createdAt } }
    }
  }
}'
```

- **Keep only `isResolved == false` threads** — already-resolved threads are skipped (idempotency; a re-run never re-triages a closed thread).
- **Humans AND bots both kept.** Bot logins keep their suffix (`coderabbitai[bot]`, `greptile-apps[bot]`, `sourcery-ai[bot]`, `codeant-ai[bot]`); tag the item `is_bot: true` for the verifier's prior context, but do NOT filter them out.
- Per thread, capture: `thread_id` (the `id` — a `PRRT_…` node id), `comment_id` (the FIRST comment's `databaseId` — the reply anchor), `author`, `path`, `line`, and the concatenated comment bodies (the thread conversation).
- `reviews[]` entries carrying a non-empty `body` — regardless of `state` — hold a summary not tied to a thread; surface every one as a context item (no `thread_id`; they cannot be resolved via API, only the author dismisses a formal review). Review `state` is not a signal that feedback is settled: a `COMMENTED` review never moves `reviewDecision`, and an `APPROVED` review can carry a substantive body and new inline threads in the same submission.
- `comments[]` (the PR's conversation tab, not a review thread) carry no thread and cannot be resolved through the API — surface each as a context-and-fix item exactly like the review bodies above; the caller reports its outcome rather than posting a reply.
- Loop the call, passing the previous page's `endCursor` as `cursor`, until `reviewThreads.pageInfo.hasNextPage` is false, concatenating `reviewThreads.nodes[]` across pages (typical PR: 1-3 calls). Take `reviews` and `comments` from the first page only — every page re-returns them identically, so concatenating those double-counts.
- **Page sizes.** `reviewThreads` is the connection this loop paginates, so no thread is lost regardless of count. The rest take one page and stop, which is why `reviews` and the PR's `comments` select their NEWEST 100 with `last:` rather than their oldest with `first:` — a connection returns oldest-first by default, so `first:` on a busy PR drops exactly the recent arrivals a re-read exists to catch. A thread's nested `comments` keeps `first:` deliberately: the reply anchor is the thread's FIRST comment, and losing that breaks every reply into the thread, where losing the tail of a 100-deep conversation costs only context on an item already in the inventory.
- **Truncation is reported, not swallowed.** `comments.pageInfo.hasPreviousPage` true means the conversation tab holds more than this read returned. Surface it to the caller as a partially-read surface — an unknown under §6, not a clean read — so a run never reports a complete picture it did not fetch.

## 2.5 Feedback snapshot and re-read

Build the snapshot from the raw §2 response, before the `isResolved == false` filter in §2 is applied — a thread that resolves during the window between reads must still appear in `threads` so its flip is visible, not silently dropped by the filter before the comparison ever sees it:

```yaml
feedback-snapshot:
  taken-at: <ISO-8601 UTC>
  pr-head-sha: <the headRefOid from §1>
  threads:          { <thread node id>: <isResolved> }
  reviews:          [ <review node id> ]
  review-comments:  [ <databaseId> ]
  pr-comments:      [ <databaseId> ]
```

Before any outward action — a commit, a push, a posted reply, a resolve mutation — re-run the §2 read and set-diff it against the stored snapshot. Report as new: a thread id absent from `threads`, a thread whose `isResolved` flipped either direction, and any review / review-comment / conversation-comment id absent from its list.

Once that diff is reported, replace the whole stored snapshot with this read — all four collections and both stamps — and commit it with `atomic_state_write` (`atomic_state_set_field` cannot write a nested mapping). Replacing it is what makes the next diff measure from here: a snapshot left standing at its Phase 1 values re-reports the same arrivals at every later read, and a caller that re-opens its gate on a non-empty diff would then never stop re-opening it. The stamps ride along for the caller's report, which states the commit this run read the PR at and how long ago — only the latest read answers either.

A verdict binds to the PR state it was assigned against, not to the run carrying it. The window between triage and the ship gate holds a human wait of arbitrary length, and an approving review can add inline threads inside that window — a check bound to state that has since moved is worse than no check, for the confidence it wrongly lends.

- The diff is a set comparison against the stored snapshot, not a `since` / `updated_at` query: resolving or unresolving a thread bumps no comment's `updated_at`, so a time-filtered pass is structurally blind to resolution changes.
- GitHub serves these reads from replicas — a re-read moments after a review was submitted can legitimately return pre-submit state. A single empty diff is weak evidence when it is the only read taken right after a write.

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

**Default: the §2 `gh api graphql` call.** The one escape hatch — when the GitHub MCP server is registered, the read side may take `reviewThreads[]` + `reviews[]` from `mcp__github__pull_request_read` instead (same fields). That payload covers the review surfaces only, so the conversation-tab comments still come from the §2 query. There is no MCP equivalent for §4/§5 writes in the base server, so the write side always uses `gh`.

The read side reports one of three outcomes, never collapsing the last two: items returned — the caller triages them; a sentinel naming that the fetch ran and found no outstanding feedback — the clean path; the fetch failed or did not run — **unknown**, never "clean" (the assessed-sentinel shape: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §"The assessed sentinel"). Fail-open still applies — a shallower triage beats a hard stop on a flaky API call — but bounded: an *unknown* standing in front of an external effect (a reply, a resolve mutation, the ship gate) resolves before that effect fires, by retrying the read or asking the user, rather than riding past it. A failed write marks that item skipped and reports it — never a hard stop, never a silent success.

## 7. Caller contract

- **Read side (`/geniro:resolve`):** read-only at every call site, and there are four. Phase 1 — the run's first contact with the PR; fetch before any analysis, so the verdicts are assigned against the code the comments describe. Phase 3, immediately before the ship gate — re-run the fetch and diff it against the stored §2.5 snapshot, so the gate question reflects the PR as it now stands, not as it stood at triage. Phase 3 again, immediately before staging — the gate waits on a person, so this is the read that actually guards the commit, push, replies and resolve mutations. A resume into Phase 2 or Phase 3 — re-run the same fetch and diff before continuing, so a thread someone already resolved during the gap between runs is not re-triaged.
- **Write side (`/geniro:resolve` Phase 3):** an external write to a public surface — the caller gates it behind an `AskUserQuestion` (the ship gate), exactly like `gh pr create` / `git push`. This helper performs the write; it does NOT own the gate. After a successful reply, the caller appends a `pr-comment-posted` entry to state.md `non-resumable-actions[]`.
- **Item fields:** the read side populates the caller's inventory (`${CLAUDE_PLUGIN_ROOT}/skills/resolve/resolve-reference.md` §1); `thread_id` flows to §5 here, `comment_id` to §4. A thread is resolved only after the caller has confirmed the fix is in the pushed diff.
