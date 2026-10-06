# Spawn agent — runtime degradation rule

## Contents

- §The problem — registration name varies by runtime
- §The rule — the prefixed → bare → general-purpose ladder
- §Empty-result fallback — when a spawn returns 0 tokens
- §Why the entry rung is read from the list — ordering rationale
- §Worked example
- §Anti-rationalization

Canonical rule for invoking the plugin's custom agents — the agents under `${CLAUDE_PLUGIN_ROOT}/agents/`. Referenced from every skill that spawns one.

## The problem

The plugin defines several custom subagents in `${CLAUDE_PLUGIN_ROOT}/agents/*.md`. Whether they are registered as invokable `subagent_type` values — and under what name — depends on the runtime:

| Runtime | Agents registered? | Resolvable as `<agent>`? | Resolvable as `geniro:<agent>`? |
|---|---|---|---|
| Interactive Claude Code with plugin marketplace-installed | Yes, under plugin namespace | **No** | **Yes** |
| Vendored / harness install (agents copied to `.claude/agents/geniro-*.md`, YAML `name:` unchanged) | Yes, under bare YAML name | **Yes** | No |
| Claude Code SDK / harness / cloud runners | **No** ([SDK init reports `plugins`+`slash_commands`, not agents](https://code.claude.com/docs/en/agent-sdk/plugins)) | No — hard error | No — hard error |
| Cursor IDE and `cursor-agent -p`, after `scripts/install-cursor.sh` | Yes, under bare YAML name (`cursor/agents/*.md`, linked into `~/.cursor/agents/`) | **Yes** | **No** — `geniro:` is Claude Code's plugin namespace and no other host has one |
| `cursor-agent` driven over ACP (Geniro, editor integrations) | **No** — its Task tool lists only Cursor's built-in agents and the workspace's own (`.cursor/agents/`, `.claude/agents/`), never `~/.cursor/agents/` | No — rejected | No — rejected |

When the agent is not registered under the form you try, there is **no silent fallback** — the spawn never starts. Skills that don't handle this break in one or more runtimes. Hosts word the failure differently and you must recognize the class, not one string: Claude Code returns `Agent type 'X' not found. Available agents: …`; Cursor over ACP returns `Invalid enum value. Expected 'generalPurpose' | …, received 'X'`; the Cursor IDE surfaces a subagent that reports `Couldn't start` with no error text at all.

The list of agent types the host accepts is the ground truth, and §The rule reads the entry rung from it. Marketplace-installed Claude Code lists `geniro:reviewer-agent` (not bare `reviewer-agent`); a vendored install, the Cursor IDE, and `cursor-agent -p` list bare names; the SDK/harness and Cursor over ACP list neither.

## The rule

**Every spawn site for a custom plugin agent uses the runtime-detect-and-degrade ladder below.** A skill's instructions name a custom plugin agent by its identity — written bare (`reviewer-agent`) or already prefixed (`geniro:reviewer-agent`), both appear across skill files — but neither spelling is a literal call string. The orchestrator reads it as "the agent named X" and applies the ladder at call time regardless of which form the skill wrote. Skill files are NOT rewritten when this ladder changes.

**`model=` is omitted at every rung, with the exceptions `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §The rule and §`--subagent-model` name** (a user-declared custom-reviewer tier, the non-judgment categories, a run carrying `--subagent-model`), which pass their tier unchanged across every rung. The agent's frontmatter `model:` governs otherwise, and at rung 3 the host general-purpose type's inherit-from-parent default does the same job; a tier anywhere else defeats the user's session-level `/model` choice.

**Where the ladder starts is read before the first call, from the agent types the host lists.** Claude Code shows them in its available-agents listing; Cursor's Task tool carries them as the `subagent_type` enum in its own schema. Enter at the first rung whose form that list carries — `geniro:<agent>` listed → rung 1, bare `<agent>` listed → rung 2, neither → rung 3 directly. A form the list does not carry is not a first attempt: it is a known-dead call, and trying it burns the whole batch. Only where no list is visible, decide from the host: `CLAUDECODE` in the environment → rung 1; absent → rung 2. This is the one part of the ladder you decide rather than discover; everything below is still driven by what the calls return.

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **Claude Code only — prefixed form.** Call `Agent(subagent_type="geniro:<agent>", description="...", prompt="...")`. This is the happy path on interactive Claude Code with the plugin marketplace-installed, and it is skipped entirely on every other host.

2. **Bare name — the entry when the list carries it, or after rung 1 fails to start** (`Agent type 'geniro:<agent>' not found`, `Couldn't start`, or whatever else this host says when a subagent never begins): `Agent(subagent_type="<agent>", ...)`. This is the form registered in vendored / harness installs (agents copied to `.claude/agents/geniro-*.md` with their YAML `name:` unchanged) and in the Cursor IDE and `cursor-agent -p` after the profile install (`cursor/agents/*.md`). Judge by whether the agent started, not by whether the wording matched a string in this file.

3. **The host's own general-purpose agent type — the entry when the list carries neither form, or after the bare name fails to start.** `general-purpose` on Claude Code, `generalPurpose` on Cursor (its Task tool accepts a closed set of agent types built at session start; a name outside that set is rejected, not routed to a fallback):

   ```
   Agent(
     subagent_type=<host's general-purpose type>,
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. Pass the same `description=` you would have used.

4. **Cache the resolution for the rest of the session.** Plugin registration is fixed at session init and does not change mid-session. Once you've established whether step 1 or step 2 worked (or both failed), every subsequent plugin-agent spawn in the same session uses that resolved form directly — do NOT re-walk the ladder. The cache does NOT carry across sessions; re-walk at the next session's first spawn.

5. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "not found" at the same ladder rung, ALL N are degraded to the same next rung — fall back the entire batch in the next response. Do not mix ladder rungs in the same batch.

## Empty-result fallback (spawn returned 0 tokens)

The ladder above resolves "agent type not found" — an agent-*registration* failure. A separate, independent failure is a spawn that resolves and runs but returns **empty** (`Done (0 tool uses · 0 tokens · 1s)` — no usable output). The common cause is a model-availability mismatch: a spawn that hardcodes a tier different from the orchestrator's (e.g. `model="haiku"`) fails immediately when the orchestrator session runs a context-window beta the target tier doesn't support — a 1M-context Opus/Sonnet session cannot spawn a Haiku child, because Haiku 4.5 has no 1M-context variant and rejects the inherited context configuration. The orchestrator sees an error it may misread as "prompt too long" even when the prompt is tiny; an empty return on a *small* prompt is the tell that this is a tier/beta mismatch, not a real size problem.

When any spawn returns empty (zero output tokens / no parseable result):

1. **Retry once with `model=` omitted** so the subagent inherits the orchestrator's tier and beta configuration — the inherited child runs under the same context window as the parent, so the mismatch cannot recur. This is the canonical default anyway per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`; the hardcoded tier is the thing that broke.
2. **If the inherit retry is also empty**, the runtime cannot spawn this work — author the output inline in the orchestrator's own context using the same prompt contract. Do not loop a third spawn. For a parallel batch, only the empty agent(s) degrade this way; the agents that returned output are unaffected.

Caller skills that pass a tier (the narrow carve-outs in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`) apply this fallback — the tier is a speed/cost preference, never a hard requirement, so it degrades to inherit (then inline) before failing the phase. A `haiku` pick that comes back empty sets the session's floor at `sonnet`: no later site re-tries it.

## Why the entry rung is read from the list

The registered form follows the install, not the host: Claude Code registers `geniro:reviewer-agent` when marketplace-installed and bare `reviewer-agent` when vendored; Cursor registers the bare names in its IDE and in `cursor-agent -p`, but none when the same binary is driven over ACP. Neither the host nor the skill text tells these apart, and the list the host publishes already does. A wrong entry costs more than one round-trip — §Parallel-spawn sites degrades the *whole batch* together, so an 11-reviewer fan-out opened at a form the host does not list spends 11 dead spawns and a second full turn before any real work starts.

## Worked example

Rungs 1 and 2 are the skill's own `Agent(...)` call with `subagent_type` swapped for that rung's form (`geniro:reviewer-agent`, then bare `reviewer-agent`); nothing else about the call changes. Rung 3 is the only shape worth rendering — the host's general-purpose prompt is the agent body, a `---` separator, then the original prompt unchanged:

```
<<body of ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md, frontmatter stripped>>
---
DIMENSION: bugs …          ← the original prompt, verbatim
```

Step 3 loses the `tools:` allowlist enforcement (general-purpose has the full tool surface — be explicit in the prompt about not editing files for read-only agents like reviewers and finding-verifiers).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll try bare names first because that's what the skill file has written" | Skill files write agent identity as bare or already-prefixed notation interchangeably — neither is a literal call string. Which rung you enter at is set by the host's agent list, not by the spelling the skill used. |
| "I can't tell marketplace from vendored, so I'll walk the ladder from the top" | The host's agent list tells you: it shows `geniro:<agent>` or bare `<agent>`, never both. Walking from the top under the other install spends a batch to learn what the list already showed. |
| "I'm on Cursor, so the bare name is the entry — the ladder will catch it if not" | Only where the profile's agents load — the IDE and `cursor-agent -p`. Driven over ACP, the same binary's enum carries no plugin agent, and every bare-name spawn in the batch is rejected. Read the enum: neither form listed means rung 3 on the first call. |
| "I'll prefix as `<some-other-plugin>:<agent>` — the prefix is the plugin name" | The prefix is the *installed* plugin namespace. For this plugin it is exactly `geniro` (matches `.claude-plugin/plugin.json`'s name field). Do not invent prefixes. |
| "The first attempt failed — I should retry the same form just to be sure" | Plugin registration is fixed at session init. The cache does NOT carry across sessions, but it absolutely holds within a session; re-attempting wastes a call. Re-walk at next session's first spawn. |
| "The agent body is long — I'll summarize it before inlining at step 3" | The agent's system prompt is the contract. Summarizing changes the contract. Inline the body verbatim (frontmatter stripped). |
| "Read-only agents like reviewer-agent shouldn't run as general-purpose at step 3 because they could now edit files" | Correct hazard, wrong mitigation. The mitigation is an explicit instruction inside the inlined prompt — most agent files already say "Do not Edit/Write/Bash apart from read-only commands." If yours doesn't, add it before falling back. |
| "If steps 1 and 2 both fail, I'll just give up and run the work in my own context" | That defeats the parallelism/isolation purpose of the spawn. Always degrade to general-purpose at step 3. |
| "I'll pass `model='sonnet'` (or any other tier) explicitly at the spawn site to be safe" | OMIT `model=` at every rung of a judgment-grade spawn; a tier is passed only where `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` names the site. The tier travels with the call, only `subagent_type` swaps per rung. |
| "The spawn came back empty saying the prompt was too long — I'll shorten the prompt and retry." | An empty return (`0 tokens`) with a "too long" message on a *small* prompt is a tier/context-beta mismatch, not a real size problem — shortening won't help (the retry comes back just as empty). Apply the empty-result fallback: retry once with `model=` omitted (inherit the parent's context window), then author the output inline. |
