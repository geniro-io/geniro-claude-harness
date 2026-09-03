#!/usr/bin/env bash
# Atomic state-file write helpers.
#
# Spec: skills/_shared/atomic-state-write.md
# Tier model: skills/_shared/state-tier-spec.md
# Design rationale: ARCHITECTURE.md §State Files
#
# Source this file from a skill's Bash invocation:
#   source "${CLAUDE_PLUGIN_ROOT}/lib/atomic-state-write.sh"
#   atomic_state_write <target-path> <<'CONTENT'
#   ...
#   CONTENT
#
# Functions exported:
#   atomic_state_write <target>              — stdin → whole file (tmp + rename)
#   atomic_state_write_cmd <target> <cmd...> — same, but commits ONLY if the producer exits 0
#   atomic_state_edit <target> <old> <new>   — literal exactly-once replace, atomic commit
#   atomic_state_set_field <target> <k> <v>  — set one frontmatter field, atomic commit
#   atomic_state_append_section <t> <h> <x>  — append an entry to the end of a body section
#   atomic_state_append_list_item <t> <k> <i> — append an item to a frontmatter YAML list
#   atomic_state_append <target>             — POSIX O_APPEND for ≤4KB lines (T3 append-only / JSONL)
#
# Why the editors exist: atomic_state_write is a writer, not an editor, so changing
# one field used to mean regenerating the whole file. A whole-file regeneration
# re-writes every field the transform did not touch at its OLD value — the silent
# carry-forward documented in atomic-state-write.md §"Changing part of an existing
# file", which stays invisible until a resume routes on the stale field. The editors
# change exactly the named bytes and leave the rest untouched.
#
# Three structural decisions, each load-bearing:
#
#   1. Every public function does its work in a SUBSHELL. The INT/TERM trap that
#      removes a half-written tmp file is then scoped to that subshell instead of
#      replacing a trap the caller installed, and a signal arriving mid-write no
#      longer overrides the caller's own handler and exit code.
#   2. Tmp filenames come from `mktemp`, not from `$$`. Inside a subshell `$$` is
#      the PARENT shell's pid in both bash and zsh, so two backgrounded writers to
#      one target computed the SAME tmp path and could splice their payloads into
#      one committed file — the exact corruption this library exists to prevent.
#   3. The editors do their string work in `awk`, not in shell parameter
#      expansion. A single `${haystack#*"$needle"}` is quadratic in bash: measured
#      21 s on a 200 KB file against 24 ms for the awk equivalent, and a state file
#      that size is ordinary. Past the Bash tool's default timeout the resulting
#      SIGTERM would land mid-write.

# Single source for the append/JSONL byte ceiling: PIPE_BUF (4096 on Linux, 512 on
# macOS) minus 2 bytes for the newline framing the append adds. emit-learning.sh sources
# this file and reuses GENIRO_APPEND_MAX_BYTES, so the two enforcers never drift.
: "${GENIRO_APPEND_MAX_BYTES:=4094}"
# Reject anything that is not a plain 1-9 digit number. A non-numeric or negative
# override would make the `-gt` ceiling test error and evaluate false, silently
# disabling the ceiling — and so would an all-digit value too large for the shell's
# integer arithmetic, which is why the length is capped and not just the alphabet.
# A numeric-but-zero override passes the alphabet test but would block every
# append, so it is floored separately, matching backpressure.sh's cap.
case "$GENIRO_APPEND_MAX_BYTES" in
  ''|*[!0-9]*)  GENIRO_APPEND_MAX_BYTES=4094 ;;
  ??????????*)  GENIRO_APPEND_MAX_BYTES=4094 ;;   # 10+ digits — past any real PIPE_BUF
esac
[ "$GENIRO_APPEND_MAX_BYTES" -lt 1 ] && GENIRO_APPEND_MAX_BYTES=4094

