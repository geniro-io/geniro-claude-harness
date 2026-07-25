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
#     miss: trailing glob (.geniro/instructions/* , .geniro/*), prefix glob
#     (.gen*, .geniro*), doubled slashes (.geniro//instructions/), parent-escape
#     (.geniro/instructions/..), a dotted state DIRECTORY name
#     (.geniro/state/review.bak/), and prefixed paths (/abs/.geniro/<seg>,
#     $PWD/.geniro/<seg>, ../proj/.geniro/<seg>)
#   - find <path-with-.geniro> ... -delete / -exec rm  (bulk deletes)
#   - <anything naming .geniro> | xargs rm             (bulk delete, find optional)
#   - rsync --delete into a .geniro/ path              (mirrors the dir away)
#   - interpreter-mediated deletes (python/node/perl/ruby/php shutil.rmtree,
#     os.remove, fs.rmSync, File.delete, unlink, …) — not shell syntax, so the
#     rm matchers never see them; each target runs the same depth rules
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

# Fail open but LOUDLY if jq is missing: without it the guard cannot inspect
# commands, and a silent exit 0 would leave the user believing the guard is active.
if ! command -v jq >/dev/null 2>&1; then
  # Data-loss guard: without jq we cannot parse the command out of the tool JSON,
  # but a raw scan for the highest-signal bulk-delete token still blocks the worst
  # case before failing open. Coarse by design (it also sees the token inside a
  # quoted string) — accepted for a rarely-hit degraded path.
  RAW=$(cat)
  if printf '%s' "$RAW" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+[^|;&]*\.geniro'; then
    echo "Geniro safety blocked [jqless-fallback]: a recursive rm touching .geniro/ was seen and jq is unavailable, so only a coarse raw-text check ran. Install jq to restore full command parsing." >&2
    exit 2
  fi
  printf '{"systemMessage":"Geniro guard inactive: jq not found on PATH, so .geniro/ deletions are NOT being checked. Install jq to restore the guard."}\n'
  exit 0
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Heredoc bodies are DATA, not shell syntax — an `rm -rf .geniro/` mentioned
# inside one is documentation text, not a command. Drop body lines (between
# <<TAG / <<-TAG / <<'TAG' / << TAG and the closing TAG) before any matching; the
# line carrying the << operator is kept. Mirrors block-dangerous-git.sh.
SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
  hd {
    line = $0
    if (dash) sub(/^\t+/, "", line)
    if (line == tag) hd = 0
    next
  }
  match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
    tag = substr($0, RSTART, RLENGTH)
    dash = (tag ~ /^<<-/)
    sub(/^<<-?[[:space:]]*/, "", tag)
    gsub(/["'\'']/, "", tag)
    hd = 1
    print
    next
  }
  { print }
')

# Interpreter indirection: `sh -c "<payload>"` and `eval "<payload>"` run
# <payload> as a command; the quote-scrub below would treat it as data and miss
# a destructive op inside. Extraction is single-sourced in lib/write-vectors.sh;
# the inline fallback keeps the guard recursing on a vendored install shipping
# hooks/ without lib/ — a missing helper must never make this guard fail open.
_geniro_wv_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"
if [ -f "$_geniro_wv_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_wv_helper" 2>/dev/null || true
fi
if ! command -v _geniro_extract_inner_payloads >/dev/null 2>&1; then
  _geniro_extract_inner_payloads() {
    local cmd="${1:-}"
    if [ -z "$cmd" ]; then return 0; fi
    local _m _pl
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
      _pl="${_pl#\"}"; _pl="${_pl%\"}"; _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/])(sh|bash|zsh|dash|ksh|ash)[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
      _pl="${_pl#\"}"; _pl="${_pl%\"}"; _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"
    return 0
  }
fi

# Re-run THIS guard on each extracted payload (unblanked); a block inside
# propagates out. Nested indirection terminates because each payload is
# strictly shorter than the command it came from.
_geniro_self="${BASH_SOURCE[0]:-$0}"
INNER_PAYLOADS=$(_geniro_extract_inner_payloads "$SCRUBBED")
if [ -n "$INNER_PAYLOADS" ]; then
  while IFS= read -r _pl; do
    [ -z "$_pl" ] && continue
    if ! printf '%s' "$_pl" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$_geniro_self"; then
      exit 2
    fi
  done <<< "$INNER_PAYLOADS"
fi

# Join backslash-newline continuations, then pad and collapse newlines (mirrors
# block-dangerous-git.sh) so multi-line heredocs, line-continued commands, and
# embedded newlines can't slip past whitespace-anchored matchers.
JOINED="${SCRUBBED//\\$'\n'/ }"
PADDED=" ${JOINED//$'\n'/ } "

# Strip git GLOBAL options (`git -C <path> worktree remove`, `git -c k=v add -f`,
# --git-dir/--work-tree/--namespace/--exec-path/--config-env/--attr-source, pager
# flags) so the `git <subcommand>` matchers below see the subcommand contiguously.
# Without this, `git -C /repo worktree remove` and `git -C /repo add -f .geniro/...`
# evade the data-loss guards. The operand alternative matches a double- or
# single-quoted span (which may contain spaces) before a bare token, so a quoted
# path like `git -C "/my repo" worktree remove` is consumed as one unit instead of
# the strip stopping at the first space inside the quotes and leaking the
# subcommand. Mirrors block-dangerous-git.sh (kept inline so this guard stays
# self-contained for vendored installs).
_op='("[^"]*"|'\''[^'\'']*'\''|[^[:space:]]+)'
PADDED=$(printf '%s' "$PADDED" | sed -E "s/git([[:space:]]+(-C[[:space:]]+${_op}|-c[[:space:]]+${_op}|--git-dir(=${_op}|[[:space:]]+${_op})|--work-tree(=${_op}|[[:space:]]+${_op})|--namespace(=${_op}|[[:space:]]+${_op})|--exec-path(=${_op}|[[:space:]]+${_op})|--config-env(=${_op}|[[:space:]]+${_op})|--attr-source(=${_op}|[[:space:]]+${_op})|-P|--no-pager|-p|--paginate|--no-optional-locks|--literal-pathspecs))+/git/g")

