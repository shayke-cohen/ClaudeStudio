import { query } from "@anthropic-ai/claude-agent-sdk";
import { writeFileSync } from "fs";

const STDIO_SERVER = "/Users/shayco/ClaudPeer/sidecar/src/tools/ask-user-stdio-server.ts";
const DEBUG_FILE = "/tmp/claude-debug-mcp.log";

console.log("[debug] process.execPath:", process.execPath);
console.log("[debug] CLAUDECODE:", process.env.CLAUDECODE);

const env: Record<string, string | undefined> = { ...process.env };
delete env.CLAUDECODE;

const stream = query({
  prompt: "Use ask_user to ask my name. Say what tools you have available.",
  options: {
    model: "claude-haiku-4-5-20251001",
    maxTurns: 2,
    cwd: "/tmp",
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    debug: true,
    debugFile: DEBUG_FILE,
    env,
    mcpServers: {
      "ask_user_server": {
        type: "stdio" as const,
        command: process.execPath,
        args: [STDIO_SERVER],
        env: {
          CLAUDPEER_SESSION_ID: "debug-001",
          CLAUDPEER_HTTP_PORT: "9850",
          PATH: process.env.PATH ?? "",
          HOME: process.env.HOME ?? "",
        }
      }
    }
  }
});

for await (const msg of stream) {
  const type = (msg as any).type;
  if (type === "result") {
    console.log("[debug] RESULT:", (msg as any).result?.substring(0, 400));
    console.log("[debug] errors:", JSON.stringify((msg as any).errors));
  } else if (type !== "system" && type !== "assistant" && type !== "user") {
    console.log("[debug] MSG:", type);
  }
}

console.log("[debug] Check debug log at:", DEBUG_FILE);
