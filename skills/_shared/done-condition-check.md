# Done-Condition check — clause-to-evidence mapping for the ship gate

Canonical clause→evidence cross-reference for the ship-time Done-Condition annotation. The orchestrator reads this inline (no grader agent). It maps each machine-checkable Done-Condition clause to the run-evidence that decides whether the clause is satisfied — pure cross-reference, no judgment authority: it tells the caller what to look at, never what to do about it. The caller (the spec author, surfaced through the user) owns the ship decision.

Consumer: `/geniro:implement` (Phase 3 Ship sub-step, before the ship-mode question — see `${CLAUDE_PLUGIN_ROOT}/skills/implement/implement-reference.md` §"Commit + Push + PR").

## When this applies

Spec-driven runs only. When the run resolved a real `spec.md`, parse its section 11 (Done Condition). When there is no spec (inline-task fallback), there is no section 11 — skip entirely.

## Clause classification

A section-11 clause is **machine-checkable** when it matches the validator's stopping-condition ontology — defined in `${CLAUDE_PLUGIN_ROOT}/skills/plan/validator-checks.md` §9 `stopping_condition` (the spec-time gate); `${CLAUDE_PLUGIN_ROOT}/skills/_shared/review-criteria/spec-compliance-criteria.md` §10 and this helper reference it. Do not re-define the regex set. The ontology covers these signal shapes:

- tests pass / green
- PR approved / merged
- telemetry / metric / log shows ...
- shipped / released to ...
- observable / verified / confirmed

A clause that matches **none** of these is free-text. Free-text clauses stay human-eyeball-only — never auto-graded. This is the guard against false-nags: a vague or narrative completion criterion the orchestrator cannot ground against evidence is left for the user's own eyes, not flagged as unmet.

## Clause-to-evidence mapping

For each machine-checkable clause, read the satisfied/unsatisfied verdict off already-collected run evidence — no new commands beyond the cheap PR-state read below:

| Clause shape | Satisfied when | Evidence source (already in hand) |
|---|---|---|
| tests pass / green | the latest test-runner verdict is `ALL_GREEN` | the Phase 2 / Phase 3 `test-runner-agent` Verdict block (`ALL_GREEN` / `HAS_FAILURES` / `INFRA_ERROR`) |
| observable / verified / confirmed | Phase 3 self-review exited clean (no surviving findings, no `## Accepted Findings` block) | the Phase 3 review-round summary + state.md `## Accepted Findings` presence |
| PR approved / merged | the PR exists and its state matches the clause | `gh pr view --json state,reviewDecision` on the branch's PR (state `MERGED`; `reviewDecision` `APPROVED`) — at ship time, before the PR is created, this is unsatisfied by construction |
| telemetry / metric / log shows ... | the diff emits the named metric / log at the named boundary | the CHANGED_FILES diff (the same artifact the spec-compliance reviewer cross-checks); a runtime-observation clause that needs a deployed system is unsatisfied at ship time |
| shipped / released to ... | the change is pushed / a PR is open to the named target | the chosen ship action's result (push ref / PR URL) — unsatisfied until the ship action runs |

A clause that depends on a post-ship runtime signal (telemetry from a deployed system, a human PR approval) is **affirmatively unsatisfied at ship time** by construction — that is the normal case the annotation surfaces, so the user ships knowing their own criterion is not yet met.

## What the caller does with the result

The caller annotates the existing ship-mode question text with one plain-English line per affirmatively-unsatisfied machine-checkable clause, then proceeds to fire the unchanged question. This helper supplies the evidence read; it never:

- fires its own question, edits the spec, or writes state;
- alters the ship-mode option labels (a verbatim allowlist) — the annotation attaches to question/description text only;
- changes the draft-vs-commit-grade push classification — a satisfied Done Condition still routes through the unchanged commit-grade gate;
- reads as ship authorization — surfacing an unmet clause opens the gate with more context, it never closes it.

## User-facing wording

Surface the clause in plain English, quoting the spec's own words, never the regex token or the field name `stopping_condition`:

- Good: "The spec's done-condition lists 'PR approved' — that's not true yet."
- Good: "Your done-condition says 'telemetry shows ≥1 successful use' — that can't be confirmed until this is deployed."
- Bad: "stopping_condition clause `PR (approved|merged)` unsatisfied." (surfaces the internal token; fails the fresh-user test.)
