#!/usr/bin/env bash
# block-geniro-deletion.sh
# PreToolUse hook for Bash - prevents bulk deletion of .geniro/ contents.
#
# .geniro/ holds user-authored persistent state: instructions/, actions/,
# workflow/, planning/FEATURES.md, planning/<task>/..., knowledge/learnings.jsonl,
# review-findings-state.md, debug/findings-state.md, .geniro-state.json.
# A single accidental `rm -rf .geniro/` (or equivalent) destroys all of it.
# This hook blocks the patterns that have caused real-world data loss.
#
# Allowed by design (NOT blocked):
#   - rm -f <single-file>          (any depth — required by skills' state cleanup)
#   - rm -rf .geniro/<top>/<sub>/  (3+ path segments — task-dir / slug-scoped trees)
#
# Blocked by default:
#   - rm -rf .geniro / .geniro/                    (whole tree)
#   - rm -rf .geniro/<single-segment>              (e.g. .geniro/instructions/)
#   - shell-equivalent forms of the above that the segment gate would otherwise
#     miss: trailing glob (.geniro/instructions/* , .geniro/*), doubled slashes
#     (.geniro//instructions/), parent-escape (.geniro/instructions/..), and a
#     dotted state DIRECTORY name (.geniro/state/review.bak/)
#   - find <path-with-.geniro> ... -delete         (bulk find-delete)
#   - git worktree remove                          (worktrees often hold un-routed state)
#
# Per-project allowlist: .geniro/safety.json (in cwd or any ancestor) can opt out
# via "allow_patterns".
#
# Pattern IDs: rm-geniro-tree, rm-geniro-subdir, rm-geniro-state-subdir,
#              find-geniro-delete, worktree-remove-with-state, git-add-force-geniro
#
# Fixed 2026-05-10 — segment-depth gates (rm-geniro-subdir, rm-geniro-state-subdir)
# now evaluate each rm/find arg INDIVIDUALLY. Previously a single regex against
# the padded command was masked by multi-arg invocations (e.g.
# `rm -rf .geniro/instructions/ .geniro/planning/foo/bar` — the deep second arg
# satisfied the global "is there a 3-seg form anywhere?" check, letting the
# shallow first arg through).

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Pad and collapse newlines (mirrors block-dangerous-git.sh) so multi-line
# heredocs and embedded newlines can't slip past whitespace-anchored matchers.
PADDED=" ${COMMAND//$'\n'/ } "

find_safety_json() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.geniro/safety.json" ]; then
      echo "$dir/.geniro/safety.json"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

ALLOWED=""
SAFETY_FILE=$(find_safety_json 2>/dev/null || true)
if [ -n "$SAFETY_FILE" ] && [ -f "$SAFETY_FILE" ]; then
  ALLOWED=$(jq -r '.allow_patterns[]? // empty' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
fi

is_allowed() {
  local pattern_id="$1"
  case " $ALLOWED " in
    *" $pattern_id "*) return 0 ;;
    *) return 1 ;;
  esac
}

block() {
  local pattern_id="$1"
  local message="$2"
  echo "Geniro safety blocked [$pattern_id]: $message" >&2
  echo "Command: $COMMAND" >&2
  if [ -n "$SAFETY_FILE" ]; then
    echo "To allow this pattern, add \"$pattern_id\" to allow_patterns in $SAFETY_FILE" >&2
  else
    echo "To allow this pattern in this project, create .geniro/safety.json with: {\"allow_patterns\": [\"$pattern_id\"]}" >&2
  fi
  exit 2
}

# Does the command include `rm` with -r (in any flag combination: -rf, -fr, -Rf, -R, --recursive)?
has_rm_recursive() {
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*r[a-zA-Z]*[[:space:]]' && return 0
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?-[a-zA-Z]*R[a-zA-Z]*[[:space:]]' && return 0
  echo "$PADDED" | grep -qE 'rm[[:space:]]+([^|;&]*[[:space:]])?--recursive[[:space:]]' && return 0
  return 1
}

# 1. rm -rf .geniro / .geniro/ (bare — whole tree)
if ! is_allowed "rm-geniro-tree"; then
  if has_rm_recursive; then
    if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro/?[[:space:]"'"'"';|&]'; then
      block "rm-geniro-tree" "rm -rf .geniro/ would wipe ALL plugin runtime + user-authored content (instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Use \`rm -f <single-file>\` for individual deletes."
    fi
  fi
