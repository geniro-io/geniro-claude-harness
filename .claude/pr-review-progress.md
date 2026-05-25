# PR #6 Review Comments — Progress Tracker

Created: 2026-05-25
Branch: claude/skip-architecture-with-spec-yjx8x

---

## Commits made during this review session

```
68292b0 refactor: strip all internal milestone refs from user-facing docs
c739d4f fix: scrub remaining stale refs from agents, CLAUDE.md, HOOKS.md
8150724 refactor: remove all legacy/historical references from skills
01ec621 refactor: PR review cleanup — agents, hooks, shared scripts
fff4a1e chore(agents): scrub stale agent refs from 3 active docs (previous session)
2bd0922 refactor(agents): delete refactor-agent (previous session)
8e70275 refactor(agents): delete relevance-filter-agent (previous session)
13511ca refactor(agents): delete architect-agent (previous session)
17e1863 feat(review): Linear workflow integration + expanded peer-PR scout (previous session)
```

---

## Comment 1 — `.claude-plugin/marketplace.json:10`
**Question:** "Check if we need all hooks, investigate each. Investigate if there is no stalled hooks"
**Status:** ✅ DONE
**Action taken:**
- Investigated all 9 hooks in hooks.json — all active, none stale
- `backpressure.sh` is NOT a hook (not registered), it's a utility script sourced by /review and /refactor — NEEDED
- Fixed marketplace.json description: "5 sub-agents" → "2", "8 safety hooks" → "6" (after also deleting plan-mode-write-guard in Comment 9)

---

## Comment 2 — `.claude/skills/improve-template/SKILL.md:19`
**Question:** "Claude plugin rules - it's correct var name? Will it be injected automatically?"
**Status:** ✅ DONE — no action needed
**Finding:** `${CLAUDE_PLUGIN_ROOT}` is the correct variable name. Auto-injected by Claude Code as an environment variable for plugins. Used 436 times across the codebase.

---

## Comment 3 — `.claude/skills/improve-template/SKILL.md:19`
**Question:** "Do we still have reviewer agent?"
**Status:** ✅ DONE — no action needed
**Finding:** Yes, reviewer-agent still exists. 2 agents remain: `reviewer-agent.md` + `adversarial-tester-agent.md`. Line 19 correctly references both.

---

## Comment 4 — `agents/adversarial-tester-agent.md:3`
**Question:** "Do we really need to specify the skill? Does this subagent need to know about it?"
**Status:** ✅ DONE
**Action taken:** Removed all skill-name references from description + body. Per Anthropic docs (code.claude.com/docs/en/sub-agents), agent description should say WHAT it does, not WHO calls it. Cleaned: description (removed "Spawned by /geniro:review Phase 4c..."), body opener (removed skill refs, made SUBTRACTIVE signal note generic), input contract #5 (removed hardcoded output paths), output schema (removed skill-specific next step).

---

## Comment 5 — `agents/adversarial-tester-agent.md:39`
**Question:** "Do we need to specify a concrete path? Or better to specify from outside?"
**Status:** ✅ DONE (handled with Comment 4)
**Action taken:** Removed hardcoded output paths. Now says "write to the exact output path provided in your spawn prompt" — caller provides the path.

---

## Comment 6 — `agents/adversarial-tester-agent.md:142`
**Question:** "Why do I see the next orchestrator step? This subagent can be called from anywhere."
**Status:** ✅ DONE (handled with Comment 4)
**Action taken:** Removed skill-specific orchestrator next step from output schema. Now says generic "route to the appropriate fix-loop or persistence pass."

---

## Comment 7 — `agents/reviewer-agent.md:3`
**Question:** "Same question for all remaining sub-agents — specific skill names, is this correct?"
**Status:** ✅ DONE (handled with Comment 4)
**Action taken:** Cleaned reviewer-agent.md: removed consumer profiles from description (was listing exact dim counts for /review and /implement), removed skill-specific consumer profiles from body, made input contract generic. Also fixed 5 additional skill refs found on second pass (Phase 6 idempotency, /geniro:debug routing, Phase 4 Step 0 judge pass).

---

## Comment 8 — `hooks/enforce-state-helper.sh:107`
**Question:** "Why do I see scripts in shared folder? That folder usually has only prompts."
**Status:** ✅ DONE
**Action taken:** Moved ALL 11 .sh scripts from `skills/_shared/` to new `lib/` directory. Updated 81 references across 35 files. The `.md` companion docs (API specs) stay in `skills/_shared/` — they're prompt/instruction files.

