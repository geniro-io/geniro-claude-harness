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
| `skills/<slug>/SKILL.md` body (after frontmatter) | ~3,000 words | ~5,000 words | Everything load-bearing belongs inside the front-load budget — that is what survives compaction (`skill-prose.md` §Rule placement). Past the whole-file guideline, move templates / pseudo-code / contracts to a sibling `*-reference.md` that some runs genuinely skip. |
| Reference file (`*-reference.md`) | n/a | none | Split by phase / concern. Add a Contents block past ~1,200 words (§Reference graph). |
| Agent file (`agents/*.md`) | whole file | ~2,500 words | Tighten or cut in place. An agent body is injected whole as the subagent's system prompt, so moving content to `agents/<name>-reference.md` converts free prompt tokens into the same tokens plus a Read the agent may skip — and a skipped rule is silently gone rather than merely late. Move only content some runs need and others don't. |

The ~3,000-word front-load budget is the one figure with a mechanism behind it: Claude Code re-attaches only the first 5,000 tokens of each skill after compaction, roughly 3,000 words of table-dense markdown. The whole-file numbers are guidelines. An oversize file is a signal to check what is load-bearing and where it sits, not a defect — never trim load-bearing content to hit a number.

The lint therefore measures **growth, not absolute size**: `tests/authoring/skill-size-baseline.txt` records the size each skill was last accepted at, and the warning fires only when a file exceeds its own record (or an unrecorded file exceeds the guideline). Accept a load-bearing growth with `bash tests/authoring/lint-skills.sh --accept <path>`, which rewrites only the row you name; the blanket `--update-baseline` silently accepts every neighbour that grew, so save it for a repo-wide pass where every row is meant. Accept after a trim too — `tests/authoring/lint-size-ratchet.sh` fails on a row recorded above its file's real size, since a stale-high row re-permits that much unreviewed growth.

## Reference graph

