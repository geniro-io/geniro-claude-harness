# M2 — Memory Layer Architecture

**Status:** Specification (pre-implementation)
**Scope:** Layer model, schemas, lifecycle, loading mechanism, conflict resolution, secrets handling
**Depends on:** M1 (planning artifacts: T1 per-task scratch, T3 append-only learnings.jsonl)
**Followed by:** M3 (compaction-survival hook strategy), M4+ (per-skill writer/reader integration)

---

## 1. Purpose

Define a coherent multi-layer memory model for the plugin so that:

- Every fact/rule/event has a single canonical home (no duplication, no ambiguity).
- Writers (pipeline skills) know **what** to record, **where**, and **when**.
- Readers (pipeline skills) know **which layer** answers their question and **how to retrieve** it.
- Stale content surfaces explicitly instead of silently misleading future sessions.
- Loading works regardless of whether `.geniro/` is checked-in or gitignored.

---

## 2. Layer model (4 canonical layers)

| Layer | Name | Lifespan | Purpose |
|---|---|---|---|
| L1 | Working | Per-task | Live state of the current run (phase, status, pending decisions). Inherits T1 from M1. |
| L2 | Episodic | Append-only event log | Things that happened — diagnoses, decisions, conventions discovered, pitfalls hit, discoveries made. Inherits T3 from M1. |
| L3 | Semantic | Current-state snapshot | Always-currently-true facts about the project — tech stack, architecture, module map, feature backlog. |
| L4 | Procedural | Stable rules | User-curated rules and procedures — code style, workflow conventions, custom review dimensions. |

These four layers map onto the standard cognitive-memory taxonomy (working / episodic / semantic / procedural). Anything that does not fit one of the four is by definition out of scope for the memory subsystem.

---

## 3. Mapping rule (writer-intent)

A new fact is placed into a layer based on the writer's intent, not arbitrary file location:

| Writer's intent (in plain English) | Layer | Example |
|---|---|---|
| "Right now, phase X of task Y is running." | L1 | `state: phase=3, status=red` |
| "In this run we observed event X." | L2 | "5 May `/debug` found stale closure in Toggle.tsx" |
| "In this project, fact X is currently true." | L3 | "uses pnpm 9.x + Vite 5" |
| "When doing X, always do Y." | L4 | "useEffect deps must include all reads" |

**Hybrid observations are normal and expected.** A single discovery often produces records in two or three layers (an `/debug` finding may emit a diagnosis to L2, update L3 if it revealed a missed module dependency, and prompt the user to add an L4 convention). This is correct — each layer captures a different aspect and decays on a different cadence.

---

## 4. File layout

```
.geniro/
├── planning/                             # L1 Working (M1 T1) + L3 Semantic (M1 T3 CRUD)
│   ├── <task-dir>/                       # L1 Working (M1 contract)
│   │   └── ...
│   ├── _project.md                       # L3 Semantic — Tech stack (stable); top of L3
│   ├── _architecture.md                  # L3 Semantic — Patterns (manual)
│   ├── _CODEBASE_MAP.md                  # L3 Semantic — Module/file index (bounded auto-incremental)
│   ├── _FEATURES.md                      # L3 Semantic — Feature backlog (via /plan [M5] or manual edit; /features skill deleted per master plan §68)
│   ├── _focus-<area>.md                  # L3 Semantic — Deep dives (manual)
│   ├── .fingerprint.json                 # L3 drift detection — hashes of package.json, tsconfig, etc.
│   └── .codebase-map.lock                # L3 advisory race-safety lock for _CODEBASE_MAP.md writes
├── knowledge/
│   ├── learnings.jsonl                   # L2 Episodic (append-only)
│   ├── .redaction-log.jsonl              # Audit log for sanitization
│   └── archive/
│       └── learnings-YYYY-Qn.jsonl       # Lazy-archived L2 entries
├── instructions/                         # L4 Procedural
│   ├── global.md
│   ├── code-style.md
│   ├── <skill>.md
│   └── review-extra/
│       └── <slug>.md
└── safety.json                           # Existing; extended with redaction config
```

**Note on co-location of L1 and L3 in `planning/`:** M1 §Architecture overview decided to keep persistent L3 registry files under `.geniro/planning/_*.md` (alongside the L1 task-dirs) rather than introduce а separate `.geniro/semantic/` directory. The `_` prefix gives users а visual cue that these are persistent-global vs ephemeral task-dirs. Validators enforce tier-by-frontmatter, not path-prefix.

