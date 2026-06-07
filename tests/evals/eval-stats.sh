#!/usr/bin/env bash
# Unit tests for evals/lib/eval-stats.sh — the single-sourced eval statistics math
# (plan §8/§9, decision 4/15). The ledger's CIs must be correct AND reproducible:
# a committed scorecard whose CI jiggles per re-ingest is worse than no CI.
#
# Run: bash tests/evals/eval-stats.sh   (auto-discovered by tests/run-all.sh)
# Exits non-zero on any failure.
#
# Plugin-developer / eval tooling only — not shipped to user projects.
#
# Contract under test (mirrors lib/score-formula.sh's "sourced jq-defs var"):
#   sourcing the lib exposes $GENIRO_EVAL_STATS_JQ_DEFS, a jq program prologue that
#   defines:
#     wilson_ci($k; $n; $z)              -> [lo, hi]   single-proportion CI (pass_rate, precision)
#     bootstrap_ci($vec; $B; $seed; $lq; $hq) -> [lo, hi]  task-clustered bootstrap (winrate, pass^k)
#     _quantile($sorted; $q)             -> number      type-7 interpolated quantile
#     mean($vec)                         -> number|null
#   Proportions use Wilson; winrate/ratios/pass^k use the bootstrap; the bootstrap
#   is seeded so the same (vec, B, seed) is byte-identical across calls (plan §8).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/evals/lib/eval-stats.sh"

TESTS_RUN=0
TESTS_FAILED=0
pass() { TESTS_RUN=$((TESTS_RUN + 1)); echo "PASS: $1"; }
fail() { TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1)); echo "FAIL: $1" >&2; }

# Evaluate a jq program with the stats defs prepended. Args after the program are
# passed through verbatim (e.g. --argjson).
sj() {
  local prog="$1"; shift
  jq -cn "$@" "$GENIRO_EVAL_STATS_JQ_DEFS $prog"
}

# Float predicate via awk: `fcmp "<lo> < 0.72 && <lo> > 0.70"` already-substituted expr.
fcmp() { awk "BEGIN{ exit !($1) }"; }

# ===== Wilson: known value (k=80, n=100, 95%) ≈ [0.7112, 0.8665] =====
lo=$(sj 'wilson_ci(80;100;1.959963985)[0]')
hi=$(sj 'wilson_ci(80;100;1.959963985)[1]')
if fcmp "$lo > 0.705 && $lo < 0.717" && fcmp "$hi > 0.860 && $hi < 0.872"; then
  pass "wilson_ci(80,100,95%) ≈ [0.711, 0.867] (got [$lo, $hi])"
else
  fail "wilson_ci(80,100) wrong — got [$lo, $hi], expected ≈ [0.711, 0.867]"
fi

# ===== Wilson: n=0 → [null, null] (no crash on empty) =====
res=$(sj 'wilson_ci(0;0;1.959963985)')
if [ "$res" = "[null,null]" ]; then
  pass "wilson_ci with n=0 → [null,null]"
else
  fail "wilson_ci(0,0) should be [null,null], got $res"
fi

# ===== Wilson: perfect proportion (k=n) clamps hi at 1, lo<1 =====
lo=$(sj 'wilson_ci(10;10;1.959963985)[0]')
hi=$(sj 'wilson_ci(10;10;1.959963985)[1]')
if [ "$hi" = "1" ] && fcmp "$lo < 1 && $lo > 0.65"; then
  pass "wilson_ci(10,10) clamps hi=1, lo<1 (got [$lo, $hi])"
else
  fail "wilson_ci(10,10) clamp wrong — got [$lo, $hi]"
fi

# ===== Wilson: bounds are ordered and contain the point estimate =====
lo=$(sj 'wilson_ci(3;10;1.959963985)[0]')
hi=$(sj 'wilson_ci(3;10;1.959963985)[1]')
if fcmp "$lo < 0.3 && $hi > 0.3 && $lo >= 0"; then
  pass "wilson_ci(3,10) brackets p=0.3 with lo≥0 (got [$lo, $hi])"
