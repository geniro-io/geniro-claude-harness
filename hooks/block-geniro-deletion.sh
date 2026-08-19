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
#   - find <path-with-.geniro> ... -delete, or -exec rm/mv/unlink/shred/truncate
#     (bulk deletes and bulk displacement)
#   - <anything naming .geniro> | xargs rm             (bulk delete, find optional)
#   - rsync --delete into a .geniro/ path              (mirrors the dir away)
#   - mv of a .geniro/ path elsewhere                  (displacement loses the
#     tree from its protected location as completely as deletion; only SOURCE
#     operands are gated, so moving content INTO .geniro/ stays allowed)
#   - interpreter-mediated deletes and moves (a scripting runtime
#     shutil.rmtree, os.remove, fs.rmSync, File.delete, unlink, shutil.move,
#     os.rename, …) — not shell syntax, so the rm and mv matchers never see
#     them; each target runs the same depth rules
#   - git worktree remove                          (worktrees often hold un-routed state)
#
# Per-project allowlist: .geniro/safety.json (in cwd or any ancestor) can opt out
# via "allow_patterns".
#
# Pattern IDs: rm-geniro-tree, rm-geniro-subdir, rm-geniro-state-subdir,
#              find-geniro-delete, worktree-remove-with-state, git-add-force-geniro
#
# Known bypass (accepted, not closed): every span below requires the command
# WORD itself (`rm`, `find`, `git`, …) to be a literal token — a word reached
# through a variable (`C=rm; $C -rf .geniro/`) evades every matcher, because
# none expand a shell variable before matching. Verified passing (rc=0) where
# the literal spelling blocks. The same shape defeats block-dangerous-git.sh's
# subcommand matchers too (see its header comment). Not closed: resolving an
# arbitrary variable into the COMMAND-WORD position (not a quoted-literal
# argument, which lib/write-vectors.sh's `_geniro_wv_resolve` already handles)
# would need a second matching pass for every span in this file, and the shape
# requires the attacker to have already planted an assignment earlier in the
# same command.
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
  # jq is present, but the command extracted empty — either tool_input.command
  # was genuinely absent, or the payload was malformed JSON the parse above
  # silently swallowed (`|| echo ""`). A malformed payload must not be a free
  # pass: run the same coarse fail-closed raw-text scan the jq-absent branch
  # above uses, so a recursive .geniro/ delete still blocks even when parsing
  # broke.
  if printf '%s' "$INPUT" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*[[:space:]]+[^|;&]*\.geniro'; then
    echo "Geniro safety blocked [jqless-fallback]: a recursive rm touching .geniro/ was seen but tool_input.command could not be parsed, so only a coarse raw-text check ran." >&2
    exit 2
  fi
  exit 0
fi

