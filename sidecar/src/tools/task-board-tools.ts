import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";

function resolveSessionId(extra: any, callingSessionId?: string): string | undefined {
  return extra?.sessionId ?? callingSessionId;
}

function recordToolCall(ctx: ToolContext, sessionId?: string) {
  if (!sessionId) return;
  const state = ctx.sessions.get(sessionId);
  if (!state) return;
  ctx.sessions.update(sessionId, { toolCallCount: state.toolCallCount + 1 });
}

export function createTaskBoardTools(ctx: ToolContext, callingSessionId?: string) {
  return [
    defineSharedTool(
      "task_board_list",
      "List tasks on the task board. Optionally filter by status or assigned agent.",
      {
        status: z.enum(["backlog", "ready", "inProgress", "done", "failed", "blocked"]).optional()
          .describe("Filter by task status"),
        assigned_to: z.string().optional()
          .describe("Filter by assigned agent name"),
      },
      async (args, extra: any) => {
        recordToolCall(ctx, resolveSessionId(extra, callingSessionId));
        const tasks = ctx.taskBoard.list({
          status: args.status,
          assignedTo: args.assigned_to,
        });
        return createTextResult(tasks);
      },
    ),

    defineSharedTool(
      "task_board_create",
      "Create a new task on the task board. Agent-created tasks default to 'ready' status so they can be claimed immediately. Use 'backlog' to save a draft task for later.",
      {
        title: z.string().describe("Short title for the task"),
        description: z.string().optional().describe("Detailed description of what needs to be done"),
        priority: z.enum(["low", "medium", "high", "critical"]).optional()
          .describe("Task priority (default: medium)"),
        labels: z.array(z.string()).optional().describe("Tags for categorization"),
        parent_task_id: z.string().optional().describe("ID of parent task if this is a subtask"),
        status: z.enum(["backlog", "ready"]).optional().describe("Initial status (default: ready)"),
      },
      async (args, extra: any) => {
        const sessionId = resolveSessionId(extra, callingSessionId);
        recordToolCall(ctx, sessionId);
        const task = ctx.taskBoard.create({
          title: args.title,
          description: args.description ?? "",
          priority: args.priority ?? "medium",
          labels: args.labels ?? [],
          parentTaskId: args.parent_task_id,
          status: args.status ?? "ready",
        });

        ctx.broadcast({ type: "task.created", sessionId, task });

        return createTextResult({ success: true, task });
      },
    ),

    defineSharedTool(
      "task_board_claim",
      "Atomically claim a ready task. Sets status to inProgress and assigns it to the calling agent. Fails if the task is already claimed or not in 'ready' status.",
      {
        task_id: z.string().describe("ID of the task to claim"),
      },
      async (args, extra: any) => {
        const sessionId = resolveSessionId(extra, callingSessionId);
        recordToolCall(ctx, sessionId);
        const state = sessionId ? ctx.sessions.get(sessionId) : undefined;
        const agentName = state?.agentName ?? sessionId ?? "unknown";

        const task = ctx.taskBoard.claim(args.task_id, agentName);
        if (!task) {
          return createTextResult({ error: "claim_failed", task_id: args.task_id, reason: "Task not found or not in 'ready' status" }, false);
        }

        ctx.broadcast({ type: "task.updated", sessionId, task });

        return createTextResult({ success: true, task });
      },
    ),

    defineSharedTool(
      "task_board_update",
      "Update a task's status, result, or linked conversation. Use this to report progress or completion.",
      {
        task_id: z.string().describe("ID of the task to update"),
        status: z.enum(["backlog", "ready", "inProgress", "done", "failed", "blocked"]).optional()
          .describe("New status"),
        result: z.string().optional().describe("Result summary when completing a task"),
        conversation_id: z.string().optional().describe("Link to the conversation where work is happening"),
        assigned_agent_id: z.string().optional().describe("Agent ID to assign"),
        assigned_agent_name: z.string().optional().describe("Agent name to assign"),
        assigned_group_id: z.string().optional().describe("Group ID to assign"),
      },
      async (args, extra: any) => {
        const sessionId = resolveSessionId(extra, callingSessionId);
        recordToolCall(ctx, sessionId);
        const updates: Record<string, any> = {};
        if (args.status) updates.status = args.status;
        if (args.result) updates.result = args.result;
        if (args.conversation_id) updates.conversationId = args.conversation_id;
        if (args.assigned_agent_id) updates.assignedAgentId = args.assigned_agent_id;
        if (args.assigned_agent_name) updates.assignedAgentName = args.assigned_agent_name;
        if (args.assigned_group_id) updates.assignedGroupId = args.assigned_group_id;

        const task = ctx.taskBoard.update(args.task_id, updates);
        if (!task) {
          return createTextResult({ error: "not_found", task_id: args.task_id }, false);
        }

        ctx.broadcast({ type: "task.updated", sessionId, task });

        return createTextResult({ success: true, task });
      },
    ),
  ];
}