else
  fail "wilson_ci(3,10) does not bracket 0.3 — got [$lo, $hi]"
fi

# ===== _quantile: median / extremes / interpolation on [1..5] =====
med=$(sj '_quantile([1,2,3,4,5];0.5)')
q0=$(sj '_quantile([1,2,3,4,5];0)')
q1=$(sj '_quantile([1,2,3,4,5];1)')
q25=$(sj '_quantile([1,2,3,4,5];0.25)')
if [ "$med" = "3" ] && [ "$q0" = "1" ] && [ "$q1" = "5" ] && [ "$q25" = "2" ]; then
  pass "_quantile on [1..5]: q0=1 q25=2 q50=3 q100=5"
else
  fail "_quantile wrong — q0=$q0 q25=$q25 q50=$med q100=$q1"
fi

# ===== mean: basic + empty =====
m=$(sj 'mean([1,2,3,4])')
mempty=$(sj 'mean([])')
if [ "$m" = "2.5" ] && [ "$mempty" = "null" ]; then
  pass "mean([1,2,3,4])=2.5, mean([])=null"
else
  fail "mean wrong — got $m and $mempty"
fi

# ===== bootstrap: REPRODUCIBLE — same (vec,B,seed) is byte-identical =====
a=$(sj 'bootstrap_ci([0.6,0.7,0.8,0.9,1.0];2000;12345;0.025;0.975)')
b=$(sj 'bootstrap_ci([0.6,0.7,0.8,0.9,1.0];2000;12345;0.025;0.975)')
if [ "$a" = "$b" ] && [ "$a" != "null" ]; then
  pass "bootstrap_ci is reproducible for a fixed seed (got $a)"
else
  fail "bootstrap_ci NOT reproducible — '$a' vs '$b'"
fi

# ===== bootstrap: zero-variance vector → degenerate CI [v, v] =====
zc=$(sj 'bootstrap_ci([0.8,0.8,0.8,0.8];3000;777;0.025;0.975)')
if [ "$zc" = "[0.8,0.8]" ]; then
  pass "bootstrap_ci of a constant vector → [0.8,0.8] (no spurious spread)"
else
  fail "bootstrap_ci constant vector should be [0.8,0.8], got $zc"
fi

# ===== bootstrap: brackets the sample mean and stays within data range =====
lo=$(sj 'bootstrap_ci([0.6,0.7,0.8,0.9,1.0];5000;42;0.025;0.975)[0]')
hi=$(sj 'bootstrap_ci([0.6,0.7,0.8,0.9,1.0];5000;42;0.025;0.975)[1]')
# sample mean = 0.8; resample means must lie within [0.6, 1.0]
if fcmp "$lo < 0.8 && $hi > 0.8 && $lo >= 0.6 && $hi <= 1.0"; then
  pass "bootstrap_ci brackets mean 0.8, stays in [0.6,1.0] (got [$lo, $hi])"
else
  fail "bootstrap_ci out of range — got [$lo, $hi]"
fi

# ===== bootstrap: degenerate lengths (0 and 1) =====
one=$(sj 'bootstrap_ci([0.42];1000;1;0.025;0.975)')
zero=$(sj 'bootstrap_ci([];1000;1;0.025;0.975)')
if [ "$one" = "[0.42,0.42]" ] && [ "$zero" = "[null,null]" ]; then
  pass "bootstrap_ci handles n=1 → [v,v] and n=0 → [null,null]"
else
  fail "bootstrap_ci degenerate lengths wrong — n1=$one n0=$zero"
fi

# ===== bootstrap: a clear-win winrate vector excludes the 0.5 null =====
# Every task favors candidate (>0.5); the lower CI bound must clear 0.5.
lo=$(sj 'bootstrap_ci([0.8,0.9,1.0,0.7,0.85,0.95];5000;2026;0.025;0.975)[0]')
if fcmp "$lo > 0.5"; then
  pass "bootstrap_ci lower bound of a clear-win vector clears 0.5 null (lo=$lo)"
