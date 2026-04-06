---
name: spec
description: "Use when gathering requirements and producing a feature specification before implementation. Clarifies intent through adaptive questioning, scouts the codebase for patterns and constraints, produces a canonical spec file."
context: main
model: inherit
allowed-tools: [Read, Bash, Glob, Grep, Write, AskUserQuestion, WebSearch]
argument-hint: "[feature or change to specify]"
---

# Spec: Gather Requirements and Produce Feature Specifications

Use this skill to clarify what a feature should do before building it. Combines adaptive questioning (from GSD discuss-phase, Superpowers brainstorming, Orchestrator Kit) with codebase analysis to produce a canonical specification that guides implementation.

## When to Use This Skill

- **Vague requests:** "Make the dashboard better"
- **Multi-faceted features:** Features with visual, API, and business logic components
- **Architectural decisions:** "Should we cache this?" "REST or GraphQL?"
- **Cross-module work:** Features touching multiple systems
- **Ambiguous scope:** "Add notifications"—to what? How?

**When NOT to use:** Trivial bugfixes, copy edits, or changes with crystal-clear intent (use `/follow-up` instead).

---

## Pipeline: Read Request → Scout Codebase → Identify Gray Areas → Ask Questions → Write Spec

## Feature Request

$ARGUMENTS

**If `$ARGUMENTS` is empty**, ask the user via `AskUserQuestion` with header "Feature": "What feature would you like to specify?" with options "Describe the feature" / "Point to an existing issue". Do not proceed until a feature description is provided.

### 0. Initialize (before anything else)

1. Ensure output directory exists: `mkdir -p .claude/.artifacts/planning/`
2. Check for existing spec files: `ls .claude/.artifacts/planning/*/*.md 2>/dev/null`
   - If specs exist, list them and ask: "Found existing specs. Creating a new one or updating existing?"
3. Check for prior context: glob `.claude/.artifacts/planning/*/` for task directories. If any exist, read their `spec.md` and `state.md` for context that informs this spec

### 1. Read User's Request (1 minute)

Extract the raw intent:
- What problem does this solve?
- Who uses it (internal tool, end user, other system)?
- What's the rough scope?

Note ambiguities and unknowns—these become gray areas.

### 2. Scout the Codebase (5–10 minutes)

Understand patterns and constraints **before** asking questions. Reduces back-and-forth.

**Search for:**
- Existing similar features (how are they structured?)
- Architectural patterns (where do API endpoints live? State management?)
- Database schema (relevant tables, constraints)
- Auth/permissions model (how are permissions enforced?)
- UI patterns (existing component library, design system)
- Integration patterns (how do systems talk to each other?)
- Config/feature flag patterns

**Tools:**
- `Glob` to find files by pattern
- `Grep` to search for keywords (e.g., "notification", "webhook")
- `Read` to examine existing implementations
- `Bash` to explore directory structure

Document findings with file paths and line numbers—you'll reference these in the spec.

### 3. Identify Gray Areas (5 minutes)

From the request and codebase, list specific **ambiguities** that block implementation:

**Visual/UX:**
- Where does this UI live? (new page, sidebar widget, modal, inline?)
- What's the user workflow? (click→see→update→save?)

**API/Data:**
- What's the input shape? Output shape?
- Pagination? Filtering? Sorting?
- Error cases—what goes wrong and how is it signaled?