# Per-file sync capability, probed once per shell.
#
# `sync -d <path>` fsyncs one file on GNU coreutils. BSD/macOS `sync` takes no
# options and IGNORES every operand, returning 0 regardless — so an rc-based probe
# reads macOS as "per-file sync succeeded". `sync --help` is the honest
# discriminator: GNU prints an options list naming `--data`, BSD prints nothing.
# Here-string, not a pipe: under `pipefail` a matching `grep -q` can exit 141 when
# it closes the pipe early (tests/authoring/lint-pipefail-grep.sh).
#
# Where there is no per-file sync this is a NO-OP, not a whole-disk `sync`. That
# fallback cost 164 ms per write measured on macOS and flushed every mounted
# filesystem on the machine, while buying nothing: macOS `sync(2)` schedules the
# flush rather than waiting for it. Atomicity — the rename — never depended on it.
# Durability across power loss is therefore Linux-only; see atomic-state-write.md
# §Portability notes.
# Probed HERE, at source time, not lazily inside a helper: every public function
# runs its body in a subshell, so a lazy probe's result would die with that
# subshell and re-run on every single write — and on BSD `sync --help` ignores the
# operand and performs a real whole-disk sync, so the probe itself was the cost it
# existed to avoid.
if grep -q -- '--data' <<< "$(sync --help 2>&1)"; then
  _ATOMIC_SYNC_HAS_D=1
else
  _ATOMIC_SYNC_HAS_D=0
fi
_atomic_state_sync_file() {
  [ "$_ATOMIC_SYNC_HAS_D" = "1" ] || return 0
  sync -d "$1" 2>/dev/null || true
}

# Hostname for the tmp filename, sanitized. zsh does not set HOSTNAME (it sets
# HOST), and without this fallback every zsh caller collapsed to the constant
# "localhost", defeating the cross-host half of the NFS collision guard.
# Hostnames carrying `/` or spaces are legal per POSIX and observed in some
# container environments; they would build an unwritable tmp path.
_atomic_state_hostname() {
  local h="${HOSTNAME:-${HOST:-}}"
  [ -n "$h" ] || h="$(hostname 2>/dev/null || echo localhost)"
  h="${h//[^A-Za-z0-9.-]/_}"
  printf '%s' "${h:-localhost}"
}

# Create the tmp file beside the target and echo its path; empty output on failure.
_atomic_state_mktemp() {
  local host
  host="$(_atomic_state_hostname)"
  mktemp "${1}.tmp.${host}.XXXXXX" 2>/dev/null
}

# Resolve + create the parent directory. Echoes the dir; rc 65 on failure.
_atomic_state_prepare_dir() {
  local dir
  dir="$(dirname "$1")"
  mkdir -p "$dir" || return 65
  printf '%s' "$dir"
}

# Shared commit path: carry the target's permissions, fsync, rename, fsync dir.
# $1 is the calling function's name, so a rename failure names the call the caller
# actually made instead of always blaming atomic_state_write.
_atomic_state_commit() {
  local fn="$1" tmp="$2" target="$3" dir="$4"

  # `mv -f file dir` moves INTO the directory and succeeds, so a target path
  # shadowed by a directory used to report success while writing nothing and
  # stranding the tmp file inside it.
  if [ -d "$target" ]; then
    rm -f "$tmp"
    echo "$fn: $target is a directory, not a state file; nothing written" >&2
    return 67
  fi

  # mktemp creates the tmp at 0600. Carry the target's own mode across a rewrite,
  # and otherwise apply the mode a plain `>` redirection would have produced, so
  # this helper never silently narrows or widens a state file's permissions.
  if [ -e "$target" ]; then
    local mode
    mode="$(stat -f '%Lp' "$target" 2>/dev/null || stat -c '%a' "$target" 2>/dev/null || echo '')"
    [ -n "$mode" ] && chmod "$mode" "$tmp" 2>/dev/null
  else
    local um
    um="$(umask)"
    chmod "$(printf '%03o' $(( 0666 & ~0$um )))" "$tmp" 2>/dev/null
  fi

  _atomic_state_sync_file "$tmp"

  # POSIX guarantees rename-within-same-fs is atomic. -f so an unwritable existing
  # target cannot prompt and hang a tty session.
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    echo "$fn: rename to $target failed" >&2
    return 67
  fi

  _atomic_state_sync_file "$dir"
  return 0
}

# The editors cannot round-trip two byte values, and both used to be lost in
# silence at rc 0: 0x04 is the record separator the awk rewrite uses, so a file
# carrying it would keep only its first record, and NUL cannot survive shell
# command substitution or `read` at all. Refuse such a file rather than shorten
# it. Markdown state files carry neither; this is a guard, not a supported shape.
_atomic_state_binary_unsafe() {
  local full stripped
  full=$(wc -c < "$1" 2>/dev/null | tr -d ' ') || return 1
  stripped=$(LC_ALL=C tr -d '\000\004' < "$1" 2>/dev/null | wc -c | tr -d ' ') || return 1
  [ "$full" != "$stripped" ]
}

