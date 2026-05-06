# Spawn Agent — Runtime Degradation Rule

Canonical rule for invoking the plugin's custom agents (`reviewer-agent`, `relevance-filter-agent`, `adversarial-tester-agent`, `refactor-agent`, `architect-agent`, `skeptic-agent`, `knowledge-retrieval-agent`, `backend-agent`, `frontend-agent`). Referenced from every skill that spawns one.

## The problem

The plugin defines 9 custom subagents in `${CLAUDE_PLUGIN_ROOT}/agents/*.md`. Whether they're registered as invokable `subagent_type` values depends on the runtime:

| Runtime | Plugin `agents/` registered? | Bare-name `subagent_type="reviewer-agent"` resolves? |
|---|---|---|
| Interactive Claude Code (desktop) with plugin marketplace-installed | Yes | Yes |
| `/geniro:vendor`-ed project (agents copied to `.claude/agents/`) | Yes (project-scope) | Yes |
| Claude Code SDK / harness / cloud runners | **No** ([SDK init reports `plugins`+`slash_commands`, not agents](https://code.claude.com/docs/en/agent-sdk/plugins)) | **No** — hard error |

When the agent is not registered, the call fails with: `Agent type 'X' not found. Available agents: claude-code-guide, Explore, general-purpose, Plan, statusline-setup`. There is **no silent fallback**. Skills that don't handle this break in harness/SDK.

## The rule

**Every Agent() spawn site for a custom plugin agent uses the runtime-detect-and-degrade pattern below.**

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **Attempt the bare-name call as written.** Example: `Agent(subagent_type="reviewer-agent", model="sonnet", prompt="...")`.

2. **If — and only if — the call returns the error `Agent type '<name>' not found. Available agents: ...`**, re-attempt as:

   ```
   Agent(
     subagent_type="general-purpose",
     model="<same-model-as-original>",
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file with the Read tool, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. Pass the same `model=` the original call requested. Pass the same `description=` you would have used.

3. **Do not pre-emptively skip the bare-name attempt.** In interactive plugin mode the bare name resolves to the real subagent — which has its own context, tool allowlist, and (in some versions) cleaner isolation. Only fall through on the explicit "not found" error. Other errors (rate limits, tool failures inside the agent) are NOT triggers for the fallback.

4. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "Agent type not found", ALL N are degraded — fall back the entire batch in the next response. Do not mix bare-name and degraded calls in the same batch; plugin registration is fixed at session init (per the SDK init behavior cited above) and does not change mid-session.

## Why bare names, not `<plugin>:<agent>` prefix

Plugin namespacing (`geniro-claude-plugin:reviewer-agent`) appears in `/agents` typeahead and in the `claude --agent` CLI flag, but is **not the form used for programmatic `Task()`/`Agent()` invocation from inside another skill**. Production frameworks confirm: GSD's workflow files explicitly use bare names (`Task(subagent_type="gsd-executor", ...)`) and instruct against fallback to `general-purpose`. The bare-name form is correct for skill→agent calls. See [issue #19276](https://github.com/anthropics/claude-code/issues/19276) (closed not-planned — Anthropic declined to add prefixed-name lookup for `Task()`).

## Worked example

Original (in `skills/review/SKILL.md` Phase 2):
```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Degraded form (auto-applied if "Agent type 'reviewer-agent' not found"):
```
Agent(subagent_type="general-purpose", model="sonnet", prompt="""
<<body of ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md, frontmatter stripped>>

---

DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

The resulting agent runs the same review logic; what's lost in degraded mode is the `tools:` allowlist enforcement (the general-purpose agent has the full tool surface — be explicit in the prompt about not editing files for read-only agents like reviewers and skeptics).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "The bare-name call failed once already this session — I should still retry it on the next spawn just to be sure" | Plugin registration is fixed at session init and does not change mid-session. Cache the "not found" inference for the rest of the session and degrade everywhere downstream; do not re-attempt the bare name. The cache does NOT carry across sessions — re-attempt at the next session's first spawn. |
| "I'll prefix as `geniro-claude-plugin:reviewer-agent` to make it more findable" | Programmatic `Task()`/`Agent()` invocation does not accept the prefix form. GSD and production frameworks use bare names. The prefix is for UI typeahead and CLI flags only. |
| "The agent body is long — I'll summarize it before inlining" | The agent's system prompt is the contract. Summarizing changes the contract. Inline the body verbatim (frontmatter stripped). |
| "Read-only agents like reviewer-agent shouldn't run as general-purpose because they could now Edit files" | Correct hazard, wrong mitigation. The mitigation is an explicit instruction inside the inlined prompt — most agent files already say "Do not Edit/Write/Bash apart from read-only commands." If yours doesn't, add it before falling back. |
| "If the bare-name fails, I'll just give up and run the work in my own context" | That defeats the parallelism/isolation purpose of the spawn. Always degrade to general-purpose; do not collapse the work to the orchestrator. The exception is single-agent spawns where the orchestrator was going to wait synchronously anyway — in that case, inline is fine. |
