import { query } from "@anthropic-ai/claude-agent-sdk";
import { randomUUID } from "crypto";
import { existsSync, mkdirSync, writeFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { AgentConfig, BulkResumeEntry, FileAttachment, SidecarEvent } from "./types.js";
import type { SessionRegistry } from "./stores/session-registry.js";
import type { ToolContext } from "./tools/tool-context.js";
import { createPeerBusServer } from "./tools/peerbus-server.js";
import { pendingQuestions, questionsBySession } from "./tools/ask-user-tool.js";
import { PLAN_MODE_APPEND } from "./prompts/plan-mode.js";
import { logger } from "./logger.js";

const FILE_PATH_REGEX = /(?:^|\s)(\/[\w.\-/]+\.(?:png|jpe?g|gif|webp|svg|ico|html?|pdf))(?:\s|$|[.,;)}\]])/gi;

export function extractFilePaths(text: string): { path: string; type: "image" | "html" | "pdf" }[] {
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
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg",
    gif: "image/gif", webp: "image/webp", svg: "image/svg+xml", ico: "image/x-icon",
  };
  return map[ext] ?? "image/png";
}

type EventEmitter = (event: SidecarEvent) => void;

export class SessionManager {
  private registry: SessionRegistry;
  private emit: EventEmitter;
  private activeAborts = new Map<string, AbortController>();
  private toolCtx: ToolContext;
  private autonomousResults = new Map<string, { resolve: (result: string) => void }>();
  /** Tracks questionIds issued by each session for cleanup on pause. */

  constructor(emit: EventEmitter, registry: SessionRegistry, toolCtx: ToolContext) {
    this.emit = emit;
    this.registry = registry;
    this.toolCtx = toolCtx;
  }

  updateSessionCwd(sessionId: string, workingDirectory: string): void {
    this.registry.updateConfig(sessionId, { workingDirectory });
  }

  async createSession(conversationId: string, config: AgentConfig): Promise<void> {
    if (this.registry.get(conversationId)) {
      logger.info("session", `Session ${conversationId} already exists, skipping create`);
      return;
    }
    this.registry.create(conversationId, config);
    logger.info("session", `Created session ${conversationId} for "${config.name}" (model: ${config.model})`);
  }

  async sendMessage(sessionId: string, text: string, attachments?: FileAttachment[], planMode?: boolean): Promise<void> {
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
      logger.info("session", `Aborting previous query for ${sessionId}`);
      existingAbort.abort();
    }

    const abortController = new AbortController();
    this.activeAborts.set(sessionId, abortController);
    this.registry.update(sessionId, { status: "active" });

    try {
      const options = this.buildQueryOptions(sessionId, config, state.claudeSessionId, abortController, attachments?.length ?? 0, planMode);
      const sdkSessionId = options.sessionId ?? options.resume;

      if (options.cwd && !existsSync(options.cwd)) {
        logger.info("session", `Creating missing cwd: ${options.cwd}`);
        mkdirSync(options.cwd, { recursive: true });
      }

      let prompt = this.buildPrompt(text, attachments);
      // Inject plan mode instructions into the user message (not system prompt)
      // — proven by A/B test to be more effective than system prompt append
      if (planMode === true) {
        prompt = PLAN_MODE_APPEND + "\n\nUser request: " + prompt;
      }
      const attachmentCount = attachments?.length ?? 0;
      const mcpNames = Object.keys(options.mcpServers ?? {});
      logger.info("session", `query() start for ${sessionId} (model=${options.model}, cwd=${options.cwd ?? "none"}, turns=${options.maxTurns}, attachments=${attachmentCount}, mcpServers=${mcpNames.join(",")})`);
      const stream = query({ prompt, options });
      let resultText = "";
      const usageAccum = { inputTokens: 0, outputTokens: 0, numTurns: 0 };

      for await (const message of stream) {
        if (abortController.signal.aborted) break;
        const msgType = (message as any).type ?? "unknown";
        const extra = msgType === "result" ? ` subtype="${(message as any).subtype}" result="${((message as any).result ?? "").substring(0, 200)}"` : "";
        logger.debug("session", `[${sessionId}] SDK msg type="${msgType}"${extra}`);
        await this.handleSDKMessage(sessionId, message, (t) => { resultText += t; }, usageAccum);
      }

      logger.info("session", `query() done for ${sessionId} (${resultText.length} chars)`);

      if (sdkSessionId && !state.claudeSessionId) {
        this.registry.update(sessionId, { claudeSessionId: sdkSessionId });
      }

      const sessionState = this.registry.get(sessionId);
      logger.info("session", `[${sessionId}] Emitting session.result: cost=${sessionState?.cost ?? 0}, inputTokens=${usageAccum.inputTokens}, outputTokens=${usageAccum.outputTokens}, numTurns=${usageAccum.numTurns}, toolCallCount=${sessionState?.toolCallCount ?? 0}`);
      this.emit({
        type: "session.result",
        sessionId,
        result: resultText || "(no text response)",
        cost: sessionState?.cost ?? 0,
        inputTokens: usageAccum.inputTokens,
        outputTokens: usageAccum.outputTokens,
        numTurns: usageAccum.numTurns,
        toolCallCount: sessionState?.toolCallCount ?? 0,
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
        logger.error("session", `[${sessionId}] Error: ${errMsg}`, {
          stack: err.stack?.substring(0, 500),
        });
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
        logger.error("session", `[${sessionId}] Autonomous send error: ${err}`);
      });
      const result = await resultPromise;
      return { sessionId, result };
    }

