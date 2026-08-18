#!/usr/bin/env bash
# Smoke test for hooks/file-protection.sh (PreToolUse Edit|Write|MultiEdit).
#
# Run: bash tests/hooks/file-protection.sh
#
# Coverage:
#   - Each protected pattern blocks (exit 2).
#   - Normal files + the substring-not-path-segment false-positive shape allow.
#   - safety.json allow_patterns bypass.
#   - MultiEdit form is guarded (file_path-based; fires once the matcher includes MultiEdit).
#   - Missing file_path fails-open (exit 0).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/file-protection.sh"

# The hook sources lib/write-vectors.sh via "${CLAUDE_PLUGIN_ROOT:-.}" — CWD-
# relative when the var is unset. This suite cd's into a mktemp sandbox below,
# so without exporting it every case here would silently exercise the hook's
# own INLINE VENDORED fallback copy (the "no lib/" install path) instead of the
# canonical helper this suite means to test. Same convention as
# tests/hooks/write-vectors-matrix.sh's "with" mode; the deliberate "without"
# comparison lives in tests/hooks/write-vectors-fallback-parity.sh.
export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Write-form payload (content arbitrary; the guard is file_path-based) -> exit code.
run_write() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, content: "x"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
# MultiEdit-form payload -> exit code (same single file_path; edits content irrelevant here).
run_multiedit() {
  jq -nc --arg p "$1" '{tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}]}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block() { if [ "$2" = "2" ]; then pass "$1"; else fail "$1 (expected exit=2, got exit=$2)"; fi; }
expect_allow() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1 (expected exit=0, got exit=$2)"; fi; }

cd "$TMPDIR_BASE" || exit 1

# ===== Protected patterns block =====
expect_block "write-env .env blocked"               "$(run_write /proj/.env)"
expect_block "write-env .env.local blocked"         "$(run_write /proj/.env.local)"
expect_block "write-git-internal .git/ blocked"     "$(run_write /proj/.git/config)"
expect_block "write-lockfile package-lock blocked"  "$(run_write /proj/package-lock.json)"
expect_block "write-lockfile go.sum blocked"        "$(run_write /proj/go.sum)"
expect_block "write-cert-key .pem blocked"          "$(run_write /proj/server.pem)"
expect_block "write-cert-key .key blocked"          "$(run_write /proj/tls.key)"
expect_block "write-credentials credentials.* blocked" "$(run_write /proj/credentials.json)"
expect_block "write-credentials secrets.* blocked"  "$(run_write /proj/config/secrets.yaml)"
expect_block "write-tfstate blocked"                "$(run_write /proj/terraform.tfstate)"
expect_block "write-vault blocked"                  "$(run_write /proj/prod.vault)"

# ===== Normal files allow =====
expect_allow "normal source file allows"            "$(run_write /proj/src/app.js)"
expect_allow "secrets as substring (not segment) allows" "$(run_write /proj/lib/redact-secrets.sh)"
expect_allow "env inside a longer name allows"      "$(run_write /proj/environment.ts)"

# ===== MultiEdit form is now guarded (file_path-based) =====
expect_block "MultiEdit to .env blocked"            "$(run_multiedit /proj/.env)"
expect_allow "MultiEdit to normal file allows"      "$(run_multiedit /proj/src/app.js)"

# ===== safety.json bypass =====
mkdir -p "$TMPDIR_BASE/proj-bypass/.geniro"
echo '{"allow_patterns": ["write-env"]}' > "$TMPDIR_BASE/proj-bypass/.geniro/safety.json"
cd "$TMPDIR_BASE/proj-bypass" || exit 1
expect_allow "safety.json bypass: write-env allowed"        "$(run_write /proj/.env)"
expect_block "safety.json bypass: unrelated pattern still blocks" "$(run_write /proj/server.pem)"
cd "$TMPDIR_BASE" || exit 1

# ===== Bash branch: shell-side writes into protected paths =====
run_bash() {
  jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "bash: echo redirect to .env blocked"        "$(run_bash 'echo "API_KEY=x" > .env')"
expect_block "bash: append to .env blocked"               "$(run_bash 'printf "K=v\n" >> ./.env')"
expect_block "bash: tee to .env blocked"                  "$(run_bash 'echo x | tee .env')"
expect_block "bash: tee -a to credentials.json blocked"   "$(run_bash 'cat tmp.txt | tee -a config/credentials.json')"
expect_block "bash: sed -i on go.sum blocked"             "$(run_bash "sed -i.bak 's/a/b/' go.sum")"
expect_block "bash: sed --in-place (GNU long form) on .env blocked" "$(run_bash "sed --in-place 's/a/b/' .env")"
expect_block "bash: cp onto .env blocked"                 "$(run_bash 'cp .env.example .env')"
expect_block "bash: mv onto server.pem blocked"           "$(run_bash 'mv new.pem server.pem')"
expect_block "bash: dd of=secrets.yaml blocked"           "$(run_bash 'dd if=/dev/stdin of=secrets.yaml')"
expect_allow "bash: reading .env allowed"                 "$(run_bash 'cat .env')"
expect_allow "bash: grep in .env allowed"                 "$(run_bash 'grep KEY .env')"
expect_allow "bash: cp FROM protected source allowed"     "$(run_bash 'cp .env /tmp/inspect.txt')"
expect_allow "bash: redirect to normal file allowed"      "$(run_bash 'echo x > out.txt')"
expect_allow "bash: stderr to /dev/null allowed"          "$(run_bash 'npm test 2>/dev/null')"
expect_allow "bash: fd dup >&2 allowed"                   "$(run_bash 'echo err >&2')"
expect_allow "bash: plain git command allowed"            "$(run_bash 'git status')"
expect_allow "bash: sed without -i on go.sum allowed"     "$(run_bash "sed 's/a/b/' go.sum")"

# Data contexts (quoted strings, heredoc bodies, sed scripts) must not block.
# The line between a quotation and an operand is whitespace, not quoting: a
# quoted span carrying a space is prose and stays blanked, while a
# whitespace-free one is a single shell word and is unquoted before matching
# (lib/write-vectors.sh §E). That is what lets the two assertions below —
# "set x > .env to configure" allowed, `> ".env"` blocked — both hold.
expect_allow "bash: quoted-string mention of > .env allowed"  "$(run_bash 'echo "set x > .env to configure"')"
expect_allow "bash: quoted sed script naming .env allowed"    "$(run_bash "sed -i 's/.env.example/.env.sample/' README.md")"
expect_allow "bash: unquoted sed script naming .env allowed"  "$(run_bash 'sed -i s/.env.example/.env.sample/ README.md')"
expect_allow "bash: heredoc body mentioning > .env allowed"   "$(run_bash 'cat <<DOC > out.txt
PORT=3000 > .env is just text
DOC')"
expect_block "bash: heredoc INTO .env still blocked"          "$(run_bash 'cat <<DOC > .env
K=v
DOC')"
expect_block "bash: quoted redirect target blocked"           "$(run_bash 'echo k > ".env"')"
expect_block "bash: single-quoted redirect target blocked"    "$(run_bash "echo k > '.env'")"
expect_block "bash: intra-word-quoted target blocked"         "$(run_bash 'echo k > .e""nv')"
expect_block "bash: backslash-escaped target blocked"         "$(run_bash 'echo k > .e\nv')"

# safety.json bypass applies to the Bash branch too
cd "$TMPDIR_BASE/proj-bypass" || exit 1
expect_allow "bash: bypass write-env honored"             "$(run_bash 'echo K=v > .env')"
expect_block "bash: bypass unrelated pattern still blocks" "$(run_bash 'cp x.pem server.pem')"
cd "$TMPDIR_BASE" || exit 1

# ===== Bash branch: additional write vectors (truncate/shred/install/rsync/ln -f) =====
expect_block "bash: truncate -s 0 .env blocked"          "$(run_bash 'truncate -s 0 .env')"
expect_block "bash: shred server.pem blocked"            "$(run_bash 'shred -u server.pem')"
expect_block "bash: install into credentials.json blocked" "$(run_bash 'install -m 600 src config/credentials.json')"
expect_block "bash: rsync onto secrets.yaml blocked"     "$(run_bash 'rsync -a a.txt secrets.yaml')"
expect_block "bash: ln -sf over .env blocked"            "$(run_bash 'ln -sf real .env')"
# Allowed: same tools targeting non-protected paths, and ln WITHOUT -f (won't clobber).
expect_allow "bash: truncate on a log file allowed"      "$(run_bash 'truncate -s 0 out.log')"
expect_allow "bash: shred a scratch tmp allowed"         "$(run_bash 'shred -u scratch.tmp')"
expect_allow "bash: rsync into a normal dir allowed"     "$(run_bash 'rsync -a src/ dest/')"
expect_allow "bash: ln -s (no -f) allowed"               "$(run_bash 'ln -s real link')"
# install -t DIR: the trailing token is a SOURCE (read), not the destination.
expect_allow "bash: install -t DIR (source not flagged) allowed" "$(run_bash 'install -t config src.pem')"

# ===== T0 #3/#4 (2026-08-07 audit): a trailing token after the real
# destination must not displace it in the "last non-flag token" scan —
# 2>/dev/null is the single most common shell idiom, so this is reachable by
# accident, not only adversarially. =====
expect_block "bash: cp onto .env with trailing 2>/dev/null blocked"   "$(run_bash 'cp .env.example .env 2>/dev/null')"
expect_block "bash: mv onto server.pem with trailing 2>&1 blocked"    "$(run_bash 'mv new.pem server.pem 2>&1')"
expect_block "bash: install into credentials.json with trailing 2>/dev/null blocked" \
  "$(run_bash 'install -m 600 src config/credentials.json 2>/dev/null')"
expect_block "bash: rsync onto secrets.yaml with trailing 2>/dev/null blocked" \
  "$(run_bash 'rsync -a a.txt secrets.yaml 2>/dev/null')"
expect_block "bash: ln -sf over .env with trailing 2>/dev/null blocked" "$(run_bash 'ln -sf real .env 2>/dev/null')"
expect_block "bash: ed onto .env with trailing stdin redirect blocked" \
  "$(run_bash 'ed .env < /tmp/patch.txt')"
expect_block "bash: sponge onto .env with trailing stdin redirect blocked" \
  "$(run_bash 'sponge .env < /tmp/in')"
# Controls: same trailing-token shapes onto a non-protected destination allow.
expect_allow "bash: cp onto a normal file with trailing 2>/dev/null allowed" \
  "$(run_bash 'cp src.txt out.txt 2>/dev/null')"
expect_allow "bash: ed onto a normal file with trailing stdin redirect allowed" \
  "$(run_bash 'ed out.txt < /tmp/patch.txt')"

# ===== Bash branch: spaced-tag heredoc body is DATA (no false block) =====
# `<< EOF` (space before the tag) must be recognized so its body is dropped —
# else a doc heredoc mentioning `cmd > .env` would hard-block.
expect_allow "bash: spaced-tag heredoc body mentioning > .env allowed" "$(run_bash 'cat << DOC > out.txt
PORT=3000 > .env is just text
DOC')"
expect_block "bash: spaced-tag heredoc INTO .env still blocked"        "$(run_bash 'cat << DOC > .env
K=v
DOC')"

# ===== Bash branch: interpreter indirection must be inspected =====
# `sh -c "<payload>"` and `eval "<payload>"` hand <payload> to a shell as a
# COMMAND, so the guard extracts it before the quote scrub and re-runs on it.
expect_block "bash: sh -c redirect into .env blocked"    "$(run_bash 'sh -c "echo K=v > .env"')"
expect_block "bash: bash -lc tee into .env blocked"      "$(run_bash "bash -lc 'echo K=v | tee .env'")"
expect_block "bash: eval redirect into .env blocked"     "$(run_bash 'eval "echo K=v > .env"')"
expect_block "bash: eval cp onto a lockfile blocked"     "$(run_bash "eval 'cp new.json package-lock.json'")"
expect_block "bash: eval nested in sh -c blocked"        "$(run_bash $'sh -c "eval \'echo K=v > .env\'"')"
# No false positives: benign payloads, and the dangerous form MENTIONED as data.
expect_allow "bash: sh -c benign command allowed"        "$(run_bash 'sh -c "echo hello"')"
expect_allow "bash: eval benign command allowed"         "$(run_bash 'eval "echo hello"')"
expect_allow "bash: eval ssh-agent idiom allowed"        "$(run_bash 'eval "$(ssh-agent -s)"')"
expect_allow "bash: prose mentioning eval write to .env allowed" \
  "$(run_bash 'echo "never run eval echo K=v > .env here"')"

# ===== Bash branch: interpreter-mediated writes =====
# An interpreter's file write is never shell syntax, so the redirection/tee/sed
# vectors above never see it. The guard scans the raw command for the
# conjunction interpreter + write op + protected target.
expect_block "bash: python3 -c open(.env,'w') blocked"   "$(run_bash "python3 -c \"open('.env','w').write('K=v')\"")"
expect_block "bash: python3 pathlib write_text blocked"  "$(run_bash "python3 -c \"from pathlib import Path; Path('.env').write_text('K=v')\"")"
expect_block "bash: node writeFileSync(.env) blocked"    "$(run_bash "node -e \"require('fs').writeFileSync('.env','K=v')\"")"
expect_block "bash: node appendFileSync onto a key blocked" "$(run_bash "node -e \"require('fs').appendFileSync('server.key','x')\"")"
expect_block "bash: perl 3-arg open onto .env blocked"   "$(run_bash "perl -e 'open(F, \">\", \".env\"); print F \"K=v\";'")"
expect_block "bash: ruby File.write onto a lockfile blocked" "$(run_bash "ruby -e \"File.write('package-lock.json','{}')\"")"
expect_block "bash: php file_put_contents onto .env blocked" "$(run_bash "php -r \"file_put_contents('.env','K=v');\"")"
expect_block "bash: awk print redirected into .env blocked"  "$(run_bash "awk 'BEGIN{print \"K=v\" > \".env\"}'")"
expect_block "bash: awk printf appended to a .pem blocked"   "$(run_bash "awk 'BEGIN{printf \"x\" >> \"cert.pem\"}'")"
expect_block "bash: python var target resolved to .env blocked" "$(run_bash "F=.env; python3 -c \"open('\$F','w').write('K=v')\"")"
expect_block "bash: python unresolvable target near .env blocked" "$(run_bash "python3 -c \"p='.env'; open(p,'w').write('K=v')\"")"

