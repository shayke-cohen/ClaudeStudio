import { createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { appendFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { ToolContext } from "./tool-context.js";
import { createBlackboardTools } from "./blackboard-tools.js";
import { createMessagingTools } from "./messaging-tools.js";
import { createChatTools } from "./chat-tools.js";
import { createWorkspaceTools } from "./workspace-tools.js";

const DEBUG_LOG = join(homedir(), ".claudpeer", "debug-ask-user.log");
function debugLog(msg: string) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  try { appendFileSync(DEBUG_LOG, line); } catch {}
  console.log(msg);
}
import { createAskUserTool } from "./ask-user-tool.js";
import { createRichDisplayTools } from "./rich-display-tools.js";

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
  const tools: any[] = [
    ...createBlackboardTools(ctx),
    ...createMessagingTools(ctx, callingSessionId),
    ...createChatTools(ctx, callingSessionId),
    ...createWorkspaceTools(ctx, callingSessionId),
  ];

  if (includeAskUser) {
    tools.push(...createAskUserTool(ctx, callingSessionId, onQuestionCreated));
    tools.push(...createRichDisplayTools(ctx, callingSessionId));
    debugLog(`[peerbus] ask_user + rich display tools INCLUDED for session ${callingSessionId}`);
  } else {
    debugLog(`[peerbus] ask_user tool NOT included for session ${callingSessionId} (includeAskUser=${includeAskUser})`);
  }

  const toolNames = tools.map((t: any) => t.name).join(", ");
  debugLog(`[peerbus] Creating SDK MCP server with ${tools.length} tools: [${toolNames}]`);

  return createSdkMcpServer({
    name: "peerbus",
    tools,
  });
}