    this.sendMessage(sessionId, initialPrompt).catch((err) => {
      logger.error("session", `[${sessionId}] Autonomous send error: ${err}`);
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

  async bulkResume(sessions: BulkResumeEntry[]): Promise<void> {
    let restored = 0;
    for (const entry of sessions) {
      if (!this.registry.get(entry.sessionId)) {
        this.registry.create(entry.sessionId, entry.agentConfig);
      }
      this.registry.update(entry.sessionId, {
        claudeSessionId: entry.claudeSessionId,
        status: "active",
      });
      restored++;
    }
    logger.info("session", `Bulk resume: restored ${restored}/${sessions.length} sessions`);
  }

  async forkSession(parentSessionId: string, childSessionId: string): Promise<void> {
    const config = this.registry.getConfig(parentSessionId);
    const parentState = this.registry.get(parentSessionId);
    if (config) {
      this.registry.create(childSessionId, config);
      if (parentState?.claudeSessionId) {
        this.registry.update(childSessionId, { claudeSessionId: parentState.claudeSessionId });
      }
    }
    this.emit({
      type: "session.forked",
      parentSessionId,
      childSessionId,
    });
  }

  async pauseSession(sessionId: string): Promise<void> {
    const abort = this.activeAborts.get(sessionId);
    if (abort) {
      abort.abort();
    }
    // Resolve any pending ask_user questions for this session (so the agent can exit cleanly)
    const qids = questionsBySession.get(sessionId);
    if (qids) {
      for (const qid of [...qids]) {
        const pending = pendingQuestions.get(qid);
        if (pending) {
          clearTimeout(pending.timer);
          pending.resolve({ answer: "[Session was paused before you could answer.]" });
          pendingQuestions.delete(qid);
        }
      }
      questionsBySession.delete(sessionId);
    }
    this.registry.update(sessionId, { status: "paused" });
  }

  listSessions() {
    return this.registry.list();
  }

  private static readonly MODEL_ALIASES: Record<string, string> = {
    sonnet: "claude-sonnet-4-6",
    opus: "claude-opus-4-6",
    haiku: "claude-haiku-4-5-20251001",
  };

  private static resolveModel(model: string | undefined): string {
    if (!model) return "claude-sonnet-4-6";
    return SessionManager.MODEL_ALIASES[model] ?? model;
  }

  private buildQueryOptions(
    sessionId: string,
    config: AgentConfig,
    claudeSessionId: string | undefined,
    abortController: AbortController,
    attachmentCount: number = 0,
    planMode?: boolean,
  ): Record<string, any> {
    let maxTurns = config.maxTurns ?? 5;
    if (attachmentCount > 0 && maxTurns < 3) {
      maxTurns = 3;
    }
    let resolvedModel = SessionManager.resolveModel(config.model);
    const usePlanMode = planMode === true;
    // Plan mode: use Opus for better instruction following + more turns for exploration
    if (usePlanMode) {
      resolvedModel = "claude-opus-4-6";
      if (maxTurns < 30) maxTurns = 30;
    }
    logger.debug("session", `[${sessionId}] buildQueryOptions: planMode=${usePlanMode}, maxTurns=${maxTurns}`);
    const env = { ...process.env };
    delete env.CLAUDECODE;
    const options: Record<string, any> = {
      model: resolvedModel,
      maxTurns,
      abortController,
      cwd: config.workingDirectory || undefined,
      // Note: we do NOT use permissionMode:"plan" because it blocks MCP tools
      // (ask_user, render_content, show_progress, suggest_actions).
      // Plan mode behavior is enforced via user message injection instead.
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      env,
      // Grant permissions for all MCP peerbus tools (ask_user, render_content, etc.)
      // Without this, bypassPermissions only covers built-in tools and MCP calls get denied.
      settings: {
        permissions: {
          allow: [
            "mcp__peerbus__ask_user",
            "mcp__peerbus__render_content",
            "mcp__peerbus__confirm_action",
            "mcp__peerbus__show_progress",
            "mcp__peerbus__suggest_actions",
            "mcp__peerbus__blackboard_read",
            "mcp__peerbus__blackboard_write",
            "mcp__peerbus__blackboard_query",
            "mcp__peerbus__blackboard_subscribe",
            "mcp__peerbus__peer_send_message",
            "mcp__peerbus__peer_broadcast",
            "mcp__peerbus__peer_receive_messages",
            "mcp__peerbus__peer_list_agents",
            "mcp__peerbus__peer_delegate_task",
            "mcp__peerbus__peer_chat_start",
            "mcp__peerbus__peer_chat_reply",
            "mcp__peerbus__peer_chat_listen",
            "mcp__peerbus__peer_chat_close",
            "mcp__peerbus__peer_chat_invite",
            "mcp__peerbus__group_invite_agent",
            "mcp__peerbus__workspace_create",
            "mcp__peerbus__workspace_join",
            "mcp__peerbus__workspace_list",
            "mcp__peerbus__task_board_list",
            "mcp__peerbus__task_board_create",
            "mcp__peerbus__task_board_claim",
            "mcp__peerbus__task_board_update",
          ],
        },
      },
    };

    const appendText = this.buildSystemPromptAppend(config, usePlanMode);
    if (appendText) {
      options.systemPrompt = {
        type: "preset" as const,
        preset: "claude_code" as const,
        append: appendText,
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
    logger.debug("session", `[${sessionId}] config.interactive=${config.interactive}, isInteractive=${isInteractive}, maxTurns=${config.maxTurns}`);
    // Include ask_user in the peerbus in-process MCP server for interactive sessions
    mcpServers["peerbus"] = createPeerBusServer(this.toolCtx, sessionId, isInteractive);
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

    const tmpDir = join(homedir(), ".claudestudio", "tmp-attachments");
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

  private buildSystemPromptAppend(config: AgentConfig, planMode?: boolean): string {
    let append = config.systemPrompt || "";

    if (config.interactive) {
      append += `\n\n## Asking the User

You have an \`ask_user\` MCP tool available. When you need to ask the user a question, get a decision, or need clarification, you MUST use the \`ask_user\` tool instead of writing the question as regular text. The tool blocks until the user responds and returns their answer directly to you.

Parameters:
- \`question\` (required): The question text
- \`options\` (optional): Array of {label, description} for structured choices
- \`multi_select\` (optional): Allow multiple selections (default: false)
- \`private\` (optional): Hide from other agents in group chat (default: true)
- \`input_type\` (optional): UI style — "options" (default buttons), "text" (free text only), "rating" (star rating), "slider" (numeric range), "toggle" (yes/no), "dropdown" (compact picker), "form" (multi-field form)
- \`input_config\` (optional): Config for the input type:
  - rating: {max_rating, rating_labels}
  - slider: {min, max, step, unit}
  - form: {fields: [{name, label, type: "text"|"number"|"toggle", placeholder, required}]}

Examples:
- Toggle: \`ask_user({question: "Proceed?", input_type: "toggle"})\` → shows Yes/No buttons
- Rating: \`ask_user({question: "Rate quality", input_type: "rating", input_config: {max_rating: 5, rating_labels: ["Poor","Fair","Good","Great","Excellent"]}})\`
- Slider: \`ask_user({question: "Priority?", input_type: "slider", input_config: {min: 1, max: 10, step: 1}})\`
- Form: \`ask_user({question: "Your info", input_type: "form", input_config: {fields: [{name: "name", label: "Name", type: "text", required: true}]}})\`

IMPORTANT: Never write questions as plain text output. Always use the ask_user tool so the user gets an interactive prompt. Choose the input_type that best matches what you're asking — toggle for yes/no, rating for quality judgments, slider for ranges, form for multiple fields.

## Rich Display

Your chat supports rich inline rendering. Use these tools instead of writing files and asking the user to open them:

- \`render_content\`: **ALWAYS use this** to display HTML, mermaid diagrams, or styled markdown directly in chat. When the user asks to see something visually — a comparison, a chart, a preview, a styled page — render it inline with this tool. Never create HTML files and tell the user to open them in a browser; use render_content instead.
- \`confirm_action\`: Request user approval before destructive operations (git push, rm, etc.). Blocks until user responds.
- \`show_progress\`: Display/update a step-by-step progress tracker. Call multiple times with same id to update.
- \`suggest_actions\`: Show clickable follow-up chips after completing a task. Great for guiding the user to natural next steps.

When to use render_content:
- User asks for a visual comparison → render side-by-side HTML
- User asks for a chart or graph → render HTML with inline SVG or CSS
- User asks for a diagram → use format="mermaid"
- User asks to preview something → render it inline
- You want to show styled output → use format="html" with CSS

You can also use these markdown features that render as rich cards:
- \`> [!info]\`, \`> [!success]\`, \`> [!warning]\`, \`> [!error]\` — callout cards
- \`\`\`mermaid\`\`\` — rendered as visual diagrams
- Markdown tables render as native tables\n`;
    }

    // GitHub awareness — inject if workspace is a GitHub repo
    if (config.workingDirectory) {
      try {
        const result = Bun.spawnSync(
          ["git", "remote", "get-url", "origin"],
          { cwd: config.workingDirectory, stdout: "pipe", stderr: "pipe" }
        );
        const remoteUrl = result.stdout.toString().trim();
        if (remoteUrl.includes("github.com")) {
          append += `\n\n## GitHub Workspace

This workspace is a GitHub repository (\`${remoteUrl}\`). You can use the \`gh\` CLI (via Bash tool) to interact with issues, PRs, reviews, and releases.

**Use GitHub for durable, visible work artifacts** (issues for tasks, PRs for code changes, reviews for quality gates). Use PeerBus for real-time agent coordination.

Before using \`gh\` commands, verify auth: \`gh auth status\`. If not authenticated, skip GitHub workflows.\n`;
        }
      } catch {
        // Not a git repo or git not available — skip
      }
    }

    if (config.skills && config.skills.length > 0) {
      append += "\n\n## Skills\n\n";
      for (const skill of config.skills) {
        append += `### ${skill.name}\n${skill.content}\n\n`;
      }
    }

    return append;
  }

  private async handleSDKMessage(
    sessionId: string,
    message: any,
    collectText: (text: string) => void,
    usageAccum?: { inputTokens: number; outputTokens: number; numTurns: number },
  ): Promise<void> {
    switch (message.type) {
      case "assistant":
        if (message.message?.content) {
          for (const block of message.message.content) {
            if (block.type === "thinking" && block.thinking) {
              this.emit({ type: "stream.thinking", sessionId, text: block.thinking });
            } else if (block.type === "text" && block.text) {
              collectText(block.text);
              this.emit({ type: "stream.token", sessionId, text: block.text });
            } else if (block.type === "image" && block.source?.type === "base64") {
              this.emit({
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
        logger.debug("session", `[${sessionId}] tool_use: name="${message.name}" id="${message.id}" input=${JSON.stringify(message.input ?? {}).substring(0, 200)}`);
        this.emit({
          type: "stream.toolCall",
          sessionId,
          tool: message.name ?? "unknown",
          input: typeof message.input === "string"
            ? message.input
            : JSON.stringify(message.input ?? {}),
        });
        {
          const st = this.registry.get(sessionId);
          this.registry.update(sessionId, { toolCallCount: (st?.toolCallCount ?? 0) + 1 });
        }
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
        // Scan tool result for image/file paths
        const resultText = typeof message.content === "string"
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
                  this.emit({
                    type: "stream.image",
                    sessionId,
                    imageData: base64,
                    mediaType: extensionToMediaType(file.path),
                    fileName: file.path.split("/").pop(),
                  });
                }
              }
            } else {
              this.emit({
                type: "stream.fileCard",
                sessionId,
                filePath: file.path,
                fileType: file.type,
                fileName: file.path.split("/").pop() ?? "file",
              });
            }
          } catch { /* file doesn't exist or unreadable — skip */ }
        }
        break;

      case "result":
        logger.info("session", `[${sessionId}] SDK result cost_usd=${message.cost_usd} total_cost_usd=${message.total_cost_usd} num_turns=${message.num_turns}`, {
          keys: Object.keys(message),
          usage: message.usage,
        });
        if (message.errors && message.errors.length > 0) {
          logger.warn("session", `[${sessionId}] SDK result ERRORS`, { errors: message.errors });
        }
        if (message.permission_denials && message.permission_denials.length > 0) {
          logger.warn("session", `[${sessionId}] SDK result permission_denials`, { denials: message.permission_denials });
        }
        if (message.cost_usd != null || message.total_cost_usd != null) {
          const cost = message.total_cost_usd ?? message.cost_usd ?? 0;
          const state = this.registry.get(sessionId);
          this.registry.update(sessionId, {
            cost: (state?.cost ?? 0) + cost,
          });
        }
        if (usageAccum) {
          const usage = message.usage ?? {};
          usageAccum.inputTokens = usage.input_tokens ?? usage.inputTokens ?? 0;
          usageAccum.outputTokens = usage.output_tokens ?? usage.outputTokens ?? 0;
          usageAccum.numTurns = message.num_turns ?? 0;
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
        if (message.type && message.type !== "system") {
          const extra = message.type === "user" && message.tool_use_result
            ? ` tool_use_result=${JSON.stringify(message.tool_use_result).substring(0, 200)}`
            : "";
          logger.debug("session", `[${sessionId}] SDK message type="${message.type}" name="${message.name ?? ""}" keys=${Object.keys(message).join(",")}${extra}`);
        }
        break;
    }
  }
}