**CLAUDE.md is not part of this layout.** The plugin never writes to or imports from CLAUDE.md (see §8).

---

## 5. L2 Episodic — schema, lifecycle, reflection, sanitization

### 5.1 Schema (hybrid: base + typed extension)

**Required base fields (every entry):**

| Field | Type | Description |
|---|---|---|
| `ts` | ISO-8601 string | Write timestamp |
| `producer` | string | Emitting skill (e.g. `/geniro:debug`) |
| `scope` | string | File path / module / `global` |
| `summary` | string | One-line essence (used in retrieval display) |
| `tags` | array of strings | Searchable labels (e.g. `["bug", "react", "useEffect"]`) |

**Optional base fields:**

| Field | Type | Description |
|---|---|---|
| `body` | string | Longer narrative |
| `links` | array of strings | URLs (PR, issue, commit) |
| `dedup_key` | string | Writer-supplied dedup key; if absent, computed as `sha256(producer + "\|" + scope + "\|" + normalize(summary))[:12]` |
| `supersedes` | string | `dedup_key` of an earlier entry this one invalidates |
| `deprecated` | bool | Marks entry stale (kept on disk, excluded from default retrieval) |
| `trust` | enum: `verified` \| `retrieved` \| `inferred` | **(P-M2-3)** Source confidence level. `verified` = grounded в code или test execution; `retrieved` = sourced from external content (web fetch, MCP comments, third-party docs); `inferred` = model deduced from indirect signals. Default per emitter (see §5.3 table). Readers may filter via `--min-trust verified` или surface trust level в displayed summaries. Trust = source confidence, NOT correctness confidence. |

**Optional typed extension (writer adds when a known type fits):**

| `type` | Required `ext.*` fields | When emitted |
|---|---|---|
| `diagnosis` | `symptom`, `root_cause`, `fix` | `/debug` after hypothesis CONFIRMED + fix applied |
| `decision` | `options[]`, `chosen`, `reasoning` | `/plan` (M5) records chosen approach + considered alternatives in emitted `spec.md` |
| `convention` | `rule` | `/review` saw same finding pattern in ≥3 reviewer outputs; `/implement` self-review (M4 §7.2 architecture/code-quality dimensions) detected ≥3 instances in changed code (replaces deleted `/learnings` skill per master plan §69) |
| `pitfall` | `trap`, `mitigation` | `/refactor` discovered a footgun; `/review` stratified high-severity finding |
| `discovery` | `area`, `insight` | `/onboard` mapped non-obvious pattern; `/investigate` answered after >3 search rounds |
| `discarded_hypothesis` | `hypothesis`, `evidence_against`, `tested_by` | **(P-X8-1)** `/debug` Phase 1 §1.5 — every hypothesis transitioned to `Status: rejected`. Sliding-window cap = 5 latest per `(producer, scope)`; older entries auto-supersede with `deprecated: true`. |
| `user_rejected_suggestion` | `suggestion`, `auq_category`, `rejection_signal` | **(P-X8-2)** Any skill — emit when AUQ resolution picks non-recommended option OR explicit cancel/no/skip. No sliding-window cap (preferences are high-signal; supersede chain handles natural updates). |
| `retry_failure_sequence` | `phase`, `attempts[]`, `resolution` | **(P-X8-3)** `/implement` Phase 2, `/debug` Phase 2, `/refactor` Phase 2 — final exit if retry_count ≥ 2. Sliding-window cap = 3 latest per `(producer, scope, phase)`. |

Unknown/free-form entries (no `type`) are valid — minimum is the required base.

**P-X8 optional base fields:**

| Field | Type | Description |
|---|---|---|
| `access_count` | int (≥0) | **(P-X8-4)** Number of times this entry was returned by `query-learnings`. Auto-incremented by `record_access` sub-helper. Absent = 0. Used in `--score-min` ranking (recency × trust × access). |

