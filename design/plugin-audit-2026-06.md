# Plugin-wide audit — 2026-06-05

Whole-repo audit via a 28-agent dynamic workflow: rubric grounding (internet best-practice + distilled `.claude/rules/*`) → 21 parallel auditors (per-skill + `_shared` + agents + shell + cross-cutting) → 5 category synthesizers. Every finding is grep-grounded to a real `path:line`. Findings are prioritized into tiers below; the per-category verdicts and "do-not-touch" lists follow.

## Health summary (what's already strong — do NOT over-correct)

- **Zero `file.md:NNN` line-number cross-refs** repo-wide — the strongest numeric-hygiene win; no fix may reintroduce one.
- **No non-Latin script** anywhere; **no commit-SHAs / design-doc anchors / "we-our" voice / version-markers-in-body** in skill bodies.
- **Schema-lockstep is exemplary** — `open_questions[]`, `authored_tests[]`, `report_status`/`step0_status`/`spawn_dims_declared`, the four-array Pre-Post guard: single-sourced in `state-tier-spec.md`, back-compat stated once and referenced.
- **Shell portability is effectively debt-free** (sha256sum→shasum, tac→tail -r, stat -c→-f all abstracted) and **ShellCheck-clean at `-S warning`**; `jq` idempotency uses `fromjson?` everywhere; never-delete + mkdir-lock invariants correct.
- **Stable `§N` anchors that resolve are ENDORSED** by the rules — only the genuinely dangling/inverted ones are defects. Decision-type tags + memory/tier codes are correctly scoped to author-facing surfaces and rendered to plain English at every user boundary.
- **Justified magic numbers carry inline WHY** (convergence ≥2/≥3, ≤5-question, ≤50-file, 4096 PIPE_BUF, 3-retry) — keep them numeric.

---

## Tier 0 — Safety (fix first)

| # | File:line | Issue | Fix | Effort |
|---|---|---|---|---|
| S1 | `hooks/hooks.json:20` + 5 Edit\|Write hooks | **`MultiEdit` is unmatched — every content/path guard is bypassable.** file-protection / enforce-tdd-order / enforce-state-helper / security-pattern-check / block-config-weakening never fire on `MultiEdit`; a model can write `.env`, weaken tsconfig, or land `eval(` in RED phase via MultiEdit. | matcher → `"Edit\|Write\|MultiEdit"`; in `security-pattern-check.sh` also iterate `.tool_input.edits[].new_string` | M |
| S2 | `lib/emit-learning.sh:158-185` | **`.links[]` bypasses `redact_secrets`** — only summary/body/ext are sanitized; a credential-bearing URL in `links` lands unredacted (violates the synthesize-then-sanitize rule). | extend the ext-paths sanitize loop to walk `.links` string paths | S |
| S3 | `hooks/security-pattern-check.sh:127,159-162` | **`perl -ne` is line-by-line** — a split `curl … \⏎ \| sh` evades the supply-chain guard. | switch multi-line patterns to `perl -0777 -ne` with `/s`; drop `\n` from the curl-pipe char class | M |
| S4 | `lib/emit-learning.sh:234` & `lib/atomic-state-write.sh:112` | **PIPE_BUF guard counts characters, not bytes** (`${#x}` vs 4096) — multibyte content just under 4096 chars can exceed 4096 bytes, so the atomicity-rejection never fires. | measure bytes: `printf '%s' "$x" \| LC_ALL=C wc -c` | S |

## Tier 1 — Test-coverage gaps