# Heredoc bodies are DATA, not shell syntax — an `rm -rf .geniro/` mentioned
# inside one is documentation text, not a command. Drop body lines (between
# <<TAG / <<-TAG / <<'TAG' / <<\TAG / << TAG and the closing TAG) before any matching; the
# line carrying the << operator is kept. Mirrors block-dangerous-git.sh.
SCRUBBED=$(printf '%s\n' "$COMMAND" | awk '
  hd {
    line = $0
    if (dash) sub(/^\t+/, "", line)
    if (line == tag) { hd = 0; nbuf = 0; next }
    buf[nbuf++] = $0
    next
  }
  {
    n = length($0); q = ""; pos = 0
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (q != "") { if (c == q) q = ""; continue }
      if (c == "\"" || c == "'\''") { q = c; continue }
      if (c == "<" && substr($0, i+1, 1) == "<" && substr($0, i+2, 1) != "<") { pos = i; break }
    }
    if (pos > 0 && match(substr($0, pos), /^<<-?[[:space:]]*[\\"'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
      tag = substr($0, pos, RLENGTH)
      dash = (tag ~ /^<<-/)
      sub(/^<<-?[[:space:]]*/, "", tag)
      gsub(/[\\"'\'']/, "", tag)
      hd = 1
      nbuf = 0
      print
      next
    }
    print
  }
  END {
    if (hd) for (j = 0; j < nbuf; j++) print buf[j]
  }
')

# Shell indirection: `sh -c "<payload>"` / `eval "<payload>"` pass <payload> as
# an ARGUMENT, and `echo "<payload>" | bash` / `bash <<EOF … EOF` pass it on
# STDIN. All four run <payload> as a command, but the quote-scrub below would
# treat it as data — and the heredoc scrub above deletes it outright — so a
# destructive op inside would never be seen. Extraction and the
# interpreter-delete scan are single-sourced in lib/write-vectors.sh; each
# inline fallback keeps the guard whole on a vendored install shipping hooks/
# without lib/ — a missing helper must never make this guard fail open — and is
# a VERBATIM copy of the canonical function. A one-sided edit reopens the hole
# there, so edit both or neither — parity is enforced by
# tests/hooks/write-vectors-fallback-parity.sh, not by markers on the canonical
# side (lib/write-vectors.sh carries none).
_geniro_wv_helper="${CLAUDE_PLUGIN_ROOT:-.}/lib/write-vectors.sh"
if [ -f "$_geniro_wv_helper" ]; then
  # shellcheck source=/dev/null
  source "$_geniro_wv_helper" 2>/dev/null || true
fi
if ! command -v _geniro_extract_inner_payloads >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_extract_inner_payloads
_geniro_extract_inner_payloads() {
  local cmd="${1:-}"
  local raw="${2:-}"
  if [ -z "$cmd" ] && [ -z "$raw" ]; then
    return 0
  fi
  local _m _pl _lit

  # ONE shell-word matcher for every arm, and every part of it is DERIVED rather
  # than enumerated — including the SHAPE of the shell word itself, not just the
  # list of channels it appears in.
  #
  # A WRAPPER is any command word whose own arguments are flags, `VAR=value`
  # assignments, durations or `{}` placeholders. `sudo`, `nohup`, `timeout 5` and
  # `env FOO=bar` fall out of that shape — and so do `setsid`, `busybox`,
  # `unshare`, `firejail` and whatever ships next, each of which a NAME list would
  # have to grow for one at a time (and did not: `setsid bash` and `busybox sh`
  # both walked past every guard). Keeping the ARGUMENT shape constrained is what
  # stops an ordinary two-word command (`grep foo bash`) from reading as a
  # wrapped shell.
  local _wv_wrd='[^-[:space:];|&<>"'\''=][^[:space:];|&<>"'\'']*'
  local _wv_wargs='([[:space:]]+(-[^[:space:];|&<>]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&<>]*|[0-9]+[smhd]?|[{}]+))*'
  local _wv_pfx="(${_wv_wrd}${_wv_wargs}[[:space:]]+)*"
  local _wv_shq='["'\'']?'
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|xonsh|nu|elvish|rc)'"${_wv_shq}"
  # One quoted literal; and the payload operand form, which may also be bare.
  local _wv_lit='("[^"]*"|'\''[^'\'']*'\'')'
  local _wv_arg='("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)'
  # A quote and its negation, for building a sed script whose delimiter is `#`.
  local _wv_q='["'\'']' _wv_nq='[^"'\'']'
  # Any flag cluster; the `-c` cluster in particular (ANY cluster containing c —
  # -c, -lc, -euc); and a token that is provably NOT a `c` cluster (a short
  # cluster with no c, a long option, a redirection, or a plain operand).
  local _wv_flag='-[^[:space:];|&<>]*'
  local _wv_cflag='-[A-Za-z]*c[A-Za-z]*'
  local _wv_nonc='(-[a-bd-zA-BD-Z0-9]*|--[^[:space:];|&]*|[^-[:space:];|&][^[:space:];|&]*)'

  # Arm 1 — interpreter `-c` payload. The `-c` cluster need not sit adjacent to
  # the shell word (`sh -x -c`, `bash --norc -c`) and the payload need not sit
  # adjacent to `-c` (`sh -c -- '<payload>'`): each adjacency is ONE spelling of
  # the channel, and requiring either emptied the extraction on all the others.
  local _wv_cpfx="${_wv_sh}([[:space:]]+${_wv_flag})*[[:space:]]+${_wv_cflag}([[:space:]]+${_wv_flag})*[[:space:]]+"
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Strip the matched PREFIX, anchored at the shell word. A greedy `^.*-c `
    # strip cuts at the LAST `-c`-shaped token instead — and `wc -c`, `sort -c`,
    # `grep -c` and `tar -c` inside the payload are ordinary commands, so
    # appending one benign second command disarmed the arm completely.
    _pl=$(printf '%s' "$_m" | sed -E "s#^[^[:alnum:]_]?${_wv_cpfx}##")
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_cpfx}${_wv_arg}" 2>/dev/null || true)"

  # Arm 2 — `eval` payload. The preceding-character class excludes `-` so a long
  # option belonging to another tool (`node --eval`, `perl --eval`) is not read
  # as the shell builtin; those are interpreter payloads, not shell commands.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

  # Arm 3 — a quoted literal piped into a shell. `echo "<program>" | bash`
  # feeds <program> on stdin, so it is neither a `-c` argument nor an `eval`
  # operand, and the guard's quote-scrub blanks it as data. The right-hand side
  # must carry no flag cluster containing `c` (that spelling is arm 1's, and
  # with -c the shell ignores stdin) — expressed as "every following token is
  # provably not a c cluster", NOT as "the shell word ends the pipeline". The
  # latter is a spelling: one trailing `2>/dev/null`, `--`, `-` or `--posix`,
  # the most ordinary things to append to a command, dropped the payload.
  # Only a QUOTED left-hand literal is extractable: a producer that COMPUTES its
  # program (a file read, a network download) carries no literal this scan can
  # read — the download spelling is hooks/security-pattern-check.sh's
  # sec-curl-pipe-sh pattern instead.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Drop from the LAST pipe, so a `|` inside the literal survives.
    _pl=$(printf '%s' "$_m" | sed -E 's/[[:space:]]*[|][^|]*$//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_lit}"'[^|"'\'']*\|[[:space:]]*'"${_wv_sh}"'([[:space:]]+'"${_wv_nonc}"')*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

  # Arm 7 — a herestring fed to a shell (`bash <<< '<payload>'`,
  # `sh -s <<< "<payload>"`). `<<<` feeds the right-hand operand on stdin exactly
  # like arm 3's pipe, but the shell word comes FIRST and the payload follows the
  # operator instead of being piped in from the left — the mirror image of arm 3.
  # Neither arm 1 (no `-c` argument here), arm 3 (no pipe) nor the heredoc scrub
  # (which explicitly excludes `<<<` from heredoc-opener detection, so this text
  # survives it unscrubbed) extracts it.
  local _wv_hspfx="${_wv_sh}([[:space:]]+${_wv_flag})*[[:space:]]*<<<[[:space:]]*"
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E "s#^[^[:alnum:]_]?${_wv_hspfx}##")
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_hspfx}${_wv_arg}" 2>/dev/null || true)"

  # Arm 4 — a heredoc body fed to a shell (`bash <<EOF … EOF`, `cat <<EOF | sh`).
  # This is the mirror image of arm 3: the body is stdin, and every guard's
  # heredoc scrub deletes it BEFORE extraction because a heredoc is data in every
  # other position (`cat > notes.md <<EOF`). So the body is re-derived here from
  # the RAW command, and emitted only when the opener line names a shell as a
  # command word. One body LINE per payload: the guards match per line and per
  # `;`-bounded span, and joining the body would let a single `#` comment line
  # swallow the commands after it. The shell-word matcher reaches awk through the
  # environment, not `-v`, because awk processes escape sequences in a `-v`
  # assignment and would eat the regex's own backslashes.
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw" | GENIRO_WV_SHRE='(^|[|;&][[:space:]]*|[[:space:]])'"${_wv_sh}"'([[:space:]]|$)' awk '
      hd {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == tag) { hd = 0; next }
        if (emit) print line
        next
      }
      match($0, /<<-?[[:space:]]*[\\"'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/[\\"'\'']/, "", tag)
        hd = 1
        emit = ($0 ~ ENVIRON["GENIRO_WV_SHRE"])
        next
      }
    ' 2>/dev/null || true
  fi

  # Arm 5 — a program fed to a shell through process substitution
  # (`bash <(echo "<program>")`, `sh -s < <(printf '<program>')`). The shell reads
  # it from the /dev/fd path the substitution names, so it carries no `-c`, no
  # pipe into the shell and no heredoc — arms 1-4 all miss it. Every quoted
  # literal inside the substitution is a candidate program, the same limit arm 3
  # carries: a substitution that COMPUTES its program leaves nothing to read.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    while IFS= read -r _lit; do
      [ -z "$_lit" ] && continue
      _pl="$_lit"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s' "$_m" | grep -oE "${_wv_lit}" 2>/dev/null || true)"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[^|;&]*[<>]\([^)]*\)' 2>/dev/null || true)"

  # Arm 6 — an interpreter handing a program to a shell. `os.system('<program>')`,
  # `subprocess.run('<program>', shell=True)` and `child_process.execSync(...)`
  # spawn a real shell, but the interpreter is not one, so no arm above sees the
  # call — and the program is not an interpreter FILE op either, so family B below
  # misses it too. That makes any interpreter a laundering channel for every
  # payload the guards block directly. The quoted argument IS the shell command.
  #
  # Gated on an interpreter COMMAND WORD, because the same text is inert without
  # one: `echo "os.system('rm -rf x')" > notes.md` authors a file, it does not
  # shell out, and blocking it would be a false positive on ordinary code
  # authoring. Nothing extractable is lost — a shell-out inside a script FILE
  # carries no literal in the command either way.
  #
  # The left boundary is the same non-word class the shell matcher uses, not a
  # hand-listed set of separators: `(python3 …)` in a subshell and
  # `out=$(python3 …)` in a command substitution disabled this arm and BOTH
  # interpreter families below while the class enumerated `[|;&[:space:]]|/`.
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    # A dot is allowed before the op name because that is how the ops are normally
    # reached (`require('child_process').execSync(…)`); the cost is that a JS
    # `re.exec("s")` also yields its argument, which re-scans as an inert word.
    local _wv_shellout='(os\.(system|popen|execute)|subprocess\.[A-Za-z_]+|Kernel\.system|IO\.popen|Open3\.[a-z_]+|exec(Sync|FileSync)?|spawn(Sync)?|fork|system|popen|shell_exec|passthru|proc_open)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^(]*\([[:space:]]*//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_shellout}"'[[:space:]]*\([[:space:]]*\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Arm 6a-bare — Perl/Ruby's `system`/`exec`/`popen` are BUILTINS as well as
    # functions: `system "rm -rf /"` and `exec "rm -rf /"` run with no call
    # parens at all, so 6a's mandatory `\(` laundered every paren-less spelling.
    # Scoped to this narrow bareword set — not the dotted os.system/subprocess.run
    # forms above, which are never spelled without parens — so an ordinary
    # two-word sentence is not swept in.
    local _wv_bareop='(system|exec|popen)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:space:]]*[[:space:]]+//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_bareop}"'[[:space:]]+\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Perl's qx{}/qx() — a backtick equivalent, the two most common delimiters.
    # Other qx delimiters (qx/…/, qx!…!) are not extracted; the payload must
    # carry no closing }/) of its own for these two to match.
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?qx[{(]//; s/[})]$//')
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])qx\{[^}]*\}|(^|[^[:alnum:]_])qx\([^)]*\)' 2>/dev/null || true)"

    # Arm 6b — the same shell-out written as an ARGV SEQUENCE.
    # `subprocess.run(['sh','-c','<program>'])` and
    # `spawnSync('sh',['-c','<program>'])` reach exactly the same shell, but the
    # program is the element AFTER `-c`, not the call's FIRST argument — so 6a's
    # "the payload is argument one" shape laundered every payload written this
    # way. Keyed on the shell word plus the `-c` element rather than on the call
    # name, so an unlisted spawner cannot hide it either.
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E "s#^.*${_wv_q}${_wv_cflag}${_wv_q}${_wv_nq}*##")
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_q}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|xonsh|nu|elvish|rc)'"${_wv_q}${_wv_nq}"'*'"${_wv_q}${_wv_cflag}${_wv_q}${_wv_nq}"'*'"${_wv_lit}" 2>/dev/null || true)"

    # Ruby's and Perl's backtick literal is the same shell-out with no call
    # syntax at all. Narrowed to those two command words: elsewhere a backtick
    # span is ordinary shell command substitution, already visible to the
    # guards as syntax, and re-extracting it would only add noise.
    if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(ruby|perl)([[:space:]]|$)'; then
      while IFS= read -r _m; do
        [ -z "$_m" ] && continue
        _pl=$(printf '%s' "$_m" | sed -E 's/^`//; s/`$//')
        [ -n "$_pl" ] && printf '%s\n' "$_pl"
      done <<< "$(printf '%s\n' "$cmd" | grep -oE '`[^`]*`' 2>/dev/null || true)"
    fi
  fi

  return 0
}
# GENIRO-VENDORED-END _geniro_extract_inner_payloads
fi
if ! command -v _geniro_wv_resolve >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_resolve
_geniro_wv_resolve() {
  local lit="${1:-}" cmd="${2:-}"
  case "$lit" in
    *'`'*) return 1 ;;
    *'$'*) : ;;
    *) printf '%s' "$lit"; return 0 ;;
  esac
  local candidates="$lit" ref vn vals val val_esc new_candidates cand
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    vn="${ref#\$}"; vn="${vn#\{}"; vn="${vn%\}}"
    vals=$(printf '%s' "$cmd" \
      | grep -oE "(^|[[:space:];&|])${vn}=[^[:space:];&|\"']+" \
      | sed -E 's/^[^=]*=//' | LC_ALL=C sort -u)
    [ -z "$vals" ] && return 1
    # A captured RHS that itself contains `$` or a backtick is an expansion or
    # substitution this scanner cannot evaluate (`F=$OTHER`, `F=$(cmd)`), not a
    # literal — treating its raw text as the resolved value would assert
    # something the running shell never actually wrote to disk. One such
    # binding taints the whole variable: every OTHER literal binding is
    # equally untrustworthy as "the" answer once even one call site could have
    # run with an unevaluable value instead.
    if printf '%s' "$vals" | grep -qE '[$`]'; then
      return 1
    fi
    new_candidates=""
    while IFS= read -r cand; do
      [ -z "$cand" ] && continue
      while IFS= read -r val; do
        [ -z "$val" ] && continue
        # Escape backslash and & before using $val as a sed REPLACEMENT:
        # unescaped, a backslash in the value mangles the substitution (sed
        # reads it as an escape) and an & re-inserts the whole matched text
        # instead of the literal value — either way the target silently
        # comes out wrong. Order matters: double backslashes FIRST, then
        # escape &, so the backslash this step inserts for & is not itself
        # re-doubled.
        val_esc=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/&/\\\&/g')
        new_candidates="${new_candidates}$(printf '%s' "$cand" | sed "s|[\$]{${vn}}|${val_esc}|g; s|[\$]${vn}|${val_esc}|g")"$'\n'
      done <<< "$vals"
    done <<< "$candidates"
    candidates="${new_candidates%$'\n'}"
  done <<< "$(printf '%s' "$lit" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' || true)"
  printf '%s' "$candidates"
  return 0
}
# GENIRO-VENDORED-END _geniro_wv_resolve
fi
if ! command -v _geniro_interp_delete_targets >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_interp_delete_targets
_geniro_interp_delete_targets() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  # Same non-word left boundary as the write roster — see the note there.
  if ! printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    return 0
  fi

  local _q="\\\\?[\"']"
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  # Delete ops across the interpreter families. The fs family is base-keyed with
  # an optional `Sync`, so `fs.rm`, `fs.rmSync` and `fs.promises.rm` all land;
  # every name that collides with an ordinary collection method (`os.remove`,
  # `File.delete`, `Deno.remove`) stays qualified, so a `list.remove` is not read
  # as a file delete. The move/rename family is included because DISPLACEMENT
  # loses a tree from its protected location as completely as deletion does, and
  # its first argument is the source — the same operand position the delete ops
  # use.
  local _ops="(shutil\.rmtree|rmtree|os\.removedirs|os\.remove|os\.unlink|os\.rmdir|Deno\.remove(Sync)?|FileUtils\.rm_rf|FileUtils\.rm_r|FileUtils\.rm|FileUtils\.mv|FileUtils\.move|File\.delete|File\.unlink|File\.rename|Dir\.delete|shutil\.move|os\.rename|os\.replace|(rm|rmdir|unlink|rename)(Sync)?)"
  local unresolved=0 lit resolved

  while IFS= read -r lit; do
    [ -z "$lit" ] && continue
    if resolved=$(_geniro_wv_resolve "$lit" "$cmd"); then
      printf '%s\n' "$resolved"
    else
      unresolved=1
    fi
  done <<< "$(
    {
      printf '%s' "$cmd" \
        | grep -oE "${_ops}\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib: Path('<target>').unlink() / .rmdir() take no argument.
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(unlink|rmdir)" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
    } 2>/dev/null || true
  )"

  if printf '%s' "$cmd" | grep -qE "${_ops}\([[:space:]]*${_nonlit}"; then
    unresolved=1
  fi

  [ "$unresolved" = "1" ] && return 10
  return 0
}
# GENIRO-VENDORED-END _geniro_interp_delete_targets
fi
if ! command -v _geniro_join_quoted_newlines >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_join_quoted_newlines
_geniro_join_quoted_newlines() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  printf '%s\n' "$cmd" | awk '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); q = ""; out = ""; seg = ""; cmt = 0; prev = "\n"
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (cmt) {
          out = out c
          if (c == "\n") cmt = 0
        } else if (q == "") {
          if (c == "#" && index("\n \t;&|(", prev) > 0) { cmt = 1; out = out c }
          else if (c == "\"" || c == "'\''") { q = c; seg = c }
          else { out = out c }
        } else if (c == "\n") {
          seg = seg " "
        } else {
          seg = seg c
          if (c == q) { out = out seg; q = ""; seg = "" }
        }
        prev = c
      }
      if (q != "") { printf "%s", buf } else { printf "%s", out }
    }
  ' 2>/dev/null || printf '%s\n' "$cmd"
}
# GENIRO-VENDORED-END _geniro_join_quoted_newlines
fi
if ! command -v _geniro_wv_expand_assignments >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_expand_assignments
_geniro_wv_expand_assignments() {
  local text="${1:-}"
  [ -z "$text" ] && return 0
  local _sentinel='GENIRO_WV_AMBIGUOUS_VAR'
  local _nonlit=$'\x01NONLIT\x01'
  local _asn _name _val _raw=""
  while IFS= read -r _asn; do
    [ -z "$_asn" ] && continue
    _asn="${_asn#"${_asn%%[A-Za-z_]*}"}"
    _name="${_asn%%=*}"
    _val="${_asn#*=}"
    case "$_val" in
      '"'*'"') _val="${_val#\"}"; _val="${_val%\"}" ;;
      "'"*"'") _val="${_val#\'}"; _val="${_val%\'}" ;;
    esac
    case "$_val" in ''|*'$'*|*'`'*) _val="$_nonlit" ;; esac
    _raw="${_raw}${_name} ${_val}"$'\n'
  done <<< "$(printf '%s\n' "$text" | grep -oE '(^|[;&|(]|[[:space:]])[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'\''[^'\'']*'\''|[^[:space:];&|)]*)' || true)"
  [ -z "$_raw" ] && { printf '%s\n' "$text"; return 0; }

  local _names n _pairs=""
  _names=$(printf '%s' "$_raw" | awk '{print $1}' | LC_ALL=C sort -u)
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    local _distinct _val_out
    _distinct=$(printf '%s' "$_raw" | grep -E "^${n} " | sed -E "s/^${n} //" | LC_ALL=C sort -u)
    if [ "$(printf '%s\n' "$_distinct" | grep -c .)" = "1" ] && [ "$_distinct" != "$_nonlit" ]; then
      _val_out="$_distinct"
    else
      _val_out="$_sentinel"
    fi
    _pairs="${_pairs}${#n} ${n} ${_val_out}"$'\n'
  done <<< "$_names"

  while IFS=' ' read -r _ _name _val; do
    [ -z "${_name:-}" ] && continue
    text="${text//\$\{$_name\}/$_val}"
    text="${text//\$$_name/$_val}"
  done <<< "$(printf '%s' "$_pairs" | sort -rn)"
  printf '%s\n' "$text"
}
# GENIRO-VENDORED-END _geniro_wv_expand_assignments
fi
if ! command -v _geniro_wv_unquote_words >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_unquote_words
_geniro_wv_unquote_words() {
  local text="${1:-}"
  [ -z "$text" ] && return 0
  printf '%s\n' "$text" | sed -E "
    s/\\\$([\"'])/\\1/g
    s/\"([^\"[:space:]]*)\"/\\1/g
    s/'([^'[:space:]]*)'/\\1/g
    s/\\\\([A-Za-z0-9._/-])/\\1/g
  "
}
# GENIRO-VENDORED-END _geniro_wv_unquote_words
fi
if ! command -v _geniro_wv_cd_prefix >/dev/null 2>&1; then
# GENIRO-VENDORED-BEGIN _geniro_wv_cd_prefix
_geniro_wv_cd_prefix() {
  local text="${1:-}" marker="${2:-}"
  [ -z "$text" ] && return 0
  [ -z "$marker" ] && return 0
  local prefix="" _cd_span _cd_tok
  while IFS= read -r _cd_span; do
    [ -z "$_cd_span" ] && continue
    set -f
    # shellcheck disable=SC2086
    for _cd_tok in $_cd_span; do
      _cd_tok="${_cd_tok#\\}"
      while [ "${_cd_tok#\(}" != "$_cd_tok" ]; do _cd_tok="${_cd_tok#\(}"; done
      case "$_cd_tok" in cd|pushd|*/cd|*/pushd|-*|+*) continue ;; esac
      _cd_tok="${_cd_tok#\"}"; _cd_tok="${_cd_tok%\"}"
      _cd_tok="${_cd_tok#\'}"; _cd_tok="${_cd_tok%\'}"
      case "/${_cd_tok%/}/" in
        */"$marker"/*) prefix="${_cd_tok%/}" ;;
      esac
      break
    done
    set +f
  done <<< "$(printf '%s\n' "$text" | grep -oE '(^|[\\|;&(/[:space:]])(cd|pushd)[[:space:]]+[^|;&]*' || true)"
  printf '%s' "$prefix"
  return 0
}
# GENIRO-VENDORED-END _geniro_wv_cd_prefix
fi

# Re-run THIS guard on each extracted payload (unblanked); a block inside
# propagates out. Nested indirection terminates because each payload is
# strictly shorter than the command it came from. Arms 1-3 read the
# heredoc-scrubbed text; arm 4 needs the RAW command, whose heredoc bodies the
# scrub above dropped as data.
_geniro_self="${BASH_SOURCE[0]:-$0}"
INNER_PAYLOADS=$(_geniro_extract_inner_payloads "$SCRUBBED" "$COMMAND")
if [ -n "$INNER_PAYLOADS" ]; then
  while IFS= read -r _pl; do
    [ -z "$_pl" ] && continue
    if ! printf '%s' "$_pl" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$_geniro_self"; then
      exit 2
    fi
  done <<< "$INNER_PAYLOADS"
fi

# Join backslash-newline continuations. Newlines stay INTACT through the quote
# passes below and are collapsed to spaces only afterwards (mirrors
# block-dangerous-git.sh), so multi-line heredocs, line-continued commands, and
# embedded newlines can't slip past whitespace-anchored matchers.
JOINED="${SCRUBBED//\\$'\n'/ }"

# A quoted literal may itself span a newline, and the per-line blanking below
# would then see an unbalanced quote on each half and scan the second half as
# syntax. Join the newlines INSIDE such a span first (lossless: a newline inside
# quotes never separates two commands), leaving every command-separating newline
# for that pass. Contract: lib/write-vectors.sh.
JOINED=$(_geniro_join_quoted_newlines "$JOINED")

# A variable carries its value into the command the shell runs, so a guard
# matching literal tokens misses every operand and every command word that
# arrived through one. Substitute assigned literals back in before matching.
# Contract: lib/write-vectors.sh §F.
JOINED=$(_geniro_wv_expand_assignments "$JOINED")

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
JOINED=$(printf '%s\n' "$JOINED" | sed -E "s/git([[:space:]]+(-C[[:space:]]+${_op}|-c[[:space:]]+${_op}|--git-dir(=${_op}|[[:space:]]+${_op})|--work-tree(=${_op}|[[:space:]]+${_op})|--namespace(=${_op}|[[:space:]]+${_op})|--exec-path(=${_op}|[[:space:]]+${_op})|--config-env(=${_op}|[[:space:]]+${_op})|--attr-source(=${_op}|[[:space:]]+${_op})|-P|--no-pager|-p|--paginate|--no-optional-locks|--literal-pathspecs))+/git/g")

# A BACKSLASH-ESCAPED separator (\| \; \&) is data, never a shell command
# separator: it spells an alternation in a BRE pattern (`grep "a\|b"`) or
# terminates a `find -exec`. Pass B below deliberately refuses to blank a quoted
# span containing ; & | (an unbalanced apostrophe in prose must not pair across a
# real separator and swallow a destructive command between two quotes) — so an
# escaped separator inside a quoted literal left the WHOLE literal unblanked, and
# the per-arg tokenizer then read `grep -c "foo\|rm -rf .geniro/state" f.md` as a
# real subdirectory wipe. Neutralizing the escaped form first can only split
# tokens apart, never hide a command from the matchers.
JOINED=$(printf '%s\n' "$JOINED" | sed -E 's/\\[;&|]/ /g')

# ANSI-C quoting ($'...') and locale quoting ($"...") name the SAME quoted span
# as a plain '...'/"..." — the shell strips the quote marks and (for $'...')
# expands escape sequences, but a $'-prefixed operand still delimits one shell
# word exactly like a bare-quoted one. The unquote pass below strips a quote's
# OUTER marks but never looks at the character immediately before the opening
# quote, so `rm -rf $'.geniro/state'` keeps its `$` glued onto the unquoted
# token (`$.geniro/state`) and the segment-depth gates below never see a real
# `.geniro/...` path. Normalizing `$'`/`$"` to a bare `'`/`"` BEFORE the
# unquote pass makes `rm -rf $'.geniro/state'` read exactly like
# `rm -rf '.geniro/state'`.
#
# A backslash before an ordinary character is dropped by the shell too, so
# `rm -rf \.geniro`, `rm -rf .ge\niro`, `mv \.geniro/... `, `rmdir \.geniro/...`,
# `git add -f \.geniro/...`, `rsync --delete ... \.geniro/...` and
# `git worktree remo\ve` all run exactly like their unescaped spelling while
# every literal matcher below sees a different string. Both spellings, and the
# whitespace-free unquote of Pass A below, are single-sourced in
# lib/write-vectors.sh §E — this call does all three.
JOINED=$(_geniro_wv_unquote_words "$JOINED")

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
# Both passes run per LINE, newlines still intact — collapsing them to spaces
# first made a NEWLINE the one separator the exclusion above could not see, so
# two ordinary prose apostrophes on two comment lines paired straight across the
# delete between them and blanked it.
JOINED=$(printf '%s\n' "$JOINED" | sed -E "s/\"([^\"[:space:]]*)\"/\1/g; s/'([^'[:space:]]*)'/\1/g; s/'[^';&|]*'/ /g; s/\"[^\";&|]*\"/ /g")

# Pad each LINE (leading/trailing space) rather than collapsing newlines into
# spaces: the span matchers below are whitespace-anchored, and every `grep -oE`
# against $PADDED processes its input per line by default (no -z), so a real
# newline between two commands already bounds a span exactly like `;`/`&`/`|`
# do. Collapsing newlines to spaces first destroys that boundary — a `rm -rf
# .geniro/instructions` on one line and an unrelated command on the next then
# read as ONE span, letting a benign second line's content leak into the first
# line's segment-depth check (and, symmetrically, letting a destructive SECOND
# line hide inside a first line's already-decided span). A backslash-newline
# continuation is not affected — it was already joined to one line above.
PADDED=$(printf '%s\n' "$JOINED" | sed -E 's/^/ /; s/$/ /')

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
  # allow_patterns entries name exact pattern IDs. The membership test below is a
  # substring probe over the space-joined list, so a single entry that CARRIES
  # whitespace ("harmless write-env alsoharmless") would silently enable every ID
  # spelled inside it. Reject those at load rather than weaken the probe.
  ALLOWED=$(jq -r '.allow_patterns[]? | select(type == "string" and (test("[[:space:]]") | not))' "$SAFETY_FILE" 2>/dev/null | tr '\n' ' ' || echo "")
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

# Collapse a path to the exact string the shell/filesystem treats as the
# target, before any segment-counting or literal-suffix match runs: repeated
# slashes (`.geniro//x`), a `.` segment (`.geniro/./x`), and a trailing slash
# or run of them (`.geniro/x/`, `.geniro/x//`) all resolve to the SAME path a
# `.geniro/x` spelling does, and every equivalent spelling must decide
# identically or one of them is an open bypass (2026-08-09 audit #3/#4: a `.`
# segment inflated the segment count past the gate, and a residual trailing
# slash after a single strip did the same). Looped to a fixed point so a comb
# of these in one path (`.geniro/./x//./`) fully collapses regardless of
# order — a single pass only shortens a run of 3+ slashes by one. Does NOT
# resolve `..`: check_delete_arg rejects a `..` segment outright below rather
# than resolving it, and folding that in here would silently turn a rejection
# into a resolution.
# Duplicated verbatim in hooks/enforce-state-helper.sh — lib/write-vectors.sh
# is out of scope for this fix (owned by a different maintainer pass), and
# both guards already vendor their own inline fallbacks of lib/ helpers for
# the same reason (a missing lib/ must never make either guard fail open).
# tests/hooks/path-normalize-matrix.sh feeds both guards every spelling above
# and asserts identical exit codes — a one-sided edit fails it.
_geniro_normalize_path() {
  local p="${1:-}"
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  # Collapse `//` and `/./` with prefix/suffix cuts, looped to a fixed point —
  # NOT ${p//pat/repl}: bash 3.2 (macOS /bin/bash) keeps the backslash of an
  # escaped `/` in the replacement, emitting `\/` into the result and silently
  # un-matching every guard pattern downstream (fails OPEN).
  while :; do
    case "$p" in
      *//*)  p="${p%%//*}/${p#*//}" ;;
      */./*) p="${p%%/./*}/${p#*/./}" ;;
      *) break ;;
    esac
  done
  while [ "${p%/.}" != "$p" ]; do p="${p%/.}"; done
  while [ "${p%/}" != "$p" ] && [ -n "${p%/}" ]; do p="${p%/}"; done
  printf '%s' "$p"
}

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
  # file by the extension carve-out below. Checked against the ORIGINAL arg,
  # before normalization strips every trailing slash.
  had_trailing_slash=0
  case "$arg" in */) had_trailing_slash=1 ;; esac

  # Collapse `.` segments and repeated/trailing slashes for segment-counting
  # (see _geniro_normalize_path above).
  stripped="$(_geniro_normalize_path "$arg")"

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
  while :; do case "$norm" in *//*) norm="${norm%%//*}/${norm#*//}" ;; *) break ;; esac; done
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

