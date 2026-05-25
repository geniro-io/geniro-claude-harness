# Secrets sanitization helper

**Status:** Authoritative for L2 episodic-memory write-side sanitization. Every entry that flows through `_shared/emit-learning.sh` is sanitized via this helper before append.

**Spec source:** `ARCHITECTURE.md` §Memory Layers.

## Why this exists

L2 episodic memory (`.geniro/knowledge/learnings.jsonl`) is append-only and shareable. A leaked JWT or AWS key written into a `summary` or `body` field stays forever and propagates to every teammate who clones the repo. Sanitization runs on every write; the audit log makes redaction observable.

The same helper is reusable from any future skill that wants to sanitize free-form text before persisting (e.g. `/debug` writing a diagnosis to L2, `/review` recording a finding).

## API

```bash
source lib/redact-secrets.sh
sanitized=$(printf '%s' "$raw" | redact_secrets <producer> <field> <dedup_key>)
```

- **Input:** arbitrary text on stdin (may contain newlines).
- **Output:** sanitized text on stdout. The helper itself does NOT add a trailing newline, but note that command-substitution capture (`$(redact_secrets ...)`) always strips trailing newlines per POSIX shell semantics. Callers that need byte-exact preservation should pipe to a file or `xxd`/`od` rather than capture via `$(...)`. All current callers re-serialize via `jq`, so this is academic.
- **Side effect:** for each built-in pattern that fires AND for each safety.json `additional_pattern` that fires, one JSONL line is appended to `.geniro/knowledge/.redaction-log.jsonl` (unless `audit_log_enabled: false`).
- **Args:** producer (skill name), field (e.g. `summary`, `ext.body`), dedup_key (the L2 entry's dedup_key — links the audit row to the entry being sanitized). All three are echoed verbatim into the audit log.

The helper never errors out — it falls through to passthrough if `git`, `jq`, or `sed` are unavailable, so a corrupted environment never blocks the L2 write. Audit-log emission also fails silently.

## Built-in pattern set

| Pattern name | Regex (POSIX ERE) | Replacement |
|---|---|---|
| `jwt` | `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | `[REDACTED:jwt]` |
| `aws-key` | `AKIA[0-9A-Z]{16}` | `[REDACTED:aws-key]` |
| `aws-secret` | `aws_secret_access_key[[:space:]]*=[[:space:]]*[A-Za-z0-9/+=]{40}` | `aws_secret_access_key=[REDACTED:aws-secret]` |
| `api-key:sk-ant` | `sk-ant-[A-Za-z0-9_-]+` | `[REDACTED:api-key:anthropic]` |
| `api-key:sk` | `sk-[A-Za-z0-9_-]+` | `[REDACTED:api-key:openai-or-similar]` |
| `api-key:pk_live` | `pk_live_[A-Za-z0-9_]+` | `[REDACTED:api-key:stripe-live]` |
| `api-key:pk_test` | `pk_test_[A-Za-z0-9_]+` | `[REDACTED:api-key:stripe-test]` |
| `api-key:ghp` | `ghp_[A-Za-z0-9_-]+` | `[REDACTED:api-key:github]` |
| `api-key:xoxb` | `xoxb-[A-Za-z0-9_-]+` | `[REDACTED:api-key:slack-bot]` |
| `bearer` | `Bearer [A-Za-z0-9._-]+` | `Bearer [REDACTED:bearer]` |
| `url-cred` | `(https?)://[^:/[:space:]]+:[^@/[:space:]]+@` | `\1://[REDACTED:url-cred]@` |
| `private-key` | `-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----` | `[REDACTED:private-key]` |

### Two design decisions worth flagging

**1. Provider-name labels (not literal prefixes).** The spec talks about `[REDACTED:api-key:<prefix>]`; the helper emits `[REDACTED:api-key:anthropic]` instead of `[REDACTED:api-key:sk-ant]`. Reason: the literal-prefix label `[REDACTED:api-key:sk-ant]` contains the substring `sk-ant`, which the next `sk-` pattern would re-match, producing nested gibberish like `[REDACTED:api-key:[REDACTED:api-key:openai-or-similar]]`. Provider names break the self-recursion AND stay readable.

**2. Pattern order matters.** `sk-ant-` must run before `sk-` (`sk-ant-foo` would otherwise be redacted as if it were a generic OpenAI key). The helper enforces this in the built-in `_RED_NAMES` array order — do not reorder without re-running the test suite.

## High-entropy warning

The spec's "generic high-entropy ≥32 chars" entry is intentionally **not** auto-redacted — false-positive risk on legitimate hashes (git SHAs, content hashes, base64 thumbnails) is too high. If callers want a stricter posture they can add an `additional_patterns` entry via `safety.json` (§safety.json knobs).

## Audit log

Path: `.geniro/knowledge/.redaction-log.jsonl` (T2 sidecar, appended via `atomic_state_append`).

Schema (one JSONL line per `(pattern, entry)` fire):

```jsonl
{"ts":"2026-05-19T14:30:00Z","producer":"/geniro:debug","field":"ext.body","pattern":"jwt","redacted_chars":156,"entry_dedup_key":"a1b2c3d4"}
```

- `redacted_chars` = total bytes of matched substrings summed across all matches that pattern produced in this call (not per-match — aggregated).
- One line per pattern × call; if a single call fired 3 distinct patterns, the audit log gets 3 lines.

## `.geniro/safety.json` knobs

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

- **`additional_patterns`** — appended to the built-in list (run after, single-line only — multiline custom patterns are not supported in this milestone). `replacement` may include sed backreferences like `\1`. The pattern's `name` appears in the audit log verbatim.
- **`ignore_patterns`** — list of names (built-in OR additional) to skip entirely. The pattern is not run; no redaction, no audit.
- **`audit_log_enabled`** — default `true`. Set `false` to suppress audit-log writes (sanitization still runs; the redaction itself is silent).

## Known limitations

- **Greedy multiline PEM match.** If the input contains two PEM blocks with content between them, the regex `.*` greedily matches from BEGIN-of-first to END-of-second, collapsing the intervening content into the single redaction. Over-redaction is preferred over under-redaction; teach producers not to concatenate raw PEMs.
- **URL with `@` in password.** `https://user:p@ss@host/` matches the first `@`, leaving `ss@host/` visible. Real producers should URL-encode credentials anyway. Document for clarity; don't try to be cleverer than the spec.
- **AWS secret exactly 40 chars.** Pattern matches `{40}` exactly. A 39- or 41-char secret slips through. Matches AWS's documented secret-key length; no looser counterpart needed.
- **`sed` and `grep` portability.** Helper uses POSIX `-E` (extended) regex syntax; works on Linux GNU and macOS BSD. Backreferences (`\1`) are GNU sed and BSD sed compatible. If you ever port to a stricter `sed`, retest each pattern.

## Test coverage

`tests/memory/redact-secrets.sh` exercises every built-in pattern, the order-dependency between `sk-ant-` and `sk-`, multiline PEM, audit-log JSONL shape, `ignore_patterns` skip, and `additional_patterns` injection. Run after any change to `redact-secrets.sh`.
