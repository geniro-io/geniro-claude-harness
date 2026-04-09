---
name: geniro:features
description: "Feature backlog management and spec creation. Track features with status, priority, complexity. Create detailed specs with codebase scouting, adaptive questioning, and auto-registration."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, WebSearch]
argument-hint: "[command: list|next|add|spec|complete|move|status] [optional: id or description]"
---

# Features: Backlog Management & Spec Creation

Use this skill to manage a project feature backlog and create detailed specifications. Track features with status, priority, and complexity. Spec features with codebase scouting, adaptive questioning, and structured output — all registered in one place.

## Core Commands

| Command | Usage | Purpose |
|---------|-------|---------|
| **list** | `/geniro:features list` | Show all features grouped by status; scan for unregistered `*-spec.md` files |
| **next** | `/geniro:features next` | Show highest-priority unstarted feature ready for work |
| **add** | `/geniro:features add [description]` | Add a new planned feature; auto-assigns next ID and priority |
| **spec** | `/geniro:features spec [id or description]` | Full spec pipeline — scout codebase, identify gray areas, ask questions, write spec, register in backlog |
| **move** | `/geniro:features move [id] [status]` | Transition a feature's status (planned→in-progress→done, or blocked) |
| **complete** | `/geniro:features complete [id]` | Mark feature as done; explain what was completed |
| **status** | `/geniro:features status` | Quick summary: total, in-progress, done, blocked count |

## Data Format

Features stored in `.geniro/planning/FEATURES.md`:

```
| ID | Description | Status | Priority | Complexity | Notes |
|----|-------------|--------|----------|------------|-------|
| F1 | Core auth system | done | P0 | XL | Shipped v1.0 |
| F2 | Email notifications | in-progress | P1 | M | Needs SMTP config |
| F3 | Admin dashboard | planned | P2 | L | Spec: admin-dashboard-spec.md |
| F4 | Payment integration | blocked | P1 | XL | Blocked on legal review |
```

**Fields:**
- **ID**: Auto-incremented (F1, F2, F3...)
- **Description**: One-sentence feature goal
- **Status**: `planned` → `in-progress` → `done` (or `blocked` if stuck)
- **Priority**: P0 (critical), P1 (high), P2 (medium), P3 (low)
- **Complexity**: XS, S, M, L, XL estimate
- **Notes**: Blockers, dependencies, spec file links

## Workflow: Add → Track → Complete

### 1. Add Feature
```
/geniro:features add Implement dark mode toggle in settings
```
→ Creates new entry with status=planned, auto-assigns ID and priority

### 2. Track Progress
```
/geniro:features list                    # See all features
/geniro:features next                    # What should I work on?
/geniro:features status                  # Quick metrics
```

### 3. Move Status
```
/geniro:features move F2 in-progress       # Start working on F2
/geniro:features move F4 blocked            # Mark F4 as blocked
```
→ Updates the feature's status in the table. Valid transitions: `planned` → `in-progress` → `done` (or `blocked` at any stage).

### 4. Complete & Mark Done
```
/geniro:features complete F2             # Mark F2 as done
```
→ Record what was shipped, move to done section

---

## `list` Command: Unregistered Spec Detection

Before displaying the features table, scan for orphan specs:

1. Glob `.geniro/planning/*-spec.md`
2. For each spec file found, check if it's referenced in FEATURES.md (in the Notes column)
3. If unregistered specs exist, surface them first:
   ```
   Found N unregistered specs: [names]. Add them to the backlog?
   (use `/geniro:features add` or I can auto-register them)
   ```
4. If user agrees to auto-register, create new FEATURES.md rows with status=planned and Notes linking to the spec file
5. Then display the full features table grouped by status

---

## `spec` Subcommand: Full Spec Pipeline

### Feature Request

`$ARGUMENTS` (after the `spec` keyword)

**If `$ARGUMENTS` is empty**, ask the user via `AskUserQuestion` with header "Feature": "What feature would you like to specify?" with options "Describe the feature" / "Point to an existing issue". Do not proceed until a feature description is provided.

**If `$ARGUMENTS` is a feature ID** (e.g., F3), look up the description from FEATURES.md and use that as the feature to spec.

### Step 0. Initialize

1. Ensure output directory exists: `mkdir -p .geniro/planning/`
2. Check for existing spec files: `ls .geniro/planning/*-spec.md 2>/dev/null`
   - If specs exist, list them and ask: "Found existing specs. Creating a new one or updating existing?"
3. Check for prior context: glob `.geniro/planning/*/` for task directories. If any exist, read their `spec.md` and `state.md` for context that informs this spec

### Step 1. Read User's Request (1 minute)

Extract the raw intent:
- What problem does this solve?
- Who uses it (internal tool, end user, other system)?
- What's the rough scope?