fi

# 2 & 2b. Per-arg evaluation of .geniro/ subdirectory protections.
#
# Why per-arg: a single regex against $PADDED can be masked by a multi-arg
# command. E.g. `rm -rf .geniro/instructions/ .geniro/planning/foo/bar` —
# the second arg's 3-seg shape made the global "is there a deep form anywhere?"
# check pass, letting the first arg's shallow `.geniro/instructions/` through.
# We now iterate each token and apply the segment-depth gate to each one
# independently.
#
# Pattern IDs evaluated per arg:
#   - rm-geniro-subdir       — `.geniro/<seg>` / `.geniro/<seg>/`            (2 segments)
#   - rm-geniro-state-subdir — `.geniro/state/<seg>` / `.geniro/state/<seg>/` (3 segments,
#                              non-filename)
#
# Allowed (NOT blocked) per arg:
#   - `.geniro/<top>/<sub>...` (3+ segments) — task-dir / slug-scoped trees
#   - `.geniro/state/<file>.<ext>` (3 segments where last is a file with extension)
#   - `.geniro/state/<skill>/<file>` (4+ segments) — slug-scoped state files

if has_rm_recursive; then
  # Tokenize the original COMMAND on whitespace. Strip surrounding quotes from
  # each token so `'.geniro/x/'`, `".geniro/x/"`, and `.geniro/x/` all evaluate
  # the same. This is best-effort tokenization (not a full shell parser); it's
  # sufficient to catch the realistic multi-arg `rm` form.
  # Disable globbing so a token like `.geniro/*` is word-split on whitespace but
  # NOT expanded against the cwd — expansion would replace it with real paths and
  # bypass the segment checks below. `set -f` is POSIX and behaves identically on
  # bash 3.2 (macOS) and GNU bash.
  set -f
  # shellcheck disable=SC2086
  for raw in $COMMAND; do
    # Trim surrounding single/double quotes
    arg="${raw#\"}"; arg="${arg%\"}"
    arg="${arg#\'}"; arg="${arg%\'}"

    # Remember whether the arg explicitly named a directory (trailing slash) — a
    # dotted DIRECTORY name (.geniro/state/review.bak/) must not be mistaken for a
    # file by the extension carve-out below.
    had_trailing_slash=0
    case "$arg" in */) had_trailing_slash=1 ;; esac

    # Strip a trailing slash for segment-counting.
    stripped="${arg%/}"

    # Only inspect args that are .geniro/-rooted paths (allow optional leading ./).
    case "$stripped" in
      .geniro|./.geniro)
        # Bare `.geniro` arg — the rm-geniro-tree check below handles the whole-
        # tree form. Skip here.
        continue
        ;;
      .geniro/*|./.geniro/*) ;;
      *) continue ;;
    esac

    # Normalize: drop leading "./" so segment counts are stable.
    norm="${stripped#./}"

    # Normalize to the path the shell actually deletes, so equivalent forms count
    # at the same depth instead of slipping the segment gate:
    #  - squeeze repeated slashes: .geniro//instructions == .geniro/instructions
    #  - drop a trailing glob '*' segment: the shell expands .geniro/instructions/*
    #    to every entry in the PARENT — the same loss as .geniro/instructions/.
    while [ "$norm" != "${norm//\/\//\/}" ]; do norm="${norm//\/\//\/}"; done
    if [ "${norm##*/}" = "*" ]; then norm="${norm%/*}"; fi

    # After dropping a trailing glob, a bare `.geniro` means "delete everything in
    # .geniro" (rm -rf .geniro/*) — the whole-tree loss spelled with a glob.
    if [ "$norm" = ".geniro" ]; then
      if ! is_allowed "rm-geniro-tree"; then
        block "rm-geniro-tree" "rm -rf .geniro/* expands to every entry under .geniro/ — the same loss as rm -rf .geniro/. Use \`rm -f <single-file>\` for individual deletes."
      fi
      continue
    fi

    # A `..` segment escapes upward (.geniro/instructions/.. resolves to .geniro/),
    # so it can wipe a protected parent. Reject rather than resolve it.
    case "/$norm/" in
      */../*)
        if ! is_allowed "rm-geniro-subdir"; then
          block "rm-geniro-subdir" "rm -rf on a .geniro/ path containing '..' ($arg) can escape upward and wipe a protected parent. Use an explicit path without '..'."
        fi
        ;;
    esac

    # Count path segments (number of '/' + 1).
    slashes="${norm//[!\/]/}"
    seg_count=$(( ${#slashes} + 1 ))

    # 2-segment form: `.geniro/<seg>` — top-level subdir wipe.
    if [ "$seg_count" -eq 2 ]; then
      if ! is_allowed "rm-geniro-subdir"; then
        block "rm-geniro-subdir" "rm -rf on a top-level .geniro/ subdirectory ($arg) wipes that entire category of user content. Allowed: deeper paths like .geniro/planning/<task-dir>/ (3+ segments). Use \`rm -f\` per-file for individual deletes."
      fi
    fi

    # 3-segment form under .geniro/state/: `.geniro/state/<seg>` — per-skill state wipe.
    # Allow if the last segment looks like a filename (has a dot+ext).
    if [ "$seg_count" -eq 3 ]; then
      case "$norm" in
        .geniro/state/*)
          last_seg="${norm##*/}"
          # Treat as a real FILE (allow) only if the last segment has a dot+ext
          # AND the arg did not end in a slash. A trailing slash means it is a
          # directory — even a dotted one like review.bak/ — so it must be gated.
          if [ "$had_trailing_slash" -eq 0 ] && [[ "$last_seg" == *.* ]] && [[ "$last_seg" =~ \.[a-zA-Z0-9]+$ ]]; then
            : # file delete (e.g. .geniro/state/review-findings-state.md) — allow
          else
            if ! is_allowed "rm-geniro-state-subdir"; then
              block "rm-geniro-state-subdir" "rm -rf on a .geniro/state/<skill>/ subdirectory ($arg) wipes parallel-branch slug files still in flight. Allowed: single-file deletes (.geniro/state/<file>.md) and 4+ segment paths (.geniro/state/<skill>/state-<slug>.md). Use \`rm -f <single-file>\` for cleanup."
            fi
          fi
          ;;
      esac
    fi
  done
  set +f