# A `cd`/`pushd` INTO the guarded tree hides every later delete operand from
# the spans below: `cd .geniro && rm -rf instructions` (or `pushd .geniro && …`)
# spells no `.geniro` path at all, yet loses exactly what
# `rm -rf .geniro/instructions` loses — and changing directory first is the
# most ordinary way an agent removes a subdirectory. Derive that prefix via the
# single-sourced helper (contract: lib/write-vectors.sh's
# `_geniro_wv_cd_prefix`, shared with enforce-state-helper.sh and
# file-protection.sh so the derivation cannot drift between them again);
# check_delete_arg_cd re-prefixes each relative OPERAND with it. The LAST such
# `cd`/`pushd` wins, matching execution order.
CD_PREFIX=$(_geniro_wv_cd_prefix "$PADDED" ".geniro")

# `for <name> in <words>; do rm -rf $<name>; done` binds each WORD to <name>
# across loop iterations — a binding shape `_geniro_wv_expand_assignments`
# (VAR=value) does not cover, since a for-loop assigns a WORD per iteration,
# not one fixed value. An operand reached through such a variable therefore
# reaches check_delete_arg still spelled "$name" (unresolved), evading every
# check above (2026-08-09 audit #8). Deliberately NOT routed through
# lib/write-vectors.sh: that file is out of scope for this fix, and this
# binding shape is local to THIS guard's delete/move/rmdir/rsync operands, not
# a general write-target resolution every guard needs. Scoped to the SAME
# variable name the unresolved operand names, so it only fires when a real
# for-loop binds that exact name — not a broad "any .geniro mention in the
# command" scan, which would false-positive on an unrelated .geniro mention
# sharing the command with an ordinary `rm -f "$SOME_OTHER_VAR"`.
_geniro_for_loop_words() {  # <text> <varname>
  local text="${1:-}" vn="${2:-}"
  [ -z "$text" ] || [ -z "$vn" ] && return 0
  local span
  while IFS= read -r span; do
    [ -z "$span" ] && continue
    printf '%s\n' "$span" | sed -E "s/^[[:space:]]*for[[:space:]]+${vn}[[:space:]]+in[[:space:]]+//"
  done <<< "$(printf '%s\n' "$text" | grep -oE "(^|[;&|(])[[:space:]]*for[[:space:]]+${vn}[[:space:]]+in[[:space:]]+[^;]*" || true)"
}

# Evaluate one operand, then — when a `cd` into the tree preceded it — the same
# operand resolved against that directory. Only a plausible OPERAND is
# re-prefixed: the command word and its flags are not paths, and prefixing them
# would read `rm` itself as `.geniro/rm`, a 2-segment subdirectory delete. An
# operand that already carries a `.geniro` segment needs no help, which is also
# what stops this from recursing.
check_delete_arg_cd() {
  local raw="$1" recursive="$2" cmdword="$3" a vn w
  check_delete_arg "$raw" "$recursive"
  # An operand still carrying an unresolved `$name`/`${name}` reference: check
  # whether that exact name is bound by a `for name in <words>` clause anywhere
  # in the command, and run the SAME depth rules on every word in that list.
  case "$raw" in
    '$'[A-Za-z_]*)
      vn="${raw#\$}"
      case "$vn" in *[!A-Za-z0-9_]*) vn="" ;; esac
      ;;
    '${'*'}')
      vn="${raw#\$\{}"; vn="${vn%\}}"
      case "$vn" in ''|*[!A-Za-z0-9_]*) vn="" ;; esac
      ;;
    *) vn="" ;;
  esac
  if [ -n "$vn" ]; then
    while IFS= read -r w; do
      [ -z "$w" ] && continue
      set -f
      # shellcheck disable=SC2086
      for w in $w; do
        check_delete_arg "$w" "$recursive"
      done
      set +f
    done <<< "$(_geniro_for_loop_words "$PADDED" "$vn")"
  fi
  [ -n "$CD_PREFIX" ] || return 0
  a="${raw#\\}"
  while [ "${a#\(}" != "$a" ]; do a="${a#\(}"; done
  a="${a#\"}"; a="${a%\"}"
  a="${a#\'}"; a="${a%\'}"
  a="${a%)}"
  [ -n "$a" ] || return 0
  case "$a" in
    -*|/*|'~'*|'$'*) return 0 ;;
    "$cmdword"|*/"$cmdword") return 0 ;;
  esac
  case "/$a" in */.geniro/*|*/.geniro) return 0 ;; esac
  check_delete_arg "${CD_PREFIX}/$a" "$recursive"
}