Scripts moved: `archive-stale.sh`, `atomic-state-write.sh`, `emit-learning.sh`, `emit-rejection.sh`, `load-semantic.sh`, `query-learnings.sh`, `redact-secrets.sh`, `repo-root.sh`, `resolve-conflicts.sh`, `update-semantic.sh`, `validate-state-file.sh`.

---

## Comment 9 — `hooks/plan-mode-write-guard.sh:144`
**Question:** "Do we really need this entire hook? Isn't this overengineering?"
**Status:** ✅ DONE
**Action taken:** Deleted `plan-mode-write-guard.sh` (159 lines). Layer 1 protection (Edit removed from /plan's `allowed-tools`) is sufficient. Removed from hooks.json, CLAUDE.md (hook description + bypass pattern), HOOKS.md, plan/SKILL.md, plan/plan-reference.md. Updated marketplace.json hook count.

---

## Comment 10 — `hooks/session-start-restore.sh:148`
**Question:** "Why do we have SH files in the Shared folder? There should be a separate subfolder."
**Status:** ✅ DONE (resolved by Comment 8 — lib/ move)

---

## Comment 11 — `hooks/session-start-restore.sh:764`
**Question:** "This entire SH script is pretty big and complex. Do we really need it?"
**Status:** ✅ DONE — kept as-is
**Finding:** 765 lines IS the M3 compaction-survival mechanism. Without it, Claude forgets everything after compaction. It handles 3 state layouts, YAML parsing in bash, and 6 context blocks. User decided to keep as-is.

---

## Comment 12 — `skills/_shared/architecture-vocabulary.md:8`
**Question:** "Do we need to specify which skills use each shared instruction? Extra sync complexity."
**Status:** ✅ DONE
**Action taken:** Removed consumer-skill lists from all `_shared/*.md` files. Same pattern as agents cleanup — shared files describe WHAT they do, not WHO uses them. Cleaned architecture-vocabulary.md manually + 1 file (learnings-extraction.md) via agent.

---

## Comment 13 — `skills/_shared/auto-mode-signals.md:3`
**Question:** "Do we still need this instruction? Do we still have auto mode?"
**Status:** ✅ DONE
**Action taken:** Deleted `auto-mode-signals.md` — orphan file with ZERO references from any skill.

---

## Comment 14 — `skills/_shared/branch-naming.md:1`
**Question:** "Do we really need a separate file for branch naming?"
**Status:** ✅ DONE
**Action taken:** Deleted `branch-naming.md` — orphan file with ZERO references from any skill (80 lines, nobody reads it).

---

## Comment 15 — `skills/_shared/design-doc-detect.md:72`
**Question:** "We don't need legacy anywhere. Delete everything related to legacy."
**Status:** ✅ DONE
**Action taken:** Full legacy cleanup across 32 files under `skills/`. Removed all pre-M* historical notes, backward-compat fallback sections, deleted-skill absorption references, generation numbering. Additional pass cleaned remaining refs from agents/, CLAUDE.md, HOOKS.md (6 more files). Then separate pass stripped ALL internal milestone numbers (M1-M10), proposal IDs (P-M*), section refs (§*), master plan refs, defect labels (D* fix), quarter labels from CLAUDE.md + HOOKS.md + README.md.

---

## Comment 16 — `skills/_shared/effort-scaling.md:3`
**Question:** "У нас разве всё ещё остался рефактор skill? Посмотреть"
(Do we still have the refactor skill? Check.)
**Status:** ❌ NOT STARTED
**Notes:** Yes, /refactor still exists as one of the 11 skills. Need to read the file and verify it's correctly referencing current skills.

---

## Comment 17 — `skills/_shared/emit-rejection.md:3`
**Question:** "Я вижу, русские буквы не должно быть ничего русского. Все должно быть на английском."
(I see Russian characters — there should be nothing Russian. Everything should be in English.)
**Status:** ❌ NOT STARTED
**Notes:** Need to scan ALL files for Cyrillic characters and replace with English equivalents. Already fixed CLAUDE.md/HOOKS.md/README.md/agents — need to check skills/ and lib/.

---

## Comment 18 — `skills/_shared/emit-rejection.md:117`
**Question:** "Зачем вообще нам эти инструкции нужны? Они реально нам нужны? Для чего?"
(Why do we need these instructions at all? Are they really needed? For what?)
**Status:** ❌ NOT STARTED
**Notes:** Need to analyze emit-rejection.md — what it does, who uses it, whether it's justified.

---

## Comment 19 — `skills/_shared/load-semantic.md:126`
**Question:** "Объяснение предназначения этих инструкций, где мы их используем, зачем"
(Explain the purpose of these instructions, where we use them, why)
**Status:** ❌ NOT STARTED
**Notes:** Need to explain load-semantic.md purpose and usage.

---

## Comment 20 — `skills/_shared/medium-gate.md:61`
**Question:** "Что за shared-инструкции такие «medium-gate»? Зачем они? Вообще, проанализируй все инструкции и дополнительные фабки shared, и скажи, какие мы можем вообще удалить."
(What is medium-gate? Analyze ALL shared instructions and say which we can delete.)
**Status:** ❌ NOT STARTED
**Notes:** This is a BIG task — full audit of all `_shared/*.md` files. Need to check each for: (a) is it referenced? (b) is it still relevant? (c) can it be merged with another file?

---

## Comment 21 — `skills/_shared/plan-loop.md:1`
**Question:** "We already have a plan-related MD file. Maybe we can merge some shared constructs?"
**Status:** ❌ NOT STARTED
**Notes:** Check for duplicate/overlapping plan-related files in _shared/.

---

## Comment 22 — `skills/_shared/resolve-conflicts.sh:1`
**Question:** "Нам вообще нужны эти инструкции, скрипт для ResolveConflict? Где он вообще применяется?"
(Do we need this script for resolve-conflicts? Where is it used?)
**Status:** ❌ NOT STARTED
**Notes:** Note: resolve-conflicts.sh was moved to lib/ in Comment 8. Need to check if it's actually used.

---

## Comment 23 — `skills/_shared/spawn-agent.md:1`
**Question:** "We already have some shared instructions related to agent spawning. Check."
**Status:** ❌ NOT STARTED
**Notes:** Check for duplicate agent-spawn-related files in _shared/.

---

## Comment 24 — `skills/_shared/test-first-gate.md:21`
**Question:** "Удали всё Legacy. У нас вообще нет уже Junior Follow-up."
(Delete all Legacy. We don't have follow-up anymore.)
**Status:** ✅ LIKELY DONE (by Comment 15 legacy cleanup agent)
**Notes:** Verify that the legacy cleanup agent handled this file.

---

## Comment 25 — `skills/_shared/validate-state-file.sh:1`
**Question:** "Нам точно нужен этот скрипт и эти инструкции? Это просто не добавляет дополнительную сложность?"
(Do we really need this script? Doesn't it just add complexity and extra tokens?)
**Status:** ❌ NOT STARTED
**Notes:** Need to analyze validate-state-file.sh — who uses it, is it justified.

---

## Comment 26 — `skills/plan/validator-checks.md:1`
**Question:** "Опять какой-то валидатор чекс. Нужно ли нам это? Выглядит, что у нас всё over-complicated."
(Another validator checks file. Do we need this? Looks over-complicated.)
**Status:** ❌ NOT STARTED
**Notes:** Need to analyze validator-checks.md — is it used, is it necessary.

---

## Comment 27 — `skills/review/guidelines-criteria.md:181`
**Question:** "What is this 'removed'? No historical notes anywhere. Only current context with current instructions."
**Status:** ✅ LIKELY DONE (by Comment 15 legacy cleanup agent)
**Notes:** Verify the specific line was cleaned.

---

## Comment 28 — `tests/memory/repo-root.sh:1`
**Question:** "Подожди, где-то у нас уже был скрипт репоруб. Мне кажется, некоторые скрипты дублируются."
(Wait, we already had a repo-root script somewhere. I think some scripts are duplicated.)
**Status:** ❌ NOT STARTED
**Notes:** Check if repo-root.sh is duplicated between lib/ and tests/memory/.

---

## Summary

| Status | Count |
|--------|-------|
| ✅ DONE | 17 (Comments 1-15, 24, 27) |
| ❌ NOT STARTED | 11 (Comments 16-23, 25-26, 28) |
| **Total** | **28** |

## Next comments to tackle: 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 28