atomic_state_write() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$target" ]; then
    echo "atomic_state_write: target path required" >&2
    return 64
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_write: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_write: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    if ! cat > "$tmp"; then
      rm -f "$tmp"
      echo "atomic_state_write: failed to write tmp $tmp" >&2
      exit 66
    fi

    # Empty-stdin guard. A pipe that errors before producing output
    # (`failing_generator | atomic_state_write target`) must not truncate the
    # target to zero bytes — and must not read as success either: this call site
    # cannot see the producer's exit status, so a silent 0 reports "state written"
    # for a run that wrote nothing. A caller that genuinely wants an empty file
    # uses `truncate -s 0 <target>`. A caller that must distinguish a partially
    # written payload from an empty one needs atomic_state_write_cmd.
    if [ ! -s "$tmp" ]; then
      rm -f "$tmp"
      echo "atomic_state_write: stdin was empty; $target left unchanged" >&2
      exit 70
    fi

    _atomic_state_commit atomic_state_write "$tmp" "$target" "$dir"
    exit $?
  )
}

# atomic_state_write_cmd <target> <command> [args...]
#
# Runs the producer itself so it can read its exit status, and commits ONLY on
# rc 0. This is the shape `producer | atomic_state_write target` cannot have: in a
# pipeline the helper is the last element, so the pipeline's rc is the helper's,
# and a producer that dies mid-stream leaves `cat` a short-but-valid payload that
# then gets renamed over good state. Use this for every generated (as opposed to
# heredoc-literal) whole-file write.
#
# The producer is exec'd directly, not through a shell — for a pipeline or a
# redirect, pass `bash -c '<pipeline>'`.
atomic_state_write_cmd() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "atomic_state_write_cmd: target path required" >&2
    return 64
  fi
  shift
  if [ "$#" -eq 0 ]; then
    echo "atomic_state_write_cmd: producer command required" >&2
    return 64
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_write_cmd: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    # Created before the producer runs, so an unwritable directory is reported as
    # the write failure it is (66) rather than blamed on the producer (75).
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_write_cmd: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    prc=0
    "$@" > "$tmp" || prc=$?

    if [ "$prc" -ne 0 ]; then
      rm -f "$tmp"
      echo "atomic_state_write_cmd: producer exited $prc; $target left unchanged" >&2
      exit 75
    fi
    if [ ! -s "$tmp" ]; then
      rm -f "$tmp"
      echo "atomic_state_write_cmd: producer wrote nothing; $target left unchanged" >&2
      exit 70
    fi

    _atomic_state_commit atomic_state_write_cmd "$tmp" "$target" "$dir"
    exit $?
  )
}

# atomic_state_edit <target> <old_text> <new_text>
#
# Replaces one literal occurrence of <old_text> with <new_text> and commits the
# result atomically. Matching is literal and non-overlapping: `*`, `?` and `[` in
# the anchor are bytes, never patterns. <old_text> must match exactly once — zero
# matches (rc 71) and more than one (rc 72) both change nothing rather than
# letting the helper guess which occurrence was meant.
#
# A file declaring `checksum:` seals a hash of its BODY, so an edit below the
# frontmatter would invalidate the seal and make validate_state_file reject the
# file (rc 7) while this helper returned 0. That combination is refused (rc 76).
atomic_state_edit() {
  local target="${1:-}" old="${2:-}" new="${3:-}"
  if [ -z "$target" ]; then
    echo "atomic_state_edit: target path required" >&2
    return 64
  fi
  if [ -z "$old" ]; then
    echo "atomic_state_edit: old text required (empty matches everywhere)" >&2
    return 64
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "atomic_state_edit: $target does not exist or is unreadable" >&2
    return 73
  fi
  if _atomic_state_binary_unsafe "$target"; then
    echo "atomic_state_edit: $target contains a NUL or 0x04 byte, which this helper cannot round-trip; rewrite it with a whole-file write instead" >&2
    return 73
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_edit: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_edit: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    # Values reach awk through the environment, not `-v`: `-v` runs escape
    # processing, so an anchor containing a backslash would not match itself.
    ASW_OLD="$old" ASW_NEW="$new" awk '
      BEGIN { RS = "\004"; o = ENVIRON["ASW_OLD"]; n = ENVIRON["ASW_NEW"] }
      {
        i = index($0, o)
        if (i == 0) { exit 71 }
        rest = substr($0, i + length(o))
        if (index(rest, o) > 0) { exit 72 }

        # Frontmatter span, for the checksum guard: the file must open with a
        # "---" line, and the block ends at the next one.
        fmend = 0
        if (substr($0, 1, 4) == "---\n") {
          j = index(substr($0, 5), "\n---\n")
          if (j > 0) { fmend = 4 + j + 4 }
        }
        if (fmend > 0 && i > fmend) {
          fm = substr($0, 1, fmend)
          if (index(fm, "\nchecksum:") > 0) { exit 76 }
        }

        printf "%s%s%s", substr($0, 1, i - 1), n, rest
      }
    ' "$target" > "$tmp"
    arc=$?

    if [ "$arc" -ne 0 ]; then
      rm -f "$tmp"
      case "$arc" in
        71) echo "atomic_state_edit: old text not found in $target; nothing changed" >&2 ;;
        72) echo "atomic_state_edit: old text matches more than once in $target; pass a longer, unique anchor" >&2 ;;
        76) echo "atomic_state_edit: $target declares checksum: and this edit is below the frontmatter, which would leave the seal stale; re-seal with atomic_state_set_field after a whole-file write instead" >&2 ;;
        *)  echo "atomic_state_edit: rewrite of $target failed (awk rc $arc)" >&2 ;;
      esac
      exit "$arc"
    fi

    _atomic_state_commit atomic_state_edit "$tmp" "$target" "$dir"
    exit $?
  )
}