# ===== pathlib bound through a variable on an earlier line (real reproducer) =====
# `p = pathlib.Path("<lit>")` on one line, then `p.write_text(...)` on a LATER
# one, is not the adjacent `Path("<lit>").write_text(...)` shape any vector
# above resolves. Before assignment-following, the resolver gave up
# (unresolved=10) and the caller fell back to treating every path-shaped TOKEN
# in the whole heredoc body as a candidate target — so a markdown BODY merely
# mentioning a protected-looking phrase ("... 5856 with binding.key") got read
# as the write target and blocked a write to an unrelated, unprotected file.
# lib/write-vectors.sh §_geniro_wv_resolve_pathlib_var follows the assignment
# instead, the same move _geniro_wv_resolve already makes for a shell $VAR.
expect_allow "bash: pathlib var bound to a normal path, prose mentions a protected-looking token, allowed" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("notes/out.md")
s = "5856 with binding.key"
p.write_text(s)
PY')"
# The narrowing must not become a hole: a variable bound to a genuinely
# protected literal, then written through, still blocks — by resolving to the
# real target instead of by the blanket fallback firing on stray text.
expect_block "bash: pathlib var bound to .env by an earlier assignment, still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path(".env")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var bound to a .pem by an earlier assignment, still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
key_path = pathlib.Path("server.pem")
key_path.write_bytes(b"K")
PY')"

