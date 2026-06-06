/**
 * Shapes of the `AskUserQuestion` tool input/answer as the Agent SDK `canUseTool`
 * callback receives and must return them.
 *
 * Source of truth: Claude Agent SDK "Handle approvals and user input"
 * (code.claude.com/docs/en/agent-sdk/user-input) — the `questions` array each
 * carries `{ question, header, options:[{label, description, preview?}], multiSelect }`,
 * and the answer is `{ questions, answers: { "<question text>": "<label>" | "<label>"[] } }`.
 */

export interface AuqOption {
  /** The selectable label. The chosen answer value must equal this string verbatim. */
  label: string;
  description?: string;
  /** TS-only, present when toolConfig.askUserQuestion.previewFormat is set. */
  preview?: string;
}

export interface AuqQuestion {
  /** Full question text — this is the KEY in the returned `answers` map. */
  question: string;
  header?: string;
  options: AuqOption[];
  /** When true, multiple labels may be selected. */
  multiSelect?: boolean;
}

export interface AuqInput {
  questions: AuqQuestion[];
}

/** A single answer: one label (single-select) or many (multiSelect). */
export type AuqAnswerValue = string | string[];

/** Map of question text -> chosen label(s). */
export interface AuqAnswers {
  [questionText: string]: AuqAnswerValue;
}

/**
 * What `canUseTool` returns to auto-answer an AskUserQuestion: the original
 * `questions` array (required for tool processing) plus the `answers` map.
 */
export interface AuqUpdatedInput {
  questions: AuqQuestion[];
  answers: AuqAnswers;
}
