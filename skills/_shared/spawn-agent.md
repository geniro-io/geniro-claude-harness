# Spawn Agent — Runtime Degradation Rule

Canonical rule for invoking the plugin's custom agents (`reviewer-agent`, `adversarial-tester-agent`). Referenced from every skill that spawns one.

## The problem

The plugin defines several custom subagents in `${CLAUDE_PLUGIN_ROOT}/agents/*.md`. Whether they are registered as invokable `subagent_type` values — and under what name — depends on the runtime:

| Runtime | Agents registered? | Resolvable as `<agent>`? | Resolvable as `geniro-claude-plugin:<agent>`? |
|---|---|---|---|
| Interactive Claude Code with plugin marketplace-installed | Yes, under plugin namespace | **No** | **Yes** |
| Vendored / harness install (agents copied to `.claude/agents/geniro-*.md`, YAML `name:` unchanged) | Yes, under bare YAML name | **Yes** | No |
| Claude Code SDK / harness / cloud runners | **No** ([SDK init reports `plugins`+`slash_commands`, not agents](https://code.claude.com/docs/en/agent-sdk/plugins)) | No — hard error | No — hard error |

When the agent is not registered under the form you try, the call fails with: `Agent type 'X' not found. Available agents: …`. There is **no silent fallback**. Skills that don't handle this break in one or more runtimes.

The "Available agents" list in that error is the ground truth for what works — when in doubt, read it. In interactive-plugin mode you will see `geniro-claude-plugin:reviewer-agent` listed (not bare `reviewer-agent`); in vendored mode you will see bare names; in SDK/harness you will see neither.

## The rule

**Every Agent() spawn site for a custom plugin agent uses the runtime-detect-and-degrade ladder below.** Skills are written with bare names in their instructions (e.g. `Agent(subagent_type="reviewer-agent", …)`); the orchestrator interprets the bare name as "the agent named X" and applies the ladder at call time. Skill files are NOT rewritten when this ladder changes.

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **First attempt — prefixed form.** Call `Agent(subagent_type="geniro-claude-plugin:<agent>", description="...", prompt="...")`. **OMIT the `model=` argument** — plugin agents declare `model: inherit` in frontmatter; omitting the runtime arg lets the Agent tool resolve the orchestrator's tier. Pass `model=` only if the caller has an explicit non-inherit override (rare — user-authored custom reviewers with declared tier; see `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`). This step is the happy path on interactive Claude Code with the plugin marketplace-installed.

2. **If — and only if — the call returns `Agent type 'geniro-claude-plugin:<agent>' not found. Available agents: ...`**, re-attempt with the bare name: `Agent(subagent_type="<agent>", ...)` (same `model=` policy — OMIT by default). This is the form registered in vendored / harness installs (where agents are copied to `.claude/agents/geniro-*.md` with their YAML `name:` field unchanged).

3. **If the bare-name attempt also returns "not found"**, re-attempt as:

   ```
   Agent(
     subagent_type="general-purpose",
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file with the Read tool, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. OMIT `model=` so the `general-purpose` fallback inherits the orchestrator's tier; pass an explicit `model=` only when the caller specified one for the original call. Pass the same `description=` you would have used.

4. **Cache the resolution for the rest of the session.** Plugin registration is fixed at session init and does not change mid-session. Once you've established whether step 1 or step 2 worked (or both failed), every subsequent plugin-agent spawn in the same session uses that resolved form directly — do NOT re-walk the ladder. The cache does NOT carry across sessions; re-walk at the next session's first spawn.

5. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "not found" at the same ladder rung, ALL N are degraded to the same next rung — fall back the entire batch in the next response. Do not mix ladder rungs in the same batch.

## Empty-result fallback (spawn returned 0 tokens)

The ladder above resolves "agent type not found" — an agent-*registration* failure. A separate, independent failure is a spawn that resolves and runs but returns **empty** (`Done (0 tool uses · 0 tokens · 1s)` — no usable output). The common cause is a model-availability mismatch: a spawn that hardcodes a tier different from the orchestrator's (e.g. `model="haiku"`) fails immediately when the orchestrator session runs a context-window beta the target tier doesn't support — a 1M-context Opus/Sonnet session cannot spawn a Haiku child, because Haiku 4.5 has no 1M-context variant and rejects the inherited context configuration. The orchestrator sees an error it may misread as "prompt too long" even when the prompt is tiny; an empty return on a *small* prompt is the tell that this is a tier/beta mismatch, not a real size problem.

When any spawn returns empty (zero output tokens / no parseable result):

1. **Retry once with `model=` omitted** so the subagent inherits the orchestrator's tier and beta configuration — the inherited child runs under the same context window as the parent, so the mismatch cannot recur. This is the canonical default anyway per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`; the hardcoded tier is the thing that broke.
2. **If the inherit retry is also empty**, the runtime cannot spawn this work — author the output inline in the orchestrator's own context using the same prompt contract. Do not loop a third spawn. For a parallel batch, only the empty agent(s) degrade this way; the agents that returned output are unaffected.

Caller skills that hardcode a tier (the two sanctioned sites in `model-tiering.md`) apply this fallback — the hardcode is a speed/cost preference, never a hard requirement, so it degrades to inherit (then inline) before failing the phase.

## Why prefixed-first

Plugin namespacing (`geniro-claude-plugin:reviewer-agent`) is the form Claude Code exposes when the plugin is marketplace-installed. The "Available agents" error list shows agents under their prefixed names in this runtime — evidence that this is the registered form, not just a UI typeahead artifact. Empirical confirmation: spawn sites that attempted bare names first hit a wasted "not found" error before succeeding under the prefixed form.

Treating the prefixed form as UI-only and bare names as the programmatic happy path is wrong in interactive-plugin mode and produces one wasted spawn error per call. Other frameworks that register agents under bare names in their target runtime use bare-first internally — that does not generalize to this plugin's registration scheme.

Note: [claude-code issue #19276](https://github.com/anthropics/claude-code/issues/19276) (closed not-planned) is sometimes cited as evidence that prefixed lookup doesn't work for `Task()`. The closure was about a specific lookup-precedence proposal; the prefixed form does in fact resolve in `Agent()` calls today, as the "Available agents" error list directly shows.

## Worked example

Skill instruction (in `skills/review/SKILL.md` Phase 2):
```
Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Step 1 — prefixed (interactive plugin-marketplace mode, happy path):
```
Agent(subagent_type="geniro-claude-plugin:reviewer-agent", prompt="""
DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

Step 2 — bare (vendored / harness mode, after step 1 returns "not found"):
```
Agent(subagent_type="reviewer-agent", prompt="""
DIMENSION: bugs
…
""")
```

Step 3 — general-purpose with body inlined (SDK/harness, after step 2 also returns "not found"):
```
Agent(subagent_type="general-purpose", prompt="""
<<body of ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md, frontmatter stripped>>

---

DIMENSION: bugs
CRITERIA: [content of bugs-criteria.md]
…
""")
```

No `model=` is passed at any step — the Agent tool resolves the tier via the `model: inherit` directive in the plugin agent's frontmatter (or, at step 3, via `general-purpose`'s own inherit-from-parent default). User-authored custom reviewers that declare an explicit tier in `.geniro/instructions/review-extra/<slug>.md` frontmatter are the one exception: pass `model={user-declared-value}` verbatim at every ladder rung.

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
| "I'll pass `model='sonnet'` (or any other tier) explicitly at the spawn site to be safe" | Plugin agents declare `model: inherit` in frontmatter; OMITTING `model=` at the spawn site is the canonical inherit pattern per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`. Passing a hardcoded tier defeats the user's session-level `/model` choice. The only spawn sites that pass `model=` are user-authored custom reviewers whose own frontmatter declared an explicit tier — honor the user's declaration, not your own pessimism about runtime behavior. |
| "The spawn came back empty saying the prompt was too long — I'll shorten the prompt and retry." | An empty return (`0 tokens`) with a "too long" message on a *small* prompt is a tier/context-beta mismatch, not a real size problem — shortening won't help (the retry comes back just as empty). Apply the empty-result fallback: retry once with `model=` omitted (inherit the parent's context window), then author the output inline. |
