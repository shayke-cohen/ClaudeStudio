import { query } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import { mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { AgentConfig, FileAttachment, SidecarEvent } from "./types.js";
import type { SessionRegistry } from "./stores/session-registry.js";
import type { ToolContext } from "./tools/tool-context.js";
import { createPeerBusServer } from "./tools/peerbus-server.js";

type EventEmitter = (event: SidecarEvent) => void;

export class SessionManager {
  private registry: SessionRegistry;
  private emit: EventEmitter;
  private activeAborts = new Map<string, AbortController>();
  private toolCtx: ToolContext;
  private autonomousResults = new Map<string, { resolve: (result: string) => void }>();

  constructor(emit: EventEmitter, registry: SessionRegistry, toolCtx: ToolContext) {
    this.emit = emit;
    this.registry = registry;
    this.toolCtx = toolCtx;
  }

  async createSession(conversationId: string, config: AgentConfig): Promise<void> {
    if (this.registry.get(conversationId)) {
      console.log(`[session] Session ${conversationId} already exists, skipping create`);
      return;
    }
    this.registry.create(conversationId, config);
    console.log(`[session] Created session ${conversationId} for "${config.name}" (model: ${config.model})`);
  }

  async sendMessage(sessionId: string, text: string, attachments?: FileAttachment[]): Promise<void> {
    const config = this.registry.getConfig(sessionId);
    if (!config) {
      this.emit({ type: "session.error", sessionId, error: "Session not found" });
      return;
    }

    const state = this.registry.get(sessionId);
    if (!state) {
      this.emit({ type: "session.error", sessionId, error: "Session state not found" });
      return;
    }

    const existingAbort = this.activeAborts.get(sessionId);
    if (existingAbort) {
      console.log(`[session] Aborting previous query for ${sessionId}`);
      existingAbort.abort();
    }

    const abortController = new AbortController();
    this.activeAborts.set(sessionId, abortController);
    this.registry.update(sessionId, { status: "active" });

    try {
      const options = this.buildQueryOptions(sessionId, config, state.claudeSessionId, abortController, attachments?.length ?? 0);
      const sdkSessionId = options.sessionId ?? options.resume;

      const prompt = this.buildPrompt(text, attachments);
      const attachmentCount = attachments?.length ?? 0;
      console.log(`[session] query() start for ${sessionId} (${config.model}, ${attachmentCount} attachments)`);
      const stream = query({ prompt, options });
      let resultText = "";

      for await (const message of stream) {
        if (abortController.signal.aborted) break;
        this.handleSDKMessage(sessionId, message, (t) => { resultText += t; });
      }

      console.log(`[session] query() done for ${sessionId} (${resultText.length} chars)`);

      if (sdkSessionId && !state.claudeSessionId) {
        this.registry.update(sessionId, { claudeSessionId: sdkSessionId });
      }

      const sessionState = this.registry.get(sessionId);
      this.emit({
        type: "session.result",
        sessionId,
        result: resultText || "(no text response)",
        cost: sessionState?.cost ?? 0,
      });
      this.registry.update(sessionId, { status: "completed" });

      const waiter = this.autonomousResults.get(sessionId);
      if (waiter) {
        waiter.resolve(resultText);
        this.autonomousResults.delete(sessionId);
      }
    } catch (err: any) {
      if (abortController.signal.aborted) {
        this.registry.update(sessionId, { status: "paused" });
      } else {
        const errMsg = err.message ?? String(err);
        console.error(`[session:${sessionId}] Error: ${errMsg}`);
        if (err.stack) console.error(`[session:${sessionId}] Stack: ${err.stack.substring(0, 500)}`);
        this.emit({
          type: "session.error",
          sessionId,
          error: errMsg,
        });
        this.registry.update(sessionId, { status: "failed" });

        const waiter = this.autonomousResults.get(sessionId);
        if (waiter) {
          waiter.resolve(`Error: ${errMsg}`);
          this.autonomousResults.delete(sessionId);
        }
      }
    } finally {
      this.activeAborts.delete(sessionId);
    }
  }

  /**
   * Spawn an autonomous session for delegation.
   * If waitForResult is true, blocks until the session completes.
   */
  async spawnAutonomous(
    sessionId: string,
    config: AgentConfig,
    initialPrompt: string,
    waitForResult: boolean,
  ): Promise<{ sessionId: string; result?: string }> {
    await this.createSession(sessionId, config);

    if (waitForResult) {
      const resultPromise = new Promise<string>((resolve) => {
        this.autonomousResults.set(sessionId, { resolve });
      });
      this.sendMessage(sessionId, initialPrompt).catch((err) => {
        console.error(`[session:${sessionId}] Autonomous send error:`, err);
      });
      const result = await resultPromise;
      return { sessionId, result };
    }

    this.sendMessage(sessionId, initialPrompt).catch((err) => {
      console.error(`[session:${sessionId}] Autonomous send error:`, err);
    });
    return { sessionId };
  }

  async resumeSession(sessionId: string, claudeSessionId: string): Promise<void> {
    this.registry.update(sessionId, { claudeSessionId, status: "active" });
    this.emit({
      type: "stream.token",
      sessionId,
      text: "Session context restored. Send a message to continue.\n",
    });
  }

  async forkSession(sessionId: string): Promise<string> {
    const config = this.registry.getConfig(sessionId);
    const forkedId = `${sessionId}-fork-${Date.now()}`;
    if (config) {
      this.registry.create(forkedId, config);
    }
    this.emit({
      type: "stream.token",
      sessionId: forkedId,
      text: `Forked from session ${sessionId}.\n`,
    });
    return forkedId;
  }

  async pauseSession(sessionId: string): Promise<void> {
    const abort = this.activeAborts.get(sessionId);
    if (abort) {
      abort.abort();
    }
    this.registry.update(sessionId, { status: "paused" });
  }

  listSessions() {
    return this.registry.list();
  }

  private buildQueryOptions(
    sessionId: string,
    config: AgentConfig,
    claudeSessionId: string | undefined,
    abortController: AbortController,
    attachmentCount: number = 0,
  ): Record<string, any> {
    let maxTurns = config.maxTurns ?? 5;
    if (attachmentCount > 0 && maxTurns < 3) {
      maxTurns = 3;
    }
    const options: Record<string, any> = {
      model: config.model || "claude-sonnet-4-6",
      maxTurns,
      abortController,
      cwd: config.workingDirectory || undefined,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
    };

    if (config.systemPrompt) {
      options.systemPrompt = {
        type: "preset" as const,
        preset: "claude_code" as const,
        append: this.buildSystemPromptAppend(config),
      };
    } else {
      options.systemPrompt = { type: "preset" as const, preset: "claude_code" as const };
    }

    if (config.allowedTools.length > 0) {
      options.allowedTools = config.allowedTools;
    }

    if (config.maxBudget) {
      options.maxBudgetUsd = config.maxBudget;
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

    mcpServers["peerbus"] = createPeerBusServer(this.toolCtx, sessionId);
    options.mcpServers = mcpServers;

    if (claudeSessionId) {
      options.resume = claudeSessionId;
    } else {
      options.sessionId = randomUUID();
    }

    return options;
  }

  private buildPrompt(text: string, attachments?: FileAttachment[]): string {
    if (!attachments || attachments.length === 0) {
      return text;
    }

    const tmpDir = join(homedir(), ".claudpeer", "tmp-attachments");
    mkdirSync(tmpDir, { recursive: true });

    const inlineTexts: string[] = [];
    const fileRefs: string[] = [];

    for (let i = 0; i < attachments.length; i++) {
      const att = attachments[i];
      const label = att.fileName || `attachment-${i + 1}`;

      if (att.mediaType === "text/plain" || att.mediaType === "text/markdown") {
        const content = Buffer.from(att.data, "base64").toString("utf-8");
        inlineTexts.push(`--- ${label} ---\n${content}\n--- end ${label} ---`);
      } else {
        const ext = this.extensionForMediaType(att.mediaType);
        const filename = `${randomUUID()}.${ext}`;
        const filePath = join(tmpDir, filename);
        writeFileSync(filePath, Buffer.from(att.data, "base64"));
        const kind = att.mediaType.startsWith("image/") ? "Image" : "File";
        fileRefs.push(`[${kind}: ${label}]: ${filePath}`);
      }
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
      case "image/png": return "png";
      case "image/jpeg": return "jpg";
      case "image/gif": return "gif";
      case "image/webp": return "webp";
      case "application/pdf": return "pdf";
      case "text/plain": return "txt";
      case "text/markdown": return "md";
      default: return mediaType.split("/")[1] || "dat";
    }
  }

  private buildSystemPromptAppend(config: AgentConfig): string {
    let append = config.systemPrompt || "";

    if (config.skills && config.skills.length > 0) {
      append += "\n\n## Skills\n\n";
      for (const skill of config.skills) {
        append += `### ${skill.name}\n${skill.content}\n\n`;
      }
    }

    return append;
  }

  private handleSDKMessage(
    sessionId: string,
    message: any,
    collectText: (text: string) => void,
  ): void {
    switch (message.type) {
      case "assistant":
        if (message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "text" && block.text) {
              collectText(block.text);
              this.emit({ type: "stream.token", sessionId, text: block.text });
            }
          }
        }
        break;

      case "tool_use":
        this.emit({
          type: "stream.toolCall",
          sessionId,
          tool: message.name ?? "unknown",
          input: typeof message.input === "string"
            ? message.input
            : JSON.stringify(message.input ?? {}),
        });
        break;

      case "tool_result":
        this.emit({
          type: "stream.toolResult",
          sessionId,
          tool: message.name ?? "unknown",
          output: typeof message.content === "string"
            ? message.content
            : JSON.stringify(message.content ?? {}),
        });
        break;

      case "result":
        if (message.cost_usd != null) {
          const state = this.registry.get(sessionId);
          this.registry.update(sessionId, {
            cost: (state?.cost ?? 0) + message.cost_usd,
          });
        }
        if (message.session_id) {
          this.registry.update(sessionId, { claudeSessionId: message.session_id });
        }
        break;

      case "error":
        this.emit({
          type: "session.error",
          sessionId,
          error: message.error?.message ?? "SDK error",
        });
        break;

      default:
        break;
    }
  }
}
