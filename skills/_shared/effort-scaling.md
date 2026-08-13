# Effort scaling

Canonical complexity rubric for routing tasks to the correct pipeline depth.

Match planning depth to task complexity. **File count is a smell detector, not a complexity detector.** A 2-file migration + API contract change is Big. A 10-file rename propagation is Small.

Tiers: **Trivial / Small / Medium / Big**. Big-tier classification at /geniro:plan time triggers milestone-mode output (emits per-milestone spec files); /geniro:implement consumes each milestone spec exactly like a single-spec input.

## Step 1: Check for hard escalation signals

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

## Step 2: Assess complexity dimensions

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

## Step 3: Apply planning depth

| Size | Planning Depth |
|------|----------------|
| **Trivial** | `/geniro:plan` emits a minimal Goal + Approach + Steps spec; `/geniro:implement` consumes it as ordinary spec input. `/geniro:refactor`: skip smell detection + smell evidence + independent reviewer + custom reviewers — orchestrator authors plan directly from scope-files. |
| **Small** | Lightweight spec: Goal + Approach + Steps (no wave grouping, no test scenarios table). `/geniro:plan` skips the Phase 4 codebase-grounded critic agents at this tier — unless Phase 4 produced ≥2 genuinely competing approaches, in which case it spawns 1 comparative critic (as for Medium). `/geniro:refactor`: skip smell detection + smell evidence + independent reviewer + custom reviewers — orchestrator authors the plan directly from scope-files. |
| **Medium** | Standard spec: the full section structure `spec-template.md` defines. `/geniro:plan` authors the full spec and spawns one Phase 4 codebase-grounded critic agent to stress-test the approaches. `/geniro:refactor`: full pipeline — orchestrator-inline smell detection + orchestrator-inline smell evidence + reviewer-agent + custom reviewers. |
| **Big** | Full spec at /geniro:plan time, with one Phase 4 codebase-grounded critic agent per generated approach (parallel). If score 9+ or >15 steps → /geniro:plan switches into milestone-output mode (emits per-milestone spec files); `/geniro:implement` consumes each milestone spec individually. `/geniro:refactor`: recommend running `/geniro:plan` first to split the refactor into independently shippable milestones; refactor then runs one milestone at a time against an approved spec.md. A wide mechanical refactor (renaming a shared column, retyping a shared symbol) cannot slice vertically — one edit breaks every call site at once; sequence it expand–contract instead: milestone-1 adds the new form beside the old, middle milestones migrate call sites in batches (per package or directory) while CI stays green because the old form still exists, and the final milestone deletes the old form once no caller remains. If user proceeds without a plan, Big runs the Medium pipeline (with accepted risk). |