RM_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[\\|;&(/[:space:]])rm[[:space:]]+[^|;&]*' || true)
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
    check_delete_arg_cd "$raw" "$recursive" rm
  done
  set +f
done <<< "$RM_SPANS"

# 2b-mv. Displacement: `mv .geniro /tmp/gone` loses the tree from its protected
#     location exactly as completely as `rm -rf .geniro` does, and none of the rm
#     spans above see a rename. Only the SOURCE operands are evaluated — the
#     destination is where content LANDS, so a `mv <scratch> .geniro/...` that
#     files new content in is not a loss. The last operand is the destination;
#     every earlier non-flag operand is a source and runs the same depth rules as
#     an rm operand, so a 3+-segment task dir keeps its allowance.
MV_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[\\|;&(/[:space:]])mv[[:space:]]+[^|;&]*' || true)
while IFS= read -r MV_SPAN; do
  [ -z "$MV_SPAN" ] && continue
  mv_operands=""
  set -f
  # shellcheck disable=SC2086
  for tok in $MV_SPAN; do
    case "$tok" in mv|*/mv|-*) continue ;; esac
    mv_operands="${mv_operands}${tok} "
  done
  set +f
  mv_operands="${mv_operands% }"
  # Drop the destination (last operand). A single-operand span is not a real mv.
  case "$mv_operands" in
    *" "*) mv_operands="${mv_operands% *}" ;;
    *) mv_operands="" ;;
  esac
  set -f
  # shellcheck disable=SC2086
  for tok in $mv_operands; do
    check_delete_arg_cd "$tok" 1 mv
  done
  set +f
