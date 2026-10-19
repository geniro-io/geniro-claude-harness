#!/usr/bin/env bash
# T3-3 (plugin-audit 2026-10-19) — every MIGRATION.md entry that names a script
# listed in HOOKS.md §Removed guards carries a `> **Superseded` banner.
#
# Run: bash tests/authoring/lint-migration-superseded.sh
#
# Why this exists: /geniro:update walks every MIGRATION.md entry between the
# installed and the new version and shows each as live advice. An entry from
# before 2026-09-29 that says "enforce-state-helper.sh hard-blocks direct
# writes" reads as a current guarantee, and two entries contradicted each other
# on the same script. A `> **Superseded — historical record only.**` banner is
# how an entry says it is history; the audit found seven entries about the
# deleted guards without one.
#
# Which scripts: derived from HOOKS.md §Removed guards, never hard-coded. The
# section's "Deleted <date>:" sentence names each deleted script in backticks,
# so a guard deleted later joins the check by being listed there. An extractor
# that finds nothing fails the run rather than passing it — a renamed sentence
# must not turn the check off silently.
#
# Entry: a `### ` heading through the line before the next heading of any level,
# fenced code skipped (a `#` shell comment is not a heading). The entry headed
# "Five guard hooks are removed; ..." is the removal record itself: it names all
# of the scripts by necessity, describes their deletion, and correctly carries
# no banner, so it is exempt by heading.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILS=0
report_fail() { FAILS=$((FAILS + 1)); echo "FAIL: $1" >&2; }

REMOVAL_RECORD_HEADING="Five guard hooks are removed"

# <hooks-md> -> one script basename per line.
deleted_scripts() {
  awk '
    /^## Removed guards/ { f = 1; next }
    f && /^## / { exit }
    f && /^Deleted / { print }
  ' "$1" 2>/dev/null | grep -oE '`[^`]+\.sh`' | tr -d '`' | sed 's|.*/||' | sort -u
}

# <migration-md> <names-file> -> `<heading line>\t<heading>\t<script>` for every
# entry that names a deleted script, has no Superseded banner, and is not the
# removal record.
migration_gaps() {
  awk -v exempt="$REMOVAL_RECORD_HEADING" '
    NR == FNR { names[++n] = $0; next }
    function flush(   i, hit) {
      if (head == "") return
      hit = ""
      for (i = 1; i <= n; i++) if (index(body, names[i]) > 0) { hit = names[i]; break }
      if (hit != "" && !banner && index(head, exempt) == 0) printf "%d\t%s\t%s\n", hl, head, hit
    }
    /^```/ { fence = !fence }
    !fence && /^#+ / {
      flush()
      if ($0 ~ /^### /) { head = $0; sub(/^### /, "", head); hl = FNR; body = head; banner = 0 }
      else head = ""
      next
    }
    head != "" {
      body = body "\n" $0
      if ($0 ~ /^> \*\*Superseded/) banner = 1
    }
    END { flush() }
  ' "$2" "$1"
}

names_file="$(mktemp)"
SELFTEST_DIR=""
trap 'rm -f "$names_file"; [ -n "$SELFTEST_DIR" ] && rm -rf "$SELFTEST_DIR"' EXIT

deleted_scripts HOOKS.md > "$names_file"
n_names="$(grep -c . "$names_file" || true)"
if [ "$n_names" -lt 1 ]; then
  report_fail "HOOKS.md §Removed guards: no deleted script found — the section's 'Deleted <date>: \`name.sh\`, ...' sentence changed shape, so this check would pass vacuously"
else
  gaps=0
  while IFS=$'\t' read -r hl heading script; do
    [ -n "$hl" ] || continue
    gaps=$((gaps + 1))
    report_fail "MIGRATION.md:$hl: entry \"$heading\" names the deleted guard $script but carries no '> **Superseded' banner — /geniro:update would show it as live advice"
  done < <(migration_gaps MIGRATION.md "$names_file")
  if [ "$gaps" -eq 0 ]; then
    echo "OK: every MIGRATION.md entry naming one of the $n_names deleted guard scripts carries a Superseded banner (or is the removal record)"
  fi
fi

# --- self-test: red on a bannerless entry, green on banner / removal record / fenced '#' ----
SELFTEST_DIR="$(mktemp -d)"

cat > "$SELFTEST_DIR/HOOKS.md" <<'EOF'
# Hooks

## Removed guards

Deleted 2026-09-29: `file-protection.sh`, `block-geniro-deletion.sh` (all but its force-add check, kept above), and their shared parser `lib/write-vectors.sh`.

| Guard | Blocks |
|---|---|
| `block-dangerous-git.sh` | 106 |

## Testing

Mentions `not-a-guard.sh` after the section.
EOF

cat > "$SELFTEST_DIR/MIGRATION.md" <<'EOF'
# Migration Notes

## v6.0.0

### Five guard hooks are removed; only the force-add check remains

`file-protection.sh` and `write-vectors.sh` are deleted.

### The env-file guard stops matching

`hooks/file-protection.sh` no longer protects env files. Nothing else changed.

### Writes through the lock guard are blocked

> **Superseded — historical record only.** `hooks/write-vectors.sh` was removed.

`write-vectors.sh` used to parse the command.

### The restore hook reports its state

Runs a shell step:

```bash
# a shell comment that looks like a top-level heading
echo ok
```

The step then mentions `file-protection.sh`, after the fenced comment.

### A later entry that names only a live script

`block-geniro-force-add.sh` blocks a force-add; `not-a-guard.sh` is unrelated.

### Entry with the script only in its last lines

Intro without a name.

Last line: `block-geniro-deletion.sh` hard-blocks a directory delete.
EOF

names_st="$SELFTEST_DIR/names.txt"
deleted_scripts "$SELFTEST_DIR/HOOKS.md" > "$names_st"
if [ "$(sort "$names_st" | tr '\n' ' ')" = "block-geniro-deletion.sh file-protection.sh write-vectors.sh " ]; then
  echo "OK: self-test — the deleted-script list is read from the 'Deleted <date>:' sentence only (lib/ stripped, table rows and later sections ignored)"
else
  report_fail "self-test — deleted-script extraction returned: $(tr '\n' ' ' < "$names_st")"
fi

got="$(migration_gaps "$SELFTEST_DIR/MIGRATION.md" "$names_st" | cut -f2 | tr '\n' '|')"
want="The env-file guard stops matching|The restore hook reports its state|Entry with the script only in its last lines|"
# The restore-hook entry names its script AFTER a fenced "# ..." line: flagging it
# proves the shell comment did not end the entry early as a fake heading.
if [ "$got" = "$want" ]; then
  echo "OK: self-test — bannerless entries are flagged; the Superseded entry, the removal record and the live-script-only entry are not"
else
  report_fail "self-test — expected [$want], got [$got]"
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "FAILED: $FAILS MIGRATION.md Superseded-banner problem(s)." >&2
  exit 1
fi
echo "OK: MIGRATION.md entries about deleted guards are all marked superseded."