else
  fail "bootstrap_ci lower bound should clear 0.5 — got lo=$lo"
fi

# ===== TEETH: resample draws are UNIFORM across an EVEN-length task vector =====
# The single decisive guard against the LCG low-bit bias: a power-of-2-modulus LCG reduced
# `% n` starved odd indices (drawn <1% of expected) for even n, silently corrupting every CI.
# Draw n=6 indices 60000× and assert each index is within ±20% of the 10000 expected.
draws=$(sj 'def hist($n;$B;$seed):
              reduce range(0;$B) as $i ({s:_lcg_seed($seed), c:[range(0;$n)|0]};
                (_lcg(.s)) as $ns | {s:$ns, c:(.c | .[_draw_index($ns;$n)] += 1)}) | .c;
            hist(6;60000;20260607)')
dmin=$(printf '%s' "$draws" | jq 'min'); dmax=$(printf '%s' "$draws" | jq 'max')
if fcmp "$dmin > 8000 && $dmax < 12000"; then
  pass "bootstrap draws are uniform over even n=6 (min=$dmin max=$dmax, expected ~10000)"
else
  fail "bootstrap draw bias on even n=6 — min=$dmin max=$dmax (LCG low-bit regression?)"
fi

# ===== TEETH: order-invariance — a correct bootstrap ignores task ORDER =====
# Same multiset, two orders, same seed → identical CI. The biased LCG gave opposite extremes.
ci_fwd=$(sj 'bootstrap_ci([0.9,0.1,0.9,0.1,0.9,0.1];5000;2026;0.025;0.975)')
ci_rev=$(sj 'bootstrap_ci([0.1,0.9,0.1,0.9,0.1,0.9];5000;2026;0.025;0.975)')
if [ "$ci_fwd" = "$ci_rev" ] && [ "$ci_fwd" != "[null,null]" ]; then
  pass "bootstrap_ci is order-invariant for a reordered multiset ($ci_fwd)"
else
  fail "bootstrap_ci is order-DEPENDENT — fwd=$ci_fwd rev=$ci_rev (LCG bias regression?)"
fi

# ===== TEETH: the CI must CONTAIN its own point estimate (even-n) =====
# vec mean = 0.5; the biased CI was [0.7667,0.9], excluding 0.5. A correct CI straddles it.
lo=$(sj 'bootstrap_ci([0.9,0.1,0.9,0.1,0.9,0.1];5000;2026;0.025;0.975)[0]')
hi=$(sj 'bootstrap_ci([0.9,0.1,0.9,0.1,0.9,0.1];5000;2026;0.025;0.975)[1]')
if fcmp "$lo <= 0.5 && $hi >= 0.5"; then
  pass "bootstrap_ci brackets its own mean 0.5 for an even-n tie vector (got [$lo, $hi])"
else
  fail "bootstrap_ci does NOT contain its point estimate 0.5 — got [$lo, $hi]"
fi

# ===== TEETH: the seed is actually consumed — different seeds → different CIs =====
# Guards against a refactor that silently drops the seed (the reproducibility test alone
# cannot distinguish a seed-honoring bootstrap from one that ignores the seed).
ci_s1=$(sj 'bootstrap_ci([0.1,0.9,0.2,0.8,0.0,1.0];4000;1;0.025;0.975)')
ci_s2=$(sj 'bootstrap_ci([0.1,0.9,0.2,0.8,0.0,1.0];4000;2;0.025;0.975)')
if [ "$ci_s1" != "$ci_s2" ]; then
  pass "bootstrap_ci honors the seed — distinct seeds give distinct CIs ($ci_s1 vs $ci_s2)"
else
  fail "bootstrap_ci ignores the seed — seed 1 and 2 gave identical $ci_s1"
fi

echo
echo "Tests run:    $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
