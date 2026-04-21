import { query } from "@anthropic-ai/claude-agent-sdk";
import { existsSync } from "fs";
import { resolve, dirname, basename } from "path";
import { fileURLToPath } from "url";
import { homedir, userInfo } from "os";
import { logger } from "./logger.js";

const _claudeCodeCliPath = (() => {
  const sidecarDir = dirname(fileURLToPath(import.meta.url));
  const bundled = resolve(sidecarDir, "claude-code-cli.js");
  if (existsSync(bundled)) return bundled;
  const devPath = resolve(sidecarDir, "../../node_modules/@anthropic-ai/claude-agent-sdk/cli.js");
  if (existsSync(devPath)) return devPath;
  return undefined;
})();

const MODEL_ALIASES: Record<string, string> = {
  sonnet: "claude-sonnet-4-6",
  opus: "claude-opus-4-7",
  haiku: "claude-haiku-4-5-20251001",
};

function resolveModel(model: string | undefined): string {
  if (!model) return "claude-sonnet-4-6";
  return MODEL_ALIASES[model] ?? model;
}

function buildEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value === "string") env[key] = value;
  }
  delete env.CLAUDECODE;

  const home = env.HOME?.trim() || homedir();
  const fallbackUser = (() => {
    try {
      const username = userInfo().username?.trim();
      if (username && username !== "unknown") return username;
    } catch { /* ignore */ }
    const leaf = basename(home);
    return leaf && leaf !== "/" ? leaf : "unknown";
  })();
  env.HOME = home;
  env.USER = env.USER?.trim() || env.LOGNAME?.trim() || fallbackUser;
  env.LOGNAME = env.LOGNAME?.trim() || env.USER;
  env.SHELL = env.SHELL?.trim() || "/bin/zsh";
  env.PATH = env.PATH?.trim() || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  return env;
}

const GENERATION_TIMEOUT_MS = 90_000;

export class GenerationService {
  /**
   * Single-turn generation via the Agent SDK (uses Claude Code auth, no API key needed).
   * model: "sonnet" | "opus" | "haiku" | full model ID (defaults to "sonnet")
   */
  async generate(systemInstructions: string, userRequest: string, model?: string): Promise<string> {
    const resolvedModel = resolveModel(model);
    const prompt = `${userRequest}\n\nRespond with ONLY valid JSON as specified above. No markdown, no code fences, no explanations.`;

    const abortController = new AbortController();
    abortController.signal.addEventListener("abort", () => {
      logger.warn("generation", "AbortController fired — timeout or external cancellation");
    });
    const timeoutId = setTimeout(() => {
      logger.warn("generation", `Generation timed out after ${GENERATION_TIMEOUT_MS}ms`);
      abortController.abort();
    }, GENERATION_TIMEOUT_MS);

    const options: Record<string, any> = {
      model: resolvedModel,
      maxTurns: 1,
      abortController,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      strictMcpConfig: true,
      mcpServers: {},
      settingSources: [],
      cwd: process.cwd(),
      env: buildEnv(),
      // Must use the claude_code preset so the SDK authenticates via Claude Code's
      // Keychain OAuth token. A plain string here would require an API key.
      systemPrompt: {
        type: "preset" as const,
        preset: "claude_code" as const,
        append: systemInstructions,
      },
      stderr: (data: string) => logger.debug("generation", `subprocess stderr: ${data.trim()}`),
    };
    if (_claudeCodeCliPath) options.pathToClaudeCodeExecutable = _claudeCodeCliPath;

    logger.info("generation", `generate: starting Agent SDK query (model: ${resolvedModel})`);

    try {
      const stream = query({ prompt, options });
      const iterator = stream[Symbol.asyncIterator]();
      let resultText = "";

      while (true) {
        const next = await iterator.next();
        if (next.done) break;
        const msg = next.value as any;
        logger.debug("generation", `SDK message type="${msg.type}" subtype="${msg.subtype ?? ""}"`);
        if (abortController.signal.aborted) break;
        if (msg.type === "assistant") {
          for (const block of msg.message?.content ?? []) {
            if (block.type === "text" && block.text) resultText += block.text;
          }
        }
      }

      logger.info("generation", `generate: done (resultText.length=${resultText.length})`);
      const result = resultText.trim();
      if (!result) throw new Error("Generation produced no output");
      return result;
    } catch (err: any) {
      if (abortController.signal.aborted) {
        const timeoutErr = new Error(`Generation timed out after ${GENERATION_TIMEOUT_MS / 1000}s`);
        logger.error("generation", `generate error: ${timeoutErr.message}`);
        throw timeoutErr;
      }
      logger.error("generation", `generate error: ${err?.message ?? err}`);
      throw err;
    } finally {
      clearTimeout(timeoutId);
    }
  }

  /** Extract the first valid JSON object from text that may contain markdown or prose. */
  extractJSON(text: string): string {
    let cleaned = text.trim();
    if (cleaned.startsWith("```")) {
      cleaned = cleaned.replace(/^```(?:json)?\s*\n?/, "").replace(/\n?```\s*$/, "");
    }
    try { JSON.parse(cleaned); return cleaned; } catch { /* fall through */ }
    const firstBrace = cleaned.indexOf("{");
    const lastBrace = cleaned.lastIndexOf("}");
    if (firstBrace !== -1 && lastBrace > firstBrace) {
      const extracted = cleaned.substring(firstBrace, lastBrace + 1);
      try { JSON.parse(extracted); return extracted; } catch { /* fall through */ }
    }
    return cleaned;
  }
}
