import { query } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import { existsSync, mkdirSync, writeFileSync } from "fs";
import { basename, dirname, join, resolve } from "path";
import { homedir, userInfo } from "os";
import { fileURLToPath } from "url";

// Resolve the bundled Claude Code CLI path at module load time.
// In production, build-sidecar-binary.sh copies cli.js next to odyssey-sidecar.js.
// In dev, it sits in node_modules/@anthropic-ai/claude-agent-sdk/cli.js.
const claudeCodeCliPath = (() => {
  const sidecarDir = dirname(fileURLToPath(import.meta.url));
  const bundled = resolve(sidecarDir, "claude-code-cli.js");
  if (existsSync(bundled)) return bundled;
  const devPath = resolve(sidecarDir, "../../node_modules/@anthropic-ai/claude-agent-sdk/cli.js");
  if (existsSync(devPath)) return devPath;
  return undefined;
})();
import type { AgentConfig, FileAttachment } from "../types.js";
import { PLAN_MODE_APPEND } from "../prompts/plan-mode.js";
import { logger } from "../logger.js";
import {
  mergeClaudeMcpInventory,
  observeMcpToolUse,
  parseQualifiedMcpToolName,
} from "../mcp-session-state.js";
import { buildSkillsSection } from "../utils/prompt-builder.js";
import { createPeerBusServer } from "../tools/peerbus-server.js";
import { createBrowserServer } from "../tools/browser-server.js";
import type {
  ProviderRuntime,
  RuntimeDependencies,
  RuntimeSendArgs,
  RuntimeSendResult,
} from "./runtime.js";

const FILE_PATH_REGEX = /(?:^|\s)(\/[\w.\-/]+\.(?:png|jpe?g|gif|webp|svg|ico|html?|pdf))(?:\s|$|[.,;)}\]])/gi;
const OLLAMA_SDK_INACTIVITY_TIMEOUT_MS = 180_000;

function extractFilePaths(text: string): { path: string; type: "image" | "html" | "pdf" }[] {
  const results: { path: string; type: "image" | "html" | "pdf" }[] = [];
  for (const match of text.matchAll(FILE_PATH_REGEX)) {
    const path = match[1];
    const ext = path.split(".").pop()?.toLowerCase() ?? "";
    if (["png", "jpg", "jpeg", "gif", "webp", "svg", "ico"].includes(ext)) {
      results.push({ path, type: "image" });
    } else if (["html", "htm"].includes(ext)) {
      results.push({ path, type: "html" });
    } else if (ext === "pdf") {
      results.push({ path, type: "pdf" });
    }
  }
  return results;
}

function extensionToMediaType(filePath: string): string {
  const ext = filePath.split(".").pop()?.toLowerCase() ?? "png";
  const map: Record<string, string> = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    ico: "image/x-icon",
  };
  return map[ext] ?? "image/png";
}

function normalizeClaudeEnv(): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value === "string") {
      env[key] = value;
    }
  }

  delete env.CLAUDECODE;

  const home = env.HOME?.trim() || homedir();
  const fallbackUser = (() => {
    try {
      const username = userInfo().username?.trim();
      if (username && username !== "unknown") {
        return username;
      }
    } catch {
      // Fall through to home-directory inference below.
    }
    const homeLeaf = basename(home);
    return homeLeaf && homeLeaf !== "/" ? homeLeaf : "unknown";
  })();
  const user = env.USER?.trim() || env.LOGNAME?.trim() || fallbackUser;

  env.HOME = home;
  env.USER = user;
  env.LOGNAME = env.LOGNAME?.trim() || user;
  env.SHELL = env.SHELL?.trim() || "/bin/zsh";
  env.PATH = env.PATH?.trim() || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  return env;
}

function ollamaModelsEnabled(): boolean {
  const raw = process.env.ODYSSEY_OLLAMA_MODELS_ENABLED
    ?? process.env.CLAUDESTUDIO_OLLAMA_MODELS_ENABLED;
  if (!raw) {
    return true;
  }
  return !["0", "false", "no", "off"].includes(raw.trim().toLowerCase());
}

function ollamaBaseURL(): string {
  return process.env.ODYSSEY_OLLAMA_BASE_URL?.trim()
    || process.env.CLAUDESTUDIO_OLLAMA_BASE_URL?.trim()
    || "http://127.0.0.1:11434";
}

