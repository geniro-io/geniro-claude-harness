#!/usr/bin/env bash
# Smoke test for the two Node hooks — the only hooks with no coverage at all,
# though geniro-check-update.js is a live mutator: it detaches a background
# child, shells out to curl twice, and writes a cache file under the user's
# config dir.
#
# Run: bash tests/hooks/js-hooks.sh
#
# Coverage:
#   geniro-check-update.js
#     - compareVersions across the ordering matrix, the sentinel/empty guards,
#       short version strings, and a non-numeric prerelease segment (a known
#       limitation, pinned so a future change to it is a deliberate one).
#     - The synchronous branch (GENIRO_UPDATE_BG=1) end-to-end against a temp
#       config dir with curl stubbed: cache written, fields correct.
#     - A failing fetch writes NO cache (a stale "up to date" is worse than none).
#   geniro-statusline.js
#     - The pure formatting helpers only (clip / fmtEta / visLen / justify /
#       modelLabel). The full render reads a transcript and the todo dir; it is
#       not pure and is deliberately out of scope here.
#
# Hermetic: the config dir, the fake plugin root and the curl stub all live in a
# mktemp sandbox, and PATH is prefixed with the stub — NO real network call is
# ever made. The detach-into-background branch is deliberately not exercised: it
# spawns a child that outlives the assertion and would race it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not available on this machine — nothing to verify."
  exit 0
fi

TMPDIR_BASE="$(mktemp -d)"
ORIGINAL_PWD="$PWD"
trap 'cd "$ORIGINAL_PWD"; rm -rf "$TMPDIR_BASE"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# ===== 1. Pure functions, lifted out of the hook sources =====
# Both hooks run their work at module load (one detaches a child, the other waits
# on stdin), so they cannot be `require`d. The functions under test are lifted
# from the source text and evaluated in an isolated scope instead — which also
# means a rename or a signature change fails loudly here rather than silently
# skipping the assertions.
cat > "$TMPDIR_BASE/pure.js" <<'NODEJS'
const fs = require('fs');
const path = require('path');

const HOOKS = process.argv[2];
let run = 0, failed = 0;
function ok(label, cond, detail) {
  run++;
  if (cond) console.log('PASS: ' + label);
  else { failed++; console.error('FAIL: ' + label + (detail ? ' — ' + detail : '')); }
}
function eq(label, got, want) {
  ok(label, Object.is(got, want), 'got ' + JSON.stringify(got) + ', want ' + JSON.stringify(want));
}

// A top-level `function name(...) { … }` ends at the first `\n}` after it — the
// convention both hooks follow. A miss throws rather than returning empty, so a
// renamed helper cannot silently drop its assertions.
function grabFn(src, name, file) {
  const start = src.indexOf('function ' + name + '(');
  if (start < 0) throw new Error('function ' + name + ' not found in ' + file);
  const end = src.indexOf('\n}', start);
  if (end < 0) throw new Error('unterminated function ' + name + ' in ' + file);
  return src.slice(start, end + 2);
}
function grabConst(src, name, file) {
  const re = new RegExp('^const ' + name + ' = .*$', 'm');
  const m = src.match(re);
  if (!m) throw new Error('const ' + name + ' not found in ' + file);
  return m[0];
}
function build(parts, exportName) {
  return new Function(parts.join('\n') + '\nreturn ' + exportName + ';')();
}

// ---- geniro-check-update.js: compareVersions ----
const CU = 'geniro-check-update.js';
const cuSrc = fs.readFileSync(path.join(HOOKS, CU), 'utf8');
const compareVersions = build([grabFn(cuSrc, 'compareVersions', CU)], 'compareVersions');

// compareVersions(installed, latest) === "an update is available".
eq('compareVersions: patch bump is an update',        compareVersions('5.0.1', '5.0.2'), true);
eq('compareVersions: minor bump is an update',        compareVersions('5.0.9', '5.1.0'), true);
eq('compareVersions: major bump is an update',        compareVersions('4.9.9', '5.0.0'), true);
eq('compareVersions: same version is not an update',  compareVersions('5.0.1', '5.0.1'), false);
eq('compareVersions: older remote is not an update',  compareVersions('5.1.0', '5.0.9'), false);
eq('compareVersions: missing segment reads as 0',     compareVersions('5.0', '5.0.1'), true);
eq('compareVersions: shorter remote is not an update', compareVersions('5.0.1', '5.0'), false);
// Guards — never offer an update the caller cannot reason about.
eq('compareVersions: unknown installed is never an update', compareVersions('unknown', '9.9.9'), false);
eq('compareVersions: empty installed is never an update',   compareVersions('', '9.9.9'), false);
eq('compareVersions: empty latest is never an update',      compareVersions('5.0.1', ''), false);