# A BACKSLASH-ESCAPED separator (\| \; \&) is data, never a shell command
# separator: it spells an alternation in a BRE pattern (`grep "a\|b"`) or
# terminates a `find -exec`. Pass B below deliberately refuses to blank a quoted
# span containing ; & | (an unbalanced apostrophe in prose must not pair across a
# real separator and swallow a destructive command between two quotes) — so an
# escaped separator inside a quoted literal left the WHOLE literal unblanked, and
# the per-arg tokenizer then read `grep -c "foo\|rm -rf .geniro/state" f.md` as a
# real subdirectory wipe. Neutralizing the escaped form first can only split
# tokens apart, never hide a command from the matchers.
PADDED=$(printf '%s' "$PADDED" | sed -E 's/\\[;&|]/ /g')

# Quoted string literals are DATA, not commands — with two exceptions handled by
# pass ordering. Pass A UNQUOTES a whitespace-free quoted token: a quoted rm
# OPERAND (`rm -rf ".geniro/"`) or a quoted SUBCOMMAND token (`git worktree
# "remove" ../wt`) is a single shell word, so unquoting it re-exposes the real
# delete / worktree-removal to the matchers below. Pass B then blanks the
# remaining quoted literals — those all contain whitespace or a separator, i.e.
# prose (`echo "do not rm -rf .geniro/"`, `git commit -m "why git add -f .geniro/
# is banned"`, `echo "later: git worktree remove ../wt"`), which must never
# block. Pass B excludes ; & | so an unbalanced apostrophe in prose cannot pair
# across a separator and swallow a real destructive command between two quotes.
PADDED=$(printf '%s' "$PADDED" | sed -E "s/\"([^\"[:space:]]*)\"/\1/g; s/'([^'[:space:]]*)'/\1/g; s/'[^';&|]*'/ /g; s/\"[^\";&|]*\"/ /g")

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

# 1 & 2. Per-SPAN, then per-ARG evaluation of rm commands.
#
# Spans: each `rm ...` segment of the command (bounded by the next &/;/|
# separator) is evaluated on its own, so a .geniro path used by a NON-rm part
# of a compound command (`mkdir -p .geniro/x && rm -rf /tmp/y`) is not
# mistaken for an rm argument. The boundary class includes ( and / so
# `$(rm ...)` substitutions and `/bin/rm` still produce a span.
#
# Per-arg: a single regex against a span can be masked by a multi-arg command.
# E.g. `rm -rf .geniro/instructions/ .geniro/planning/foo/bar` — the second
# arg's 3-seg shape made the global "is there a deep form anywhere?" check
# pass, letting the first arg's shallow `.geniro/instructions/` through. Each
# token gets the segment-depth gate independently.
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

