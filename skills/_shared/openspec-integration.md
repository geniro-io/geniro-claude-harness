# OpenSpec integration — duplicate an approved plan into an OpenSpec change proposal

Single source of truth for the OpenSpec integration primitive. Skills cite this file; do NOT inline-paste the procedure.

Applied by `/geniro:plan` when the consumer repository already uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) — a spec-driven-development framework that tracks change proposals under an `openspec/` directory. When that directory is present, `/geniro:plan` offers to duplicate the approved plan into a standard OpenSpec change proposal, so a team that drives its workflow through OpenSpec gets the plan in their own tooling's format without re-authoring it by hand.

The Geniro `spec.md` stays the source of truth that `/geniro:implement` consumes. The OpenSpec change is a parallel, cross-linked artifact derived from it — never a replacement. Detection-gated, opt-in, read-only on detection, fail-open on every write and CLI step.

## Contents

- §1 What OpenSpec is + detection
- §2 The opt-in suggestion (detection-gated)
- §3 Change-id and capability naming
- §3.5 Tooling-first — prefer the repo's own OpenSpec commands & conventions
- §4 Files written — the change-proposal layout
- §5 Mapping — Geniro spec sections to OpenSpec files
- §6 Spec deltas — requirement + scenario format
- §7 Cross-reference — the integration link
- §8 CLI validation (when available)
- §9 Lifecycle — write at approval, one commit
- §10 Fail-open
- §11 Plain-English echo
- §12 Anti-rationalization

---

## 1. What OpenSpec is + detection

OpenSpec organizes spec-driven work under a repo-root `openspec/` directory:

```
openspec/
  project.md                       # project context
  specs/<capability>/spec.md       # current, deployed capabilities (source of truth "today")
  changes/<change-id>/             # one folder per in-flight change proposal
    proposal.md
    tasks.md
    design.md                      # optional — complex changes only
    specs/<capability>/spec.md     # the requirement delta for this change
  changes/archive/                 # changes archived after deploy
```

**Detection (read-only).** A repo uses OpenSpec when its OpenSpec root directory exists with at least one of `<root>/project.md`, `<root>/specs/`, or `<root>/changes/`. The root is `openspec/` by default, but the repo may configure a custom location — resolve it first, then test, all read-only from the primary worktree per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/primary-worktree.md`.

**Resolve the OpenSpec root (custom-directory aware).** A custom OpenSpec root is resolvable only from Geniro-side config — OpenSpec stores its project config in `openspec/config.yaml` but exposes no discoverable field for relocating the root (a custom location is set at `openspec init <path>` time and is not recorded anywhere a reader can find it). So resolve the root from the two Geniro-side sources, then fall back to the default. Check in order; first hit wins:

1. **Geniro workflow config (the setup-written file).** `.geniro/workflow/openspec.md` carries an `openspec:` block with `enabled` + `directory`, written by `/geniro:setup` when the user enables the integration (the same place the Linear/issue-tracker integration is configured). Read it as markdown first: `enabled: false` turns the integration OFF (stop — no detection); `enabled: true` makes its `directory` value the root. This is the canonical config when setup has run.
2. **Geniro custom-instruction override.** When no workflow file is present, a user may declare `openspec_dir: <path>` in `.geniro/instructions/plan.md` or `global.md` (surfaced by the L4 loader). Honor it as the root.
3. **Default.** `openspec/` at the primary worktree root, when neither Geniro-side source set a directory.

**Populate `$openspec_dir_override` before the snippet.** Extract the directory the orchestrator-read config sets and assign it: from source 1, the workflow file's `openspec:` `directory:` value (only when its `enabled:` is not `false`); else from source 2, the L4 `openspec_dir:` value. Leave it empty when neither set one — the snippet then uses the default.

```bash
# resolve_openspec_root: echo "openspec-detected:<root>" when OpenSpec is present.
# $openspec_dir_override = the directory from the workflow file (source 1, enabled)
#   or the L4 openspec_dir override (source 2); empty when neither set one.
root="${openspec_dir_override:-openspec}"   # source 1/2 if set, else source 3 default

if [ -d "$root" ] && { [ -f "$root/project.md" ] || [ -d "$root/specs" ] || [ -d "$root/changes" ]; }; then
  echo "openspec-detected:$root"
