/**
 * Integration tests for task_board_* PeerBus tools.
 *
 * Tests the tool factory (createTaskBoardTools) by wiring through a real ToolContext
 * with real stores — but no sidecar, no WebSocket, no Claude SDK.
 *
 * Usage: CLAUDESTUDIO_DATA_DIR=/tmp/claudestudio-test-$(date +%s) bun test test/integration/task-board-tools.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";
import { createTaskBoardTools } from "../../src/tools/task-board-tools.js";

function createTestContext(): {
  ctx: ToolContext;
  events: SidecarEvent[];
} {
  const events: SidecarEvent[] = [];

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`test-${Date.now()}-${Math.random()}`),
    taskBoard: new TaskBoardStore(`test-${Date.now()}-${Math.random()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    broadcast: (event) => events.push(event),
    spawnSession: async (sessionId, config, prompt, wait) => {
      return { sessionId, result: wait ? "mock-result" : undefined };
    },
    agentDefinitions: new Map(),
  } as ToolContext;

  return { ctx, events };
}

function parseToolResult(result: any): any {
  return JSON.parse(result.content[0].text);
}

async function call(toolObj: any, args: Record<string, any>, extra: Record<string, any> = {}): Promise<any> {
  if (typeof toolObj.execute === "function") {
    return toolObj.execute(args, extra);
  }
  if (typeof toolObj.handler === "function") {
    return toolObj.handler(args, extra);
  }
  throw new TypeError("Tool object does not expose execute() or handler()");
}

function findTool(tools: any[], name: string) {
  const t = tools.find((t: any) => t.name === name);
  if (!t) throw new Error(`Tool "${name}" not found in [${tools.map((t: any) => t.name)}]`);
  return t;
}

// ─── Task Board Tools ───────────────────────────────────────────────

describe("Task Board Tools (integration)", () => {
  let ctx: ToolContext;
  let events: SidecarEvent[];
  let tools: ReturnType<typeof createTaskBoardTools>;

  beforeEach(() => {
    ({ ctx, events } = createTestContext());
    tools = createTaskBoardTools(ctx, "sess-1");
    // Create a mock session so claim can find the agent name
    ctx.sessions.create("sess-1", { name: "Orchestrator", systemPrompt: "", allowedTools: [], mcpServers: [], model: "sonnet", workingDirectory: "/tmp", skills: [] });
  });

  // ─── task_board_create ───

  test("task_board_create creates a task and broadcasts", async () => {
    const tool = findTool(tools, "task_board_create");
    const result = parseToolResult(await call(tool, {
      title: "Fix login bug",
      description: "Users can't log in",
      priority: "high",
      labels: ["auth", "urgent"],
    }));

    expect(result.success).toBe(true);
    expect(result.task.title).toBe("Fix login bug");
    expect(result.task.description).toBe("Users can't log in");
    expect(result.task.priority).toBe("high");
    expect(result.task.labels).toEqual(["auth", "urgent"]);
    expect(result.task.status).toBe("ready"); // default for agent-created tasks

    // Should broadcast task.created event
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("task.created");
  });

  test("task_board_create with parent_task_id sets parentTaskId", async () => {
    const tool = findTool(tools, "task_board_create");
    const parent = parseToolResult(await call(tool, { title: "Parent" }));
    const child = parseToolResult(await call(tool, {
      title: "Child",
      parent_task_id: parent.task.id,
    }));

    expect(child.task.parentTaskId).toBe(parent.task.id);
  });

  test("task_board_create defaults to ready status for agents", async () => {
    const tool = findTool(tools, "task_board_create");
    const result = parseToolResult(await call(tool, { title: "Test" }));
    expect(result.task.status).toBe("ready");
  });

  test("task_board_create with explicit backlog status", async () => {
    const tool = findTool(tools, "task_board_create");
    const result = parseToolResult(await call(tool, { title: "Draft", status: "backlog" }));
    expect(result.task.status).toBe("backlog");
  });

  // ─── task_board_list ───

  test("task_board_list returns all tasks", async () => {
    const createTool = findTool(tools, "task_board_create");
    await call(createTool, { title: "Task A" });
    await call(createTool, { title: "Task B" });

    const listTool = findTool(tools, "task_board_list");
    const result = parseToolResult(await call(listTool, {}));
    expect(result).toHaveLength(2);
  });

  test("task_board_list filters by status", async () => {
    const createTool = findTool(tools, "task_board_create");
    await call(createTool, { title: "Ready", status: "ready" });
    await call(createTool, { title: "Draft", status: "backlog" });

    const listTool = findTool(tools, "task_board_list");
    const result = parseToolResult(await call(listTool, { status: "ready" }));
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe("Ready");
  });

  // ─── task_board_claim ───

  test("task_board_claim claims a ready task", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Claimable", status: "ready" }));

    const claimTool = findTool(tools, "task_board_claim");
    const result = parseToolResult(await call(claimTool, { task_id: created.task.id }, { sessionId: "sess-1" }));

    expect(result.success).toBe(true);
    expect(result.task.status).toBe("inProgress");
    expect(result.task.assignedAgentId).toBeUndefined();
    expect(result.task.assignedAgentName).toBe("Orchestrator");
    expect(result.task.startedAt).toBeTruthy();
  });

  test("task_board_claim fails for non-ready task", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Draft", status: "backlog" }));

    const claimTool = findTool(tools, "task_board_claim");
    // Need to update status to backlog first — but agent creates as "ready" by default
    // Create a backlog task directly
    ctx.taskBoard.create({ title: "Not Ready", status: "backlog" });
    const backlogTask = ctx.taskBoard.list({ status: "backlog" })[0];

    const result = parseToolResult(await call(claimTool, { task_id: backlogTask.id }, { sessionId: "sess-1" }));
    expect(result.error).toBe("claim_failed");
  });

  test("task_board_claim fails for already-claimed task", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Claimable" }));

    const claimTool = findTool(tools, "task_board_claim");
    await call(claimTool, { task_id: created.task.id }, { sessionId: "sess-1" });
    const secondClaim = parseToolResult(await call(claimTool, { task_id: created.task.id }, { sessionId: "sess-1" }));
    expect(secondClaim.error).toBe("claim_failed");
  });

  // ─── task_board_update ───

  test("task_board_update changes status and result", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Task" }));

    const claimTool = findTool(tools, "task_board_claim");
    await call(claimTool, { task_id: created.task.id }, { sessionId: "sess-1" });

    const updateTool = findTool(tools, "task_board_update");
    const result = parseToolResult(await call(updateTool, {
      task_id: created.task.id,
      status: "done",
      result: "Bug fixed successfully",
    }));

    expect(result.success).toBe(true);
    expect(result.task.status).toBe("done");
    expect(result.task.result).toBe("Bug fixed successfully");
    expect(result.task.completedAt).toBeTruthy();
  });

  test("task_board_update links conversation", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Task" }));

    const updateTool = findTool(tools, "task_board_update");
    const result = parseToolResult(await call(updateTool, {
      task_id: created.task.id,
      conversation_id: "conv-abc-123",
    }));

    expect(result.task.conversationId).toBe("conv-abc-123");
  });

  test("task_board_update returns error for missing task", async () => {
    const updateTool = findTool(tools, "task_board_update");
    const result = parseToolResult(await call(updateTool, {
      task_id: "nonexistent",
      status: "done",
    }));
    expect(result.error).toBe("not_found");
  });

  // ─── Event Broadcasting ───

  test("all mutating tools broadcast events", async () => {
    const createTool = findTool(tools, "task_board_create");
    const created = parseToolResult(await call(createTool, { title: "Test" }));
    expect(events.filter((e) => e.type === "task.created")).toHaveLength(1);

    const claimTool = findTool(tools, "task_board_claim");
    await call(claimTool, { task_id: created.task.id }, { sessionId: "sess-1" });
    expect(events.filter((e) => e.type === "task.updated")).toHaveLength(1);

    const updateTool = findTool(tools, "task_board_update");
    await call(updateTool, { task_id: created.task.id, status: "done", result: "Done" });
    expect(events.filter((e) => e.type === "task.updated")).toHaveLength(2);
  });
});
