---
name: geniro:features
description: "Use when managing a feature backlog or writing a detailed spec for what to build next. Tracks status/priority/complexity; creates specs via codebase scouting, adaptive questioning, and auto-registration."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, WebSearch]
argument-hint: "[command: list|next|add|spec|triage|complete|move|status] [optional: id or description]"
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
| **triage** | `/geniro:features triage [id]` | AI-driven triage: gather context → recommend category → grill → apply outcome (ready-for-agent / ready-for-human / needs-info / wontfix). For bugs, attempts reproduction or routes to `/geniro:debug`. |
| **move** | `/geniro:features move [id] [status]` | Transition a feature's status (planned→in-progress→done, or blocked) |
| **complete** | `/geniro:features complete [id]` | Mark feature as done; explain what was completed |
| **status** | `/geniro:features status` | Quick summary: total, in-progress, done, blocked count |

## Data Format

Features stored in `<PRIMARY_ROOT>/.geniro/planning/FEATURES.md` (resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A — the registry is cross-session and must survive worktree teardown):

```
| ID | Description | Category | Status | Triage | Priority | Complexity | Notes |
|----|-------------|----------|--------|--------|----------|------------|-------|
| F1 | Core auth system | enhancement | done | ready-for-agent | P0 | XL | Shipped v1.0 |
| F2 | Email notifications | enhancement | in-progress | ready-for-human | P1 | M | Needs SMTP config |
| F3 | Admin dashboard | enhancement | planned | ready-for-agent | P2 | L | Spec: admin-dashboard-spec.md |
| F4 | Payment integration | bug | blocked | needs-info | P1 | XL | Blocked on legal review |
```

**Fields:**
- **ID**: Auto-incremented (F1, F2, F3...)
- **Description**: One-sentence feature goal
- **Category**: `bug` (something is broken vs the intended/specified behavior) or `enhancement` (new behavior or improvement). Set by `/geniro:features triage`; defaults to `enhancement` for new entries created by `add`.
- **Status**: `planned` → `in-progress` → `done` (or `blocked` if stuck)
- **Triage**: `needs-triage` (default for new entries, awaiting `/geniro:features triage`) | `needs-info` (blocked on user/reporter for clarifying info) | `ready-for-agent` (scope clear; an agent like `/geniro:implement` can pick it up autonomously) | `ready-for-human` (scope clear but needs human judgment in implementation — auth/payments/UX/cross-stack) | `wontfix` (rejected after triage; kept for searchability)
- **Priority**: P0 (critical), P1 (high), P2 (medium), P3 (low)
- **Complexity**: XS, S, M, L, XL estimate
- **Notes**: Blockers, dependencies, spec file links, triage rationale (1 line)

**Backwards compatibility:** existing FEATURES.md tables without `Category` and `Triage` columns are read as `enhancement` + `needs-triage` defaults. The `list`, `next`, `add`, `move`, `complete`, and `status` commands work without `Category`/`Triage` populated; only `triage` reads/writes them.

## Workflow: Add → Track → Complete

### 0. Load custom instructions (every sub-command)
Before processing any sub-command, load `.geniro/instructions/global.md` if present. Apply its **Rules** and **Constraints** sections throughout the run (e.g., backlog hygiene rules, default-priority policies, required spec sections). Phase-specific "Additional Steps" entries may not have matching phases here — apply where they fit, otherwise skip.

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

## `triage` Subcommand: AI-Driven Triage Pipeline

### Feature ID

`$ARGUMENTS` (after the `triage` keyword) — feature ID like `F3` or `next` (auto-pick the highest-priority `needs-triage` entry).

**If `$ARGUMENTS` is empty**, ask via `AskUserQuestion` with header "Triage": "Which feature to triage?" with options "Next needs-triage entry (auto-pick)" / "I'll provide an ID" / "Cancel".

**If feature ID not in FEATURES.md**: report "F<id> not found in FEATURES.md" and stop.

**If feature is already triaged (Triage != needs-triage)**: ask via `AskUserQuestion` "F<id> is already triaged as `<current-triage>`. Re-triage anyway?" with options "Yes — re-triage" / "Skip" / "Show current triage rationale from Notes".

### Step 1: Gather context (5 min)