# ===== last-binding-wins bypass (real regression) =====
# The resolver used to take the LAST literal binding of <ident> and the caller
# treated "resolved" as "no longer unresolved" — so a script that rebinds the
# identifier after the protected literal resolved to the decoy and the real
# target never became a candidate. Ordinary source order, not adversarial:
# `p = Path(".env"); p.write_text(a); p = Path("out.txt"); p.write_text(b)`.
# All-or-nothing fixes it: every literal binding of <ident> is now a
# candidate, so the earlier .env binding is never dropped just because a
# later statement rebinds the same name.
expect_block "bash: pathlib var rebound after a protected literal binding, still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path(".env")
p.write_text(a)
p = pathlib.Path("out.txt")
p.write_text(b)
PY')"
# A rebind that mixes a protected literal binding with a later NON-literal one
# (`os.environ[...]`) cannot be resolved to a single safe answer — the runtime
# value of the second binding is unknowable from the command text — so the
# resolver forces unresolved and the caller's blanket fallback (every
# path-shaped token in the command) catches the .env mention instead.
expect_block "bash: pathlib var rebound to a non-literal after a protected literal, still blocked" \
  "$(run_bash 'python3 - <<PY
import os, pathlib
p = pathlib.Path(".env")
p = pathlib.Path(os.environ["X"])
p.write_text("K=v")
PY')"
# A call's keyword argument (`log(p="notes.txt")`) is not an assignment — the
# assignment match is anchored to a statement boundary so `(` can never open
# one — and must not resolve <ident> to the kwarg's value while the real,
# non-literal binding two lines down is what actually reaches write_text.
expect_block "bash: keyword argument does not masquerade as a pathlib var binding" \
  "$(run_bash 'python3 - <<PY
