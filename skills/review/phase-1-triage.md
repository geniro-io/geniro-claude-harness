# /geniro:review — Phase 1 & Phase 1.5

Phase bodies for `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`. Read on entry to Phase 1. The spine keeps the phase headings, the loop invariants, the anti-rationalization table, and the Definition of done — this file carries the Steps.

## Contents

- Phase 1 — Triage & context collect (steps listed below; exit criterion at the end)
- Phase 1.5 — Mechanical pre-pass
  - 1.5.1 Check 1 — Lint
  - 1.5.2 Check 2 — Schema
  - 1.5.3 Check 3 — Secret scan
  - 1.5.4 Custom-reviewer discovery
  - 1.5.5 Output handling
  - 1.5.6 Fail-handling
  - 1.5.7 Pre-pass declaration (state.md write before Phase 2)

---

## Phase 1 — Triage & context collect

State.md `phase: triage`. Every step below is specified in full — inputs, decision trees, fail-open rules, gate wording — in `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-triage-reference.md`, which is the single home of the Phase 1 contract. Read it on entry to this phase — before any step below, echoed per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/phase-entry-read.md`, exactly as this file itself was. The list here is the running order and nothing more, so a step's rule is never stated in two places to drift apart; the corollary is that every Phase 1 gate — the workspace-approval decision tree, the round-3 escalation, the re-review scope question — exists only in that reference, and a run that stops at this file has the running order with none of the gates.

**Flags & presets:** `--plan <path>`, `--subagent-model <tier>`, and the workspace modifiers are cataloged with the cross-skill flag set in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md`.

Run these in order (`§` anchors are sections of the triage reference):

1. **Set up the workspace** — settle which working tree the rest of the phase inspects, before anything reads the repo · §0.
2. **Parse the input** — strip `--focus <text>` and `--subagent-model <tier>` first, then resolve the review-target shape from the remaining `$ARGUMENTS`. When it resolves to a PR ref, also Read `${CLAUDE_PLUGIN_ROOT}/skills/review/phase-1-pr-reference.md` — it carries the whole PR-side contract (thread-state fetch, existing-review ingest, metadata fetch, peer-PR scout) and no other input shape loads it · §1.
3. **Resolve the scope** — the reviewed file set, the scope-exclusion note, and the sanity gate that aborts an unresolvable ref or an empty diff before any reviewer spawns · §2 + §2.1.
4. **Fetch the pull-request metadata** (PR ref only) — diff, base/head refs, title/body, head SHA, URL, draft state, author, labels · `phase-1-pr-reference.md` §3.
5. **Fetch the linked issue** — workflow-file detection, tracker-ID match, spec-frontmatter ref merge, and the `LINEAR CONTEXT:` block · §3.5.
6. **Scout sibling pull requests** (PR ref only) — scored, capped, and inlined as `PEER-PR CONTEXT:` · `phase-1-pr-reference.md` §4.
7. **Load the custom instructions** · §6.
8. **Count the review round** — the round counter, the round-3 escalation question, and the re-review scope question on a fresh second-or-later round · §7.
9. **Load the plan context** · §8.
10. **Stratify by risk** — sets `risk-tier: standard | high`, which scales three downstream knobs · §9.
11. **Load the memory layers** — project snapshot, past learnings, conflict resolution · §10.
12. **Triage by size** — Trivial / Substantive classification plus each reviewer's payload shape · §12.

Exit criterion: state.md frontmatter carries the fields each prior step wrote — `round`, `risk-tier`, `pr-ref`, `linear-task-ref`, `linear-parent-ref`, `plan-context-ref`, and `subagent-model` (from the step-2 flag parse; missing reads as `inherit`); `approvals[]` carries any AUQ answers; `## Tool log` includes initial load echoes.

Phase 1 PR metadata and tracker context loads are orchestrator-inline (`gh pr diff` / `gh pr view` / `mcp__linear__*` reads). For codebase-research side queries inside this phase (e.g., locating a pattern across the wider repo when scoring peer-PR overlap), spawn `codebase-research-agent` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/context-isolation-checklist.md` § Codebase research.

---

## Phase 1.5 — Mechanical pre-pass

State.md `phase: mechanical-prepass`.

Three deterministic checks BEFORE LLM reviewer spawns. Cheap-deterministic first; LLM-spawn second with pre-pass findings as prior-context. Sequential, not parallel — LLM agents seeing prior mechanical findings produce better-targeted output.

**Each check is must-attempt and lands exactly one of three recorded outcomes** — `findings` (written to the finding list; Check 3's tagged CRITICAL), `clean` (the check ran and found nothing), or `error` (a fail-open `## Errors mechanical-prepass-<id>: <reason>` entry, which also covers not-applicable). There is no silent fourth outcome — skipping a check entirely (e.g. running neither lint nor `tsc` on a TS-dominated diff) is the failure this contract closes, and a clean run is a real result, not the absence of one. Record each check's outcome in state.md frontmatter (§1.5.7) before exiting this phase, mirroring §2.2's spawn-declaration pattern.

### 1.5.1 Check 1 — Lint

Detect the project's own lint setup and run its lint command over the changed files through `source "${CLAUDE_PLUGIN_ROOT}/hooks/backpressure.sh" && run_silent "Lint" "<lint_cmd>"` — the same containment the Phase 2.7 build check mandates; a lint pass over a broken diff floods context exactly like a build. Capture failures as `{tool, file, line, rule, message}` tuples.

### 1.5.2 Check 2 — Schema

