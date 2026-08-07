# Audit dimensions reference

Per-dimension checklists for `/audit-plugin`. Each dimension defines its file scope, what to look for, how to check it, and how to map findings to severity tiers. The orchestrator pastes ONE dimension section into each reviewer's prompt — reviewers never read this file themselves.

## Contents

- Reviewer spawn template
- Run setup
- Fix-round execution
- Ledger contract
- Deletion gate
- Severity tiers (shared output classification)
- Finding output contract (shared reviewer schema)
- D1 — Mechanical hygiene (deterministic, no LLM)
- D2 — Cross-file consistency
- D3 — Stale rules & dead references
- D4 — Authoring-rules compliance
- D5 — Logic & syntax correctness
- D6 — Over-complication & instruction bloat
- D7 — Magic numbers & duplicated constants
- D8 — Safety & test coverage
- D9 — Wiring completeness (declared vs. wired)
- Do-not-flag list (endorsed patterns)

---

## Reviewer spawn template

Pasted by the orchestrator at Phase 2. Every slot is filled before the spawn — a reviewer that has to discover its own rubric will invent one.

```
Agent(subagent_type="general-purpose", prompt="""
## Task: Plugin audit — dimension D<N> (<name>)

You are one reviewer in a multi-dimension audit of this Claude Code plugin repo.
Review ONLY your dimension; other dimensions are covered by parallel reviewers.

### Your rubric
{{paste the full D<N> section from dimensions-reference.md}}

### Severity tiers and output contract
{{paste §Severity tiers from dimensions-reference.md + §Finding output contract from ${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md}}

### Do-not-flag list
{{paste §Do-not-flag list}}

### Your file scope
{{inventory subset for this dimension, from Phase 0}}

### Mechanical pre-pass context
{{battery summary; for D3 additionally: the candidate lists; for D7 additionally: the seed-grep output}}

### Procedure
1. Load your markdown scope in FULL via `scripts/dump-md.sh <scope paths>` and survey from that — grep hits miss reworded coverage; grep only to pinpoint an exact known string. Read non-markdown files directly.
2. Verify each candidate finding by Reading the exact cited lines — your `evidence` column must be a verbatim quote.
3. Return ONLY the findings table per the output contract plus a 2-3 sentence per-dimension verdict ("healthy / debt concentrated in X").
Do NOT fix anything. Do NOT review outside your dimension. Report only.
""", description="Audit: D<N> <name>")
```

Dimension-specific notes:
- **D4 (rules compliance):** instruct the reviewer to load the three `.claude/rules/*.md` files first as its rubric source (`scripts/dump-md.sh .claude/rules` — they're too long to paste).
- **D5:** two spawns — D5a scope `skills/ agents/ .claude/skills/`, D5b scope `hooks/ lib/ tests/`.
- **D6:** paste the no-execution-site and over-constraint candidate lists from the D1 battery into the `### Mechanical pre-pass context` slot, as D3 and D7 already get theirs.
- **D8:** paste the dead-matcher candidates from the D1 activation-reachability check.
- **D9:** paste the D1 declaration inventory. Also paste `skills/_shared/load-custom-instructions.md` §Producer contract — check 1 adjudicates against the block set that file defines, and a reviewer left to recall the set will check the three it remembers.
- **Sharding:** if a dimension's markdown scope exceeds ~15K lines (full-audit D4/D6 typically do), split into shard A (`skills/*/SKILL.md` + `agents/`) and shard B (the remainder of the dimension's scope — everything NOT in shard A, so no file falls between two positive globs), same prompt, both in the batch.

## Run setup

Read at Phase 0, alongside this file's rubric sections.

**Inventory** — record file counts + line totals in the state checkpoint:

- Shipped: `skills/**/*.md`, `agents/*.md`, `hooks/*` + `hooks/hooks.json`, `lib/*.sh`, `settings.json`, `scripts/*.sh`.
- Dual-runtime port: `cursor/**` (generated `cursor/agents/*.md`, `cursor/hooks.json`, `cursor/hooks/claude-hook-shim.sh`, `cursor/README.md`) + `.cursor-plugin/plugin.json`. The shim is a guard-carrying surface — it translates every wired hook's block signal into Cursor's deny response, so it belongs in the safety scope, not only the consistency scope.
- Repo-local: `.claude/rules/*.md`, `.claude/skills/**/*.md`.
- Docs (drift targets): `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `MIGRATION.md`, `CONTRIBUTING.md`.
- Tests: `tests/**` (coverage map input for D8). `design/` and `evals/` are out of scope unless `$ARGUMENTS` names them.

**State checkpoint** — write `.geniro/state/audit-plugin/<slug>/state.md` (producer `audit-plugin` — not in the handoff helper's enumerated producer set, but adopting its contract shape verbatim) via `atomic_state_write` (source `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — a direct `Write` to a `.geniro/state/` path trips the state-helper hook). Slug and the full slug-scoped T1.5 frontmatter per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/within-skill-state-handoff.md` §Slug rules and §Producer contract — the field set, the line-1 rule, and the `validate_state_file` consequences live there. Each checkpoint records: phase completed, scope, dimensions selected, finding counts.

## Fix-round execution

Read at Phase 5 when a fix path is approved — you already have this file open from Phase 2. The disjoint-scope grouping, the ownership assert, and the 1-round budget are in SKILL.md §Phase 5. The shared discipline — the three things that reliably happen after fix agents spawn, dead-agent ground-truthing, and the verification order — is canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` §Fix-round discipline. Plugin-repo specifics:

- **Once-per-round integration steps:** regenerating `cursor/agents/` from edited `agents/*.md` sources, accepting a size baseline, and completing a deletion across the files that referenced the deleted thing.
- **Routing:** large structural items (multi-file refactors, reference-graph re-homing) are better routed to `/improve-template` with the finding rows as `$ARGUMENTS`; say so instead of attempting them inline.

## Ledger contract

Read at Phase 0 with the rest of this file, and still here at Phase 5 when decisions are written back.

`design/audit-ledger.tsv` is tracked. One row per finding any audit has raised: `fingerprint`, `file`, `class`, `tier`, `disposition`, `runs`, `note`. API in `${CLAUDE_PLUGIN_ROOT}/lib/audit-ledger.sh`.

**Why it exists.** Seven whole-repo rounds produced 138, 121, 101, 87 and 130 findings and never trended down. Every round began blind: the report goes to gitignored `design/scratch/` and each run gets a fresh container, so no run read its predecessor's decisions. The only durable memory was the do-not-flag list, which grew from 11 entries to 16 while roughly 700 findings passed through it. A finding rejected in round 3 came back identically in round 4.

**The key.** `ledger_fingerprint` hashes 100 characters of context from the cited line — whitespace-insensitive, spanning line boundaries, line number not an input. Inserting 200 lines above a finding leaves its key alone; rewriting the passage moves it and the finding correctly reopens. `class` is the other half: an LLM reviewer has no stable rule id, so a short slug chosen once by a person (`dedup`, `stale-ref`, `magic-number`, `caps-emphasis`) supplies what the machine cannot derive. Reuse a slug verbatim across rounds or its history splits in two.

**Dispositions.** `fixed` for what was applied — kept as history so a return is visibly a REGRESSION. `rejected` for what the user declined or you filtered. `accepted` for a defect the repo knowingly carries. A `rejected` row without a note is refused by the helper: a suppression nobody can audit is how a ledger rots into a blanket that hides real defects.

**Pruning is mechanical.** `ledger_prune` drops rows whose file is gone, and nothing else. Re-opening a decision means a new finding in a new run, never an edit to an old row.

**The 3-run bar (Phase 3 step 4b), and what it cost not to have it.** Across those seven rounds this pipeline wrote 8,782 lines into hooks, `lib/` and tests and lost 1,231 — 86% still standing — while writing 6,055 lines of prose and losing 5,722. Prose churned 11,777 lines to net 333. The surviving half is the half a test pinned, which is also why a code finding closes with a test rather than a fix. Prose has no such pin, so its only oracle is agreement between independent runs; one reviewer's taste on one run is not evidence, and acting on it is precisely what manufactured the next round's findings.

## Deletion gate

Read at Phase 5 alongside §Fix-round execution, and reachable from this file rather than SKILL.md on purpose: Phase 5 arrives late in a long run, which is exactly when a compaction has dropped SKILL.md's tail, and this file is re-read there anyway. SKILL.md's no-blanket-deletion invariant — a mechanic is never deleted on a blanket approval — survives in the spine and is what sends you here.

Walk the mechanism-level D6 proposals one at a time. Per proposal, render the explanation as its own chat message and then fire a lean `AskUserQuestion`, per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering, in the visual language of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md`.

The render carries the four things the finding had to establish, plus what the user is left with:

- **What it is and where it lives** — the mechanic named in plain terms, with its path.
- **The case it exists for, and how often that case arises** — the reason someone built it, not a guess at their intent.
- **What it costs per run** — the measured figure, naming the profile it came from.
- **What covers that ground afterwards** — the other mechanism that catches the same case, or a plain statement that nothing will and the run will not know.
- **Whether it stands alone** — or only holds together with another proposal in this set, which the user has to decide as one.
- **What a run looks like once it is gone** — the observable difference, so the decision is about behavior rather than about a file.

Options: "Keep it" / "Delete it" / "Shrink it instead" / "Explain further". Mark whichever of keep-or-delete the evidence actually supports as `(Recommended)`, per that helper's §Recommended-label policy — a gate that recommends deletion by default spends the user's attention to obtain a signature, which is the same net-negative shape the mechanism-level check exists to find. "Shrink it instead" is the honest middle when the cost is real but the ground is still needed; it converts the finding into a text-level one and it re-enters the fix path as an edit.

Record the ones the user keeps in the report's subtraction sweep as considered-and-kept, with the reason. That is what stops the next audit re-proposing them, and it is the half of the sweep that compounds.

## Severity tiers (shared output classification)

Dimensions are review lenses; tiers classify the output. Every finding gets exactly one tier.

| Tier | Name | Admits |
|---|---|---|
| T0 | Safety | Hook bypass holes, secret-leak paths, data-loss vectors, fail-open where fail-closed is required |
| T1 | Correctness | Logic bugs, gates that can never fire, producer/consumer schema mismatch, shell bugs with behavioral impact, untested live data-mutating code |
| T2 | Rule violations | Breaches of `.claude/rules/*` hard exclusions or hard structural rules (description length past `.claude/rules/skill-structure.md` §Frontmatter hygiene, reference-graph inversion, non-English, dangling refs) |
| T3 | Staleness & drift | Dead references, doc-vs-reality drift, stale conditionals, orphaned files |
| T4 | Maintainability | Duplicated single-source content, unexplained or multi-homed constants, over-complication, anti-rationalization dead weight, latent-but-unreachable defects, test-coverage-map gaps |
| T5 | Cosmetic | caps-without-reasoning, provenance citations. Heading case and terminology are NOT in this tier: `lint-prose-and-links.sh` decides heading case against a named allowlist, and terminology was measured to have no true positives here — every Title-Case heading in this corpus is a contract token, and `dim` is settled vocabulary, not drift from `dimension` |

## Finding output contract (shared reviewer schema)

The table schema, row cap, and inadmissibility rule are canonical in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/audit-pipeline.md` §Finding output contract — paste that section into reviewer prompts alongside §Severity tiers above.

---

## D1 — Mechanical hygiene (deterministic, no LLM)

**Scope:** whole repo. **Method:** Bash only — the orchestrator runs this battery directly in Phase 1; no reviewer spawn.

| Check | Command / procedure | Tier on failure |
|---|---|---|
| Test suites | `bash tests/run-all.sh`, run through the test-runner agent (structured pass/fail + failure snippets) | T1 |
| Authoring lint | `bash tests/authoring/lint-skills.sh` (hard fails → findings; warnings → advisory findings) | T2 / T4 |
| ShellCheck | Preflight `command -v shellcheck` (absent → "skipped: tool unavailable", never a finding). Then `find lib hooks tests evals cursor scripts -name '*.sh' -exec shellcheck -S error {} +` (errors → T1); re-run `-S warning` (advisory → T4). Keep this path set in lockstep with `.github/workflows/ci.yml` — a path linted here but not in CI (or the reverse) is itself a finding. `find`, not `tests/**/*.sh` — `**` needs globstar and silently misses top-level files without it | T1 / T4 |
| Deleted-skill refs | `grep -rnE 'geniro:(brainstorm|decompose|follow-up|deep-simplify|features|learnings|cleanup|vendor)' skills/ agents/ hooks/ lib/ cursor/ scripts/` — matches are CANDIDATES for D3 adjudication (README.md's "Skills deleted" table is a legitimate mention) | feed D3 |
| hooks.json wiring | `bash tests/authoring/lint-hook-wiring.sh` — every `hooks/*.sh` + `hooks/*.js` wired or declared unwired, the Claude-minus-Cursor gap matching its declaration, and every prose count of that gap stating the real number | T1 |
| Canonical homes | `bash tests/authoring/lint-canonical-homes.sh` — every "X is canonical in FILE §SECTION" declaration resolves to a real file and a real heading | T2 |
| Links & heading case | `bash tests/authoring/lint-prose-and-links.sh` — local markdown links resolve (hard); Title-Case headings outside the allowlist (advisory) | T3 / T5 |
| Frontmatter fields | Every `skills/*/SKILL.md` has `name`, `description`, `context`, `model`, `allowed-tools`, `argument-hint`; description length per `.claude/rules/skill-structure.md` §Frontmatter hygiene. Every `agents/*.md` declares `maxTurns` per that file's §`maxTurns` on agent frontmatter — an unset cap defaults to 10 turns outside interactive Claude Code, which truncates a reasoning agent at its emit step; `agents/*-reference.md` companions are exempt, carrying no agent frontmatter by design | T2 |
| Activation reachability | Each `.claude/rules/*.md` `paths:` glob matches at least one tracked file, evaluated under **gitignore `**` semantics** (a trailing `dir/**/*.ext` matches files directly in `dir/`, no subdirectory required) — NOT `git ls-files <pathspec>`, whose pathspec `**` semantics require an intervening path segment and report a false zero-match on a subdirectory-free directory (measured on `agents/**/*.md`). Each `hooks.json` matcher names tools and events that exist in Claude Code's surface — a matcher that can never fire is a guard that silently never runs | T1 (zero-match `paths:` glob under gitignore semantics); dead matchers → CANDIDATES, feed D8 |
| File-size guidelines | Word counts per the rule in `tests/authoring/lint-skills.sh` §words_in (`awk '{w+=NF}'`, never `wc -w` — that one's answer changes with the locale): budgets per `.claude/rules/skill-structure.md` §File-size limits (front-load budget for SKILL.md, whole-file guideline, and the `agents/*.md` cap). All advisory — `tests/authoring/lint-skills.sh` warns only when a SKILL.md grows past its recorded size in `tests/authoring/skill-size-baseline.txt`, and then names the heading its compaction boundary falls at, so a silent run means every size is one a maintainer already accepted. Flag WHAT sits below the boundary, never the number itself | T4 |
| TOC presence | Same word-count rule: any runtime-Read file (`skills/**/*-reference.md`, `_shared/*.md`) past the threshold `.claude/rules/skill-structure.md` §Reference graph sets, with no "Contents"/"Sections" block near the top. `agents/*.md` are exempt there — injected, not Read | T4 |
| Orphan candidates | For each `skills/_shared/*.md`, `lib/*.sh`, `agents/*.md`: grep the repo for its basename; zero inbound references → CANDIDATE for D3 adjudication | feed D3 |
| No-execution-site candidates | Same basenames, but the shape a zero-reference test cannot see: referrers exist yet **none is an execution site** — every hit is another `_shared/` peer, and no `skills/*/SKILL.md`, phase file, or `agents/*.md` names it. A helper two peers cite but no skill ever runs is dead with a non-zero reference count. Also flag a helper whose referrers disagree about where it fires | feed D6 |
| Over-constraint candidates | The authoring lint's INFO lines already name every SKILL.md over the front-load budget and the heading its compaction boundary falls at — paste them; they are check-10 candidates. Plus `grep -c` per shipped file for blanket prohibitions in normal prose (`NEVER` / `ALWAYS` / `MUST` outside a table row) — density, not any single hit, is the check-11 signal | feed D6 |
| Declaration inventory | For D9: enumerate each declaration kind so the reviewer adjudicates a list instead of running its own search. Per skill, the loader call sites (`SKILL_SLUG` / `LOAD_TIER` / `MODE`) and their initial-load-vs-refresh split; the phases-overview entries against the `## PHASE` headings and the phase-body files those pointers name; the `AskUserQuestion` site count; the `{{slot}}` names each spawn template declares; and per instruction-block heading, the files naming it. Emit each as a location list, never a count — a count cannot be adjudicated, and every entry here needs classifying as author / validate / parse / execute before it is a gap | feed D9 |

Record full battery output to the state checkpoint. Machine findings are pre-verified (no Phase 3 re-read needed); candidate lists feed the relevant reviewer prompts.

## D2 — Cross-file consistency

**Scope:** `CLAUDE.md`, `README.md`, `HOOKS.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `MIGRATION.md`, `skills/`, `agents/`, `hooks/` (check 1 compares doc claims against actual script matchers), `lib/` (check 4 compares helper contracts against the scripts). **Method:** LLM reviewer, grep-grounded.

Checks:
1. **Docs-vs-reality drift.** CLAUDE.md skills table, README, HOOKS.md, ARCHITECTURE.md, and CONTRIBUTING.md claims vs actual skill/hook/helper behavior: listed skills exist, described flags/phases/paths match the SKILL.md body, hook descriptions match the script's actual matchers and bypass IDs, design rationale cited from ARCHITECTURE.md still matches the code that cites it.
2. **Description-vs-body drift.** Each SKILL.md frontmatter `description:` vs what the body actually does (flags, phases, outputs).
3. **Schema lockstep.** For every state-file / handoff field a producer writes (per `skills/_shared/state-tier-spec.md`), confirm consumers read the same field name and shape; flag fields written-but-never-read or read-but-never-written. Hit count carries no signal here — a written field always has hits, so classify each as a write, a read, or a schema declaration and report when none is a read (or none is a write). Name both remedies and say which is cheaper: an unwired producer is as often a missing feature as it is dead weight.
4. **Helper contract drift.** For each `_shared/*.md` helper and `lib/*.sh` script: do callers pass the slots / flags / MODE values the contract defines? Do cited exit codes match the script?
5. **Single-source violations.** Pseudo-code blocks, slot tables, or schema definitions duplicated across ≥2 files (the rule: one source, others cite it).
6. **Spawn-site consistency.** Every plugin-agent spawn follows the `spawn-agent.md` ladder and the OMIT-`model=` rule for carve-out agents; flag sites that contradict the skill's own tiering table.
7. **Terminology consistency** within each file (one term per concept, per `.claude/rules/skill-prose.md` §Terminology consistency).

Tier mapping: schema mismatch with behavioral impact → T1; doc drift / duplication → T3 / T4; terminology → T5.

## D3 — Stale rules & dead references

**Scope:** `skills/`, `agents/`, `.claude/rules/`, `.claude/skills/`, `cursor/`, `scripts/`, top-level docs. **Method:** LLM reviewer seeded with D1 candidate lists. Where a reference is dead, check git history for a rename before writing the fix — repointing to the survivor beats deleting the mention.

Checks:
1. **Deleted-skill references** outside the documented replacement tables (adjudicate D1 candidates).
2. **Dangling section anchors — the undecidable half only.** A `§` sitting next to a file path is decided mechanically: `lint-canonical-homes.sh` hard-fails a canonical declaration whose file or heading is gone, and `lint-skills.sh` check 10 ratchets the rest. What is left for a reader is the BARE anchor, whose binding is not mechanically recoverable — it may name a section in the citing file, in a file named a paragraph earlier, or in none. Adjudicate those; do not re-scan what the lints already decided.
3. **Dropped phase/step names.** References to phases or steps that were renamed or removed (grep the referenced skill for the phase name). Read each hit rather than counting it — a hit that only *documents the removal* is not evidence the name is still live.
4. **Stale conditionals.** "when X ships" / "once Y lands" where X/Y already exists; "reserved for future" hooks that are now live.
5. **Orphans.** Adjudicate D1 orphan candidates: a `_shared` helper, lib script, or agent with zero inbound references is dead weight (or its callers reference it by a wrong name — which is a T1 instead).
6. **Stale rule files.** `.claude/rules/*` migration-audit sections describing work already completed; rules citing files that moved.
7. **MIGRATION.md / HOOKS.md entries** describing behavior the current code no longer has.

Tier mapping: wrong-name reference breaking a runtime lookup → T1; everything else → T3.

## D4 — Authoring-rules compliance

**Scope:** `skills/**/*.md`, `agents/*.md` (shipped files — the rules bind these; `.claude/skills/` is exempt from shipping rules but check it for the prose rules), plus `.claude/rules/*.md` and `CLAUDE.md` for check 4, the one rule that binds those two paths. **Method:** LLM reviewer; instruct it to read every `.claude/rules/*.md` file first and apply them as the rubric.

Checks (the rules files are the source of truth — these are pointers, not restatements):
1. **Hard exclusions** (`skill-authoring.md`): plugin-author-internal references, authoring-process narration, informational noise, out-of-scope content, non-English.
2. **Prose rules** (`skill-prose.md`): caps-MUST/NEVER/ALWAYS outside anti-rationalization tables; menu-of-options paragraphs; restatement summaries; mixed point-of-view; load-bearing invariants placed past the compaction re-attach boundary (§Rule placement); fresh-user test on every user-facing string (step titles, AUQ text, narration templates).
3. **Structure rules** (`skill-structure.md`): section ordering; frontmatter description format (third person, "Use when", no XML); anti-rationalization tables within the row cap with reasoning in the right cell; reference-graph depth within its hop limit and no upward links from `_shared/` into skill bodies for runtime instructions; no line-number cross-refs. Also **reference class** (§Reference classes): prose carrying taste a verifier could evaluate one criterion at a time wants to be a rubric; prose stating a condition a command could decide wants to be an executable check or a failing test; prose describing a file's conventions wants to be that file, passed as an exemplar. Flag the mismatch, not every prose reference — prose is the default, just not the only option.

4. **Rule-file rules** (`rule-writing.md`, which scopes itself to `.claude/rules/**` and `CLAUDE.md`): those files carry the instruction, the reason only where the model would rationalize around it, and exact contract values — not the case assembled for a human reviewer. D6 check 14 owns the same split everywhere else; this row is the pointer for the two paths no shipping rule reaches.

Tier mapping: hard exclusions / hard structure breaches → T2; prose-guideline breaches → T5 (or T4 when they carry recurring token cost, e.g. restatement blocks).

## D5 — Logic & syntax correctness

**Scope split:** 5a (markdown logic) covers `skills/`, `agents/`, `.claude/skills/`; 5b (shell logic) covers `hooks/`, `lib/`, `tests/`, `cursor/hooks/`, `scripts/`. Spawn as two reviewers. **Method:** LLM reviewers; every claim must survive a re-read of the cited code.

5a checks (markdown):
1. **Contradictions.** Phase A states X, phase B assumes not-X; an invariant the steps violate; a budget table disagreeing with the step that enforces it.
2. **Unfireable gates.** Conditions comparing against fields no schema carries; gates whose trigger can never occur; branches conditioned on a flag, mode, or option the skill no longer ships (check `argument-hint` and the modifier table, not only the body); gates an earlier gate always pre-empts; AUQ flows with no path to one of their documented outcomes.
3. **Tool-surface mismatches.** Body instructs using a tool absent from `allowed-tools`; AskUserQuestion specs exceeding 4 options; spawn prompts using slots never filled.
4. **State-machine holes.** `phase:`/`status:` enum values written but never read (or read but never written); terminal states unhandled by resume logic.
5. **Broken procedures.** Steps referencing outputs of steps that don't produce them; counters that reset on compaction while the skill claims compaction-safety.
6. **Turn-completion seams.** A step that emits content and then owes a tool call — a gate render followed by its question, a spawn batch followed by its collection, an echo attesting to a Read — where the wording lets the run come to rest between the two. The underlying model has a documented early-stopping failure mode on exactly this seam: it ends on a statement of intent and the promised call never happens, which reads as a completed step from every angle except the user's. Flag a step whose obligation spans a turn boundary with nothing closing it, and one that states intent as its own completion criterion. The canonical closure and its recovery are in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Turn-completion guard and `${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md` — flag the site that lacks it, never the contract.

5b checks (shell):
1. **Quoting & word-splitting** on user-controlled or file-derived values; unquoted globs.
2. **Regex correctness** in guard hooks — false negatives (bypassable patterns, line-by-line matching of multi-line constructs) and false positives (legit commands blocked).
3. **Exit-code semantics** — hooks must exit 2 to block / 0 to allow per their contract; helpers' documented rc values match reality.
4. **Trap/lock hygiene** — locks released on SIGINT/SIGTERM; mktemp cleaned; partial writes impossible (atomic mv).
5. **Portability** — BSD/GNU divergence (`grep -P`, `stat -c`, `sed -i`, `tac`); `#!/usr/bin/env bash`.
6. **Input validation** — env-var overrides sanitized; malformed JSON stdin handled (fail-open vs fail-closed chosen deliberately and matching the hook's safety role).

Tier mapping: bypassable guard / data-loss path → T0; behavioral bug → T1; latent-but-unreachable → T4.

## D6 — Over-complication & instruction bloat

**Scope:** every instruction surface in the repo — `skills/` (bodies, references, and `_shared/` helpers), `agents/`, `.claude/skills/`, `.claude/rules/`, and `CLAUDE.md`. The last three ship to nobody, which is exactly why they accumulate: they load on every plugin-editing session, the rules files are additionally pasted verbatim into every reviewer prompt this skill spawns, and no other dimension sweeps them for bloat. **Runs on every audit** — full, path-scoped, single-dimension, or `--quick` — per SKILL.md shared invariant 5; on a scoped run it inherits the run's scope, and on `--quick` the orchestrator sweeps inline. **Method:** LLM reviewer. The goal is REMOVAL/COMPRESSION candidates — every finding proposes one concrete action: delete, shorten, merge, move to a sibling reference file, or convert a deterministic constraint to a hook/script.

Apply the per-line test to every candidate: "would removing this make Claude err?" If not, it is weight without payload. For prohibitive, edge-case and sequencing text the test has to name the case — a guard's removal never fails the happy path, so "the run worked without it" is evidence about the path that ran, not about the text. Then apply it a second way, which is where this dimension's largest wins are: "would replacing this rule with a criterion, or this example with a better-designed interface, make Claude err?" A rule can be unique, correct and still cost more than it buys — checks 11 and 12 carry that half, check 13 carries it up a level to whole mechanics, and check 14 carries it sideways, to the argument riding along with a rule that deserves to stay. Target signal density, not raw size (`.claude/rules/skill-prose.md` §Token budget awareness): what degrades rule-following is how many plausible-but-inapplicable rules the model must adjudicate between, not the volume of text, so a near-duplicate or a drifted restatement costs far more than its word count. Where a rule is load-bearing for one kind of task only, prefer scoping it to that work over deleting it.

**There is a ceiling on the proposal, not only a bar per candidate.** A proposal that would take most of a rule-dense file is out of range however well the remainder reads: constraint compliance degrades faster than knowledge retention past the reduction ceiling, so the loss surfaces as an unfollowed rule that no re-read of the shortened file can show. The ceiling, the measurement, and its source live in `.claude/rules/skill-prose.md` §Token budget awareness.

Checks:
1. **Restatements.** Same rationale stated ≥2× within one file; "in other words" summaries; rule text duplicating an anti-rationalization row; parallel tables sharing one schema, which read as a single table with one more column.
2. **Hedges** without a condition ("may or may not", "depending on the situation").
3. **Collapsible steps.** Adjacent steps that always run together with no decision between them; sub-step trees deeper than the decision structure warrants.
4. **Anti-rationalization rows carrying no live rationalization.** A row whose left cell names reasoning the current design no longer permits the model to reach. Rows are the densest carrier of dead text, and the easiest to over-condemn — apply check 12's bar, including its carve-out: a failure mode absent from current code is what a working guardrail looks like, not evidence the row is spent.
5. **Example & option overload.** Near-identical examples teaching one pattern, or more per concept than `.claude/rules/skill-prose.md` §"Examples — diverse and canonical" allows (that file owns the count); option lists offering several choices with no stated default → collapse to one default + one escape hatch. This check owns example *redundancy*; an example that constrains the solution space is check 11.
6. **Model-known instruction.** Text re-explaining standard tool behavior or general competence the model already has ("read before editing", "write clean code") — delete, or convert a hard constraint to a hook. This is the per-line test's most common failure.
7. **Over-specified procedure.** Instructions narrating what the model would do anyway — trivial substeps, platform-specific command mechanics, shell idioms, workaround recipes for environment quirks the model can resolve on its own. Assume a capable model: state the goal and the bound ("poll until ready or ~30s"), not the mechanics of achieving it (per `.claude/rules/skill-prose.md` §Assume a capable model). Also: Definition-of-Done lists restating every body step instead of exit gates.
8. **Cross-file duplicated rules.** The SAME rule (prose, not a constant — D7 owns constants) stated in ≥2 files. Keep one canonical home; others cite it with `§`. A duplicate that has DRIFTED reads as a contradiction.
9. **Appended-patch contradiction.** A later note / "NOTE:" / exception / caveat that patches or narrows an earlier rule in the same file instead of being folded into it — the later text silently overrides the earlier (recency wins) or forces reconciliation. Rewrite the original to be correct on its own; delete the patch.
10. **Progressive disclosure not used.** The structural default for a long skill is a spine plus a tree of files loaded at the point of use, not one file that front-loads everything. Flag SKILL.md detail that belongs in a sibling file read on phase entry (multi-paragraph explanations of one step, inline pseudo-code duplicated from a reference, or a large fully-unique block — a long template, full schema table, big example set) — propose a MOVE, not a cut. Redundancy is not a precondition. A MOVE only pays when the destination is conditionally loaded, so name the runs that will not read it: a reference every run of the skill loads is part of that skill's always-on budget, and a move into an `agents/*.md` body is never a saving, since an agent body is injected whole as the subagent's system prompt. A skill whose spine already fills the front-load budget wants splitting, not compressing.

11. **Over-constraint.** The preceding checks ask whether text is redundant. This one asks whether text that is live, unique and correct still costs more than it buys, because it was written for a weaker model than the one reading it — in a mature plugin the largest single source of removable instruction is guardrails the current generation no longer needs, not duplication. Shapes:
    - **Rule that should be a criterion.** A fixed threshold or blanket prohibition where the model could read the situation instead — "never write multi-line comments" versus "match the surrounding code's comment density". Flag the ones whose right answer plainly varies by context; a project contract (an exact path, schema, or canonical option label) is not this shape and stays fixed.
    - **Prohibition where a requirement carries the same rule.** The shape above asks whether a rule should be fixed at all; this one asks how a rule that *should* stay fixed is phrased. Prohibition-type constraints measurably lose compliance as a session's context grows, while requirement-type constraints hold — so a long agentic run erodes exactly the guardrail it most needs, and erodes it invisibly, since nothing fails at the moment the rule stops binding. Propose the positive form wherever one carries the rule. Keep the prohibition where the bar is data loss or an outward-facing effect and no positive rewrite reaches it; there, propose restating it at the point of use rather than only in a rules list, which is what survives the decay.
    - **Example that narrows.** An example is not free: it constrains the model to the space the example demonstrates. Flag examples teaching a pattern the model already has, or a single example standing in for a rule that should be stated as a rule. Where the real fix is upstream — a more expressive parameter, a closed enum, a tool surface that cannot express the wrong call — propose that instead (`.claude/rules/skill-structure.md` §Design the interface, not the instructions).
    - **Guardrail past its model.** A rule whose stated or implied justification is a failure mode of an older generation, or one a hook, schema, or test now enforces deterministically. Enforcement moving into a mechanism is exactly when the prose should go.

    **Report the removal candidate, never the count.** Name what the text constrains, what the model would do without it, and what breaks if that judgment is wrong. A candidate whose answer is genuinely invariant across contexts is not over-constraint — leave it.

12. **Dead instructions (liveness).** Text that can no longer apply at all: an instruction or gate governing a step, phase, sub-command, or flag that no longer exists; a mechanism a refactor replaced, still described in the old terms. Anti-rationalization rows are the densest carrier.

    **Route by referent, at the owner's tier** — this check is the lens, not the home, and filing everything here would downgrade real T1 defects to T4: a schema or frontmatter field → D2 §Schema lockstep; a phase or step name → D3 §Dropped phase/step names; a gate or branch condition → D5a §Unfireable gates; a replaced mechanism still documented → D3 §MIGRATION.md / HOOKS.md entries. Only text with no such owner is reported here.

    **Name the referent, then check it — hit count is not the verdict.** Grep proves absence only for a named identifier, and only outside `design/` and `evals/`, which quote strings they do not use; hits that merely *document a removal* (MIGRATION.md, a deleted-skills table) are not liveness. **An anti-rationalization row is not dead because its failure mode is absent from current code — that is what a working guardrail looks like.** Retire a row only when the step it polices is gone or a mechanism now enforces it; the latter is check 11's third shape, not this one.

13. **Mechanism-level subtraction.** Checks 1-12 ask whether *text* earns its place. This one asks whether a whole **mechanic** does — a phase, step, gate, sub-pipeline, helper, agent spawn, reviewer dimension, state file, mode, modifier, checkpoint, or verification pass. A mechanic can be well-written, unique, correct, and still not worth running, and no text-level check can see that: every one of them starts from the assumption that the thing should exist and asks only whether it is stated well. Three dispositions, and a finding names which one it is:

    - **Low yield.** It runs and almost never changes an outcome — a check whose findings are always filtered, a gate the user answers the same way every time, a verification pass that has never overturned what it verifies.
    - **Net-negative.** It runs and makes the process worse: a gate that fires so often it is rubber-stamped (which spends the user's attention and buys a signature, not a decision), a check whose false-positive rate trains readers to skip its output, a step that forces a default the run then has to work around.
    - **Cost or latency.** Removing it measurably cuts what a run loads or how long it takes — an always-on load only one phase reads, a serialized round-trip, a spawn whose output another spawn already carries.

    **The bar here is evidentiary, not stylistic, and it is the highest in this dimension.** A text cut that misses costs a rationale someone can notice is gone. A mechanic deleted in error leaves nothing behind to notice — no failure at the time, and none in any run after, because the step that would have objected is the step that was removed. So a proposal carries four things, and one that cannot is not a deletion proposal:

    - **The case it exists for, and that case's base rate.** "I did not see it fire" is not evidence — an idle guard is a working guard, which this dimension already says about prohibitive text and which binds harder here. Evidence is: the case it catches, how often that case arises, and what the run does on that case once the mechanic is gone.
    - **A measured cost, never an asserted one.** A token claim cites `scripts/measure-run-load.sh --detail <profile>` with the profile's total and the mechanic's own contribution; a latency claim counts what actually serializes — spawns, round-trips, gates awaiting a human. "Feels heavy" is not a finding. And cheapness cuts the other way: a mechanic costing little per run is a good trade even at a low firing rate, so the case needs cost × frequency, never low frequency alone.
    - **What covers the ground afterwards.** Either name the other mechanism catching the same case, or say plainly that the ground becomes uncovered and the run will not know it. Both are acceptable answers; not knowing which one applies is not.
    - **Whether it stands alone.** Say if the proposal holds only together with another in the same set. Two mechanics each redundant *given the other* are not both redundant, and a round applying them together removes the ground both were covering — the one compound failure a per-item gate cannot catch on its own.

    Report it whichever way the evidence points; a proposal that cleared the bar is worth making, and one that did not belongs in the verdict as a rejected candidate, not in the table as a hedged row.

14. **The case for the rule, shipped with the rule.** The preceding checks ask whether a rule earns its place. This one asks whether the *argument for* it is riding along. An instruction file is payload for a model that has to act, not a document defending its own design to a reviewer — and that defence is the hardest bloat in the repo to see, because it is unique, correct, on-topic, and reads as thorough. Shapes:

    - **Provenance.** Source lists ("sources for the rules below: …"), attribution paragraphs, and "per `<vendor>` verbatim: …" quote blocks standing beside the rule they already produced. Restate the rule in the file's own voice; drop the citation.
    - **Evidence grading.** A note on which rules rest on measurement and which on taste, or a passage weighing how strong the backing is. Grade while authoring; the grade steers no run.
    - **Refutation of a rejected theory.** Text explaining what the rule is *not* founded on, or why a plausible alternative lost. The model was never going to apply the rejected theory.
    - **Origin narration.** How the rule arrived — the version it replaced, the incident behind it, the migration that produced it.

    **Every shape applies on every surface in this dimension's scope.** Reference files and helpers are where all four collect, because they are long, rarely re-read end to end, and exempt from the front-load budget that disciplines a spine.

    **What stays.** The rule; the reason where the model would otherwise rationalize around it — an anti-pattern, an escape hatch, error semantics — which is check 11's bar, not this one's; and a bare link a counterintuitive rule needs to stop being re-litigated, the link rather than a summary of it. A rule whose whole body is its own justification is a check 11 candidate, not a check 14 one: the fix there is deleting the rule, here it is keeping the rule and cutting its defence.

    **Headings are a contract.** Before proposing a rename or a drop, grep the repo for the filename: another file citing `<file>.md §<Heading>` breaks with no error, and D3 check 2 reports it next run as an unrelated defect.

Tier mapping: T4 by default; pure-style items → T5; a duplicated rule that has drifted into a contradiction → T1. Check 13's mechanism proposals tier by disposition: net-negative → T1 when the mechanic produces wrong outcomes rather than merely costly ones, else T4; low-yield and cost/latency → T4. The tier orders the report; it never decides the deletion, which is the user's call at its own gate. Every removal carries regression risk — propose, never auto-cut; state what behavior would change if the deletion is wrong. A shorten or merge proposal carries one thing more: a **preserved inventory**, the spans the rewrite must reproduce verbatim — commands, tool names, trigger phrases, output formats, paths, numbers, exact error strings, and any string a test greps for. Those are contracts rather than prose, so a reword that drifts one of them reddens CI while every sentence still reads correct.

**Return the sweep, not a quota.** The sweep is mandatory; its result is not. Zero findings is a valid outcome; a manufactured one is worse than none, because a deletion is the one finding whose wrongness the user cannot notice later. So the deliverable is the sweep itself, reported whether or not it yielded anything — and a clean result belongs in the verdict sentence, not padded into a findings row:

- **Name what you examined**, at the granularity of the check: which files you read in full, which of this dimension's checks you applied, and where you looked hardest. A verdict that does not say what was swept is indistinguishable from a sweep that did not happen.
- **Name what you rejected and why.** A candidate you considered and left — because the answer is genuinely invariant across contexts, because the guardrail is still load-bearing, because the destination of a proposed MOVE is loaded by every run anyway — is a *result*, and it is the most useful thing you can hand the next round. It goes in the verdict, not the table. This is also what stops the next reviewer re-litigating it.
- **Say plainly when a subtraction pass found nothing.** "Swept `_shared/`, the meta-skills, and `.claude/rules/` in full against every check; the two candidates were X and Y, both rejected for <reason>" is a complete and successful D6 result.

## D7 — Magic numbers & duplicated constants

**Scope:** `skills/`, `agents/`, `.claude/skills/`, `hooks/`, `lib/`. **Method:** LLM reviewer seeded with a number-density grep.

Seed grep (orchestrator runs, pastes matches into the prompt): `grep -rhoE '(≤|>=|<=|≥|max |cap |within )[0-9]+|[0-9]+ (retries|rounds|lines|files|questions|attempts|seconds|chars|tokens)' skills/ agents/ .claude/skills/ | sort | uniq -c | sort -rn | head -80` — `-h`, not `-n`: a `file:line:` prefix makes every line unique, so `uniq -c` would count nothing and the multi-homed-constant signal vanishes; the reviewer greps locations for the candidates it pursues. Plus `grep -rnE '[0-9]{3,}' hooks/ lib/ --include='*.sh' | grep -v ':[[:space:]]*#'` (POSIX class, not `\s` — BSD grep treats `\s` as a literal `s`).

Checks:
**Two dispositions, and the split is the whole discipline of this dimension.** A number that lives in exactly one place and explains itself is doing its job — the fix is an inline WHY or a citation, and the number stays. A number that is *restated*, or that *counts something the repo changes*, or that *ordinals a list an edit can reorder*, cannot stay correct: it has no single home to be fixed in. The keep-the-number group and the remove-the-number group below split this way — do not blur the two: stripping a self-explaining single-homed threshold costs a rationale the model was relying on and buys nothing.

Keep-the-number checks:

1. **Unexplained thresholds.** A numeric limit with no adjacent rationale and no citation to a canonical source. The fix is an inline WHY or a citation — keep the number itself.
2. **Contradicting constants.** The same concept with DIFFERENT values in different files (this is a T1, not T4).
3. **Shell literals.** Hardcoded sizes/timeouts in hooks/lib without a comment or env-override; duplicated literals that must move in lockstep.

Remove-the-number checks — the drift-prone classes. For these, "add a WHY" is not an acceptable fix, because the defect is that the value exists in more than one place at all:

4. **Multi-homed constants.** The same threshold stated in ≥2 files, **even while the values agree** — agreement today is drift tomorrow. Fix: one home keeps the number, every other site cites it. A file that names another file as the owner and then restates the value anyway is this check's most common shape, and the restatement is what to delete.
5. **Prose counts of repo contents.** A count of things the repo contains — skills, agents, helpers, test suites, dimensions, reviewers, assertions, bypass IDs, load-set files. Hook counts are excluded: `lint-hook-wiring.sh` decides those, including the Cursor-unwired gap that has already drifted once. Measure each against reality, then **reword so the count is not stated**: the list lives elsewhere, so the sentence should point at it rather than tally it. "the seven per-skill scopes" becomes "the per-skill scopes"; "the same batch as the 7-10 built-ins" becomes "the same batch as the consumer's built-in dimensions". Re-stating the corrected number only resets the clock on the same defect.
6. **Drifting ordinals.** A hardcoded step, phase, check, sub-phase, or invariant NUMBER used as a cross-reference. Inserting or removing one item silently invalidates every reference past it, and a renumbering pass that misses one site produces a citation that resolves to the wrong step — worse than one that dangles, because nothing detects it. Fix: content anchors per `.claude/rules/skill-structure.md` §Cross-skill references ("the F→P invariant", not "step 4.3"). Two carve-outs stay numeric: a number that is part of a **contract** other files grep for (a schema version, a phase-enum value, an exit code), and a **contiguity requirement** a validator enforces (a check set that must run 1..N). Flag the reference, not the heading it points at.

Tier mapping: contradicting constants → T1; multi-homed / unexplained / drifting ordinals → T4; stale prose counts → T3.

## D8 — Safety & test coverage

**Scope:** `hooks/hooks.json`, `hooks/`, `lib/`, `tests/`, `settings.json`, `cursor/hooks.json`, `cursor/hooks/`, plus `skills/` for check 6 only (destructive-op grep). **Method:** LLM reviewer.

Checks:
1. **Matcher coverage.** Every guard hook's `hooks.json` matcher covers ALL tools that can perform the guarded action (Edit/Write/MultiEdit/NotebookEdit; Bash variants). A guard that misses one tool is bypassable — T0. The inverse is also a finding: a matcher naming a tool or event that does not exist can never fire, so the guard silently never runs — T1; D1 seeds these.
2. **Sanitization coverage.** Every field that reaches a persisted artifact passes through `redact-secrets`; new fields added to emit paths are walked by the sanitize loop.
3. **Fail-open vs fail-closed.** For each guard: what happens when `jq` is missing, stdin is malformed, or safety.json is unparseable? Safety-critical guards should fail closed; convenience hooks may fail open — flag mismatches with the hook's role.
4. **Bypass-list integrity.** Every documented `allow_patterns` ID is actually checked by its hook; every hook bypass branch has a documented ID (CLAUDE.md + HOOKS.md).
5. **Test coverage map.** For each hook and each data-mutating lib helper: does a `tests/**` suite exercise it (both block and allow paths for guards)? Untested hard-block guards and untested live data-mutators → T1.
6. **Destructive-op surface.** Any `rm -rf`, `git push`, `--force` usage in skills/hooks/lib outside the documented guarded paths.

Tier mapping: bypassable guard / unsanitized secret path → T0; untested live mutator / wrong fail direction → T1; map gaps → T4.

## D9 — Wiring completeness (declared vs. wired)

**Scope:** `skills/`, `agents/`, `hooks/hooks.json`, `.claude/rules/`, with `skills/_shared/` as the contract source. **Method:** LLM reviewer seeded with the D1 declaration inventory.

Every other dimension reads what is written and asks whether it is right. This one asks what is **declared but never wired**, and what is **wired against a declaration that does not resolve**. D1's no-execution-site grep already asks this for `_shared/` helpers, lib scripts, and agents; the checks below extend the same question to the declaration kinds that have no owner today — the instruction layer, load sites, phase structure, gates, template slots, and claimed enforcement.

**Absence is the finding, so absence is what has to be proven.** A grep returning nothing is not evidence until you have searched every name the thing travels under: a block by its heading *and* by its plain-English description, a gate by its question text *and* by the decision it makes, a phase by its number *and* its name. Name the searches you ran in the `evidence` column — a finding whose evidence is "no hits" without saying what was searched is inadmissible under the output contract, the same bar a fabricated quote fails.

**Authoring a thing is not consuming it.** The commonest false positive here is the reverse: counting a mention as a wiring. A skill that *authors* a block, a validator that *checks its shape*, and a loader that *parses* it are all mentions; the execution site is the phase that acts on the parsed value. Classify each hit as author / validate / parse / execute before concluding either way.

**Route by owner** — this dimension owns the missing-half question only. A declaration that *contradicts* rather than *dangles* belongs to its owner: a state-file field written but never read → D2 §Schema lockstep; a gate whose trigger can never occur → D5a §Unfireable gates; a guard matcher missing a tool → D8 §Matcher coverage; a reference to something deleted → D3. Filing those here buries real T0/T1 defects under a completeness label.

Checks:

1. **Instruction-block consumption.** Every block the loader's §Producer contract parses — `## Rules`, `## Constraints`, `## Additional Steps`, `## Data Sources`, `## Verification Surface`, `## Memory Backend` — reaches at least one execution site. `/geniro:instructions` authors them and `/geniro:setup` scaffolds them; `load-custom-instructions.md` parses them; none of those is an execution site. A block a user can author, the CRUD skill validates, and the loader parses, but no phase ever acts on, is a feature that silently does nothing — and the user cannot discover that, because every visible step succeeds and the echo line still prints. Check the `## Additional Steps` boundary anchors too: a subsection naming a phase boundary no consumer has is applied "where it fits" by the loader's allowance, which is a real escape hatch for a skill that genuinely lacks the phase and a silent no-op when the name is simply wrong. Two traps make a bare heading grep useless here — helper files carry their OWN `## Constraints` and `## Rules` headings for unrelated purposes (`ui-preview-gate.md`, `update-semantic.md`), and the loader deliberately owns the application semantics so consumers are forbidden from restating them. Neither a coincidental heading nor that prohibition tells you whether a phase ever acts on the value; read the site.
2. **Load-site coverage.** Each loader call site names a `SKILL_SLUG` matching its own skill directory (a mismatched slug makes the per-skill `<slug>.md` unresolvable, so the file loads as absent forever), a `LOAD_TIER` the loader defines, and a `MODE`. Flag a pipeline skill whose phases consume meaningful context and which declares an initial load with no refresh site — compaction drops the rules mid-run and nothing re-reads them. **`MODE:` is an overloaded slot name**: `spec-challenge.md`, `library-reuse-audit.md`, and `task-chain-context.md` each define their own value set, so bind the slot to the helper actually being invoked rather than to the token.
3. **Phase structure completeness.** Every phase in a skill's phases overview has its `## PHASE N` heading; every phase-body pointer resolves to a file that exists; every phase with a body file states the entry Read and its echo; the Definition of Done carries an exit gate for each phase that can ship something. Flag the missing half in either direction — a heading absent from the overview is as much a defect as the reverse, because external files cite phases by number and a phase documented only in the body cannot be cited.
4. **Gate wiring.** Every user decision a skill declares — in its phases overview, its Approval Points, its Definition of Done, its `approvals[]` categories — has an `AskUserQuestion` fire site in the body or in the phase file that owns it. Every gate presenting rich content before deciding cites the render contract rather than restating it. This owns the gate that was promised and never built; a gate that exists but cannot fire is D5a check 2.
5. **Template slots.** Every `{{slot}}` a spawn or prompt template declares is filled at every site using that template, and every slot a site fills exists in the template. An unfilled slot reaches the subagent as literal braces, which reads as missing context rather than as an error, so the agent proceeds on whatever it can infer. Pair with the agent's own contract: an agent whose workflow prescribes an instruction load declares the load report in its output schema, since the spawn site has no other way to distinguish a load that happened from one that did not.
6. **Claimed enforcement with no mechanism.** Prose asserting something is "mechanically enforced", "hard-blocked", or "the hook blocks this" names a hook that exists in `hooks/` and is registered in `hooks.json`. A claim of enforcement with nothing behind it is worse than no claim, because readers stop verifying what they believe a mechanism guarantees. Where both the claim and the hook exist and only their details disagree, that is D2 check 1 — this check owns the case where the mechanism is absent entirely.

Tier mapping: an authorable declaration no site consumes, an unresolvable slug or tier, and an unfilled slot the spawn depends on → T1 (the feature does not work); a safety guard claimed in prose with no hook behind it → T0; a promised gate never built → T1 when it guards an external effect, T3 otherwise; missing refresh site, unfilled non-load-bearing slot → T4; phase-structure and Definition-of-Done gaps → T3.

**Report the searches, not just the gaps.** Like D6, this dimension's verdict is only readable if it says what was swept: which declaration kinds you enumerated, how many sites each had, and which apparent gaps you resolved as author/validate/parse mentions rather than missing wirings. A verdict of "wiring healthy" that does not say what was traced is indistinguishable from a dimension that traced nothing.

---

## Do-not-flag list (endorsed patterns)

Verified healthy by prior audit — re-flagging these is a false positive:

- **Resolving `§N` section anchors** — content anchors are the endorsed cross-reference form; only dangling/inverted ones are defects.
- **Caps inside anti-rationalization right-hand cells** when accompanied by reasoning.
- **Justified magic numbers with adjacent WHY** (convergence ≥2/≥3, ≤50-file scan cap, 4096 PIPE_BUF, retry counts with backoff rationale) — keep numeric. This endorsement covers a **single-homed** value only; it is not a defence for a restated one. D7 checks 4-6 (multi-homed constants, prose counts of repo contents, drifting ordinals) are outside it, and an adjacent WHY does not rescue them — a rationale duplicated into two files drifts exactly as fast as the number it explains.
- **Author-facing tier/layer codes (T1/L4/m6-v2) in architecture docs** (`CLAUDE.md` §State Files / §Memory Layers, `state-tier-spec.md`) — the plain-English rule binds user-facing strings, not author-facing architecture sections.
- **Decision-type tags and memory codes in skill-body declarative prose** — only their leakage into user-facing strings is a defect.
- **Size guidelines treated as guidelines** — a SKILL.md a few hundred words past the whole-file guideline is advisory, not a defect demanding cuts.
- **Deleted-skill names inside README.md's "Skills deleted" table and MIGRATION.md** — documentation of the deletion, not a stale reference.
- **Rich SKILL.md `description:` fields carrying trigger keywords + what/when** — the description is the sole signal Claude uses to select a skill, so its keywords are load-bearing; trimming them to save tokens degrades selection (a compaction pass's most common own-goal). Flag a description only for exceeding the length limit in `.claude/rules/skill-structure.md` §Frontmatter hygiene (D1 checks it) or for body drift (D2 §Description-vs-body drift), never for verbosity.
- **The two deliberately-unwired Cursor hooks** (gate-render, update-check) — their absence from `cursor/hooks.json` is documented: those events do not map cleanly to a Cursor slot. Only a WIRED guard that fails open under the shim is a defect.
- **`cursor/agents/*.md` divergence from `agents/*.md` in dropped fields** (`tools`, `maxTurns`, forced `model: inherit`, added `readonly`) — that is the generator's contract, not drift. Real drift is caught by `tests/cursor/build-agents-fresh.sh`; flag only what that test cannot see.
- **`agents/<name>-reference.md` companions** — body-overflow targets prescribed by `.claude/rules/skill-structure.md`; they carry no agent frontmatter by design and are skipped by the Cursor generator. This is also the `maxTurns` exemption in D1's frontmatter check.
- **A first load site that prescribes `MODE: refresh` rather than `initial-load`** — `load-custom-instructions.md` §When to invoke documents it: a consumer may invoke the phase-boundary contract at its Phase 1 entry instead of a Step 0 load. `refactor` and `implement` are built this way. D9 check 2 flags a *missing* refresh site, never a first site that is one.
- **`MODE:` carrying values outside the loader's set** — the slot name is shared by `spec-challenge.md` (`plan` / `implement`), `library-reuse-audit.md`, and `task-chain-context.md`, each with its own values. A `MODE: plan` is a defect only if the helper being invoked is the instruction loader; bind the slot to its helper before flagging.
- **An instruction block declared optional and absent from a project** — `## Data Sources`, `## Verification Surface`, and `## Memory Backend` are opt-in declarations whose absence the loader treats as "nothing changes". D9 check 1 asks whether the plugin has an execution site for the block, never whether a given project authored one.
- **A reason attached to a rule the model would otherwise rationalize around** — an anti-pattern, an escape hatch, or error semantics carries its why so the constraint survives an edge case its wording never anticipated. That is payload. D6 check 14 hunts the case built *for* a rule, never the reason living *inside* one; where the reason itself looks spent, that is check 11's bar, not check 14's.
- **A link the instruction requires following** — a URL the model must fetch to do the work (a schema, an API reference, a runbook) is a data source, not a citation. Only a link supporting an argument is in check 14's range.