import pathlib
def log(**kw): pass
log(p="notes.txt")
target = ".env"
p = pathlib.Path(target)
p.write_text("K=v")
PY')"
# Control: a pathlib var written through .open() WITH a write mode must still
# block — the read-mode carve-out just below must not swallow this shape.
expect_block "bash: pathlib var written through .open('w') still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path(".env")
p.open("w").write("x")
PY')"

# ===== RHS whitelist (second-round fix): a binding resolves to a literal ONLY
# when the RHS is EXACTLY a path literal, tail-anchored — every shape below
# APPENDS something after the literal, so under the old start-anchored-only
# match each one resolved to the wrong (safe) prefix and silently dropped the
# real protected target. Every idiomatic pathlib join/derive spelling must
# still block. =====
expect_block "bash: pathlib var Path(dir) / protected literal still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("safe") / ".env"
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var Path(dir).joinpath(protected) still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("safe").joinpath(".env")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var augmented-assigned onto a protected literal still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("safe")
p /= ".env"
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var .with_name(protected) still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("out.txt").with_name(".env")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var .with_suffix(protected-ext) still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("x.txt").with_suffix(".pem")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var .parent / protected literal still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("a/b").parent / ".env"
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var ternary onto a protected literal still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
c = False
p = pathlib.Path("out.txt") if c else pathlib.Path(".env")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var string-concatenated onto a protected literal still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("." + "/.env")
p.write_text("K=v")
PY')"
expect_block "bash: pathlib var literal binding split by a backslash continuation still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("safe") \
    / ".env"