fi
```

Carry the resolved `<root>` through every later step — `<root>/changes/<change-id>/`, `<root>/specs/<capability>/`, and the CLI run all use it, not a hard-coded `openspec/`. Detection never writes and never blocks. Absence is the normal case — the integration stays dormant and `/geniro:plan` behaves exactly as it does without OpenSpec.

## 2. The opt-in suggestion (detection-gated)

The suggestion fires ONLY when §1 detected OpenSpec. A repo without `openspec/` never sees the question — there is nothing to duplicate into.

When the `--openspec` / `--no-openspec` modifier pre-answered the suggestion, skip the question and apply the modifier (`--openspec` → emit; `--no-openspec` → skip). `--openspec` still requires detection — when it is passed but no `openspec/` directory exists, emit the §11 "not found" note and skip rather than scaffolding OpenSpec from scratch (initializing a framework the team has not adopted is a heavier decision than this skill owns; the team runs `openspec init` themselves).

Otherwise render a one-line plain-English framing, then fire ONE lean `AskUserQuestion`:
- `header`: "OpenSpec"
- `question`: "This repo uses OpenSpec. Also duplicate this approved plan into an OpenSpec change proposal?"
- `options[]` (single-select):
  - **Yes — create the OpenSpec change** (Recommended) — write the change proposal under `openspec/changes/<change-id>/` and include it in the plan commit.
  - **No — Geniro spec only** — leave OpenSpec untouched; the Geniro spec is unaffected either way.

Persist the pick to `approvals[]` category `openspec_duplicate` so a resume does not re-ask.

## 3. Change-id and capability naming

**Change-id** — verb-led kebab-case, the OpenSpec convention (`add-two-factor-auth`, `refactor-payment-retry`). Derive it from the plan: prefer a verb + the task slug (e.g. task slug `two-factor-auth` → `add-two-factor-auth`); when the objective already starts with a verb, kebab-case the objective's first clause. Cap at ~40 chars. If `<root>/changes/<change-id>/` already exists, append `-2`, `-3`, … so an existing change is never overwritten.

**Capability** — the spec folder a requirement belongs to. Match an existing `<root>/specs/<capability>/` folder when the plan's scope maps to one (read the folder list; pick the closest by name). When none matches, derive a single new capability slug from the primary affected area in scope section 2. One capability per change keeps the delta simple; split into multiple capability folders only when the scope plainly spans two established capabilities.

## 3.5 Tooling-first — prefer the repo's own OpenSpec commands & conventions

A repo that uses OpenSpec ships its own scaffolding tooling — the `/opsx:*` commands (`/opsx:propose` scaffolds a change folder, `/opsx:explore` refines, `/opsx:apply` works the tasks, `/opsx:archive` merges deltas), a project `openspec` CLI, and a refresh script such as `pnpm openspec:update`. That tooling is the authority on the exact shape a change must take in THIS repo's installed OpenSpec version — including files the hand-written §4–§6 contract can't anticipate (the per-change `.openspec.yaml` marker was one such surprise). Generate through the repo's tooling and conventions; hand-writing is the fallback for when no tooling is present.

**Discover the repo's tooling first (read-only).** Before writing anything:

1. **Read an existing change as the living template.** `ls <root>/changes/` and read one non-archived `changes/<id>/` end-to-end — its file set, its `.openspec.yaml` key set, its requirement/scenario style, and its change-id naming style (verb-led vs feature-led). Mirror exactly what you find; an existing change in the repo outranks the generic §4–§6 contract whenever they differ.
2. **Detect the commands + CLI.** Check for the `openspec` CLI (`command -v openspec`), the `/opsx:*` commands (named in `AGENTS.md`, `.claude/commands/`, or a `package.json` script like `openspec:update`), and any documented refresh step. Note what exists for the steps below.

**Generate through the tooling when it can do the work:**

- When the `openspec` CLI exposes a scaffold/create command in this repo's version, use it to create the change skeleton, then fill the skeleton from the Geniro plan (§5–§6) — so the structure and marker files are tool-generated and version-correct, not reverse-engineered.
- When scaffolding is only available as an interactive `/opsx:propose` command (AI-driven, would re-derive the plan you already approved), do NOT re-run it — instead replicate the artifacts it produces by mirroring the existing-change template from step 1, then fill them from the plan.
- Always finish with the repo's validator (§8, `openspec validate --strict`) — it is the tooling's own check that the generated change is well-formed. When the repo documents a refresh step (`pnpm openspec:update`), surface it in the §11 echo rather than running it (it regenerates the team's command set — their call, not the plan's).

This is a specific case of a general rule: when a repo provides its own commands, skills, or CLI for an artifact, detect them and generate through them fully before hand-rolling the artifact yourself. Hand-writing reverse-engineers a format the tooling already produces correctly, and drifts the moment the tooling's version moves.

## 4. Files written — the change-proposal layout

The §4–§6 file contract below is the **fallback** shape, used when §3.5 found no usable tooling — and even then, mirror an existing change (§3.5 step 1) over this generic contract wherever they differ. Write under `<root>/changes/<change-id>/` (the §1-resolved root). These live OUTSIDE `.geniro/`, so the `enforce-state-helper` hook does not apply — write them with the `Write` tool (the skill's `allowed-tools` includes `Write`). They are planning artifacts, not source code: markdown specs and task checklists with no executable code, authored only after the Phase 8 approval and committed in the same commit as the Geniro spec.

| File | Always? | Source |
|---|---|---|
| `.openspec.yaml` | yes | §4 marker below |
| `proposal.md` | yes | §5 — objective + scope + risk/rollback |
| `tasks.md` | yes | §5 — the plan's Steps |
| `specs/<capability>/spec.md` | yes | §6 — Validation + Done Condition as requirements |
| `design.md` | Medium / Big tier only | §5 — chosen approach + considered alternatives |

`design.md` is optional in OpenSpec — emit it only for Medium/Big effort tiers, where the approach reasoning is worth recording. Skip it on Trivial/Small; a one-paragraph design adds noise.

**`.openspec.yaml` (per-change marker).** OpenSpec writes a small metadata file in each change folder; match it so the generated change reads as native to the team's tooling and passes any per-change validation. Two fields:

```yaml
schema: spec-driven
created: <YYYY-MM-DD>
```

`schema` is the literal `spec-driven`. `created` is today's date from a live `date -u +%Y-%m-%d` read — never a model-supplied date (same timestamp-sourcing rule as `${CLAUDE_PLUGIN_ROOT}/skills/_shared/atomic-state-write.md` § Timestamp sourcing). When a repo's existing changes carry additional keys in their `.openspec.yaml`, read one and mirror its key set rather than assuming these two are exhaustive.

## 5. Mapping — Geniro spec sections to OpenSpec files

Read the approved Geniro `spec.md` and map its sections. Do not re-derive content — transcribe and reshape what the user already approved.

**`proposal.md`:**

```markdown
## Why