**Example entries:**
```jsonl
{"ts":"2026-05-16T14:23:00Z","producer":"/geniro:debug","scope":"src/components/Toggle.tsx","summary":"Stale closure in useEffect — value missing from deps","tags":["bug","react","useEffect"],"type":"diagnosis","ext":{"symptom":"toggle stale","root_cause":"missing dep","fix":"add value to deps array"}}
{"ts":"2026-05-16T15:10:00Z","producer":"/geniro:implement","scope":"global","summary":"chose fetch over axios","tags":["arch","http"],"type":"decision","ext":{"options":["axios","fetch"],"chosen":"fetch","reasoning":"fewer deps, native AbortController"}}
{"ts":"2026-05-16T16:00:00Z","producer":"/geniro:implement","scope":"global","summary":"migrated to vite","dedup_key":"c3d4e5f6","supersedes":"a1b2c3d4","tags":["arch","build"]}
```

### 5.2 Lifecycle

**Write side (`_shared/emit-learning.md` helper):**
1. If `dedup_key` is not supplied, compute `sha256(producer + "|" + scope + "|" + normalize(summary))[:12]`.
2. Run sanitization pass on string fields (see §5.4).
3. Scan the last 200 entries of `learnings.jsonl` for a matching `dedup_key`:
   - Match found, identical content → skip (no-op).
   - Match found, different content → append with auto-injected `supersedes: <old_key>` (last write wins).
   - No match → append fresh.
4. Writer may also explicitly set `supersedes` to invalidate older entries (e.g. when `/debug` proves a prior diagnosis incorrect).

**Read side (`_shared/query-learnings.md` helper):**
1. Query by combination of `type`, `tags`, `scope` filters.
2. Filter out any entry whose `dedup_key` appears as `supersedes` in a later entry (last-write-wins by `ts`).
3. Filter out `deprecated: true` by default.
4. Optionally include superseded (`--include-superseded`) for historical/audit context.
5. Optionally search archive (`--include-archive`) for cold history.

**Archive:** (post-redesign: `/learnings` skill deleted per master plan §69 — archival is now а manual operation)
- Threshold guidance: when `learnings.jsonl` exceeds 10 MB or 5,000 lines, а one-line notice surfaces in `/implement` или `/debug` post-run summary suggesting manual archival.
- Archive path: `.geniro/knowledge/archive/learnings-YYYY-Qn.jsonl` (quarterly rollups). User moves cold entries manually via file operations or а scripted one-liner.
- Manual control: edit `learnings.jsonl` directly to add `deprecated: true` to entries, or move к archive/ subdir.

**Manual deprecation:**
- Edit `learnings.jsonl` directly to mark entries `deprecated: true` (excluded from retrieval by readers but kept on disk for audit trail). No interactive command — direct file edit.

### 5.3 Reflection cycle (when to emit)

**Auto-emit triggers per skill (concrete observable signals, not subjective interestingness):**

| Skill | Trigger | Type | Default trust (P-M2-3) |
|---|---|---|---|
| `/geniro:debug` | Hypothesis tracking shows FALSIFIED → CONFIRMED + fix applied | `diagnosis` | `verified` |
| `/geniro:plan` (M5) | `spec.md` records chosen approach with considered alternatives | `decision` | `verified` |
| `/geniro:implement` (M4) | Self-review reviewer-agent (architecture or code-quality dimension §7.2) detects ≥3 instances of same pattern in changed code | `convention` | `verified` |
| `/geniro:implement` (M4) | Inline-task mode (no /plan available) where Phase 1 produced an inline approach choice — mirrors `/plan`'s `decision` emit для cross-session recall | `decision` | `verified` |
| `/geniro:review` | `relevance-filter-agent` aggregated same finding from ≥3 reviewers | `pitfall` | `verified` |
| `/geniro:refactor` | Pattern extracted to shared utility/component | `discovery` | `verified` |
| `/geniro:onboard` | Non-obvious architectural pattern documented | `discovery` | `verified` |
| `/geniro:investigate` | Question answered after >3 search rounds | `discovery` | `retrieved` if WebFetch/WebSearch used; `verified` if code-grounded only |
| `/geniro:debug` (P-X8-1) | Phase 1 §1.5 — hypothesis transitioned to `Status: rejected` | `discarded_hypothesis` | `verified` |
| Any skill (P-X8-2) | AUQ resolution: picked-option ≠ recommended OR explicit cancel/no/skip | `user_rejected_suggestion` | `verified` |
| `/geniro:implement` (P-X8-3) | Phase 2 §6.3 final exit, self-review fix-loop retry_count ≥ 2 | `retry_failure_sequence` | `verified` |
| `/geniro:debug` (P-X8-3) | Phase 2 §2.5 final exit, fix_attempts ≥ 2 | `retry_failure_sequence` | `verified` |
| `/geniro:refactor` (P-X8-3) | Phase 2 exit, blocked_count ≥ 2 | `retry_failure_sequence` | `verified` |