# atomic_state_set_field <target> <field> <value>
#
# Sets `<field>: <value>` inside the leading `---` frontmatter block only — a
# same-named line in the body is never touched. The block must be closed and the
# field must already exist: a state file's schema comes from state-tier-spec.md,
# and inventing a key here would let a typo pass for a set.
#
# This is the call that advances `phase:` / `status:` / `timestamp:` without
# regenerating the file, so no untouched field can carry forward stale.
atomic_state_set_field() {
  local argc="$#"
  local target="${1:-}" field="${2:-}" value="${3:-}"
  if [ -z "$target" ] || [ -z "$field" ]; then
    echo "atomic_state_set_field: target path and field name required" >&2
    return 64
  fi
  # A forgotten third argument used to blank the field at rc 0 — a typo silently
  # destroying the value this helper family exists to protect. An explicit ""
  # still sets an empty value; an omitted argument is an error.
  if [ "$argc" -lt 3 ]; then
    echo "atomic_state_set_field: value required (pass \"\" to set an empty value)" >&2
    return 64
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "atomic_state_set_field: $target does not exist or is unreadable" >&2
    return 73
  fi
  # A newline in the value would put a bare continuation line inside the `---`
  # block — frontmatter the validator rejects, written at rc 0. Multi-line content
  # belongs in the body, so this is a caller error, not a shape to support.
  case "$value" in
    *$'\n'*)
      echo "atomic_state_set_field: value must be a single line; '$field' left unchanged" >&2
      return 64
      ;;
  esac
  if _atomic_state_binary_unsafe "$target"; then
    echo "atomic_state_set_field: $target contains a NUL or 0x04 byte, which this helper cannot round-trip; rewrite it with a whole-file write instead" >&2
    return 73
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_set_field: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_set_field: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    # Preserve a missing trailing newline rather than silently normalizing it:
    # awk terminates every record it prints, so the flag decides whether the last
    # one keeps its newline.
    ends_nl=1
    if [ -s "$target" ] && [ -n "$(tail -c 1 "$target" 2>/dev/null)" ]; then
      ends_nl=0
    fi

    ASW_FIELD="$field" ASW_VALUE="$value" ASW_ENDS_NL="$ends_nl" awk '
      BEGIN {
        f = ENVIRON["ASW_FIELD"]; v = ENVIRON["ASW_VALUE"]
        ends_nl = ENVIRON["ASW_ENDS_NL"]
        fence = 0; found = 0; prefix = f ":"
      }
      {
        line = $0
        if (line == "---") {
          if (fence == 0 && NR == 1)      { fence = 1 }
          else if (fence == 1)            { fence = 2 }
        } else if (fence == 1 && found == 0) {
          # Exact key match, not a prefix: `phase` must not claim `phases:`.
          if (substr(line, 1, length(prefix)) == prefix) { line = f ": " v; found = 1 }
        }
        if (NR > 1) { printf "\n" }
        printf "%s", line
      }
      END {
        if (ends_nl == "1") { printf "\n" }
        if (fence != 2) { exit 2 }
        if (found != 1) { exit 3 }
      }
    ' "$target" > "$tmp"
    arc=$?

    if [ "$arc" -ne 0 ]; then
      rm -f "$tmp"
      case "$arc" in
        2) echo "atomic_state_set_field: $target has no closed leading '---' frontmatter block; nothing changed" >&2 ;;
        3) echo "atomic_state_set_field: field '$field' not present in the frontmatter of $target; nothing changed" >&2 ;;
        *) echo "atomic_state_set_field: rewrite of $target failed (awk rc $arc)" >&2 ;;
      esac
      exit 74
    fi

    _atomic_state_commit atomic_state_set_field "$tmp" "$target" "$dir"
    exit $?
  )
}