p.write_text("K=v")
PY')"
# The narrowing must not become the ORIGINAL false positive: `.resolve()` and
# `.expanduser()` narrow/normalize the SAME path rather than compute a new
# one, so a binding through either must still resolve to a literal.
expect_allow "bash: pathlib var Path(lit).resolve() still allowed (FP relief)" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("notes/out.md").resolve()
p.write_text("K=v")
PY')"
expect_allow "bash: pathlib var Path(lit).expanduser() still allowed (FP relief)" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path("notes/out.md").expanduser()
p.write_text("K=v")
PY')"

# ===== unresolved gate extended to .touch()/.open(write-mode) =====
# Only write_text/write_bytes used to set the unresolved flag on a failed
# pathlib-var resolution, so an unresolvable `p.touch()`/`p.open('w')` yielded
# zero candidates AND no fallback — a silent allow.
expect_block "bash: pathlib var .touch() with unresolvable target still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
d = ".env"
p = pathlib.Path(d)
p.touch()
PY')"
expect_block "bash: pathlib var .open(write mode) with unresolvable target still blocked" \
  "$(run_bash 'python3 - <<PY
import pathlib
d = ".env"
p = pathlib.Path(d)
p.open("w")
PY')"
expect_allow "bash: pathlib var .open() default mode with unresolvable target stays a read" \
  "$(run_bash 'python3 - <<PY
import pathlib
d = ".env"
p = pathlib.Path(d)
p.open().read()
PY')"

# ===== pathlib var .open() with no write mode is a READ, not a write =====
# `p.open()` defaults to mode "r" exactly like the builtin open(); the
# identifier-capture grep used to match `.open(` unconditionally, so a plain
# read through a pathlib var bound to a protected path was flagged as a write.
expect_allow "bash: pathlib var read through .open() (default mode) allowed" \
  "$(run_bash 'python3 - <<PY
import pathlib
p = pathlib.Path(".env")
print(p.open().read())
PY')"

