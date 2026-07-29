#!/usr/bin/env bash
# Unit suite for lib/write-vectors.sh — the single source of truth for the
# write/delete channels a Bash-side guard cannot see by matching shell syntax.
#
# Run: bash tests/hooks/write-vectors.sh
#
# Why a unit suite and not only the per-hook suites: four guards consume this
# one helper, and three consecutive audits each closed one channel and left the
# next open precisely because the channel list had no test of its own. A per-hook
# test proves one guard blocks one shape; this suite pins the CHANNEL MATRIX, so
# a new indirection shape has one place to be added and one place to fail.
#
# Contract under test (documented in the helper's own header):
#   _geniro_extract_inner_payloads "$SCRUBBED" "$RAW"
#     Four arms — `-c` family, `eval`, pipe-to-shell, heredoc-to-shell. Arms 1-3
#     read $1 (heredoc-scrubbed); arm 4 reads $2 (raw, bodies intact). One
#     payload per line, one layer of surrounding quotes stripped. Always rc=0.
#   _geniro_interp_write_targets  / _geniro_interp_delete_targets
#     stdout — one resolved literal target per line.
#     rc 0  — no interpreter/op conjunction, or every target resolved.
#     rc 10 — at least one target is a variable/expression this scan cannot
#             resolve; the caller decides (fail-safe, never fail-open).
#
# Fixture paths are neutral (.env, secret.txt, proj/data) — the helper is
# path-agnostic and each caller supplies its own path predicate.
#
# Portability: bash 3.2 / BSD, no writes anywhere, no network.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/write-vectors.sh"

# Normalize a helper's multi-line stdout to a stable, order-independent set so an
# assertion pins CONTENT, not emission order (a target matched by two arms is
# emitted twice; the guards de-duplicate by testing each line).
as_set() { printf '%s' "$1" | { grep -v '^$' || true; } | LC_ALL=C sort -u | tr '\n' ',' | sed 's/,$//'; }

OUT=""
RC=0
run_extract() { OUT=$(_geniro_extract_inner_payloads "$@"); RC=$?; }
run_write()   { OUT=$(_geniro_interp_write_targets "$1");   RC=$?; }
run_delete()  { OUT=$(_geniro_interp_delete_targets "$1");  RC=$?; }

# expect <label> <expected-set> <expected-rc>  — reads OUT/RC from the last run_*.
expect() {
  local label="$1" want="$2" want_rc="$3" got
  got=$(as_set "$OUT")
  if [ "$got" = "$want" ] && [ "$RC" = "$want_rc" ]; then
    pass "$label"
  else
    fail "$label — got rc=$RC targets='$got' (expected rc=$want_rc targets='$want')"
  fi
}

echo "===== _geniro_extract_inner_payloads — arm 1: the \`-c\` family ====="

run_extract 'sh -c "printf k > .env"';        expect "sh -c, double-quoted payload"        'printf k > .env' 0
run_extract "bash -lc 'rm -f x'";             expect "bash -lc, single-quoted payload"     'rm -f x' 0
run_extract 'zsh -euc "echo hi"';             expect "zsh -euc, flag cluster containing c" 'echo hi' 0
run_extract 'dash -c echo';                   expect "dash -c, bare payload"               'echo' 0
run_extract 'ksh -c "echo hi"';               expect "ksh -c"                              'echo hi' 0
run_extract 'ash -c "echo hi"';               expect "ash -c"                              'echo hi' 0
# A `-c` mid-word must not read as the flag: the guard would otherwise extract a
# payload out of an unrelated tool's argument on every command line.
run_extract 'mysh -c "echo hi"';              expect "a non-shell command word is not the -c family" '' 0

echo
echo "===== _geniro_extract_inner_payloads — arm 2: \`eval\` ====="

