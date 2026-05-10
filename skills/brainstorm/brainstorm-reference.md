# Brainstorm Reference

Companion reference for less-common usage paths of `/geniro:brainstorm`. The main flow lives in `${CLAUDE_PLUGIN_ROOT}/skills/brainstorm/SKILL.md`; this file documents refinement entry, edge cases, hand-off pre-fill, and the shared rules consumed.

---

## Refining an existing design

When Phase 0 mode detection returns `mode=DESIGN_DOC` and the user picks **Refine** from the Phase 0 AUQ, the brainstorming loop does NOT restart from Phase 1. Loop entry point:

- **Read the design doc in full** — the existing sections become the starting state.
- **Jump to `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` Phase 5** (Section approval) with each existing section pre-rendered as the AUQ subject. The user can Approve / Revise / Skip per the loop's section-by-section contract.
- **Phase 1 (explore), Phase 2 (visual), Phase 3 (clarifying), Phase 4 (approaches) are skipped** — the existing doc has already encoded the explore findings and decisions. Re-running them would invalidate prior section work.
- **Phase 6 (write), Phase 7 (self-review), Phase 8 (user re-review) run normally** — the revised doc is committed (new commit, not amend) and re-audited. The HARD-GATE remains binding until Phase 8 returns Approve.

Cap the Phase 5 revision loop at 3 rounds per the loop's existing cap. If a section will not converge after 3 rounds, surface the loop's "re-open Phase 3 / Phase 4" AUQ — Refine may have been the wrong entry; the user can pivot to a Start-over.

---

## Edge cases

- **Empty `$ARGUMENTS`** — fire `AskUserQuestion` per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`:
  - `header`: `"Topic"`.
  - `question`: `"What are you thinking about?"`.
  - `options[]`: include `Other` so the user can free-text the topic. Treat the response as `mode=IDEA, topic=<response>` and continue at Phase 1 of the brainstorming loop.
  - Empty AUQ answer = upstream Claude Code bug per `medium-gate.md`; fall back to plain text and re-ask. Never auto-default.

- **Topic spans multiple subsystems** — the brainstorming loop completes normally (one design doc), but the Phase 9 hand-off should recommend `Decompose into milestones`. Surface the multi-subsystem signal in the Phase 9 AUQ description so the user sees the recommendation. Do not auto-pick — the menu is single-select Always-WAIT.

- **User wants to brainstorm WITHOUT writing a doc** — not supported. The committed doc is the durable artifact downstream skills consume via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md`. If the user insists, write a minimal doc (Phase 5 trivial = 1-2 sections) and let them prune it manually post-commit. The three detection markers must still be present per the loop's Phase 6 contract.

- **`mode=CODE_REFERENCE`** — error and exit per SKILL.md Phase 0. Do NOT fall back to `mode=IDEA` (silent misclassification of code references is the failure mode `design-doc-detect.md` Anti-rationalization warns against).

---

## Skipping the hand-off menu

The Phase 9 hand-off menu is Always-WAIT — auto-routing destroys the Big-vs-Small decision the user owns. However, when `$ARGUMENTS` already contains an unambiguous hand-off signal, the orchestrator MAY pre-fill the AUQ default selection so the user can confirm with one click.

- **Forbidden:** `--implement`, `--decompose`, `--backlog` flags (per the flag-free principle in `design-doc-detect.md` Anti-rationalization — adding flags duplicates information and fragments the surface).
- **Allowed signals (natural language in the topic string):**
  - `"brainstorm and then implement <topic>"` → pre-select **Implement directly** in Phase 9 AUQ.
  - `"brainstorm and then decompose <topic>"` → pre-select **Decompose into milestones**.
  - `"brainstorm and add to backlog <topic>"` → pre-select **Add to backlog**.

Pre-fill means the option is highlighted as the default; the user still confirms via `AskUserQuestion`. Never auto-execute the hand-off without the AUQ — same Always-WAIT contract as `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md`.

---

## Cross-references

Shared rules consumed by this skill:

- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/brainstorming-loop.md` — canonical 8-phase ideation loop (Phases 1-8 of this skill).
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/design-doc-detect.md` — Phase 0 mode detection algorithm; per-consumer behavior table for `/geniro:brainstorm`.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/medium-gate.md` — `AskUserQuestion` schema for the Phase 0 Refine/Start-over/Cancel gate, the empty-argument fallback, and the Phase 9 hand-off menu.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ui-preview-gate.md` — invoked from brainstorming-loop Phase 2 when a UI signal fires.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/branch-naming.md` — slug derivation for the design-doc path (`<branch>` segment).
