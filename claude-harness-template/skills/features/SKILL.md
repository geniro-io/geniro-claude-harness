---
name: features
description: "Lightweight feature backlog management. Track features with status, priority, complexity. List, prioritize, add, complete, and check progress without heavyweight PM tools."
context: main
model: haiku
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion]
argument-hint: "[command: list|next|add|complete|status] [optional: id or description]"
---

# Features: Lightweight Backlog & Progress Tracking

Use this skill to manage a project feature backlog without heavyweight PM tools. Track features with status, priority, and complexity. Designed for rapid iteration and clear progress visibility.

## Core Commands

| Command | Usage | Purpose |
|---------|-------|---------|
| **list** | `/features list` | Show all features grouped by status (planned, in-progress, done, blocked) |
| **next** | `/features next` | Show highest-priority unstarted feature ready for work |
| **add** | `/features add [description]` | Add a new planned feature; auto-assigns next ID and priority |
| **move** | `/features move [id] [status]` | Transition a feature's status (planned→in-progress→done, or blocked) |
| **complete** | `/features complete [id]` | Mark feature as done; explain what was completed |
| **status** | `/features status` | Quick summary: total, in-progress, done, blocked count |

## Data Format

Features stored in `.claude/.artifacts/planning/FEATURES.md`:

```
| ID | Description | Status | Priority | Complexity | Notes |
|----|-------------|--------|----------|------------|-------|
| F1 | Core auth system | done | P0 | XL | Shipped v1.0 |
| F2 | Email notifications | in-progress | P1 | M | Needs SMTP config |
| F3 | Admin dashboard | planned | P2 | L | Design pending |
| F4 | Payment integration | blocked | P1 | XL | Blocked on legal review |
```

**Fields:**
- **ID**: Auto-incremented (F1, F2, F3...)
- **Description**: One-sentence feature goal
- **Status**: `planned` → `in-progress` → `done` (or `blocked` if stuck)
- **Priority**: P0 (critical), P1 (high), P2 (medium), P3 (low)
- **Complexity**: XS, S, M, L, XL estimate
- **Notes**: Blockers, dependencies, or context

## Workflow: Add → Track → Complete

### 1. Add Feature
```
/features add Implement dark mode toggle in settings
```
→ Creates new entry with status=planned, auto-assigns ID and priority

### 2. Track Progress
```
/features list                    # See all features
/features next                    # What should I work on?
/features status                  # Quick metrics
```

### 3. Move Status
```
/features move F2 in-progress       # Start working on F2
/features move F4 blocked            # Mark F4 as blocked
```
→ Updates the feature's status in the table. Valid transitions: `planned` → `in-progress` → `done` (or `blocked` at any stage).

### 4. Complete & Mark Done
```
/features complete F2             # Mark F2 as done
```
→ Record what was shipped, move to done section

**Note:** For detailed feature specs, use `/spec [description]`. Specs are stored as separate `*-spec.md` files in `.claude/.artifacts/planning/`.

## Compliance — Do Not Over-Engineer

| Your reasoning | Why it's wrong |
|---|---|
| "Let me add story points and velocity tracking" | Complexity kills adoption. One Markdown table, no databases. |
| "We need a dependency graph first" | Dependency graphs are overhead. Use priority + blockers column instead. |
| "I should optimize the backlog ordering" | Perfect ordering doesn't exist. Sort by priority, pick the top item, ship it. |
| "Let me track this in a separate tool" | Features live in `.claude/.artifacts/planning/FEATURES.md`. One source of truth. |
| "I'll update statuses in bulk later" | Status updates go stale fast. Update when work starts/finishes, not later. |

## Definition of Done

For each skill invocation, confirm:

- [ ] Feature file (`.claude/.artifacts/planning/FEATURES.md`) exists and is readable
- [ ] All features have ID, description, status, priority, complexity
- [ ] Requested command executed (list/next/add/complete/status)
- [ ] Output is clear and actionable
- [ ] File updated if any changes made (add/complete)
- [ ] Status transitions are valid (planned→in-progress→done, or blocked)

---

## When to Use This Skill

**Use `/features`:**
- Starting a project and need lightweight backlog
- Tracking 5–50 features (not thousands)
- Need quick visibility into what's done vs. blocked vs. planned
- Team is 1–10 people (small enough for simple Markdown)
- Want progress without PM overhead

**Don't use:**
- Complex multi-project portfolio management
- Need inter-team dependency tracking
- Tracking 100+ features (use Jira/Linear)

---

## Examples

### List Features
```
/features list
```
→ Output grouped by status with IDs, descriptions, priority, complexity

### Add Feature
```
/features add API rate limiting with token buckets
```
→ New entry: F5 | API rate limiting... | planned | P2 | M | Created today

### Check What's Next
```
/features next
```
→ Show highest P-value unstarted feature with complexity estimate
→ Includes routing hint: "Ready to spec this? `/spec [feature name]`"

### Complete Feature
```
/features complete F3
```
→ Mark F3 as done, prompt for completion notes, update file

### Status Snapshot
```
/features status
```
→ "Total: 12 | In-progress: 2 | Done: 5 | Blocked: 1 | Planned: 4"
