# Context isolation checklist

Co-cited with `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` at every Agent() spawn site. spawn-agent.md handles agent-name resolution + runtime degradation; this file handles prompt richness. Together they ensure subagents never inherit orchestrator session state.

This file is the single source of truth for the pre-inlined-context contract every Agent() spawn must satisfy. Skills cite this file; do NOT inline-paste the checklist.

## Contents

- Why this exists — the three failure modes a bare prompt produces
- When this applies — every Agent() spawn; codebase research uses `codebase-research-agent`
- Required pre-inlined context — the fields every prompt carries
- Reading the load report back — what to check when the agent returns
- Forbidden patterns — prompt shapes that guarantee a re-do
- Anti-rationalization
- Definition of Done

## Why this exists

Subagents do not share memory, working set, or CLAUDE.md context with the orchestrator. An agent spawned with the prompt `"investigate the auth bug"` starts from zero — no knowledge of which files the orchestrator just read, which conventions matter, which tools are off-limits, or what the deliverable shape is. Three observed failure modes when the checklist is skipped:

- The agent re-discovers files via Glob that the orchestrator already had open, doubling latency and burning tokens on rediscovery.
- The agent improvises an output schema (free-form prose) that downstream parsing cannot consume — orchestrator falls back to re-prompting or running the work itself.
- The agent calls Edit/Write when the orchestrator only wanted analysis, mutating the tree in ways the spawn site never anticipated.

Pre-inlining every required field below collapses all three failure modes.

## When this applies

Satisfy the checklist on every Agent() spawn.

### Codebase research — use `codebase-research-agent`

The plugin's `codebase-research-agent` (`${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md`) is the default for codebase research that would otherwise flood the orchestrator's context — mapping subsystems, tracing flows, locating definitions, summarizing behavior. It inherits the orchestrator's model tier (so on an Opus session the research runs Opus, where the built-in `Explore` subagent would have been pinned to Haiku 4.5) and as a plugin-defined custom agent it sidesteps [anthropics/claude-code#38928](https://github.com/anthropics/claude-code/issues/38928) (MCP-overflow → `0 tool uses` on hosts with many MCP servers).

Call via the runtime-degradation ladder at `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` (prefixed `geniro:codebase-research-agent` → bare → general-purpose-with-body) and OMIT `model=` so the orchestrator's session tier propagates. Pre-inline the slots from the agent's Input Contract — always passed: `RESEARCH_QUESTION` / `DELIVERABLE_SHAPE` / `PROJECT SEARCH POLICY` / `OUTPUT_PATH`; passed when they apply: `SCOPE_HINT` / `PRE_INLINED_CONTEXT` / `THOROUGHNESS`. `PROJECT SEARCH POLICY` is always passed by the spawn site yet marked `recommended` in the agent's own contract — the two are consistent: the obligation is on the producer, and the agent fails open (self-loads `global.md`) rather than aborting, so an un-updated spawn site degrades instead of returning a stub report. `OUTPUT_PATH` convention: `.geniro/planning/<task-slug>/.research-out.md` (default) OR `.geniro/planning/<task-slug>/.research-<facet>.md` (when running multiple facets in parallel — `/geniro:plan` Phase 1 pattern). See `${CLAUDE_PLUGIN_ROOT}/agents/codebase-research-agent.md` for the full contract and worked `DELIVERABLE_SHAPE` examples.

Concrete call shape (step 1 of the spawn-agent ladder; substitute slot values):

```
Agent(subagent_type="geniro:codebase-research-agent",
      description="<5-10 word task summary>",
      prompt="""
WORKTREE: <absolute path from `git rev-parse --show-toplevel`>

RESEARCH_QUESTION: <complete-sentence question>

PROJECT SEARCH POLICY: <verbatim global.md rule bullets governing how to search this codebase, or `none declared`>
It governs every lookup you make, not just the first. If it names a tool your runtime defers, load it before deciding you cannot comply.

DELIVERABLE_SHAPE: <pinned output shape — ordered call chain / definition+caller table / module map / etc.>

SCOPE_HINT: <path globs or module names; omit when scanning whole repo>

PRE_INLINED_CONTEXT:
<file excerpts the orchestrator already read; omit if none>

OUTPUT_PATH: <absolute path under .geniro/planning/<task-slug>/.research-out.md>

THOROUGHNESS: <quick | medium | very thorough; default medium>

Anchor: WORKTREE is your root — run every Bash call from it (`cd <WORKTREE> && …`) and resolve every file path under it.
""")
```

Do NOT spawn the built-in `Explore` subagent from plugin skills — `codebase-research-agent` covers the same use case at orchestrator tier without the upstream-bug exposure. `/geniro:implement` Phase 1 keeps its dedicated `codebase-explorer-agent` (implementation-specific — takes a `spec.md`, produces REUSE/EXTEND/NO-ANALOGUE inventory); other phases use `codebase-research-agent`.

## Required pre-inlined context

Include every field below in every Agent() prompt — a missing field is the gap the §Why-this-exists failures come through.

