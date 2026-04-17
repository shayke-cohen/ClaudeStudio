import { createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import type { ToolContext } from "./tool-context.js";
import { createBlackboardTools } from "./blackboard-tools.js";
import { createMessagingTools } from "./messaging-tools.js";
import { createChatTools } from "./chat-tools.js";
import { createWorkspaceTools } from "./workspace-tools.js";
import { createTaskBoardTools } from "./task-board-tools.js";
import { createConnectorTools } from "./connector-tools.js";
import { createAskUserTool } from "./ask-user-tool.js";
import { createAskAgentTool } from "./ask-agent-tool.js";
import { createRichDisplayTools } from "./rich-display-tools.js";
import { logger } from "../logger.js";
import {
  toClaudeTool,
  toCodexDynamicToolSpec,
  type SharedToolDefinition,
} from "./shared-tool.js";

/**
 * Creates the in-process PeerBus MCP server that gives every agent session
 * access to blackboard, messaging, chat, delegation, workspace, and ask-user tools.
 *
 * The returned server config is passed directly into SDK query() options
 * alongside any external MCP servers the agent is configured with.
 *
 * @param includeAskUser — set to true for interactive sessions; the ask_user tool
 *   is only included when this flag is set.
 */
export function createPeerBusServer(
  ctx: ToolContext,
  callingSessionId: string,
  includeAskUser = false,
  onQuestionCreated?: (questionId: string) => void,
) {
  const definitions = createPeerBusToolDefinitions(
    ctx,
    callingSessionId,
    includeAskUser,
    onQuestionCreated,
  );
  const tools = definitions.map((definition) => toClaudeTool(definition));

  const toolNames = tools.map((t: any) => t.name).join(", ");
  logger.debug("peerbus", `Creating SDK MCP server with ${tools.length} tools: [${toolNames}]`);

  return createSdkMcpServer({
    name: "peerbus",
    tools,
  });
}

export function createPeerBusToolDefinitions(
  ctx: ToolContext,
  callingSessionId: string,
  includeAskUser = false,
  onQuestionCreated?: (questionId: string) => void,
): SharedToolDefinition[] {
  const definitions: SharedToolDefinition[] = [
    ...createBlackboardTools(ctx),
    ...createMessagingTools(ctx, callingSessionId),
    ...createChatTools(ctx, callingSessionId),
    ...createWorkspaceTools(ctx, callingSessionId),
    ...createTaskBoardTools(ctx, callingSessionId),
    ...createConnectorTools(ctx, callingSessionId),
  ];

  if (includeAskUser) {
    definitions.push(...createAskUserTool(ctx, callingSessionId, onQuestionCreated));
    definitions.push(...createAskAgentTool(ctx, callingSessionId));
    definitions.push(...createRichDisplayTools(ctx, callingSessionId));
    logger.debug("peerbus", `ask_user + ask_agent + rich display tools INCLUDED for session ${callingSessionId}`);
  } else {
    logger.debug("peerbus", `ask_user/ask_agent tools NOT included for session ${callingSessionId} (includeAskUser=${includeAskUser})`);
  }

  return definitions;
}

export function createCodexDynamicTools(
  ctx: ToolContext,
  callingSessionId: string,
  includeAskUser = false,
  onQuestionCreated?: (questionId: string) => void,
) {
  const definitions = createPeerBusToolDefinitions(
    ctx,
    callingSessionId,
    includeAskUser,
    onQuestionCreated,
  );

  return {
    definitions,
    specs: definitions.map((definition) => toCodexDynamicToolSpec(definition)),
    handlers: new Map(definitions.map((definition) => [definition.name, definition] as const)),
  };
}