export class ClaudeRuntime implements ProviderRuntime {
  readonly provider = "claude" as const;
  private static readonly OLLAMA_MODEL_PREFIX = "ollama:";

  constructor(private readonly deps: RuntimeDependencies) {}

  async createSession(_sessionId: string, _config: AgentConfig): Promise<void> {}

  async resumeSession(_sessionId: string, _backendSessionId: string, _config?: AgentConfig): Promise<void> {}

  async forkSession(
    _parentSessionId: string,
    _childSessionId: string,
    _config: AgentConfig,
    parentBackendSessionId?: string,
  ): Promise<string | undefined> {
    return parentBackendSessionId;
  }

  async pauseSession(_sessionId: string): Promise<void> {}

  async sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult> {
    const options = this.buildQueryOptions(
      args.sessionId,
      args.config,
      args.backendSessionId,
      args.abortController,
      args.attachments?.length ?? 0,
      args.planMode,
    );
    const initialBackendSessionId = options.sessionId ?? options.resume;
    const useOllamaBackend = ClaudeRuntime.isOllamaBackedModel(args.config.model);

    const resolvedCwd = options.cwd?.replace(/^~(?=\/|$)/, homedir());
    if (resolvedCwd && !existsSync(resolvedCwd)) {
      logger.info("session", `Creating missing cwd: ${resolvedCwd}`);
      mkdirSync(resolvedCwd, { recursive: true });
    }
    if (resolvedCwd) options.cwd = resolvedCwd;

    let prompt = this.buildPrompt(args.text, args.attachments);
    if (args.planMode === true) {
      prompt = PLAN_MODE_APPEND + "\n\nUser request: " + prompt;
    }

    const attachmentCount = args.attachments?.length ?? 0;
    const mcpNames = Object.keys(options.mcpServers ?? {});
    logger.info(
      "session",
      `query() start for ${args.sessionId} (provider=claude, model=${options.model}, cwd=${options.cwd ?? "none"}, turns=${options.maxTurns}, attachments=${attachmentCount}, mcpServers=${mcpNames.join(",")})`,
    );

    const stream = query({ prompt, options });
    const iterator = stream[Symbol.asyncIterator]();
    let resultText = "";
    const usageAccum = { inputTokens: 0, outputTokens: 0, numTurns: 0 };
    let latestBackendSessionId = initialBackendSessionId;
    let costDelta = 0;

    while (true) {
      const next = useOllamaBackend
        ? await this.waitForOllamaMessage(
          iterator.next(),
          String(options.model),
          args.abortController,
          OLLAMA_SDK_INACTIVITY_TIMEOUT_MS,
        )
        : await iterator.next();
      if (next.done) {
        break;
      }
      const message = next.value;
      if (args.abortController.signal.aborted) {
        break;
      }

      const msgType = (message as any).type ?? "unknown";
      const extra =
        msgType === "result"
          ? ` subtype="${(message as any).subtype}" result="${((message as any).result ?? "").substring(0, 200)}"`
          : "";
      logger.debug("session", `[${args.sessionId}] SDK msg type="${msgType}"${extra}`);
      const handled = await this.handleSDKMessage(args.sessionId, message, (text) => {
        resultText += text;
      }, usageAccum);
      latestBackendSessionId = handled.backendSessionId ?? latestBackendSessionId;
      costDelta += handled.costDelta;
    }

    logger.info("session", `query() done for ${args.sessionId} (${resultText.length} chars)`);

    return {
      backendSessionId: latestBackendSessionId,
      resultText,
      costDelta,
      inputTokens: usageAccum.inputTokens,
      outputTokens: usageAccum.outputTokens,
      numTurns: usageAccum.numTurns,
    };
  }

  buildTurnOptionsForTesting(
    sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    attachmentCount = 0,
    planMode?: boolean,
  ): Record<string, any> {
    return this.buildQueryOptions(
      sessionId,
      config,
      backendSessionId,
      new AbortController(),
      attachmentCount,
      planMode,
    );
  }

  async waitForOllamaMessageForTesting(
    nextMessage: Promise<IteratorResult<any>>,
    modelName: string,
    abortController: AbortController,
    timeoutMs = OLLAMA_SDK_INACTIVITY_TIMEOUT_MS,
  ): Promise<IteratorResult<any>> {
    return this.waitForOllamaMessage(nextMessage, modelName, abortController, timeoutMs);
  }