# atomic_state_append_section <target> <heading> <text> [--create]
#
# Appends <text> at the END of the body section introduced by the exact heading
# line <heading> (for example `## Tool log`), keeping the section's own trailing
# blank lines between the new entry and the next heading. The section ends at the
# next heading of the same or a higher level, or at end of file.
#
# This exists because the natural anchor for an append — the heading itself — is
# wrong the moment the section is non-empty: anchoring on `## Tool log` inserts
# the newest entry ABOVE the older ones and inverts a log that downstream steps
# parse in order.
#
# <heading> must appear exactly once (rc 78 otherwise): a document with two
# `## Errors` headings has no single end to append to.
#
# A missing heading is rc 77, NOT a silent create — a typo would otherwise grow a
# second, near-identical section that nothing reads. Sections a run creates on
# demand (`## Deferred Findings`, `## Visual Baseline`, `## Authored Tests` — the
# ones no state.md template declares up front) pass `--create`, which appends the
# heading at end of file on the first call and behaves normally after that.
atomic_state_append_section() {
  local target="${1:-}" heading="${2:-}" text="${3:-}" create=0
  [ "${4:-}" = "--create" ] && create=1
  if [ -z "$target" ] || [ -z "$heading" ]; then
    echo "atomic_state_append_section: target path and heading required" >&2
    return 64
  fi
  if [ -z "$text" ]; then
    echo "atomic_state_append_section: text required; nothing appended to $target" >&2
    return 64
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "atomic_state_append_section: $target does not exist or is unreadable" >&2
    return 73
  fi
  if _atomic_state_binary_unsafe "$target"; then
    echo "atomic_state_append_section: $target contains a NUL or 0x04 byte, which this helper cannot round-trip" >&2
    return 73
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_append_section: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_append_section: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    ends_nl=1
    if [ -s "$target" ] && [ -n "$(tail -c 1 "$target" 2>/dev/null)" ]; then
      ends_nl=0
    fi

    ASW_HEADING="$heading" ASW_TEXT="$text" ASW_ENDS_NL="$ends_nl" ASW_CREATE="$create" awk '
      function hlevel(s,   n) { n = 0; while (substr(s, n + 1, 1) == "#") { n++ }; return n }
      function out(s) { if (started) { printf "\n" } printf "%s", s; started = 1 }
      function flush_blanks(   i) { for (i = 1; i <= nblank; i++) { out("") } ; nblank = 0 }
      BEGIN {
        h = ENVIRON["ASW_HEADING"]; t = ENVIRON["ASW_TEXT"]
        ends_nl = ENVIRON["ASW_ENDS_NL"]
        create = ENVIRON["ASW_CREATE"]
        hits = 0; insec = 0; done = 0; nblank = 0; started = 0; lvl = 0
      }
      {
        line = $0
        if (line == h) {
          hits++
          if (hits == 1) { insec = 1; lvl = hlevel(line) }
          flush_blanks(); out(line); next
        }
        if (insec && !done && hlevel(line) > 0 && hlevel(line) <= lvl) {
          # Next sibling heading: the entry goes above the blank run that
          # separates this section from it.
          out(t); done = 1; insec = 0
          flush_blanks(); out(line); next
        }
        if (insec && line == "") { nblank++; next }
        flush_blanks(); out(line)
      }
      END {
        if (insec && !done) { out(t); done = 1 }
        flush_blanks()
        if (hits == 0 && create == "1") {
          out(""); out(h); out(t); hits = 1
        }
        if (ends_nl == "1") { printf "\n" }
        if (hits == 0) { exit 77 }
        if (hits > 1)  { exit 78 }
      }
    ' "$target" > "$tmp"
    arc=$?

    if [ "$arc" -ne 0 ]; then
      rm -f "$tmp"
      case "$arc" in
        77) echo "atomic_state_append_section: heading '$heading' not found in $target; nothing changed (pass --create to add the section)" >&2 ;;
        78) echo "atomic_state_append_section: heading '$heading' appears more than once in $target; nothing changed" >&2 ;;
        *)  echo "atomic_state_append_section: rewrite of $target failed (awk rc $arc)" >&2 ;;
      esac
      exit "$arc"
    fi

    _atomic_state_commit atomic_state_append_section "$tmp" "$target" "$dir"
    exit $?
  )
}

