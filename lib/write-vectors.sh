#!/usr/bin/env bash
# Single source of truth for the write/delete vectors a Bash-side guard cannot
# see by matching shell syntax alone.
#
# Four families live here:
#   A. `_geniro_extract_inner_payloads` — shell indirection (`sh -c`, `eval`, a
#      pipe, a heredoc, a process substitution, an interpreter shelling out).
#   B. `_geniro_interp_write_targets` / `_geniro_interp_delete_targets` —
#      interpreter-mediated file writes and deletes.
#   C. `_geniro_join_quoted_newlines` — a quoted literal spanning a newline,
#      which every line-oriented pass in a guard reads as two unbalanced lines.
#   D. `_geniro_wv_cd_prefix` — a `cd`/`pushd` into a guarded tree, which hides
#      every later relative operand from a caller's own path matchers.
#
# Every recognizer here is STRUCTURAL, not enumerative. A shell is reached by
# more spellings than a bare word — `/bin/sh` names it by path, `"sh"` quotes it,
# and `sudo` / `nohup` / `timeout 5` / `env FOO=bar` prefix it with a wrapper that
# changes only the process environment — and each spelling runs the same program,
# so ONE shell-word matcher serves every arm below. The interpreter roster and the
# write/delete op lists follow the same rule: ops are keyed on BASE names, so
# `*Sync`, a `promises.` prefix and the async variants fall out without being
# enumerated. A recognizer that models a fixed spelling is a channel, not a guard.
#
# A shell can be handed a program seven ways, and only one of them is shell
# syntax the guards can match directly. `sh -c "<payload>"` and `eval
# "<payload>"` pass it as an ARGUMENT; `echo "<payload>" | bash`,
# `bash <<EOF … EOF`, `bash <(echo "<payload>")` and `bash <<< "<payload>"`
# pass it on STDIN; `os.system('<payload>')` hands it to a shell from inside an
# interpreter. In every case the guards' own passes destroy it before matching —
# quoted literals are blanked as data, heredoc bodies are dropped as data — so
# without this extraction the payload is inert text and the guard never inspects
# the command that actually runs. Each guard calls this BEFORE its own
# quote-blanking pass, then re-runs ITSELF on every returned payload; a block
# inside propagates out. Recursion terminates because a payload is always
# strictly shorter than the command it came from.
#
# Seven shapes are extracted:
#   1. the sh|bash|zsh|dash|ksh|ash|fish|csh|tcsh|xonsh|nu|elvish|rc `-c` family
#      — any flag cluster containing c (-c, -lc, -euc), payload double-quoted,
#      single-quoted, or bare;
#   2. `eval` followed by a quoted or bare payload;
#   3. a quoted literal piped into a shell (`echo "<payload>" | bash`,
#      `printf '<payload>' | nohup sh`) — stdin, so arms 1 and 2 never see it;
#   4. a heredoc body whose opener line invokes a shell (`bash <<EOF`,
#      `cat <<EOF | sh`) — also stdin, and the guards' heredoc scrub would
#      otherwise drop it as data. Emitted one body LINE per payload, which is
#      what the guards' line- and span-oriented matchers consume;
#   5. a quoted literal inside a process substitution a shell reads
#      (`bash <(echo "<payload>")`) — a fifth stdin channel with no `-c`, no
#      pipe and no heredoc;
#   6. the quoted argument of an interpreter's shell-out call (`os.system`,
#      `subprocess.run(…, shell=True)`, `child_process.exec*`, a Ruby backtick),
#      which is neither shell syntax nor an interpreter FILE op, so both
#      families here would otherwise miss it entirely;
#   7. a herestring fed to a shell (`bash <<< "<payload>"`, `sh -s <<< '<payload>'`)
#      — a sixth stdin channel, the mirror image of arm 3: the shell word comes
#      FIRST and the payload follows the `<<<` operator rather than being piped
#      in from the left, so neither arm 1 (no `-c`), arm 3 (no pipe) nor the
#      heredoc scrub (`<<<` is deliberately excluded from heredoc detection) sees it.
#
# Usage:
#   source "$_script_dir/write-vectors.sh"
#   payloads="$(_geniro_extract_inner_payloads "$SCRUBBED" "$COMMAND")"
#
# $1 is the heredoc-scrubbed command (arms 1-3, 5 and 6 read it, so a `sh -c`
# MENTIONED inside a heredoc body destined for a file stays data). $2 is the RAW
# command, bodies intact — arm 4 needs them, and it re-derives which heredocs are
# fed to a shell rather than trusting the scrub. Omit $2 to run every arm but 4.
#
# Prints one payload per line, with one layer of surrounding quotes stripped;
# empty output when the command carries no indirection.
#
# Hooks source this with an inline fallback so a vendored install shipping
# hooks/ without lib/ still recurses — a missing helper must never make a guard
# fail open. See hooks/enforce-tdd-order.sh for the sourcing pattern. Every
# fallback is a VERBATIM copy of the function it stands in for (delimited by
# `GENIRO-VENDORED-BEGIN/END` markers); a one-sided edit here reopens the hole
# on vendored installs.

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

