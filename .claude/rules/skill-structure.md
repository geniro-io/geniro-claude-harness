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
| Reference file (`*-reference.md`) | ≤ 600 lines | no ceiling | Split by phase / concern. Add TOC at the top if file > 100 lines (see §TOC rule). |
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
name: geniro:<slug>               # gerund form or noun; lowercase + numbers + hyphens; ≤64 chars
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
9. Per-phase sections (`## PHASE 1`, `## PHASE 2`, ...) — each contains short Steps list. Inline ONLY the workflow narrative; push templates + pseudo-code to reference.md.
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
| Reference a sub-step | content-anchored: "the Phase 4c F→P invariant" | "step at line 350" |
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

Before committing edits to `skills/**/*.md` or `agents/**/*.md`, walk this checklist:

1. **Line counts.** `wc -l` the touched file. Over 500 (or 700 hard ceiling) → split.
2. **Reference depth.** `grep '${CLAUDE_PLUGIN_ROOT}\|${CLAUDE_SKILL_DIR}'` the file. Any reference target itself must NOT reference another skill body for runtime instructions.
3. **TOC presence.** Any reference file > 100 lines must have a TOC near the top.
4. **No line-number cross-refs.** `grep -nE 'SKILL\.md:[0-9]+|reference\.md:[0-9]+'` returns nothing.
5. **No pseudo-code duplication.** If you added a pseudo-code block (`while`, `if`, `for` in a fenced block), grep the sibling reference file. If it lives there too, point to it from SKILL.md instead of inlining.
6. **Anti-rationalization table ≤ 15 rows.** `sed -n '/^## Anti-rationalization/,/^## /p' <file> | grep -cE '^\|'` — subtract 2 (header + separator) and check.
7. **Frontmatter description** is third-person, "Use when …" form, ≤1024 chars.

## Migration audit — remaining work

The numbers below reflect the codebase after the structural-refactor pass. Re-run the greps in §Pre-commit verification when auditing.

**SKILL.md files exceeding the 500-line target** (all under the 700 hard ceiling):

| File | Lines | Note |
|---|---|---|
| `skills/review/SKILL.md` | 712 | Marginal — 12 over the 700 hard ceiling; revisit on next structural pass (spawn-list + 9-dim grid + Definition of Done + Phase 2 narration + Phase 4.1 MEDIUM-Evidence constraint dominate length) |
| `skills/debug/SKILL.md` | 689 | Acceptable — under hard ceiling; Adversarial Mode A1-A6 procedure inline |
| `skills/implement/SKILL.md` | 668 | Acceptable — under hard ceiling; 3-phase loop with KR/CE/TR/reviewer/adversarial spawn sites |
| `skills/setup/SKILL.md` | 629 | Acceptable — 4-phase singleton bootstrap inline |
| `skills/instructions/SKILL.md` | 593 | Acceptable — 10-scope CRUD inline |
| `skills/actions/SKILL.md` | 568 | Acceptable — 6-op CRUD + 3-tier risk-class AUQ inline |
| `skills/refactor/SKILL.md` | 550 | Acceptable — under hard ceiling |
| `skills/onboard/SKILL.md` | 505 | Marginal — re-examine if it grows |

**Anti-rationalization tables**: all ≤15 rows. Caps respected.

**Reference files > 100 lines lacking a TOC**: re-audit when adding new reference files. Add a 5-15 line "Contents" block right after the H1 per §Reference graph rule.

This audit reflects the post-refactor state. New edits self-enforce via the §Pre-commit verification checklist.