<Geniro spec section 1 Objective, expanded with the Problem & Evidence section when the spec carries one (--prd run); 1-3 sentences stating the motivation.>

## What Changes

<Geniro spec section 2 Scope — Included, as a bullet list. Add a "Not changing:" line summarizing section 3 Scope — Excluded when it is non-empty.>

## Impact

- Affected specs: <capability/ folders touched by the delta>
- Affected code: <the file globs from section 2 / the Steps' cited paths>
- Risks: <Geniro spec section 5 Risks, one line; "none" when the spec says so>
- Rollback: <Geniro spec section 10 Rollback-Recovery, one line>
```

**`tasks.md`** — OpenSpec uses numbered groups with checkbox sub-items. Map the plan's Steps (section 6): group related steps under a `## N. <group>` heading, each step a `- [ ] N.M` checkbox. A flat plan maps to a single group:

```markdown
## 1. Implementation

- [ ] 1.1 <Geniro spec Step 1 description>
- [ ] 1.2 <Geniro spec Step 2 description>

## 2. Validation

- [ ] 2.1 <each section 9 Validation criterion as a verifiable task>
```

Carry each step's intent in plain words; drop the Geniro `<!-- step-N -->` anchors and `file:line` cites (OpenSpec tasks are coarser). For a milestone-sliced plan, one group per milestone.

**`design.md`** (Medium/Big only) — the chosen approach and why, plus the alternatives considered:

```markdown
## Context

<one paragraph: the design problem, from the Objective + Risks>

## Decision

<the Phase 4 chosen approach name + summary from the Geniro spec's Approach prose>

## Alternatives considered

<the Geniro spec `## Considered Alternatives` body, condensed — each alternative + why not>
```

## 6. Spec deltas — requirement + scenario format

The delta at `<root>/changes/<change-id>/specs/<capability>/spec.md` states the behavior this change adds or modifies, in OpenSpec's requirement/scenario grammar. Derive requirements from the plan's behavioral criteria — section 9 (Validation) and section 11 (Done Condition) describe observable behavior, which is exactly what a requirement captures.

Format (OpenSpec canonical):

```markdown
## ADDED Requirements

### Requirement: <short capability name>

The system SHALL <observable behavior, derived from a Validation criterion or the Done Condition>.

#### Scenario: <scenario name>

- **WHEN** <the triggering condition>
- **THEN** <the expected outcome>
```

Rules that keep `openspec validate --strict` green:
- Use `## ADDED Requirements` for new behavior, `## MODIFIED Requirements` for changed behavior, `## REMOVED Requirements` for removed behavior. A pure-additive feature uses `ADDED` only.
- **Every requirement carries at least one `#### Scenario:`.** OpenSpec validation fails a requirement with no scenario. When the plan gives a behavior but no explicit case, write one scenario from the Done Condition's observable signal.
- One requirement per distinct behavior; do not collapse unrelated criteria into one requirement.
- Requirement text uses SHALL/MUST (normative); scenarios use the `WHEN`/`THEN` (optionally `GIVEN`/`AND`) bullet form.

A Trivial plan with a single Validation criterion yields one requirement with one scenario — that is valid and sufficient.

## 7. Cross-reference — the integration link

Link the two artifacts so each points at the other:

1. **Geniro spec → OpenSpec.** At the Phase 8 approval rewrite (the same rewrite that flips `lifecycle: draft` → `approved`), add `openspec_change_id: <change-id>` to the Geniro spec frontmatter. Optional field; absent when the user declined the suggestion. Per `${CLAUDE_PLUGIN_ROOT}/skills/plan/spec-template.md` § Frontmatter.
2. **OpenSpec → Geniro spec.** Add a trailer line to `proposal.md`:

   ```markdown
   ---
   Generated from the Geniro plan at `.geniro/planning/<slug>/spec.md`.
   ```

The cross-reference is what makes this an integration rather than two disconnected files: a reader on either side can find the other. A `/geniro:plan` re-run on the same task derives the same change-id and the §3 collision rule appends `-2` / `-3`, so a re-run writes a fresh change beside the original rather than overwriting it — the user archives or discards the superseded one through their normal OpenSpec workflow.

## 8. CLI validation (when available)

