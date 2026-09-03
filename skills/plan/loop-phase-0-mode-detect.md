# Phase 0 — Mode detect

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: mode-detect` during this phase. Light cost — a single design-doc-detect.md helper call.

### 0.1 $ARGUMENTS resolution

**Opt-in flag detection.** Strip every recognized flag token from `$ARGUMENTS` before passing the remaining text to mode detection. state.md does not exist yet — it is created in §0.3 — so write no frontmatter here; carry each detected flag forward and write its field into the INITIAL frontmatter at the §0.3 creation step. The flags are orthogonal; any combination may be passed.

- **`--deep`** (semantic-parse `--deep` / `deep` / `deep mode`) → `deep-mode: true` (false/omitted when absent), plus an `approvals[]` entry with category `deep_mode_choice`. Deepens Phase 4 (judge-panel approach search + 3× feasibility critics) and Phase 7.5 (3× claim verification) per `${CLAUDE_PLUGIN_ROOT}/skills/plan/deep-mode-reference.md`. Absent: those phases run their standard single-pass paths unless the user picks Deep at the Phase 3 wrap-up depth question (rules + AUQ shape in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §2a).
- **`--artifact`** → `artifact_mode: true` + `artifact_status: pending`. Turns on the live visual plan artifact (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`) and IS the opt-in, so §0.2.5 skips its question. Absent: the §0.2.5 question decides whether artifact mode turns on.

**Launch-modifier detection (opt-in pre-fill of `launch_config`).** `/geniro:plan` also recognizes the `/geniro:implement` launch modifiers so a `/plan <topic> worktree ship:draft` invocation pre-fills the plan's `launch_config` block instead of discarding them. Semantic-parse `$ARGUMENTS` for the workspace modifiers (`new-branch` / `current-branch` / `worktree` / `no-worktree` / `here`), the ship modifiers (`don't push` / `no push` / `commit only` → commit-no-push, `draft only` → draft-pr, `ready-for-review` → ready-for-review, `stop after review` → stop-after-review), and a `freshness:merge` / `freshness:rebase` / `freshness:skip` modifier (colon form only — bare `merge` / `skip` are too ambiguous inside a free-text planning topic); `--deep` is already handled above. Strip the matched tokens from the topic text before mode detection, then carry the recognized set forward to two places: the `freshness:` token feeds §1.1b (the Phase 1 branch-freshness step applies the strategy directly), and the full launch-modifier set feeds §8.3.5 to pre-fill `launch_config` non-interactively. When no launch modifier is present, both steps run their interactive paths.

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; proceeds to Phase 1 with topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows to AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table: "code reference passed to /geniro:plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?". Exit without writing state.md.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ:
 - `header`: "Topic"
 - `question`: "What do you want to plan?"
 - `options[]` (single-select, 3 options + Other free-text): "New feature" / "Existing problem to solve" / "Cancel"
 - Non-empty answer (via a picked option OR free-text Other) → IDEA mode; "Cancel" → terminal without state.md.
 - Persist outcome to `approvals[]` with `category: disambiguate_arguments` .

### 0.2 DESIGN_DOC mode AUQ

Fire `AskUserQuestion` with:
- `header`: "Existing design doc"
- `question`: "Design doc already exists at `<path>`. What now?"
- `options[]` (single-select, 2 options):
 - **Start fresh with this as context** (Recommended) — load the doc into Phase 1 explore context; run the full planning loop (Phases 0–9; Phase 2 fires only when the UI trigger matches per §"Phase 2 — Visual Companion"); emit a new spec.md at a fresh task-dir.
 - **Cancel** — exit without writing state.md.

**On "Start fresh"** → flow to Phase 1 with the doc body inlined into Phase 1 research-agent prompts under a `## Prior Design Doc` section. The doc is NOT used as section template; Phase 5 uses the fixed section schema unconditionally.

**On "Cancel"** → exit immediately. Surface terminal message: "Cancelled before planning started".

There is no in-loop edit-existing-sections mode. To surgically revise an existing design doc, edit it directly and re-run `/geniro:plan` only when ready to re-emit.

### 0.2.5 Visual artifact opt-in

After mode resolves (IDEA or DESIGN_DOC) and before the §0.3 state.md write. When the `--artifact` flag was present in §0.1, skip this question — the flag is the opt-in, the run is in artifact mode. When the flag was absent, fire the single opt-in `AskUserQuestion` — literal template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1b. On the "Yes" pick (or flag present) the run is in artifact mode — the §0.3 frontmatter gets `artifact_mode: true` + `artifact_status: pending`; on "No" artifact mode stays off and no artifact fields are written. Persist the pick to `approvals[]` category `artifact_choice` so a resume doesn't re-ask.

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` only when the run is in artifact mode — the user picked "Yes" or the `--artifact` flag was passed — starting from the §1.5 `loop-artifact-call-sites.md` read; a run that declines the page never loads the lifecycle helper.

### 0.3 Task-dir + state.md creation

After mode is resolved (IDEA or DESIGN_DOC):

1. **Resolve task slug.** Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/`.
3. **state.md:** `.geniro/planning/<task-slug>/state.md`. Write via `atomic_state_write`. Full frontmatter + body template (frontmatter fields `tier`/`producer`/`schema-version`/`branch`/`worktree`/`timestamp`/`phase`/`status`/`non-resumable-actions`/`approvals`/`task_slug`/`mode`; plus `deep-mode: <true|false>` from the `--deep` flag in §0.1 (false when absent); plus `artifact_mode: true` and `artifact_status: pending` written together when artifact mode is on (the `--artifact` flag was present OR the §0.2.5 opt-in answered Yes), both omitted otherwise; body sections `# State: <topic>` / `## Inputs` / `## Tool log` / `## Errors` / `## Open Questions`) in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1.
4. **Transition.** Set `phase: explore` via `atomic_state_set_field` and proceed to Phase 1.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): append `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_append_section`, THEN set `phase: aborted` via `atomic_state_set_field`, before exit. Reason first: a crash between the two then leaves a run that still reads as in-progress rather than one marked aborted with no reason recorded.
