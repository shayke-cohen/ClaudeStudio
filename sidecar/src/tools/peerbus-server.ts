import { createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import type { ToolContext } from "./tool-context.js";
import { createBlackboardTools } from "./blackboard-tools.js";
import { createMessagingTools } from "./messaging-tools.js";
import { createChatTools } from "./chat-tools.js";
import { createWorkspaceTools } from "./workspace-tools.js";

/**
 * Creates the in-process PeerBus MCP server that gives every agent session
 * access to blackboard, messaging, chat, delegation, and workspace tools.
 *
 * The returned server config is passed directly into SDK query() options
 * alongside any external MCP servers the agent is configured with.
 */
export function createPeerBusServer(ctx: ToolContext, callingSessionId: string) {
  return createSdkMcpServer({
    name: "peerbus",
    tools: [
      ...createBlackboardTools(ctx),
      ...createMessagingTools(ctx, callingSessionId),
      ...createChatTools(ctx, callingSessionId),
      ...createWorkspaceTools(ctx, callingSessionId),
    ],
  });
}
