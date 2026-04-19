import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { SidecarEvent } from "../../src/types.js";
import { createConnectorTools } from "../../src/tools/connector-tools.js";
import { resolveConfirmation } from "../../src/tools/rich-display-tools.js";

function createContext() {
  const events: SidecarEvent[] = [];
  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`connectors-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: (event) => events.push(event),
    spawnSession: async (sessionId) => ({ sessionId }),
    agentDefinitions: new Map(),
  };
  return { ctx, events };
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

function parseToolResult(result: any) {
  return JSON.parse(result.content[0].text);
}

describe("Connector tools", () => {
  let ctx: ToolContext;
  let events: SidecarEvent[];
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    ({ ctx, events } = createContext());
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      const url = input.toString();
      if (url.includes("chat.postMessage")) {
        return new Response(JSON.stringify({ ok: true, channel: "C123", ts: "1.0" }), { status: 200 });
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as typeof fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  test("connected read-capable provider exposes read tool", () => {
    ctx.connectors.upsert({
      id: "x-1",
      provider: "x",
      installScope: "system",
      displayName: "X Sandbox",
      grantedScopes: ["users.read", "tweet.read"],
      authMode: "pkce-native",
      writePolicy: "require-approval",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    expect(tools.some((tool) => tool.name === "x_get_profile")).toBe(true);
    expect(tools.some((tool) => tool.name === "x_post_tweet")).toBe(false);
  });

  test("read-only connection hides write tools", () => {
    ctx.connectors.upsert({
      id: "slack-1",
      provider: "slack",
      installScope: "system",
      displayName: "Slack",
      grantedScopes: ["channels:read", "chat:write"],
      authMode: "brokered",
      writePolicy: "read-only",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    expect(tools.some((tool) => tool.name === "slack_list_channels")).toBe(true);
    expect(tools.some((tool) => tool.name === "slack_post_message")).toBe(false);
  });

  test("write tools request approval and emit audit events", async () => {
    ctx.connectors.upsert({
      id: "slack-1",
      provider: "slack",
      installScope: "system",
      displayName: "Slack",
      grantedScopes: ["channels:read", "chat:write"],
      authMode: "brokered",
      writePolicy: "require-approval",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    const tool = tools.find((entry) => entry.name === "slack_post_message");
    expect(tool).toBeDefined();

    const pending = call(tool, { channel: "#ops", text: "hello" });
    await Bun.sleep(0);

    const confirmation = events.find((event) => event.type === "agent.confirmation");
    expect(confirmation?.type).toBe("agent.confirmation");
    if (confirmation?.type === "agent.confirmation") {
      resolveConfirmation(confirmation.confirmationId, true);
    }

    const parsed = parseToolResult(await pending);
    expect(parsed.ok).toBe(true);
    expect(events.some((event) => event.type === "connector.audit")).toBe(true);
  });

  test("autonomous write tools execute without confirmation", async () => {
    ctx.connectors.upsert({
      id: "x-1",
      provider: "x",
      installScope: "system",
      displayName: "X",
      grantedScopes: ["tweet.write"],
      authMode: "pkce-native",
      writePolicy: "autonomous",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    const tool = tools.find((entry) => entry.name === "x_post_tweet");
    expect(tool).toBeDefined();

    const parsed = parseToolResult(await call(tool, { text: "Ship it" }));
    expect(parsed.ok).toBe(true);
    expect(events.some((event) => event.type === "agent.confirmation")).toBe(false);
    expect(events.some((event) =>
      event.type === "connector.audit" &&
      event.action === "x_post_tweet" &&
      event.outcome === "allowed"
    )).toBe(true);
  });

  test("denied connector approval returns blocked result and denied audit", async () => {
    ctx.connectors.upsert({
      id: "slack-2",
      provider: "slack",
      installScope: "system",
      displayName: "Slack",
      grantedScopes: ["chat:write"],
      authMode: "brokered",
      writePolicy: "require-approval",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    const tool = tools.find((entry) => entry.name === "slack_post_message");
    expect(tool).toBeDefined();

    const pending = call(tool, { channel: "#ops", text: "hello" });
    await Bun.sleep(0);

    const confirmation = events.find((event) => event.type === "agent.confirmation");
    expect(confirmation?.type).toBe("agent.confirmation");
    if (confirmation?.type === "agent.confirmation") {
      resolveConfirmation(confirmation.confirmationId, false);
    }

    const parsed = parseToolResult(await pending);
    expect(parsed.approved).toBe(false);
    expect(events.some((event) =>
      event.type === "connector.audit" &&
      event.action === "slack_post_message" &&
      event.outcome === "denied"
    )).toBe(true);
  });

  test("disconnected connectors and connectors without runtime credentials expose no provider tools", () => {
    ctx.connectors.upsert({
      id: "linkedin-1",
      provider: "linkedin",
      installScope: "system",
      displayName: "LinkedIn",
      grantedScopes: ["openid", "w_member_social"],
      authMode: "pkce-native",
      writePolicy: "autonomous",
      status: "disconnected",
    }, {
      accessToken: "token",
    });

    ctx.connectors.upsert({
      id: "facebook-1",
      provider: "facebook",
      installScope: "system",
      displayName: "Facebook",
      grantedScopes: ["public_profile", "pages_manage_posts"],
      authMode: "brokered",
      writePolicy: "autonomous",
      status: "connected",
    });

    const tools = createConnectorTools(ctx, "session-1");
    expect(tools.some((tool) => tool.name === "linkedin_get_profile")).toBe(false);
    expect(tools.some((tool) => tool.name === "facebook_create_post")).toBe(false);
  });

  test("runtime failures emit failed audits and safe error payloads", async () => {
    globalThis.fetch = (async () =>
      new Response(JSON.stringify({ error: "rate limited" }), { status: 429 })) as typeof fetch;

    ctx.connectors.upsert({
      id: "x-2",
      provider: "x",
      installScope: "system",
      displayName: "X",
      grantedScopes: ["tweet.write"],
      authMode: "pkce-native",
      writePolicy: "autonomous",
      status: "connected",
    }, {
      accessToken: "token",
    });

    const tools = createConnectorTools(ctx, "session-1");
    const tool = tools.find((entry) => entry.name === "x_post_tweet");
    expect(tool).toBeDefined();

    const parsed = parseToolResult(await call(tool, { text: "Ship it" }));
    expect(parsed.error).toBe("rate limited");
    expect(parsed.provider).toBe("x");
    expect(events.some((event) =>
      event.type === "connector.audit" &&
      event.action === "x_post_tweet" &&
      event.outcome === "failed" &&
      event.summary === "rate limited"
    )).toBe(true);
  });
});