  private static readonly MODEL_ALIASES: Record<string, string> = {
    sonnet: "claude-sonnet-4-6",
    opus: "claude-opus-4-7",
    haiku: "claude-haiku-4-5-20251001",
  };

  private static resolveModel(model: string | undefined): string {
    if (!model) return "claude-sonnet-4-6";
    return ClaudeRuntime.MODEL_ALIASES[model] ?? model;
  }

  private static isOllamaBackedModel(model: string | undefined): boolean {
    return typeof model === "string"
      && model.toLowerCase().startsWith(ClaudeRuntime.OLLAMA_MODEL_PREFIX)
      && model.length > ClaudeRuntime.OLLAMA_MODEL_PREFIX.length;
  }

  private static stripOllamaPrefix(model: string): string {
    return model.slice(ClaudeRuntime.OLLAMA_MODEL_PREFIX.length);
  }

  private buildQueryOptions(
    sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    abortController: AbortController,
    attachmentCount = 0,
    planMode?: boolean,
  ): Record<string, any> {
    let maxTurns = config.maxTurns ?? 5;
    if (attachmentCount > 0 && maxTurns < 3) {
      maxTurns = 3;
    }

    const useOllamaBackend = ClaudeRuntime.isOllamaBackedModel(config.model);
    if (useOllamaBackend && !ollamaModelsEnabled()) {
      throw new Error("Ollama-backed Claude models are disabled in Odyssey Settings > Models.");
    }

    let resolvedModel = useOllamaBackend
      ? ClaudeRuntime.stripOllamaPrefix(config.model)
      : ClaudeRuntime.resolveModel(config.model);
    const usePlanMode = planMode === true;
    if (usePlanMode && !useOllamaBackend) {
      resolvedModel = ClaudeRuntime.resolveModel("opus");
      if (maxTurns < 30) maxTurns = 30;
    }

    logger.debug("session", `[${sessionId}] buildQueryOptions: planMode=${usePlanMode}, maxTurns=${maxTurns}`);
    const env = normalizeClaudeEnv();
    if (useOllamaBackend) {
      env.ANTHROPIC_BASE_URL = ollamaBaseURL();
      env.ANTHROPIC_AUTH_TOKEN = "ollama";
      env.ANTHROPIC_API_KEY = "";
    }
    const options: Record<string, any> = {
      model: resolvedModel,
      maxTurns,
      abortController,
      cwd: config.workingDirectory || undefined,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      strictMcpConfig: true,
      env,
    };
    if (claudeCodeCliPath) {
      options.pathToClaudeCodeExecutable = claudeCodeCliPath;
    }

    const appendText = this.buildSystemPromptAppend(config, usePlanMode, true);
    if (appendText) {
      options.systemPrompt = {
        type: "preset" as const,
        preset: "claude_code" as const,
        append: appendText,
      };
    } else {
      options.systemPrompt = {
        type: "preset" as const,
        preset: "claude_code" as const,
      };
    }

    if (config.maxBudget) {
      options.maxBudgetUsd = config.maxBudget;
    }

    if (config.maxThinkingTokens) {
      options.maxThinkingTokens = config.maxThinkingTokens;
    }

    const mcpServers: Record<string, any> = {};
    for (const mcp of config.mcpServers) {
      if (mcp.command) {
        mcpServers[mcp.name] = {
          type: "stdio",
          command: mcp.command,
          args: mcp.args ?? [],
          env: mcp.env ?? {},
        };
      } else if (mcp.url) {
        mcpServers[mcp.name] = {
          type: "sse",
          url: mcp.url,
        };
      }
    }

    const isInteractive = config.interactive ?? false;
    mcpServers.peerbus = createPeerBusServer(this.deps.toolCtx, sessionId, isInteractive);
    mcpServers.browser = createBrowserServer(this.deps.toolCtx);
    options.mcpServers = mcpServers;

    if (backendSessionId) {
      options.resume = backendSessionId;
    } else {
      options.sessionId = randomUUID();
    }

    return options;
  }

