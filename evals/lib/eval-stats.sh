#!/usr/bin/env bash
# evals/lib/eval-stats.sh — single source of truth for the eval pipeline's statistics math.
#
# Mirrors lib/score-formula.sh's contract: source this file, then prepend
# "$GENIRO_EVAL_STATS_JQ_DEFS" to any jq program that needs the estimators. Keeping the
# math in one jq-defs string is what guarantees ingest.sh and /geniro:eval (Phase D) can
# never drift on HOW a CI is computed — they share the definitions, not a re-derivation.
#
# Why these specific estimators (plan §8/§9, decision 4):
#   - PROPORTIONS (pass_rate, precision, recall_at1) → Wilson score interval. The right
#     family for a bounded Bernoulli quantity; v3's t-interval@df=n-1 was wrong and is gone.
#   - WINRATE / RATIOS / pass^k → a task-clustered bootstrap. The TASK is the unit of
#     randomization (between-task variance dominates), so the bootstrap resamples the vector
#     of per-task means — NOT pooled trials, which would give a deceptively narrow CI.
#   - The bootstrap is SEEDED via a self-contained LCG so the committed ledger's CI is
#     reproducible: re-ingesting the same benchmark.json yields a byte-identical interval.
#     A CI that jiggles per run would undermine a committed scorecard.
#
# Plugin-developer / eval tooling only — NOT shipped to user projects, NOT loaded by any skill.

# Default 95% two-sided z. Single-sourced so callers don't sprinkle magic numbers.
# shellcheck disable=SC2034  # consumed by callers that source this file
: "${GENIRO_EVAL_Z95:=1.959963985}"

# shellcheck disable=SC2034  # consumed by callers that source this file
GENIRO_EVAL_STATS_JQ_DEFS='
  # Arithmetic mean of an array; null on empty (no division by zero).
  def mean($vec):
    if ($vec | length) == 0 then null else ($vec | add) / ($vec | length) end;

  # Wilson score interval for $k successes in $n trials at z-multiplier $z.
  # Returns [lo, hi] clamped to [0, 1]; [null, null] when $n == 0.
  def wilson_ci($k; $n; $z):
    if $n == 0 then [null, null]
    else
      ($k / $n) as $p
      | ($z * $z) as $z2
      | (1 + $z2 / $n) as $den
      | (($p + $z2 / (2 * $n)) / $den) as $center
      | ( ($z / $den) * ( ( ($p * (1 - $p)) / $n + $z2 / (4 * $n * $n) ) | sqrt ) ) as $half
      | [ ([$center - $half, 0] | max), ([$center + $half, 1] | min) ]
    end;

  # Type-7 (linear-interpolation) quantile of a PRE-SORTED ascending array.
  def _quantile($sorted; $q):
    ($sorted | length) as $m
    | if $m == 0 then null
      elif $m == 1 then $sorted[0]
      else
        ($q * ($m - 1)) as $pos
        | ($pos | floor) as $lo
        | ($pos - $lo) as $frac
        | if ($lo + 1) < $m then ($sorted[$lo] * (1 - $frac) + $sorted[$lo + 1] * $frac)
          else $sorted[$lo] end
      end;

  # MINSTD (Lehmer) PRNG — pure multiplicative: modulus m = 2^31-1 (prime), multiplier a = 48271.
  # CRITICAL: a*state ~= 2^46.6 stays < 2^53, so the modular arithmetic is EXACT in the jq double
  # domain. A power-of-2-modulus LCG (a*state ~= 2^61 > 2^53) silently loses its low bits to float
  # rounding, and reducing THAT mod a small/even n starves the odd task indices — which would
  # corrupt every committed CI and let task ORDER alone flip the promotion gate.
  def _lcg_seed($seed): (((($seed % 2147483646) + 2147483646) % 2147483646) + 1);   # → [1, 2^31-2]
  def _lcg($s): (48271 * $s) % 2147483647;
  # Resample index in [0,$n): the HIGH-bit ratio floor((state/m)*n), NOT (state % n). Lehmer/LCG
  # low bits carry serial correlation; the ratio uses the well-distributed high bits → uniform draws.
  def _draw_index($s; $n): (($s / 2147483647) * $n) | floor;

  # Task-clustered nonparametric bootstrap CI of the MEAN of $vec.
  # Each of $B resamples draws n=length($vec) tasks WITH REPLACEMENT and averages them;
  # the [$lq, $hq] quantiles of the resample-mean distribution are the CI. Seeded by $seed.
  #   n == 0 → [null, null]   (nothing to estimate)
  #   n == 1 → [v, v]         (a single task carries no between-task variance)
  def bootstrap_ci($vec; $B; $seed; $lq; $hq):
    ($vec | length) as $n
    | if $n == 0 then [null, null]
      elif $n == 1 then [ $vec[0], $vec[0] ]
      else
        ( reduce range(0; $B) as $b
            ( { s: _lcg_seed($seed), means: [] };
              ( reduce range(0; $n) as $i
                  ( { s: .s, sum: 0 };
                    ( _lcg(.s) ) as $ns
                    | { s: $ns, sum: (.sum + $vec[ _draw_index($ns; $n) ]) }
                  )
              ) as $r
              | { s: $r.s, means: (.means + [ $r.sum / $n ]) }
            )
        )
        | ( .means | sort ) as $sorted
        | [ _quantile($sorted; $lq), _quantile($sorted; $hq) ]
      end;
'