# ---------------------------------------------------------------------------
# A quoted literal may span a newline:
#
#   echo "first line
#   second line" > notes.md
#
# Every guard's quote-blanking pass and every echo/printf content scan is LINE
# oriented, so each physical line carries an UNBALANCED quote: the blanking pass
# leaves the second line's text as bare syntax (a false block on a command that
# merely mentions a protected path), and the content scan never pairs the payload
# with the redirect target on the opener line (a false negative). A newline INSIDE
# a quoted span never separates two commands — only an unquoted one does — so
# joining exactly those newlines is lossless for both passes.
#
# Prints the command with every newline inside a BALANCED quoted span replaced by
# a space, every other newline intact. Input with no such span is echoed byte for
# byte. An UNTERMINATED quote also echoes the input unchanged: joining from a
# stray apostrophe (`# don't clobber`) to end-of-input would swallow the next
# line's redirect, and a guard must never fail open to fix a false positive.
#
# A COMMENT is skipped rather than scanned, because the unterminated-quote guard
# above only covers a stray apostrophe with nothing after it. TWO prose
# apostrophes in two comments are individually stray but jointly balanced, so
# without this the scan paired `# don't` with a later `# won't`, folded every
# line between them into one "quoted span", and the caller's next pass blanked
# the real command sitting there. A `#` opening a word is a comment to the end of
# its line in the shell too, so nothing inside one can open a quoted operand.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# A `cd` or `pushd` INTO a guarded tree hides every later relative operand
# from a caller's own path-shaped matchers: `cd .geniro && rm -rf instructions`
# (or `pushd .geniro && …`) spells no `.geniro` path in the command that
# follows at all, yet resolves to exactly the same target
# `rm -rf .geniro/instructions` would. `pushd` reaches the identical
# directory-change builtin `cd` does — it changes the working directory and
# pushes the old one onto a stack — so a matcher keyed on the literal word
# `cd` alone lets `pushd` walk straight through.
#
# _geniro_wv_cd_prefix <text> <marker>
#
# Scans <text> for the LAST `cd`/`pushd` invocation whose target contains
# <marker> (a literal substring like ".geniro" or ".git", matched between
# slashes so a prefix collision — e.g. a directory named `.geniroX`, or a repo
# named `.gitignore-tools` — does not count), and prints that target with any
# trailing slash stripped. Empty stdout when no such invocation is found. The
# LAST one wins, matching shell execution order — a later `cd`/`pushd`
# overrides an earlier one for every operand that follows it.
#
# <text> must already be split so each `cd`/`pushd` invocation's own operand
# span cannot run past the boundary of an unrelated line or command — this
# function relies on `grep` matching per LINE (its default, unset by any `-z`),
# so the caller's own separator/newline handling is what keeps that honest,
# not this function.
#
# `pushd`'s own flags (`-n`) and stack-index operands (`+2`, `-1`) fall out of
# the same leading-`-`-or-`+`-or-flag skip `cd`'s flags do; `(cd .geniro; …)`
# subshell wrapping and a `\cd`/`\pushd` escape are unwrapped before matching.
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

