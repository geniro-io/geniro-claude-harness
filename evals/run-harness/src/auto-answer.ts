import type { AuqInput, AuqAnswers, AuqAnswerValue, AuqOption, AuqQuestion } from "./types.js";

/**
 * Auto-answer policies for the eval driver's `canUseTool` gate callback.
 *
 * Two policies ship, selected by name through `EVAL_AUQ_POLICY`:
 *
 * - `approve-default-v1` — pick the `(Recommended)` / pre-selected option. Safe for
 *   `/plan`, which writes a spec and stops.
 * - `deny-irreversible-v1` — the same choice rule, but options that take an irreversible
 *   outward action are removed from the candidate set first. This is the policy
 *   `run-suite.sh`'s side-effect guard requires before it will run the `review` or
 *   `implement` suites, because under an approving policy those runs post to a real PR,
 *   push, or open a PR for real. `/implement`'s ship gate makes the danger concrete: its
 *   recommended option IS "Open draft PR (Recommended)", so approving the recommendation
 *   is exactly the irreversible act.
 *
 * Neither policy synthesizes free text; both only ever return labels the gate presented.
 */

const RECOMMENDED_MARKER = /\(recommended\)/i;

export function isRecommended(option: AuqOption): boolean {
  return RECOMMENDED_MARKER.test(option.label);
}

/**
 * Labels whose pick performs an action that leaves the sandbox and cannot be undone —
 * the four `run-suite.sh` names: commit, push, open a PR, post a PR review.
 *
 * Matched against the option LABEL, which the skills pin as verbatim canonical allowlists
 * (`/geniro:review` action gate "Post Draft PR review"; `/geniro:implement` ship gate
 * "Open draft PR (Recommended)" / "Open PR" / "Just push (no PR)"), so the label is the
 * stable surface to key on. Descriptions are prose and are deliberately not matched.
 */
const IRREVERSIBLE_LABEL_PATTERNS: RegExp[] = [
  /\bpost\b/i, //   "Post Draft PR review", "Send all" lives behind it and is unreachable
  /\bpush\b/i, //   "Just push (no PR)", "Commit + push"
  /\bcommit\b/i, // any commit-grade pick, including "Commit on <branch> anyway"
  /\bopen\b[^.]*\bpr\b/i, // "Open draft PR (Recommended)", "Open PR"
  /\bship\b/i,
  /\bmerge\b/i,
];

export function isIrreversible(option: AuqOption): boolean {
  return IRREVERSIBLE_LABEL_PATTERNS.some((re) => re.test(option.label));
}

function chooseForQuestion(q: AuqQuestion, policy: PolicyName): AuqAnswerValue {
  const presented = q.options ?? [];
  if (presented.length === 0) {
    throw new Error(
      `${policy}: AskUserQuestion "${q.question}" has no options — an unanswerable gate is a finding, not a silent default.`,
    );
  }

  // Under the denying policy, an irreversible option is not a candidate at all — the
  // choice rule below then runs over what is left, so a denied recommendation falls
  // through to the safest presented alternative rather than being picked.
  const options = policy === "deny-irreversible-v1" ? presented.filter((o) => !isIrreversible(o)) : presented;

  if (options.length === 0) {
    // Fail closed, exactly as the no-options case does. Every option taking an
    // irreversible action means the gate cannot be answered unattended, and silently
    // picking one would perform the act the policy exists to prevent.
    throw new Error(
      `${policy}: AskUserQuestion "${q.question}" offers only irreversible options ` +
        `(${presented.map((o) => o.label).join(" | ")}) — refusing to answer rather than take one.`,
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

export type PolicyName = "approve-default-v1" | "deny-irreversible-v1";

export const POLICY_NAMES: PolicyName[] = ["approve-default-v1", "deny-irreversible-v1"];

/**
 * `approve-default-v1` — pick the `(Recommended)` / pre-selected option, **order-stable by
 * the marker, not positional**, falling back to the first listed option only when none is
 * marked. Return the chosen option's `label` verbatim (the SDK matches the answer string
 * back to a presented label, so a stripped/normalized value would fail to map).
 *
 * geniro convention (skills/_shared/per-finding-question.md "Recommended-label policy"):
 * a recommended option's label is suffixed with " (Recommended)" AND positioned first.
 * Keying on the MARKER (not position) keeps the policy correct if option order changes
 * and lets it resolve `/review`'s variable, dynamically-labelled per-finding gates — not
 * just `/plan`'s fixed binary approve gate.
 */
export function approveDefaultV1(input: AuqInput): AuqAnswers {
  return answerWith(input, "approve-default-v1");
}

/**
 * `deny-irreversible-v1` — `approve-default-v1`'s choice rule over a candidate set with
 * every irreversible option removed. Throws when a gate presents nothing else.
 */
export function denyIrreversibleV1(input: AuqInput): AuqAnswers {
  return answerWith(input, "deny-irreversible-v1");
}

function answerWith(input: AuqInput, policy: PolicyName): AuqAnswers {
  const answers: AuqAnswers = {};
  for (const q of input.questions ?? []) {
    answers[q.question] = chooseForQuestion(q, policy);
  }
  return answers;
}

/**
 * Resolve a policy by name. An unknown name is a hard error rather than a fallback to the
 * approving default: a typo in `EVAL_AUQ_POLICY` would otherwise silently re-enable the
 * behavior `run-suite.sh`'s guard refuses to allow.
 */
export function resolvePolicy(name: string | undefined): { name: PolicyName; answer: (i: AuqInput) => AuqAnswers } {
  const resolved = (name ?? "approve-default-v1") as PolicyName;
  if (!POLICY_NAMES.includes(resolved)) {
    throw new Error(
      `unknown EVAL_AUQ_POLICY "${name}" — known policies: ${POLICY_NAMES.join(", ")}`,
    );
  }
  return {
    name: resolved,
    answer: resolved === "deny-irreversible-v1" ? denyIrreversibleV1 : approveDefaultV1,
  };
}
