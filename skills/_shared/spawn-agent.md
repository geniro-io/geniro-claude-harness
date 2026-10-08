# Spawn agent — runtime degradation rule

## Contents

- §The problem — registration name varies by runtime
- §The rule — the prefixed → bare → general-purpose ladder
- §Empty-result fallback — when a spawn returns nothing usable
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
| Codex (CLI and desktop app), plugin install | **No** — plugins cannot ship agents; Codex reads custom agents only from `~/.codex/agents/` or `<repo>/.codex/agents/` TOML files, or `[agents.<name>]` in `config.toml` | No — rejected | No — rejected |

When the agent is not registered under the form you try, there is **no silent fallback** — the spawn never starts. Skills that don't handle this break in one or more runtimes. Hosts word the failure differently and you must recognize the class, not one string: Claude Code returns `Agent type 'X' not found. Available agents: …`; Cursor over ACP returns `Invalid enum value. Expected 'generalPurpose' | …, received 'X'`; Codex returns `unknown agent_type 'X'`; the Cursor IDE surfaces a subagent that reports `Couldn't start` with no error text at all.

The list of agent types the host accepts is the ground truth, and §The rule reads the entry rung from it. Marketplace-installed Claude Code lists `geniro:reviewer-agent` (not bare `reviewer-agent`); a vendored install, the Cursor IDE, and `cursor-agent -p` list bare names; the SDK/harness, Cursor over ACP, and Codex list neither.

## The rule

**Every spawn site for a custom plugin agent uses the runtime-detect-and-degrade ladder below.** A skill's instructions name a custom plugin agent by its identity — written bare (`reviewer-agent`) or already prefixed (`geniro:reviewer-agent`), both appear across skill files — but neither spelling is a literal call string. The orchestrator reads it as "the agent named X" and applies the ladder at call time regardless of which form the skill wrote. Skill files are NOT rewritten when this ladder changes.

**A session spawn omits `model=` at every rung; a light spawn passes its class's host spelling from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Runtime resolution unchanged across every rung, or omits it where the class resolves to the session (§Cost classes).** User-declared values come from a custom reviewer's `model:` or the run's `--subagent-model`; §Runtime resolution also covers a value the host cannot spell. Agent frontmatter is always `inherit`, and at rung 3 the host general-purpose type's inherit-from-parent default does the same job; a model passed anywhere else defeats the user's session-level `/model` choice.

**Every plugin-agent spawn and every general-purpose spawn starts from its prompt alone, never from a copy of the orchestrator's conversation.** The plugin's reviewers, verifiers, and research agents are independent checks by design; a subagent that inherits the orchestrator's history inherits its framing and stops being one. Claude Code and Cursor already start a subagent from the prompt. On Codex, pass `fork_turns: "none"` (or leave `fork_context` false on the older tool): the current tool's default (`all`) copies the whole conversation.

**Where the ladder starts is read before the first call, from the agent types the host lists.** Claude Code shows them in its available-agents listing; Cursor's Task tool carries them as the `subagent_type` enum in its own schema; Codex's `spawn_agent` carries them in the `agent_type` description of its schema. Enter at the first rung whose form that list carries — `geniro:<agent>` listed → rung 1, bare `<agent>` listed → rung 2, neither → rung 3 directly. A form the list does not carry is not a first attempt: it is a known-dead call, and trying it burns the whole batch. Only where no list is visible, decide from the host: `CLAUDECODE` in the environment → rung 1; `CODEX_THREAD_ID` in the environment → rung 3 (Codex registers no plugin agents); neither → rung 2. This is the one part of the ladder you decide rather than discover; everything below is still driven by what the calls return.

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **Claude Code only — prefixed form.** Call `Agent(subagent_type="geniro:<agent>", description="...", prompt="...")`. This is the happy path on interactive Claude Code with the plugin marketplace-installed, and it is skipped entirely on every other host.

2. **Bare name — the entry when the list carries it, or after rung 1 fails to start** (`Agent type 'geniro:<agent>' not found`, `Couldn't start`, or whatever else this host says when a subagent never begins): `Agent(subagent_type="<agent>", ...)`. This is the form registered in vendored / harness installs (agents copied to `.claude/agents/geniro-*.md` with their YAML `name:` unchanged) and in the Cursor IDE and `cursor-agent -p` after the profile install (`cursor/agents/*.md`). Judge by whether the agent started, not by whether the wording matched a string in this file.