# ---------------------------------------------------------------------------
# Interpreter-mediated writes and deletes.
#
# A guard's shell-syntax vectors (redirection, tee, sed -i, cp/mv, rm) read a
# command whose heredoc bodies and quoted literals were blanked as data. An
# interpreter's file op is never shell syntax in any position, so
# `python3 -c "open('.env','w').write(k)"` and
# `awk 'BEGIN{print k > ".env"}'` reach the filesystem completely unchecked.
# These two functions scan the RAW command for that channel.
#
# The op lists are keyed on BASE names (`writeFile`, `rm`, `copyFile`) with an
# optional `Sync` suffix, and the extraction drops everything left of the opening
# paren — so `fs.writeFile`, `fs.writeFileSync`, `fs.promises.rm` and
# `Deno.writeTextFileSync` are all covered without enumerating a spelling each.
# Names that collide with an ordinary collection method (`os.remove` vs
# `list.remove`, `File.delete`) stay qualified.
#
# Both fire only on the conjunction interpreter + write/delete op + target, so a
# read-only interpreter call (`node -e "console.log(x)"`, `awk '{print $1}' f`)
# yields nothing and stays allowed. The caller supplies the third conjunct: it
# runs its OWN path predicate over the returned targets, so a write to a path the
# caller does not protect costs nothing.
#
# Contract (both functions):
#   stdout — one resolved literal target per line (possibly empty).
#   rc 0   — no interpreter/op conjunction, or every target resolved to a literal.
#   rc 10  — at least one target is a variable or expression this scan cannot
#            resolve. The caller decides what to do with an unknown target;
#            scanning the command for its own distinctive path shape (as
#            hooks/enforce-state-helper.sh does for `.geniro/...`) is the pattern.
#
# Callers run under `set -e`, so capture with `|| unresolved=1`:
#   targets=$(_geniro_interp_write_targets "$COMMAND") || unresolved=1
# ---------------------------------------------------------------------------

# Resolve shell expansions inside an extracted literal against an assignment in
# the SAME command — the shape that writes a computed path
# (`F=.env; python3 -c "open('$F','w')…"`). Prints one resolved candidate per
# line; returns 1 when a referenced variable has no visible assignment at all
# (target unknown).
#
# ALL-OR-NOTHING per variable, not last-binding-wins: the raw command text can
# carry a `$VAR` reference at MORE THAN ONE write/delete call site (two `open`
# calls either side of a reassignment), and this function is handed one
# extracted literal at a time with no notion of WHERE in `cmd` that literal
# sits — it cannot tell which assignment was live at ITS particular call site.
# Picking only the last assignment in the text (the previous `tail -1`)
# resolves every call site to the SAME single value, so a call site that ran
# with an EARLIER, still-live binding is silently cleared while the resolver
# reports a decoy — a bypass, not a false positive. Resolving every literal
# binding as its own candidate costs nothing here (the caller just checks
# more strings), so each is emitted on its own line — the same move
# `_geniro_wv_resolve_pathlib_var` makes for a python variable one layer up.
#
# A variable is forced unresolved (return 1) the moment ANY of its bindings is
# not a plain literal — `F=$(cmd)`, `F=` (empty), `F=$OTHER` — since a value
# built from an expansion this scanner cannot evaluate makes every OTHER
# literal binding equally untrustworthy as "the" answer; asserting a superset
# built from only the literal-looking bindings would still assert a possibly-
# wrong answer instead of deferring to the caller's conservative fallback.
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

