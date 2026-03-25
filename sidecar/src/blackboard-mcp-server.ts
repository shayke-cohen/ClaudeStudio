#!/usr/bin/env bun
/**
 * Standalone MCP server exposing the ClaudPeer blackboard as tools.
 * Communicates via JSON-RPC over stdio (MCP protocol).
 * Connects to the blackboard HTTP API at CLAUDPEER_HTTP_PORT (default 9850).
 *
 * Usage: bun run sidecar/src/blackboard-mcp-server.ts
 */

const HTTP_PORT = parseInt(process.env.CLAUDPEER_HTTP_PORT ?? "9850", 10);
const BASE_URL = `http://127.0.0.1:${HTTP_PORT}`;

// --- MCP stdio transport ---

const decoder = new TextDecoder();
let buffer = "";

async function readStdin(): Promise<void> {
  const reader = Bun.stdin.stream().getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    processBuffer();
  }
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
    handleMessage(JSON.parse(body));
  }
}

function sendResponse(msg: any): void {
  const body = JSON.stringify(msg);
  const header = `Content-Length: ${Buffer.byteLength(body)}\r\n\r\n`;
  process.stdout.write(header + body);
}

// --- Tool definitions ---

const TOOLS = [
  {
    name: "blackboard_read",
    description: "Read a value from the shared blackboard by key.",
    inputSchema: {
      type: "object",
      properties: { key: { type: "string", description: "The key to read" } },
      required: ["key"],
    },
  },
  {
    name: "blackboard_write",
    description: "Write a key-value pair to the shared blackboard.",
    inputSchema: {
      type: "object",
      properties: {
        key: { type: "string", description: "The key to write" },
        value: { type: "string", description: "The value to store" },
      },
      required: ["key", "value"],
    },
  },
  {
    name: "blackboard_query",
    description: "Query the blackboard with a glob pattern (e.g., 'project.*').",
    inputSchema: {
      type: "object",
      properties: { pattern: { type: "string", description: "Glob pattern to match keys" } },
      required: ["pattern"],
    },
  },
  {
    name: "blackboard_list_keys",
    description: "List all keys on the blackboard, optionally filtered by workspace scope.",
    inputSchema: {
      type: "object",
      properties: { scope: { type: "string", description: "Optional workspace scope filter" } },
    },
  },
];

// --- HTTP helpers ---

async function bbRead(key: string): Promise<any> {
  const res = await fetch(`${BASE_URL}/blackboard/read?key=${encodeURIComponent(key)}`);
  if (res.status === 404) return { error: "not_found", key };
  return res.json();
}

async function bbWrite(key: string, value: string): Promise<any> {
  const res = await fetch(`${BASE_URL}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key, value, writtenBy: "mcp-client" }),
  });
  return res.json();
}

async function bbQuery(pattern: string): Promise<any> {
  const res = await fetch(`${BASE_URL}/blackboard/query?pattern=${encodeURIComponent(pattern)}`);
  return res.json();
}

async function bbListKeys(scope?: string): Promise<any> {
  const url = scope
    ? `${BASE_URL}/blackboard/keys?scope=${encodeURIComponent(scope)}`
    : `${BASE_URL}/blackboard/keys`;
  const res = await fetch(url);
  return res.json();
}

// --- MCP message handler ---

async function handleMessage(msg: any): Promise<void> {
  if (msg.method === "initialize") {
    sendResponse({
      jsonrpc: "2.0",
      id: msg.id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "claudpeer-blackboard", version: "0.1.0" },
      },
    });
    return;
  }

  if (msg.method === "notifications/initialized") return; // no-op

  if (msg.method === "tools/list") {
    sendResponse({
      jsonrpc: "2.0",
      id: msg.id,
      result: { tools: TOOLS },
    });
    return;
  }

  if (msg.method === "tools/call") {
    const { name, arguments: args } = msg.params;
    let result: any;
    try {
      switch (name) {
        case "blackboard_read":
          result = await bbRead(args.key);
          break;
        case "blackboard_write":
          result = await bbWrite(args.key, args.value);
          break;
        case "blackboard_query":
          result = await bbQuery(args.pattern);
          break;
        case "blackboard_list_keys":
          result = await bbListKeys(args.scope);
          break;
        default:
          sendResponse({
            jsonrpc: "2.0",
            id: msg.id,
            result: { content: [{ type: "text", text: `Unknown tool: ${name}` }], isError: true },
          });
          return;
      }
      sendResponse({
        jsonrpc: "2.0",
        id: msg.id,
        result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] },
      });
    } catch (err: any) {
      sendResponse({
        jsonrpc: "2.0",
        id: msg.id,
        result: { content: [{ type: "text", text: `Error: ${err.message}` }], isError: true },
      });
    }
    return;
  }

  // Unknown method
  sendResponse({
    jsonrpc: "2.0",
    id: msg.id,
    error: { code: -32601, message: `Method not found: ${msg.method}` },
  });
}

// Start reading stdin
readStdin().catch(console.error);