**Manual:** post-redesign, `/learnings` skill is deleted (master plan §69). Manual curation = direct `learnings.jsonl` edits (mark `deprecated: true`, archive cold entries, etc. — see §5.2 Archive sub-section).

**Stop-hook reminder removed:** previous spec drafts proposed а Stop-hook warning when `/debug` finished without emitting а `diagnosis` entry, suggesting `/geniro:learnings`. Since `/learnings` is deleted (master plan §69) AND auto-emit is now the canonical path (Phase-end auto-step в `/implement` and `/debug` per master plan §69), the reminder is obsolete. If `/debug` resolves without emitting а diagnosis, that's а bug в `/debug` (M7 design owns the fix), not а user-actionable reminder.

### 5.4 Secrets sanitization

`_shared/emit-learning.md` runs a regex pass over `summary`, `body`, and string fields inside `ext.*` before append.

**Auto-redacted patterns:**

| Pattern | Replacement |
|---|---|
| JWT (`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`) | `[REDACTED:jwt]` |
| AWS access key (`AKIA[0-9A-Z]{16}`) | `[REDACTED:aws-key]` |
| AWS secret (`aws_secret_access_key\s*=\s*[A-Za-z0-9/+=]{40}`) | `[REDACTED:aws-secret]` |
| Anthropic/OpenAI/Stripe/GitHub/Slack API keys (provider-prefixed: `sk-`, `sk-ant-`, `pk_(live\|test)_`, `ghp_`, `xoxb-`) | `[REDACTED:api-key:<prefix>]` |
| `Bearer <token>` | `Bearer [REDACTED:bearer]` |
| URL credentials (`https?://[^:]+:[^@]+@`) | `https://[REDACTED:url-cred]@` |
| `-----BEGIN (RSA \| OPENSSH \| EC \| PGP )?PRIVATE KEY-----...-----END...` | `[REDACTED:private-key]` |
| Generic high-entropy ≥32 chars (mixed case + digits) | Warn-only flag (no auto-redact — false-positive risk on legit hashes) |

**Audit log:** each redaction appends an entry to `.geniro/knowledge/.redaction-log.jsonl`:
```jsonl
{"ts":"2026-05-16T...","producer":"/geniro:debug","field":"ext.body","pattern":"jwt","redacted_chars":156,"entry_dedup_key":"a1b2c3d4"}
```

**Extensibility (`.geniro/safety.json`):**
```json
{
  "redaction": {
    "additional_patterns": [
      {"name": "internal-token", "regex": "INT-[A-Z0-9]{16}", "replacement": "[REDACTED:internal]"}
    ],
    "ignore_patterns": ["high-entropy"],
    "audit_log_enabled": true
  }
}
```

**Backward scan:** historical `learnings.jsonl` (and archive) entries written before the pattern set was extended are NOT auto-redacted. `/learnings` skill is deleted (master plan §69), so audit happens manually during one-shot M2 migration (§11 step 3) and ad-hoc thereafter via direct `grep -P` over `learnings.jsonl` against `_shared/emit-learning.md` regex set — report-only, user reviews and patches any historical secrets manually.

---

## 6. L3 Semantic — structure, cadence, drift detection

### 6.1 Files and ownership

| File | Update mode | Writer | Trigger |
|---|---|---|---|
| `_project.md` (Tech Stack + top-level index) | Manual + drift-detect prompt | `/setup`, `/onboard --refresh-stack` | Fingerprint divergence detected |
| `_architecture.md` | Manual | `/setup`, `/onboard --architecture` | User explicit invocation |
| `_CODEBASE_MAP.md` | Bounded auto-incremental | `/implement` (add module), `/refactor` (move/rename) | Structural file change |
| `_FEATURES.md` | Manual or via /plan (M5) | `/geniro:plan` (M5 — feature-backlog updates absorbed from deleted `/features` skill per master plan §68); user may also edit directly | Plan-driven feature record OR manual edit |
| `_focus-<area>.md` | Manual | `/onboard <area>`, `/investigate --persist` | Deep-dive saved |

