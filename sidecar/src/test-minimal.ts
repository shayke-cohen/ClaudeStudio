import { query } from "@anthropic-ai/claude-agent-sdk";

async function main() {
  console.log("[test] Starting minimal SDK test");

  try {
    const stream = query({
      prompt: "Say hello world exactly",
      options: {
        model: "claude-haiku-4-5-20251001",
        maxTurns: 1,
        cwd: "/tmp",
        permissionMode: "bypassPermissions",
        allowDangerouslySkipPermissions: true,
      }
    });

    for await (const msg of stream) {
      const type = (msg as any).type;
      if (type === "result") {
        console.log("[test] RESULT:", (msg as any).result?.substring(0, 200));
      } else if (type !== "system" && type !== "assistant") {
        console.log("[test] MSG:", type);
      }
    }
  } catch (e: any) {
    console.error("[test] ERROR:", e.message);
  }
}

main();
