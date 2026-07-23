---
globs: "skills/**/*.md, agents/**/*.md"
---

# Skill & agent authoring — file structure

Positive-guidance companion to `.claude/rules/skill-authoring.md`. While that file lists what NEVER ships, this file lists the mechanical structure rules every skill / agent / reference file should follow when authored or edited.

Sources for every number below: Anthropic [Skill best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices), [Claude Code skill docs](https://code.claude.com/docs/en/skills), and [Cursor rules docs](https://cursor.com/docs/rules) (cross-source confirmation for the 500-line cap).

## File-size limits

| File class | Target | Hard ceiling | What to do on overflow |
|---|---|---|---|
| `skills/<slug>/SKILL.md` body (after frontmatter) | ≤ 500 lines | ~700 lines | Move detailed templates / pseudo-code / contracts to a sibling `*-reference.md`; SKILL.md keeps the workflow narrative + step bullets + invariants + anti-rationalization. |
| Reference file (`*-reference.md`) | ≤ 600 lines | no ceiling | Split by phase / concern. Add TOC at the top if file > 100 lines (see §Reference graph). |
| Agent file (`agents/*.md`) | ≤ 250 lines | ~400 lines | Move slot tables and worked examples to `agents/<name>-reference.md`. |

500 lines is the cross-source-confirmed target, not a strict cap. Don't trim load-bearing content to hit a number. Move detail to a reference file instead.

## Reference graph

- **Depth ≤ 1 hop from SKILL.md to reference / helper.** SKILL.md may link to `*-reference.md` or to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/*.md` helpers. Those targets may NOT link back into another skill body (`skills/<other>/SKILL.md` or its references) for runtime instructions — cross-skill coordination lives in `_shared/`, never in a foreign skill's reference file. **Inside `_shared/`, peers may cross-link freely** for topological context (e.g., `state-tier-spec.md` ↔ `atomic-state-write.md` ↔ `validate-state-file.md` reference each other because they describe one cohesive subsystem). The 1-hop ceiling constrains the SKILL → reference edge; `_shared/` is a flat namespace whose helpers navigate among themselves. Claude still does partial reads on transitively-discovered files, so chains longer than ~3 hops from SKILL.md to leaf degrade — avoid those.
- **TOC required** for any file > 100 lines. Place a 5-15 line "Contents" or "Sections" block right after the H1 so partial-read previews still see the full scope.
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

1. **Run `bash tests/authoring/lint-skills.sh`.** It mechanizes the checkable rules here — hard-fails on non-Latin text, dangling `${CLAUDE_PLUGIN_ROOT}` file references, and unknown spawn names; warns on file-size targets, anti-rationalization tables over 15 rows, and line-number cross-refs. On an over-target size, move detail to a sibling reference file; never trim load-bearing content to hit a number (the caps are guidelines).
2. **Reference depth.** Any file this edit makes a skill cite must not itself pull runtime instructions from another skill's body (§Reference graph).
3. **TOC presence.** A reference file grown past 100 lines has a Contents block near the top.
4. **No pseudo-code duplication.** A pseudo-code block added to SKILL.md must not also live in the sibling reference file — cite the single source instead.
5. **Frontmatter description** is third-person, "Use when …" form, ≤1024 chars.