# Resolve a pathlib target bound by an interpreter-level VARIABLE rather than
# spelled adjacent to the write call — the shape
#   p = pathlib.Path(".geniro/planning/x/state.md")
#   ...
#   p.write_text(s)
# The literal sits on the assignment line, not next to `.write_text`, so the
# adjacency match `Path("<lit>").write_text(` in the caller never sees it. This
# is the same "follow the binding" move `_geniro_wv_resolve` makes for a shell
# `$VAR` inside a literal, one level down inside the interpreter body: a target
# that resolves through assignment must resolve here too, or the caller falls
# back to treating every path-shaped token in the WHOLE command as a candidate
# — which is what turned prose mentioning "binding.key" into a blocked write.
#
# ALL-OR-NOTHING per identifier, not last-binding-wins: a script can rebind
# <ident> after the literal binding (`p = Path("<protected>"); ... p =
# Path("x")`), and picking only the last assignment resolves to the wrong
# single target while the real one never becomes a candidate — a bypass, not
# a false positive. Resolving to a SUPERSET of candidates costs nothing here
# (the caller just checks more paths), so every literal binding of <ident> is
# emitted, one per line, whenever <ident>'s assignments are ALL literal. The
# moment <ident> carries even one assignment whose right-hand side is not a
# recognized literal shape — `p = Path(os.environ["X"])`, `p = secret` — the
# runtime value at the write site is unknowable from any literal we did find,
# so resolution fails outright (return 1) and the caller's unresolved/fallback
# path takes over instead of asserting a possibly-wrong single answer.
#
# Three equivalent binding spellings count as literal: `p = pathlib.Path("<lit>")`,
# `p = Path("<lit>")`, `p = "<lit>"`. The assignment must open a statement —
# start of command, or right after `;`, `&`, `|`, or whitespace — never inside
# a call's argument list, so a keyword argument (`log(p="<lit>")`) can never
# masquerade as a binding of <ident>.
_geniro_wv_resolve_pathlib_var() {
  local ident="${1:-}" cmd="${2:-}"
  [ -z "$ident" ] && return 1
  local _q="\\\\?[\"']"
  # The boundary a real assignment can open a statement after: command start,
  # whitespace/`;`/`&`/`|`, or the quote a shell wraps an interpreter's `-c`
  # payload in — the FIRST statement of `-c "p=...` sits right after that
  # quote, not after any whitespace. `(` and `,` are deliberately excluded so a
  # call's keyword argument never opens a "statement" here.
  local _bound='(^|[[:space:];&|\"'"'"'])'
  # An augmented assignment (`p /= x`, `p += x`) rebinds <ident> in a way the
  # `=` scan below cannot see at all (`/=` never matches a bare `=`), and it
  # can appear AFTER a perfectly literal binding — `p = Path('lit'); p /= x`
  # still ends with p pointing at the augmented result, not the literal.
  # Forced unresolved unconditionally, wherever the operator appears relative
  # to any binding: a literal binding earlier in the command proves nothing
  # about what <ident> holds by the time it reaches a write call.
  local _augop='(\*\*|\/\/|>>|<<|\/|\+|-|\*|%|&|\||\^)='
  if printf '%s' "$cmd" | grep -qE "${_bound}${ident}[[:space:]]*${_augop}"; then
    return 1
  fi
  local rhs_list rhs lit lits="" nonlit=0 found=0
  rhs_list=$(printf '%s' "$cmd" \
    | grep -oE "${_bound}${ident}[[:space:]]*=[[:space:]]*[^;&|]+" \
    | sed -E "s/^.*${ident}[[:space:]]*=[[:space:]]*//")
  [ -z "$rhs_list" ] && return 1
  # A binding counts as literal only when the RHS is EXACTLY a path literal,
  # tail-anchored — `Path("lit") / x`, `.joinpath(...)`, `.with_name(...)`,
  # `.with_suffix(...)`, `.parent`, a ternary, string concatenation and a
  # trailing backslash line continuation all leave text after the literal, so
  # none of them can match this and all fall through to `nonlit`, which forces
  # the caller's conservative fallback instead of asserting a wrong single
  # answer. `.resolve()`, `.absolute()` and `.expanduser()` are the sole
  # exception carved out of the tail: each narrows or normalizes the SAME
  # path rather than computing a new one, and without the carve-out
  # `p = Path('notes/out.md').resolve()` regresses to the false positive this
  # resolver exists to fix.
  local _tail='([[:space:]]*(\.(resolve|absolute|expanduser)\(\))*[[:space:]]*)'
  while IFS= read -r rhs; do
    [ -z "$rhs" ] && continue
    found=1
    rhs=$(printf '%s' "$rhs" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
    lit=""
    if printf '%s' "$rhs" | grep -qE "^(pathlib\.)?Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)${_tail}\$"; then
      lit=$(printf '%s' "$rhs" \
        | grep -oE "^(pathlib\.)?Path\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^(pathlib\.)?Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"']\$//")
    elif printf '%s' "$rhs" | grep -qE "^${_q}[^\\\\\"']+${_q}\$"; then
      # Bare string binding: `p = "<lit>"` with no Path() wrapper — still a
      # literal-valued variable a later `.write_text`/`.open` call can carry.
      lit=$(printf '%s' "$rhs" \
        | grep -oE "^${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^\\\\?[\"']//; s/\\\\?[\"']\$//")
    fi
    if [ -n "$lit" ]; then
      lits="${lits}${lit}"$'\n'
    else
      nonlit=1
    fi
  done <<< "$rhs_list"
  [ "$found" = "0" ] && return 1
  [ "$nonlit" = "1" ] && return 1
  printf '%s' "$lits"
  return 0
}

# Path-shaped tokens of a command — the fallback candidate set for a caller whose
# protected paths are distinctive filenames and which therefore loses nothing by
# checking every plausible path in an rc-10 command. A token qualifies by holding
# a `/` or ending in a short extension, which keeps interpreter method chains
# (`.writeFileSync`) and bare words (`open`, `w`) out of the set.
_geniro_wv_path_tokens() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  local tokre='[^[:space:]"'\''`=(),;|&<>{}]+'
  printf '%s' "$cmd" | grep -oE "$tokre" 2>/dev/null \
    | grep -E '/|\.[A-Za-z0-9]{1,6}$' 2>/dev/null \
    | grep -vE '^-' 2>/dev/null || true
  return 0
}

_geniro_interp_write_targets() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  # Runtime roster. bun and tsx implement node:fs verbatim and deno ships its own
  # Deno.* file API, so a roster frozen at the 2019 set lets one word bypass the
  # whole channel. The left boundary is the same non-word class the shell matcher
  # uses: enumerating separators omitted `(` and backtick, so a subshell or a
  # command substitution around the interpreter disabled this whole family.
  if ! printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript|awk|gawk|mawk)([[:space:]]|$)'; then
    return 0
  fi

  # Quote class tolerating a shell backslash-escape (`open(\"x\", \"w\")` is how a
  # double-quoted -c argument reaches a guard).
  local _q="\\\\?[\"']"
  # A non-literal target: a bare identifier or an escaped variable
  # (`fopen(\$f, "w")`), i.e. anything that is not the opening quote of a literal.
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  # Ops whose FIRST argument is the target and which write unconditionally.
  # Base-keyed: `writeFile` covers fs.writeFile/writeFileSync/promises.writeFile,
  # `writeTextFile` covers Deno.writeTextFile(Sync), `truncate`/`ftruncate` cover
  # os.truncate/os.ftruncate and fs.truncate(Sync)/fs.ftruncate(Sync) — a
  # truncation is a write (it replaces the file's content with zero-or-fewer
  # bytes) exactly like `truncate -s 0 FILE` on the shell side.
  local _wops_first='((writeFile|appendFile|createWriteStream|outputFile|writeTextFile|truncate|ftruncate)(Sync)?|file_put_contents|File\.write|IO\.write)'
  # Copy/rename: the SECOND argument is the target. This is the interpreter
  # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in every
  # calling guard already treats as a write — without it the same clobber walks
  # past that guard just by being written in Python or Node.
  local _wops_second='(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|File\.rename|FileUtils\.(cp|mv|copy|move)|(copyFile|rename|cp)(Sync)?)'
  local unresolved=0 has_awk=0 lit resolved
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])(awk|gawk|mawk)([[:space:]]|$)'; then
    has_awk=1
  fi

  # --- targets named by a quoted literal ---
  while IFS= read -r lit; do
    [ -z "$lit" ] && continue
    if resolved=$(_geniro_wv_resolve "$lit" "$cmd"); then
      printf '%s\n' "$resolved"
    else
      unresolved=1
    fi
  done <<< "$(
    {
      # open()/fopen()/File.open() count only with a write mode in the second
      # argument — `open('<path>')` is a read and must stay allowed. The Lua
      # io.open('<path>','w') spelling is the same shape and matches on the name.
      printf '%s' "$cmd" \
        | grep -oE "(open|fopen|File\.open)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[waxWAX>]" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # The 3-argument perl open puts the mode second and the path third
      # (`open(FH, ">", "path")`).
      printf '%s' "$cmd" \
        | grep -oE "open\([^,)]*,[[:space:]]*${_q}[>+]{1,2}${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      printf '%s' "$cmd" \
        | grep -oE "${_wops_first}\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib: the target is the Path(...) argument, not the write_text body.
      # `.open(...)` only counts with a write mode — `Path('x').open()` with no
      # args defaults to read, same as the builtin open()/fopen() gate above;
      # without this `p.open().read()` reads as a write and blocks a plain read.
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch)|Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.open\([^)]*${_q}[waxWAX>]" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib bound through a variable: `p = pathlib.Path("<lit>")` on an
      # earlier line, then `p.write_text(...)` / `.write_bytes(...)` /
      # `.touch()` / `.open(...)` later — the adjacency match just above only
      # reaches a literal spelled next to the write call, not one bound one
      # line up. Each bare identifier immediately before the write op is
      # looked up via `_geniro_wv_resolve_pathlib_var`; an identifier with no
      # visible binding prints nothing here and is caught by the unresolved
      # check below instead. Same write-mode gate on `.open(...)` as the
      # adjacent form above.
      while IFS= read -r _wv_pvar; do
        [ -z "$_wv_pvar" ] && continue
        _geniro_wv_resolve_pathlib_var "$_wv_pvar" "$cmd" 2>/dev/null || true
        printf '\n'
      done <<< "$(printf '%s' "$cmd" \
        | grep -oE "[A-Za-z_][A-Za-z0-9_]*\.(write_text|write_bytes|touch)\(|[A-Za-z_][A-Za-z0-9_]*\.open\([^)]*${_q}[waxWAX>]" \
        | sed -E "s/\.(write_text|write_bytes|touch)\(\$//; s/\.open\(.*\$//" \
        | sort -u)"
      # (Every comment in this $( ) body keeps its apostrophes and parentheses
      # balanced on purpose: bash 3.2 does not skip comments while scanning the
      # body, so an odd one reads as an unterminated quote or an unclosed group.)
      printf '%s' "$cmd" \
        | grep -oE "${_wops_second}\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # awk: `print`/`printf` redirected to a quoted literal, the shape that
      # writes a file from inside an awk program
      # (`awk 'BEGIN{print "x" > "path"}'`). The redirect lives inside the
      # program string, so every shell-syntax redirection vector blanks it as
      # data. Only a QUOTED target counts: an awk redirect to a bare identifier
      # is indistinguishable from a numeric comparison (`print (a > b)`), and
      # firing on that shape would block read-only awk one-liners.
      if [ "$has_awk" = "1" ]; then
        printf '%s' "$cmd" \
          | grep -oE "(print|printf)[^;}]*>{1,2}[[:space:]]*${_q}[^\\\\\"']+${_q}" \
          | sed -E "s/^.*>{1,2}[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      fi
    } 2>/dev/null || true
  )"

  # --- targets this scan cannot resolve ---
  # A write op whose target is a variable or expression, and the in-place
  # interpreter edits (perl -pi -e, ruby -i, perl -i.bak) whose target is the
  # file operand. The flag must end at a word or suffix boundary so an unrelated
  # long option (`ruby -version`) does not read as `-i`.
  if printf '%s' "$cmd" | grep -qE "open\([[:space:]]*${_nonlit}[^)]*,[[:space:]]*${_q}[waxWAX>]|open\([^)]*mode[[:space:]]*=[[:space:]]*${_q}[wax]|(${_wops_first}|File\.open)\([[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # Copy/rename whose DESTINATION (second argument) is a variable or expression.
  if printf '%s' "$cmd" | grep -qE "${_wops_second}\([^,)]*,[[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # pathlib's write_text/write_bytes carry CONTENT, not a path — the target sits
  # in the Path(...) call (spelled adjacent to the write, or bound to a variable
  # on an earlier line and resolved by _geniro_wv_resolve_pathlib_var above; a
  # literal from either shape was already emitted in the capture block). What
  # is left unresolved here is a target that is NEITHER: no adjacent
  # `Path("<lit>")`, and either no bare-identifier `IDENT.write_text(...)` call
  # at all (e.g. a chained expression like `Path(x).write_text(...)`) or one
  # whose identifier carries no visible literal-binding assignment.
  # `.touch()` and a write-mode `.open(...)` are write-capable exactly like
  # `write_text`/`write_bytes` and feed the SAME identifier capture above —
  # gating only the first two here let an unresolvable `p.touch()` or
  # `p.open('w')` yield zero candidates AND no fallback, the silent-allow this
  # block exists to prevent.
  local _wv_wgate="(write_text|write_bytes|touch)\\(|\\.open\\([^)]*${_q}[waxWAX>]"
  if printf '%s' "$cmd" | grep -qE "$_wv_wgate"; then
    if ! printf '%s' "$cmd" | grep -qE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch)|Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.open\([^)]*${_q}[waxWAX>]"; then
      local _wv_any_pvar=0 _wv_all_pvar_resolved=1 _wv_pvar3
      while IFS= read -r _wv_pvar3; do
        [ -z "$_wv_pvar3" ] && continue
        _wv_any_pvar=1
        _geniro_wv_resolve_pathlib_var "$_wv_pvar3" "$cmd" >/dev/null 2>&1 || _wv_all_pvar_resolved=0
      done <<< "$(printf '%s' "$cmd" \
        | grep -oE '[A-Za-z_][A-Za-z0-9_]*\.(write_text|write_bytes|touch)\(|[A-Za-z_][A-Za-z0-9_]*\.open\([^)]*'"${_q}"'[waxWAX>]' \
        | sed -E "s/\.(write_text|write_bytes|touch)\(\$//; s/\.open\(.*\$//" \
        | sort -u)"
      if [ "$_wv_any_pvar" = "0" ] || [ "$_wv_all_pvar_resolved" = "0" ]; then
        unresolved=1
      fi
    fi
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(perl|ruby)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i([[:space:].]|$)'; then
    unresolved=1
  fi

  [ "$unresolved" = "1" ] && return 10
  return 0
}

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