# Evaluate ONE delete operand against the .geniro/ depth rules. `recursive` is 1
# for a delete that removes a tree (`rm -r`, an interpreter rmtree) and 0 for a
# per-file delete, which bulk-deletes only through a glob. Shared by the rm loop,
# the rsync --delete arm, and the interpreter-mediated delete vector so all three
# grant the same allowances.
check_delete_arg() {
  local raw="$1" recursive="$2"
  local arg stripped norm glob_probe had_trailing_slash last_seg slashes seg_count

  # Trim surrounding single/double quotes, plus a trailing command-
  # substitution close so `$(rm -rf .geniro/x)` tokens still segment-count.
  arg="${raw#\"}"; arg="${arg%\"}"
  arg="${arg#\'}"; arg="${arg%\'}"
  arg="${arg%)}"

  # Non-recursive rm bulk-deletes only via a glob; skip non-glob args so a
  # single-file `rm -f <path>` (any depth) stays allowed while
  # `rm -f .geniro/<dir>/*` (bulk) falls through to the segment gate.
  if [ "$recursive" -eq 0 ]; then
    case "$arg" in *'*'*|*'?'*|*'['*) : ;; *) return 0 ;; esac
  fi

  # Remember whether the arg explicitly named a directory (trailing slash) — a
  # dotted DIRECTORY name (.geniro/state/review.bak/) must not be mistaken for a
  # file by the extension carve-out below.
  had_trailing_slash=0
  case "$arg" in */) had_trailing_slash=1 ;; esac

  # Strip a trailing slash for segment-counting.
  stripped="${arg%/}"

  # A prefix-glob token expands to .geniro/ at execution time even though the
  # literal token never spells the full name (`rm -rf .gen*`). Treat any glob
  # whose literal prefix is a prefix of ".geniro" as a whole-tree delete.
  glob_probe="${stripped#./}"
  case "$glob_probe" in
    '.*'|'.g*'|'.ge*'|'.gen*'|'.geni*'|'.genir*'|'.geniro*')
      if ! is_allowed "rm-geniro-tree"; then
        block "rm-geniro-tree" "rm -rf $arg is a glob that expands to .geniro/ — the same loss as rm -rf .geniro/. Use \`rm -f <single-file>\` for individual deletes."
      fi
      return 0
      ;;
  esac

  # Inspect any arg that carries a .geniro path segment. Absolute paths,
  # unexpanded \$PWD/~ prefixes, and ../-escapes delete the same tree as the
  # relative spelling, so they are normalized to their `.geniro/...` suffix
  # before segment-counting. A bare `.geniro` (however prefixed) is the whole
  # tree — the span regex catches the rm spelling, this catches every other
  # caller's.
  case "$stripped" in
    .geniro|./.geniro|*/.geniro)
      if ! is_allowed "rm-geniro-tree"; then
        block "rm-geniro-tree" "deleting $arg would wipe ALL plugin runtime + user-authored content (instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Use \`rm -f <single-file>\` for individual deletes."
      fi
      return 0
      ;;
    .geniro/*)   norm="$stripped" ;;
    ./.geniro/*) norm="${stripped#./}" ;;
    */.geniro/*) norm=".geniro/${stripped##*/.geniro/}" ;;
    *) return 0 ;;
  esac

  # Normalize to the path the shell actually deletes, so equivalent forms count
  # at the same depth instead of slipping the segment gate:
  #  - squeeze repeated slashes: .geniro//instructions == .geniro/instructions
  #  - drop a trailing glob segment — bare `*` OR a globbed filename like `*.md`:
  #    the shell expands .geniro/instructions/*.md to every matching entry in the
  #    PARENT, the same loss as wiping .geniro/instructions/ itself. Matching only
  #    a bare `*` let `.geniro/instructions/*.md` keep its 3rd segment and pass the
  #    gate while `.geniro/instructions/*` was correctly blocked.
  while [ "$norm" != "${norm//\/\//\/}" ]; do norm="${norm//\/\//\/}"; done
  case "${norm##*/}" in *'*'*) norm="${norm%/*}" ;; esac

  # After dropping a trailing glob, a bare `.geniro` means "delete everything in
  # .geniro" (rm -rf .geniro/*) — the whole-tree loss spelled with a glob.
  if [ "$norm" = ".geniro" ]; then
    if ! is_allowed "rm-geniro-tree"; then
      block "rm-geniro-tree" "rm -rf .geniro/* expands to every entry under .geniro/ — the same loss as rm -rf .geniro/. Use \`rm -f <single-file>\` for individual deletes."
    fi
    return 0
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
  return 0
}