run_extract 'eval "rm -f x"';                 expect "eval, double-quoted payload"   'rm -f x' 0
run_extract "eval 'rm -f x'";                 expect "eval, single-quoted payload"   'rm -f x' 0
run_extract 'eval rm';                        expect "eval, bare payload"            'rm' 0
# `--eval` belongs to an interpreter, not the shell builtin. Reading it as a
# shell payload would hand the guard a JS/Perl program to match as shell syntax.
run_extract 'node --eval "console.log(1)"';   expect "node --eval is NOT the shell builtin" '' 0
run_extract 'perl --eval "print 1"';          expect "perl --eval is NOT the shell builtin" '' 0

echo
echo "===== _geniro_extract_inner_payloads — nested indirection ====="

# The helper extracts one layer; the CALLER re-runs itself on each payload. Both
# layers must therefore be reachable: the outer payload here still contains the
# inner `eval`, and a second pass resolves it.
run_extract "sh -c 'eval \"echo deep\"'"
first_pass="$OUT"
if printf '%s\n' "$first_pass" | grep -q 'eval "echo deep"'; then
  run_extract 'eval "echo deep"'
  expect "nested sh -c \" eval: second pass reaches the inner payload" 'echo deep' 0
else
  fail "nested sh -c / eval: first pass did not surface the inner eval — got '$first_pass'"
fi

echo
echo "===== _geniro_extract_inner_payloads — arm 3: pipe-to-shell (stdin) ====="

run_extract 'echo "printf k > .env" | bash';  expect "echo \"…\" | bash"                  'printf k > .env' 0
run_extract "printf 'rm -f x' | sh";          expect "printf '…' | sh"                    'rm -f x' 0
run_extract 'echo "rm -f x" | sudo bash';     expect "pipe through a sudo prefix"         'rm -f x' 0
run_extract 'echo "rm -f x" | /usr/bin/sh';   expect "pipe into a path-qualified shell"   'rm -f x' 0
# Right-hand side is not a shell — the literal is data, not a program.
run_extract 'echo "hello" | grep -q h';       expect "pipe into a non-shell is not a payload" '' 0

echo
echo "===== _geniro_extract_inner_payloads — arm 4: heredoc-to-shell (stdin) ====="

# The guards scrub heredoc bodies BEFORE extraction (a heredoc is data in every
# other position), so arm 4 re-derives the body from the RAW command in $2. $1 is
# what the guard's own scrub left behind.
HD_SHELL=$'bash <<EOF\nrm -f secret.txt\nEOF\n'
run_extract 'bash <<EOF' "$HD_SHELL"
expect "bash <<EOF body is extracted from the raw command" 'rm -f secret.txt' 0

HD_PIPE=$'cat <<EOF | sh\nrm -f secret.txt\nEOF\n'
run_extract 'cat <<EOF | sh' "$HD_PIPE"
expect "cat <<EOF | sh body is extracted" 'rm -f secret.txt' 0

HD_DASH=$'bash <<-EOF\n\trm -f secret.txt\n\tEOF\n'
run_extract 'bash <<-EOF' "$HD_DASH"
expect "<<- strips leading tabs and still finds the terminator" 'rm -f secret.txt' 0

HD_MULTI=$'bash <<\'EOF\'\nrm -f a\nrm -f b\nEOF\n'
run_extract "bash <<'EOF'" "$HD_MULTI"
expect "quoted tag, multi-line body emits one payload per line" 'rm -f a,rm -f b' 0

# The commonest heredoc by far writes a FILE. Emitting its body as a shell
# payload would make every `cat > notes.md <<EOF` re-enter the guard as commands.
HD_FILE=$'cat > notes.md <<EOF\nrm -f secret.txt\nEOF\n'
run_extract 'cat > notes.md <<EOF' "$HD_FILE"
expect "heredoc into a FILE is not a shell payload" '' 0

# $2 omitted → arms 1-3 only, per the documented signature.
run_extract "$HD_SHELL"
expect "arm 4 is inert when the raw command is not passed" '' 0

echo
echo "===== _geniro_extract_inner_payloads — no-indirection commands ====="

run_extract 'ls -la';   expect "a plain command yields no payload" '' 0
run_extract '';         expect "empty command yields no payload"   '' 0
run_extract '' '';      expect "both arguments empty yields no payload" '' 0

