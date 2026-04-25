# Effort Scaling

Canonical complexity rubric for routing tasks to the correct pipeline depth. Used by `/geniro:implement` (Phase 1 routing) and `/geniro:decompose` (Big task gate, <3-milestone fallback).

Match planning depth to task complexity. **File count is a smell detector, not a complexity detector.** A 2-file migration + API contract change is Big. A 10-file rename propagation is Small.

## Step 1: Check for Hard Escalation Signals

These signals force **Big** classification regardless of file count:

| Signal | Why it's hard |
|--------|---------------|
| New entity, table, or migration | Irreversible schema change |
| New API endpoint or new page/route | Cross-stack coordination, auth decisions |
| Auth, permissions, or role changes | Unbounded blast radius |
| New module or subsystem | Architectural decision, no existing pattern to follow |
| 3+ modules coordinated | Distributed coordination complexity |
| Open-closed principle violation | Modifying behavior for all consumers; regression risk unbounded |
| New async/queue/background work | Runtime failure modes not caught by tests |
| New external integration or env vars | Cross-cutting infrastructure |
| Ambiguous intent | Multiple valid design approaches |

**If ANY hard signal is present → Big, skip to Step 3.**

## Step 2: Assess Complexity Dimensions

If no hard signals, score these dimensions:

| Dimension | Low (0) | Medium (1) | High (2) |
|-----------|---------|------------|----------|
| **Task type** | Bug fix, rename, config change | Extend existing feature with existing patterns | New feature, greenfield, no exemplar to follow |
| **Cross-boundary scope** | Single module/layer | 2 layers (e.g., service + route) | 3+ layers (DB + API + UI) or cross-stack |
| **Reversibility** | Pure source code changes | New files + test changes | Stateful side effects (migrations, API contracts, external calls) |
| **Edit scatter** | Changes concentrated in 1-2 locations | 3-5 distinct edit sites | 6+ sites across different modules |
| **Pattern availability** | Strong exemplar exists in codebase | Partial pattern, needs adaptation | No existing pattern, greenfield design |

**Score: sum of all dimensions (0-10)**
- **0-3 → Small**
- **4-6 → Medium**
- **7+ → Big**

## Step 3: Apply Planning Depth

| Size | Planning Depth |
|------|----------------|
| **Small** | Lightweight plan: Goal + Approach + Steps (no wave grouping, no test scenarios table). Skip skeptic validation. Full plan print at approval is still mandatory. |
| **Medium** | Standard plan: full structure from `plan-criteria.md`. Architect + skeptic validation. |
| **Big** | Full architect + skeptic plan, single pass. If score 9+ or >15 steps → hand off to `/geniro:decompose` for milestone decomposition. |