# ---------------------------------------------------------------------------
# E. _geniro_wv_unquote_words <text>
#
# Recover the word the SHELL will actually pass, for the quoting and escaping
# that a guard's line-oriented passes destroy before they can match it.
#
# Three shell-inert spellings name one word, and every guard here matches words:
#
#   1. `$'--force'` / `$"--force"` — ANSI-C and locale quoting delimit a word
#      exactly like a plain quote, but leave a `$` glued to the token once the
#      marks come off, so a whitespace-anchored matcher never anchors.
#   2. `'--force'`, `"--force"`, `--fo""rce`, `.e""nv` — a quoted span carrying
#      no whitespace is one word, so its marks are noise. Blanking it as data
#      (correct for prose) erases a flag or a path operand instead.
#   3. `\-\-force`, `--for\ce`, `.\env` — a backslash before an ordinary
#      character is dropped by the shell. Only ordinary characters are
#      unescaped here: `\ `, `\\`, `\$`, `\"`, `\'` and a line continuation all
#      change what the shell does, so they are left alone.
#
# A quoted span CONTAINING whitespace stays quoted — that is prose, and
# unquoting `echo "never run git push --force"` would block a sentence. The
# whitespace test is what separates an operand from a quotation.
#
# Callers run this BEFORE their quoted-literal blanking pass, so the blanking
# that follows sees only spans that really are data.
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

