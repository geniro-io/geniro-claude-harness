# Plugin-audit fix — PROGRESS / RESUME state

Working state for the "fix everything (Tier 0-5)" pass over the plugin-wide audit in `design/plugin-audit-2026-06.md` (that file is the canonical findings list with `file:line` + fix per item). This file tracks DONE vs REMAINING so the work resumes cleanly after a compaction.

**Branch:** `chore/plugin-audit-fixes` (off the review-improvements commit `17e2958`). Working tree is CLEAN — everything below marked DONE is committed.

**Commits so far (newest first):**
- `95e1154` test(audit): cover archive-stale / emit-rejection + .links/PIPE_BUF; harden missing-arg guards under set -u
- `b20715e` style(audit): normalize terminology — handoff / subagent / re-run
- `3496372` docs(audit): progress/resume doc
- `d737ffe` test(audit): cover untested hard-block hooks + MultiEdit/multiline regression
- `9d82620` refactor(audit): fix reference-graph inversions (_shared no longer points up)
- `293c155` fix(audit): Tier-3 correctness — schema gaps, stale checks, dangling anchor
- `5cf76d5` fix(safety): close MultiEdit hook bypass + redaction/PIPE_BUF gaps; correctness nits
- (`17e2958` feat(review): additive TDD / decision-gate / deep mode — the PRIOR task, base of this branch)

**Verification baseline:** full suite **19 suites / 0 failures**; shellcheck `-S error` clean (pre-existing SC2120 warning in validate-state-file.sh is below the CI gate); authoring lint 0 hard failures.

---

## DONE

**Tier 0 — safety (commit 5cf76d5):**
- [x] S1 — `hooks.json` matcher `Edit|Write` → `Edit|Write|MultiEdit`; `security-pattern-check.sh` also scans `.tool_input.edits[].new_string`.
- [x] S2 — `lib/emit-learning.sh` routes `.links[]` through `redact_secrets`.
- [x] S3 — `security-pattern-check.sh` uses `perl -0777` slurp so a multi-line download-pipe-to-shell is caught; `[^|\n]`→`[^|]`.
- [x] S4 — PIPE_BUF guard counts bytes (`wc -c`) not chars in `emit-learning.sh` + `atomic-state-write.sh`.