fi

# 3. find ... .geniro ... -delete  (any flavor of find-delete that touches .geniro)
if ! is_allowed "find-geniro-delete"; then
  if echo "$PADDED" | grep -qE 'find[[:space:]]+[^|;&]*\.geniro[^|;&]*-delete'; then
    block "find-geniro-delete" "find ... -delete on .geniro/ wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path, or pathlib.Path.unlink in Python) so each deletion is auditable."
  fi
fi

# 4. git worktree remove  (worktrees commonly contain .geniro/ state not routed
#    through ${PRIMARY_ROOT} — removal silently destroys it).
if ! is_allowed "worktree-remove-with-state"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+worktree[[:space:]]+remove[[:space:]]'; then
    block "worktree-remove-with-state" "git worktree remove destroys the gitignored .geniro/ in the worktree. Verify the worktree's .geniro/ is empty (or that all needed state was routed to the primary worktree via _shared/primary-worktree.md) before removing."
  fi
fi

# 5. git add -f / --force on .geniro/ paths. Force-adding ignored files makes them
#    appear in the IDE's Source Control panel — and IDE "Discard All Changes" then
#    becomes a one-click data-loss vector (real incident: Cursor SCM discard wiped
#    .geniro/actions/*.md after they were force-added). The correct path for files
#    that should be tracked is to negate them in .gitignore (e.g. !.geniro/actions/),
#    not to bypass the ignore via -f.
if ! is_allowed "git-add-force-geniro"; then
  # `git add` invocation with -f or --force present, AND a .geniro/ path argument.
  if echo "$PADDED" | grep -qE 'git[[:space:]]+add[[:space:]]'; then
    if echo "$PADDED" | grep -qE 'git[[:space:]]+add[[:space:]]+([^|;&]*[[:space:]])?(-[a-zA-Z]*f[a-zA-Z]*[[:space:]]|--force[[:space:]])'; then
      if echo "$PADDED" | grep -qE '(/|[[:space:]"'"'"'])\.geniro(/|[[:space:]"'"'"';|&])'; then
        block "git-add-force-geniro" "git add -f on .geniro/ paths makes ignored files appear in the IDE's Source Control panel — one click of 'Discard All Changes' then deletes them. To track .geniro/ subdirs, negate them in .gitignore instead (e.g. \`!.geniro/actions/\` and \`!.geniro/actions/**\`)."
      fi
    fi
  fi
fi

exit 0