echo
echo "===== _geniro_interp_write_targets — python ====="

run_write 'python3 -c "open(\".env\",\"w\").write(1)"'
expect "open(path, \"w\") with escaped quotes" '.env' 0
run_write "python3 -c \"open('.env','w')\""
expect "open(path, 'w')" '.env' 0
run_write "python3 -c \"open('.env','a')\""
expect "open(path, 'a') — append is a write" '.env' 0
# The third conjunct is the write MODE: a read must stay allowed or every
# interpreter one-liner that opens a file becomes a block.
run_write "python3 -c \"open('x.txt')\""
expect "open(path) with no mode is a read — no target" '' 0
run_write "python3 -c \"data = open('x.txt').read()\""
expect "open(path).read() is a read — no target" '' 0

run_write "python3 -c \"from pathlib import Path; Path('.env').open('w')\""
expect "Path(path).open('w')" '.env' 0
run_write "python3 -c \"from pathlib import Path; Path('.env').touch()\""
expect "Path(path).touch()" '.env' 0
run_write "python3 -c \"from pathlib import Path; Path('.env').write_text('x')\""
expect "Path(path).write_text()" '.env' 0
run_write "python3 -c \"from pathlib import Path; Path('.env').write_bytes(b'x')\""
expect "Path(path).write_bytes()" '.env' 0
# write_text carries CONTENT, not a path — with the Path built earlier the target
# is unknowable, which must surface as rc=10 rather than as silence.
run_write "python3 -c \"p = build(); p.write_text('x')\""
expect "write_text on a Path built earlier → rc=10, no target" '' 10

echo
echo "===== _geniro_interp_write_targets — node / perl / ruby / php / awk ====="

run_write "node -e \"fs.writeFileSync('.env','x')\""
expect "node writeFileSync" '.env' 0
run_write "node -e \"fs.appendFileSync('a.log','x')\""
expect "node appendFileSync" 'a.log' 0
run_write "node -e \"fs.createWriteStream('o.bin')\""
expect "node createWriteStream" 'o.bin' 0
run_write "node -e \"console.log(process.argv)\""
expect "a read-only node one-liner yields nothing" '' 0

# perl's 3-argument open puts the mode second and the path third. The FH bareword
# in argument 1 also trips the unresolved scan, so this reports the literal AND
# rc=10 — the fail-safe direction (the caller checks the target and still knows
# something else in the command was unreadable).
run_write "perl -e 'open(FH, \">\", \"out.txt\")'"
expect "perl 3-arg open reports the path and flags the bareword handle" 'out.txt' 10

run_write "ruby -e \"File.write('r.txt','x')\""
expect "ruby File.write" 'r.txt' 0
run_write "ruby -e \"IO.write('r2.txt','x')\""
expect "ruby IO.write" 'r2.txt' 0
run_write "php -r \"file_put_contents('p.txt','x');\""
expect "php file_put_contents" 'p.txt' 0

# The awk redirect lives inside the PROGRAM string, so every shell-syntax
# redirection vector blanks it as data.
run_write "awk 'BEGIN{print \"x\" > \"a.txt\"}'"
expect "awk print > \"literal\"" 'a.txt' 0
run_write "awk 'BEGIN{printf \"%s\", \"x\" >> \"a.txt\"}'"
expect "awk printf >> \"literal\"" 'a.txt' 0
# A bare identifier after `>` in awk is indistinguishable from a comparison, so
# firing on it would block read-only one-liners.
run_write "awk '{print \$1}' f.txt"
expect "a read-only awk one-liner yields nothing" '' 0

echo
echo "===== _geniro_interp_write_targets — copy / rename (target is arg 2) ====="

