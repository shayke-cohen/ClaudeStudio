import { createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import type { ToolContext } from "./tool-context.js";
import { createBrowserTools } from "./browser-tools.js";
import { toClaudeTool } from "./shared-tool.js";
import { logger } from "../logger.js";

/**
 * Creates the in-process browser MCP server that gives agent sessions
 * access to all browser control tools (navigate, click, type, screenshot, etc.).
 *
 * The returned server config is passed directly into SDK query() options
 * alongside any external MCP servers the agent is configured with.
 */
export function createBrowserServer(ctx: ToolContext) {
  const definitions = createBrowserTools(ctx);
  const tools = definitions.map((definition) => toClaudeTool(definition));

  const toolNames = tools.map((t) => (t as { name: string }).name).join(", ");
  logger.debug("browser", `Creating browser SDK MCP server with ${tools.length} tools: [${toolNames}]`);

  return createSdkMcpServer({
    name: "browser",
    tools,
  });
}
