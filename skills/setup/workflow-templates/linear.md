# Workflow: Linear Integration

This project uses Linear for issue tracking. Skills read this file at runtime to adapt their behavior.

## Contents

- Argument Detection
- Fetching Issue Context
- Status Transitions
- AI-Disclosure Prefix on Authored Comments
- Commit Message Format
- PR Description
- Implement Skill Behavior
- MCP Setup

## Argument Detection

When parsing `$ARGUMENTS`, check for Linear references **before** treating input as a plain description:

1. **Linear URL** — regex: `https://linear\.app/.+/issue/([A-Z]+-\d+)` → extract issue ID
2. **Issue ID** — regex: `\b[A-Z]{2,}-\d+\b` (e.g., `ENG-123`, `PROJ-42`) → use directly

If both a Linear reference and a plain description are present, use both (fetch issue context + supplement with description).

## Fetching Issue Context

When a Linear reference is detected:

1. Fetch the issue via Linear MCP: extract title, description, acceptance criteria, labels, priority, assignee
2. Use the fetched context to inform discovery/planning — treat it as supplementary input alongside the user's description
3. **If Linear MCP is unavailable:** log a warning and proceed without issue context (non-blocking). Do NOT fail the pipeline.

## Status Transitions

**Never update Linear issue status automatically.** Always ask the user first using `AskUserQuestion`.

### On task start
After fetching the issue, inspect the current `state.name` (Linear status) and `assignee` fields, then send the applicable prompts in a single `AskUserQuestion` call.

The status prompt is conditional on `state.name` — asking "Move to In Progress?" when the issue is already In Progress wastes attention; asking it when the issue is Done is semantically wrong (the user is reopening, not transitioning forward). Branch:

| Current `state.name` | Status prompt behavior |
|---|---|
| `In Progress` | **Skip prompt.** Echo "[ISSUE-ID] already In Progress — no transition needed." |
| Any started, non-terminal state other than `In Progress` (e.g., `In Review`) | Fire — Header: "Linear Status", Question: "[ISSUE-ID] is currently [current-state]. Move back to In Progress?", Options: "Yes — move back to In Progress" / "No — leave as [current-state]" |
| Any non-started, non-terminal state (e.g., `Todo`, `Backlog`, `Triage`) | Fire — Header: "Linear Status", Question: "Move [ISSUE-ID] to In Progress?", Options: "Yes — move to In Progress" / "No — leave as [current-state]" |
| Any terminal state (e.g., `Done`, `Cancelled`, `Duplicate`) | Fire — Header: "Linear Status", Question: "[ISSUE-ID] is currently [current-state]. Reopen and move to In Progress?", Options: "Yes — reopen and move to In Progress" / "No — leave as [current-state]" |
| Unknown / unresolved (Linear MCP unavailable AND no cached status) | Fire — Header: "Linear Status", Question: "Move [ISSUE-ID] to In Progress? (current status unknown — Linear MCP unavailable)", Options: "Yes — move to In Progress" / "No — leave as is" |

`[current-state]` is substituted verbatim with `state.name` — Linear team configurations vary (custom labels like "Blocked", "Waiting on customer"), preserve the user's terminology.

Assignment prompt (only if `assignee` is null):
- Header: "Linear Assignee"
- Question: "Assign [ISSUE-ID] to you?"
- Options: "Yes — assign to me" / "No — leave unassigned"

If the user accepts assignment, call `update_issue({ id: "[ISSUE-ID]", assigneeId: "me" })` — Linear MCP resolves `"me"` to the authenticated user, no separate user lookup needed.

### On task completion
After the user approves shipping, re-fetch `state.name` (the status may have changed externally during implementation) and branch on both the ship action and the current state:

| Ship action | Current `state.name` | Behavior |
|---|---|---|
| **Commit + PR** | `In Review` | Skip move question — already In Review. Ask only "Update [ISSUE-ID] with PR link as comment?" — Options: "Yes" / "No" |
| **Commit + PR** | Any terminal state (`Done` / `Cancelled` / `Duplicate`) | Skip move question — terminal state. Ask only "Update [ISSUE-ID] with PR link as comment?" — Options: "Yes" / "No" |
| **Commit + PR** | Any other non-terminal | Ask "Move [ISSUE-ID] to In Review and add PR link?" — Options: "Yes" / "No" |
| **Commit** OR **Commit + push** | Any terminal state | Skip — no follow-up update needed. |
| **Commit** OR **Commit + push** | Any non-terminal | Ask "Update [ISSUE-ID] with implementation comment?" — Options: "Yes" / "No" |
| **Leave uncommitted** | Any | Do not ask — status was already handled at start. |
| Any | Unknown / unresolved (re-fetch failed AND no cached status) | Ask the action's default question without status preconditions; prefix with "(current status unknown)". |

If Linear MCP is unavailable at this point, log a warning and skip the re-fetch + questions (non-blocking).

## AI-Disclosure Prefix on Authored Comments

Any Linear comment authored by a Geniro skill — implementation summary, triage outcome, status-change rationale, or any text the skill posts via `update_issue` / `create_comment` — MUST begin with the prefix:

```
[AI-generated by Geniro]
```

(literal bracket-prefix, single trailing space, then the comment body)

Rationale: human reviewers and downstream automation need to distinguish AI-authored content from human-authored content at a glance, especially in triage and review workflows where the skill speaks on behalf of the user. The prefix is required regardless of which skill authored the comment (`/geniro:implement` Phase 3 Ship status update, `/geniro:debug` finding summary posted to a Linear issue, etc.).

The prefix is NOT required for:
- Status-only updates (no comment text — just `state: "In Progress"`)
- Assignee-only updates
- Commit messages (those follow the conventional-commits format below; the commit author identity already conveys provenance)
- PR descriptions (PRs ship with `Co-Authored-By` trailers in the commits, which serves the same disclosure role)

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

When `/geniro:implement` receives a Linear issue ID or URL, follow `## Fetching Issue Context` above — the fetched title/description/acceptance criteria flow into Phase 1 (analyze) as planning input. `/geniro:plan` also reads Linear context when a Linear issue ID or URL appears in its `$ARGUMENTS`, persisting it to the spec's `workflow_refs[]`.

## MCP Setup

Linear MCP must be configured for this integration to fetch issues and update status:
```
claude mcp add --transport http linear https://mcp.linear.app/mcp
```

If not configured, all Linear features degrade gracefully — issue IDs are still recognized in arguments and included in commit messages, but fetching/updating requires MCP.
