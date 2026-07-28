---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
  - ".claude/skills/**/*.md"
---

# Skill & agent authoring — file structure

Positive-guidance companion to `.claude/rules/skill-authoring.md`. While that file lists what NEVER ships, this file lists the mechanical structure rules every skill / agent / reference file should follow when authored or edited.

Sources for every number below: Anthropic [Skill best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [Claude Code skill docs](https://code.claude.com/docs/en/skills) (the compaction re-attach budget), and [Cursor rules docs](https://cursor.com/docs/rules).

## File-size limits

**Measure a file in words, not lines.** A skill body here runs anywhere from 9 to 21 words per line depending on how much of it is tables and fenced blocks, so a line count says almost nothing about what the file costs: `setup` is 571 lines and 5,267 words, `resolve` is 142 lines and 3,044 words — lines rank them backwards. A line count also invites the wrong fix, since a file can shed 150 lines by tightening tables and come out denser than it started.

| File class | Front-load budget | Whole-file guideline | What to do on overflow |
|---|---|---|---|
| `skills/<slug>/SKILL.md` body (after frontmatter) | ~3,000 words | ~5,000 words | Everything load-bearing belongs inside the front-load budget — that is what survives compaction (§Rule placement, and `skill-prose.md` §Rule placement for the mechanism). Past the whole-file guideline, move templates / pseudo-code / contracts to a sibling `*-reference.md` that some runs genuinely skip. |
| Reference file (`*-reference.md`) | n/a | none | Split by phase / concern. Add a Contents block past ~1,200 words (§Reference graph). |
| Agent file (`agents/*.md`) | whole file | ~2,500 words | Tighten or cut in place. Moving content to `agents/<name>-reference.md` is not a saving: an agent body is injected whole as the subagent's system prompt, so the move converts free prompt tokens into the same tokens plus a Read the agent may skip — and a rule it skips is silently gone rather than merely late. Move only content some runs need and others don't. |

The ~3,000-word front-load budget is the one figure with a mechanism behind it: Claude Code re-attaches only the first 5,000 tokens of each skill after compaction, which is roughly 3,000 words of table-dense markdown. The whole-file numbers are guidelines. An oversize file is a signal to check what is load-bearing and where it sits, not a defect in itself — never trim load-bearing content to hit a number.

## Reference graph

- **Depth ≤ 1 hop from SKILL.md to reference / helper.** SKILL.md may link to `*-reference.md` or to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/*.md` helpers. Those targets may NOT link back into another skill body (`skills/<other>/SKILL.md` or its references) for runtime instructions — cross-skill coordination lives in `_shared/`, never in a foreign skill's reference file. **Inside `_shared/`, peers may cross-link freely** for topological context (e.g., `state-tier-spec.md` ↔ `atomic-state-write.md` ↔ `validate-state-file.md` reference each other because they describe one cohesive subsystem). The 1-hop ceiling constrains the SKILL → reference edge; `_shared/` is a flat namespace whose helpers navigate among themselves. Claude still does partial reads on transitively-discovered files, so chains longer than ~3 hops from SKILL.md to leaf degrade — avoid those.
- **TOC required** for any file over ~1,200 words **that is Read at runtime** — SKILL.md bodies, `*-reference.md`, `_shared/*.md`. Place a 5-15 line "Contents" or "Sections" block right after the H1 so partial-read previews still see the full scope. This does not apply to `agents/*.md`: an agent body is injected in full as the subagent's system prompt, so there is no partial-read preview for a TOC to widen, and the bullets cost their tokens on every spawn.
- **Single-source-of-truth.** Pseudo-code blocks, slot tables, schema definitions live in exactly ONE file. Cross-references point at the source; never inline a copy.

## Frontmatter hygiene

`skills/<slug>/SKILL.md` frontmatter required fields:

```yaml
---
name: <slug>                       # bare slug — Claude Code prefixes it with the plugin name (`geniro`)
description: "Use when ..."        # third-person, what + when, slightly pushy, ≤1024 chars, no XML
context: main                      # or fork (for subagent-isolation skills)
model: inherit                     # default; per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md
allowed-tools: [Read, Write, ...]  # explicit allowlist
argument-hint: "[shape | empty]"   # one-line cue
---
```

Description rules:
1. **Third-person, never first/second.** Good: "Processes Excel files." Bad: "I can help you" / "You can use this."
2. **What + when.** Don't describe behavior without saying when to invoke.
3. **Slightly pushy.** Anthropic explicitly recommends combatting under-triggering. Lead with `Use when <trigger phrase>.`
4. **No reserved words** (`anthropic`, `claude`) in the `name:` field.
5. **No XML tags** anywhere in description.

### `maxTurns` on agent frontmatter

Every `agents/*.md` declares `maxTurns:` explicitly. Interactive Claude Code treats the value as advisory documentation, but the Agent SDK, `claude-code-action`, and cloud runners default to **10 turns** when the field is unset — an agent shipped without a cap hits `Reached maximum number of turns (10)` on its first reasoning workload there. Declaring it explicitly is what makes the agent portable across both runtimes.

Pick the value by counting the workload, then adding slack:

```
floor    = sum(Reads + Greps + Bash invocations + reasoning turns + emit step)
slack    = 50-60% (retry / refinement iterations)
maxTurns = ceil(floor × 1.5) + optional safety bump
```

Set the cap at floor + 50%, never at floor. The last turns of a run are the emit step (write findings, produce output); a cap sized to the floor truncates exactly there, yielding partial output and a corrupted downstream handoff rather than a visible failure. Do not compensate in the other direction either — agents chasing a goal routinely run past a cap they were told to self-monitor, so the cap is the mechanism, not a hint.

Typical caps land in the 30-100 range: tight for mechanical agents (a test runner), generous for reasoning agents (a reviewer, an adversarial tester). Document the rationale inline near the frontmatter when the number is non-obvious. A value above ~150 reads as "the author gave up bounding scope" — audit the agent's procedure for scope creep before raising it further.

## Section ordering (SKILL.md body)

Predictable section order helps the orchestrator parse and helps human readers skim. Use this top-to-bottom:

1. H1 title — matches `name:` semantically.
2. One-sentence role statement ("You are an autonomous executor."). No multi-paragraph intro.
3. Phases overview (numbered list, 1-2 sentences per phase). Mention parallel-spawn batches if applicable.
4. State machine (text diagram or table) — if the skill has non-trivial state.
5. Loop invariants — numbered, each one sentence + one-clause justification.
6. Budgets / quality gates — table.
7. Memory I/O — short references to `_shared` helpers.
8. ACI per-phase tool surface — table.
9. Per-phase sections (`## PHASE 1`, `## PHASE 2`, ...) — each contains short Steps list. Inline ONLY the workflow narrative; push templates + pseudo-code to reference.md. End each phase on a completion criterion the model can check — done distinguishable from not-done — and, where coverage matters, exhaustive ("every kept finding rendered", not "render the findings"); a vague bound is what lets a phase end prematurely. The Definition-of-Done checklist is the canonical form.
10. Modifier handling — table.
11. Task execution entry / state recovery.
12. Anti-rationalization — table (see size cap below).
13. REFERENCE — bulleted list of `${CLAUDE_PLUGIN_ROOT}/...` paths.

Sections 1-7 land in the top third (high-attention zone per [Liu et al. 2024](https://aclanthology.org/2024.tacl-1.9/)). Section 12 anchors the bottom third (also high-attention). The middle holds detail — that's fine since detail is referenced by name from invariants and steps.

## Cross-skill references

| What you mean | Write this | Don't write this |
|---|---|---|
| Reference a sibling skill | `/geniro:plan` | `skills/plan/SKILL.md:319` |
| Reference a phase | `/geniro:plan Phase 5` | `plan-loop.md:319-322` |
| Reference a sub-step | content-anchored: "the Phase 4.3 F→P invariant" | "step at line 350" |
| Reference a shared helper | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<name>.md` | bare filename without root |
| Reference an agent contract | `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md` §Output Format | line-numbered ref |

Line numbers decay within the same edit; section numbers and content anchors survive.

## Anti-rationalization table sizing

The anti-rationalization table is the runtime guardrail against future drift. Each row is `| reasoning the model might generate | why that reasoning is wrong + what to do instead |`.

Constraints:
- **≤ 15 rows per skill.** Past 15, the table itself becomes hard to read. If you find yourself adding row #16, audit existing rows — at least one is probably dead weight (rule it's defending against is no longer a live failure mode).
- **Each row's right-hand cell carries reasoning**, not just `NEVER` / `ALWAYS` in caps. Anthropic's [`skill-creator`](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md) flags caps-MUST as a yellow flag — the row should explain *why* the reasoning is wrong (citing an invariant, a documented failure mode, a published Anthropic recommendation, or a real incident).
- **No internal design-doc anchors** in the right-hand cell. The reader has no access to `design/<file>.md §9quinquies` from their own repo.

## Pre-commit verification

Before committing edits to `skills/**/*.md` or `agents/**/*.md`:

1. **Run `bash tests/authoring/lint-skills.sh`.** It mechanizes the checkable rules here — hard-fails on non-Latin text, dangling `${CLAUDE_PLUGIN_ROOT}` file references, and unknown spawn names; warns on word-count targets, anti-rationalization tables over 15 rows, and line-number cross-refs. Read an over-target warning as "check what is load-bearing and where it sits", not as "cut until the number goes away".
2. **Reference depth.** Any file this edit makes a skill cite must not itself pull runtime instructions from another skill's body (§Reference graph).
3. **TOC presence.** A runtime-Read file grown past ~1,200 words has a Contents block near the top. `agents/*.md` are exempt — they are injected, not Read.
4. **No pseudo-code duplication.** A pseudo-code block added to SKILL.md must not also live in the sibling reference file — cite the single source instead.
5. **Frontmatter description** is third-person, "Use when …" form, ≤1024 chars.
