import { test } from "node:test";
import assert from "node:assert/strict";

import { approveDefaultV1, denyIrreversibleV1, isIrreversible, isRecommended, resolvePolicy } from "./auto-answer.js";
import type { AuqInput, AuqQuestion } from "./types.js";

/**
 * `approve-default-v1` (plan §5): pick the `(Recommended)` / pre-selected option,
 * order-stable (by the marker) NOT positional; fall back to the first listed option
 * when none is marked. Return the chosen option's label verbatim.
 *
 * The geniro convention (skills/_shared/per-finding-question.md "Recommended-label
 * policy"): a recommended option's label is suffixed with " (Recommended)" AND
 * positioned first. We key on the MARKER so the policy survives a re-order.
 */

function q(partial: Partial<AuqQuestion> & { question: string; options: AuqQuestion["options"] }): AuqQuestion {
  return { ...partial };
}

test("isRecommended detects the (Recommended) marker, case-insensitively", () => {
  assert.equal(isRecommended({ label: "Approve (Recommended)" }), true);
  assert.equal(isRecommended({ label: "Approve (recommended)" }), true);
  assert.equal(isRecommended({ label: "Request changes" }), false);
});

test("single-select: picks the Recommended option even when it is NOT first (order-stable, not positional)", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Approve spec?",
        options: [
          { label: "Request changes" },
          { label: "Abort" },
          { label: "Approve (Recommended)" },
        ],
      }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), { "Approve spec?": "Approve (Recommended)" });
});

test("single-select: falls back to the FIRST option when none is marked Recommended", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Workspace setup?",
        options: [{ label: "Use a worktree" }, { label: "Run in place" }],
      }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), { "Workspace setup?": "Use a worktree" });
});

test("returns the chosen label VERBATIM (the SDK matches the answer string to an option label)", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Next step?",
        options: [
          { label: "/geniro:implement (Recommended)", description: "hand off" },
          { label: "Stop" },
        ],
      }),
    ],
  };
  // Must include the trailing marker exactly as rendered — not a stripped "/geniro:implement".
  assert.deepEqual(approveDefaultV1(input), { "Next step?": "/geniro:implement (Recommended)" });
});

test("single-select: when MULTIPLE options carry the marker, picks the first such (order-stable)", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Pick one",
        options: [
          { label: "B (Recommended)" },
          { label: "A (Recommended)" },
        ],
      }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), { "Pick one": "B (Recommended)" });
});

test("multiSelect: returns the Recommended labels as an array when any are marked", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Which findings to author tests for?",
        multiSelect: true,
        options: [
          { label: "SQLi in auth.ts (Recommended)" },
          { label: "Missing null-check" },
          { label: "Style nit (Recommended)" },
        ],
      }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), {
    "Which findings to author tests for?": ["SQLi in auth.ts (Recommended)", "Style nit (Recommended)"],
  });
});

test("multiSelect: returns an EMPTY array (conservative — pick nothing) when none is Recommended", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Select findings to post",
        multiSelect: true,
        options: [{ label: "Finding A" }, { label: "Finding B" }],
      }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), { "Select findings to post": [] });
});

test("handles a batched gate of multiple questions (geniro caps at 4 per call)", () => {
  const input: AuqInput = {
    questions: [
      q({ question: "Goal & scope?", options: [{ label: "Approve all (Recommended)" }, { label: "Revise" }] }),
      q({ question: "Safety?", options: [{ label: "Approve all (Recommended)" }, { label: "Revise" }] }),
    ],
  };
  assert.deepEqual(approveDefaultV1(input), {
    "Goal & scope?": "Approve all (Recommended)",
    "Safety?": "Approve all (Recommended)",
  });
});

test("never synthesizes free text — always returns a presented label", () => {
  const input: AuqInput = {
    questions: [q({ question: "Topic?", options: [{ label: "New feature" }, { label: "Existing problem" }] })],
  };
  const answers = approveDefaultV1(input);
  assert.equal(answers["Topic?"], "New feature");
});

test("fails fast on a malformed question with no options (an unanswerable gate is a Phase-0 finding, not a silent skip)", () => {
  const input = { questions: [{ question: "broken", options: [] }] } as AuqInput;
  assert.throws(() => approveDefaultV1(input), /no options/i);
});

/**
 * `deny-irreversible-v1` — the policy `run-suite.sh`'s side-effect guard requires before
 * it will run the review/implement suites. Same choice rule; irreversible options are
 * removed from the candidate set first, and a gate offering nothing else throws.
 */

