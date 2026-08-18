# Spawn agent — runtime degradation rule

## Contents

- §The problem — registration name varies by runtime
- §The rule — the prefixed → bare → general-purpose ladder
- §Empty-result fallback — when a spawn returns 0 tokens
- §Why the entry rung is host-dependent — ordering rationale
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
| Cursor, or any other non-Claude-Code plugin host | Yes, under bare YAML name (`cursor/agents/*.md`) | **Yes** | **No** — `geniro:` is Claude Code's plugin namespace and no other host has one |

When the agent is not registered under the form you try, there is **no silent fallback** — the spawn never starts. Skills that don't handle this break in one or more runtimes. Hosts word the failure differently and you must recognize the class, not one string: Claude Code returns `Agent type 'X' not found. Available agents: …`; Cursor surfaces a subagent that reports `Couldn't start` with no error text at all.

Where the host does list what it accepts, that list is the ground truth — when in doubt, read it. In interactive-plugin mode you will see `geniro:reviewer-agent` listed (not bare `reviewer-agent`); in vendored and Cursor installs you will see bare names; in SDK/harness you will see neither.

## The rule

**Every Agent() spawn site for a custom plugin agent uses the runtime-detect-and-degrade ladder below.** A skill's instructions name a custom plugin agent by its identity — written bare (`reviewer-agent`) or already prefixed (`geniro:reviewer-agent`), both appear across skill files — but neither spelling is a literal call string. The orchestrator reads it as "the agent named X" and applies the ladder at call time regardless of which form the skill wrote. Skill files are NOT rewritten when this ladder changes.

**`model=` is omitted at every rung, with two exceptions.** The agent's frontmatter `model:` governs (rationale + carve-outs: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`), and at rung 3 `general-purpose`'s own inherit-from-parent default does the same job. The first exception is a user-authored custom reviewer that declares an explicit tier in `.geniro/instructions/review-extra/<slug>.md` frontmatter — pass `model={user-declared-value}` verbatim, at whichever rung resolves. The second is a non-judgment site (`model-tiering.md` §The rule, categories 2-4) — it passes a tier, `sonnet` by default or the cheaper one that file's §Sizing a non-judgment spawn picked for this workload, unchanged across every rung. A tier anywhere else defeats the user's session-level `/model` choice.

**Where the ladder starts is a host question, decided before the first call.** `geniro:` is the namespace Claude Code prefixes onto a marketplace-installed plugin's agents; no other host has a plugin namespace, so under any other host rung 1 is not a form that might work — it is a form that provably cannot, and trying it burns the whole batch. Under Claude Code, enter at rung 1. Under any other host — Cursor, or any runtime where you had to resolve `${CLAUDE_PLUGIN_ROOT}` yourself per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/runtime-portability.md` — **skip rung 1 and enter at rung 2**. This is the one part of the ladder you decide rather than discover; everything below is still driven by what the calls return.

When a skill's instructions say to `Agent(subagent_type="<plugin-agent>", ...)`:

1. **Claude Code only — prefixed form.** Call `Agent(subagent_type="geniro:<agent>", description="...", prompt="...")`. This is the happy path on interactive Claude Code with the plugin marketplace-installed, and it is skipped entirely on every other host.

2. **On any failure to start the agent at rung 1** — `Agent type 'geniro:<agent>' not found`, `Couldn't start`, or whatever else this host says when a subagent never begins — re-attempt with the bare name: `Agent(subagent_type="<agent>", ...)`. This is the form registered in vendored / harness installs (agents copied to `.claude/agents/geniro-*.md` with their YAML `name:` unchanged) and in Cursor (`cursor/agents/*.md`), and it is where non-Claude-Code hosts enter. Judge by whether the agent started, not by whether the wording matched a string in this file.

3. **If the bare-name attempt also fails to start**, re-attempt as:

   ```
   Agent(
     subagent_type="general-purpose",
     prompt=<<contents of ${CLAUDE_PLUGIN_ROOT}/agents/<agent-name>.md, body only — strip YAML frontmatter>> + "\n\n---\n\n" + <original prompt>
   )
   ```

   Read the agent file with the Read tool, drop the leading `---\n…\n---\n` frontmatter block, and prepend the remaining body to your task prompt with a `---` separator. If the file has no leading `---` line, treat the whole file as the body and prepend verbatim. Pass the same `description=` you would have used.

4. **Cache the resolution for the rest of the session.** Plugin registration is fixed at session init and does not change mid-session. Once you've established whether step 1 or step 2 worked (or both failed), every subsequent plugin-agent spawn in the same session uses that resolved form directly — do NOT re-walk the ladder. The cache does NOT carry across sessions; re-walk at the next session's first spawn.

5. **Parallel-spawn sites:** if a skill spawns N agents in one response and any one of them returns "not found" at the same ladder rung, ALL N are degraded to the same next rung — fall back the entire batch in the next response. Do not mix ladder rungs in the same batch.

## Empty-result fallback (spawn returned 0 tokens)

The ladder above resolves "agent type not found" — an agent-*registration* failure. A separate, independent failure is a spawn that resolves and runs but returns **empty** (`Done (0 tool uses · 0 tokens · 1s)` — no usable output). The common cause is a model-availability mismatch: a spawn that hardcodes a tier different from the orchestrator's (e.g. `model="haiku"`) fails immediately when the orchestrator session runs a context-window beta the target tier doesn't support — a 1M-context Opus/Sonnet session cannot spawn a Haiku child, because Haiku 4.5 has no 1M-context variant and rejects the inherited context configuration. The orchestrator sees an error it may misread as "prompt too long" even when the prompt is tiny; an empty return on a *small* prompt is the tell that this is a tier/beta mismatch, not a real size problem.

