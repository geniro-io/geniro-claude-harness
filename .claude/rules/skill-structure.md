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

- **Depth ≤ 1 hop** from SKILL.md. SKILL.md may link to `*-reference.md` or to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/*.md` helpers; those files may NOT link back into other skill bodies for runtime instructions. Claude does partial reads (`head -100`) on nested refs and loses information.
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

## Migration audit — concrete current violations

The numbers below reflect the codebase at the time this rule was authored. They are starting points, not a freeze frame — re-run the greps in §Pre-commit verification when auditing.

**SKILL.md files exceeding the 500-line target:**

| File | Lines | Suggested action |
|---|---|---|
| `skills/debug/SKILL.md` | 920 | Severe — split state machine + recovery scenarios into `debug-state-reference.md` |
| `skills/investigate/SKILL.md` | 839 | Severe — split 9-type taxonomy + agent-spawn templates into `investigate-taxonomy-reference.md` |
| `skills/refactor/SKILL.md` | 716 | Move smell-detection patterns + per-step regression contracts into `refactor-patterns-reference.md` |
| `skills/implement/SKILL.md` | 643 | Already partially split; consider moving Step 0 sub-sections into `implement-reference.md` §"Phase 1 Step 0" |
| `skills/setup/SKILL.md` | 629 | Move 4-phase interview templates into `setup-interview-reference.md` |
| `skills/review/SKILL.md` | 602 | Move Phase 4 sub-phase tables into existing `phase-4c-test-gate-reference.md` umbrella |
| `skills/instructions/SKILL.md` | 593 | Move per-scope scaffolds into `instructions-scaffolds-reference.md` |
| `skills/actions/SKILL.md` | 568 | Move risk-class AUQ ladder details into `actions-risk-reference.md` |
| `skills/onboard/SKILL.md` | 507 | Marginal — re-examine before splitting |

**Anti-rationalization tables exceeding 15 rows:**

| File | Rows | Suggested action |
|---|---|---|
| `skills/debug/SKILL.md` | 32 | Prune to top 15 by current relevance |
| `skills/refactor/SKILL.md` | 24 | Prune to top 15 |
| `skills/review/SKILL.md` | 23 | Prune to top 15 |
| `skills/investigate/SKILL.md` | 20 | Prune to top 15 |
| `skills/implement/SKILL.md` | 18 | Prune by 3 |

**Reference files > 100 lines lacking a TOC:**

`plan-loop.md` (545), `implement-reference.md` (544), `phase-1-triage-reference.md` (377), `phase-6-handoff-reference.md` (285), `plan-context-reference.md` (206), `phase-4c-test-gate-reference.md` (138), `incoming-mode-reference.md` (121). Add a 5-15 line "Contents" block right after the H1.

**Line-number cross-references to fix:**

| Location | Reference | Replace with |
|---|---|---|
| `skills/plan/plan-loop.md:119` | `skills/investigate/SKILL.md:199` | content anchor: "/geniro:investigate Phase 2 spawn idiom" |
| `skills/review/phase-1-triage-reference.md:206` | `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md:22` | content anchor: "the Phase 1 workflow-integration block" |

This audit is one-time; the structural constraints above are forever. New edits enforce themselves via the Pre-commit verification checklist.