done <<< "$MV_SPANS"

# 2b-rmdir. `rmdir` removes a directory outright — bounded (it only succeeds on
#     an EMPTY directory), but it is the same NODE-loss shape `rm -r` produces
#     at that segment depth, and it carried no matcher of its own. Every operand
#     runs the depth rules at recursive=1: a bare `rmdir .geniro` or
#     `rmdir .geniro/instructions` deletes the directory node itself exactly as
#     `rm -rf` would, so the same whole-tree / subdir gates apply.
RMDIR_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[\\|;&(/[:space:]])rmdir[[:space:]]+[^|;&]*' || true)
while IFS= read -r RMDIR_SPAN; do
  [ -z "$RMDIR_SPAN" ] && continue
  set -f
  # shellcheck disable=SC2086
  for tok in $RMDIR_SPAN; do
    case "$tok" in rmdir|*/rmdir|-*) continue ;; esac
    check_delete_arg_cd "$tok" 1 rmdir
  done
  set +f
done <<< "$RMDIR_SPANS"

# 2c. Interpreter-mediated deletes and displacements: a scripting runtime
#     removing a .geniro path (shutil.rmtree, os.remove, fs.rmSync, File.delete,
#     unlink, …) or moving one away (shutil.move, os.rename, …). None of that is
#     shell syntax, so the rm and mv spans above never see it. The move family's
#     first argument is the source, the same operand position the delete ops use.
#     Each resolved target runs the SAME depth rules as an rm operand, so a
#     per-file delete and a 3+-segment task dir stay allowed. Contract:
#     lib/write-vectors.sh, sourced with the shell-indirection extractor above.
_id_unresolved=0
_id_targets=$(_geniro_interp_delete_targets "$COMMAND") || _id_unresolved=1
if [ -n "$_id_targets" ] || [ "$_id_unresolved" = "1" ]; then
  # Tree-removing ops (rmtree, rm_rf, rmSync/rm with recursive) delete a whole
  # directory; the per-file ops do not, and get the same treatment as `rm -f`.
  # A move relocates whatever it names, directory included, so it counts as
  # recursive too — otherwise the non-recursive path skips every non-glob arg
  # and `shutil.move('.geniro', …)` walks straight through.
  _id_recursive=0
  if printf '%s' "$COMMAND" | grep -qE 'rmtree|rm_rf|rm_r\(|removedirs|recursive|shutil\.move|os\.rename|os\.replace|File\.rename|FileUtils\.(mv|move)|Deno\.remove(Sync)?|(rm|rmdir|rename)(Sync)?\('; then
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