# ---------------------------------------------------------------------------
# F. _geniro_wv_expand_assignments <text>
#
# Put an assigned literal back where its expansion sits, so a guard matches the
# command the shell will actually run.
#
# There are two shapes and they need opposite treatment from the payload
# extractor. A variable can hold a whole destructive COMMAND (`C="<force-push
# spelled out>"; $C`), or it can hold just the OPERAND a destructive command
# will act on (`P=<guarded dir>; rm -rf $P`). Re-running a guard on the value
# only works for the first — a bare path proves nothing on its own.
# Substituting the value back into the text covers both, because in both cases
# the value is what reaches the shell.
#
# Only single-pass literal assignments are expanded — a value that is itself an
# expansion, a substitution, or the output of a command is left alone rather
# than chased, since nothing here evaluates anything. Longest names first, so
# `$AB` is not clobbered by a rule for `$A`.
#
# ALL-OR-NOTHING per identifier, not first-assignment-wins: a script can bind
# the SAME name more than once (`F=out.txt; F=<protected>; printf x > "$F"`),
# and this function has no notion of WHICH assignment was live at the read
# site — only that the text carries more than one candidate. The previous
# code picked a value anyway: it substituted whichever binding its pass
# reached first, which — since a substituted `$NAME` disappears from the text
# before a later binding of the SAME name is ever tried — silently became
# "first assignment in the text wins," an accident of iteration order with no
# relationship to what the shell would actually run. That let a read site
# resolve to a decoy while the real, live value (possibly the protected one)
# was never checked — a bypass, not a false positive.
#
# A name whose every occurrence agrees on ONE literal value substitutes
# exactly as before — ordinary shell with a single (or idempotently repeated)
# binding is unaffected. A name that is EVER non-literal, or carries two or
# more DISTINCT literal values, is instead rewritten to an inert SENTINEL:
# on its own the sentinel matches no protected pattern (cost-free to a caller
# doing plain literal matching, e.g. block-dangerous-git.sh's command-text
# scan), while a caller whose vector IS the write/delete target — file-
# protection.sh's and enforce-tdd-order.sh's candidate extraction — greps its
# own extracted candidate for the sentinel and, on a match, routes into the
# SAME conservative fallback an unresolved interpreter target already uses:
# `_geniro_wv_path_tokens` over the surrounding text, which still carries
# every literal binding as a plain token, so `F=<protected>; F=out.txt;
# printf x > "$F"` still surfaces `<protected>` as a candidate even though the
# live value at the read site is the benign one — the same "check the
# superset, not just the one you can prove" trade this function's sibling
# resolvers make.
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
