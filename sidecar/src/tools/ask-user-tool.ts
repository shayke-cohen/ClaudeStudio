import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

export interface PendingQuestion {
  resolve: (answer: { answer: string; selectedOptions?: string[] }) => void;
  reject: (err: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/** Map of questionId → pending resolver. Shared between tool, ws-server, and HTTP API. */
export const pendingQuestions = new Map<string, PendingQuestion>();

/** Map of sessionId → set of questionIds, so sessions can clean up on pause. */
export const questionsBySession = new Map<string, Set<string>>();

/**
 * Create a pending question and return its ID + a promise that resolves with the answer.
 * Used by the HTTP API endpoint so the stdio MCP server can long-poll for the answer.
 */
export function createQuestion(sessionId: string): { questionId: string; promise: Promise<{ answer: string; selectedOptions?: string[] }> } {
  const questionId = randomUUID();
  let resolveFn!: (value: { answer: string; selectedOptions?: string[] }) => void;
  let rejectFn!: (err: Error) => void;
  const promise = new Promise<{ answer: string; selectedOptions?: string[] }>((resolve, reject) => {
    resolveFn = resolve;
    rejectFn = reject;
  });
  const timer = setTimeout(() => {
    pendingQuestions.delete(questionId);
    // Clean up session tracking
    const set = questionsBySession.get(sessionId);
    if (set) { set.delete(questionId); if (set.size === 0) questionsBySession.delete(sessionId); }
    resolveFn({ answer: "[User did not respond within the timeout period. Proceed with your best judgment.]" });
  }, DEFAULT_TIMEOUT_MS);
  pendingQuestions.set(questionId, { resolve: resolveFn, reject: rejectFn, timer });
  // Track by session for cleanup on pause
  const sessionSet = questionsBySession.get(sessionId) ?? new Set();
  sessionSet.add(questionId);
  questionsBySession.set(sessionId, sessionSet);
  return { questionId, promise };
}

export function resolveQuestion(
  questionId: string,
  answer: string,
  selectedOptions?: string[],
): boolean {
  const pending = pendingQuestions.get(questionId);
  if (!pending) return false;
  clearTimeout(pending.timer);
  pendingQuestions.delete(questionId);
  // Remove from session tracking
  for (const [sid, set] of questionsBySession) {
    if (set.delete(questionId) && set.size === 0) questionsBySession.delete(sid);
  }
  pending.resolve({ answer, selectedOptions });
  return true;
}

export function rejectQuestion(questionId: string, reason: string): boolean {
  const pending = pendingQuestions.get(questionId);
  if (!pending) return false;
  clearTimeout(pending.timer);
  pending.reject(new Error(reason));
  pendingQuestions.delete(questionId);
  return true;
}

export function createAskUserTool(ctx: ToolContext, callingSessionId: string, onQuestionCreated?: (questionId: string) => void) {
  return [
    tool(
      "ask_user",
      "Ask the user a question and wait for their answer. Blocks until the user responds. Use this when you need clarification, a decision, or confirmation before proceeding. By default, your question is private (not visible to other agents in group chats).",
      {
        question: z.string().describe("The question to ask the user"),
        options: z
          .array(
            z.object({
              label: z.string().describe("Short display text for this option"),
              description: z.string().optional().describe("Explanation of what this option means"),
            }),
          )
          .optional()
          .describe("Optional structured choices. If omitted, the user types a free-text answer."),
        multi_select: z
          .boolean()
          .optional()
          .default(false)
          .describe("Allow the user to select multiple options (default: false)"),
        private: z
          .boolean()
          .optional()
          .default(true)
          .describe("If true (default), the question is only visible to the user — other agents in a group chat won't see it. Set to false to make it visible to all agents."),
        input_type: z
          .enum(["text", "options", "rating", "slider", "toggle", "dropdown", "form"])
          .optional()
          .default("options")
          .describe("UI input type: 'text' (free text), 'options' (buttons, default), 'rating' (star rating), 'slider' (numeric range), 'toggle' (yes/no), 'dropdown' (compact picker for many options), 'form' (multi-field form)"),
        input_config: z
          .object({
            max_rating: z.number().optional().describe("Max stars for rating (default 5)"),
            rating_labels: z.array(z.string()).optional().describe("Labels for each rating level"),
            min: z.number().optional().describe("Slider minimum value"),
            max: z.number().optional().describe("Slider maximum value"),
            step: z.number().optional().describe("Slider step size"),
            unit: z.string().optional().describe("Unit label for slider (e.g. '%', 'ms')"),
            fields: z.array(z.object({
              name: z.string().describe("Field key"),
              label: z.string().describe("Display label"),
              type: z.enum(["text", "number", "toggle"]).describe("Field input type"),
              placeholder: z.string().optional().describe("Placeholder text"),
              required: z.boolean().optional().describe("Whether field is required"),
            })).optional().describe("Form fields (for input_type='form')"),
          })
          .optional()
          .describe("Configuration for the selected input_type"),
      },
      async (args) => {
        console.log(`[ask_user] tool invoked for session ${callingSessionId}: "${args.question.substring(0, 80)}"`);
        const questionId = randomUUID();

        const result = await new Promise<{ answer: string; selectedOptions?: string[] }>(
          (resolve, reject) => {
            const timer = setTimeout(() => {
              pendingQuestions.delete(questionId);
              resolve({
                answer: "[User did not respond within the timeout period. Proceed with your best judgment.]",
              });
            }, DEFAULT_TIMEOUT_MS);

            pendingQuestions.set(questionId, { resolve, reject, timer });
            onQuestionCreated?.(questionId);

            const inputConfig = args.input_config ? {
              maxRating: args.input_config.max_rating,
              ratingLabels: args.input_config.rating_labels,
              min: args.input_config.min,
              max: args.input_config.max,
              step: args.input_config.step,
              unit: args.input_config.unit,
              fields: args.input_config.fields,
            } : undefined;

            ctx.broadcast({
              type: "agent.question",
              sessionId: callingSessionId,
              questionId,
              question: args.question,
              options: args.options,
              multiSelect: args.multi_select ?? false,
              private: args.private ?? true,
              inputType: args.input_type ?? "options",
              inputConfig,
            });
          },
        );

        return {
          content: [
            {
              type: "text" as const,
              text: JSON.stringify({
                answer: result.answer,
                selectedOptions: result.selectedOptions,
              }),
            },
          ],
        };
      },
    ),
  ];
}