When any spawn returns empty (zero output tokens / no parseable result):

1. **Retry once with `model=` omitted** so the subagent inherits the orchestrator's tier and beta configuration — the inherited child runs under the same context window as the parent, so the mismatch cannot recur. This is the canonical default anyway per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`; the hardcoded tier is the thing that broke.
2. **If the inherit retry is also empty**, the runtime cannot spawn this work — author the output inline in the orchestrator's own context using the same prompt contract. Do not loop a third spawn. For a parallel batch, only the empty agent(s) degrade this way; the agents that returned output are unaffected.

Caller skills that pass a tier (the narrow carve-outs in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md`) apply this fallback — the tier is a speed/cost preference, never a hard requirement, so it degrades to inherit (then inline) before failing the phase. A `haiku` pick that comes back empty sets the session's floor at `sonnet`: no later site re-tries it.

## Why the entry rung is host-dependent

Under Claude Code the two forms are genuinely ambiguous — marketplace-installed registers `geniro:reviewer-agent`, a vendored install registers bare `reviewer-agent`, and you cannot tell which from inside the session, so the ladder guesses prefixed-first because that is the more common install and a wrong guess costs one round-trip. Under any other host there is nothing to guess: the namespace that would produce the prefix does not exist, so rung 1 fails 100% of the time.

That asymmetry is why the entry rung is decided rather than discovered. The cost of a doomed rung 1 is not one round-trip either — §Parallel-spawn sites degrades the *whole batch* together, so an 11-reviewer fan-out under Cursor spends 11 dead spawns and a second full turn before any real work starts.

## Worked example

Rungs 1 and 2 are the skill's own `Agent(...)` call with `subagent_type` swapped for that rung's form (`geniro:reviewer-agent`, then bare `reviewer-agent`); nothing else about the call changes. Rung 3 is the only shape worth rendering — the `general-purpose` prompt is the agent body, a `---` separator, then the original prompt unchanged:

```
<<body of ${CLAUDE_PLUGIN_ROOT}/agents/reviewer-agent.md, frontmatter stripped>>
---
DIMENSION: bugs …          ← the original prompt, verbatim
```

Step 3 loses the `tools:` allowlist enforcement (general-purpose has the full tool surface — be explicit in the prompt about not editing files for read-only agents like reviewers and skeptics).

## Anti-rationalization

| Your reasoning | Why it's wrong |
|---|---|
| "I'll try bare names first because that's what the skill file has written" | Skill files write agent identity as bare or already-prefixed notation interchangeably — neither is a literal call string. Which rung you enter at is set by the host, not by the spelling the skill used: prefixed under Claude Code, bare everywhere else. |
| "I'll skip the prefixed attempt because we're definitely in vendored mode" | Marketplace-vs-vendored is the case you genuinely cannot tell apart from inside a Claude Code session — walk the ladder there and cache the result. What you CAN tell is which host you are on, and that is the only thing rung 0 asks you to decide. |
| "I'm on Cursor, but I'll still try the prefixed form first — the ladder will catch it" | The ladder catches it at the price of the entire batch: a `/geniro-review` fan-out spends 11 dead spawns and a wasted turn on a form the host has no namespace to resolve. A rung that fails 100% of the time on this host is not a first attempt, it is a known-dead call. |
| "I'll prefix as `<some-other-plugin>:<agent>` — the prefix is the plugin name" | The prefix is the *installed* plugin namespace. For this plugin it is exactly `geniro` (matches `.claude-plugin/plugin.json`'s name field). Do not invent prefixes. |
| "The first attempt failed — I should retry the same form just to be sure" | Plugin registration is fixed at session init. The cache does NOT carry across sessions, but it absolutely holds within a session; re-attempting wastes a call. Re-walk at next session's first spawn. |
| "The agent body is long — I'll summarize it before inlining at step 3" | The agent's system prompt is the contract. Summarizing changes the contract. Inline the body verbatim (frontmatter stripped). |
| "Read-only agents like reviewer-agent shouldn't run as general-purpose at step 3 because they could now Edit files" | Correct hazard, wrong mitigation. The mitigation is an explicit instruction inside the inlined prompt — most agent files already say "Do not Edit/Write/Bash apart from read-only commands." If yours doesn't, add it before falling back. |
| "If steps 1 and 2 both fail, I'll just give up and run the work in my own context" | That defeats the parallelism/isolation purpose of the spawn. Always degrade to general-purpose at step 3. The exception is single-agent spawns where the orchestrator was going to wait synchronously anyway — in that case, inline is fine. |
| "I'll pass `model='sonnet'` (or any other tier) explicitly at the spawn site to be safe" | OMIT `model=` at every rung of a judgment-grade spawn — a tier there defeats the user's session-level `/model` choice, unless the user made that choice explicitly. A tier is passed only where a carve-out in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md` §The rule names the site (categories 2-4, where `sonnet` is the ceiling and §Sizing picks below it), or where the run carries `--subagent-model` (same file, §`--subagent-model`) — the user's own election, not the plugin's. The ladder is unchanged either way: the tier travels with the call, only `subagent_type` swaps per rung. |
| "The spawn came back empty saying the prompt was too long — I'll shorten the prompt and retry." | An empty return (`0 tokens`) with a "too long" message on a *small* prompt is a tier/context-beta mismatch, not a real size problem — shortening won't help (the retry comes back just as empty). Apply the empty-result fallback: retry once with `model=` omitted (inherit the parent's context window), then author the output inline. |