### 6.2 Drift detection

`.geniro/planning/.fingerprint.json` stores hashes of critical files:
```json
{
  "captured_at": "2026-05-16T12:00:00Z",
  "files": {
    "package.json": "sha256:...",
    "tsconfig.json": "sha256:...",
    "vite.config.ts": "sha256:..."
  }
}
```

**Drift check:** runs at the start of any pipeline skill (cheap; one file read + N hash comparisons).

**On divergence:** soft notification in the skill's initial output, e.g.:
```
[L3 drift] Tech stack fingerprint diverged — package.json deps changed since /onboard ran on 2026-04-12.
Consider /geniro:onboard --refresh-stack. Continuing with current memory.
```

**Never auto-overwrites.** Refresh requires explicit user action; refresh shows a diff before applying.

### 6.3 Bounded auto-incremental writes

`_shared/update-semantic.md` helper applies only to `_CODEBASE_MAP.md` and `_FEATURES.md`. Rules:
- Append-only or single-line replacement; no mass rewrites.
- Format strict and parseable: `- <path> — <short description>, used by <consumer>`.
- Lock-guarded: acquire `.geniro/planning/.codebase-map.lock` via `O_EXCL` file create; defer write to skill completion if locked.
- Human edits welcome anywhere; helper never trashes existing content (diff-style append at end of relevant section).

### 6.4 Reader contract

`_shared/load-semantic.md` helper:
- Default: loads `_project.md` + `_CODEBASE_MAP.md` (top-2 most generally useful).
- Opt-in: skills can pass `extras: ["_architecture", "_FEATURES", "_focus-auth"]` for additional files.
- Cost: typical project loads ~5–15 KB at baseline.

---

## 7. L4 Procedural — existing paths formalized

Paths already exist via the `/geniro:instructions` skill and `_shared/load-custom-instructions.md` loader. M2 only formalizes their role as the L4 procedural layer.

| File | Scope |
|---|---|
| `.geniro/instructions/global.md` | Apply to all pipeline skills |
| `.geniro/instructions/code-style.md` | Apply at every code-writing and review step |
| `.geniro/instructions/<skill>.md` | Apply when `<skill>` runs |
| `.geniro/instructions/review-extra/<slug>.md` | Custom review dimensions; loaded alongside built-in reviewers |

No schema or lifecycle changes — these files remain user-authored Markdown.

---

## 8. CLAUDE.md policy

**The plugin never modifies CLAUDE.md.** This is a hard rule, motivated by:

- `.geniro/` may be gitignored per-project — `@`-imports from CLAUDE.md to `.geniro/*` would fail for teammates lacking the directory.
- CLAUDE.md is shared/committed in most projects; plugin-driven mutations would surprise users.
- Loading must work uniformly whether `.geniro/` is shared or local — a property only skill-driven loading provides.

**Loading mechanism:** all pipeline skills load L3 and L4 via shared helpers (§9) at start of run. Compaction-survival is handled by the SessionStart hook (M3 territory), not by CLAUDE.md `@`-imports.

**User opt-in:** users who explicitly want CLAUDE.md to `@`-import `.geniro/*` files (e.g. shared-`.geniro/` teams) may add the imports manually. The plugin documents this option but never adds them automatically.

---

## 9. Shared helpers (contract surface)

| Helper | Purpose | Used by |
|---|---|---|
| `_shared/load-custom-instructions.md` | Load L4 (existing; minor extension for refresh mode) | All pipeline skills |
| `_shared/load-semantic.md` | Load L3 (top-2 default + opt-in extras); fingerprint drift check | All pipeline skills |
| `_shared/query-learnings.md` | Query L2 by `type`/`tags`/`scope`; filter superseded + deprecated; optional archive | `/debug`, `/implement`, `/plan` (M5), `/review` |
| `_shared/emit-learning.md` | Append to L2 with dedup + supersede + sanitization | All triggering skills (§5.3) |
| `_shared/update-semantic.md` | Bounded auto-incremental write to L3; lock-guarded; append-style | `/implement`, `/refactor`, `/plan` (M5 — manages `_FEATURES.md` updates absorbed from deleted `/features` skill per master plan §68) |
| `_shared/resolve-conflicts.md` | Cross-layer conflict surface; AskUserQuestion gate for hard conflicts | Called from `load-*` helpers |

