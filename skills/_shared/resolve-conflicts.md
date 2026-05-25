# Cross-layer conflict resolution protocol

**Status:** Authoritative for how skills surface cross-layer disagreements (L4 vs L3 vs L2). Provides FORMATTING — detection lives in the calling skill.

**Spec source:** `ARCHITECTURE.md` §Memory Layers.

**MODE contract (M3 §7.4):** formatting helper — **no MODE parameter, compaction-immune.** Behavior is derived from `load-*` outputs at call time; refreshes cascade from the load-side and need no signaling here.

## What this helper does — and what it doesn't

**It does:**
- Formats a canonical `[layer-conflict]` notice block (soft conflict, skill continues using precedence-winning value).
- Formats a hard-conflict text block intended for embedding in `AskUserQuestion` (L4 rule contradicts L3 reality, skill halts).

**It does NOT:**
- Detect conflicts. Conflicts are semantic ("use webpack" in L4 conflicts with "vite.config.ts present" in L3); the calling skill — with its LLM context window of loaded L4/L3/L2 content — is the only entity that can reliably tell. The helper exists so that once a skill HAS decided a conflict exists, every skill formats the notice identically.

This split matches M1's pattern: `validate-state-file.sh` validates schema (mechanical), but routing decisions (T1/T2/T3 selection) live in the calling skill.

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
  --suggested-action "After you decide, /geniro:instructions edit global.md to refresh L4.")
# ... feed $text into AskUserQuestion ...
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
[layer-conflict] subject: http library
  L4 .geniro/instructions/global.md: use axios
  L3 .geniro/planning/.fingerprint.json + _project.md: vite.config.ts present, no axios in package.json
  L2 learnings.jsonl dedup_key=a1b2c3d4: migrated to fetch on 2025-08-20
  → Skill is following L4 (precedence). Consider /geniro:instructions edit global.md.
```

### Hard conflict block (`hard_conflict_block`)

```
Hard cross-layer conflict on: http library

The layers disagree and precedence (L4 > L3 > L2) alone cannot resolve this — your L4 rule contradicts current L3 reality. Which is intent?

  - L4 rule (.geniro/instructions/global.md): use axios
  - L3 fact (.geniro/planning/_project.md): axios removed from package.json; fetch in use

After you decide, /geniro:instructions edit global.md to refresh L4.
```

The hard-conflict block is **plain text** intended for embedding into `AskUserQuestion`'s `question` parameter; the skill itself wires the options (typically: "L4 is correct (refresh L3)", "L3 is correct (update L4)", "Abort").

## Conflict-resolution flow (the canonical skill pattern)

1. Skill loads L4 (`load_custom_instructions`), L3 (`load_semantic`), L2 (`query_learnings --type decision` or similar).
2. Skill's LLM context inspects the three layers for semantic conflicts. (No automation — the LLM is the conflict detector.)
3. If a soft conflict exists: skill calls `emit_conflict_notice` with the relevant facts, then continues using the precedence-winning value (typically L4).
4. If the soft notice is being emitted and the L4 rule conflicts with both L3 AND L2 (suggesting L4 is genuinely stale), the skill upgrades to a hard conflict: `hard_conflict_block` + `AskUserQuestion`.
5. After user resolves a hard conflict: skill auto-emits an L2 `type=convention` entry recording the resolution (`/geniro:emit-learning` style call) and may prompt the user to `/geniro:instructions edit global.md`.

## Exit codes

- `0` — formatted notice / block emitted to stdout.
- `64` — missing `--subject`, invalid `--following`, or unknown flag.

## Known limitations

- **No automatic detection.** This is deliberate — see §"What this helper does".
- **Single-subject only.** One conflict per call. Multi-subject conflicts get separate notices.
- **No threading with the AUQ tool.** The helper FORMATS text; wiring it into `AskUserQuestion` is the calling skill's job.

## Test coverage

`tests/memory/resolve-conflicts.sh` exercises the soft notice format with each combination of L4/L3/L2 lines present, the hard-block format, flag-validation rejection (rc=64) for missing subject / bad --following / unknown flag, and the `--suggested-action` append.
