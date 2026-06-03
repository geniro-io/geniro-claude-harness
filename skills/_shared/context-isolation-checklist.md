# Context Isolation Checklist

Co-cited with `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every Agent() spawn site. spawn-agent.md handles agent-name resolution + runtime degradation; this file handles prompt richness. Together they ensure subagents never inherit orchestrator session state.

This file is the single source of truth for the pre-inlined-context contract every Agent() spawn must satisfy. Skills cite this file; do NOT inline-paste the checklist.

## Why this exists

Subagents do not share memory, working set, or CLAUDE.md context with the orchestrator. An agent spawned with the prompt `"investigate the auth bug"` starts from zero — no knowledge of which files the orchestrator just read, which conventions matter, which tools are off-limits, or what the deliverable shape is. Three observed failure modes when the checklist is skipped:

- The agent re-discovers files via Glob that the orchestrator already had open, doubling latency and burning tokens on rediscovery.
- The agent improvises an output schema (free-form prose) that downstream parsing cannot consume — orchestrator falls back to re-prompting or running the work itself.
- The agent calls Edit/Write when the orchestrator only wanted analysis, mutating the tree in ways the spawn site never anticipated.

Pre-inlining the six required fields below collapses all three failure modes.

## When this applies

Satisfy the checklist on every Agent() spawn. A bare-prompt spawn forces the agent to re-discover everything from scratch, which is exactly the rediscovery / wrong-schema / unwanted-mutation set of failures listed above.

### Codebase research — use `codebase-research-agent`

The plugin's `codebase-research-agent` (`agents/codebase-research-agent.md`) is the default for codebase research that would otherwise flood the orchestrator's context — mapping subsystems, tracing flows, locating definitions, summarising behaviour. It inherits the orchestrator's model tier (so on an Opus session the research runs Opus, where the built-in `Explore` subagent would have been pinned to Haiku 4.5) and as a plugin-defined custom agent it sidesteps [anthropics/claude-code#38928](https://github.com/anthropics/claude-code/issues/38928) (MCP-overflow → `0 tool uses` on hosts with many MCP servers).

Call via the runtime-degradation ladder at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (prefixed `geniro-claude-plugin:codebase-research-agent` → bare → general-purpose-with-body) and OMIT `model=` so the orchestrator's session tier propagates. Pre-inline the slots from the agent's Input Contract (3 required: `RESEARCH_QUESTION` / `DELIVERABLE_SHAPE` / `OUTPUT_PATH`; 3 optional: `SCOPE_HINT` / `PRE_INLINED_CONTEXT` / `THOROUGHNESS`). `OUTPUT_PATH` convention: `.geniro/planning/<task-slug>/.research-out.md` (default) OR `.geniro/planning/<task-slug>/.research-<facet>.md` (when running multiple facets in parallel — `/geniro:plan` Phase 1 pattern). See `${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md` for the full contract and worked `DELIVERABLE_SHAPE` examples.

Concrete call shape (step 1 of the spawn-agent ladder; substitute slot values):

```
Agent(subagent_type="geniro-claude-plugin:codebase-research-agent",
      description="<5-10 word task summary>",
      prompt="""
RESEARCH_QUESTION: <complete-sentence question>

DELIVERABLE_SHAPE: <pinned output shape — ordered call chain / definition+caller table / module map / etc.>

SCOPE_HINT: <path globs or module names; omit when scanning whole repo>

PRE_INLINED_CONTEXT:
<file excerpts the orchestrator already read; omit if none>

OUTPUT_PATH: <absolute path under .geniro/planning/<task-slug>/.research-out.md>

THOROUGHNESS: <quick | medium | very thorough; default medium>
""")
```

Do NOT spawn the built-in `Explore` subagent from plugin skills — `codebase-research-agent` covers the same use case at orchestrator tier without the upstream-bug exposure. `/geniro:implement` Phase 1 keeps its dedicated `codebase-explorer-agent` (implementation-specific — takes a `spec.md`, produces REUSE/EXTEND/NO-ANALOGUE inventory); other phases use `codebase-research-agent`.

## Required pre-inlined context

Include all six fields in every Agent() prompt — a missing field is the gap that produces the rediscovery, wrong-schema, or unwanted-mutation failure described in §Why this exists.

**(1) Task scope.** Exactly what the agent must produce — single deliverable, no expansion. Phrase as "Produce <X>" not "Investigate <Y>". Scope-creep prevention: if the orchestrator would accept two different deliverables from the same prompt, the scope is under-specified. Cross-reference `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` for in-agent scope guards.

**(2) Acceptance criteria.** Explicit pass/fail signal in 1-3 bullets. The agent uses these to self-check before reporting completion; the orchestrator uses them to validate the agent's output. Examples: "Output table has exactly 3 columns: file, line, severity" / "Every finding has an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`".

**(3) Relevant file paths with content.** Orchestrator reads files in advance and pastes the content into the prompt. Agents do NOT discover via Glob — discovery duplicates work the orchestrator already did. Paste the verbatim content under a `## Pre-Inlined Files` section with path headers; do not summarize.

**(4) Prohibited tools list.** When the agent must NOT touch certain surfaces, declare it explicitly via `disallowedTools: [<list>]` AND restate the constraint inside the prompt body (belt-and-suspenders, since degraded `general-purpose` calls per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` lose the tool allowlist enforcement). Common patterns:
- reviewer-agent: `disallowedTools: ["Edit", "Write", "NotebookEdit"]` — read-only by contract.
- adversarial-tester-agent: `disallowedTools: ["Edit", "Write", "NotebookEdit"]` outside test files — mutation allowed only on test paths via the spawn prompt's file allowlist.
- `/geniro:investigate` research spawns (general-purpose): `disallowedTools: ["Edit", "Write"]` — research is read-only.
- `/geniro:setup` Phase 4 verification spawn (general-purpose): `disallowedTools: ["Edit", "Write"]` — verification is read-only.

**(5) Output schema.** The exact format the agent's response must match. Examples: a Markdown table with named headers, a JSON block matching a stated schema, or finding objects matching the per-finding line schema in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-tagging.md`. If the orchestrator cannot parse the agent's output, re-spawning is wasted work — pin the schema upfront. Include a one-example block showing the literal shape.

**(6) Model tier.** For plugin-defined agents (reviewer-agent / adversarial-tester-agent / codebase-research-agent / codebase-explorer-agent / knowledge-retrieval-agent / test-runner-agent) OMIT `model=` so they inherit the orchestrator's session tier per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Pass `model=` explicitly ONLY for general-purpose spawns where the tier IS the deliverable contract (e.g. `/geniro:setup` Phase 4 verification = sonnet, ui-preview = haiku), and for user-authored custom reviewers that declared `model:` in their frontmatter. The tier choice is part of the spawn contract; document it at the spawn site.

## Forbidden patterns

- **Bare "investigate X" prompts** with no scope, no acceptance criteria, and no pre-inlined files. The orchestrator's session has the context; the agent does not. A bare investigation prompt forces the agent to re-discover everything from scratch — slow, lossy, and prone to scope drift.
- **"Read CLAUDE.md and figure it out."** Pre-inline the relevant CLAUDE.md excerpts directly into the prompt. CLAUDE.md is too large to load as a whole into the subagent's context, and the agent cannot tell which section is relevant to its task without your filtering. Quote the specific lines that matter; cite the file path so the agent can re-read if needed.
- **"Continue from where the last agent left off."** Every agent starts fresh — there is no shared scratch-space, no carried-over reasoning, no implicit task queue. Pass state explicitly via the within-skill state file (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`) or via pre-inlined content in the prompt body. "Continue" without a state-file path or pre-inlined content is a guaranteed re-do.
- **Implicit deliverable shape ("write up your findings").** Without an output schema, "findings" can be a paragraph, a table, a JSON blob, or a stack trace. Pin the shape.
- **Orchestrator-only file paths.** If you reference `<task-dir>/plan.md` without the resolved absolute path, the agent's `pwd` may differ — your relative path is meaningless to it. Always pass absolute paths.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The agent will figure out the missing context — Sonnet is smart enough." | The orchestrator's job is to construct context; agents aren't telepathic. Smart-enough fills gaps with plausible guesses, which is exactly the failure mode the checklist exists to prevent. The agent's plausible guess about your scope is not your scope. |
| "Adding all this context bloats the prompt — I'll trim to keep token cost down." | Context is cheaper than wrong output. A 4k-token complete prompt that produces a usable deliverable beats a 1k-token bare prompt that requires a re-spawn (or worse, ships the wrong thing). Budget the prompt for completeness. |
| "The acceptance criteria duplicate the task scope — pick one." | Scope is what to produce; criteria is how to verify. They serve different purposes — scope drives the agent's work, criteria drives the orchestrator's accept/reject decision. Both required. |
| "I'll skip the disallowedTools field — the agent has good judgment." | The agent's good judgment is unaudited. The disallowedTools list is the only enforcement layer between the agent and the file system in interactive mode; in degraded mode (general-purpose fallback) you lose even that, and the in-prompt restatement is the only remaining guard. Belt + suspenders. |
| "Pre-inlining files is for slow agents — fast agents can re-Glob." | Re-Globbing is non-deterministic (different agents see different snapshots) and re-discovers files the orchestrator already validated. Pre-inlining is the parallelism multiplier — the orchestrator does discovery once, every agent benefits. |
| "I'll pin a `model=` on every spawn so tier is always explicit." | Plugin-defined agents declare `model: inherit` and the spawn site OMITs `model=` — the runtime arg defeats the user's session-level tier choice (and `model="inherit"` fails input validation). Pass `model=` explicitly only for general-purpose spawns where tier is the safety contract (verification = sonnet, ui-preview = haiku) and for custom reviewers that declared `model:` in frontmatter. |
| "Built-in `Explore` is the standard codebase-search agent in Claude Code — I'll use it instead of spawning a plugin agent." | `Explore` is pinned to Haiku 4.5 regardless of the orchestrator's tier — on an Opus session, evidence gathering for the orchestrator's reasoning would run on a substantially weaker model. The plugin's `codebase-research-agent` declares `model: inherit` so research runs at the tier the user picked at session start. `Explore` is also exposed to the upstream MCP-overflow bug ([#38928](https://github.com/anthropics/claude-code/issues/38928)). `codebase-research-agent` is the default for every plugin skill's codebase research; do not spawn `Explore`. |

## Definition of Done

A spawn site correctly applies the checklist when:

- [ ] Task scope is a single explicit deliverable, phrased "Produce <X>".
- [ ] Acceptance criteria are 1-3 explicit pass/fail bullets.
- [ ] Every relevant file is pre-inlined (full content) with absolute path; no implicit Glob expected.
- [ ] disallowedTools is set when the agent's contract is read-only; the constraint is also restated in-prompt.
- [ ] Output schema is pinned with a one-example block showing the literal shape.
- [ ] Model tier follows `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`: plugin-defined agents OMIT `model=` (inherit orchestrator tier); `model=` is passed explicitly only for general-purpose spawns where tier is the contract and for custom reviewers that declared `model:` in frontmatter.
- [ ] The spawn obeys `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` runtime-degradation rule (prefixed `geniro-claude-plugin:<agent>` first, then bare `<agent>` on "not found", then general-purpose with body-prepended on second "not found"; cache the resolved rung for the session).