- **Depth ≤ 1 hop from SKILL.md to reference / helper.** SKILL.md may link to `*-reference.md` or to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/*.md`. Those targets may not link back into another skill body for runtime instructions — cross-skill coordination lives in `_shared/`. **Inside `_shared/`, peers cross-link freely**: it is a flat namespace whose helpers navigate among themselves, and the 1-hop ceiling constrains the SKILL → reference edge only. Claude does partial reads on transitively-discovered files, so chains past ~3 hops to a leaf degrade — avoid those.
- **TOC required** for any file over ~1,200 words **that is Read at runtime** — SKILL.md bodies, `*-reference.md`, `_shared/*.md`. Place a 5-15 line "Contents" block right after the H1 so partial-read previews see the full scope. `agents/*.md` are exempt: injected in full, so there is no preview for a TOC to widen and the bullets cost their tokens on every spawn.
- **Single source of truth.** Pseudo-code blocks, slot tables, and schema definitions live in exactly one file. Cross-reference the source; never inline a copy.

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

Where a contract's *shape* can carry a rule, prefer that to prose stating the rule. A closed enum, a typed field, a required slot, or a tool allowlist communicates usage at the point of use and cannot drift from its documentation, because it is the documentation.

- **Enumerate instead of demonstrating.** Listing a field's legal values (`confirmed` / `clarified` / `refuted` / `unverified`) teaches usage without a worked example, and without constraining the model to the one case the example showed.
- **Name the field for what it does.** A name implying a behavior the field lacks costs more than it saves: every consumer then needs a sentence undoing the implication, and those sentences are what drift.
- **Let the tool surface state the boundary.** `allowed-tools` / `disallowedTools=` expresses read-only discipline structurally. Keep prose only for what the surface cannot express — a `Bash`-issued `git push` is not covered by withholding `Edit`.
- **Return the value instead of asking the caller to remember it.** A helper that echoes its own result needs no rule telling callers to echo it.

When you find yourself writing a second sentence to clarify how a field should be used, check whether renaming the field or closing its value set removes the need for both.

## Frontmatter hygiene

`skills/<slug>/SKILL.md` required fields:

```yaml
---
name: <slug>                       # bare slug — Claude Code prefixes the plugin name (`geniro`)
description: "Use when ..."        # third-person, what + when, slightly pushy, <=1024 chars, no XML
context: main                      # or fork (for subagent-isolation skills)
model: inherit                     # default; per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md
allowed-tools: [Read, Write, ...]  # explicit allowlist
argument-hint: "[shape | empty]"   # one-line cue
---
```

Description rules:
1. **Third person.** Good: "Processes Excel files." Bad: "I can help you" / "You can use this."
2. **What + when.** Don't describe behavior without saying when to invoke.
3. **Slightly pushy** — lead with `Use when <trigger phrase>.` to combat under-triggering.
4. **No reserved words** (`anthropic`, `claude`) in `name:`.
5. **No XML tags** anywhere in the description.

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
10. Per-phase sections (`## PHASE 1`, ...) — short Steps lists. Inline only the workflow narrative; push templates and pseudo-code to a reference. End each phase on a completion criterion the model can check — done distinguishable from not-done — and, where coverage matters, exhaustive ("every kept finding rendered", not "render the findings"); a vague bound is what lets a phase end early. The Definition-of-Done checklist is the canonical form.
11. Modifier handling — table.
12. Task execution entry / state recovery.
13. REFERENCE — bulleted list of `${CLAUDE_PLUGIN_ROOT}/...` paths.

Sections 1-9 are the spine — what the model checks every turn and what has to survive a summary — so they belong inside the ~3,000-word front-load budget. Anti-rationalization sits at 6 for that reason (`skill-prose.md` §Rule placement carries the mechanism).

**When sections 1-9 alone approach 3,000 words, split the file** rather than compressing the spine — a spine filling the whole budget leaves no room for the phases, which is the failure the split exists to prevent.

## Cross-skill references

| What you mean | Write this | Don't write this |
|---|---|---|
| Reference a sibling skill | `/geniro:plan` | `skills/plan/SKILL.md:319` |
| Reference a phase | `/geniro:plan Phase 5` | `plan-loop.md:319-322` |
| Reference a sub-step | content-anchored: "the Phase 4.3 F→P invariant" | "step at line 350" |
| Reference a shared helper | `${CLAUDE_PLUGIN_ROOT}/skills/_shared/<name>.md` | bare filename without root |
| Reference an agent contract | `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md` §Output Format — open the agent and cite the heading it carries | line-numbered ref |

Line numbers decay within the same edit; section numbers and content anchors survive.

## Anti-rationalization table sizing

Each row is `| reasoning the model might generate | why that reasoning is wrong + what to do instead |`.

- **≤ 15 rows per skill.** Past 15 the table itself becomes hard to read. Adding row #16 means auditing the existing rows — at least one is defending against a failure mode that is no longer live.
- **Each right-hand cell carries reasoning**, not caps. It explains *why* the reasoning is wrong, citing an invariant, a documented failure mode, or a real incident.
- **No internal design-doc anchors** in the right-hand cell. The reader has no access to `design/<file>.md` from their own repo.

## Pre-commit verification

1. **Run `bash tests/authoring/lint-skills.sh`.** It hard-fails on non-Latin text, dangling `${CLAUDE_PLUGIN_ROOT}` references, and unknown spawn names; it warns on anti-rationalization tables over 15 rows, line-number cross-refs, and any SKILL.md grown past its recorded size. Read a growth warning as "check what is load-bearing and where it sits", not "cut until the number goes away" — then `--accept <path>` for that file alone.
2. **Reference depth.** Any file this edit makes a skill cite must not itself pull runtime instructions from another skill's body (§Reference graph).
3. **TOC presence.** A runtime-Read file past ~1,200 words has a Contents block near the top. `agents/*.md` are exempt.
4. **No pseudo-code duplication.** A block added to SKILL.md must not also live in the sibling reference file.
5. **Frontmatter description** is third-person, "Use when …" form, within the length limit.
