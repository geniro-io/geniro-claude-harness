# Effort Scaling

Canonical complexity rubric for routing tasks to the correct pipeline depth.

Match planning depth to task complexity. **File count is a smell detector, not a complexity detector.** A 2-file migration + API contract change is Big. A 10-file rename propagation is Small.

Tiers: **Trivial / Small / Medium / Big**. Big-tier classification at /plan time triggers milestone-mode output (M5 emits per-milestone spec files); /implement (M4) consumes each milestone spec exactly like а single-spec input.

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
- **0 → Trivial** (must ALSO be 1-2 files, single module, unambiguous intent — otherwise round up to Small)
- **1-3 → Small**
- **4-6 → Medium**
- **7+ → Big**

## Step 3: Apply Planning Depth

| Size | Planning Depth |
|------|----------------|
| **Trivial** | `/plan` (M5) emits а minimal Goal + Approach + Steps spec; `/implement` (M4) consumes it as ordinary spec input. `/refactor` (M8 §6.3 Step 3): skip smell detection + smell evidence + independent reviewer + custom reviewers — orchestrator authors plan directly от scope-files. No Lane-mode branching exists в M4 — the runtime is constant. |
| **Small** | Lightweight spec: Goal + Approach + Steps (no wave grouping, no test scenarios table). `/plan` may skip skeptic-validation at this tier. `/refactor` (M8 §6.3 Step 3): full smell-detection in Phase 1 BUT skip smell evidence + independent reviewer + custom reviewers. |
| **Medium** | Standard spec: full structure from `plan-criteria.md`. `/plan` runs architect + skeptic. `/refactor` (M8 §6.3 Step 3): full pipeline — orchestrator-inline smell detection (§1.4) + orchestrator-inline smell evidence (§1.5) + reviewer-agent + custom reviewers. |
| **Big** | Full architect + skeptic spec at /plan time. If score 9+ or >15 steps → /plan switches into milestone-output mode (emits per-milestone spec files); `/implement` consumes each milestone spec individually. `/refactor` (M8 §6.3 Step 3): recommend running `/geniro:plan` first к split the refactor into independently shippable milestones; refactor then runs one milestone at а time against an approved spec.md. If user proceeds без а plan, Big runs the Medium pipeline (с accepted risk). |
