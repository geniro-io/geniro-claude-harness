#!/usr/bin/env bash
# Single source of truth for the write/delete vectors a Bash-side guard cannot
# see by matching shell syntax alone.
#
# Two families live here:
#   A. `_geniro_extract_inner_payloads` — shell indirection (`sh -c`, `eval`).
#   B. `_geniro_interp_write_targets` / `_geniro_interp_delete_targets` —
#      interpreter-mediated file writes and deletes (python/node/perl/ruby/php,
#      plus awk for writes).
#
# A shell can be handed a program four ways, and only one of them is shell
# syntax the guards can match directly. `sh -c "<payload>"` and
# `eval "<payload>"` pass it as an ARGUMENT; `echo "<payload>" | bash` and
# `bash <<EOF … EOF` pass it on STDIN. In every case the guards' own passes
# destroy it before matching — quoted literals are blanked as data, heredoc
# bodies are dropped as data — so without this extraction the payload is inert
# text and the guard never inspects the command that actually runs. Each guard
# calls this BEFORE its own quote-blanking pass, then re-runs ITSELF on every
# returned payload; a block inside propagates out. Recursion terminates because
# a payload is always strictly shorter than the command it came from.
#
# Four shapes are extracted:
#   1. the sh|bash|zsh|dash|ksh|ash `-c` family — any flag cluster containing c
#      (-c, -lc, -euc), payload double-quoted, single-quoted, or bare;
#   2. `eval` followed by a quoted or bare payload;
#   3. a quoted literal piped into a BARE shell (`echo "<payload>" | bash`,
#      `printf '<payload>' | sh`) — stdin, so arms 1 and 2 never see it;
#   4. a heredoc body whose opener line invokes a bare shell (`bash <<EOF`,
#      `cat <<EOF | sh`) — also stdin, and the guards' heredoc scrub would
#      otherwise drop it as data. Emitted one body LINE per payload, which is
#      what the guards' line- and span-oriented matchers consume.
#
# Usage:
#   source "$_script_dir/write-vectors.sh"
#   payloads="$(_geniro_extract_inner_payloads "$SCRUBBED" "$COMMAND")"
#
# $1 is the heredoc-scrubbed command (arms 1-3 read it, so a `sh -c` MENTIONED
# inside a heredoc body destined for a file stays data). $2 is the RAW command,
# bodies intact — arm 4 needs them, and it re-derives which heredocs are fed to
# a shell rather than trusting the scrub. Omit $2 to run arms 1-3 only.
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
  local _m _pl

  # Arm 1 — interpreter `-c` payload.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/])(sh|bash|zsh|dash|ksh|ash)[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"

  # Arm 2 — `eval` payload. The preceding-character class excludes `-` so a long
  # option belonging to another tool (`node --eval`, `perl --eval`) is not read
  # as the shell builtin; those are interpreter payloads, not shell commands.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^[^[:alnum:]_]?eval[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_/-])eval[[:space:]]+("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)' 2>/dev/null || true)"

  # Arm 3 — a quoted literal piped into a BARE shell. `echo "<program>" | bash`
  # feeds <program> on stdin, so it is neither a `-c` argument nor an `eval`
  # operand, and the guard's quote-scrub blanks it as data. The right-hand side
  # must carry no flag cluster containing `c` (that spelling is arm 1's, and
  # with -c the shell ignores stdin). Only a QUOTED left-hand literal is
  # extractable: a producer that COMPUTES its program (a file read, a network
  # download) carries no literal this scan can read — the download spelling is
  # hooks/security-pattern-check.sh's sec-curl-pipe-sh pattern instead.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    # Drop from the LAST pipe, so a `|` inside the literal survives.
    _pl=$(printf '%s' "$_m" | sed -E 's/[[:space:]]*[|][^|]*$//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '("[^"]*"|'\''[^'\'']*'\'')[^|"'\'']*\|[[:space:]]*((sudo|command|env|exec)[[:space:]]+)*([^[:space:]|;&<>]*/)?(sh|bash|zsh|dash|ksh|ash)([[:space:]]+-[a-bd-zA-BD-Z0-9]+)*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

  # Arm 4 — a heredoc body fed to a bare shell (`bash <<EOF … EOF`,
  # `cat <<EOF | sh`). This is the mirror image of arm 3: the body is stdin, and
  # every guard's heredoc scrub deletes it BEFORE extraction because a heredoc is
  # data in every other position (`cat > notes.md <<EOF`). So the body is
  # re-derived here from the RAW command, and emitted only when the opener line
  # names a bare shell as a command word. One body LINE per payload: the guards
  # match per line and per `;`-bounded span, and joining the body would let a
  # single `#` comment line swallow the commands after it.
  if [ -n "$raw" ]; then
    printf '%s\n' "$raw" | awk '
      hd {
        line = $0
        if (dash) sub(/^\t+/, "", line)
        if (line == tag) { hd = 0; next }
        if (emit) print line
        next
      }
      match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["'\'']/, "", tag)
        hd = 1
        emit = ($0 ~ /(^|[|;&][[:space:]]*|[[:space:]])(sudo[[:space:]]+|command[[:space:]]+|env[[:space:]]+|exec[[:space:]]+)*([^[:space:]|;&<>]*\/)?(sh|bash|zsh|dash|ksh|ash)([[:space:]]|$)/)
        next
      }
    ' 2>/dev/null || true
  fi

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
# (`F=.env; python3 -c "open('$F','w')…"`). Prints the resolved literal; returns
# 1 when a referenced variable has no visible assignment (target unknown).
_geniro_wv_resolve() {
  local lit="${1:-}" cmd="${2:-}"
  case "$lit" in
    *'`'*) return 1 ;;
    *'$'*) : ;;
    *) printf '%s' "$lit"; return 0 ;;
  esac
  local resolved="$lit" ref vn val
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    vn="${ref#\$}"; vn="${vn#\{}"; vn="${vn%\}}"
    val=$(printf '%s' "$cmd" \
      | grep -oE "(^|[[:space:];&|])${vn}=[^[:space:];&|\"']+" \
      | tail -1 | sed -E 's/^[^=]*=//' || true)
    if [ -z "$val" ]; then return 1; fi
    resolved=$(printf '%s' "$resolved" | sed "s|[\$]{${vn}}|${val}|g; s|[\$]${vn}|${val}|g")
  done <<< "$(printf '%s' "$lit" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' || true)"
  printf '%s' "$resolved"
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
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|perl|ruby|php|awk|gawk|mawk)([[:space:]]|$)'; then
    return 0
  fi

  # Quote class tolerating a shell backslash-escape (`open(\"x\", \"w\")` is how a
  # double-quoted -c argument reaches a guard).
  local _q="\\\\?[\"']"
  # A non-literal target: a bare identifier or an escaped variable
  # (`fopen(\$f, "w")`), i.e. anything that is not the opening quote of a literal.
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  local unresolved=0 has_awk=0 lit resolved
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(awk|gawk|mawk)([[:space:]]|$)'; then
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
      # argument — `open('<path>')` is a read and must stay allowed.
      printf '%s' "$cmd" \
        | grep -oE "(open|fopen|File\.open)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[waxWAX>]" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # perl's 3-argument open puts the mode second and the path third
      # (`open(FH, ">", "path")`).
      printf '%s' "$cmd" \
        | grep -oE "open\([^,)]*,[[:space:]]*${_q}[>+]{1,2}${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^.*,[[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # These write unconditionally, so their first argument is the target.
      printf '%s' "$cmd" \
        | grep -oE "(writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|IO\.write)\([[:space:]]*${_q}[^\\\\\"']+${_q}" \
        | sed -E "s/^[^(]*\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # pathlib: the target is the Path(...) argument, not write_text's content.
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch|open)" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
      # Copy/rename: the SECOND argument is the target. This is the interpreter
      # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in
      # every calling guard already treats as a write — without it the same
      # clobber walks past that guard just by being written in Python or Node.
      # (No apostrophe above on purpose: bash 3.2 does not skip comments while
      # scanning a $( ) body, so one would read as an unterminated quote.)
      printf '%s' "$cmd" \
        | grep -oE "(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|copyFileSync|renameSync|File\.rename)\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*,[[:space:]]*${_q}[^\\\\\"']+${_q}" \
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
  if printf '%s' "$cmd" | grep -qE "open\([[:space:]]*${_nonlit}[^)]*,[[:space:]]*${_q}[waxWAX>]|open\([^)]*mode[[:space:]]*=[[:space:]]*${_q}[wax]|(writeFileSync|appendFileSync|createWriteStream|writeFile|file_put_contents|File\.write|File\.open|IO\.write)\([[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # Copy/rename whose DESTINATION (second argument) is a variable or expression.
  if printf '%s' "$cmd" | grep -qE "(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|copyFileSync|renameSync|File\.rename)\([^,)]*,[[:space:]]*${_nonlit}"; then
    unresolved=1
  fi
  # pathlib's write_text/write_bytes carry CONTENT, not a path — the target sits
  # in the Path(...) call. A literal there was already emitted above; every other
  # spelling (`p.write_text(d)` on a Path built earlier) leaves it unknown.
  if printf '%s' "$cmd" | grep -qE '(write_text|write_bytes)\('; then
    if ! printf '%s' "$cmd" | grep -qE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes)"; then
      unresolved=1
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
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    return 0
  fi

  local _q="\\\\?[\"']"
  local _nonlit="(\\\\[^\"']|[^\\\\\"'[:space:])])"
  # Delete ops across the interpreter families. Each is name-qualified
  # (`os.remove`, `fs.rm`) or unambiguous on its own (`rmtree`, `unlink`), so a
  # same-named collection method (`list.remove`) does not read as a file delete.
  # The move/rename family is included because DISPLACEMENT loses a tree from its
  # protected location as completely as deletion does, and its first argument is
  # the source — the same operand position the delete ops use.
  local _ops="(shutil\.rmtree|rmtree|os\.removedirs|os\.remove|os\.unlink|os\.rmdir|fs\.rmSync|fs\.rmdirSync|fs\.unlinkSync|fs\.rm|rmSync|rmdirSync|unlinkSync|FileUtils\.rm_rf|FileUtils\.rm_r|FileUtils\.rm|File\.delete|File\.unlink|Dir\.delete|unlink|rmdir|shutil\.move|os\.rename|os\.replace|renameSync|File\.rename|FileUtils\.mv|FileUtils\.move)"
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