# Does a find -path/-name/-ipath/-iname GLOB ARGUMENT cover .geniro without
# spelling it literally (`find . -path '*geniro*' -delete`, 2026-08-09 audit
# #9)? find matches -name/-iname against the found entry's BASENAME and
# -path/-ipath against its full traversed PATH, so a bare ".geniro" probes the
# -name shape and a path with a leading segment probes -path; bash's own
# case/glob engine — the SAME engine a real shell filename expansion would
# use — decides both, so no separate fnmatch reimplementation is needed.
find_glob_covers_geniro() {
  local pattern="$1"
  case ".geniro" in $pattern) return 0 ;; esac
  case "./.geniro" in $pattern) return 0 ;; esac
  case "a/.geniro/b" in $pattern) return 0 ;; esac
  return 1
}

# A find SPAN "targets" .geniro either by spelling it literally anywhere in the
# span (the existing check) or via a -path/-name/-ipath/-iname glob argument
# that covers it (this is check_delete_arg's own prefix-glob probe, applied to
# find's ARGUMENT STRING instead of a shell-expanded token). Quotes around the
# glob argument are already stripped by the JOINED pipeline's unquote pass
# before $PADDED is built, so a token here is bare either way.
find_span_targets_geniro() {
  local span="$1" tok take=0 pat
  case "$span" in *.geniro*) return 0 ;; esac
  set -f
  # shellcheck disable=SC2086
  for tok in $span; do
    if [ "$take" = "1" ]; then
      take=0
      pat="${tok#\"}"; pat="${pat%\"}"
      pat="${pat#\'}"; pat="${pat%\'}"
      if find_glob_covers_geniro "$pat"; then set +f; return 0; fi
      continue
    fi
    case "$tok" in -path|-name|-ipath|-iname) take=1 ;; esac
  done
  set +f
  return 1
}

