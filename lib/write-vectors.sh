#!/usr/bin/env bash
# Single source of truth for the write/delete vectors a Bash-side guard cannot
# see by matching shell syntax alone.
#
# Three families live here:
#   A. `_geniro_extract_inner_payloads` — shell indirection (`sh -c`, `eval`, a
#      pipe, a heredoc, a process substitution, an interpreter shelling out).
#   B. `_geniro_interp_write_targets` / `_geniro_interp_delete_targets` —
#      interpreter-mediated file writes and deletes.
#   C. `_geniro_join_quoted_newlines` — a quoted literal spanning a newline,
#      which every line-oriented pass in a guard reads as two unbalanced lines.
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
# A shell can be handed a program six ways, and only one of them is shell syntax
# the guards can match directly. `sh -c "<payload>"` and `eval "<payload>"` pass
# it as an ARGUMENT; `echo "<payload>" | bash`, `bash <<EOF … EOF` and
# `bash <(echo "<payload>")` pass it on STDIN; `os.system('<payload>')` hands it
# to a shell from inside an interpreter. In every case the guards' own passes
# destroy it before matching — quoted literals are blanked as data, heredoc
# bodies are dropped as data — so without this extraction the payload is inert
# text and the guard never inspects the command that actually runs. Each guard
# calls this BEFORE its own quote-blanking pass, then re-runs ITSELF on every
# returned payload; a block inside propagates out. Recursion terminates because
# a payload is always strictly shorter than the command it came from.
#
# Six shapes are extracted:
#   1. the sh|bash|zsh|dash|ksh|ash `-c` family — any flag cluster containing c
#      (-c, -lc, -euc), payload double-quoted, single-quoted, or bare;
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
#      families here would otherwise miss it entirely.
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

  # ONE shell-word matcher for every arm. The wrapper prefix consumes its own
  # flags, `VAR=value` assignments, durations and `{}` placeholders — never an
  # arbitrary word, which would let any two-word command read as a shell.
  local _wv_pfx='((sudo|doas|command|env|exec|nohup|nice|timeout|stdbuf|ionice|xargs)([[:space:]]+(-[^[:space:];|&<>]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];|&<>]*|[0-9]+[smhd]?|[{}]+))*[[:space:]]+)*'
  local _wv_shq='["'\'']?'
  local _wv_sh="${_wv_pfx}${_wv_shq}"'([^[:space:];|&<>"'\'']*/)?(sh|bash|zsh|dash|ksh|ash)'"${_wv_shq}"
  # One quoted literal; and the payload operand form, which may also be bare.
  local _wv_lit='("[^"]*"|'\''[^'\'']*'\'')'
  local _wv_arg='("[^"]*"|'\''[^'\'']*'\''|[^[:space:];|&]+)'

  # Arm 1 — interpreter `-c` payload.
  while IFS= read -r _m; do
    [ -z "$_m" ] && continue
    _pl=$(printf '%s' "$_m" | sed -E 's/^.*[[:space:]]-[A-Za-z]*c[A-Za-z]*[[:space:]]+//')
    _pl="${_pl#\"}"; _pl="${_pl%\"}"
    _pl="${_pl#\'}"; _pl="${_pl%\'}"
    [ -n "$_pl" ] && printf '%s\n' "$_pl"
  done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_sh}"'[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+'"${_wv_arg}" 2>/dev/null || true)"

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
  done <<< "$(printf '%s\n' "$cmd" | grep -oE "${_wv_lit}"'[^|"'\'']*\|[[:space:]]*'"${_wv_sh}"'([[:space:]]+-[a-bd-zA-BD-Z0-9]+)*[[:space:]]*($|[;&|])' 2>/dev/null || true)"

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
      match($0, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/) {
        tag = substr($0, RSTART, RLENGTH)
        dash = (tag ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", tag)
        gsub(/["'\'']/, "", tag)
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
  if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
    # A dot is allowed before the op name because that is how the ops are normally
    # reached (`require('child_process').execSync(…)`); the cost is that a JS
    # `re.exec("s")` also yields its argument, which re-scans as an inert word.
    local _wv_shellout='(os\.(system|popen)|subprocess\.[A-Za-z_]+|Kernel\.system|IO\.popen|Open3\.[a-z_]+|exec(Sync|FileSync)?|system|popen|shell_exec|passthru|proc_open)'
    while IFS= read -r _m; do
      [ -z "$_m" ] && continue
      _pl=$(printf '%s' "$_m" | sed -E 's/^[^(]*\([[:space:]]*//')
      _pl="${_pl#\\}"
      _pl="${_pl#\"}"; _pl="${_pl%\"}"
      _pl="${_pl#\'}"; _pl="${_pl%\'}"
      _pl="${_pl%\\}"
      [ -n "$_pl" ] && printf '%s\n' "$_pl"
    done <<< "$(printf '%s\n' "$cmd" | grep -oE '(^|[^[:alnum:]_])'"${_wv_shellout}"'[[:space:]]*\([[:space:]]*\\?'"${_wv_lit}" 2>/dev/null || true)"

    # Ruby's backtick literal is the same shell-out with no call syntax at all.
    # Narrowed further to a `ruby` command word: elsewhere a backtick span is
    # ordinary shell command substitution, already visible to the guards as
    # syntax, and re-extracting it would only add noise.
    if printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)ruby([[:space:]]|$)'; then
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
# ---------------------------------------------------------------------------
_geniro_join_quoted_newlines() {
  local cmd="${1:-}"
  [ -z "$cmd" ] && return 0
  printf '%s\n' "$cmd" | awk '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); q = ""; out = ""; seg = ""
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (q == "") {
          if (c == "\"" || c == "'\''") { q = c; seg = c } else { out = out c }
        } else if (c == "\n") {
          seg = seg " "
        } else {
          seg = seg c
          if (c == q) { out = out seg; q = ""; seg = "" }
        }
      }
      if (q != "") { printf "%s", buf } else { printf "%s", out }
    }
  ' 2>/dev/null || printf '%s\n' "$cmd"
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
  # Runtime roster. bun and tsx implement node:fs verbatim and deno ships its own
  # Deno.* file API, so a roster frozen at the 2019 set lets one word bypass the
  # whole channel.
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript|awk|gawk|mawk)([[:space:]]|$)'; then
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
  # `writeTextFile` covers Deno.writeTextFile(Sync).
  local _wops_first='((writeFile|appendFile|createWriteStream|outputFile|writeTextFile)(Sync)?|file_put_contents|File\.write|IO\.write)'
  # Copy/rename: the SECOND argument is the target. This is the interpreter
  # spelling of a cp/mv DESTINATION, which the shell-side cp/mv vector in every
  # calling guard already treats as a write — without it the same clobber walks
  # past that guard just by being written in Python or Node.
  local _wops_second='(shutil\.copy[A-Za-z0-9_]*|shutil\.move|os\.rename|os\.replace|File\.rename|FileUtils\.(cp|mv|copy|move)|(copyFile|rename|cp)(Sync)?)'
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
      printf '%s' "$cmd" \
        | grep -oE "Path\([[:space:]]*${_q}[^\\\\\"']+${_q}[[:space:]]*\)[[:space:]]*\.(write_text|write_bytes|touch|open)" \
        | sed -E "s/^Path\([[:space:]]*\\\\?[\"']//; s/\\\\?[\"'].*\$//"
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
  if ! printf '%s' "$cmd" | grep -qE '(^|[|;&[:space:]]|/)(python[0-9.]*|node|bun|bunx|deno|tsx|perl|ruby|php|lua|tclsh|Rscript)([[:space:]]|$)'; then
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