1. Read the feature row in FEATURES.md (Description, Category if set, Notes).
2. If a spec file is linked in Notes, read it.
3. Check `<PRIMARY_ROOT>/.geniro/knowledge/learnings.jsonl` for related patterns/gotchas (Grep with description keywords).
4. If `.geniro/planning/<task-dir>/` exists for this feature, read `spec.md` and `state.md`.

### Step 2: Recommend Category (bug vs enhancement)

Apply this rubric — pick the FIRST that matches:

| Signal | Category |
|---|---|
| Description names a broken behavior, error, regression, or "X stopped working" | `bug` |
| Description references existing entity behaving wrong | `bug` |
| Description proposes new functionality or capability | `enhancement` |
| Description proposes optimization / refactor / cleanup of working code | `enhancement` |
| Ambiguous | Ask user via AskUserQuestion (header "Category", options: "Bug — something is broken vs intended behavior" / "Enhancement — new behavior or improvement") |

Auto-select if signals are strong; otherwise ask. Record the recommendation; user can override at Step 6.

### Step 3: Reproduce (bugs only)

If Category is `bug`:
1. Scout the codebase for the affected area (Grep for entity names, file paths mentioned in description).
2. **If reproduction steps are clear AND scoped to ≤5 minutes:** attempt reproduction inline (run a query, hit an endpoint, read the suspect code path).
3. **If reproduction is non-trivial:** offer routing via AskUserQuestion (header "Reproduce", options: "Route to /geniro:debug for systematic investigation (Recommended)" / "Skip reproduction — triage from description alone" / "I'll repro and report back").
4. **If reproduction succeeds:** capture the artifact (failing assertion, log line, screenshot reference) in the triage record (Step 6 Notes column).
5. **If reproduction fails / cannot reproduce in ≤5 minutes / requires user environment:** mark Triage `needs-info` and proceed to Step 4 to gather missing data.

### Step 4: Grill (close gaps before applying outcome)

Identify gaps that block triage:

- **Missing scope** — what exactly is in vs out?
- **Missing acceptance criteria** — how do we know it's done?
- **Missing reproduction** (bugs) — what are the exact steps + environment?
- **Missing rationale** — why is this priority? what does it unblock?

For each gap, ask via `AskUserQuestion` (one question per gap, max 3 gaps per round, max 2 rounds total). After 2 rounds, if gaps remain, mark Triage `needs-info` and write the outstanding questions into Notes per the template below.

### Step 5: Apply Outcome (recommend + ask)

Synthesize the triage outcome from Steps 1-4:

| Outcome | When | Effect |
|---|---|---|
| `ready-for-agent` | Scope clear + acceptance criteria defined + low product-decision risk + no auth/payments/UX subjective judgment | Triage column = ready-for-agent; Status stays `planned` (or moves to `in-progress` only if user explicitly starts work). Feature can be picked up by `/geniro:implement` without a human gate. |
| `ready-for-human` | Scope clear + acceptance criteria defined + needs human judgment in implementation (UX, cross-stack contracts, auth/payments, ambiguous trade-offs) | Triage = ready-for-human; Status stays `planned`. Implementation should NOT be started by an autonomous agent. |
| `needs-info` | Gaps remain after Step 4 grilling | Triage = needs-info; Status moves to `blocked`. Notes populated with structured needs-info template (below). |
| `wontfix` | After triage, the feature is rejected (out of scope, conflicts with constraint, duplicate) | Triage = wontfix; Status moves to `done` (closed without ship); Notes captures rejection rationale (1 line). |

Recommend ONE outcome to the user via `AskUserQuestion` with header "Outcome", listing all 4 with the recommended one first labeled "(Recommended)".

### Step 6: Apply changes to FEATURES.md

After user approves the outcome:

1. Update the feature row's `Category` and `Triage` columns.
2. Update `Status` if the outcome dictates (`needs-info` → `blocked`; `wontfix` → `done`; otherwise unchanged).
3. Append a 1-line triage rationale to Notes: `Triaged YYYY-MM-DD: <outcome> — <rationale>`.
4. If outcome was `needs-info`, write the structured template into Notes (multi-line — use `<br>` or newlines per FEATURES.md's existing convention):

```
## Needs-info template

**Established facts (don't ask again):**
- [bullet — what we already know from triage]
- [bullet]

**Outstanding questions:**
- [Q1 — specific, answerable]
- [Q2]

**To unblock:** answer outstanding questions, then run `/geniro:features triage F<id>` again to re-triage.
```

This ensures resumed triage sessions don't lose prior work.

### Step 7: Post to issue tracker (if integration active)

If `.geniro/workflow/<tracker>.md` exists (Linear, GitHub Issues, etc.) AND the feature is linked to an external issue (via Notes column "Linear: ENG-123" / "GH: #456" pattern):

1. Read the workflow file's AI-disclosure rules and comment-format rules.
2. Compose a triage comment summarizing: outcome, category, rationale, next step.
3. **Prefix the comment with the AI-disclosure marker** specified in the workflow file (e.g., `[AI-generated by Geniro] ` for Linear). Never post AI-authored content to the tracker without the prefix.
4. Post via the tracker's MCP (if available); skip silently with a warning if MCP unavailable.

### Step 8: Confirm and close

Report to the user:
- F<id> triage outcome: <outcome>
- Category: <bug | enhancement>
- Status now: <planned | blocked | done>
- Next action: pick one based on outcome:
  - `ready-for-agent` → "Run `/geniro:features spec F<id>` if no spec exists, or `/geniro:implement F<id>` directly."
  - `ready-for-human` → "Manual implementation; the feature is queued in FEATURES.md."
  - `needs-info` → "Answer the outstanding questions in Notes, then re-run `/geniro:features triage F<id>`."
  - `wontfix` → "Closed as wontfix. Rationale in Notes."

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
- **Module boundaries** — what NEW interface should exist, what should be ABSORBED into existing modules, where the SEAMS sit (use vocabulary from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md`)

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

### Modules & Interfaces
List the deep modules this feature introduces or extends. Use vocabulary from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/architecture-vocabulary.md` (depth, seam, adapter, leverage, locality).

For each module:
- **Name**: [module identifier — what callers will reference]
- **Public interface**: [the smallest possible surface — function signatures, exported types, REST endpoints, CLI flags]
- **Hidden behavior**: [what the implementation absorbs so callers don't have to think about it — rate-limiting, caching, retry, validation, etc.]
- **Seam to existing code**: [where this module connects to the codebase; one-hop max]
- **Reuse?** REUSE-AS-IS / EXTEND existing module / NO-ANALOGUE (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/existing-abstraction-audit.md`)

If this feature is purely additive UI/data with no new interface surface, write "No new modules — extends [existing module]" and skip the per-module breakdown.

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

1. Read `<PRIMARY_ROOT>/.geniro/planning/FEATURES.md` (create if missing)
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

- [ ] Feature file (`<PRIMARY_ROOT>/.geniro/planning/FEATURES.md`, path resolved per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`) exists and is readable
- [ ] All features have ID, description, status, priority, complexity (Category and Triage default to `enhancement` and `needs-triage` for entries created before triage existed)
- [ ] Requested command executed correctly
- [ ] Output is clear and actionable
- [ ] File updated if any changes made
- [ ] Status transitions are valid (planned→in-progress→done, or blocked)
- [ ] (triage command) Step 1 context gathered (FEATURES.md row + linked spec + relevant learnings + planning task-dir if present)
- [ ] (triage command) Category recommended (bug/enhancement) with rubric or asked via AskUserQuestion when ambiguous
- [ ] (triage command) Bugs: reproduction attempted inline OR routed to `/geniro:debug` OR escalated as `needs-info` with reason
- [ ] (triage command) Gaps grilled (max 2 rounds) before applying outcome
- [ ] (triage command) Outcome (ready-for-agent / ready-for-human / needs-info / wontfix) recommended via AskUserQuestion; user approved before any FEATURES.md write
- [ ] (triage command) FEATURES.md row updated: Category + Triage + Status (if outcome dictates) + 1-line rationale appended to Notes
- [ ] (triage command) `needs-info` outcomes write the structured template (Established facts / Outstanding questions / To unblock) into Notes
- [ ] (triage command) If issue-tracker integration active and feature linked to external issue: triage comment posted with the workflow file's AI-disclosure prefix; never post AI-authored content without the prefix
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
