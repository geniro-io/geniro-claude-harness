<!-- Generated from skills/setup/phase-4-validate.md by scripts/build-cursor-skills.sh. Edit the source and re-run; do not edit this copy. -->

# Setup Phase 4 — Validate

Phase file for `/geniro:setup`. The spine — invariants, budgets, tool surface, anti-rationalization — is `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`.

### 4.1 Verification subagent spawn

```
Agent(subagent_type="general-purpose", # ad-hoc verification agent — spawns as general-purpose directly; the ${CLAUDE_PLUGIN_ROOT}/skills/_shared/spawn-agent.md ladder applies only if promoted to a plugin-defined agent
model="sonnet", # hardcode carve-out per ${CLAUDE_PLUGIN_ROOT}/skills/_shared/model-tiering.md — tier and its reason stated in §Subagent model tiering; keep the pin
prompt="""
You are a READ-ONLY verifier. The Agent tool has no per-spawn tool allowlist, so this
paragraph is the whole read-only floor: do not create, edit, or delete any file, and run no
mutating shell command — report DRIFT items and let the orchestrator regenerate the affected
sections. An edit from here would overwrite content the orchestrator is about to rewrite from
the detected project facts. Read, read-only Bash, Glob, and Grep are the whole job.

Validate the generated <PROJECT_ROOT>/CLAUDE.md against the codebase.

First, Read ${CLAUDE_PLUGIN_ROOT}/skills/setup/verification-checks.md and run every check it
defines (cross-language contamination, template artifact, generic-placeholder) — that
file is the single source for the contamination, template-residue and placeholder criteria, and
its per-language wrong-token table catches stack drift no fixed grep list would.

Then run these additional checks:
1. Every command in the `## Commands` section runs locally (try `bash -n` syntax check; do not execute).
2. Every claimed file path in `## Tech Stack` exists.
3. No Geniro-plugin content — report every entry of verification-checks.md's §Excluded content
   list that appears in the generated file. CLAUDE.md is project-only.

Output a markdown report:
## PASS items (one per line)
## DRIFT items (one per line with file:line)

Truncate at 4000 chars (drop trailing PASS items first; keep all DRIFT) — the bounded-results
invariant in ${CLAUDE_PLUGIN_ROOT}/skills/_shared/loop-invariants.md, bound here by loop
invariant #4.

Anchor: PROJECT_ROOT is your root — run every Bash call from it (`cd <PROJECT_ROOT> && …`) and resolve every file path under it.
"""
)
```

### 4.2 3-retry escalation loop

This section is the single source for the retry cap and round count — every SKILL.md site cites it rather than restating the numbers.

Rounds 1-3: spawn the verification subagent. If `DRIFT items` is empty → transition to Phase Done. Else → regenerate affected sections (jump back to Phase 3 for those sections only) and re-spawn.

Round 4 — **AUQ escalation:** `Accept with warnings (finish setup; remaining issues noted for next run) | Abort setup | Start over from the beginning (re-detect the codebase)`. On "Accept with warnings": state.md `phase: done` (DRIFT items stay logged in `## Open Questions`). On "Abort setup": state.md `phase: failed` (terminal). On "Start over": state.md `phase: detect` (non-terminal — re-run Phase 1).

`## Open Questions` accumulates DRIFT items across rounds — survives compaction.

### 4.3 Emit learning on successful Validate

On transition to DONE — emit one `discovery` learning row, then echo `Recorded learning: <summary>` to the user per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md` §"Caller contract":

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/emit-learning.sh"
emit_learning <<'EOF'
{
"producer": "/geniro:setup",
"scope": "global",
"type": "discovery",
"trust": "verified",
"mode": "init",
"tags": ["setup", "stack", "bootstrap"],
"summary": "bootstrap complete: node/npm/jest, ship_mode=open-PR-draft, full reviewer set",
"ext": {
"stack": "node/npm",
"test_runner": "jest",
"ship_mode_default": "open-pr-draft",
"reviewer_set": "full",
"claude_md_loc": 45
}
}
EOF
```

`trust: verified` per base schema (code-grounded — Detect read real files; no WebFetch). The `mode` field records the actual run mode — emit `"re-run"` instead of `"init"` when this fired on a re-run.