# 3. find ... .geniro ... -delete / -exec rm / piped to xargs rm — bulk deletion
#    that walks the tree. All three spellings produce the same loss.
if ! is_allowed "find-geniro-delete"; then
  FIND_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[\\|;&(/[:space:]])find[[:space:]]+[^|;&]*' || true)
  while IFS= read -r FIND_SPAN; do
    [ -z "$FIND_SPAN" ] && continue
    find_span_targets_geniro "$FIND_SPAN" || continue
    if echo "$FIND_SPAN" | grep -qE -- '-delete'; then
      block "find-geniro-delete" "find ... -delete on .geniro/ wipes user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path, or pathlib.Path.unlink in Python) so each deletion is auditable."
    fi
    # The executed command is any of the loss family, not `rm` alone: `-exec mv` is
    # the displacement this guard's mv span already blocks directly,
    # unlink/shred/truncate destroy each matched file exactly as `rm` does, and
    # `rmdir` removes each matched (empty) directory node the same way.
    if echo "$FIND_SPAN" | grep -qE -- '-exec(dir)?[[:space:]]+([^[:space:]]*/)?(rm|unlink|shred|truncate|mv|rmdir)([[:space:]]|$)'; then
      block "find-geniro-delete" "find ... -exec rm/mv/unlink/shred/truncate/rmdir on .geniro/ wipes or displaces user-authored content in bulk. Iterate file-by-file (\`rm -f\` per path) so each deletion is auditable."
    fi
  done <<< "$FIND_SPANS"
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
RSYNC_SPANS=$(printf '%s' "$PADDED" | grep -oE '(^|[\\|;&(/[:space:]])rsync[[:space:]]+[^|;&]*' || true)
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
  [ -n "$rsync_dest" ] && check_delete_arg_cd "$rsync_dest" 1 rsync
done <<< "$RSYNC_SPANS"