After writing the files, validate the change when the `openspec` CLI is installed (it ships with the team's OpenSpec setup; absence is common and fine):

```bash
if command -v openspec >/dev/null 2>&1; then
  openspec validate "<change-id>" --strict
fi
```

- CLI present and validation passes → echo the §11 success line.
- CLI present and validation fails → the files are written but malformed against OpenSpec's stricter checks. Surface the validator output in plain English and offer to fix it (re-author the flagged file, re-validate; max 2 rounds), then continue. A validation failure never blocks the plan commit — the Geniro spec is already approved and the OpenSpec change is the secondary artifact.
- CLI absent → skip validation silently; the files still conform to §4–§6, which is the format the CLI checks.

## 9. Lifecycle — write at approval, one commit

The OpenSpec change is written at Phase 8 AFTER the user approves the Geniro spec, and folded into the SAME commit:
- Write the §4 files only on the "Yes" pick (or `--openspec`).
- `git add <root>/changes/<change-id>/` alongside the Geniro `spec.md` (+ milestones) in the Phase 8 commit step, so one commit carries the plan and its OpenSpec duplicate.
- Record the write in the Geniro state.md `## Tool log` and add the written paths to the Phase 8 `non-resumable-actions[]` commit entry's `files` list.
- When the Phase 8 commit itself fails (pre-commit hook, dirty tree), remove the just-written `<root>/changes/<change-id>/` before surfacing the error — it was never committed, and the Geniro Phase 9 cleanup sweeps only `.geniro/`, so leaving it would orphan a stale change on disk.

Writing at approval (not at Phase 6 draft time) means an artifact the user declined is never created, and a plan revised before approval never leaves a stale OpenSpec change on disk; the commit-failure removal above closes the one remaining window where a stale change could survive.

## 10. Fail-open

| Situation | Behavior |
|---|---|
| `openspec/` absent | Integration dormant; no question, no write, no notice beyond nothing. |
| Detection check errors | Treat as not-detected; continue the plan unchanged. |
| A file write fails | Echo a one-line caveat naming the file; the Geniro spec commit still proceeds (the plan is the primary deliverable). Do not abort the plan over the secondary artifact. |
| `openspec` CLI absent | Skip validation; files still conform to the documented format. |
| `openspec validate` fails | Surface in plain English, offer a bounded fix loop (§8), never block the commit. |
| `--openspec` passed but not detected | Echo the §11 "not found" note; skip — never scaffold OpenSpec the team has not adopted. |

## 11. Plain-English echo

User-facing lines name what happened in plain words — never internal identifiers.

```
This repo uses OpenSpec — I can duplicate this plan into an OpenSpec change proposal too.
Created the OpenSpec change "add-two-factor-auth" and validated it — included in the plan commit. I matched the shape of your existing changes (same marker file and naming style).
Your OpenSpec commands refresh with `pnpm openspec:update` after a CLI release — run that yourself if the generated change looks out of date.
Created the OpenSpec change "add-two-factor-auth" (OpenSpec CLI not installed, so I skipped its validator — the files follow the standard format).
The OpenSpec validator flagged the change proposal — here's what it wants fixed, and I can fix it for you.
You passed --openspec, but this repo has no openspec/ directory yet — skipping. Run `openspec init` first if you want OpenSpec here.
Couldn't write the OpenSpec change file — your Geniro plan is saved and committed regardless.
```

## 12. Anti-rationalization

| Reasoning | Why it is wrong |
|---|---|
| "OpenSpec is detected, so replace the Geniro spec with the OpenSpec change and skip spec.md." | `/geniro:implement` consumes the Geniro `spec.md` — replacing it breaks the whole plan→implement pipeline. The OpenSpec change is a parallel, cross-linked duplicate, never a substitute. Write both. |
| "Writing under `openspec/` is writing source — that violates /geniro:plan's never-touch-source rule." | OpenSpec change files are markdown specs, task checklists, and requirement deltas — planning artifacts, the same class as spec.md, just in another tool's convention. They carry no executable code, are written only after the Phase 8 approval, and ship in the plan commit. That is planning, not implementation. |
| "Emit the OpenSpec change at Phase 6 alongside spec.md to mirror its lifecycle exactly." | The suggestion is offered at Phase 8 after the user approves; emitting earlier would create an artifact the user may decline, and a pre-approval revision would leave a stale change on disk. Write at approval, commit once. |
| "Skip the scenario — the requirement text already states the behavior." | OpenSpec `validate --strict` fails any requirement with zero scenarios. Every requirement needs at least one `#### Scenario:`; derive it from the Done Condition's observable signal when the plan gives no explicit case. |
| "`--openspec` was passed but there's no openspec/ dir — run `openspec init` to set it up." | Initializing a framework the team has not adopted is a bigger decision than this skill owns. Detection gates the integration; when not detected, note it and skip — the team runs `openspec init` themselves. |
| "The OpenSpec validator failed — abort the plan so nothing inconsistent ships." | The Geniro spec is already approved and is the primary deliverable; the OpenSpec duplicate is secondary. Surface the failure, offer a bounded fix, but never block the plan commit on the secondary artifact. |
| "Hand-write the OpenSpec files from the §4–§6 contract — my format is correct, no need to look at the repo's tooling." | The repo's own `/opsx:*` commands and `openspec` CLI are the authority on the exact shape its installed OpenSpec version expects — including files the generic contract can't anticipate (the per-change `.openspec.yaml` marker was discovered only by reading a real repo). Per §3.5, read an existing change and generate through the tooling first; the §4–§6 contract is the fallback, and an existing change outranks it on any difference. |