# No false positives: read-only interpreter calls, and writes elsewhere.
expect_allow "bash: python3 reading .env allowed"        "$(run_bash "python3 -c \"print(open('.env').read())\"")"
expect_allow "bash: node console.log allowed"           "$(run_bash "node -e \"console.log(1+1)\"")"
expect_allow "bash: awk printing a field allowed"       "$(run_bash "awk '{print \$1}' .env")"
expect_allow "bash: awk numeric compare allowed"        "$(run_bash "awk '{print (a > b) ? 1 : 2}' .env")"
expect_allow "bash: python writing a normal file allowed" "$(run_bash "python3 -c \"open('out.txt','w').write('x')\"")"
expect_allow "bash: running a python script allowed"    "$(run_bash 'python3 manage.py migrate')"
expect_allow "bash: node reading .env allowed"          "$(run_bash "node -e \"console.log(require('fs').readFileSync('.env','utf8'))\"")"

# ===== NotebookEdit form is guarded (notebook_path, not file_path) =====
run_notebookedit() {
  jq -nc --arg p "$1" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p, new_source: "x = 1"}}' | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "NotebookEdit to .env blocked"          "$(run_notebookedit /proj/.env)"
expect_block "NotebookEdit to a .pem blocked"        "$(run_notebookedit /proj/server.pem)"
expect_allow "NotebookEdit to a normal notebook allows" "$(run_notebookedit /proj/analysis.ipynb)"

# ===== jq-less fail-closed scan: the coarse raw name check still blocks =====
# The guard's whole role is preventing credential clobber, so it does NOT fail
# fully open when jq is missing — it scans the path/command FIELDS textually and
# blocks the highest-signal protected names. Everything else fails open. FAKEBIN
# holds symlinks to every tool the fallback needs except jq.
FAKEBIN="$TMPDIR_BASE/nojq-bin"
mkdir -p "$FAKEBIN"
for _t in cat grep sed awk tr head printf env bash sh; do
  _s="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_s" "$FAKEBIN/$_t"