| # | File | Issue | Fix | Effort |
|---|---|---|---|---|
| T1 | `lib/archive-stale.sh`, `lib/emit-rejection.sh` | No suites — both are live data-mutating helpers (archive-stale flips `deprecated:true` on the append-only log + auto-runs on SessionStart; emit-rejection's signal `case` regresses silently). | add `tests/memory/archive-stale.sh` + `tests/memory/emit-rejection.sh` | M |
| T2 | `tests/hooks/` | **6 of 10 hooks untested**, incl. 2 hard-block guards (`file-protection.sh`, `enforce-tdd-order.sh`) + `block-config-weakening.sh` — same blast radius as the tested data-loss guards. | mirror `tests/hooks/block-*.sh` structure for those three first | M |
| T3 | `tests/run-all.sh` | `jq` is an unguarded hard dependency — on a jq-less box suites fail opaquely and hook tests silently invert block/allow. | add a `command -v jq` preflight | S |
| T4 | `tests/hooks/session-start-restore.sh` | no negative test for malformed/non-JSON stdin (a parse-failure emitting invalid `additionalContext` would regress silently). | add a `printf 'not json'` case | S |

## Tier 2 — Structural rule violations (HARD)

| # | File:line | Issue | Fix | Effort |
|---|---|---|---|---|
| R1 | `skills/review/SKILL.md:3` | `description:` is **1111 chars — over the 1024 hard ceiling**; also packs `§2.1`/`Phase 6 Pre-gate`/`open_questions[]` jargon that hurts discovery. | trim ≤1024; drop §-number/field jargon; keep trigger + dim shape | M |
| R2 | plan/SKILL.md:220, plan-loop.md:678, debug/SKILL.md:611, investigate/SKILL.md:389, review/SKILL.md:577 | **5 anti-rationalization tables over the ≤15-row ceiling** (4 at 17, review at 16) — several rows duplicate another file's table or restate body prose. | merge/drop the dead-weight rows → ≤15 each | S each |
| R3 | `skills/_shared/per-finding-question.md:84,167` | **Reference-graph inversion** — the canonical AUQ cap-extension helper points UP into `review/SKILL.md`; the "≤4, chain a second" rule is duplicated across ≥12 files. | make per-finding-question.md `§Cap-extension` the sole source; delete upward refs; all sites cite the helper | M |
| R4 | `skills/_shared/spec-challenge.md:75,83,86,195` | helper links into `review/phase-4-verification-reference.md` for runtime procedure (3 refs also missing the `${CLAUDE_PLUGIN_ROOT}` prefix → dangling). | promote the verifier input-contract into a `_shared/` helper both cite; add the prefix to all three | M |
| R5 | `skills/onboard/SKILL.md:58` (+ investigate) | links into `/geniro:implement` BODY for "loop invariants" — cross-skill-body dependency. | move shared invariants to `_shared/loop-invariants.md`; cite from both | M |
| R6 | `skills/review/phase-4-3-test-gate-reference.md:65` | dangling `§plain-English decision-type` anchor (no such header; content is at per-finding-question.md `§Multi-select pick loop`). | retarget the anchor, or add an explicit header | S |

## Tier 3 — Correctness / consistency nits

| # | File:line | Issue | Fix | Effort |
|---|---|---|---|---|
| C1 | `skills/review/SKILL.md:3` | **(self-introduced)** description says `--tdd` "additionally auto-authors failing tests" — contradicts the non-negotiable Phase 4.3 approval gate. | reword to "offers to author failing tests (gated by approval)" | S |
| C2 | `skills/actions/SKILL.md:32 vs 243-249` | loop invariant #2 ("every Write preceded by validation") is false — `create` validates post-write (Step 6). | reword the invariant to "previewed draft + post-write validation gate" | S |
| C3 | `skills/implement/SKILL.md:215` + implement-reference.md:455 | stale conditional treats `/geniro:plan` as not-yet-shipped ("when /plan ships"). | state directly: `decision` emit fires only in inline-task mode | S |
| C4 | `skills/setup/SKILL.md:494-504` | restart-warning gate compares a `plugin_version` the state-file schema doesn't have → can never fire. | add `plugin_version:` to the frontmatter schema | S |
| C5 | `skills/investigate/SKILL.md:35,280,301` | dive-deeper round cap is scratchpad-only — resets on compaction (contradicts the skill's compaction-safety). | persist the round count to state.md | S |
| C6 | `skills/setup/verification-checks.md:38` | verifier compares generated CLAUDE.md to `reference/CLAUDE.md.example`, but generation never reads that example. | wire the example in, or downgrade the check | S |
| C7 | `skills/plan/SKILL.md` ACI table | missing a Phase 7.5 (spec-challenge) row though it spawns agents + writes `## Errors`. | add the row (Read / Agent / atomic_state_write) | S |
| C8 | `lib/update-semantic.sh:125-191` | lock not cleared on SIGINT/SIGTERM — a Ctrl-C leaves a stale O_EXCL lock that wedges all L3 writes. | `trap 'rm -f "$lock_path"' RETURN` after acquire | S |
| C9 | `hooks/session-start-restore.sh:701,716` | `GENIRO_AUTO_ARCHIVE_THRESHOLD` not sanitized — a non-numeric value silently disables auto-archive. | `case` sanitize to default 5000 (mirrors `output_cap`) | S |
| C10 | `lib/redact-secrets.sh:49,89,190-212` | jq-error on safety.json fails OPEN; stale "NUL-substitution" comment (code uses `\001`); multiline PEM path corrupts a payload already containing `\001`. | fail-closed on jq-error; fix comment; guard the `\001` payload case | S |

## Tier 4 — Maintainability (numbers + overengineering)

- **Number-density reduction** — `review/SKILL.md` (94 §N + 140 Phase-N) and `investigate`/`refactor`/`update`/`plan-loop` carry the heaviest cross-ref clusters. Convert only the high-traffic anchors that already have an adjacent English handle (`§7.0` → "the Pre-Post guard", `§4.1` → "the multi-signal admission gate"); **keep resolving cross-file anchors that lack an English label.** Effort L for review, M/S elsewhere.
- **Single-source duplicated thresholds (keep the number, cite one home):** `~4K/5K` output cap (6+ files), convergence ≥2/≥3 (~6 sites → severity-calibration-reference.md), AUQ 4-option cap (≥12 sites → per-finding-question.md, ties to R3), caller-blast 1-3/4-9/10+ (architecture-criteria ×5), `4-retry` backoff (update ×5), peer-PR caps (2 files). Effort S-M each.
- **Overengineering — rationale restated N× within one file** (the dominant pattern, ~14 sites, mostly LOW 1-line fixes): trim `review/SKILL.md` 27-item Definition-of-Done to ~8 load-bearing exit gates (also the cheapest path back under the line target); collapse `update` 4-retry restatements; dedup the verbatim `rm -f` cleanup block (`implement/SKILL.md:623` = `implement-reference.md:505`); collapse `design-doc-detect.md` 3 single-marker anti-rat rows into one.

## Tier 5 — Cosmetic polish

- **Title-Case section headers** → sentence-case (worst: `refactor-patterns.md` 13 headings; several `_shared` H1s; setup/investigate/onboard/update `## Path Constraints`/`## Subagent Model Tiering` etc.). **Do NOT mass-rename the `*-criteria.md` set** — cross-file consistency there is worth more than the churn.
- **Caps-without-reasoning** (yellow-flag): setup:18 `NEVER`, update:205/236 `WARNING:`, review:201/210 `(MANDATORY)`, debug:96 `ONLY`, actions:95/226 `MUST`. Reframe with the inline why (most repo caps already carry reasoning — leave those).
- **Terminology sweeps:** `hand-off`→`handoff` (44 prose instances), `sub-agent`→`subagent` (21), `rerun`→`re-run` (3); `agents/reviewer-agent.md:3` decision-type vocabulary mismatch. Mechanical — run a fresh diff-review after (replace_all + newline-glue memory rules).
- **Provenance citations** (restate in own voice): conventions-criteria.md:23 (NATURALIZE/IntelliCode), plan "Metaswarm anti-pattern", test-first-gate "superpowers iron law", actions:508 "official skill-creator questions", existing-abstraction-audit Sandi Metz quote.
- **User-facing leaks:** phase-1-triage-reference.md:358 `header: "Round-N gate"`; actions:206 "Should **we**…"; update WARNING: prefixes; INCOMING AUQ `#N`/`K` substitution directive.
- **Misc shell hygiene:** backpressure/file-protection `#!/bin/bash`→`#!/usr/bin/env bash`; 9-way `find_safety_json` duplication; lint-skills mktemp trap + line-ref miscount.

---

## Per-axis verdicts

- **Rule-compliance:** healthy — hard exclusions clean repo-wide; remaining items are small polish dominated by Title-Case headers + the anti-rat-overflow pattern (R2). Highest-value: trim the 5 over-cap tables.
- **Numbers:** healthy — zero line-refs, most constants self-document; real debt is section-anchor density (review) + ~12 duplicated thresholds; none dangerous except the `_shared` upward inversions (R3/R4).
- **Overengineering:** healthy — no re-explained tooling, no menu-of-equivalents; only recurring pattern is in-file rationale restatement. Highest-value: trim review's 27-item DoD.
- **Gaps/consistency:** healthy — schema-lockstep + reference resolution exemplary; highest real-world risk is the MultiEdit bypass (S1).
- **Shell:** strong on portability/shellcheck (≈zero debt); real gaps are correctness/safety (S1-S4) + missing tests (T1-T2).

**Single highest-value fix across the whole repo: S1 (MultiEdit hook bypass)** — every file-protection / TDD-order / config-weakening / security guard is currently bypassable through one untracked tool.
