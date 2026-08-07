# Update — user-content snapshot

Sibling reference for `${CLAUDE_PLUGIN_ROOT}/skills/update/SKILL.md` §User-content snapshot. `phase-1-precheck.md` (baseline) and `phase-3-postcheck.md` (comparison) each paste these definitions verbatim into their own Bash call — shell state doesn't persist between calls, so neither phase can source a shared file. Both phases must paste byte-identical code: a drifted second copy would make the survival diff raise a false tamper alarm over content nothing touched. Change it here, then re-paste into both phase files in the same edit.

```bash
# One "<sha256> <mtime> <path>" line per user-authored file, sorted. $1 = PRIMARY_ROOT.
_gu_snapshot() {
  find "$1/.geniro/instructions" "$1/.geniro/actions" -type f -name "*.md" 2>/dev/null \
  | sort \
  | while IFS= read -r f; do
      h=$({ sha256sum "$f" 2>/dev/null || shasum -a 256 "$f" 2>/dev/null; } | cut -d' ' -f1)
      printf '%s %s %s\n' "$h" "$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null)" "$f"
    done
}

# Carry-forward channel between the two phases. The PRIMARY_ROOT hash in the filename keeps
# concurrent /update sessions in different repos from clobbering each other's baseline. $1 = PRIMARY_ROOT.
_gu_snapshot_file() {
  printf '/tmp/geniro-user-snapshot.%s.txt' \
    "$(printf '%s' "$1" | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -c1-12)"
}
```
