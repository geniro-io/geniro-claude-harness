# /geniro:plan Reference (M5)

Companion reference for less-common usage paths of `/geniro:plan`. The main flow lives в `${CLAUDE_SKILL_DIR}/SKILL.md`; this file documents edge cases, the deprecation alias note, и the shared rules consumed.

---

## DESIGN_DOC mode — no refine path

The Phase 0 DESIGN_DOC AUQ has 2 options (per `plan-loop.md` §0.2):

- **Start fresh с this as context** (Recommended) — the prior doc is inlined into Phase 1 Explore-agent prompts under а `## Prior Design Doc` section. Phase 5 uses the §17 10-section schema unconditionally — the prior doc is context, не template.
- **Cancel** — exit без writing state.md.

If the user really wants к surgically edit an existing design doc bypassing Phase 1-4, the correct path is к open the doc directly в an editor + manually update sections + re-run `/geniro:plan` only when ready к re-emit. /plan does NOT have an in-loop «edit existing sections» mode.

---

## Edge cases

- **Empty $ARGUMENTS** — Phase 0 §0.1 fires an `AskUserQuestion` с 3 options ("New feature" / "Existing problem к solve" / "Cancel") followed by free-text capture. Non-empty answer → IDEA mode; "Cancel" → terminal без state.md.

- **Topic spans multiple subsystems / very Big task** — the plan-loop completes normally (Phase 5 §5.3 milestone-mode fires automatically when effort tier is Big + Steps count ≥10 или wall-time ≥1 day). The Phase 9 hand-off recommends `/implement milestone 1` for sliced specs.

- **User wants к plan WITHOUT writing а spec.md** — not supported. The committed spec.md IS the durable artifact downstream skills (М4 /implement, М6 /review) consume via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. If the user insists, run /plan, pick "Stop — keep spec для later" at Phase 9 (terminal `done`, spec sits on disk но not committed). The three detection markers must still be present per Phase 6 contract.

- **`mode=CODE_REFERENCE`** — error и exit per Phase 0 §0.1 (design-doc-detect helper returns CODE_REFERENCE → /plan emits error: «code reference passed к /plan; pass а topic or design-doc path. Did you mean /geniro:implement <path>?»). Do NOT fall back к `mode=IDEA` — silent misclassification of code references is the failure mode `design-doc-detect.md` Anti-rationalization warns against.

- **Compaction mid-Phase-5** — handled by М3 SessionStart re-injection of state.md `approvals[]` (P-M1-1) и `## Tool log`. The model re-reads `approvals[]` и skips already-answered AUQs; Phase 6 §6.4 idempotent re-entry regenerates spec.md от persisted approvals.

- **Phase 7 validator hard-fail on round 3** — `plan-loop.md` §7.3 escalation AUQ fires с 3 options (accept-as-is / re-revise / abort). User has agency; no silent abort.

- **Phase 8 user-revision round 3 exhaust** — `plan-loop.md` §8.3 escalation AUQ fires с 3 options (accept-as-is / re-revise / abort). Terminal `aborted` records `## Termination reason: repeated-failure: phase-8 revision-limit-3`.

- **Concurrent /plan runs in different worktrees** — each worktree has its own `.geniro/planning/<task-slug>/state.md`.

---

## Cross-references

Shared rules consumed by this skill:

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/plan-loop.md` — canonical 9-phase loop (Phases 0-9 of this skill).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — Phase 0 mode detection algorithm; per-consumer behavior table for `/geniro:plan`.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` — `AskUserQuestion` schema for the Phase 0 AUQ, the empty-argument fallback, и the Phase 9 hand-off menu.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` — multi-select picker schema for Phase 5 §5.3 milestone-name approval.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/effort-scaling.md` — tier rubric used by Phase 1 §1.2 effort-tier-scaled spawns и Phase 5 §5.3 milestone-mode trigger.
- `${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh` — М1 state.md write helper.
- `${CLAUDE_PLUGIN_ROOT}/lib/validate-state-file.sh` — М1 state.md validator for resume.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/load-custom-instructions.md` — L4 directive doc (Phase 1 entry refresh).
- `${CLAUDE_PLUGIN_ROOT}/lib/load-semantic.sh` — L3 read helper (Phase 1 entry).
- `${CLAUDE_PLUGIN_ROOT}/lib/query-learnings.sh` — L2 read helper (Phase 1 entry).
- `${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh` — L2 write helper (Phase 8 conditional `decision` emit).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/resolve-conflicts.md` — cross-layer L4/L3/L2 conflict protocol.
- `${CLAUDE_SKILL_DIR}/spec-template.md` — 10-section P-M5-1 schema template (Phase 6 input).
- `${CLAUDE_SKILL_DIR}/validator-checks.md` — 13 mechanical checks (Phase 7 input).
- Architecture spec: `architecture/M5-plan-redesign.md`.
