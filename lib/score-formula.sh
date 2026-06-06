#!/usr/bin/env bash
# Single source of truth for the L2 learnings score formula.
#
# Defines the four jq weighting functions shared by the ranker
# (lib/query-learnings.sh --score-min) and the archiver (lib/archive-stale.sh).
# The two callers MUST score identically: the archiver only reaps an entry when
# its score falls below the floor, so if its weights drifted from the ranker's it
# would deprecate entries the ranker would still surface. Keeping the weights in
# one place is what guarantees they cannot drift.
#
# Usage: source this file, then prepend "$GENIRO_SCORE_JQ_DEFS" to the jq program.
# jq ignores whitespace, so each caller's own composite expression follows verbatim:
#   source "$_script_dir/score-formula.sh"
#   local filter="$GENIRO_SCORE_JQ_DEFS"'
#     map( . as $entry | ... | $rd * $tw * $aw * $rw ) ...'
#
# The composite (how the four weights combine into a score and what each caller
# does with it) stays in each caller — only the weight definitions are shared.

# Recency-decay time constant (days). Single-sourced here so the ranker
# (query-learnings --score-min) and the archiver (archive-stale) cannot drift on
# the tau input the way the weight functions cannot drift. Both read it as
# tau="${GENIRO_DECAY_TAU_DAYS:-$GENIRO_DECAY_TAU_DAYS_DEFAULT}".
# shellcheck disable=SC2034  # consumed by callers that source this file
: "${GENIRO_DECAY_TAU_DAYS_DEFAULT:=90}"

# shellcheck disable=SC2034  # consumed by callers that source this file
GENIRO_SCORE_JQ_DEFS='
  def recency_decay($age_days; $tau):
    if $age_days == null then 0.5
    else (- ($age_days / $tau)) | exp end;
  def trust_weight:
    if . == "verified" then 1.0
    elif . == "retrieved" then 0.66
    else 0.33
    end;
  def access_weight($n):
    1.0 + (($n + 1) | log10);
  # Dampened recurrence factor: 1 + ln(max(recurrence_count, 1)). A count of 1
  # (or an absent field, treated as 1) yields ln(1)=0 -> factor 1.0, so pre-field
  # and never-repeated entries score exactly as before this factor was added. ln
  # growth keeps a high count strengthening but not dominating: 2 -> ~1.69,
  # 5 -> ~2.61, 20 -> ~4.0. The max() clamps the floor at 1 to guard a stray 0.
  def recurrence_weight($n):
    1.0 + (([$n, 1] | max) | log);
'
