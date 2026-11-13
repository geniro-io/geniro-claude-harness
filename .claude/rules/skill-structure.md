---
paths:
  - "skills/**/*.md"
  - "agents/**/*.md"
  - ".claude/skills/**/*.md"
---

# Skill & agent authoring — file structure

Mechanical structure rules for every skill / agent / reference file. Companions: `.claude/rules/skill-authoring.md` (what never ships), `.claude/rules/skill-prose.md` (voice and prose).

## File-size limits

**Measure a file in words, not lines.** Words per line vary several-fold with how much of a body is tables and fenced blocks, so the two rankings disagree — and a line count invites the wrong fix, since tightening tables sheds lines while raising density.

| File class | Front-load budget | Whole-file guideline | On overflow |
|---|---|---|---|
| `skills/<slug>/SKILL.md` body (after frontmatter) | ~3,000 words | ~5,000 words | Load-bearing content stays inside the front-load budget (`skill-prose.md` §Rule placement); apply the branch test (`skill-prose.md` §Token budget awareness) and move what some runs skip to a sibling `*-reference.md`. |
| Reference file (`*-reference.md`) | n/a | none | Split by phase / concern. Add a Contents block past ~1,200 words (§Reference graph). |
| Agent file (`agents/*.md`) | whole file | ~2,500 words | Tighten or cut in place. An `agents/*.md` body is injected whole, so moving its content out adds a Read and saves nothing — and a skipped rule is silently gone rather than merely late. Move only content some runs need and others don't. |

The ~3,000-word front-load budget approximates the compaction re-attach boundary (`skill-prose.md` §Rule placement), which is measured in characters because characters-per-word swings several-fold with table density. **Sprawl** is a file simply too long, every line live and unique: attention thins across the excess, and every extra line is one more to keep relevant. The cure is the branch test — disclose reference behind pointers, and split by branch or sequence so each path carries only what it needs. The whole-file numbers are guidelines; never trim load-bearing content to hit a number.

## Reference graph

