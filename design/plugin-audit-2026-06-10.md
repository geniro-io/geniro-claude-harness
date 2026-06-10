# Plugin-wide audit — 2026-06-10

**Scope:** full repo (empty arguments). **Reviewer topology:** D1 mechanical battery (orchestrator-inline) → 10 parallel dimension reviewers: D2 (consistency), D3 (staleness), D4 sharded A/B (authoring rules), D5a sharded A/B (markdown logic), D5b (shell logic), D6 (over-complication), D7 (magic numbers), D8 (safety & coverage). Every admitted finding re-verified by orchestrator Read of the cited line; the three shell bypasses were re-confirmed empirically by feeding crafted tool-input JSON to the live hooks.

## Health summary (what's strong — do NOT over-correct)

- **The recent guard hardening largely holds.** `MultiEdit` is now matched and tested across 5 hook suites; `block-dangerous-git.sh` strips `git -C`/`-c`/`--git-dir` global options; the `file-protection.sh` Bash branch exists with block+allow tests; all 6 documented bypass-ID families are checked bidirectionally (no dead IDs, no undocumented branches).
- **Schema-lockstep is exemplary.** Every chain traced (state-tier enum ↔ validator ↔ restore-hook renderer, `m6-v2` handoff producer↔consumer, `workflow_refs[]` across plan/consumers, `open_questions[]`, `authored_tests[]`) is consistent. The `lib/` memory helpers (emit-learning, query-learnings, archive-stale, atomic-state-write) all verify clean against their `_shared/` contracts.
- **Mechanical hygiene is clean:** zero `file.md:NNN` line-number cross-refs, no non-Latin script, no commit-SHAs / design-doc anchors / "we-our" voice in skill bodies, all `${CLAUDE_PLUGIN_ROOT}` refs and spawn names resolve, all frontmatter complete, descriptions ≤1024 chars, all long reference files carry TOCs. Tests: 27/27 suites pass. ShellCheck `-S error`: clean.
- **No contradicting constants and no stale prose counts** in the number layer — every count spot-checked (14 validator checks, 8 always-fire dims, 60-char slug) matches reality; shell literals are well-disciplined (env overrides + sanitization).
- **Spawn-site discipline holds** with only the two documented carve-outs (setup verification subagent on Sonnet; doc-patcher on haiku).

The defect mass is NOT in the machine-facing layer. It is concentrated in (1) one shell guard that the hardening commit missed, (2) skill state-machine / tool-surface tables, and (3) the human-facing docs (README / ARCHITECTURE / HOOKS / MIGRATION) lagging the last two feature waves.

---

## Tier 0 — Safety (fix first)

| # | file:line | issue | fix | effort |
|---|---|---|---|---|
| S1 | `hooks/block-geniro-deletion.sh:280,293` | **`git -C <path>` bypasses BOTH `.geniro/` data-loss guards** (worktree-remove + git-add-force). The hardening commit added the `git`-global-option strip to `block-dangerous-git.sh:55` but NOT here, so `git -C /repo worktree remove ../wt` and `git -C /repo add -f .geniro/actions/foo.md` both exit 0 where the plain forms exit 2. **Empirically confirmed** (the documented Cursor-SCM real-incident vector). | Apply the same `sed -E 's/git(<global-opts>)+/git/g'` normalization `block-dangerous-git.sh:55` uses, before the git-subcommand matchers in this file. | M |
| S2 | `hooks/hooks.json:25` | **`NotebookEdit` is unmatched by all 5 Edit/Write guards** (file-protection, tdd-order, state-helper, security-scan, config-weakening). A `credentials.ipynb`/`secrets.ipynb` write, an `eval(`/`pickle.load` notebook cell, or a RED-phase production notebook edit all bypass every content/path guard. Zero `NotebookEdit` references anywhere in `hooks/`. | Add `NotebookEdit` to the matcher and extract `.tool_input.notebook_path // .tool_input.file_path` in the path-based hooks. | S |

## Tier 1 — Correctness