Note ambiguities and unknowns — these become gray areas.

### Step 2. Scout the Codebase (5–10 minutes)

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

Document findings with file paths and line numbers — you'll reference these in the spec.

### Step 3. Identify Gray Areas (5 minutes)

From the request and codebase, list specific **ambiguities** that block implementation:

**Visual/UX:**
- Where does this UI live? (new page, sidebar widget, modal, inline?)
- What's the user workflow? (click→see→update→save?)

**API/Data:**
- What's the input shape? Output shape?
- Pagination? Filtering? Sorting?
- Error cases — what goes wrong and how is it signaled?

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

### Step 4. Ask Structured Questions (5–10 minutes)

**Use the `AskUserQuestion` tool** to present gray areas as **multiple-choice questions** (2–4 options per question, recommended default, batched together). Do NOT output questions as plain text — always use the tool so the user gets a structured interface to respond.

**If no gray areas remain** (codebase patterns + request fully resolve the feature), present assumed decisions to the user via `AskUserQuestion` with header "Confirm": "Codebase patterns resolve all decisions. Here's what I'll assume: [list decisions]" with options "Looks good, write the spec" / "I have additional requirements". Do not silently skip to spec writing.

**Triage gray areas.** Present all identified gray areas via `AskUserQuestion` with `multiSelect: true`: "Which areas need discussion? (Unselected items will use the recommended default.)" If more than 4 gray areas, split into 2 grouped questions.

**Discuss selected areas.** For each selected gray area, use `AskUserQuestion` with 2–4 concrete options. Include a recommended default based on codebase patterns.

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

Recommendation: A (dropdown). Matches product's notification style.
```

**Guidelines:**
- Present options concisely (2–3 lines each)
- Include a recommended default based on codebase patterns
- Batch 2–4 questions together (not one per turn)
- After user answers, confirm you understand before moving to spec writing

If user picks non-default, use `AskUserQuestion` to ask "What's the reasoning?" once — don't debate.

**AskUserQuestion fallback:** If `AskUserQuestion` returns an empty or blank answer, fall back to plain text: print the questions as formatted text and ask the user to respond before proceeding. Do not continue with empty answers.

**Max 2 follow-up rounds.** After the initial questions and 2 rounds of follow-up clarification, document remaining ambiguities in the spec's "Open Questions" section and proceed to writing. If 2 rounds are insufficient, suggest splitting into smaller specs.

### Scope Creep Guard

If the user introduces new capabilities during discussion (beyond clarification of existing scope):
1. Note them as "Related but separate: [description]"
2. At spec completion, present captured items: "These came up but are outside current scope. Include in Out of Scope section?"
3. If user insists on expanding, ask: "This changes feature size. Expand this spec or create a separate `/geniro:features spec`?"

### Step 5. Write the Spec File (15–30 minutes)

Create a `<feature-name>-spec.md` file in `.geniro/planning/` (e.g., `notification-center-spec.md`). Derive the filename: lowercase, spaces to hyphens, remove special characters, max 40 chars. Include canonical references to user decisions.

**Spec structure:**

```markdown
# Feature Spec: [Feature Name]

## Summary
[1–2 sentence problem statement and high-level solution]

## Use Cases
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

### Data Model
- **New tables/fields:** [schema]
- **Constraints:** [uniqueness, foreign keys]
- **Migrations:** [if breaking changes]

### Business Logic
- [Rules and constraints]
- **Permissions:** [who can do what]
- **State machine:** [valid transitions, if stateful]

### Integration
- [External systems touched]
- [Webhooks, events, or polling]

### Performance & Caching
- [Estimated scale]
- [Caching strategy, if any]

## Open Decisions
- [ ] [Decision point] → User chose: [choice]

## Canonical References
- **Implementation guide:** See `/geniro:implement` skill
- **Related code:** [Link to similar feature in codebase]

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

### Step 5a. Validate Against Repo Conventions

Before registering, quick-check the spec's architectural proposals against the codebase:
- Grep for similar existing features — does the proposed architecture (new tables, API patterns, component patterns) match how the repo implements similar features?
- If proposed patterns contradict established conventions (e.g., spec proposes REST when repo uses GraphQL, or proposes a new ORM when repo uses raw SQL), flag in the spec's "Open Decisions" section and ask the user via `AskUserQuestion` before proceeding.
- This is a lightweight inline check, not a full agent spawn — the user reviews the spec in Step 6.

### Step 5b. Register in FEATURES.md

After writing the spec file, update the backlog:

1. Read `.geniro/planning/FEATURES.md` (create if missing)
2. **If an existing feature ID was provided** (e.g., `/geniro:features spec F3`): update that row's Notes column to link the spec file (e.g., `Spec: notification-center-spec.md`)
3. **If a description was provided** (e.g., `/geniro:features spec Add notifications`): create a new row with:
   - Next auto-incremented ID
   - Description from the spec's Summary
   - Status: `planned`
   - Priority: P2 (default, adjustable)
   - Complexity: estimate from spec scope
   - Notes: `Spec: <feature-name>-spec.md`
4. Confirm registration: "Registered as F[N] in FEATURES.md with link to spec."

### Step 6. Confirm & Close

Read the spec aloud to user:
- "Here's the spec I wrote. Does this match what you're building?"
- "Are there requirements missing or anything that feels off?"

If user says "that's it," confirm:
- "Spec is ready and registered in FEATURES.md. Next step is `/geniro:implement [feature name]` to build it."

If user revises, update spec and re-confirm (usually 1–2 rounds).

---

## Spec Example (Condensed)

**User request:** "Add notifications so users know when something important happens."

**Scout findings:** Existing toast in `/src/components/Toast`, WebSocket in `/src/lib/websocket`, Users table in `/db/schema.sql`.

**Gray areas:** UI location? Notification types? Real-time or polling? Preferences management?

**Questions asked:** Delivery method → User chose WebSocket. Persistence → User chose database.

**Resulting spec excerpt:**
```markdown
# Feature Spec: Notification Center
## Summary
Real-time notifications via bell icon dropdown. Persisted in database for history.
## UI/UX
- Location: Top-right bell icon (reuse Dropdown + Badge components)
- Workflow: Click bell → dropdown → "See all" → click to mark read
## API
- GET /api/notifications?limit=5&unreadOnly=true
## Data Model
- New table: notifications (id, userId, type, title, message, read, createdAt)
## Integration
- WebSocket event "notification:new" (reuse /src/lib/websocket)
```

Registered as F5 in FEATURES.md with `Notes: Spec: notification-center-spec.md`.

---

## Examples

### List Features
```
/geniro:features list
```
→ Scans for unregistered specs, then shows features grouped by status

### Add Feature
```
/geniro:features add API rate limiting with token buckets
```
→ New entry: F5 | API rate limiting... | planned | P2 | M | Created today

### Check What's Next
```
/geniro:features next
```
→ Show highest P-value unstarted feature with complexity estimate
→ Routing hint: "Ready to spec this? `/geniro:features spec [feature name]`"

### Spec a Feature
```
/geniro:features spec F3                    # Spec existing feature by ID
/geniro:features spec Add payment system    # Spec new feature by description
```
→ Runs full pipeline: scout → ask → write → register

---

## When to Use

- **`/geniro:features list|add|next|status|move|complete`** — lightweight backlog management for 5–50 features
- **`/geniro:features spec`** — vague requests, multi-faceted features, architectural decisions, cross-module work, ambiguous scope
- **Don't use spec for:** trivial bugfixes, copy edits, or changes with crystal-clear intent (use `/geniro:follow-up` instead)
- **Don't use features for:** 100+ feature portfolios (use Jira/Linear)

---

## Definition of Done

For each skill invocation, confirm:

- [ ] Feature file (`.geniro/planning/FEATURES.md`) exists and is readable
- [ ] All features have ID, description, status, priority, complexity
- [ ] Requested command executed correctly
- [ ] Output is clear and actionable
- [ ] File updated if any changes made
- [ ] Status transitions are valid (planned→in-progress→done, or blocked)
- [ ] (spec command) Codebase scouted; patterns documented
- [ ] (spec command) Gray areas identified (3–6 concrete questions)
- [ ] (spec command) Questions asked and answered by user
- [ ] (spec command) Spec file written with full Requirements section
- [ ] (spec command) Spec validated against repo conventions
- [ ] (spec command) Spec registered in FEATURES.md
- [ ] (spec command) User confirmed spec is complete

---

## Compliance — Do Not Skip Steps or Over-Engineer

| Your reasoning | Why it's wrong |
|---|---|
| "Let me add story points and velocity tracking" | Complexity kills adoption. One Markdown table, no databases. |
| "We need a dependency graph first" | Use priority + blockers column instead. |
| "I should optimize the backlog ordering" | Sort by priority, pick the top item, ship it. |
| "Let me track this in a separate tool" | Features live in FEATURES.md. One source of truth. |
| "I already know the codebase" | You'll ask questions the code already answers. Scout first. |
| "Let me just ask 'What do you want?'" | Vague questions get vague answers. Ask specific, bounded questions with options. |
| "I'll write the spec and fill in gaps later" | Specs without user input are wrong. Always ask about tradeoffs before writing. |
| "The spec looks complete enough" | A spec the user didn't confirm causes rework. Always get explicit confirmation. |
| "This is simple, I can skip straight to writing" | Simple-seeming features hide complex tradeoffs. Scout → Ask → Write → Confirm. Always. |