Run whichever type / schema checks the diff's file types call for — compiler no-emit type check, JSON-Schema or OpenAPI validation, protobuf lint — through the same `run_silent` containment as check 1: a no-emit type check on a broken diff can emit thousands of lines. Capture failures in the same tuple shape.

### 1.5.3 Check 3 — Secret scan

Regex pass against changed-file content:

- `AKIA[0-9A-Z]{16}` (AWS access keys)
- `sk-[a-zA-Z0-9]{32,}` (OpenAI-style keys)
- `-----BEGIN (?:RSA |EC |OPENSSH |)PRIVATE KEY-----` (PEM markers)
- `ghp_[a-zA-Z0-9]{36}` (GitHub personal tokens)

**Risk-tier:high strict mode** adds:
- `(?:AWS|GCP|AZURE)_(?:SECRET|ACCESS)_KEY=`
- GCP service-account JSON markers (`"type": "service_account"`)
- Azure SAS tokens (`?si=.+&sig=`)
- SSH OPENSSH key patterns

Findings tagged `severity: CRITICAL` (secrets are always critical).

### 1.5.4 Custom-reviewer discovery

**Resolve `PRIMARY_ROOT` first.** Run the Mode A snippet from `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md` in a shell call before invoking the helper — the helper requires the slot in scope to dual-glob local + main-worktree `review-extra/` files, and a linked worktree's `.geniro/instructions/` is gitignored and may be empty.

Apply `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-reviewers.md` to enumerate user-authored review dimensions in `.geniro/instructions/review-extra/<slug>.md`. The helper applies its `paths:` filter against the changed-files list, enforces the per-project cap it owns, and returns spawn-specs: `{slug, dimension-label: custom:<slug>, model, criteria-content, severity-default, requires-context, source-path}`.

Persist the result to state.md frontmatter `custom_reviewers[]` — every short spawn-spec scalar, one entry per surviving reviewer (canonical field list: `${CLAUDE_PLUGIN_ROOT}/skills/_shared/state-tier-spec.md` §"`/geniro:review` producer-specific fields"):

```yaml
custom_reviewers:
  - slug: manifest-incident-patterns
    paths_matched: true               # whether the spec's `paths:` matched any changed file (`true` when no paths filter declared — always-fires)
    model: inherit                    # frontmatter value, or `inherit` when OMITTED in the spec
    source_path: .geniro/instructions/review-extra/manifest-incident-patterns.md
    severity_default: HIGH
    requires_context: "fetch the live incident report, latest entry, and provide its pattern list"   # verbatim `requires-context:` directive, or null when unset
```

The one spawn-spec field this list deliberately omits is `criteria-content` — the user file's whole body. Writing it here would drag every word of every custom rubric through `atomic_state_write` into a durable handoff that ships downstream, then back out at Phase 2: the same pass-through cost §2.3's "pass the path, never the body" rule exists to avoid, paid twice. `source_path` is the anchor instead — Phase 2 re-reads it for the body at the moment it composes the spawn.

Phase 2 reads `custom_reviewers[]` from frontmatter and re-reads each `source_path` for the criteria body — no discovery, globbing, path-filtering, or cap-checking at Phase 2 entry (discovery lives here because Phase 1.5 already has shell tooling primed, keeping the cognitively heavy Phase 2 spawn assembly free of it).

On the helper's hard-cap error, surface it to chat, persist `custom_reviewers: []`, and let Phase 2 fire only the built-ins. A helper batch-size *warning* is advice to the user about how many custom reviewers to keep — it never trims the batch: the §2.1 always-fire rows fire on every run regardless of how many custom reviewers discovery returned.

### 1.5.5 Output handling

Mechanical findings tagged `origin: mechanical:<check_id>`. Routed two ways:

1. **To Phase 2 LLM reviewers as prior-context** — pasted into spawn prompts under a `## Mechanical Pre-pass Findings` section. LLM agents use those as starting points (avoid duplicating; extend with semantic understanding).
2. **To Phase 5 persist** — included in the state.md finding list with the mechanical tag preserved.

### 1.5.6 Fail-handling

Each check records exactly one outcome. Continue to Phase 2 whatever it is (fail-open, consistent with `gh` fail-open):

- **Check produced findings** → outcome `findings`.
- **Check ran and found nothing** → outcome `clean`. A green lint or type-check is the common case on a healthy diff, and it is a result the §4.0a gate reads as a pass — not a gap.
- **Check failed** (process exit nonzero with no output OR command not found) → outcome `error`; write `## Errors mechanical-prepass-<check_id>: command_unavailable_or_failed`.
- **Check not applicable** (no lint config detected for `lint`; no TS / schema / proto files in the diff for `schema`) → outcome `error`; write `## Errors mechanical-prepass-<check_id>: not_applicable`, so a deliberate skip stays distinguishable from never reaching the check — which is what the §4.0a gate detects.

Secret scan is a pure-regex pass — it cannot fail or be not-applicable, so its outcome is `findings` or `clean`.

### 1.5.7 Pre-pass declaration (state.md write before Phase 2)

Before leaving Phase 1.5, declare each check's outcome in state.md frontmatter via `atomic_state_write`, mirroring §2.2's spawn-declaration pattern:

```yaml
# frontmatter update — one entry per check, value in {findings, clean, error}
mechanical_prepass_attempted:
  lint: findings
  schema: error
  secret: clean
```

Every check that ran gets an entry; a check with no entry is one that was never reached. This is the observability surface the Phase 4 §4.0a verification gate asserts against — a missing declaration, a missing check, or an outcome the run cannot corroborate (`findings` with nothing on the finding list, `error` with no `## Errors mechanical-prepass-<id>` entry) is a pre-pass contract miss the gate surfaces.

---
