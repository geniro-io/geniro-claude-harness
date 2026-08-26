# Cross-layer conflict resolution protocol

**Status:** Authoritative for how skills surface cross-layer disagreements (L4 vs L3 vs L2). Provides FORMATTING — detection lives in the calling skill.

**MODE contract:** formatting helper — **no MODE parameter, compaction-immune.** Behavior is derived from `load-*` outputs at call time; refreshes cascade from the load-side and need no signaling here.

## What this helper does — and what it doesn't

**It does:**
- Formats a canonical conflict notice block (soft conflict, skill continues using precedence-winning value).
- Formats a hard-conflict text block the calling skill renders to chat ahead of a lean `AskUserQuestion` (L4 rule contradicts L3 reality, skill halts).

**It does NOT:**
- Detect conflicts. Conflicts are semantic ("use webpack" in L4 conflicts with "vite.config.ts present" in L3); the calling skill — with its LLM context window of loaded L4/L3/L2 content — is the only entity that can reliably tell. The helper exists so that once a skill HAS decided a conflict exists, every skill formats the notice identically.

This split matches the `validate-state-file.sh` pattern: it validates schema (mechanical), but routing decisions (T1/T2/T3 selection) live in the calling skill.

## API

```bash
source lib/resolve-conflicts.sh

# Soft conflict — skill continues, prints notice
emit_conflict_notice \
  --subject "http library" \
  --l4 "use axios" \
  --l4-source ".geniro/instructions/global.md" \
  --l3 "vite.config.ts present, no axios in package.json" \
  --l3-source ".geniro/planning/.fingerprint.json + _project.md" \
  --l2 "migrated to fetch on 2025-08-20" \
  --l2-source "learnings.jsonl dedup_key=a1b2c3d4" \
  --following L4 \
  --suggested-action "Consider /geniro:instructions edit global.md."

# Hard conflict — skill halts and invokes AskUserQuestion
text=$(hard_conflict_block \
  --subject "http library" \
  --l4 "use axios" --l4-source ".geniro/instructions/global.md" \
  --l3 "axios removed from package.json; fetch in use" --l3-source ".geniro/planning/_project.md" \
  --suggested-action "After you decide, /geniro:instructions edit global.md to refresh your project rules.")
# ... emit $text as its own chat message, then fire the lean AskUserQuestion ...
```

## Flag reference

All flags apply to both modes:

| Flag | Required | Notes |
|------|----------|-------|
| `--subject <text>` | yes | Short label (e.g. `"http library"`, `"build tool"`). |
| `--l4 <text>` | no | L4 rule content (one line). |
| `--l4-source <path>` | no | Where the L4 rule lives (e.g. `.geniro/instructions/global.md`). |
| `--l3 <text>` | no | L3 fact content. |
| `--l3-source <path>` | no | Where the L3 fact was loaded from. |
| `--l2 <text>` | no | L2 historical event. |
| `--l2-source <ref>` | no | Typically `learnings.jsonl dedup_key=…` or `ts=…`. |
| `--following <L2\|L3\|L4>` | soft only | Which layer the skill is using. Omit for hard mode. |
| `--suggested-action <text>` | no | Remediation prompt appended to the notice. |

At least one of `--l4` / `--l3` / `--l2` should be supplied; otherwise the notice has no content.

## Output formats

### Soft conflict notice (`emit_conflict_notice`)

```
Conflict on: http library
  Your project rules (.geniro/instructions/global.md): use axios
  Your project snapshot (.geniro/planning/.fingerprint.json + _project.md): vite.config.ts present, no axios in package.json
  Past learnings (learnings.jsonl dedup_key=a1b2c3d4): migrated to fetch on 2025-08-20
  → Following your project rules, which take precedence. Consider /geniro:instructions edit global.md.
```

The layer that wins renders by its plain-English name ("your project rules" / "your project snapshot" / "past learnings"), never as a bare layer code — the user is being told which source the run is trusting, and a code they have to look up defeats the notice.

### Hard conflict block (`hard_conflict_block`)

```
Conflict that needs your decision: http library

A rule you set for this project and the current state of your codebase point in opposite directions, and the usual order — project rules first, then the project snapshot, then past learnings — cannot settle it, because the rule contradicts what the code looks like today. Which one is your intent?

Technical detail:
  - Your project rules (.geniro/instructions/global.md): use axios
  - Your project snapshot (.geniro/planning/_project.md): axios removed from package.json; fetch in use

After you decide, /geniro:instructions edit global.md to refresh your project rules.
```

The hard-conflict block is **plain text**, laid out in the two layers of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/gate-rendering.md` §Two explanation layers: the frame sentence states the disagreement in ordinary words, and the source files sit under `Technical detail:`. The helper only has the `--l4` / `--l3` / `--l2` strings it was handed, so the frame stays generic — a calling skill holding the actual content expands the plain layer with the specifics ("the code makes its requests with the browser's built-in fetch instead") before rendering. **The calling skill emits it as its own chat message and then fires a lean `AskUserQuestion` that points at it** (per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/per-finding-question.md` §Message-first rendering) — the block is a render, not a `question` value: pasted into `question` it is a wall of text in a narrow prompt, which is what leaves a user resolving a conflict they did not read. The skill wires the options (typically: "The project rules are right — refresh the snapshot", "The snapshot is right — update the rules", "Abort").

## Conflict-resolution flow (the canonical skill pattern)

1. Skill loads L4 (`load_custom_instructions`), L3 (`load_semantic`), L2 (`query_learnings --type decision` or similar).
2. Skill's LLM context inspects the three layers for semantic conflicts. (No automation — the LLM is the conflict detector.)
3. If a soft conflict exists: skill calls `emit_conflict_notice` with the relevant facts, then continues using the precedence-winning value (typically L4).
4. If the soft notice is being emitted and the L4 rule conflicts with both L3 AND L2 (suggesting L4 is genuinely stale), the skill upgrades to a hard conflict: `hard_conflict_block` + `AskUserQuestion`.
5. After user resolves a hard conflict: skill auto-emits an L2 `type=convention` entry recording the resolution (via the `emit_learning` helper, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/emit-learning.md`) — echo `Recorded learning: <summary>` after the emit, per that file's §"Caller contract" — and may prompt the user to `/geniro:instructions edit global.md`.

## Exit codes

- `0` — formatted notice / block emitted to stdout.
- `64` — missing `--subject`, invalid `--following`, or unknown flag.

## Known limitations

- **No automatic detection.** This is deliberate — see §"What this helper does".
- **Single-subject only.** One conflict per call. Multi-subject conflicts get separate notices.
- **No threading with the AUQ tool.** The helper FORMATS text; rendering it to chat and wiring the lean `AskUserQuestion` after it is the calling skill's job.