**Task scope.** Exactly what the agent must produce — single deliverable, no expansion. Phrase as "Produce <X>" not "Investigate <Y>". Scope-creep prevention: if the orchestrator would accept two different deliverables from the same prompt, the scope is under-specified. Cross-reference `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scope-anchor.md` for in-agent scope guards.

**Acceptance criteria.** Explicit pass/fail signal in 1-3 bullets. The agent uses these to self-check before reporting completion; the orchestrator uses them to validate the agent's output. Examples: "Output table has exactly 3 columns: file, line, severity" / "Every finding has an Evidence Block per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/evidence-standard.md`".

**Relevant file paths with content.** Orchestrator reads files in advance and pastes the content into the prompt. Agents do NOT discover via Glob — discovery duplicates work the orchestrator already did. Paste the verbatim content under a `## Pre-Inlined Files` section with path headers; do not summarize.

The rule binds on the task inputs the orchestrator discovered — the diff, the changed files, the spec, whatever it went looking for. A fixed plugin-owned reference the agent's own contract already tells it to Read (a `review-criteria/` rubric, `subagent-instruction-load.md`, the confidence rubric) passes as a resolved absolute path instead: nothing was discovered, so nothing is re-discovered, and inlining it would push a multi-thousand-word file through the orchestrator's context purely to hand it to an agent that would have opened it anyway. Resolve the path before passing it — an unresolved `${CLAUDE_PLUGIN_ROOT}` token is not a path the agent can open.

**Prohibited tools list.** When the agent must NOT touch certain surfaces, declare it explicitly via `disallowedTools: [<list>]` AND restate the constraint inside the prompt body (belt-and-suspenders, since degraded `general-purpose` calls per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` lose the tool allowlist enforcement). Common patterns:
- reviewer-agent: `disallowedTools: ["Edit", "Write", "NotebookEdit"]` — read-only by contract.
- adversarial-tester-agent: `disallowedTools: ["Edit", "Write", "NotebookEdit"]` outside test files — mutation allowed only on test paths via the spawn prompt's file allowlist.
- `/geniro:investigate` research spawns (general-purpose): `disallowedTools: ["Edit", "Write"]` — research is read-only.
- `/geniro:setup` Phase 4 verification spawn (general-purpose): `disallowedTools: ["Edit", "Write"]` — verification is read-only.

**Output schema.** The exact format the agent's response must match. Examples: a Markdown table with named headers, a JSON block matching a stated schema, or finding blocks matching the per-finding schema in `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md` §Output Format. If the orchestrator cannot parse the agent's output, re-spawning is wasted work — pin the schema upfront. Include a one-example block showing the literal shape.

**Model tier.** For plugin-defined agents OMIT `model=` — the agent's frontmatter `model:` governs, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Pass `model=` explicitly only where that file's carve-outs name the site: an execution spawn applying an already-made decision (`model="sonnet"`, category 4), a general-purpose spawn where the tier IS the deliverable contract (`/geniro:setup` Phase 4 verification = sonnet), or a user-authored custom reviewer that declared `model:` in its frontmatter. Document the choice at the spawn site.

**Project search policy** — passed by the spawn site whenever the agent will search or read code (the agent itself fails open on absence, so this is a producer obligation, not an agent-side error). A project's `global.md` may govern HOW to search this codebase: a code index to query before plain-text search, a required lookup tool, a directory that is off-limits. The plugin owns no opinion about which tool that is — it is whatever the project declared. Pass the governing rule bullets under a `PROJECT SEARCH POLICY:` slot; when `global.md` declares nothing about searching, write `PROJECT SEARCH POLICY: none declared` so the agent knows the absence is real rather than a dropped slot.

Three properties are load-bearing, and a policy that reaches the agent without them loses to the agent's own default search:

- **Verbatim and whole.** Paraphrase drops the actionable clause first, and a batch that re-types the policy per spawn drifts shorter with each one — pass the same text to every agent in the batch.
- **Positioned with the task, not appended after the constraints.** A policy arriving as a trailing note below the read-only rules reads as a footnote; the agent's own workflow steps outrank it.
- **Scoped to every lookup, not the first.** Say so explicitly. Applying the project's tool once and reverting to the default for the rest of the run is the common failure, not a rare one.

If the policy names a tool, give its exact invocation form. A tool the runtime defers is not in the agent's tool surface until the agent loads it, so a policy naming one reads as unavailable and gets skipped silently — state that the agent should load it before concluding it cannot comply.

This push complements the agent's own pull (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/subagent-instruction-load.md`). Both exist because neither alone holds: the pull is a step an agent can skip, and the push only carries what the orchestrator itself loaded.

## Reading the load report back

The checklist above governs what leaves the spawn site. What the agent then did with it is knowable only from the agent's report, because its narration never crosses back — so a spawn is not complete until its report has been read for a `Context loaded:` line.

The line comes from agents whose own workflow tells them to load something: the reviewer, the two codebase agents, the adversarial tester, the knowledge-retrieval agent, the reflection agent. An agent whose every input is pushed by the spawn prompt — the test runner, the finding verifier — emits no such line, and its absence there is the contract rather than a skip.