3. **The host's own general-purpose agent type — the entry when the list carries neither form, or after the bare name fails to start.** `general-purpose` on Claude Code, `default` on Codex (or `agent_type` omitted), `generalPurpose` on Cursor (its Task tool accepts a closed set of agent types built at session start; a name outside that set is rejected, not routed to a fallback):

   ```
   Agent(
     subagent_type=<host's general-purpose type>,
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. Pass the same `description=` you would have used (Codex's current spawn tool takes a unique snake_case `task_name` instead).

4. **Cache the resolution for the rest of the session.** Plugin registration is fixed at session init and does not change mid-session. Once you've established whether step 1 or step 2 worked (or both failed), every subsequent plugin-agent spawn in the same session uses that resolved form directly — do NOT re-walk the ladder. The cache does NOT carry across sessions; re-walk at the next session's first spawn.

5. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "not found" at the same ladder rung, ALL N are degraded to the same next rung — fall back the entire batch in the next response. Do not mix ladder rungs in the same batch. A spawn refused for the host's concurrent-subagent limit is not a registration failure (Codex allows 3 spawned subagents at once by default, 6 on its older tool, and reports "agent thread limit reached"): keep the resolved rung, wait for running spawns to finish (on Codex, `wait_agent` — and on its older tool also `close_agent`, since a finished agent holds its slot until closed), and spawn the remainder in waves until every member of the batch has run. Degrading on a limit refusal costs the fan-out its rung — on Codex, already at rung 3, that means running the agents inline without their isolation — where waves cost only wall-time.

## Empty-result fallback (spawn returned nothing usable)

The ladder above resolves "agent type not found" — an agent-*registration* failure. A separate, independent failure is a spawn that resolves and runs but returns **empty** (`Done (0 tool uses · 0 tokens · 1s)` — zero output). The common cause is a model-availability mismatch: a light spawn passes a model different from the orchestrator's and fails immediately when the orchestrator session runs a context-window beta that model doesn't support — a 1M-context session cannot spawn a child from a family with no 1M-context variant. The orchestrator sees an error it may misread as "prompt too long" even when the prompt is tiny; an empty return on a *small* prompt is the tell that this is a model/beta mismatch, not a real size problem.

`${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Cost classes (Fallbacks) owns the triggers; this section runs the retries for read-only spawns and for a writer whose model the host refused, never for a writer that already started.

When a spawn comes back unusable:

1. **Zero output, or a model the host does not offer or refuses: step up one class, each time it comes back empty:** light (smallest) → light (mid) → session. A session spawn retries once. The session attempt omits `model=`, so the child runs under the same context window as the parent and the mismatch cannot recur. A class that came back empty stays stepped up for the rest of the run: no later site re-tries it.
2. **Malformed or otherwise unusable output: re-spawn once as session.** A light spawn jumps straight to session; a session spawn retries once.
3. **If the session attempt also fails**, the runtime cannot spawn this work. Follow the caller's own error path where it has one (a verifier is marked unverified and kept, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/finding-verification.md` §4.5); only where it has none, author the output inline in the orchestrator's own context using the same prompt contract. Do not loop another spawn. For a parallel batch, only the failed agent(s) degrade this way; the agents that returned output are unaffected.

Every light site applies this fallback — the class is a speed/cost preference, never a hard requirement, so it steps up through the classes before the caller's error path.

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
| "I'll pass a model explicitly at the spawn site to be safe" | A session spawn omits `model=` at every rung; only a light site passes a model, the host spelling of its class from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §Runtime resolution. The model travels with the call, only `subagent_type` swaps per rung. |
| "The spawn came back empty saying the prompt was too long — I'll shorten the prompt and retry." | An empty return (`0 tokens`) with a "too long" message on a *small* prompt is a model/context-beta mismatch, not a real size problem — shortening won't help (the retry comes back just as empty). Apply the empty-result fallback: step up a class until session omits `model=` (inherits the parent's context window), then the caller's own error path, or the output authored inline where it has none. |