# 4. git worktree remove  (worktrees commonly contain .geniro/ state not routed
#    through ${PRIMARY_ROOT} — removal silently destroys it).
#
# The guard LOOKS before it blocks. It used to fire on the command shape alone,
# telling the caller to "verify the worktree's .geniro/ is empty" — a
# precondition the caller could satisfy but the guard could not observe, so
# verifying changed nothing and the block stood. Measured across 1,408 sessions
# (2026-08-13) that shape produced no compliance at all: in every trace the run
# confirmed the worktree held nothing worth keeping and then either handed the
# removal back to the user by hand or abandoned it, because the only remaining
# exit was a permanent safety.json grant that a second guard exists to prevent.
#
# So: resolve the target, and block only when it really holds .geniro/ content
# git would not preserve — untracked or ignored files. A worktree with no
# .geniro/, or one whose .geniro/ is entirely tracked (the content survives in
# the branch), is nothing to lose and is allowed through.
#
# Unresolvable target → block, unchanged. A path built from a variable or a
# command substitution cannot be inspected, and this is a data-loss guard: the
# fail-closed direction is the one that keeps state.
if ! is_allowed "worktree-remove-with-state"; then
  if echo "$PADDED" | grep -qE 'git[[:space:]]+worktree[[:space:]]+remove[[:space:]]'; then
    _wt_span=$(printf '%s' "$PADDED" | grep -oE 'git[[:space:]]+worktree[[:space:]]+remove[^;&|]*' | head -1 || true)
    _wt_target=""
    set -f
    # shellcheck disable=SC2086
    for _wt_tok in ${_wt_span#*remove}; do
      case "$_wt_tok" in
        -*) continue ;;
        *) _wt_target="$_wt_tok"; break ;;
      esac
    done
    set +f

    _wt_verdict="block"
    _wt_detail="the worktree path could not be resolved from the command"
    # A relative target is relative to where the command will RUN, not to where
    # the hook runs. Resolve it against a leading `cd`/`pushd` when the command
    # carries one — the common shape is `cd <abs> && git worktree remove
    # <relative>`, and reading the relative path against the hook's own cwd
    # would look at the wrong directory (or at nothing) and decide from that.
    # A `cd` we cannot resolve leaves the target unresolvable, hence fail-closed.
    _wt_base=""
    _wt_cd=$(printf '%s' "$PADDED" | grep -oE '(^|[;&|(])[[:space:]]*(cd|pushd)[[:space:]]+[^;&|]+' | tail -1 || true)
    if [ -n "$_wt_cd" ]; then
      set -f
      # shellcheck disable=SC2086
      for _wt_tok in ${_wt_cd}; do
        case "$_wt_tok" in cd|pushd|*/cd|*/pushd|-*|+*|';'|'&&'|'||') continue ;; esac
        _wt_tok="${_wt_tok#\"}"; _wt_tok="${_wt_tok%\"}"
        _wt_tok="${_wt_tok#\'}"; _wt_tok="${_wt_tok%\'}"
        _wt_base="$_wt_tok"; break
      done
      set +f
    fi
    # _wt_anchored=1 means the resolved path is the one the command will act on,
    # so "not found" genuinely means "nothing there". Without an anchor a
    # missing directory only means it is missing from HERE.
    _wt_anchored=0
    case "$_wt_target" in
      /*) _wt_anchored=1 ;;                      # absolute — use as given
      *)
        case "$_wt_base" in
          '')  : ;;                              # no cd — hook cwd is a guess
          /*)  _wt_target="${_wt_base%/}/$_wt_target"; _wt_anchored=1 ;;
          *)   _wt_target='?unresolvable' ;;     # cd to a relative/variable dir
        esac ;;
    esac
    case "$_wt_target" in
      ''|*'$'*|*'`'*|*'*'*|*'?'*)
        : ;;  # empty, variable, substitution or glob — leave fail-closed
      *)
        if [ ! -d "$_wt_target" ]; then
          # Absent, and we know we looked in the right place.
          [ "$_wt_anchored" = "1" ] && _wt_verdict="allow"
          [ "$_wt_anchored" = "1" ] || _wt_detail="the target is relative and no leading cd anchors it, so its contents could not be checked"
        elif [ ! -d "$_wt_target/.geniro" ]; then
          _wt_verdict="allow"
        else
          # Untracked + ignored files under .geniro/ are the ones `git worktree
          # remove` destroys for good. `|| true` because git exits non-zero when
          # the directory is not a worktree at all, which is not a verdict.
          # --untracked-files=all so the listing names the actual files rather
          # than collapsing to `?? .geniro/` — the caller has to decide what is
          # worth routing, and a directory name does not tell them.
          _wt_at_risk=$(git -C "$_wt_target" status --porcelain --ignored --untracked-files=all -- .geniro 2>/dev/null | head -20 || true)
          if [ -z "$_wt_at_risk" ]; then
            _wt_verdict="allow"
          else
            _wt_detail="its .geniro/ holds untracked or ignored files that removal destroys for good:
$_wt_at_risk"
          fi
        fi
        ;;
    esac

    if [ "$_wt_verdict" = "block" ]; then
      block "worktree-remove-with-state" "git worktree remove destroys the gitignored .geniro/ in the worktree, and $_wt_detail.
Route the state first — copy what is worth keeping to the primary worktree (_shared/primary-worktree.md), or delete it — then re-run the removal; this guard re-checks and lets a clean worktree through."
    fi
  fi
fi

# 5. git add -f / --force on .geniro/ paths. Force-adding ignored files makes them
#    appear in the IDE's Source Control panel — and IDE "Discard All Changes" then
#    becomes a one-click data-loss vector (real incident: Cursor SCM discard wiped
#    .geniro/actions/*.md after they were force-added). The correct path for files
#    that should be tracked is to negate them in .gitignore (e.g. !.geniro/actions/),
#    not to bypass the ignore via -f.
if ! is_allowed "git-add-force-geniro"; then
  # `git add` invocation with -f or --force present, AND a .geniro/ path
  # argument. `git update-index --add --force` is the plumbing equivalent —
  # same ignored-file-becomes-tracked data-loss vector, different porcelain —
  # so the subcommand alternation covers both. Both the flag check and the
  # path probe run against the SAME extracted `git add`/`git update-index`
  # span (bounded to the next &/;/| separator), not the whole padded command —
  # otherwise a `.geniro` mention ANYWHERE else in the command (an unrelated
  # commit message, a later command) satisfies the path probe on its own, and
  # force-adding a path that has nothing to do with .geniro/ blocks.
  ADD_SPANS=$(printf '%s' "$PADDED" | grep -oE 'git[[:space:]]+(add|update-index)[[:space:]]+[^|;&]*' || true)
  while IFS= read -r ADD_SPAN; do
    [ -z "$ADD_SPAN" ] && continue
    if echo "$ADD_SPAN" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'; then
      if echo "$ADD_SPAN" | grep -qE '(/|[[:space:]"'"'"'])\.geniro(/|[[:space:]"'"'"';|&])'; then
        block "git-add-force-geniro" "git add -f (or the git update-index --add --force plumbing equivalent) on .geniro/ paths makes ignored files appear in the IDE's Source Control panel — one click of 'Discard All Changes' then deletes them. To track .geniro/ subdirs, negate them in .gitignore instead (e.g. \`!.geniro/actions/\` and \`!.geniro/actions/**\`)."
      fi
    fi
  done <<< "$ADD_SPANS"
fi

exit 0
