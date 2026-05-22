# Spawn Agent — Runtime Degradation Rule

Canonical rule for invoking the plugin's custom agents (`reviewer-agent`, `adversarial-tester-agent`). Referenced from every skill that spawns one.

## The problem

The plugin defines 2 custom subagents in `${CLAUDE_PLUGIN_ROOT}/agents/*.md`. Whether they are registered as invokable `subagent_type` values — and under what name — depends on the runtime:

| Runtime | Agents registered? | Resolvable as `<agent>`? | Resolvable as `geniro-claude-plugin:<agent>`? |
|---|---|---|---|
| Interactive Claude Code with plugin marketplace-installed | Yes, under plugin namespace | **No** | **Yes** |
| `/geniro:vendor`-ed project (agents copied to `.claude/agents/geniro-*.md`, YAML `name:` unchanged) | Yes, under bare YAML name | **Yes** | No |
| Claude Code SDK / harness / cloud runners | **No** ([SDK init reports `plugins`+`slash_commands`, not agents](https://code.claude.com/docs/en/agent-sdk/plugins)) | No — hard error | No — hard error |

When the agent is not registered under the form you try, the call fails with: `Agent type 'X' not found. Available agents: …`. There is **no silent fallback**. Skills that don't handle this break in one or more runtimes.

The "Available agents" list in that error is the ground truth for what works — when in doubt, read it. In interactive-plugin mode you will see `geniro-claude-plugin:reviewer-agent` listed (not bare `reviewer-agent`); in vendored mode you will see bare names; in SDK/harness you will see neither.

## The rule

**Every Agent() spawn site for a custom plugin agent uses the runtime-detect-and-degrade ladder below.** Skills are written with bare names in their instructions (e.g. `Agent(subagent_type="reviewer-agent", …)`); the orchestrator interprets the bare name as "the agent named X" and applies the ladder at call time. Skill files are NOT rewritten when this ladder changes.

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **First attempt — prefixed form.** Call `Agent(subagent_type="geniro-claude-plugin:<agent>", model="<requested-model>", description="...", prompt="...")`. This is the form registered by interactive Claude Code when the plugin is marketplace-installed and is the happy path on developer workstations.

2. **If — and only if — the call returns `Agent type 'geniro-claude-plugin:<agent>' not found. Available agents: ...`**, re-attempt with the bare name: `Agent(subagent_type="<agent>", ...)`. This is the form registered in `/geniro:vendor`-ed projects (where agents are copied to `.claude/agents/geniro-*.md` with their YAML `name:` field unchanged).

3. **If the bare-name attempt also returns "not found"**, re-attempt as:

   ```
   Agent(
     subagent_type="general-purpose",
     model="<same-model-as-original>",
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file with the Read tool, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. Pass the same `model=` the original call requested. Pass the same `description=` you would have used.

4. **Cache the resolution for the rest of the session.** Plugin registration is fixed at session init and does not change mid-session. Once you've established whether step 1 or step 2 worked (or both failed), every subsequent plugin-agent spawn in the same session uses that resolved form directly — do NOT re-walk the ladder. The cache does NOT carry across sessions; re-walk at the next session's first spawn.

5. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "not found" at the same ladder rung, ALL N are degraded to the same next rung — fall back the entire batch in the next response. Do not mix ladder rungs in the same batch.

## Why prefixed-first

Plugin namespacing (`geniro-claude-plugin:reviewer-agent`) is the form Claude Code exposes when the plugin is marketplace-installed. The "Available agents" error list shows agents under their prefixed names in this runtime — evidence that this is the registered form, not just a UI typeahead artifact. Empirical confirmation: spawn sites that attempted bare names first hit a wasted "not found" error before succeeding under the prefixed form (ManifestOS, 2026-05-13).

A previous version of this rule asserted that the prefixed form was UI-only and that bare names were the programmatic happy path. That was wrong in interactive-plugin mode and produced one wasted spawn error per call. GSD's framework uses bare names internally because GSD's agents register under bare names in their target runtime — that does not generalize to this plugin's registration scheme.

Note: [claude-code issue #19276](https://github.com/anthropics/claude-code/issues/19276) (closed not-planned) is sometimes cited as evidence that prefixed lookup doesn't work for `Task()`. The closure was about a specific lookup-precedence proposal; the prefixed form does in fact resolve in `Agent()` calls today, as the "Available agents" error list directly shows.

## Worked example

Skill instruction (in `skills/review/SKILL.md` Phase 2):
```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Step 1 — prefixed (interactive plugin-marketplace mode, happy path):
```
Agent(subagent_type="geniro-claude-plugin:reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Step 2 — bare (vendored-project mode, after step 1 returns "not found"):
```
Agent(subagent_type="reviewer-agent", model="sonnet", prompt="""
DIMENSION: bugs
…
""")
```

Step 3 — general-purpose with body inlined (SDK/harness, after step 2 also returns "not found"):
```
Agent(subagent_type="general-purpose", model="sonnet", prompt="""
<<body of ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md, frontmatter stripped>>

---

DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Step 3 loses the `tools:` allowlist enforcement (general-purpose has the full tool surface — be explicit in the prompt about not editing files for read-only agents like reviewers and skeptics).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll try bare names first because that's what the skill files have written" | Skills are written with bare names as the canonical "agent identity" notation. The orchestrator interprets that identity and applies the ladder — skills are not literal call strings. Bare-first wastes a `not found` round-trip in the happy path. |
| "I'll skip the prefixed attempt because we're definitely in vendored mode" | You cannot reliably tell at spawn time. Walk the ladder once at first spawn and cache the result for the session. The cost of one extra `not found` per session is negligible; the cost of guessing wrong is N wasted spawns. |
| "I'll prefix as `<some-other-plugin>:<agent>` — the prefix is the plugin name" | The prefix is the *installed* plugin namespace. For this plugin it is exactly `geniro-claude-plugin` (matches `.claude-plugin/plugin.json`'s name field). Do not invent prefixes. |
| "The first attempt failed — I should retry the same form just to be sure" | Plugin registration is fixed at session init. The cache does NOT carry across sessions, but it absolutely holds within a session; re-attempting wastes a call. Re-walk at next session's first spawn. |
| "The agent body is long — I'll summarize it before inlining at step 3" | The agent's system prompt is the contract. Summarizing changes the contract. Inline the body verbatim (frontmatter stripped). |
| "Read-only agents like reviewer-agent shouldn't run as general-purpose at step 3 because they could now Edit files" | Correct hazard, wrong mitigation. The mitigation is an explicit instruction inside the inlined prompt — most agent files already say "Do not Edit/Write/Bash apart from read-only commands." If yours doesn't, add it before falling back. |
| "If steps 1 and 2 both fail, I'll just give up and run the work in my own context" | That defeats the parallelism/isolation purpose of the spawn. Always degrade to general-purpose at step 3. The exception is single-agent spawns where the orchestrator was going to wait synchronously anyway — in that case, inline is fine. |
