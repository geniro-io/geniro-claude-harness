---
name: geniro:features
description: "Use when managing a feature backlog or registering a new feature with an associated design doc. Tracks status/priority/complexity; `add` is the unified ideation+registration entry that runs the shared brainstorming loop or accepts an existing design doc."
context: main
model: inherit
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, WebSearch]
argument-hint: "[command: list|next|add|triage|complete|move|status] [optional: id, description, or design-doc path]"
---

# Features: Backlog Management & Registration

Use this skill to manage a project feature backlog. Track features with status, priority, and complexity, and register new features with an associated design doc.

`/geniro:features` is the **backlog layer** — it tracks, prioritizes, and stores status. `/geniro:brainstorm` is the **ideation layer** for cases without backlog commitment. The `add` subcommand and `/geniro:brainstorm` use the SAME canonical ideation procedure (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md`); `add` adds backlog registration as a Phase 9 step on top.

## Core Commands

| Command | Usage | Purpose |
|---------|-------|---------|
| **list** | `/geniro:features list` | Show all features grouped by status; scan for unregistered `*-spec.md` files |
| **next** | `/geniro:features next` | Show highest-priority unstarted feature ready for work |
| **add** | `/geniro:features add <topic-string-or-design-path>` | Unified ideation+registration entry. If passed an existing design-doc path, skip ideation and register directly. If passed a topic string, run the shared brainstorming loop, write a design doc, then register. |
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
Before processing any sub-command: **Step 0 — Load custom instructions.** Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` with `SKILL_SLUG: features`, `LOAD_TIER: rules-only`, `MODE: initial-load`. The helper's §Procedure prescribes an imperative `Read` of `global.md`; its §Echo contract requires one observable line. Both are mandatory. The load fires on every sub-command invocation.

### 1. Add Feature
```
/geniro:features add Implement dark mode toggle in settings
/geniro:features add .geniro/planning/my-branch/2026-05-10-dark-mode-design.md
```
→ Runs the shared brainstorming loop (topic string) or skips ideation (design-doc path), then registers in FEATURES.md with auto-assigned ID. See the `add` Subcommand section below for the full procedure.

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
  - `ready-for-agent` → "Run `/geniro:features add F<id>` if no design doc exists, or `/geniro:implement F<id>` directly."
  - `ready-for-human` → "Manual implementation; the feature is queued in FEATURES.md."
  - `needs-info` → "Answer the outstanding questions in Notes, then re-run `/geniro:features triage F<id>`."
  - `wontfix` → "Closed as wontfix. Rationale in Notes."

---

## `add` Subcommand: Unified Ideation + Backlog Registration

`/geniro:features add <topic-string-or-design-path>` — register a feature in the backlog with an associated design doc. If a topic string is passed, run the shared brainstorming loop to produce the design doc; if an existing design-doc path is passed, skip ideation and register directly.

### Phase 0 — Input mode detection

Cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` and run its detection algorithm on the first non-flag token of `$ARGUMENTS` (after stripping the `add` keyword):

- `mode=DESIGN_DOC` (token resolves to an existing design doc — path-glob, HTML marker, or YAML frontmatter match per ANY-OF semantics) → SKIP ideation entirely; jump to Phase 9 below with `<design-path>` set to the resolved path.
- `mode=IDEA` (token does not resolve to a file) → run the shared brainstorming loop (Phases 1–8 below), then proceed to Phase 9.
- `mode=CODE_REFERENCE` (token resolves to a file but no design-doc marker matches) → error: "argument resolves to a code reference, not a design doc; pass a topic string or a design-doc path".

**If `$ARGUMENTS` is empty after stripping the keyword**, ask via `AskUserQuestion` with header "Feature": "What feature would you like to add?" with options "Describe the feature (run brainstorming loop)" / "Point to an existing design doc" / "Cancel". Do not proceed until input is provided.

NO `--from-design` flag. Detection is via `design-doc-detect.md` ANY-OF rules; the contract is flag-free.

### Phases 1–8 — Brainstorming loop

Cite `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` for the canonical 8-phase procedure (Explore / Visual companion / Clarifying / Approaches / Section approval / Write design doc / Self-review / Post-spec user re-review). Do NOT inline-paste the loop logic — the shared rule is the single source of truth.

The HARD-GATE in `brainstorming-loop.md` is binding for Phases 1–8; release happens only on the user's "Approve" choice in Phase 8. After release, control returns here for Phase 9.

### Phase 9 — Backlog registration (skill-specific)

After Phase 8 release (or on direct entry from Phase 0 `mode=DESIGN_DOC`), update the backlog:

1. Read `<PRIMARY_ROOT>/.geniro/planning/FEATURES.md` (create if missing; resolve `<PRIMARY_ROOT>` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` Mode A).
2. Assign the next auto-incremented F-id (scan existing rows for max ID, increment).
3. Append a new row with:
   - **ID**: next F-id
   - **Description / title**: H1 from the design doc (strip leading `# `)
   - **Category**: `enhancement` (default; user can re-categorize via `/geniro:features triage`)
   - **Status**: `planned`
   - **Triage**: `Triage` (i.e. `needs-triage`)
   - **Priority**: ask via `AskUserQuestion` (header "Priority", options "P1 — high", "P2 — medium (Recommended)", "P3 — low")
   - **Complexity**: estimate from design-doc scope (XS / S / M / L / XL)
   - **Notes**: link to the design-doc path (e.g. `Design: .geniro/planning/<branch>/<YYYY-MM-DD>-<topic-slug>-design.md`)