The line, its value set, and the consumer's obligations on each are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/skip-visibility.md` §The load report. Two readings are the spawn site's own problem rather than the agent's: `unreadable` on a path this prompt passed means the path was wrong, so correct it and re-spawn that one agent; a report with no such line at all means the agent never ran its load steps, so name that in the run's output instead of consuming the report as if the project's rules had shaped it.

A batch is checked per agent. One reviewer reporting `project-rules=absent` while its siblings report `read` is a dropped load in that spawn, not a project without rules.

## Forbidden patterns

- **Bare "investigate X" prompts** with no scope, no acceptance criteria, and no pre-inlined files. The orchestrator's session has the context; the agent does not. A bare investigation prompt forces the agent to re-discover everything from scratch — slow, lossy, and prone to scope drift.
- **"Read CLAUDE.md and figure it out."** Pre-inline the relevant CLAUDE.md excerpts directly into the prompt. CLAUDE.md is too large to load as a whole into the subagent's context, and the agent cannot tell which section is relevant to its task without your filtering. Quote the specific lines that matter; cite the file path so the agent can re-read if needed.
- **"Continue from where the last agent left off."** Every agent starts fresh — there is no shared scratch-space, no carried-over reasoning, no implicit task queue. Pass state explicitly via the within-skill state file (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md`) or via pre-inlined content in the prompt body. "Continue" without a state-file path or pre-inlined content is a guaranteed re-do.
- **Implicit deliverable shape ("write up your findings").** Without an output schema, "findings" can be a paragraph, a table, a JSON blob, or a stack trace. Pin the shape.
- **The project's search policy as a closing aside** ("Note: the project has an index — prefer it over grep"). A rule that changes which tool the agent reaches for is part of the task, not a sign-off. Placed last it competes with the agent's own workflow steps and loses; abbreviated across a parallel batch it decays into nothing by the final spawn.
- **Orchestrator-only file paths.** If you reference `<task-dir>/plan.md` without the resolved absolute path, the agent's `pwd` may differ — your relative path is meaningless to it. Always pass absolute paths.

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The agent will figure out the missing context — Sonnet is smart enough." | The orchestrator's job is to construct context; agents aren't telepathic. Smart-enough fills gaps with plausible guesses, which is exactly the failure mode the checklist exists to prevent. The agent's plausible guess about your scope is not your scope. |
| "Adding all this context bloats the prompt — I'll trim to keep token cost down." | Context is cheaper than wrong output. A 4k-token complete prompt that produces a usable deliverable beats a 1k-token bare prompt that requires a re-spawn (or worse, ships the wrong thing). Budget the prompt for completeness. |
| "The acceptance criteria duplicate the task scope — pick one." | Scope is what to produce; criteria is how to verify. They serve different purposes — scope drives the agent's work, criteria drives the orchestrator's accept/reject decision. Both required. |
| "I'll skip the disallowedTools field — the agent has good judgment." | The agent's good judgment is unaudited. The disallowedTools list is the only enforcement layer between the agent and the file system in interactive mode; in degraded mode (general-purpose fallback) you lose even that, and the in-prompt restatement is the only remaining guard. Belt + suspenders. |
| "Pre-inlining files is for slow agents — fast agents can re-Glob." | Re-Globbing is non-deterministic (different agents see different snapshots) and re-discovers files the orchestrator already validated. Pre-inlining is the parallelism multiplier — the orchestrator does discovery once, every agent benefits. |
| "I'll pin a `model=` on every spawn so tier is always explicit." | OMIT `model=` for plugin-defined agents — their frontmatter tier governs, and `model="inherit"` at the call site fails input validation outright. Pin only where a carve-out names the site. The rule, its four carve-out categories, and the reasoning: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. |
| "The agent loads `global.md` itself at its Step 0, so pre-inlining the search policy is redundant." | Its Step 0 is one skippable step at the head of a long workflow, and a skip is silent — you cannot tell from the agent's output whether the policy ever reached it. The push costs a few lines of prompt you already have loaded; the pull is the fallback for what you didn't. |
| "Built-in `Explore` is the standard codebase-search agent in Claude Code — I'll use it instead of spawning a plugin agent." | Do not spawn `Explore` from a plugin skill — `codebase-research-agent` is the default for every plugin skill's codebase research, for the two reasons in §Codebase research. |
| "The report came back complete and well-formed, so the agent clearly had the context it needed." | Report completeness is evidence the agent followed its output schema, not that it followed its load steps — an agent that skipped `global.md` returns the same shape, just judged against the plugin's defaults instead of the project's rules. §Reading the load report back is the only check that separates them. |

## Definition of Done

A spawn site correctly applies the checklist when:

- [ ] Every § Required pre-inlined context field is present in the prompt, each satisfying the condition stated there.
- [ ] The spawn obeys the runtime-degradation ladder in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md` and caches the resolved rung for the session.
- [ ] Every report from an agent that declares a `Context loaded:` line was checked for it per §Reading the load report back, and each `unreadable` or missing line was acted on rather than noted.