RM_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[|;&(/[:space:]])rm[[:space:]]+[^|;&]*' || true)
while IFS= read -r RM_SPAN; do
  [ -z "$RM_SPAN" ] && continue
  # Recursion gate. A recursive rm (-r/-R in any flag combination, or
  # --recursive) is fully segment-gated. A NON-recursive rm still causes bulk
  # loss through a glob — `rm -f .geniro/actions/*` expands to every file in the
  # dir, the same loss as wiping it — while `rm -f <single-file>` at any depth
  # is an allowed individual delete and a bare `rm -f <dir>` without -r is a
  # no-op. So a non-recursive span also runs the per-arg gate below, but the
  # loop evaluates ONLY its glob args (it skips non-glob args), keeping
  # single-file deletes allowed.
  recursive=0
  if printf '%s' " $RM_SPAN " | grep -qE '[[:space:]]-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]|[[:space:]]--recursive[[:space:]]'; then
    recursive=1
  fi

  # 1. rm -rf .geniro / .geniro/ / <prefix>/.geniro (bare — whole tree). Only a
  #    recursive rm deletes a bare directory, so this whole-tree check is
  #    recursion-gated; the glob spellings (.geniro/*) are caught per-arg below
  #    for both recursion modes. The trailing space appended to the span lets
  #    the terminator class match at end-of-span; ) is in the class so
  #    `$(rm -rf .geniro)` terminates a match.
  if [ "$recursive" -eq 1 ] && ! is_allowed "rm-geniro-tree"; then
    if printf '%s' "$RM_SPAN " | grep -qE '(/|[[:space:]"'"'"'])\.geniro/?[[:space:]"'"'"');|&]'; then
      block "rm-geniro-tree" "rm -rf .geniro/ would wipe ALL plugin runtime + user-authored content (instructions, actions, workflow, FEATURES.md, learnings, planning artifacts). Use \`rm -f <single-file>\` for individual deletes."
    fi
  fi

  # 2 & 2b. Tokenize the span on whitespace. Strip surrounding quotes from
  # each token so `'.geniro/x/'`, `".geniro/x/"`, and `.geniro/x/` all evaluate
  # the same. This is best-effort tokenization (not a full shell parser); it's
  # sufficient to catch the realistic multi-arg `rm` form.
  # Disable globbing so a token like `.geniro/*` is word-split on whitespace but
  # NOT expanded against the cwd — expansion would replace it with real paths and
  # bypass the segment checks below. `set -f` is POSIX and behaves identically on
  # bash 3.2 (macOS) and GNU bash.
  set -f
  # shellcheck disable=SC2086
  for raw in $RM_SPAN; do
    check_delete_arg "$raw" "$recursive"
  done
  set +f
done <<< "$RM_SPANS"

# 2c. Interpreter-mediated deletes: python/node/perl/ruby/php removing a .geniro
#     path (shutil.rmtree, os.remove, fs.rmSync, File.delete, unlink, …). None of
#     that is shell syntax, so the rm spans above never see it. Each resolved
#     target runs the SAME depth rules as an rm operand, so a per-file delete and
#     a 3+-segment task dir stay allowed. Contract: lib/write-vectors.sh, sourced
#     with the shell-indirection extractor above.
if ! command -v _geniro_interp_delete_targets >/dev/null 2>&1; then
  # Degraded stand-in on a vendored install shipping hooks/ without lib/:
  # literal targets only (no variable resolution), rc=10 for every other delete
  # op so the caller still scans the command for .geniro paths.
  _geniro_interp_delete_targets() {
    local c="${1:-}" q="\\\\?[\"']"
    local ops="(shutil\.rmtree|rmtree|os\.removedirs|os\.remove|os\.unlink|os\.rmdir|fs\.rmSync|fs\.rmdirSync|fs\.unlinkSync|fs\.rm|rmSync|rmdirSync|unlinkSync|FileUtils\.rm_rf|FileUtils\.rm_r|FileUtils\.rm|File\.delete|File\.unlink|Dir\.delete|unlink|rmdir)"
    printf '%s' "$c" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)' || return 0
    printf '%s' "$c" | grep -oE "${ops}\([[:space:]]*${q}[^\\\\\"']+${q}|Path\([[:space:]]*${q}[^\\\\\"']+${q}[[:space:]]*\)[[:space:]]*\.(unlink|rmdir)" 2>/dev/null \
      | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//" || true
    if printf '%s' "$c" | grep -qE "${ops}\("; then
      return 10
    fi
    return 0
  }