// KNOWN LIMITATION, pinned deliberately: segments go through Number(), so a
// prerelease suffix yields NaN and `(NaN || 0)` reads as 0.
//   - a prerelease INSTALLED version still sees the release as newer (correct);
//   - a prerelease LATEST version reads as older, so no update is offered.
// The second is wrong-but-quiet: it under-reports, never a false alarm and never
// a throw. Asserted so that changing it is a decision, not an accident.
eq('compareVersions: prerelease installed -> release is an update',
   compareVersions('5.1.2-rc1', '5.1.2'), true);
eq('compareVersions: prerelease LATEST is not offered (known limitation)',
   compareVersions('5.1.2', '5.1.3-rc1'), false);
ok('compareVersions: never throws on non-numeric input',
   (() => { try { compareVersions('abc', 'def'); return true; } catch { return false; } })());

// ---- geniro-statusline.js: pure formatting helpers ----
const SL = 'geniro-statusline.js';
const slSrc = fs.readFileSync(path.join(HOOKS, SL), 'utf8');
const clip       = build([grabFn(slSrc, 'clip', SL)], 'clip');
const fmtEta     = build([grabFn(slSrc, 'fmtEta', SL)], 'fmtEta');
const modelLabel = build([grabFn(slSrc, 'modelLabel', SL)], 'modelLabel');
const visLen     = build([grabConst(slSrc, 'AMBIGUOUS_WIDE', SL), grabFn(slSrc, 'visLen', SL)], 'visLen');
const justify    = build([
  grabConst(slSrc, 'AMBIGUOUS_WIDE', SL),
  grabConst(slSrc, 'spaces', SL),
  grabFn(slSrc, 'visLen', SL),
  grabFn(slSrc, 'justify', SL),
], 'justify');

eq('clip: collapses whitespace and trims',   clip('  a   b  ', 10), 'a b');
eq('clip: truncates with an ellipsis',       clip('abcdefghij', 5), 'abcd…');
eq('clip: leaves a short string alone',      clip('abc', 10), 'abc');

eq('fmtEta: zero is "now"',                  fmtEta(0), 'now');
eq('fmtEta: negative is "now"',              fmtEta(-30), 'now');
eq('fmtEta: sub-hour renders minutes',       fmtEta(90), '1m');
eq('fmtEta: over an hour renders h+m',       fmtEta(3720), '1h2m');
eq('fmtEta: exact hours keep the m field',   fmtEta(7200), '2h0m');

eq('visLen: plain ASCII',                    visLen('abc'), 3);
eq('visLen: ANSI colour codes are not width', visLen('\x1b[2mabc\x1b[0m'), 3);
eq('visLen: an emoji costs two columns',     visLen('👍'), 2);
// The ambiguous-wide set exists because these render double-width on some
// terminals and the over-wide line then gets its right edge truncated.
eq('visLen: an ellipsis is charged as wide', visLen('…'), 2);

eq('justify: pads to the target width',      justify('L', 'R', 10), 'L' + ' '.repeat(8) + 'R');
eq('justify: no right side returns the left', justify('L', '', 10), 'L');
eq('justify: too narrow degrades to a join', justify('LLLLL', 'RRRRR', 5), 'LLLLL RRRRR');

eq('modelLabel: a versioned display_name wins', modelLabel({ display_name: 'Opus 4.8', id: 'x' }), 'Opus 4.8');
eq('modelLabel: reconstructs from the id',      modelLabel({ id: 'claude-sonnet-4-5' }), 'Sonnet 4.5');
eq('modelLabel: carries the context window',    modelLabel({ id: 'claude-opus-4-8[1m]' }), 'Opus 4.8 (1M context)');
eq('modelLabel: falls back when nothing is known', modelLabel({}), 'Claude');

console.log('__RESULT__ ' + run + ' ' + failed);
NODEJS

pure_out=$(node "$TMPDIR_BASE/pure.js" "$REPO_ROOT/hooks" 2>&1)
pure_rc=$?
printf '%s\n' "$pure_out" | grep -v '^__RESULT__' || true
summary=$(printf '%s\n' "$pure_out" | grep '^__RESULT__' || true)
if [ -z "$summary" ]; then
  fail "pure-function harness did not complete (node rc=$pure_rc) — see output above"