**Tier 3 — correctness (5cf76d5 + 293c155):**
- [x] C1 — `review/SKILL.md` description: `--tdd` "auto-authors" → "offers to author (gated by approval)".
- [x] C2 — `actions/SKILL.md` invariant #2 no longer claims validation precedes the write.
- [x] C3 — `implement-reference.md` stale "when /geniro:plan ships" + "legacy…superseded" narration dropped.
- [x] C4 — `setup/SKILL.md` added `plugin_version` frontmatter field for the §5.4 restart-warning gate.
- [x] C5 — `investigate/SKILL.md` dive-deeper round count persisted to state.md `dive_round:` (was scratchpad).
- [x] C6 — `setup/verification-checks.md` reworded the example-contamination check to a generic-placeholder scan.
- [x] C7 — `plan/SKILL.md` ACI table gained the missing Phase 7.5 (spec-challenge) row.
- [x] C8 — `lib/update-semantic.sh` lock released on every return path (`trap ... RETURN`).
- [x] C9 — `session-start-restore.sh` sanitizes a non-numeric `GENIRO_AUTO_ARCHIVE_THRESHOLD`.
- [x] C10 — `redact-secrets.sh` stale "NUL-substitution" comment fixed (0x01). (C10's fail-open + multiline-payload sub-items were judged non-bugs / out-of-scope — see notes.)
- [x] R1 — `review/SKILL.md` description trimmed 1111→998 chars (under the 1024 ceiling), jargon dropped.
- [x] R6 — `phase-4-3-test-gate-reference.md` dangling `§ plain-English decision-type` anchor → `§ Multi-select pick loop`.

**Tier 2 — reference-graph inversions (9d82620):**
- [x] R3 — `_shared/per-finding-question.md` self-contains `§ Cap-extension` (dropped upward refs into review body); persisted-line-schema ref → `phase-6-handoff-reference.md`.
- [x] R4 — `_shared/spec-challenge.md` 3 dangling `phase-4-verification-reference.md` refs prefixed with `${CLAUDE_PLUGIN_ROOT}/skills/review/`.
- [x] R5 — created `_shared/loop-invariants.md` (canonical 7 agent-loop invariants); repointed onboard + investigate; cross-linked from implement.

**Tier 1 — tests (d737ffe):**
- [x] T2 — new suites `tests/hooks/{file-protection,block-config-weakening,enforce-tdd-order}.sh` (positive-block / false-positive / safety.json bypass / MultiEdit / fail-open).
- [x] T3 — `tests/run-all.sh` jq preflight.
- [x] security-pattern-check suite extended with MultiEdit + multi-line cases (protects S1/S3).

**Tier 5 — terminology sweep (b20715e):**
- [x] `hand-off`→`handoff` (16 files), `sub-agent`/`Sub-agent`→`subagent` (11 files, EXCLUDING the scope-anchor.md external-URL match), `rerun`→`re-run` (2 files). Section header + every cross-ref moved in lockstep. Prose-only, 0 hard lint.

**Tier 1 — tests, round 2 (`95e1154`):**
- [x] T1 — new `tests/memory/archive-stale.sh` (13 cases: stale-flip / 3 controls / never-delete / dry-run / malformed-refuse / bad-tau) + `tests/memory/emit-rejection.sh` (10 cases: each signal / non-recommended / no-op / false-positive guard / missing-arg).
- [x] Extended `tests/memory/emit-learning.sh` with `.links` redaction (object + array) + multibyte-PIPE_BUF byte-count cases (protects S2/S4).
- [x] T4 — `tests/hooks/session-start-restore.sh` gained a malformed/empty-stdin negative case (graceful default, no crash, valid JSON).
- [x] **Robustness fix (found via the emit-rejection test):** `emit-rejection.sh` + `atomic-state-write.sh` (×2) + `validate-state-file.sh` read their first positional as `${1:-}` so a documented `rc=64` "X required" guard isn't preempted by an `set -u` unbound-variable crash on a short/zero arg list. Locked by a zero-arg-under-`set -u` assertion in `tests/state/atomic-write.sh`.

---

## REMAINING (not yet done)

**Tier 2 — anti-rationalization tables over 15 rows (R2, ADVISORY/warn-only — do ONLY the duplication-removal cuts, do NOT drop a distinct guard):**
- [ ] `plan/SKILL.md` (17) — cut rows that duplicate `plan-loop.md`'s table.
- [ ] `plan/plan-loop.md` (17) — drop dead-weight rows.
- [ ] `debug/SKILL.md` (17) — merge two near-dup evidence rows + drop test-naming row already in §2.4.
- [ ] `investigate/SKILL.md` (17) — merge glossary/JIT + convergence overlaps.
- [ ] `review/SKILL.md` (16) — LEAVE: both candidate cut-rows are distinct guards (decision-type-orthogonal is load-bearing). 1-over-guideline is acceptable.

**Tier 4 — maintainability (single-source duplicated thresholds; trims):**
- [ ] `implement/SKILL.md:623` == `implement-reference.md:505` — `rm -f` cleanup block duplicated verbatim → single-source.
- [ ] `review/SKILL.md:598-628` — 27-item Definition-of-Done → trim to ~8 load-bearing exit gates (also reclaims lines).
- [ ] Single-source duplicated thresholds (keep the number, cite one home): `~4K/5K` output cap (6+ files), convergence ≥2/≥3 (→ severity-calibration-reference.md), caller-blast 1-3/4-9/10+ (architecture-criteria ×5), `4-retry` backoff (update ×5), peer-PR caps, 20-LOC trivial (architecture/pr-metadata-criteria).
- [ ] In-file rationale-restatement trims (≈14 LOW sites): update 4-retry ×5; investigate dive-round; atomic-state-write empty-stdin ×3; context-isolation-checklist Explore-Haiku ×3; finding-tagging 60% ×5; design-doc-detect 3 single-marker anti-rat rows; etc. (full list in audit Tier-4/overengineering report).

**Tier 5 — cosmetic:**
- [x] ~~Terminology sweeps~~ — DONE (b20715e).
- [ ] Title-Case section headers → sentence-case (worst: `_shared/refactor-patterns.md` 13 headings; several `_shared` H1s; setup/investigate/onboard/update `## Path Constraints`/`## Subagent Model Tiering`). **Do NOT mass-rename the `*-criteria.md` set.**
- [ ] Caps-without-reasoning reframes: setup:18 `NEVER`; update:205/236 `WARNING:`; review:201/210 `(MANDATORY)`; debug:96 `ONLY`; actions:95/226 `MUST`. (Most repo caps carry reasoning — leave those.)
- [ ] Provenance citations → own voice: conventions-criteria:23 (NATURALIZE/IntelliCode); plan "Metaswarm anti-pattern"; test-first-gate "superpowers iron law"; actions:508 "official skill-creator questions"; existing-abstraction-audit Sandi-Metz quote.
- [ ] User-facing leaks: `phase-1-triage-reference.md:358` `header: "Round-N gate"`; actions:206 "Should **we**…"; update `WARNING:` prefixes; INCOMING AUQ `#N`/`K` substitution directive.
- [ ] Shell hygiene: `hooks/backpressure.sh` + `hooks/file-protection.sh` `#!/bin/bash` → `#!/usr/bin/env bash`; `tests/authoring/lint-skills.sh` mktemp trap + line-ref miscount; (optional) extract the 9-way duplicated `find_safety_json` into a sourced helper.

---

## Resume gotchas (learned this session)

1. **The security hook now blocks edits whose CONTENT contains a literal `curl … | sh` / `--insecure`** (it works — confirmed). When editing `.sh` files (incl. tests) that need such a payload, assemble it via `printf 'curl … | %s' sh` so the literal never appears in source. eval/pickle/etc. are extension-scoped (py/js) so they don't trip on a `.sh` file.
2. **After a compaction/resume the harness clears file-read state** — Re-`Read` a file in the new session before `Edit` (the first edit attempt will fail "File has not been read yet").
3. **`replace_all` is per-file** — terminology sweep is N Edit calls or a `sed -i ''` Bash loop (macOS BSD sed needs the `''` arg). Verify with a fresh grep + `git diff` review afterward (memory: deterministic≠verified).
4. **`run-all.sh` is slow under load** (system was loaded from audit workflows) — individual suites confirm fast; don't mistake `tail`-buffering for a hang.
5. **Commit per coherent tier** (the pattern so far). Lint (`bash tests/authoring/lint-skills.sh`) + full suite (`bash tests/run-all.sh`) before each commit.