fi

_id_unresolved=0
_id_targets=$(_geniro_interp_delete_targets "$COMMAND") || _id_unresolved=1
if [ -n "$_id_targets" ] || [ "$_id_unresolved" = "1" ]; then
  # Tree-removing ops (rmtree, rm_rf, rmSync/rm with recursive) delete a whole
  # directory; the per-file ops do not, and get the same treatment as `rm -f`.
  _id_recursive=0
  if printf '%s' "$COMMAND" | grep -qE 'rmtree|rm_rf|rm_r\(|rmSync|rmdirSync|removedirs|rmdir|recursive'; then
    _id_recursive=1
  fi
  while IFS= read -r _id_tok; do
    [ -z "$_id_tok" ] && continue
    check_delete_arg "$_id_tok" "$_id_recursive"
  done <<< "$_id_targets"
  if [ "$_id_unresolved" = "1" ]; then
    # The delete target is a variable or expression. Fall back to the .geniro
    # paths named anywhere in the command — the same conservative resolution
    # hooks/enforce-state-helper.sh applies to an unresolvable write target.
    while IFS= read -r _id_tok; do
      [ -z "$_id_tok" ] && continue
      check_delete_arg "$_id_tok" "$_id_recursive"
    done <<< "$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]\"'\`=(),;|&<>{}]+" 2>/dev/null | grep -E '(^|/)\.geniro(/|$)' 2>/dev/null || true)"
  fi
fi

# 3. find ... .geniro ... -delete / -exec rm / piped to xargs rm — bulk deletion
#    that walks the tree. All three spellings produce the same loss.
if ! is_allowed "find-geniro-delete"; then
  if echo "$PADDED" | grep -qE 'find[[:space:]]+[^|;&]*\.geniro[^|;&]*-delete'; then
    block "find-geniro-delete" "find ... -delete on .geniro/ wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path, or pathlib.Path.unlink in Python) so each deletion is auditable."
  fi
  if echo "$PADDED" | grep -qE 'find[[:space:]]+[^|;&]*\.geniro[^|;&]*-exec(dir)?[[:space:]]+([^[:space:]]*/)?rm([[:space:]]|$)'; then
    block "find-geniro-delete" "find ... -exec rm on .geniro/ wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path) so each deletion is auditable."
  fi
  # `xargs rm` deletes in bulk whatever the left-hand side lists, and find is only
  # one of the producers (`echo .geniro | xargs rm -rf`, `ls .geniro/x | xargs rm`
  # lose the same content), so the arm matches any pipeline whose left side names
  # a .geniro path.
  if echo "$PADDED" | grep -qE '\.geniro[^&;]*\|[[:space:]]*xargs([[:space:]]+(-[^[:space:]]+|\{\}))*[[:space:]]+([^[:space:]]*/)?rm([[:space:]]|$)'; then
    block "find-geniro-delete" "piping a .geniro/ path into \`xargs rm\` wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path) so each deletion is auditable."
  fi
fi

# 3b. rsync --delete INTO a .geniro/ path — an empty (or partial) source mirrors
#     over the destination and removes everything the source lacks, the same loss
#     as deleting the directory. The destination runs the same depth rules as an
#     rm operand, so a deep task dir keeps its allowance.
RSYNC_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[|;&(/[:space:]])rsync[[:space:]]+[^|;&]*' || true)
while IFS= read -r RSYNC_SPAN; do
  [ -z "$RSYNC_SPAN" ] && continue
  printf '%s' "$RSYNC_SPAN" | grep -qE '[[:space:]]--delete([-=][a-z]+)?([[:space:]]|$)' || continue
  rsync_dest=""
  set -f
  # shellcheck disable=SC2086
  for tok in $RSYNC_SPAN; do
    case "$tok" in rsync|*/rsync|-*) continue ;; esac
    rsync_dest="$tok"
  done
  set +f
  [ -n "$rsync_dest" ] && check_delete_arg "$rsync_dest" 1
done <<< "$RSYNC_SPANS"

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
