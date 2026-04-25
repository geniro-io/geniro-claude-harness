---
name: pr-notify-slack
description: "Use when a pull request is opened or updated and you want to post a structured summary to Slack #eng-reviews. Do NOT use for force-pushed branches or draft PRs."
model: inherit
allowed-tools: [Read, Bash(gh *), Bash(curl *), AskUserQuestion]
argument-hint: "[pr_number]"
created: 2026-04-25
created-by: geniro:actions
---

# pr-notify-slack

Post a structured summary of a GitHub pull request to Slack `#eng-reviews` so reviewers see context without leaving Slack.

## When to use

- A teammate asks for a Slack ping when a PR is ready to review
- You opened a PR and want to surface it for async review without DMing individuals
- A release-preparation flow needs to broadcast a PR awaiting sign-off

## When NOT to use

- The PR is still in draft (would create noise)
- The branch was just force-pushed (the previous summary may still be relevant — confirm first)
- The repo isn't connected to Slack (no `$SLACK_BOT_TOKEN` in env)

## Steps

1. Resolve the PR number. If `[pr_number]` was passed positionally, use it. Otherwise list open PRs with `gh pr list --json number,title,author --limit 10` and use the `AskUserQuestion` tool to let the user pick one.
2. Fetch PR details: `gh pr view <pr_number> --json number,title,body,author,headRefName,baseRefName,additions,deletions,changedFiles,url,isDraft`.
3. If `isDraft: true`, abort with the message "PR #<n> is still a draft — skipping Slack ping" and stop.
4. Build the Slack message body. Format: title (linked), author handle, base ← head branches, additions/deletions, changedFiles count, first 280 chars of the PR body.
5. Confirm before posting: use the `AskUserQuestion` tool to show the formatted preview and ask "Post to #eng-reviews?" with options "Post it" / "Cancel".
6. POST to Slack: `curl -X POST -H "Authorization: Bearer $SLACK_BOT_TOKEN" -H "Content-Type: application/json" -d '<payload>' https://slack.com/api/chat.postMessage`. Use the `chat.postMessage` API with `channel: "#eng-reviews"`.
7. Verify the response — Slack returns `{"ok": true, "ts": "..."}` on success. If `ok: false`, surface the `error` field.

## Output

A confirmation line with the Slack message timestamp and a permalink, e.g. "Posted to #eng-reviews at 2026-04-25T14:32:11Z — https://geniro.slack.com/archives/CXXX/pYYY".

## Test cases

1. **Happy path**: pass an open non-draft PR number → Slack confirmation line appears.
2. **Draft PR**: pass a draft PR number → action aborts with skip message, no Slack call.
