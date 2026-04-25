# Workflow: Linear Integration

This project uses Linear for issue tracking. Skills read this file at runtime to adapt their behavior.

## Argument Detection

When parsing `$ARGUMENTS`, check for Linear references **before** treating input as a plain description:

1. **Linear URL** — regex: `https://linear\.app/.+/issue/([A-Z]+-\d+)` → extract issue ID
2. **Issue ID** — regex: `\b[A-Z]{2,}-\d+\b` (e.g., `ENG-123`, `PROJ-42`) → use directly

If both a Linear reference and a plain description are present, use both (fetch issue context + supplement with description).

## Fetching Issue Context

When a Linear reference is detected:

1. Fetch the issue via Linear MCP: extract title, description, acceptance criteria, labels, priority
2. Use the fetched context to inform discovery/planning — treat it as supplementary input alongside the user's description
3. **If Linear MCP is unavailable:** log a warning and proceed without issue context (non-blocking). Do NOT fail the pipeline.

## Status Transitions

**Never update Linear issue status automatically.** Always ask the user first using `AskUserQuestion`.

### On task start (implement/follow-up Phase 1)
After fetching the issue, ask:
- Header: "Linear Status"
- Question: "Move [ISSUE-ID] to In Progress?"
- Options: "Yes — move to In Progress" / "No — leave current status"

### On task completion (implement Phase 7 / follow-up Phase 6)
After the user approves shipping:

- **After Commit + PR:** Ask "Move [ISSUE-ID] to In Review and add PR link?" — Options: "Yes" / "No"
- **After Commit or Commit + push:** Ask "Update [ISSUE-ID] with implementation comment?" — Options: "Yes" / "No"
- **After Leave uncommitted:** Do not ask — status was already handled at start

If Linear MCP is unavailable at this point, log a warning and skip (non-blocking).

## Commit Message Format

When a Linear issue ID was detected, include it in the commit message:
```
feat(module): description [ENG-123]
```

The issue ID goes in square brackets at the end of the first line.

## PR Description

When creating a pull request and a Linear issue was detected, include:
```
Linear: [ISSUE-ID](https://linear.app/team/issue/ISSUE-ID)
```
in the PR description body.

## Implement Skill Behavior

When `/geniro:implement` receives a Linear issue ID or URL:
1. Fetch the issue via MCP (same rules as above)
2. Use title/description/acceptance criteria as planning input for Phase 2 (architect+skeptic)
3. If MCP unavailable: log warning, proceed with whatever description was provided

## MCP Setup

Linear MCP must be configured for this integration to fetch issues and update status:
```
claude mcp add --transport http linear https://mcp.linear.app/mcp
```

If not configured, all Linear features degrade gracefully — issue IDs are still recognized in arguments and included in commit messages, but fetching/updating requires MCP.
