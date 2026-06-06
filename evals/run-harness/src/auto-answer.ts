import type { AuqInput, AuqAnswers, AuqAnswerValue, AuqOption, AuqQuestion } from "./types.js";

/**
 * `approve-default-v1` — the recorded auto-answer policy (plan §5).
 *
 * Pick the `(Recommended)` / pre-selected option, **order-stable by the marker, not
 * positional**, falling back to the first listed option only when none is marked.
 * Return the chosen option's `label` verbatim (the SDK matches the answer string back
 * to a presented label, so a stripped/normalized value would fail to map).
 *
 * geniro convention (skills/_shared/per-finding-question.md "Recommended-label policy"):
 * a recommended option's label is suffixed with " (Recommended)" AND positioned first.
 * Keying on the MARKER (not position) keeps the policy correct if option order changes
 * and lets it resolve `/review`'s variable, dynamically-labelled per-finding gates — not
 * just `/plan`'s fixed binary approve gate.
 *
 * This policy never synthesizes free text; it only ever returns labels the gate presented.
 */

const RECOMMENDED_MARKER = /\(recommended\)/i;

export function isRecommended(option: AuqOption): boolean {
  return RECOMMENDED_MARKER.test(option.label);
}

function chooseForQuestion(q: AuqQuestion): AuqAnswerValue {
  const options = q.options ?? [];
  if (options.length === 0) {
    throw new Error(
      `approve-default-v1: AskUserQuestion "${q.question}" has no options — an unanswerable gate is a Phase-0 finding, not a silent default.`,
    );
  }

  const recommended = options.filter(isRecommended);

  if (q.multiSelect) {
    // Conservative multi-select: take exactly the marked options; if none are marked,
    // select nothing (the do-nothing / lowest-blast-radius path — e.g. author no tests,
    // post no findings — which still lets the run complete unattended).
    return recommended.map((o) => o.label);
  }

  // Single-select: first marked option (order-stable), else the first listed option.
  const chosen = recommended[0] ?? options[0]!;
  return chosen.label;
}

export function approveDefaultV1(input: AuqInput): AuqAnswers {
  const answers: AuqAnswers = {};
  for (const q of input.questions ?? []) {
    answers[q.question] = chooseForQuestion(q);
  }
  return answers;
}
