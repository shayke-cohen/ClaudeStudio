import { beforeEach, describe, expect, test } from "bun:test";
import { SessionManager } from "../../src/session-manager.js";
import { ClaudeRuntime } from "../../src/providers/claude-runtime.js";
import { CodexRuntime } from "../../src/providers/codex-runtime.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import { makeAgentConfig } from "../helpers.js";

function countOccurrences(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
}

describe("Provider runtime integration", () => {
  let registry: SessionRegistry;
  let events: SidecarEvent[];
  let manager: SessionManager;
  let ctx: ToolContext;

  beforeEach(() => {
    registry = new SessionRegistry();
    events = [];

    ctx = {
      blackboard: new BlackboardStore(`provider-int-${Date.now()}`),
      taskBoard: new TaskBoardStore(`provider-int-${Date.now()}`),
      sessions: registry,
      messages: new MessageStore(),
      channels: new ChatChannelStore(),
      workspaces: new WorkspaceStore(),
      peerRegistry: new PeerRegistry(),
      relayClient: {
        isConnected: () => false,
        connect: async () => {},
        sendCommand: async () => ({}),
      } as any,
      broadcast: (event) => events.push(event),
      spawnSession: async (sessionId) => ({ sessionId }),
      agentDefinitions: new Map(),
    };

    manager = new SessionManager((event) => events.push(event), registry, ctx);
  });

  test("codex sessions route to Codex runtime test options and preserve provider in registry", async () => {
    await manager.createSession("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
      workingDirectory: "/tmp/codex-session",
      mcpServers: [
        {
          name: "Argus",
          command: "npx",
          args: ["-y", "-p", "@wix/argus", "argus-mcp"],
        },
        {
          name: "AppXray",
          command: "npx",
          args: ["-y", "@wix/appxray-mcp-server"],
        },
      ],
    }));

    const state = registry.get("codex-session");
    const options = manager.buildQueryOptionsForTesting("codex-session", 1, true);

    expect(state?.provider).toBe("codex");
    expect(state?.effectiveMcpServers.map((entry) => entry.name)).toEqual(["Argus", "AppXray"]);
    expect(options.provider).toBe("codex");
    expect(options.model).toBe("gpt-5-codex");
    expect(options.cwd).toBe("/tmp/codex-session");
    expect(options.attachmentCount).toBe(1);
    expect(options.mcpServerCount).toBe(2);
    expect(options.appServerConfigOverrides).toContain("mcp_servers={}");
    expect(options.appServerConfigOverrides).toContain(`mcp_servers.session_mcp_0.command="npx"`);
    expect(options.appServerConfigOverrides).toContain(`mcp_servers.session_mcp_0.args=["-y","-p","@wix/argus","argus-mcp"]`);
    expect(options.appServerConfigOverrides).toContain(`mcp_servers.session_mcp_1.command="npx"`);
    expect(options.appServerConfigOverrides).toContain(`mcp_servers.session_mcp_1.args=["-y","@wix/appxray-mcp-server"]`);
  });

  test("claude sessions attach configured MCPs only through mcpServers in bypass mode", async () => {
    await manager.createSession("claude-session", makeAgentConfig({
      name: "Coder",
      provider: "claude",
      model: "claude-opus-4-6",
      workingDirectory: "/tmp/claude-session",
      mcpServers: [
        {
          name: "Argus",
          command: "npx",
          args: ["-y", "-p", "@wix/argus", "argus-mcp"],
        },
        {
          name: "AppXray",
          command: "npx",
          args: ["-y", "@wix/appxray-mcp-server"],
        },
      ],
    }));

    const options = manager.buildQueryOptionsForTesting("claude-session", 0, false);

    expect(Object.keys(options.mcpServers)).toEqual(["Argus", "AppXray", "peerbus"]);
    expect(options.mcpServers.Argus.command).toBe("npx");
    expect(options.mcpServers.Argus.args).toEqual(["-y", "-p", "@wix/argus", "argus-mcp"]);
    expect(options.mcpServers.AppXray.command).toBe("npx");
    expect(options.mcpServers.AppXray.args).toEqual(["-y", "@wix/appxray-mcp-server"]);
    expect(options.allowedTools).toBeUndefined();
    expect(options.settings).toBeUndefined();
    expect(options.permissionMode).toBe("bypassPermissions");
  });

  test("claude composes configured skills exactly once into the provider prompt append", async () => {
    await manager.createSession("claude-skill-session", makeAgentConfig({
      name: "Coder",
      provider: "claude",
      model: "claude-opus-4-6",
      systemPrompt: "Base prompt only.",
      workingDirectory: "/tmp/claude-skill-session",
      skills: [
        { name: "Plan", content: "Plan before editing." },
        { name: "Verify", content: "Run focused verification." },
      ],
      interactive: true,
    }));

    const options = manager.buildQueryOptionsForTesting("claude-skill-session", 0, true);
    const append = options.systemPrompt?.append as string;

    expect(append).toContain("Base prompt only.");
    expect(append).toContain("### Plan\nPlan before editing.");
    expect(append).toContain("### Verify\nRun focused verification.");
    expect(countOccurrences(append, "## Skills")).toBe(1);
    expect(append).toContain("Use `render_content`, `confirm_action`, `show_progress`, and `suggest_actions`");
  });

  test("claude sessions capture MCP inventory from system init and observed MCP tool use", async () => {
    const runtime = new ClaudeRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("claude-session", makeAgentConfig({
      name: "Coder",
      provider: "claude",
      model: "claude-opus-4-6",
      mcpServers: [
        {
          name: "Octocode",
          command: "npx",
          args: ["-y", "octocode-mcp@latest"],
        },
        {
          name: "Broken Search",
          command: "broken-mcp",
        },
      ],
    }) as any);

    await (runtime as any).handleSDKMessage(
      "claude-session",
      {
        type: "system",
        subtype: "init",
        session_id: "sdk-session-1",
        mcp_servers: [
          { name: "Octocode", status: "connected" },
          { name: "Broken Search", status: "failed", error: "spawn failed" },
        ],
      },
      () => {},
      { inputTokens: 0, outputTokens: 0, numTurns: 0 },
    );

    await (runtime as any).handleSDKMessage(
      "claude-session",
      {
        type: "tool_use",
        name: "mcp__octocode__local_ripgrep",
        input: { query: "sled" },
      },
      () => {},
      { inputTokens: 0, outputTokens: 0, numTurns: 0 },
    );

    const inventory = registry.getMcpInventory("claude-session");
    expect(inventory).toEqual([
      {
        name: "Broken Search",
        namespace: "broken_search",
        source: "configured",
        transport: "stdio",
        configured: true,
        availability: "failed",
        providerStatus: "failed",
        error: "spawn failed",
      },
      {
        name: "Octocode",
        namespace: "octocode",
        source: "configured",
        transport: "stdio",
        configured: true,
        availability: "loaded",
        providerStatus: "connected",
        tools: [{ name: "local_ripgrep" }],
      },
    ]);
  });

  test("codex refreshes MCP inventory after thread start and records failures cleanly", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    const config = makeAgentConfig({
      name: "Coder",
      provider: "codex",
      model: "gpt-5-codex",
      workingDirectory: "/tmp/codex-session",
      mcpServers: [
        {
          name: "Octocode",
          command: "npx",
          args: ["-y", "octocode-mcp@latest"],
        },
        {
          name: "Broken Search",
          command: "broken-mcp",
        },
      ],
    }) as any;

    registry.create("codex-session", config);

    const calls: string[] = [];
    const fakeClient = {
      call: async (method: string) => {
        calls.push(method);
        if (method === "thread/start") {
          return { thread: { id: "thr-123" } };
        }
        if (method === "mcpServerStatus/list") {
          return {
            servers: [
              {
                name: "session_mcp_0",
                status: "connected",
                tools: [{ name: "package_search", description: "Search packages" }],
              },
              {
                name: "session_mcp_1",
                status: "failed",
                error: "spawn failed",
              },
            ],
          };
        }
        throw new Error(`Unexpected method ${method}`);
      },
    };
    (runtime as any).clientsBySession.set("codex-session", {
      client: fakeClient,
      mcpAliases: new Map([
        ["session_mcp_0", "Octocode"],
        ["session_mcp_1", "Broken Search"],
      ]),
    });

    await (runtime as any).ensureThread(
      fakeClient,
      "codex-session",
      config,
      undefined,
      [],
      false,
    );

    expect(calls).toEqual(["thread/start", "mcpServerStatus/list"]);
    expect(registry.getMcpInventory("codex-session")).toEqual([
      {
        name: "Broken Search",
        namespace: "broken_search",
        source: "configured",
        transport: "stdio",
        configured: true,
        availability: "failed",
        providerStatus: "failed",
        error: "spawn failed",
      },
      {
        name: "Octocode",
        namespace: "octocode",
        source: "configured",
        transport: "stdio",
        configured: true,
        availability: "loaded",
        providerStatus: "connected",
        tools: [{ name: "package_search", description: "Search packages" }],
      },
    ]);
  });

  test("codex composes configured skills exactly once into developer instructions", async () => {
    await manager.createSession("codex-skill-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
      systemPrompt: "Base prompt only.",
      workingDirectory: "/tmp/codex-skill-session",
      skills: [
        { name: "Plan", content: "Plan before editing." },
        { name: "Verify", content: "Run focused verification." },
      ],
      mcpServers: [
        {
          name: "Argus",
          command: "npx",
          args: ["-y", "-p", "@wix/argus", "argus-mcp"],
        },
      ],
      interactive: true,
    }));

    const options = manager.buildQueryOptionsForTesting("codex-skill-session", 0, true);
    const developerInstructions = options.developerInstructions as string;

    expect(developerInstructions).toContain("Base prompt only.");
    expect(developerInstructions).toContain("### Plan\nPlan before editing.");
    expect(developerInstructions).toContain("### Verify\nRun focused verification.");
    expect(countOccurrences(developerInstructions, "## Skills")).toBe(1);
    expect(developerInstructions).toContain("Use dynamic tools for ask_user, render_content, confirm_action, show_progress, and suggest_actions");
    expect(developerInstructions).toContain("## PLAN MODE — ACTIVE");
  });

  test("Codex notifications normalize into existing sidecar event semantics", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
      interactive: true,
    }) as any);

    const resolved: any[] = [];
    const pendingTurn = {
      sessionId: "codex-session",
      threadId: "thr-1",
      turnId: "turn-1",
      model: "gpt-5-codex",
      resultText: "",
      latestPlanText: null,
      latestToolOutputs: new Map<string, string>(),
      usage: { inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
      resolve: (value: any) => resolved.push(value),
      reject: (error: Error) => {
        throw error;
      },
    };

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");
    (runtime as any).activeTurnsBySession.set("codex-session", pendingTurn);
    (runtime as any).activeTurnsByTurnId.set("turn-1", pendingTurn);

    (runtime as any).handleNotification({
      method: "item/started",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        item: {
          type: "dynamicToolCall",
          id: "item-1",
          tool: "ask_user",
          arguments: { question: "Proceed?" },
        },
      },
    });
    (runtime as any).handleNotification({
      method: "thread/tokenUsage/updated",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        tokenUsage: {
          last: {
            inputTokens: 1000,
            cachedInputTokens: 200,
            outputTokens: 300,
          },
        },
      },
    });
    (runtime as any).handleNotification({
      method: "item/agentMessage/delta",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        delta: "Hello from Codex",
      },
    });
    (runtime as any).handleNotification({
      method: "item/reasoning/summaryTextDelta",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        delta: "Reasoning summary",
      },
    });
    (runtime as any).handleNotification({
      method: "item/completed",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        item: {
          type: "dynamicToolCall",
          id: "item-1",
          tool: "ask_user",
          success: true,
          contentItems: [{ type: "inputText", text: "{\"answer\":\"yes\"}" }],
        },
      },
    });
    (runtime as any).handleNotification({
      method: "turn/completed",
      params: {
        threadId: "thr-1",
        turn: {
          id: "turn-1",
          status: "completed",
        },
      },
    });

    expect(events).toEqual([
      {
        type: "stream.toolCall",
        sessionId: "codex-session",
        tool: "ask_user",
        input: JSON.stringify({ question: "Proceed?" }),
      },
      {
        type: "stream.token",
        sessionId: "codex-session",
        text: "Hello from Codex",
      },
      {
        type: "stream.thinking",
        sessionId: "codex-session",
        text: "Reasoning summary",
      },
      {
        type: "stream.toolResult",
        sessionId: "codex-session",
        tool: "ask_user",
        output: JSON.stringify({
          success: true,
          contentItems: [{ type: "inputText", text: "{\"answer\":\"yes\"}" }],
        }),
      },
    ]);
    expect(resolved).toEqual([
      {
        backendSessionId: "thr-1",
        resultText: "Hello from Codex",
        costDelta: 0.004025,
        inputTokens: 1000,
        outputTokens: 300,
        numTurns: 1,
      },
    ]);
  });

  test("Codex completion resolves even when notifications arrive before turn registration finishes", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-race", "codex-session");

    const resolved: any[] = [];
    const pendingTurn = {
      sessionId: "codex-session",
      threadId: "thr-race",
      turnId: null,
      model: "gpt-5-codex",
      resultText: "",
      latestPlanText: null,
      latestToolOutputs: new Map<string, string>(),
      usage: { inputTokens: 4, cachedInputTokens: 0, outputTokens: 9 },
      resolve: (value: any) => resolved.push(value),
      reject: (error: Error) => {
        throw error;
      },
    };

    (runtime as any).activeTurnsBySession.set("codex-session", pendingTurn);

    (runtime as any).handleNotification({
      method: "item/agentMessage/delta",
      params: {
        threadId: "thr-race",
        turnId: "turn-race",
        delta: "codex smoke ok",
      },
    });
    (runtime as any).handleNotification({
      method: "turn/completed",
      params: {
        threadId: "thr-race",
        turn: {
          id: "turn-race",
          status: "completed",
        },
      },
    });

    expect(events).toEqual([
      {
        type: "stream.token",
        sessionId: "codex-session",
        text: "codex smoke ok",
      },
    ]);
    expect(resolved).toEqual([
      {
        backendSessionId: "thr-race",
        resultText: "codex smoke ok",
        costDelta: 0.000095,
        inputTokens: 4,
        outputTokens: 9,
        numTurns: 1,
      },
    ]);
    expect((runtime as any).activeTurnsBySession.has("codex-session")).toBe(false);
    expect((runtime as any).activeTurnsByTurnId.has("turn-race")).toBe(false);
  });

  test("Codex dynamic tool calls return app-server compatible content items for blackboard writes", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");

    const response = await (runtime as any).handleServerRequest("codex-session", {
      id: "tool-1",
      method: "item/tool/call",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        callId: "call-1",
        tool: "blackboard_write",
        arguments: {
          key: "research.sync.dropbox_drive",
          value: "{\"status\":\"ok\"}",
        },
      },
    });

    expect(response.success).toBe(true);
    expect(response.contentItems).toHaveLength(1);
    expect(response.contentItems[0]).toMatchObject({
      type: "inputText",
    });
    const payload = JSON.parse(response.contentItems[0].text);
    expect(payload).toMatchObject({
      success: true,
      key: "research.sync.dropbox_drive",
    });
    expect(typeof payload.updatedAt).toBe("string");

    const entry = ctx.blackboard.read("research.sync.dropbox_drive");
    expect(entry?.value).toBe("{\"status\":\"ok\"}");
    expect(events).toContainEqual({
      type: "blackboard.update",
      sessionId: "codex-session",
      key: "research.sync.dropbox_drive",
      value: "{\"status\":\"ok\"}",
      writtenBy: "CodexBot",
    });
  });

  test("Codex permission approval requests map into existing confirmation flow", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");

    const approvalPromise = (runtime as any).handleServerRequest("codex-session", {
      id: "perm-1",
      method: "item/permissions/requestApproval",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        itemId: "item-1",
        reason: "Need write access for this task",
        permissions: {
          network: { enabled: true },
          fileSystem: {
            read: ["/tmp/readable"],
            write: ["/tmp/writable"],
          },
        },
      },
    });

    expect(events).toEqual([
      {
        type: "agent.confirmation",
        sessionId: "codex-session",
        confirmationId: "perm-1",
        action: "Grant additional permissions",
        reason: "Need write access for this task",
        riskLevel: "high",
        details: "network: enabled\nread: /tmp/readable\nwrite: /tmp/writable",
      },
    ]);

    const answered = await runtime.answerConfirmation("codex-session", "perm-1", true);
    expect(answered).toBe(true);
    await expect(approvalPromise).resolves.toEqual({
      permissions: {
        network: { enabled: true },
        fileSystem: {
          read: ["/tmp/readable"],
          write: ["/tmp/writable"],
        },
      },
      scope: "turn",
    });
  });

  test("Codex MCP elicitation requests map into the existing question flow", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");

    const elicitationPromise = (runtime as any).handleServerRequest("codex-session", {
      id: "elicitation-1",
      method: "mcpServer/elicitation/request",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        serverName: "filesystem",
        mode: "form",
        _meta: { source: "mcp" },
        message: "Need a ticket id before continuing",
        requestedSchema: {
          type: "object",
          properties: {
            ticket: {
              type: "string",
              title: "Ticket",
              description: "Enter the tracking ticket",
            },
            confirm: {
              type: "boolean",
              title: "Confirm",
            },
          },
          required: ["ticket"],
        },
      },
    });

    expect(events).toEqual([
      {
        type: "agent.question",
        sessionId: "codex-session",
        questionId: "elicitation-1",
        question: "Need a ticket id before continuing",
        multiSelect: false,
        private: false,
        inputType: "form",
        inputConfig: {
          fields: [
            {
              name: "ticket",
              label: "Ticket",
              type: "text",
              placeholder: "Enter the tracking ticket",
              required: true,
            },
            {
              name: "confirm",
              label: "Confirm",
              type: "toggle",
              placeholder: undefined,
              required: false,
            },
          ],
        },
      },
    ]);

    const answered = await runtime.answerQuestion(
      "codex-session",
      "elicitation-1",
      JSON.stringify({ ticket: "ABC-123", confirm: "true" }),
    );
    expect(answered).toBe(true);
    await expect(elicitationPromise).resolves.toEqual({
      action: "accept",
      content: {
        ticket: "ABC-123",
        confirm: "true",
      },
      _meta: { source: "mcp" },
    });
  });
});