# atomic_state_append_list_item <target> <key> <item>
#
# Appends one item to the YAML list under frontmatter <key>, inside the leading
# `---` block only. <item> is the item's content WITHOUT the leading `- ` and
# WITHOUT indentation; the helper indents it (`  - ` on the first line, four
# spaces on the rest), so a caller writes the entry the way the schema shows it
# rather than counting spaces.
#
# Both list shapes are handled: an empty `key: []` becomes a block list, and an
# existing block list gains the item after its last line. A key holding any other
# scalar is refused (rc 79) rather than turned into a list.
#
# This is the shape `atomic_state_set_field` cannot write — `approvals[]`,
# `non-resumable-actions[]`, `workflow_refs[]` are multi-line mappings, and a
# set_field value must be a single line.
atomic_state_append_list_item() {
  local target="${1:-}" key="${2:-}" item="${3:-}"
  if [ -z "$target" ] || [ -z "$key" ]; then
    echo "atomic_state_append_list_item: target path and key required" >&2
    return 64
  fi
  if [ -z "$item" ]; then
    echo "atomic_state_append_list_item: item required; nothing appended to $target" >&2
    return 64
  fi
  if [ ! -f "$target" ] || [ ! -r "$target" ]; then
    echo "atomic_state_append_list_item: $target does not exist or is unreadable" >&2
    return 73
  fi
  if _atomic_state_binary_unsafe "$target"; then
    echo "atomic_state_append_list_item: $target contains a NUL or 0x04 byte, which this helper cannot round-trip" >&2
    return 73
  fi
  (
    dir="$(_atomic_state_prepare_dir "$target")" || {
      echo "atomic_state_append_list_item: failed to mkdir $(dirname "$target")" >&2
      exit 65
    }
    tmp="$(_atomic_state_mktemp "$target")"
    if [ -z "$tmp" ]; then
      echo "atomic_state_append_list_item: failed to create tmp beside $target" >&2
      exit 66
    fi
    trap 'rm -f "$tmp"; exit 130' INT
    trap 'rm -f "$tmp"; exit 143' TERM
    trap 'rm -f "$tmp"; exit 129' HUP

    ends_nl=1
    if [ -s "$target" ] && [ -n "$(tail -c 1 "$target" 2>/dev/null)" ]; then
      ends_nl=0
    fi

    ASW_KEY="$key" ASW_ITEM="$item" ASW_ENDS_NL="$ends_nl" awk '
      function out(s) { if (started) { printf "\n" } printf "%s", s; started = 1 }
      function emit_item(   n, i, parts) {
        n = split(item, parts, "\n")
        for (i = 1; i <= n; i++) {
          if (i == 1) { out("  - " parts[i]) } else { out("    " parts[i]) }
        }
      }
      BEGIN {
        k = ENVIRON["ASW_KEY"]; item = ENVIRON["ASW_ITEM"]
        ends_nl = ENVIRON["ASW_ENDS_NL"]
        fence = 0; state = 0; started = 0; bad = 0
        # state 0 = key not seen, 1 = inside the key block, 2 = written
      }
      {
        line = $0
        if (line == "---") {
          if (fence == 0 && NR == 1)   { fence = 1; out(line); next }
          else if (fence == 1) {
            if (state == 1) { emit_item(); state = 2 }
            fence = 2; out(line); next
          }
        }
        if (fence == 1 && state == 0 && substr(line, 1, length(k) + 1) == k ":") {
          rest = substr(line, length(k) + 2)
          sub(/^[ \t]+/, "", rest)
          if (rest == "[]") { out(k ":"); state = 1; next }        # empty inline list
          if (rest == "")   { out(line);  state = 1; next }        # block list follows
          bad = 1; out(line); next                                  # a scalar — refuse
        }
        if (state == 1) {
          # The block ends at the first line that is not indented under the key.
          if (line ~ /^[ \t]/) { out(line); next }
          emit_item(); state = 2; out(line); next
        }
        out(line)
      }
      END {
        if (state == 1) { emit_item(); state = 2 }
        if (ends_nl == "1") { printf "\n" }
        if (bad)        { exit 79 }
        if (fence != 2) { exit 2 }
        if (state != 2) { exit 3 }
      }
    ' "$target" > "$tmp"
    arc=$?

    if [ "$arc" -ne 0 ]; then
      rm -f "$tmp"
      case "$arc" in
        2)  echo "atomic_state_append_list_item: $target has no closed leading '---' frontmatter block; nothing changed" >&2; exit 74 ;;
        3)  echo "atomic_state_append_list_item: key '$key' not present in the frontmatter of $target; nothing changed" >&2; exit 74 ;;
        79) echo "atomic_state_append_list_item: '$key' holds a scalar, not a list; nothing changed" >&2; exit 79 ;;
        *)  echo "atomic_state_append_list_item: rewrite of $target failed (awk rc $arc)" >&2; exit "$arc" ;;
      esac
    fi

    _atomic_state_commit atomic_state_append_list_item "$tmp" "$target" "$dir"
    exit $?
  )
}