test("isIrreversible flags the four run-suite.sh action classes and spares safe labels", () => {
  assert.equal(isIrreversible({ label: "Post Draft PR review" }), true);
  assert.equal(isIrreversible({ label: "Just push (no PR)" }), true);
  assert.equal(isIrreversible({ label: "Commit on `feat/x` anyway" }), true);
  assert.equal(isIrreversible({ label: "Open draft PR (Recommended)" }), true);
  assert.equal(isIrreversible({ label: "Open PR" }), true);

  assert.equal(isIrreversible({ label: "Skip" }), false);
  assert.equal(isIrreversible({ label: "Continue rounds" }), false);
  assert.equal(isIrreversible({ label: "/geniro:implement findings (Recommended)" }), false);
  assert.equal(isIrreversible({ label: "Stop — let me sort the branch out" }), false);
  // \b keeps "post" from matching inside a longer word.
  assert.equal(isIrreversible({ label: "Postpone the decision" }), false);
});

test("review action gate: drops 'Post Draft PR review' and takes the recommended survivor", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "How should I proceed with the 3 findings?",
        options: [
          { label: "/geniro:implement findings (Recommended)" },
          { label: "Post Draft PR review" },
          { label: "Continue rounds" },
          { label: "Skip" },
        ],
      }),
    ],
  };
  assert.deepEqual(denyIrreversibleV1(input), {
    "How should I proceed with the 3 findings?": "/geniro:implement findings (Recommended)",
  });
});

test("a denied RECOMMENDATION falls through to the safest survivor, it does not win", () => {
  // The concrete danger: /geniro:implement's ship gate marks an irreversible option as
  // the recommendation, so approve-default-v1 would open a real PR.
  const input: AuqInput = {
    questions: [
      q({
        question: "Ship mode?",
        options: [
          { label: "Open draft PR (Recommended)" },
          { label: "Leave uncommitted" },
        ],
      }),
    ],
  };
  assert.deepEqual(denyIrreversibleV1(input), { "Ship mode?": "Leave uncommitted" });
  // The two policies must genuinely differ here — this is what the run-suite guard buys.
  assert.deepEqual(approveDefaultV1(input), { "Ship mode?": "Open draft PR (Recommended)" });
});

test("branch-check gate: both commit-bearing options are dropped, 'Stop' survives", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "The working tree is on `x` but this run targeted `y` — how do you want to proceed?",
        options: [
          { label: "Move my commit to `y` first" },
          { label: "Commit on `x` anyway" },
          { label: "Stop — let me sort the branch out" },
        ],
      }),
    ],
  };
  assert.deepEqual(denyIrreversibleV1(input), {
    "The working tree is on `x` but this run targeted `y` — how do you want to proceed?":
      "Stop — let me sort the branch out",
  });
});

test("fails CLOSED when every option is irreversible — the real ship-gate allowlist", () => {
  // /geniro:implement pins exactly these three labels, and all three ship. A suite that
  // needs to reach Ship uses the skill's own `stop after review` modifier to skip this
  // gate; answering it unattended is precisely what this policy must refuse to do.
  const input: AuqInput = {
    questions: [
      q({
        question: "Ship mode?",
        options: [
          { label: "Open draft PR (Recommended)" },
          { label: "Open PR" },
          { label: "Just push (no PR)" },
        ],
      }),
    ],
  };
  assert.throws(() => denyIrreversibleV1(input), /only irreversible options/i);
});

test("multiSelect: irreversible marked options are dropped from the selection", () => {
  const input: AuqInput = {
    questions: [
      q({
        question: "Which findings to act on?",
        multiSelect: true,
        options: [
          { label: "Author a test for the SQLi (Recommended)" },
          { label: "Post the findings to the PR (Recommended)" },
        ],
      }),
    ],
  };
  assert.deepEqual(denyIrreversibleV1(input), {
    "Which findings to act on?": ["Author a test for the SQLi (Recommended)"],
  });
});

test("resolvePolicy: defaults to the approving policy, resolves both names, throws on a typo", () => {
  assert.equal(resolvePolicy(undefined).name, "approve-default-v1");
  assert.equal(resolvePolicy("approve-default-v1").name, "approve-default-v1");
  assert.equal(resolvePolicy("deny-irreversible-v1").name, "deny-irreversible-v1");
  // A typo must NOT silently fall back to approving — that would re-enable the exact
  // behavior run-suite.sh's guard refuses, while the guard reads the env var as set.
  assert.throws(() => resolvePolicy("deny-irreversible"), /unknown EVAL_AUQ_POLICY/i);
});

test("resolvePolicy returns a working answer function for each name", () => {
  const input: AuqInput = {
    questions: [q({ question: "Ship mode?", options: [{ label: "Open PR (Recommended)" }, { label: "Leave uncommitted" }] })],
  };
  assert.deepEqual(resolvePolicy("approve-default-v1").answer(input), { "Ship mode?": "Open PR (Recommended)" });
  assert.deepEqual(resolvePolicy("deny-irreversible-v1").answer(input), { "Ship mode?": "Leave uncommitted" });
});
