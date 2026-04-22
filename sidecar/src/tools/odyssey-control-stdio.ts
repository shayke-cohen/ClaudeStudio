import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { CallToolRequestSchema, ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import { odysseyControlToolDefinitions } from "./odyssey-control-server.js";
import { toCodexDynamicToolSpec } from "./shared-tool.js";

export async function runOdysseyControlStdio() {
  const server = new Server({ name: "odyssey-control", version: "1.0.0" }, { capabilities: { tools: {} } });

  const toolSpecs = odysseyControlToolDefinitions.map((def) => ({
    def,
    spec: toCodexDynamicToolSpec(def),
  }));

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: toolSpecs.map(({ spec }) => ({
      name: spec.name,
      description: spec.description,
      inputSchema: spec.inputSchema as any,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const entry = toolSpecs.find((t) => t.spec.name === request.params.name);
    if (!entry) {
      return { content: [{ type: "text", text: `Unknown tool: ${request.params.name}` }], isError: true };
    }
    try {
      const result = await entry.def.execute(request.params.arguments ?? {});
      return { content: result.content };
    } catch (e) {
      return { content: [{ type: "text", text: String(e) }], isError: true };
    }
  });

  const transport = new StdioServerTransport();

  await new Promise<void>((resolve, reject) => {
    transport.onclose = resolve;
    transport.onerror = reject;
    server.connect(transport).catch(reject);
  });
}