- **Depth ≤ 1 hop from SKILL.md to reference / helper.** SKILL.md may link to `*-reference.md` or to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/*.md`. Those targets may not link back into another skill body for runtime instructions — cross-skill coordination lives in `_shared/`. **Inside `_shared/`, peers cross-link freely**: it is a flat namespace whose helpers navigate among themselves, and the 1-hop ceiling constrains the SKILL → reference edge only. Claude does partial reads on transitively-discovered files, so chains past ~3 hops to a leaf degrade — avoid those.
- **TOC required** for any file over ~1,200 words **that is Read at runtime** — SKILL.md bodies, `*-reference.md`, `_shared/*.md`. Place a 5-15 line "Contents" block right after the H1 so partial-read previews see the full scope. `agents/*.md` are exempt: injected in full, a TOC only adds tokens to every spawn.
- **Single source of truth.** Pseudo-code blocks, slot tables, and schema definitions live in exactly one file. Cross-reference the source; never inline a copy.
- **A must-have target behind a weakly worded pointer is a variance bug:** sharpen the wording first, and inline the material only if sharpening fails.
- **One exemption — the turn-boundary rule** is inlined verbatim in every pipeline `SKILL.md`, and the lint's cross-file duplication warning is expected to name it: across 20 measured `/geniro:implement` runs, `_shared/loop-invariants.md` was read 0 times and `gate-rendering.md` once. Keep the copies in step, and re-measure that the target is read before collapsing any of them back to a citation.

### Reference classes

Reach for the highest-fidelity form the content admits — a reference expressed as code communicates more reliably than a description of the same thing.

| Class | Use for | Example in this repo |
|---|---|---|
| **Rubric** | Taste and standards a subagent applies — "what does a good X look like". Written as criteria a verifier evaluates one at a time, not as prose advice. Pair with a spawned verifier rather than orchestrator self-assessment. | `skills/_shared/review-criteria/*.md` |
| **Executable spec** | An acceptance criterion a command can decide. Prefer a `verify:` line, a failing test, or a schema over a sentence describing the condition. | `skills/_shared/spec-template.md` §9 `verify:` lines |
| **Exemplar** | "Write it like this" — pass the actual file rather than describing its conventions. | `/geniro:implement` Phase 1 exemplar files |
| **Prose reference** | Procedure, contracts, and rationale none of the above expresses. The default, not the only option. | most of `_shared/` |

When a section of prose is really a rubric or an executable check, convert it rather than polishing it.

## Design the interface, not the instructions

Where a contract's *shape* can carry a rule, prefer that to prose stating the rule. A closed enum, a typed field, a required slot (auditability, not depth — `skill-prose.md` §What adding instructions buys), or a tool allowlist communicates usage at the point of use and cannot drift from its documentation, because it is the documentation.

- **Enumerate instead of demonstrating.** Listing a field's legal values (`confirmed` / `clarified` / `refuted` / `unverified`) teaches usage without a worked example, and without constraining the model to the one case the example showed.
- **Name the field for what it does.** A name implying a behavior the field lacks costs more than it saves: every consumer then needs a sentence undoing the implication, and those sentences are what drift.
- **Let the tool surface state the boundary where the surface actually is one.** A plugin-defined agent's own `tools:` frontmatter withholds a tool outright, so it expresses read-only discipline structurally — the Agent tool itself takes no `tools=` or `disallowedTools=` argument, so a spawn cannot restrict a generic subagent this way. A skill's `allowed-tools` withholds nothing either (it only pre-approves tools, and an unlisted tool stays callable), so a skill's read-only rule is prose, and citing `allowed-tools` as enforcement states a guarantee the field never made. Keep prose for what no surface expresses — a `Bash`-issued `git push` is not covered by withholding `Edit`.
- **Return the value instead of asking the caller to remember it.** A helper that echoes its own result needs no rule telling callers to echo it.

When you find yourself writing a second sentence to clarify how a field should be used, check whether renaming the field or closing its value set removes the need for both.

## Frontmatter hygiene

`skills/<slug>/SKILL.md` required fields:

```yaml
---
name: <slug>                       # bare slug — Claude Code prefixes the plugin name (`geniro`)
description: "Use when ..."        # third-person, trigger + optional "Skip for ...", <=250 chars, no XML
context: main                      # or fork (for subagent-isolation skills)
model: inherit                     # always inherit (agents too); the cost class is set at the spawn site — ${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md §Cost classes
allowed-tools: [Read, Write, ...]  # explicit allowlist
argument-hint: "[shape | empty]"   # one-line cue
---
```

All six fields are required; `tests/authoring/lint-skills.sh` (check 1b) fails a SKILL.md missing one. The single exception is `/geniro:actions`, which declares no `allowed-tools` — the field only pre-approves tools and never restricts them, and an action's own steps decide which tools a run needs.

Description rules — every description loads into every session's skill listing, so each word is paid on every turn:
1. **Third person.** Good: "Processes Excel files." Bad: "I can help you" / "You can use this."
2. **≤250 characters, "Use when …" opener, optional "Skip for …" tail.** One trigger per branch; cut identity and process summary the body already carries.
3. **No reserved words** (`anthropic`, `claude`) in `name:`.
4. **No XML tags** anywhere in the description.
5. **Invocation.** Pick model-invocation only when the agent must reach the skill on its own, or another skill must. If it only ever fires by hand, set `disable-model-invocation: true` and pay no context load. A skill another skill hands off to stays model-invoked.

### `maxTurns` on agent frontmatter

Every `agents/*.md` declares `maxTurns:` explicitly. Interactive Claude Code treats it as advisory, but the Agent SDK, `claude-code-action`, and cloud runners default to **10 turns** when it is unset — an uncapped agent hits `Reached maximum number of turns (10)` on its first reasoning workload there.

Set the cap comfortably above the workload estimate, never at it: the last turns are the emit step, so a cap sized to the estimate truncates exactly there — partial output and a corrupted handoff rather than a visible failure. Don't over-correct either; agents chasing a goal routinely run past a cap they were told to self-monitor, so the cap is the mechanism, not a hint. Typical values land in the 30-100 range, tight for mechanical agents and generous for reasoning ones. Past ~150, audit the agent's procedure for scope creep before raising it further.

## Section ordering (SKILL.md body)

1. H1 title — matches `name:` semantically.
2. One-sentence role statement ("You are an autonomous executor."). No multi-paragraph intro.
3. Phases overview (numbered, 1-2 sentences each). Mention parallel-spawn batches if applicable.
4. State machine (text diagram or table) — if the skill has non-trivial state.
5. Loop invariants — numbered, each one sentence + one-clause justification.
6. Anti-rationalization — table (see size cap below).
7. Budgets / quality gates — table.
8. ACI per-phase tool surface — table.
9. Memory I/O — short references to `_shared` helpers.
10. Per-phase sections (`## PHASE 1`, ...) — short Steps lists. Inline only the workflow narrative; push templates and pseudo-code to a reference. End each phase on a completion criterion that tells done from not-done and, where coverage matters, is exhaustive ("every kept finding rendered", not "render the findings"). A vague bound invites premature completion: the visible later steps pull the run toward finishing, and the criterion's clarity is the resistance — sharpen the criterion first; hiding later steps helps only across a real context boundary (a hand-off or a subagent dispatch), never an inline call. The Definition-of-Done checklist is the canonical form.
11. Modifier handling — table.
12. Task execution entry / state recovery.
13. REFERENCE — bulleted list of `${CLAUDE_PLUGIN_ROOT}/...` paths.

Sections 1-9 are the spine — what the model checks every turn and what has to survive a summary — so they belong inside the ~3,000-word front-load budget (`skill-prose.md` §Rule placement carries the mechanism, and the split when they alone approach it).

## Cross-skill references

| What you mean | Write this | Don't write this |
|---|---|---|
| Reference a sibling skill | `/geniro:plan` | `skills/plan/SKILL.md:319` |
| Reference a phase | `/geniro:plan Phase 5` | `plan-loop.md:319-322` |
| Reference a sub-step | content-anchored: "the implement Phase 3 F→P invariant" | "step at line 350" |
| Reference a shared helper | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<name>.md` | bare filename without root |
| Reference an agent contract | `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md` §Output Format — open the agent and cite the heading it carries | line-numbered ref |

Line numbers decay within the same edit; section numbers and content anchors survive.

## Anti-rationalization table sizing

Each row is `| reasoning the model might generate | why that reasoning is wrong + what to do instead |`.

- **≤ 15 rows per skill.** Past 15 the table itself becomes hard to read. Adding row #16 means auditing the existing rows — at least one is defending against a failure mode that is no longer live.
- **Each right-hand cell carries reasoning**, not bare caps. It explains *why* the reasoning is wrong, citing an invariant, a documented failure mode, or a real incident.

## Pre-commit verification

1. **Run `bash tests/authoring/lint-skills.sh`** — it hard-fails on SKILL.md frontmatter that would not load, dangling `${CLAUDE_PLUGIN_ROOT}` references and unknown spawn names, and names the last section that survives compaction — **then `scripts/word-delta.sh <base>`** for the pass's word budget.
2. **Re-check the edit against §Reference graph** (depth, Contents block, no pseudo-code in both SKILL.md and its reference) **and §Frontmatter hygiene** (description form and length).