# The interpreter spelling of a `cp`/`mv` DESTINATION. Without these the same
# clobber walks past a guard that blocks the shell spelling.
run_write "python3 -c \"import shutil; shutil.copy('t','.env')\""
expect "shutil.copy destination" '.env' 0
run_write "python3 -c \"import shutil; shutil.copy2('t','.env')\""
expect "shutil.copy2 destination" '.env' 0
run_write "python3 -c \"import shutil; shutil.move('t','.env')\""
expect "shutil.move destination" '.env' 0
run_write "python3 -c \"import os; os.rename('t','.env')\""
expect "os.rename destination" '.env' 0
run_write "python3 -c \"import os; os.replace('t','.env')\""
expect "os.replace destination" '.env' 0
run_write "node -e \"fs.copyFileSync('t','.env')\""
expect "fs.copyFileSync destination" '.env' 0
run_write "node -e \"fs.renameSync('t','.env')\""
expect "fs.renameSync destination" '.env' 0
run_write "python3 -c \"import shutil; shutil.copy('t', dest)\""
expect "copy with a variable destination → rc=10" '' 10

echo
echo "===== _geniro_interp_write_targets — exit codes ====="

run_write "python3 -c \"open(F,'w')\""
expect "variable target → rc=10, no literal" '' 10
run_write "F=.env; python3 -c \"open('\$F','w')\""
expect "variable assigned in the SAME command resolves → rc=0" '.env' 0
run_write "python3 -c \"open(os.environ['X'],'w')\""
expect "target from the environment → rc=10" '' 10
# perl -i / ruby -i edit in place; the file operand is on the command line, so
# rc=10 tells the caller to look there.
run_write "perl -pi -e 's/a/b/' src/app.js"
expect "perl -pi in-place edit → rc=10" '' 10
run_write "ruby -i -pe 'x' src/app.js"
expect "ruby -i in-place edit → rc=10" '' 10
# No interpreter → the whole scan is skipped; the caller's shell-syntax vectors
# own this shape.
run_write "cp t .env"
expect "a shell-syntax copy is not this scan's channel" '' 0
run_write ""
expect "empty command → rc=0, no target" '' 0

echo
echo "===== _geniro_interp_delete_targets ====="

run_delete "python3 -c \"import os; os.remove('proj/data/x')\""
expect "os.remove" 'proj/data/x' 0
run_delete "python3 -c \"import os; os.unlink('proj/data/x')\""
expect "os.unlink" 'proj/data/x' 0
run_delete "python3 -c \"import shutil; shutil.rmtree('proj/data')\""
expect "shutil.rmtree" 'proj/data' 0
run_delete "python3 -c \"from pathlib import Path; Path('proj/data/x').unlink()\""
expect "Path(path).unlink()" 'proj/data/x' 0
run_delete "node -e \"fs.unlinkSync('proj/data/x')\""
expect "node fs.unlinkSync" 'proj/data/x' 0
run_delete "node -e \"fs.rmSync('proj/data',{recursive:true})\""
expect "node fs.rmSync" 'proj/data' 0
run_delete "ruby -e \"FileUtils.rm_rf('proj/data')\""
expect "ruby FileUtils.rm_rf" 'proj/data' 0

# Displacement loses a tree from its protected location as completely as
# deletion, and the SOURCE is the first operand — the same position as a delete.
run_delete "python3 -c \"import shutil; shutil.move('proj/data','/tmp/g')\""
expect "shutil.move source counts as a delete" 'proj/data' 0
run_delete "python3 -c \"import os; os.rename('proj/data','/tmp/g')\""
expect "os.rename source counts as a delete" 'proj/data' 0
run_delete "ruby -e \"FileUtils.mv('proj/data','/tmp/g')\""
expect "FileUtils.mv source counts as a delete" 'proj/data' 0

# Name-qualification keeps a same-named collection method out of the set.
run_delete "python3 -c \"lst.remove('a')\""
expect "list.remove is not a file delete" '' 0
run_delete "node -e \"console.log(1)\""
expect "a read-only node one-liner yields nothing" '' 0
run_delete "rm -rf proj/data"
expect "a shell-syntax rm is not this scan's channel" '' 0

run_delete "python3 -c \"import shutil; shutil.rmtree(D)\""
expect "variable delete target → rc=10" '' 10
run_delete ""
expect "empty command → rc=0, no target" '' 0

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