| # | file:line | issue | fix | effort |
|---|---|---|---|---|
| C1 | `hooks/block-dangerous-git.sh:55` | The global-option strip omits `--exec-path=`/`--config-env=`/`--attr-source=`, so `git --exec-path=/x push --force` bypasses every destructive-git matcher. **Empirically confirmed** (lower reachability than S1 — Claude won't naturally emit these). | Add the three value-taking options (`=` and space forms) to the strip alternation. | S |
| C2 | `hooks/file-protection.sh:151` | A `<<-` heredoc with a TAB-indented closing terminator never closes the scrubber (`$0 == tag` is exact-match), dropping every subsequent line — a real `echo secret > .env` after such a heredoc is missed. Best-effort Bash branch only; the Edit/Write primary path is unaffected. **Confirmed.** | For `<<-` headers, strip leading tabs before the tag comparison. | S |
| C3 | `hooks/hooks.json:5-22` | `block-config-weakening` / `security-pattern-check` / `enforce-tdd-order` have no `Bash` matcher, so `sed -i`/`>>` on an existing `tsconfig.json`, a heredoc-written `eval(`, and RED-phase production writes via shell all bypass them while the equivalent Edit is blocked. | Add a Bash branch (reuse file-protection's write-target extractor) to config-weakening at minimum, or document the asymmetry in HOOKS.md. | M |
| C4 | `hooks/block-dangerous-git.sh:30-33` (+ 5 siblings) | All hard-block data-loss guards fail OPEN for the session when `jq` is absent — a loud one-time message fires, but force-push / `rm -rf .geniro` then go unchecked. For the three data-loss guards, fail-closed matches the role. | Fail closed (exit 2) in the three data-loss guards when jq is missing, or add a grep-only degraded parse. | M |
| C5 | `lib/emit-learning.sh:158-162` | Unknown top-level string fields (e.g. `note`, `entry`) survive into `learnings.jsonl` unredacted — `redact_secrets` only walks summary/body/ext/links, so a secret in a non-canonical key persists verbatim. | Drop non-schema top-level keys at rebuild, or extend the redact walk to all top-level strings except the closed control-plane set. | M |
| C6 | `skills/{plan,implement,review,debug}/SKILL.md` frontmatter | Deep mode requires an internal `Workflow(...)`, but `Workflow` is absent from every `allowed-tools` list — the skills treat that list as the mechanical enforcement layer, so the documented deep path can never fire. | Add `Workflow` to the four skills' `allowed-tools` (and the tracker MCP read tools where used). | S |
| C7 | implement:49-51,293-294 · review:43,47 · debug:30,254 · refactor:353 | **Escalation/terminal-state resume holes (×4).** `phase-2/3-escalated` (implement) are written but absent from the resume rule's matched set; `escalated` (review) is contradictorily classified terminal vs non-terminal; `ship-summary-only` (debug) is declared terminal yet the stall gate enters it with Phase 3 pending; refactor's PRODUCT-DECISION option 1 exits leaving `verify-escalated` with no terminal write. A session compacted in any of these has no resume path or resumes as "complete". | Per skill: add the escalated states to the non-terminal/resume set with "re-surface last AUQ" semantics; keep `phase: ship` during stall-flagged Phase 3; write a terminal after refactor option-1. | S each |
| C8 | refactor:366/490, 481/185 · debug:567-569/128 · onboard:280-284 · investigate:378 · actions:49 | **ACI tool-surface tables forbid tools their own steps require (family of 6).** refactor Phase 3 fix loop needs Edit (omitted); refactor Phase 1 ACI says "no spawns" vs §1.4 spawning codebase-research-agent; debug Phase 0 fires an AUQ + `atomic_state_write` it blocks; onboard omits AskUserQuestion (both phases) + Bash (Phase 2); investigate Phase 3 is Read-only vs its AUQ/state-write/cleanup; actions create-row omits `sed -i`/`rm`/`mv`. | Amend each ACI row to include the tools its steps actually use. | S each |
| C9 | `skills/actions/SKILL.md:411` | The edit-mode auto-validation AUQ offers "Revert to pre-edit version" but no step captures a pre-edit snapshot — an AUQ outcome with no path to fulfill it. | Add a pre-edit `cp` snapshot at Phase 6 Step 2, or drop the revert option. | S |
| C10 | `skills/implement/SKILL.md:568` | The Phase 2 sliding-window overflow marks `deprecated: true` on `learnings.jsonl` "via direct edit" — contradicting the atomic-write contract and the state-helper hook guarding `.geniro/knowledge/` (debug §1.5 mandates the atomic path). | Replace "via direct edit" with debug's atomic-rewrite procedure. | S |
| C11 | `skills/_shared/validate-state-file.md:40-43` | The documented API example captures `rc=$?` inside an `if !` block, where `$?` is always 0 — the per-exit-code recovery routing the helper documents can never fire if copied. | Change to `validate_state_file <path>; rc=$?; if [ "$rc" -ne 0 ]; then …`. | S |
| C12 | `skills/_shared/review-handoff.md:142` | The §2.6 canonical handoff template omits `pr-bot-comments-snapshot:` / `pr-formal-reviews-snapshot:` / `prior-round-summary:` (read by the §7.1 dedup checks) — a Phase 5.1 full-file `atomic_state_write` per this template silently drops the Phase-1-persisted fields its own Post drill consumes. | Add the three producer fields to the §2.6 frontmatter template. | M |
| C13 | `skills/_shared/update-semantic.md:92-99` | The documented rc=11 defer-and-retry pattern stores args as `"$*"` then replays via `eval`, re-splitting every multi-word `--append`/`--replace` value — every deferred write errors or appends garbage. | Store via `printf '%q '`-quoted strings before the eval replay. | S |
| C14 | `skills/review/phase-1-triage-reference.md:108` | Rule 6 runs `git worktree add <path> <CURRENT_BRANCH>` while that branch is checked out in the main worktree — git refuses with "already used by worktree" in exactly the condition (not-in-worktree) under which rule 6 fires. **Empirically confirmed.** | Use `git worktree add --detach <path> <CURRENT_BRANCH>` or `-b review-<slug>`. | S |
| C15 | `skills/plan/validator-checks.md:21` | Validator check #1 requires the Objective be "declarative (not imperative)", but the template's only ✅ example ("Add OAuth login to the customer portal.") is imperative — a spec authored per the template fails the rule. | Drop "not imperative" from the check, or rewrite the template example as declarative. | S |
| C16 | `.claude/skills/analyze-thread/SKILL.md:56,318` · `improve-template/SKILL.md:45` | The repo-local pair's handoff pipeline is broken: both cite plain-text `Branch:`/`Worktree:` headers as "mandatory per the Producer contract" when that contract mandates line-1 YAML frontmatter (so the documented checkpoint fails the very `validate_state_file` the skill later runs), and the analyze-thread → improve-template handoff names a consumer "Step 12" that does not exist in improve-template. | Adopt the helper's T1.5 frontmatter checkpoint shape; add the handoff-consumption step to improve-template (or pass findings as plain `$ARGUMENTS`). | M |

## Tier 2 — Rule violations (structural / hard exclusions)

| # | file:line | issue | fix | effort |
|---|---|---|---|---|
| R1 | _shared→skill-body upward links (×7): finding-tagging.md:11 · root-cause-gate.md:63,74 · review-handoff.md:462,162 · design-doc-detect.md:63 · finding-verification.md:126 · load-custom-instructions.md:103 · (implement:693, implement:283/review:118 reach into `skills/plan/`) | **Reference-graph inversions** — `_shared/` helpers and two SKILL.md files point UP into skill bodies / foreign-skill dirs for runtime contracts (evidence-kinds, the snapshot-field contract, deep-mode aggregation, the spec `workflow_refs[]` schema, the tracker-mutation rule). The worst (`finding-tagging.md` "kinds 2-5") points at a copy whose numbering contradicts canonical `evidence-standard.md`. | Relocate each cited contract into `_shared/` (or restate inline) and have all consumers cite the canonical home. | M each |
| R2 | review:527 · instructions:391 · review:401,608 · implement:95 · tdd-mode-reference.md:36 | **Authoring-process narration in shipped bodies** — "This is the fix for '…'", "predates the spec's enum redesign", "(matches the legacy threshold)", "Deferred to if a cost-aware mode is opted into", "document this so users don't…". Hard exclusion §3. | Delete the narration; state the current rule directly. | S each |
| R3 | `skills/review/SKILL.md:3` | Frontmatter `description:` uses second person ("…or you manually", "gated by your approval") — skill-structure mandates third-person descriptions. | Reword to third person. | S |
| R4 | actions:450-470 ↔ instructions:398-415 · plan-context.md:128 ↔ spec-compliance-criteria.md:37 · severity-calibration.md:119-120 ↔ conventions-criteria.md:299-300 | **Single-source violations** — full lint-rule tables, a prose-fallback emit block (already drifted on the `id:` field), and conventions HIGH/MEDIUM rows duplicated verbatim across two files each. | Pick one canonical home per pair; the other cites it. | M |

## Tier 3 — Staleness & doc drift

The dominant cluster. README / ARCHITECTURE / HOOKS / MIGRATION lag the last two feature waves (regressions + rules-compliance dims, all-survivor verification, 12-phase /plan, cluster gates, config-weakening hook, reflection-agent). Convergence noted where ≥2 reviewers independently flagged.

| # | file:line | issue | convergence |
|---|---|---|---|
| D1 | HOOKS.md:18-32 · README.md:243-250,284 | `block-config-weakening.sh` entirely missing from HOOKS.md table+sections and README safety table; both miss the security-pattern-scan row too; counts stale ("9 hooks" lists 8; "7 safety hooks"). | D2-2, D3-2, D8-7, D2-3, D3-3 (×5) |
| D2 | HOOKS.md:25-27 + script headers | Matcher documented `Edit\|Write`; hooks.json registers `Edit\|Write\|MultiEdit`; the tdd-order/security-scan script header comments carry the same stale claim. | D2-16, D8-8 (×2) |
| D3 | README.md:269 · MIGRATION.md:439 · improve-template:19 | Agent count stale — 7 agents ship; docs say "6"/"2 current agents"/"2 agents post-rationalization" and omit reflection-agent. | D2-4, D3-10, D4b-10, D2-14, D3-18 (×5) |
| D4 | README.md:119 | /plan described as "10-phase loop" — 12 phases now (omits problem-discovery `--prd` 0.5 + spec-challenge 7.5). | D2-5, D3-9 (×2) |
| D5 | ARCHITECTURE.md:106 | M6 mandatory-spawn list omits the live `rules-compliance` conditional dimension. | D2-9, D3-6 (×2) |
| D6 | ARCHITECTURE.md:21 | Recovery AUQ shows 3 options; canonical template has 4 (`update-worktree-path` missing). | D2-10, D3-20 (×2) |
| D7 | ARCHITECTURE.md:218 | "SKILL.md must stay under 500 lines" contradicts skill-structure's target-not-cap rule and reality (debug at 700). | D2-12, D3-8 (×2) |
| D8 | HOOKS.md:43 | file-protection "Protects" list shows 3 lockfiles; the script blocks 10. | D2-15, D3-14 (×2) |
| D9 | README.md:111 · setup §3.3 · state-tier-spec.md:74 | `.geniro/docs/` documented as a `/setup` spin-out target with a ">40 LOC" split methodology; no skill writes it — producer-less path + nonexistent methodology. | D2-6, D3-12, D2-7, D3-13 (×4) |
| D10 | ARCHITECTURE.md:82 + README.md:82 | UI-preview spawn described as `model="haiku"`; the gate file says OMIT `model=` (inherit). The actual haiku carve-out is the implement-reference doc-patcher. | D2-1 |
| D11 | ARCHITECTURE.md:9 | "Every state write … enforced by PreToolUse hook" — the hook is warn-mode, and two files are mktemp+mv tier-exempt. | D2-11 |
| D12 | ARCHITECTURE.md:166 | /setup verifier "runs an 8-checklist"; verification-checks.md defines 3 checks. | D2-8 |
| D13 | ARCHITECTURE.md:189 | M10c "any network/curl must be `risk_class: high`" contradicts the actions Q5 ladder (external reads = medium). | D3-7 |
| D14 | MIGRATION.md:106,154 | `m6-v2` entry: HIGHs-only verify + 0-100 confidence; current = all CRITICAL/HIGH/MEDIUM + 1-5 scale; spawn list 7+3 vs current 8+4. | D3-4, D3-5 |
| D15 | MIGRATION.md:138-148 | /plan migration entry describes the superseded per-section-AUQ-preview pattern; /update + /setup actively walk it and relay it to users. | D3-1 |
| D16 | HOOKS.md:180 · README.md:70 · README.md:268 · CONTRIBUTING.md:18 | Cites a nonexistent auto-format hook; "session summaries" (non-canonical per MIGRATION); marketplace.json mislabeled "11-skill inventory"; "installing the template" (now a plugin). | D3-15, D3-19, D2-13, D2-20, D3-21 |
| D17 | analyze-thread/checks-reference.md:64-65 · SKILL.md:380,157,12 · improve-template:138 | Misattributed rule source (skill-prose vs skill-structure); nonexistent `§"User-facing narration"` + `§"Mechanical reference"` anchors; "32-item taxonomy" (36 checks exist); "354KB" ARCHITECTURE.md (25KB). | D3-16, D3-17, D5aB-19, D4b-9 |
| D18 | spec-challenge.md:45 · state-tier-spec.md:53,116,55 · review-handoff.md:99 · phase-4-3-test-gate-reference.md:86 | Lifecycle/registry seams: `.spec-challenge-out.md` + `.research-*` in no cleanup contract; T1 heading on a T1.5 `approvals` array; T1.5 "survives Ship" vs the MUST-delete contract; review-handoff cites a nonexistent state-tier-spec §T2 example; a root-level adversarial output that fits no tier layout. | D5aB-9,10,11,12,13,16 + D8-9 |

## Tier 4 — Maintainability

**Over-complication (D6) — dominant shape is within-file restatement (same rationale 2-4× across role statement / phase body / anti-rationalization row / Definition-of-Done):**
- DoD lists restate every body step instead of exit gates — debug (26 boxes), plan-loop (20), refactor (19); review:604 documents the correct ~8-gate shape to copy.
- Rationale repeated N× in one file: refactor PRODUCT-DECISION (4×), implement L4-load (3×), debug §3.3 emit re-list (3×), review spawn-batch/no-trim (3×), refactor inline-not-subagent (2×), implement invariant #10 dup of #8.
- Two cross-file verbatim procedure copies violating the project's own single-source rule: the recurring-pattern rule-capture offer (debug ↔ refactor) and the producer-preserving round-trip handoff write (~200 words, implement ↔ debug).
- **Clean MOVE candidates** for the ceiling files (content move, not cut): debug §1.5 emit payload + §3.1 findings template → debug-state-reference (~40 lines); implement Step 0c AUQ YAML + 0f table → implement-reference (~60); setup state-file templates → a setup reference (~60).

**Magic numbers (D7) — dominant shape is dual-canonical homes (no contradicting values found):**
- review §4.1 gate numerics live in full in two files; two referrers name *different* files "the single source" → pick severity-calibration §5, others cite.
- L2 score-formula constants restated in `query-learnings.md` doc vs `lib/score-formula.sh` header, no cross-pointer.
- Tri-homed memory thresholds with no designated home: archive-stale criteria (0.1/180d/0), `retry_failure_sequence` window (3 latest), `recurrence_count >= 3`, 200-entry dedup window, the 8-item dropped-skill list, the ≤250-char description cap (7 sites).
- debug stall-gate "5 inconclusive" / "2 attempts" lack adjacent rationale.

**Test-coverage gaps (D8):** `lib/branch-slug.sh` (no direct suite — a divergent slug silently disables the TDD gate + state resume), `hooks/backpressure.sh` (no suite — `eval` runner), both Node scripts (no JS test infra; check-update writes a cache file untested).

**Shell hardening edges (D8/D5b):** `update-semantic.sh` O_EXCL lock has no age-based stale reclaim (SIGKILL wedges all L3 writes); file-protection's quoted-redirect `> ".env"` is a documented miss; block-geniro-deletion never scrubs quoted literals so benign greps mentioning a guarded pattern hard-block (observed live during this audit); `block-dangerous-git` doesn't guard remote-branch deletion (`git push --delete`).

**Other:** severity-calibration §5 pseudo-code admits a MEDIUM via any signal while its own prose restricts MEDIUM to signal #2; the per-skill phase-enum table in instructions duplicates 7 skills' state machines.

## Tier 5 — Cosmetic

- **Title-Case section headings** across debug/review/refactor SKILL.md, all 7 agents, and many `_shared/` files (soft preference is sentence case) — fix on next touch, no dedicated sweep.
- **Terminology mix** `dim`/`dims` vs `dimension` in review prose (D2-21, D4a-15 ×2); reserve `dim` for slug/field identifiers.
- **Caps in normal prose** (yellow flag): debug MUST/NEVER at several sites; `load-custom-reviewers.md:87` ALWAYS without reasoning. Reframe with the inline why.
- **User-facing-string leaks:** step titles "Refresh L4 instructions" (implement:598, review:235); `$ARGUMENTS` in implement AUQ text; "PLAN CONTEXT"/"checks 10/11" in the spec-compliance question; "sub-AUQ"/"Terminal aborted" in plan AUQ option descriptions; first-person plural in improve-template spawn prompts; `spawn-agent.md`/`review-handoff.md` positional-anchor + agent-count staleness.
- **"Refresh" label with `MODE: initial-load`** at investigate:81 / onboard:101 (label/parameter mismatch).

## Filtered (dropped or merged — transparency)

- **SC2120 (`lib/validate-state-file.sh:46`) and SC2164 (`tests/memory/repo-root.sh:34`)** — adjudicated behaviorally benign: the `_geniro_sha256` fallback's only call site pipes via stdin (no-arg `shasum` reads stdin correctly); the test's unguarded `cd` self-corrects via absolute re-cd each case. Not findings.
- **~30 doc-drift rows collapsed** into the D1-D18 grouped rows above (e.g. the 5 separate "agent count" sites → D3; the config-weakening-missing sites → D1).
- **D5b-3 (heredoc) reviewer-tiered T0 → recalibrated T1** (C2): the Bash branch is documented best-effort and the primary Edit/Write guard is unaffected, so it is a narrow behavioral gap, not a primary-path loss vector.
- **Numbers that merely look duplicated** (600s lock age in two lock impls, distinct ≤4K char caps for different outputs, AUQ 4-option cap sites that correctly cite the cap-extension home) — endorsed-pattern false positives, not flagged.

---

## Single highest-value fix

**S1 — the `git -C` bypass in `block-geniro-deletion.sh`.** The hardening commit that closed `git -C` evasion on `block-dangerous-git.sh` did not apply the same one-line strip to the `.geniro/` deletion guard, leaving its two subcommand guards (`worktree remove`, `git add -f`) bypassable through the everyday `git -C` flag — and `git add -f` on `.geniro/` is the documented real-incident data-loss vector (Cursor SCM "Discard All" wiping force-added `.geniro/actions/*.md`). It is a one-paragraph fix (port the `sed` block already proven in the sibling guard) that closes a confirmed hole in the plugin's most important data-protection layer.