atomic_state_append() {
  local target="${1:-}"   # default so a zero-arg call under `set -u` reaches the guard
  if [ -z "$target" ]; then
    echo "atomic_state_append: target path required" >&2
    return 64
  fi

  # Ensure parent directory exists.
  local dir
  dir="$(_atomic_state_prepare_dir "$target")" || {
    echo "atomic_state_append: failed to mkdir $(dirname "$target")" >&2
    return 65
  }

  # Capture stdin (handles content without trailing newline; `read -r` would
  # return non-zero on EOF and lose the partial line).
  local content
  content="$(cat)"
  if [ -z "$content" ]; then
    # Empty stdin — nothing to append. rc 70, not 0: the caller's producer (jq,
    # redact_secrets, a serializer) failing to emit is exactly how a learning gets
    # "recorded" with rc 0 and no line on disk.
    echo "atomic_state_append: stdin was empty; nothing appended to $target" >&2
    return 70
  fi

  # Byte ceiling for the append. Shell `>>` opens O_APPEND, so the kernel
  # serializes concurrent writes up to PIPE_BUF — but PIPE_BUF is platform
  # dependent (4096 on Linux, only 512 on macOS), so this cap bounds line length
  # and is NOT a hard macOS atomicity guarantee. Reserve 2 bytes for the framing
  # the append adds below (an optional leading `\n` + the trailing `\n`). Count
  # BYTES not characters — ${#content} counts characters, and multibyte content
  # can exceed the ceiling in bytes while staying under it in characters.
  local content_bytes
  content_bytes=$(printf '%s' "$content" | wc -c | tr -d ' ')
  if [ "$content_bytes" -gt "$GENIRO_APPEND_MAX_BYTES" ]; then
    echo "atomic_state_append: content + framing exceeds the ${GENIRO_APPEND_MAX_BYTES}-byte ceiling (content ${content_bytes}); atomicity not guaranteed" >&2
    return 68
  fi

  # Newline-terminator guard. If the target exists and its last byte is not `\n`
  # (typical of hand-edited files or partial migrations), a bare append would
  # concatenate onto the previous final line, corrupting JSONL — a single line
  # holding two adjacent objects. Prepend a `\n` in that case.
  # `[ -n "$(tail -c 1 "$target")" ]` is the portable last-byte-is-not-newline
  # check: command substitution strips trailing newlines, so when the last byte IS
  # `\n`, `$(tail -c 1)` becomes empty and `-n` returns false.
  local prefix="" existed=1
  [ -e "$target" ] || existed=0
  if [ -s "$target" ] && [ -n "$(tail -c 1 "$target" 2>/dev/null)" ]; then
    prefix=$'\n'
  fi

  printf '%s%s\n' "$prefix" "$content" >> "$target" || {
    echo "atomic_state_append: append to $target failed" >&2
    return 69
  }

  _atomic_state_sync_file "$target"
  # A newly created file's directory entry needs the directory synced too,
  # matching what _atomic_state_commit does for the whole-file writers.
  [ "$existed" -eq 0 ] && _atomic_state_sync_file "$dir"
  return 0
}
