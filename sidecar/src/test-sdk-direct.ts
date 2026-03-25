import { query } from "@anthropic-ai/claude-agent-sdk";

const STDIO_SERVER = "/Users/shayco/ClaudPeer/sidecar/src/tools/ask-user-stdio-server.ts";

async function main() {
  console.log("[test] Starting SDK test");
  console.log("[test] process.execPath:", process.execPath);
  
  const stream = query({
    prompt: "What color do I prefer? You MUST use the ask_user tool to find out.",
    model: "claude-haiku-4-5-20251001",
    maxTurns: 3,
    cwd: "/tmp",
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    systemPrompt: {
      type: "preset" as const,
      preset: "claude_code" as const,
      append: "\n\nYou have an `ask_user` MCP tool available. Use it to ask questions.",
    },
    mcpServers: {
      "ask_user_server": {
        type: "stdio" as const,
        command: process.execPath,
        args: [STDIO_SERVER],
        env: {
          ...process.env as Record<string, string>,
          CLAUDPEER_SESSION_ID: "test-direct-001",
          CLAUDPEER_HTTP_PORT: "9850",
        }
      }
    },
    env: (() => { const e = { ...process.env } as Record<string, string | undefined>; delete e.CLAUDECODE; return e; })()
  });
  
  for await (const msg of stream) {
    const type = (msg as any).type;
    if (type === "tool_use") {
      console.log("[test] TOOL CALL:", (msg as any).name, JSON.stringify((msg as any).input ?? {}).substring(0, 200));
    } else if (type === "result") {
      console.log("[test] RESULT:", JSON.stringify(msg).substring(0, 500));
    } else if (type !== "system" && type !== "assistant") {
      console.log("[test] MSG:", type);
    }
  }
}

main().catch(console.error);
