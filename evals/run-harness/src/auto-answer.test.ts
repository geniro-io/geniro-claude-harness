import { test } from "node:test";
import assert from "node:assert/strict";

import { approveDefaultV1, isRecommended } from "./auto-answer.js";
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