**Business Logic:**
- Rules/constraints (what can the user do, what's forbidden?)
- Permissions (who can access this? edit this?)
- State transitions (if stateful, what are valid transitions?)

**Architecture:**
- New table? Schema changes?
- Async work needed? (jobs, webhooks, polling)
- Cache/performance concerns?

**Integration:**
- Does this talk to external systems?
- Real-time? Or eventual consistency?

List 3–6 concrete questions, not vague ones.

### 4. Ask Structured Questions (5–10 minutes)

**Use the `AskUserQuestion` tool** to present gray areas as **multiple-choice questions** (2–4 options per question, recommended default, batched together). Do NOT output questions as plain text — always use the tool so the user gets a structured interface to respond.

**If no gray areas remain** (codebase patterns + request fully resolve the feature), present assumed decisions to the user via `AskUserQuestion` with header "Confirm": "Codebase patterns resolve all decisions. Here's what I'll assume: [list decisions]" with options "Looks good, write the spec" / "I have additional requirements". Do not silently skip to spec writing.

**Step 1: Triage gray areas.** Present all identified gray areas via `AskUserQuestion` with `multiSelect: true`: "Which areas need discussion? (Unselected items will use the recommended default.)" If more than 4 gray areas, split into 2 grouped questions.

**Step 2: Discuss selected areas.** For each selected gray area, use `AskUserQuestion` with 2–4 concrete options. Include a recommended default based on codebase patterns.

**Example question structure:**
```
## UI Location
Where should the notifications panel appear?

A) Top-right dropdown (like email inbox)
   - Pro: Familiar, non-intrusive
   - Con: Takes screen real estate
B) Sidebar widget (persistent)
   - Pro: Always visible, good for count badges
   - Con: Takes up sidebar space
C) Modal on login (users don't miss it)
   - Pro: Users see it immediately
   - Con: Can feel pushy

Recommendation: A (dropdown). Matches product's notification style.
```

**Guidelines:**
- Present options concisely (2–3 lines each)
- Include a recommended default based on codebase patterns
- Batch 2–4 questions together (not one per turn)
- After user answers, confirm you understand before moving to spec writing

If user picks non-default, use `AskUserQuestion` to ask "What's the reasoning?" once—don't debate.

**AskUserQuestion fallback:** If `AskUserQuestion` returns an empty or blank answer, fall back to plain text: print the questions as formatted text and ask the user to respond before proceeding. Do not continue with empty answers.

**Max 2 follow-up rounds.** After the initial questions and 2 rounds of follow-up clarification, document remaining ambiguities in the spec's "Open Questions" section and proceed to writing. If 2 rounds are insufficient, suggest splitting into smaller specs.

### Scope Creep Guard

If the user introduces new capabilities during discussion (beyond clarification of existing scope):
1. Note them as "Related but separate: [description]"
2. At spec completion, present captured items: "These came up but are outside current scope. Include in Out of Scope section?"
3. If user insists on expanding, ask: "This changes feature size. Expand this spec or create a separate `/spec`?"

### 5. Write the Spec File (15–30 minutes)

Create a `<feature-name>-spec.md` file in `.claude/.artifacts/planning/` (e.g., `notification-center-spec.md`). Derive the filename: lowercase, spaces to hyphens, remove special characters, max 40 chars. Include canonical references to user decisions.

**Spec structure:**

```markdown
# Feature Spec: [Feature Name]

## Summary
[1–2 sentence problem statement and high-level solution]

## Use Cases
- [User type/role] wants to [action] so that [outcome]
- [User type/role] wants to [action] so that [outcome]

## Scope
- [In scope: what this feature does]
- [Out of scope: related work not included]

## Requirements

### UI/UX
- [Location]: [where in the app]
- [Workflow]: [step-by-step user actions]
- [Look and feel]: [reference existing component or design pattern]

### API
- **Endpoint:** [GET/POST /path]
- **Input:** [schema or example]
- **Output:** [schema or example]
- **Errors:** [what can go wrong, how is it signaled]
- **Pagination/Filtering:** [if applicable]

### Data Model
- **New tables/fields:** [schema]
- **Constraints:** [uniqueness, foreign keys]
- **Migrations:** [if breaking changes]

### Business Logic
- [Rule 1]
- [Rule 2]
- **Permissions:** [who can do what]
- **State machine:** [valid transitions, if stateful]

### Integration
- [External systems touched]
- [Webhooks, events, or polling]
- [Real-time or eventual consistency]

### Performance & Caching
- [Estimated scale: X users, Y requests/sec]
- [Caching strategy, if any]
- [Background work, if any]

## Open Decisions
- [ ] [Decision point from question 1] → User chose: [choice]
- [ ] [Decision point from question 2] → User chose: [choice]

## Canonical References
- **Implementation guide:** See `/implement` skill
- **Related code:** [Link to similar feature in codebase]
- **Design system:** [Link to component library or design doc, if applicable]

## Definition of Done
- [ ] Spec reviewed and approved
- [ ] Implementation satisfies all Requirements section
- [ ] API tested (if applicable)
- [ ] Permission checks tested (if applicable)
- [ ] Migrations run successfully (if applicable)
```

**Guidelines:**
- Keep spec under 3 pages (focus on essentials, not minutiae)
- Reference user's codebase patterns consistently
- Link to existing code or design docs
- Use the exact language user chose (e.g., if they said "panel" not "modal", use "panel")
- Mark assumptions with "Assumption:" if needed
- If a requirement is ambiguous, say so and note it for `/implement`

### 6. Confirm & Close

Read the spec aloud to user:
- "Here's the spec I wrote. Does this match what you're building?"
- "Are there requirements missing or anything that feels off?"

If user says "that's it," confirm:
- "Spec is ready. Next step is `/implement [feature name]` to build it."

If user revises, update spec and re-confirm (usually 1–2 rounds).

---

## Example: Notification Center Feature

### User's Initial Request
"Add notifications so users know when something important happens."

### Codebase Scout Findings
```
- Existing notifications: toast messages in /src/components/Toast
- Email service: /src/services/EmailService (uses third-party API)
- WebSocket setup: /src/lib/websocket (already used for chat)
- Users table: /db/schema.sql (has id, email, preferences)
- Auth: permission checks in /src/middleware/auth.ts
- UI patterns: Dropdowns in /src/components/Dropdown, Modals in /src/components/Modal
```

### Gray Areas Identified
1. Where do notifications live UI-wise? (toast, dropdown, page, sidebar?)
2. What types of notifications? (system alerts, user actions, integrations?)
3. Real-time or polling?
4. Does user need to manage notification preferences?

### Questions Asked (condensed)
```
Q1. Notification delivery method?
A) Real-time via WebSocket (low latency, can cost more)
B) Polling every 10s (cheaper, slight delay)
C) Both—WebSocket for critical, polling fallback

Recommendation: A (WebSocket). You already use it for chat.
User chose: A

Q2. Notification persistence?
A) In-memory (disappears on refresh)
B) Database (users can see history)
C) Database + read receipts (enterprise feature)

Recommendation: B (database). Matches your email notification pattern.
User chose: B
```

### Resulting Spec (excerpt)
```markdown
# Feature Spec: Notification Center

## Summary
Users receive real-time notifications for important events (new messages, updates to shared items, system alerts) via a bell icon dropdown in the top nav. Notifications persist in the database so users can review history.

## UI/UX
- **Location:** Top-right bell icon (matches existing dropdown pattern)
- **Workflow:** Click bell → dropdown shows 5 most recent → "See all" link to full page → click to mark read
- **Look and feel:** Reuse /src/components/Dropdown + /src/components/Badge for count

## API
- **Endpoint:** GET /api/notifications?limit=5&unreadOnly=true
- **Output:** { notifications: [ { id, type, title, message, createdAt, read, link } ], total }

## Data Model
- **New table:** notifications (id, userId, type, title, message, read, createdAt, updatedAt)

## Integration
- **Real-time:** WebSocket event "notification:new" (reuse /src/lib/websocket)
- **Sync:** Fetch on page load + subscribe to new events

## Permissions
- Users can see only their own notifications
```

---

## Definition of Done for Spec Skill

- [ ] Codebase scouted; patterns documented
- [ ] Gray areas identified (3–6 concrete questions)
- [ ] Questions asked and answered by user
- [ ] Spec file written with full Requirements section
- [ ] Spec references canonical code examples
- [ ] User confirmed spec is complete
- [ ] Spec file saved to `.claude/.artifacts/planning/<feature-name>-spec.md`

---

## Compliance — Do Not Skip Steps

| Your reasoning | Why it's wrong |
|---|---|
| "I already know the codebase" | You'll ask questions the code already answers. Scout first. |
| "Let me just ask 'What do you want?'" | Vague questions get vague answers. Ask specific, bounded questions with options. |
| "I'll write the spec and fill in gaps later" | Specs without user input are wrong. Always ask about tradeoffs before writing. |
| "The spec looks complete enough" | A spec the user didn't confirm is a spec that causes rework. Always get explicit confirmation. |
| "This is simple, I can skip straight to writing" | Simple-seeming features hide complex tradeoffs. Scout → Ask → Write → Confirm. Always. |

---

## Sources & Frameworks

This skill draws from:
- **GSD (Getting Stuff Done):** Discuss-phase for clarifying intent
- **Superpowers framework:** Brainstorming with multiple options
- **Orchestrator Kit:** speckit.clarify + speckit.specify for structured requirements
- **SuperClaude:** Confidence-check before implementation

See [Extend Claude with skills - Claude Code Docs](https://code.claude.com/docs/en/skills) for more on skill design.
