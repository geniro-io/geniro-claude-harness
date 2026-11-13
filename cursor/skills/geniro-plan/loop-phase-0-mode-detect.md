<!-- Generated from skills/plan/loop-phase-0-mode-detect.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Phase 0 — Mode detect

The spine is `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-loop.md`; this file carries the Steps.

State.md `phase: mode-detect` during this phase.

### 0.1 $ARGUMENTS resolution

**Opt-in flag detection.** Strip every recognized flag token from `$ARGUMENTS` before mode detection. state.md does not exist until §0.3, so carry each detected flag forward and write its field into the initial frontmatter there. The flags are orthogonal.

- **`--artifact`** → `artifact_mode: true` + `artifact_status: pending`. Turns on the live visual plan artifact (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md`) and IS the opt-in, so §0.2.5 skips its question. Absent: the §0.2.5 question decides whether artifact mode turns on.

**Launch-modifier detection (pre-fills `launch_config`).** Semantic-parse `$ARGUMENTS` for the `/geniro:plan` launch modifiers cataloged in `${CLAUDE_PLUGIN_ROOT}/skills/_shared/flags-reference.md` — workspace, ship (`don't push` / `no push` / `commit only` → commit-no-push, `draft only` → draft-pr, `ready-for-review`, `stop after review` → stop-after-review) and `freshness:merge` / `freshness:rebase` / `freshness:skip` (colon form only — bare `merge` / `skip` are too ambiguous inside a free-text topic). Strip the matched tokens before mode detection and carry the set forward: `freshness:` feeds §1.1b, the full set feeds §8.3.5. With none, both run interactively.

Use `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` helper unchanged. Returns:

- **IDEA(topic)** — free-form text; proceeds to Phase 1 with topic as initial context.
- **DESIGN_DOC(path)** — existing design doc; flows to AUQ.
- **CODE_REFERENCE(path)** — error per design-doc-detect.md per-consumer table: "code reference passed to /geniro:plan; pass a topic or design-doc path. Did you mean /geniro:implement <path>?". Exit without writing state.md.
- **None** (empty $ARGUMENTS) — fires empty-argument AUQ:
 - `header`: "Topic"
 - `question`: "What do you want to plan?"
 - `options[]` (single-select, 3 options + Other free-text): "New feature" / "Existing problem to solve" / "Cancel"
 - A free-text Other answer is the topic → IDEA mode. "New feature" / "Existing problem to solve" name only the kind of work: ask what it is in a plain chat question, wait, and use the reply as the topic — the option label would plan a task called "New feature". "Cancel" → terminal without state.md.
 - Persist outcome to `approvals[]` with `category: disambiguate_arguments` .

### 0.2 DESIGN_DOC mode question

Fire `AskQuestion` with:
- `header`: "Design doc"
- `question`: "Design doc already exists at `<path>`. What now?"
- `options[]` (single-select, 2 options):
 - **Start fresh with this as context** (Recommended) — load the doc into Phase 1 explore context; run the full planning loop (Phases 0–9; Phase 2 fires only when the UI trigger matches per §"Phase 2 — Visual Companion"); emit a new spec.md at a fresh task-dir.
 - **Cancel** — exit without writing state.md.

**On "Start fresh"** → flow to Phase 1 with the doc body inlined into Phase 1 research-agent prompts under a `## Prior Design Doc` section. The doc is NOT used as section template; Phase 5 uses the fixed section schema unconditionally.

**On "Cancel"** → exit immediately. Surface terminal message: "Cancelled before planning started".

There is no in-loop edit-existing-sections mode: edit an existing design doc directly and re-run `/geniro:plan` only to re-emit.

### 0.2.5 Visual artifact opt-in

After mode resolves and before the §0.3 state.md write. With the `--artifact` flag present the flag is the opt-in: skip the question. Without it, fire the single opt-in `AskQuestion` — literal template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1b. A "Yes" (or the flag) puts the run in artifact mode and the §0.3 frontmatter gets the artifact fields; "No" writes none. Persist the pick to `approvals[]` category `artifact_choice` so a resume doesn't re-ask.

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-artifact.md` only when the run is in artifact mode, starting from the §1.5 `loop-artifact-call-sites.md` read; a run that declines the page never loads it.

### 0.3 Task-dir + state.md creation

After mode is resolved (IDEA or DESIGN_DOC):

1. **Resolve task slug.** Inputs: $ARGUMENTS topic OR basename(design-doc) sans extension. Output: kebab-case slug ≤40 chars.
2. **Task-dir:** `.geniro/planning/<task-slug>/`.
3. **state.md:** `.geniro/planning/<task-slug>/state.md`, written via `atomic_state_write` from the frontmatter and body template in `${CLAUDE_PLUGIN_ROOT}/skills/plan/plan-auq-reference.md` §1. In artifact mode (`--artifact` or a §0.2.5 Yes) write `artifact_mode: true`, `artifact_status: pending` and an empty `artifact_url: ""` together — `atomic_state_set_field` only replaces an existing key, so without the placeholder the first publish's URL write fails; omit all three otherwise.
4. **Transition.** Set `phase: explore` via `atomic_state_set_field` and proceed to Phase 1.

### 0.4 Cancel handling

If state.md already created when user cancels (e.g., deep cancel via Other): append `## Termination reason: user-cancelled-at-phase-0` via `atomic_state_append_section --create` (the section is new), THEN set `phase: aborted` via `atomic_state_set_field`, before exit. Reason first: a crash between the two then leaves a run reading as in-progress, not aborted with no reason recorded.
