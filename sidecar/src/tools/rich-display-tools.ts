import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";

const DEFAULT_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

// --- Confirmation tool (blocking) ---

export interface PendingConfirmation {
  resolve: (result: { approved: boolean; modifiedAction?: string }) => void;
  timer: ReturnType<typeof setTimeout>;
}

export const pendingConfirmations = new Map<string, PendingConfirmation>();

export function resolveConfirmation(
  confirmationId: string,
  approved: boolean,
  modifiedAction?: string,
): boolean {
  const pending = pendingConfirmations.get(confirmationId);
  if (!pending) return false;
  clearTimeout(pending.timer);
  pendingConfirmations.delete(confirmationId);
  pending.resolve({ approved, modifiedAction });
  return true;
}

/**
 * Create all rich display tools for a session.
 */
export function createRichDisplayTools(ctx: ToolContext, callingSessionId: string) {
  return [
    // --- render_content (fire-and-forget) ---
    tool(
      "render_content",
      "Display rich content inline in the user's chat. Use for charts, styled reports, visualizations, or any content that benefits from HTML rendering. The content appears as an inline card in the conversation.",
      {
        format: z
          .enum(["html", "mermaid", "markdown"])
          .describe("Content format: html for rich content, mermaid for diagrams, markdown for styled cards"),
        title: z.string().optional().describe("Optional card title shown above content"),
        content: z.string().describe("The content to render (HTML string, mermaid source, or markdown)"),
        height: z.number().optional().describe("Optional max height in pixels. Auto-sizes if omitted."),
      },
      async (args) => {
        console.log(`[render_content] format=${args.format} for session ${callingSessionId}`);
        ctx.broadcast({
          type: "stream.richContent",
          sessionId: callingSessionId,
          format: args.format,
          title: args.title,
          content: args.content,
          height: args.height,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify({ rendered: true, format: args.format }) }],
        };
      },
    ),

    // --- confirm_action (blocking) ---
    tool(
      "confirm_action",
      "Request user approval before performing a destructive or important action. Blocks until the user responds with approve or reject. Use this for operations like git push, file deletion, deployments, or any action with significant consequences.",
      {
        action: z.string().describe("What you're about to do (e.g., 'git push origin main', 'rm -rf build/')"),
        reason: z.string().describe("Why this action needs approval"),
        risk_level: z.enum(["low", "medium", "high"]).describe("Risk assessment of the action"),
        details: z.string().optional().describe("Optional additional context (diff summary, affected files, etc.)"),
      },
      async (args) => {
        console.log(`[confirm_action] action="${args.action}" risk=${args.risk_level} for session ${callingSessionId}`);
        const confirmationId = randomUUID();

        const result = await new Promise<{ approved: boolean; modifiedAction?: string }>(
          (resolve) => {
            const timer = setTimeout(() => {
              pendingConfirmations.delete(confirmationId);
              resolve({ approved: false });
            }, DEFAULT_TIMEOUT_MS);

            pendingConfirmations.set(confirmationId, { resolve, timer });

            ctx.broadcast({
              type: "agent.confirmation",
              sessionId: callingSessionId,
              confirmationId,
              action: args.action,
              reason: args.reason,
              riskLevel: args.risk_level,
              details: args.details,
            });
          },
        );

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              approved: result.approved,
              modifiedAction: result.modifiedAction,
            }),
          }],
        };
      },
    ),

    // --- show_progress (fire-and-forget, updateable) ---
    tool(
      "show_progress",
      "Display or update a progress tracker in the chat. Call multiple times with the same id to update step statuses as work progresses.",
      {
        id: z.string().describe("Unique progress tracker ID (reuse to update existing tracker)"),
        title: z.string().describe("Progress card title"),
        steps: z.array(
          z.object({
            label: z.string().describe("Step description"),
            status: z.enum(["pending", "running", "done", "error", "skipped"]).describe("Current step status"),
          }),
        ).describe("Array of steps with their current statuses"),
      },
      async (args) => {
        console.log(`[show_progress] id=${args.id} title="${args.title}" for session ${callingSessionId}`);
        ctx.broadcast({
          type: "stream.progress",
          sessionId: callingSessionId,
          progressId: args.id,
          title: args.title,
          steps: args.steps,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify({ updated: true, id: args.id }) }],
        };
      },
    ),

    // --- suggest_actions (fire-and-forget) ---
    tool(
      "suggest_actions",
      "Show clickable follow-up action chips in the chat. The user can tap one to send it as their next message. Use this after completing a task to suggest natural next steps.",
      {
        suggestions: z.array(
          z.object({
            label: z.string().describe("Chip text shown to user"),
            message: z.string().optional().describe("Message sent when clicked (defaults to label text)"),
          }),
        ).max(5).describe("Up to 5 suggestion chips"),
      },
      async (args) => {
        console.log(`[suggest_actions] ${args.suggestions.length} suggestions for session ${callingSessionId}`);
        ctx.broadcast({
          type: "stream.suggestions",
          sessionId: callingSessionId,
          suggestions: args.suggestions,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify({ suggested: true, count: args.suggestions.length }) }],
        };
      },
    ),
  ];
}