4. Commit the FEATURES.md update with message `features: register F<id> — <title>`. Do not amend prior commits.
5. Confirm registration to the user: "Registered as F<id> in FEATURES.md, linked to <design-path>."

### Phase 10 — Hand-off menu

Per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` AUQ schema, fire `AskUserQuestion`:

- `header`: `"Hand-off"`
- `question`: `"Feature F<id> registered. What's next?"`
- `options[]`:
  - `label`: `"Decompose now"` — `description`: `"Run /geniro:decompose <design-path> to break the feature into 3–7 milestones."`
  - `label`: `"Implement now"` — `description`: `"Run /geniro:implement <design-path> to start architecture review and implementation."`
  - `label`: `"Leave in backlog"` — `description`: `"Done — feature is queued in FEATURES.md for later. No further action."`

On the user's choice, surface the routing line (do not auto-invoke the next skill — the user invokes it explicitly).

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
→ Routing hint: "Ready to design + register this? `/geniro:features add [feature description]`"

### Add a Feature from an Existing Design Doc
```
/geniro:features add .geniro/planning/my-branch/2026-05-10-payments-design.md
```
→ Skips ideation (Phase 0 detects `mode=DESIGN_DOC`); jumps straight to Phase 9 backlog registration and Phase 10 hand-off menu.

---

## When to Use

- **`/geniro:features list|next|status|move|complete|triage`** — lightweight backlog management for 5–50 features.
- **`/geniro:features add <topic-or-design-path>`** — unified ideation + registration entry. Runs the shared `brainstorming-loop.md` for topic strings (vague requests, multi-faceted features, architectural decisions, cross-module work, ambiguous scope), or skips ideation and registers directly when an existing design-doc path is passed.
- **`/geniro:brainstorm`** — pure ideation layer for cases without backlog commitment; uses the SAME `brainstorming-loop.md` shared rule but does not register a feature. Use when you want a design doc without a FEATURES.md row.
- **Don't use `add` for:** trivial bugfixes, copy edits, or changes with crystal-clear intent (use `/geniro:follow-up` instead).
- **Don't use features for:** 100+ feature portfolios (use Jira/Linear).

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
- [ ] (add command) Phase 0 input-mode detection ran per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` (DESIGN_DOC / IDEA / CODE_REFERENCE)
- [ ] (add command, IDEA mode) Brainstorming loop ran per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md`; HARD-GATE released only on Phase 8 user "Approve"
- [ ] (add command) Phase 9 registered the feature in FEATURES.md with next F-id, title from design-doc H1, status `planned`, Triage `needs-triage`, priority via AskUserQuestion, complexity estimate, Notes linking the design-doc path
- [ ] (add command) FEATURES.md update committed with message `features: register F<id> — <title>` (fresh commit, not amended)
- [ ] (add command) Phase 10 hand-off menu fired (Decompose / Implement / Leave in backlog)

---

## Compliance — Do Not Skip Steps or Over-Engineer

| Your reasoning | Why it's wrong |
|---|---|
| "Let me add story points and velocity tracking" | Complexity kills adoption. One Markdown table, no databases. |
| "We need a dependency graph first" | Use priority + blockers column instead. |
| "I should optimize the backlog ordering" | Sort by priority, pick the top item, ship it. |
| "Let me track this in a separate tool" | Features live in FEATURES.md. One source of truth. |
| "I already know the codebase" | You'll ask questions the code already answers. Scout first. |
| "Let me just ask 'What do you want?'" | Vague questions get vague answers. Use `brainstorming-loop.md` Phase 3 — one dimension per AUQ, ≤5 total questions, single-select options. |
| "I'll inline-paste the brainstorming loop here for clarity" | Forbidden. The shared rule `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` is the single source of truth. Cite it; do NOT duplicate the loop logic. |
| "The design doc looks complete enough; I'll skip Phase 8 user re-review" | Same failure mode as auto-dropping medium-gate. Self-review and user re-review catch different defect classes. Both are required by the shared rule. |
| "This is simple, I can skip straight to FEATURES.md registration" | The HARD-GATE in `brainstorming-loop.md` applies to EVERY task regardless of perceived simplicity. Trivial topics get a trivial design (1–2 sections in Phase 5), not zero design. |
| "I'll add a `--from-design` flag so users can skip ideation explicitly" | Forbidden. Auto-detection via `design-doc-detect.md` ANY-OF rules is the contract. Adding a flag duplicates the marker information and creates a "did you remember the flag?" failure mode. |
