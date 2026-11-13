# User-facing prose — plain English

Detail behind `.claude/rules/skill-prose.md` §"User-facing output uses plain English". Not auto-loaded: read it before writing or editing a string the orchestrator surfaces to the user.

## The fresh-user test

**A fresh user with the plugin installed but no architecture docs loaded — no `CLAUDE.md`, no `state-tier-spec.md` — must be able to act on the string without first learning a Geniro-specific identifier.** If understanding it requires knowing `T2` / `FIX-NOW` / `phase: triage` / `m5-v2` / `KR`, restate the identifier's meaning inline or drop it for the plain-English form.

Both dimensions must pass:

- **No untranslated identifiers.** `T2` / `FIX-NOW` / `phase: triage` restated inline or dropped.
- **No assumed hidden context.** The string explains the situation it is about. A review gate asking *"How should we handle the implicit entity-default @Filter at the 3 call sites?"* fails even though every word is plain English — the user was never shown what that code does, why it is a concern, or what the options mean. For decisions carrying finding or investigation context, render the self-contained explanation to a chat message first, then fire a lean question, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering.

Applies to everything the orchestrator surfaces: chat narration, todo-list labels, `AskUserQuestion` `header` / `question` / `description` / option `label` / `preview`, status echoes, final report sections, and errors surfaced to chat (not the state-file `## Errors` body section — that is a structured artifact for downstream consumers).

## Explanations are layered

Plain layer first, `**Technical detail:**` block second — `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers is canonical. When a render template in a skill or reference enumerates its slots, the slot list names both layers and puts the cites in the second; a slot list ending at `**Why it matters:** … (evidence: path:lines)` merges them back.

## Translation tables

Extend when new internal vocabulary appears.

| Family | Internal term | Plain-English form for user-facing prose |
|---|---|---|
| Memory layer | `L1` / working memory | "task state" / "session state" |
| | `L2` / episodic memory / learnings | "past learnings" / "prior knowledge" |
| | `L3` / semantic memory / snapshot | "project snapshot" / "codebase map" |
| | `L4` / procedural memory / instructions | "custom instructions" / "project rules" |
| State tier | `T1` / ephemeral state | "scratch files" / "transient working files" |
| | `T1.5` / durable task state | "task artifacts" |
| | `T2` / handoff | "handoff" (drop the `T2` — the word carries the semantic) |
| | `T3` / persistent state | "persistent state" (drop `T3`) |
| Subagent | `KR` / `KR output` | "knowledge-retrieval agent" / "knowledge-retrieval output" |
| | `CE` / `CE output` | "codebase-explorer agent" / "codebase-explorer output" |
| | `TR` / `TR output` | "test-runner agent" / "test-runner output" |
| Decision type (reviewer-internal) | `FIX-NOW` | "automatic fix" / "I can fix this directly" |
| | `TESTABLE` | "this can be verified with a test" |
| | `PRODUCT-DECISION` | "needs your decision" / "judgment call required" |
| | `INTENT-CHECK` | "needs you to confirm intent" |
| Cause type (debug-internal) | `ROOT-CAUSE` | "root cause" |
| | `SYMPTOM` | "surface symptom" / "downstream effect" |
| | `UNKNOWN` | "cause not yet identified" |
| Frontmatter field | `approvals[]` | "decisions you've made in this run" / "saved choices" |
| | `non-resumable-actions[]` | "external actions that can't be undone (push, PR open)" |
| | `workflow_refs[]` | "linked tracker tickets" |
| | `open_questions[]` | "open questions from the prior review/debug" |
| | `related_findings[]` | "findings this question gates" |

**Everything else** — phase / step labels (`Phase 4.3`, `Step 0b`), state-machine enum values (`phase: analyze`), reviewer dimension slugs (`spec-compliance`), schema versions (`m5-v2`), helper / hook names (`load_semantic`, `PreToolUse`). Narrate what is happening or what a helper did, never the identifier: "Analyzing the change scope", not "Now in `phase: analyze`"; "Couldn't refresh the project snapshot", not "load_semantic returned rc=11". Surface a schema version only when the user must act on the difference, and then describe the action ("this spec uses the older format and needs re-authoring"), not the version. Cross-reference a step by its concept ("the open-question gate"), not its number.

## What's exempt

The rule governs narrative prose surfaced to the user. It does not govern:

- **Filesystem paths** (`.kr-out.md`, `_CODEBASE_MAP.md`) — their prefixes and extensions carry the semantics. Keep them.
- **YAML / JSON keys inside code blocks** rendered to the user.
- **Architectural sections documenting the layer / tier / subagent system itself** — `CLAUDE.md` §Memory Layers, `skills/_shared/state-tier-spec.md`. Those address authors.
- **Skill body declarative prose** referencing architecture for authors — the orchestrator paraphrases rather than echoes it.
- **`## Errors` body sections** in state files. The chat-surfaced version of the same error still follows the rule.

## Step titles ARE user-facing

The model echoes a step title when it executes the step. `5. **Load custom instructions.**` is fine; `5. **Load L4 instructions.**` is not. This is the most common leak vector — fix step titles first when auditing a skill. Section headers behave the same way: the model paraphrases them into narration.

## Anti-rationalization

| Rationalization | What's actually wrong |
|---|---|
| "The user can grep the architecture docs if they don't understand `T2`." | Forcing a context-switch into doc archaeology to read a progress message is the failure this test prevents. |
| "Spelling out `knowledge-retrieval agent` every time bloats the prose." | Three words per occurrence is the cost of clarity. The body has the bandwidth; the user-facing surface is the load-bearing constraint. |
| "The skill body uses `Phase 4.3` everywhere — I'll keep it for consistency in echoes." | Consistency with author-facing vocabulary IS the problem: the model echoes it verbatim because it sees no signal not to. |
| "`PRODUCT-DECISION` is precise; 'needs your decision' loses precision." | That precision serves author-side coordination, mapping findings to gates. The user needs to act on the decision, not learn the taxonomy. |
| "`(Internal: L4 procedural memory layer)` preserves the cross-reference without confusing the user." | The model echoes the parenthetical too. The rule is binary at the user surface; author cross-references live in the architecture docs. |