  private async waitForOllamaMessage(
    nextMessage: Promise<IteratorResult<any>>,
    modelName: string,
    abortController: AbortController,
    timeoutMs: number,
  ): Promise<IteratorResult<any>> {
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        nextMessage,
        new Promise<IteratorResult<any>>((_, reject) => {
          timeoutId = setTimeout(() => {
            abortController.abort();
            reject(
              new Error(
                `Ollama model ${modelName} stopped responding through Claude Code for ${timeoutMs}ms. Try another local model such as gpt-oss:20b.`,
              ),
            );
          }, timeoutMs);
        }),
      ]);
    } finally {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    }
  }

  private buildPrompt(text: string, attachments?: FileAttachment[]): string {
    if (!attachments || attachments.length === 0) {
      return text;
    }

    const tmpDir = join(homedir(), ".odyssey", "tmp-attachments");
    mkdirSync(tmpDir, { recursive: true });

    const inlineTexts: string[] = [];
    const fileRefs: string[] = [];

    for (let i = 0; i < attachments.length; i++) {
      const att = attachments[i];
      const label = att.fileName || `attachment-${i + 1}`;

      if (att.mediaType === "text/plain" || att.mediaType === "text/markdown") {
        const content = Buffer.from(att.data, "base64").toString("utf-8");
        inlineTexts.push(`--- ${label} ---\n${content}\n--- end ${label} ---`);
        continue;
      }

      const ext = this.extensionForMediaType(att.mediaType);
      const filename = `${randomUUID()}.${ext}`;
      const filePath = join(tmpDir, filename);
      writeFileSync(filePath, Buffer.from(att.data, "base64"));
      const kind = att.mediaType.startsWith("image/") ? "Image" : "File";
      fileRefs.push(`[${kind}: ${label}]: ${filePath}`);
    }

    const parts: string[] = [];
    if (fileRefs.length > 0) {
      const noun = fileRefs.length === 1 ? "file" : "files";
      parts.push(`The user has attached ${fileRefs.length} ${noun}. Read ${fileRefs.length === 1 ? "it" : "them"} with your Read tool before responding.`);
      parts.push(fileRefs.join("\n"));
    }

    if (inlineTexts.length > 0) {
      parts.push("The user has included the following text file contents:\n");
      parts.push(inlineTexts.join("\n\n"));
    }

    if (text) {
      parts.push(text);
    }

    return parts.join("\n\n");
  }

  private extensionForMediaType(mediaType: string): string {
    switch (mediaType) {
      case "image/png":
        return "png";
      case "image/jpeg":
        return "jpg";
      case "image/gif":
        return "gif";
      case "image/webp":
        return "webp";
      case "application/pdf":
        return "pdf";
      case "text/plain":
        return "txt";
      case "text/markdown":
        return "md";
      default:
        return mediaType.split("/")[1] || "dat";
    }
  }

  private buildSystemPromptAppend(config: AgentConfig, _planMode?: boolean, includePeerBus = true): string {
    let append = config.systemPrompt || "";

    if (config.interactive && includePeerBus) {
      append += `\n\n## Asking the User

You have an \`ask_user\` MCP tool available. When you need to ask the user a question, get a decision, or need clarification, you MUST use the \`ask_user\` tool instead of writing the question as regular text. The tool blocks until the user responds and returns their answer directly to you.

IMPORTANT: Never write questions as plain text output. Always use the ask_user tool so the user gets an interactive prompt.

## Rich Display

Use \`render_content\`, \`confirm_action\`, \`show_progress\`, and \`suggest_actions\` for rich chat UX instead of writing local preview files.\n`;
    }

    if (config.workingDirectory) {
      try {
        const result = Bun.spawnSync(
          ["git", "remote", "get-url", "origin"],
          { cwd: config.workingDirectory, stdout: "pipe", stderr: "pipe" },
        );
        const remoteUrl = result.stdout.toString().trim();
        if (remoteUrl.includes("github.com")) {
          append += `\n\n## GitHub Workspace

This workspace is a GitHub repository (\`${remoteUrl}\`). You can use the \`gh\` CLI (via Bash tool) to interact with issues, PRs, reviews, and releases.\n`;
        }
      } catch {
        logger.debug("session", `GitHub detection: not a git repo or git unavailable`, { cwd: config.workingDirectory });
      }
    }

    append += buildSkillsSection(config.skills ?? []);

    return append;
  }

  private recordClaudeMcpInventory(sessionId: string, mcpServers: Array<{ name: string; status: string }> | undefined): void {
    const config = this.deps.registry.getConfig(sessionId);
    if (!config) {
      return;
    }

    const inventory = mergeClaudeMcpInventory(
      config,
      this.deps.registry.getMcpInventory(sessionId),
      mcpServers ?? [],
    );
    this.deps.registry.replaceMcpInventory(sessionId, inventory);
    logger.info("session", `Effective MCP inventory for ${sessionId}`, {
      provider: "claude",
      mcpServers: inventory,
    });
  }

  private recordObservedMcpTool(sessionId: string, toolName: string): void {
    const parsed = parseQualifiedMcpToolName(toolName);
    if (!parsed) {
      return;
    }

    const inventory = observeMcpToolUse(
      this.deps.registry.getMcpInventory(sessionId),
      parsed.namespace,
      parsed.tool,
    );
    this.deps.registry.replaceMcpInventory(sessionId, inventory);
  }

  private async handleSDKMessage(
    sessionId: string,
    message: any,
    collectText: (text: string) => void,
    usageAccum: { inputTokens: number; outputTokens: number; numTurns: number },
  ): Promise<{ backendSessionId?: string; costDelta: number }> {
    let backendSessionId: string | undefined;
    let costDelta = 0;

    switch (message.type) {
      case "system":
        if (message.subtype === "init") {
          this.recordClaudeMcpInventory(sessionId, message.mcp_servers);
          if (message.session_id) {
            backendSessionId = message.session_id;
          }
        }
        break;

      case "assistant":
        if (message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "thinking" && block.thinking) {
              this.deps.emit({ type: "stream.thinking", sessionId, text: block.thinking });
            } else if (block.type === "text" && block.text) {
              collectText(block.text);
              this.deps.emit({ type: "stream.token", sessionId, text: block.text });
            } else if (block.type === "image" && block.source?.type === "base64") {
              this.deps.emit({
                type: "stream.image",
                sessionId,
                imageData: block.source.data,
                mediaType: block.source.media_type ?? "image/png",
              });
            }
          }
        }
        break;

      case "tool_use":
        if (typeof message.name === "string") {
          this.recordObservedMcpTool(sessionId, message.name);
        }
        this.deps.emit({
          type: "stream.toolCall",
          sessionId,
          tool: message.name ?? "unknown",
          input:
            typeof message.input === "string"
              ? message.input
              : JSON.stringify(message.input ?? {}),
        });
        {
          const state = this.deps.registry.get(sessionId);
          this.deps.registry.update(sessionId, {
            toolCallCount: (state?.toolCallCount ?? 0) + 1,
          });
        }
        break;

      case "tool_result": {
        this.deps.emit({
          type: "stream.toolResult",
          sessionId,
          tool: message.name ?? "unknown",
          output:
            typeof message.content === "string"
              ? message.content
              : JSON.stringify(message.content ?? {}),
        });

        const resultText =
          typeof message.content === "string"
            ? message.content
            : JSON.stringify(message.content ?? "");
        const files = extractFilePaths(resultText);
        for (const file of files) {
          try {
            if (file.type === "image") {
              const fileObj = Bun.file(file.path);
              if (await fileObj.exists()) {
                const data = await fileObj.arrayBuffer();
                const base64 = Buffer.from(data).toString("base64");
                if (base64.length < 10_000_000) {
                  this.deps.emit({
                    type: "stream.image",
                    sessionId,
                    imageData: base64,
                    mediaType: extensionToMediaType(file.path),
                    fileName: file.path.split("/").pop(),
                  });
                }
              }
            } else {
              this.deps.emit({
                type: "stream.fileCard",
                sessionId,
                filePath: file.path,
                fileType: file.type,
                fileName: file.path.split("/").pop() ?? "file",
              });
            }
          } catch {
            // Skip unreadable files.
          }
        }
        break;
      }

      case "result": {
        const cost = message.total_cost_usd ?? message.cost_usd ?? 0;
        if (cost) {
          costDelta += cost;
        }
        const usage = message.usage ?? {};
        usageAccum.inputTokens = usage.input_tokens ?? usage.inputTokens ?? 0;
        usageAccum.outputTokens = usage.output_tokens ?? usage.outputTokens ?? 0;
        usageAccum.numTurns = message.num_turns ?? 0;
        this.deps.registry.update(sessionId, {
          tokenCount: usageAccum.inputTokens + usageAccum.outputTokens,
        });
        if (message.session_id) {
          backendSessionId = message.session_id;
        }
        break;
      }

      case "error":
        throw new Error(message.error?.message ?? "SDK error");

      default:
        break;
    }

    return { backendSessionId, costDelta };
  }
}