else
  n_run=$(printf '%s' "$summary" | awk '{print $2}')
  n_failed=$(printf '%s' "$summary" | awk '{print $3}')
  TESTS_RUN=$((TESTS_RUN + n_run))
  TESTS_FAILED=$((TESTS_FAILED + n_failed))
fi

# ===== 2. geniro-check-update.js end-to-end, network stubbed =====
CFG="$TMPDIR_BASE/config"
PLUGIN="$TMPDIR_BASE/plugin"
STUB="$TMPDIR_BASE/stub"
mkdir -p "$CFG" "$PLUGIN/.claude-plugin" "$STUB"
echo '{"name":"geniro","version":"5.0.1"}' > "$PLUGIN/.claude-plugin/plugin.json"

# The hook shells out through `curl`; a stub earlier on PATH intercepts both the
# release-API call and the raw-plugin.json fallback.
write_curl_stub() {  # <exit-code> <stdout>
  cat > "$STUB/curl" <<EOF
#!/bin/sh
printf '%s' '$2'
exit $1
EOF
  chmod +x "$STUB/curl"
}

CACHE="$CFG/cache/geniro-update-check.json"

write_curl_stub 0 '{"tag_name":"v9.9.9"}'
rm -f "$CACHE"
GENIRO_UPDATE_BG=1 CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$STUB:$PATH" node "$REPO_ROOT/hooks/geniro-check-update.js" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$CACHE" ]; then
  got=$(node -e '
    const c = require(process.argv[1]);
    console.log([c.installed, c.latest, c.update_available, typeof c.checked].join("|"));
  ' "$CACHE" 2>&1)
  if [ "$got" = "5.0.1|9.9.9|true|number" ]; then
    pass "check-update: writes the cache under CLAUDE_CONFIG_DIR with installed/latest/update_available/checked"
  else
    fail "check-update cache contents — got '$got' (expected '5.0.1|9.9.9|true|number')"
  fi
else
  fail "check-update: no cache written (rc=$rc, cache-exists=$([ -f "$CACHE" ] && echo y || echo n))"
fi

# The tag is normalized: the API returns "v9.9.9", the cache must not.
if [ -f "$CACHE" ] && ! grep -q '"latest": *"v' "$CACHE"; then
  pass "check-update: strips the leading v from the release tag"
else
  fail "check-update: release tag reached the cache unnormalized"
fi

# An already-current install must record update_available:false, not just omit it.
write_curl_stub 0 '{"tag_name":"v5.0.1"}'
rm -f "$CACHE"
GENIRO_UPDATE_BG=1 CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$STUB:$PATH" node "$REPO_ROOT/hooks/geniro-check-update.js" >/dev/null 2>&1
if [ -f "$CACHE" ] && node -e 'process.exit(require(process.argv[1]).update_available === false ? 0 : 1)' "$CACHE" 2>/dev/null; then
  pass "check-update: an up-to-date install records update_available:false"
else
  fail "check-update: up-to-date install did not record update_available:false"
fi

# Both fetch attempts fail → no version is known, so nothing is written. A stale
# cache left behind would be reported to the user as current.
write_curl_stub 22 ''
rm -f "$CACHE"
GENIRO_UPDATE_BG=1 CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$STUB:$PATH" node "$REPO_ROOT/hooks/geniro-check-update.js" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$CACHE" ]; then
  pass "check-update: a failing fetch exits 0 and writes no cache"
else
  fail "check-update failing-fetch path; rc=$rc cache-exists=$([ -f "$CACHE" ] && echo y || echo n) (expect 0/n)"
fi

# An unreadable plugin manifest must not crash the hook — the version degrades to
# the "unknown" sentinel, which compareVersions already refuses to act on.
write_curl_stub 0 '{"tag_name":"v9.9.9"}'
rm -f "$CACHE"
GENIRO_UPDATE_BG=1 CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PLUGIN_ROOT="$TMPDIR_BASE/no-such-plugin" \
  PATH="$STUB:$PATH" node "$REPO_ROOT/hooks/geniro-check-update.js" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$CACHE" ] \
   && node -e 'const c = require(process.argv[1]); process.exit(c.installed === "unknown" && c.update_available === false ? 0 : 1)' "$CACHE" 2>/dev/null; then
  pass "check-update: a missing plugin manifest degrades to installed:unknown, no update offered"
else
  fail "check-update missing-manifest path; rc=$rc cache-exists=$([ -f "$CACHE" ] && echo y || echo n)"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
