#!/usr/bin/env bun
/**
 * Standalone MCP server exposing the ask_user tool to Claude agent sessions.
 * Communicates via JSON-RPC over stdio (MCP protocol).
 * Connects to the sidecar HTTP API at CLAUDPEER_HTTP_PORT (default 9850).
 *
 * Each interactive session spawns one instance of this server.
 * The sidecar passes the session ID via CLAUDPEER_SESSION_ID env var.
 */

const HTTP_PORT = parseInt(process.env.CLAUDPEER_HTTP_PORT ?? "9850", 10);
const SESSION_ID = process.env.CLAUDPEER_SESSION_ID ?? "unknown";
const BASE_URL = `http://127.0.0.1:${HTTP_PORT}`;

// --- MCP stdio transport ---

let buffer = "";

function startStdinReader(): void {
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk: string) => {
    buffer += chunk;
    processBuffer();
  });
  process.stdin.on("end", () => {
    process.exit(0);
  });
  process.stdin.resume();
}

function processBuffer(): void {
  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) break;
    const header = buffer.substring(0, headerEnd);
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) { buffer = buffer.substring(headerEnd + 4); continue; }
    const length = parseInt(match[1], 10);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + length) break;
    const body = buffer.substring(bodyStart, bodyStart + length);
    buffer = buffer.substring(bodyStart + length);
    handleMessage(JSON.parse(body)).catch((err) => {
      process.stderr.write(`[ask-user-mcp] Error handling message: ${err.message}\n`);
    });
  }
}

function sendMessage(msg: unknown): void {
  const body = JSON.stringify(msg);
  const header = `Content-Length: ${Buffer.byteLength(body)}\r\n\r\n`;
  process.stdout.write(header + body);
}

// --- Tool definitions ---

const TOOLS = [
  {
    name: "ask_user",
    description:
      "Ask the user a question and wait for their answer. Blocks until the user responds. Use this when you need clarification, a decision, or confirmation before proceeding. By default, your question is private (not visible to other agents in group chats).",
    inputSchema: {
      type: "object",
      properties: {
        question: { type: "string", description: "The question to ask the user" },
        options: {
          type: "array",
          description: "Optional structured choices. If omitted, the user types a free-text answer.",
          items: {
            type: "object",
            properties: {
              label: { type: "string", description: "Short display text for this option" },
              description: { type: "string", description: "Explanation of what this option means" },
            },
            required: ["label"],
          },
        },
        multi_select: {
          type: "boolean",
          description: "Allow the user to select multiple options (default: false)",
          default: false,
        },
        private: {
          type: "boolean",
          description: "If true (default), the question is only visible to the user — other agents in a group chat won't see it.",
          default: true,
        },
      },
      required: ["question"],
    },
  },
];

// --- Message handler ---

async function handleMessage(msg: any): Promise<void> {
  const { id, method, params } = msg;

  if (method === "initialize") {
    sendMessage({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "ask-user", version: "1.0.0" },
      },
    });
    return;
  }

  if (method === "notifications/initialized") {
    return;
  }

  if (method === "tools/list") {
    sendMessage({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
    return;
  }

  if (method === "tools/call") {
    const toolName = params?.name;
    const args = params?.arguments ?? {};

    if (toolName === "ask_user") {
      const result = await callAskUser(args);
      sendMessage({ jsonrpc: "2.0", id, result });
      return;
    }

    sendMessage({
      jsonrpc: "2.0",
      id,
      error: { code: -32601, message: `Unknown tool: ${toolName}` },
    });
    return;
  }

  // Unknown method — return method not found
  sendMessage({
    jsonrpc: "2.0",
    id: id ?? null,
    error: { code: -32601, message: `Method not found: ${method}` },
  });
}

async function callAskUser(args: {
  question: string;
  options?: { label: string; description?: string }[];
  multi_select?: boolean;
  private?: boolean;
}): Promise<{ content: { type: "text"; text: string }[] }> {
  const body = {
    question: args.question,
    options: args.options,
    multiSelect: args.multi_select ?? false,
    private: args.private ?? true,
  };

  process.stderr.write(`[ask-user-mcp] Asking: "${args.question.substring(0, 80)}" (session=${SESSION_ID})\n`);

  // POST to sidecar to create the question — blocks until answered (long-poll)
  const response = await fetch(`${BASE_URL}/api/v1/sessions/${SESSION_ID}/questions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    // 6 minute timeout — longer than the 5-minute sidecar timeout
    signal: AbortSignal.timeout(6 * 60 * 1000),
  });

  if (!response.ok) {
    const errText = await response.text().catch(() => "unknown error");
    throw new Error(`ask_user HTTP error ${response.status}: ${errText}`);
  }

  const result = await response.json() as { answer: string; selectedOptions?: string[] };
  process.stderr.write(`[ask-user-mcp] Got answer for session=${SESSION_ID}\n`);

  const output: { answer: string; selectedOptions?: string[] } = { answer: result.answer };
  if (result.selectedOptions && result.selectedOptions.length > 0) {
    output.selectedOptions = result.selectedOptions;
  }

  return {
    content: [{ type: "text", text: JSON.stringify(output) }],
  };
}

// --- Start ---
startStdinReader();