done
run_write_nojq() {  # <path>
  printf '{"tool_input":{"file_path":"%s","content":"x"}}' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
run_bash_nojq() {  # <command>
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "jqless: write to .env still blocked"        "$(run_write_nojq /proj/.env)"
expect_block "jqless: write to a .pem still blocked"      "$(run_write_nojq /proj/server.pem)"
expect_block "jqless: write to credentials.json blocked"  "$(run_write_nojq /proj/credentials.json)"
expect_block "jqless: bash redirect to .env blocked"      "$(run_bash_nojq 'echo x > .env')"
expect_block "jqless: notebook_path .env blocked"         "$(printf '{"tool_input":{"notebook_path":"/proj/.env"}}' | PATH="$FAKEBIN" bash "$HOOK" >/dev/null 2>&1; echo $?)"
# Outside the coarse name set the guard fails OPEN — a lockfile is protected only
# on the full jq path, and the allowlist itself needs jq to read.
expect_allow "jqless: lockfile fails open"                "$(run_write_nojq /proj/package-lock.json)"
expect_allow "jqless: normal source fails open"           "$(run_bash_nojq 'echo x > src/app.js')"

# ===== Fail-open on missing file_path =====
expect_allow "missing file_path → allow" "$(echo '{"tool_input": {}}' | bash "$HOOK" >/dev/null 2>&1; echo $?)"

# ===== jq PRESENT but payload MALFORMED: must still fail-closed on a raw scan =====
# Distinct from the jqless section above (jq absent, well-formed JSON). Here jq is
# on PATH but the JSON itself is truncated, so TOOL_NAME (:58) and FILE_PATH both
# parse empty and neither the Bash branch nor the Edit branch ever fires — this is
# the input class finding #1 covers.
run_raw() {  # <raw-payload-text>
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
  echo $?
}
expect_block "malformed payload naming .env still blocked" \
  "$(run_raw '{"tool_name":"Bash","tool_input":{"command":"echo hi > .env"')"
expect_allow "malformed payload with no protected name allows" \
  "$(run_raw '{"tool_name":"Bash","tool_input":{"command":"echo hello"')"

# ===== T0-1: `pushd` reaches the same builtin `cd` does and must not evade =====
# `pushd .git && echo x > config` spelled no `.git` path in the redirect
# target at all, yet wrote exactly where `echo x > .git/config` would.
expect_block "bash: pushd .git && echo x > config blocked" \
  "$(run_bash 'pushd .git && echo x > config')"
expect_block "bash: cd .git && echo x > config still blocked" \
  "$(run_bash 'cd .git && echo x > config')"
# `pushd -n` (suppress directory-stack printing) must not be read as the target.
expect_block "bash: pushd -n .git && echo x > HEAD blocked" \
  "$(run_bash 'pushd -n .git && echo x > HEAD')"
expect_allow "bash: pushd into a non-.git dir allowed" \
  "$(run_bash 'pushd src && echo x > app.js')"

# ===== T1-1: a newline must not let one line's content leak into another's span =====
# Newlines used to be collapsed to spaces before the write-vector extraction,
# so a benign command on one line and an unrelated write on the next read as
# ONE span — a read (`cat`) that merely MENTIONS a protected name on one line
# must not block an unrelated write on a different line.
expect_allow "bash: cp then cat .env (newline) allowed" \
  "$(run_bash $'cp a.txt b.txt\ncat .env')"
expect_block "bash: real write to .env on line 1 (newline) still blocked" \
  "$(run_bash $'echo x > .env\necho done')"
expect_block "bash: real write to .env on line 2 (newline) still blocked" \
  "$(run_bash $'echo done\necho x > .env')"

# ===== T2: a shell $VAR rebound before the write, not just a single binding =====
# `_geniro_wv_expand_assignments` used to substitute ONE winning value for a
# rebound identifier — whichever assignment its substitution pass reached
# first, an accident of the sort order with no relationship to what the shell
# would actually run — so `F=out.txt; F=.env; printf x > "$F"` resolved `$F`
# to "out.txt" and the write to the real, live value (.env) was never checked.
# lib/write-vectors.sh §F now rewrites an identifier bound to two or more
# DISTINCT literals (or ever bound non-literally) to an inert sentinel instead
# of guessing; this guard's own `add_candidate` recognizes that sentinel and
# falls back to every literal binding in the command, the same move the
# unresolved-interpreter-target branch already makes.
expect_block "bash: \$VAR rebound benign-then-protected, still blocked" \
  "$(run_bash 'F=out.txt; F=".env"; printf x > "$F"')"
# Decision: a rebind is ALWAYS treated as ambiguous, even when the FINAL
# value is provably benign — this mirrors _geniro_wv_resolve_pathlib_var's
# ALL-OR-NOTHING rule (any rebind forces the conservative path) rather than
# trying to track which assignment is "live" at the one read site. A regex
# scan over raw text has no control-flow visibility (an intervening `if`
# could make either binding the one that actually ran), so re-deriving
# "last assignment wins" here would silently reopen the exact bypass this fix
# closes the moment the rebind sits inside a conditional. The one-time cost
# is a rebind-to-benign pattern landing in the conservative token fallback
# instead of resolving cleanly — cheap next to a live write to a protected
# path going unchecked.
expect_block "bash: \$VAR rebound protected-then-benign is STILL conservative (not last-wins)" \
  "$(run_bash 'F=".env"; F=out.txt; printf x > "$F"')"
# Rebinding to a NON-literal (a command substitution) after a literal binding
# taints the identifier exactly like a second literal binding does — the
# scanner cannot evaluate `$(...)`, so the value actually live at the read
# site is unknowable from the text either way.
expect_block "bash: \$VAR literal-then-non-literal rebind, still blocked" \
  "$(run_bash 'F=".env"; F=$(echo out.txt); printf x > "$F"')"
# The SAME literal value bound twice is not a rebind — no ambiguity, no
# fallback, ordinary idempotent shell stays exactly as fast/precise as before.
expect_block "bash: \$VAR bound twice to the SAME protected literal, still blocked" \
  "$(run_bash 'F=".env"; F=".env"; printf x > "$F"')"
expect_allow "bash: \$VAR bound twice to the SAME benign literal, still allowed" \
  "$(run_bash 'F=out.txt; F=out.txt; printf x > "$F"')"
# Ordinary single-binding shell — the common case — must resolve cleanly and
# stay allowed; this is the false-positive check this fix must not regress.
expect_allow "bash: ordinary single-binding \$VAR redirect allowed" \
  "$(run_bash 'OUT=build/out.txt; echo x > "$OUT"')"
expect_allow "bash: \$VAR from a command substitution, unrelated to any protected name, allowed" \
  "$(run_bash 'TMP=$(mktemp); echo x > "$TMP"')"
expect_allow "bash: \$VAR rebound but only ever READ, not written, allowed" \
  "$(run_bash 'F=a.txt; F=b.txt; cat "$F"')"

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