Each helper has a stable input/output contract documented inside its `.md` (M4+ work to write the helper bodies).

---

## 10. Cross-layer conflict resolution

**Cross-layer precedence (fixed):** L4 > L3 > L2.

- L4 = user-curated explicit rules (highest trust).
- L3 = current-state facts (drift-monitored).
- L2 = historical events (lowest cross-layer trust; may be superseded).
- L1 = task-scoped; does not conflict cross-layer.

**Within-layer:** recency wins. L2 uses the `supersedes` chain (§5.2). L3 uses latest fingerprint refresh / file mtime. L4 uses file mtime (single source per rule).

**Conflict surfacing:** when `_shared/resolve-conflicts.md` detects layers disagreeing, the active skill prints a notice in its output and continues using the precedence-winning value. Example:
```
[layer-conflict]
  L4 global.md: "use webpack"  ⚠️ may be stale
  L2 decision 2025-08-20: "migrated to vite, axios removed"
  L3 fingerprint: vite.config.ts present
  → Skill is following L4 (precedence). Consider /geniro:instructions edit global.md.
```

**Hard conflicts (L4 rule directly contradicts L3 reality):** the skill halts and calls `AskUserQuestion`:
- "L4 says use axios; L3 shows axios removed and fetch in use. Which is intent?"
- User picks → skill auto-emits an L2 `type=convention` entry recording the resolution (no `supersedes` field — that's L2-internal per §5.1 schema; cross-layer L4 reference lives в the summary text instead) + prompts `/geniro:instructions edit global.md` to update L4 source.
- This closes the loop: future runs see the updated L4; the L2 entry serves as the audit trail of how the conflict was resolved.

---

## 11. Migration plan (when M2 ships)

For projects already using the plugin pre-M2:

1. `/geniro:update` detects M2 and triggers a one-shot migration (canonical pre-rename paths per M1 §Path inventory):
   - If `.geniro/planning/FEATURES.md` exists → rename к `.geniro/planning/_FEATURES.md` + add T3 frontmatter.
   - If `.geniro/planning/CODEBASE_MAP.md` exists → rename к `.geniro/planning/_CODEBASE_MAP.md` + add T3 frontmatter.
   - If `.geniro/planning/focus-<area>.md` exist → rename each к `.geniro/planning/_focus-<area>.md` + add T3 frontmatter.
   - Create `.geniro/planning/.fingerprint.json` from current `package.json` / `tsconfig.json`.
   - Create `.geniro/planning/_project.md` skeleton if absent, populated from `/setup`'s record of tech stack.
2. Existing `.geniro/knowledge/learnings.jsonl` entries remain valid (hybrid schema is backward-compatible with free-form base-only entries).
3. One-time manual secret-scan: grep existing `.geniro/knowledge/learnings.jsonl` against the redaction patterns in `_shared/emit-learning.md`. Report-only (no auto-edit); user reviews and patches any historical secrets manually. (Replaces the deleted `/geniro:learnings audit` command per master plan §69.)
4. No CLAUDE.md changes (per §8).

Projects starting fresh post-M2 get the layout created by `/setup`.

---

## 12. Out of scope for M2 (deferred)

The following were explicitly considered and deferred to later milestones to keep M2 focused:

- **Per-developer vs shared L2** — hybrid local + shared `learnings.jsonl` (`.geniro/knowledge/shared/learnings.jsonl` checked-in for team conventions). Defer to a later milestone; current M2 treats L2 as a single file whose share-status follows `.geniro/` gitignore status.
- **Monorepo per-package L3** — separate `.geniro/planning/_*.md` set per package с root-package precedence rules. Defer; M2 assumes one L3 tree per repo root.
- **Read budget / token cost cap** — hard caps on default load size with lazy expansion. Defer; M2 relies on the top-2 default selection in `load-semantic.md` being small enough in practice.
- **Embedding-based L2 retrieval** — semantic similarity search over `learnings.jsonl`. Defer; M2 retrieval is exact-match on `type`/`tags`/`scope` filters, which is sufficient for the initial reflection volume.
- **Three memory categories from agents-best-practices (P-M2-1):** repo identifies 8 canonical memory categories; M2's L1-L4 covers 5. The remaining 3 are deferred:
  - **User preferences** — e.g. preferred commit message style, default reviewer dimensions, UI theme. Today: not modeled. Future: could live в `.geniro/preferences.md` (T3 CRUD) or as а new L5 layer if it grows. Defer until use case emerges (likely M10 /setup territory).
  - **Approval records** — partially addressed by M1 P-M1-1 (T1 frontmatter `approvals: []` for task-scoped one-time decisions). Cross-session approval persistence (e.g., user globally approved force-pushes for `feature/*` branches) is а separate concept and currently not modeled. Defer.
  - **Connector state** — MCP server availability, auth status, scopes. Today: implicit via runtime tool detection. Future: persisted в T3 для performance + compaction-survival. Defer until MCP usage stabilizes (likely P-X6 observability territory).

---

## 13. Open questions for M3 onward

- ✅ **M3:** Compaction-survival strategy — landed в `architecture/M3-compaction-survival.md` (SessionStart hook injection list + MODE: refresh contract defined).
- ✅ **M4 /implement:** Memory I/O section landed в `architecture/M4-implement-redesign.md` §13. Other pipeline skills (`/plan` M5, `/debug` M7, `/review` M6, `/refactor` M8) will add their own Memory I/O sections in their respective milestone docs.
- ⏳ **M-later:** Redaction-pattern marketplace, drift-notification UX polish. (`/geniro:learnings audit` UX is N/A — `/learnings` skill deleted per master plan §69; replaced by manual secret-scan during M2 migration per §11 step 3.)
- ⏳ **M-later (P-M2-2):** Validator framework — enumerate structural checks beyond §5.4 secrets sanitization that need mechanical enforcement. Candidates: spec.md schema (post-M5), learnings.jsonl entry schema, `.geniro/planning/_FEATURES.md` row format, state.md body-section-name spelling (`## Phase log` / `## Tool log` / `## Errors` / `## Open Questions` / `## Termination reason` / `## Inputs from <producer>` / `## Inline Plan` (M4 §5.4) / `## Accepted Failures` (M4 §6) / `## Accepted Findings` (M4 §7.4) — mistyping breaks M3 rendering или Phase-3 reviewer-agent input parsing), possibly extended semantic PII scan. **Trigger:** after M5-M7 ship and collect empirical data о повторных model failures that prompt-level guidance fails к prevent. Real design happens then, not now.

---

## Appendix A — Worked example: full multi-layer flow

User: `/geniro:debug "Toggle component shows stale value after parent re-render"`

1. **Load phase (helpers called by `/debug`):**
   - `load-custom-instructions` reads L4 `global.md` + `code-style.md` + `debug.md`.
   - `load-semantic` reads L3 `_project.md` + `_CODEBASE_MAP.md` (default top-2).
   - `query-learnings` searches L2 with `tags=[react,useEffect,closure]` — finds a prior diagnosis from 2025 with same root_cause pattern.
   - `resolve-conflicts` checks layers: no conflict. Logs nothing.

2. **Investigation phase:**
   - `/debug` shows prior diagnosis to user as "we've seen this pattern before — root cause was missing dep in useEffect array."
   - User confirms similar shape; `/debug` skips ahead to verifying the missing dep.
   - Hypothesis CONFIRMED, fix applied.

3. **Reflection phase (auto-trigger §5.3):**
   - `/debug` calls `emit-learning` with `{producer: "/geniro:debug", scope: "src/components/Toggle.tsx", summary: "...", type: "diagnosis", ext: {...}, tags: [...]}`.
   - Helper computes `dedup_key`, runs sanitization (no secrets detected), scans last 200 — no match — appends.
   - L2 grows by one entry.

4. **Drift check (incidental):**
   - `load-semantic` noticed `package.json` hash diverged from `.fingerprint.json` (Vite was bumped 5.0→5.1 yesterday).
   - Soft notification appeared at top of `/debug` output: "L3 drift detected — consider `/geniro:onboard --refresh-stack`."
   - User acts on it later; no blocking.

5. **No L3 write** — the diagnosis didn't reveal a new module or change architecture, so `update-semantic` is not called.

6. **No L4 write** — the discovery was task-specific, not a general rule. If user later wants to encode "always check useEffect deps" as a rule, they run `/geniro:instructions edit code-style.md`.

Six months later, another `/debug` session on a different stale-closure symptom queries L2 with the same tags and finds **both** entries (current and 2025), surfacing the pattern as a recurring problem — at which point the user may decide to promote it to an L4 rule.

---

*End of M2 specification.*
