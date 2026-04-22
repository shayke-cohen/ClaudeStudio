import { randomUUID } from "crypto";
import { existsSync, mkdirSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { homedir } from "os";
import type { AgentConfig, FileAttachment } from "../types.js";
import { PLAN_MODE_APPEND } from "../prompts/plan-mode.js";
import { logger } from "../logger.js";
import {
  buildConfiguredMcpInventory,
  mergeCodexMcpInventory,
  observeMcpToolUse,
  normalizeMcpNamespace,
} from "../mcp-session-state.js";
import { buildSkillsSection } from "../utils/prompt-builder.js";
import { createCodexDynamicTools } from "../tools/peerbus-server.js";
import { toCodexDynamicToolResponse } from "../tools/shared-tool.js";
import type { QuestionInputConfig, QuestionOption } from "../types.js";
import type {
  ProviderRuntime,
  RuntimeDependencies,
  RuntimeSendArgs,
  RuntimeSendResult,
} from "./runtime.js";
import { CodexAppServerClient } from "./codex-app-server-client.js";

interface PendingTurn {
  sessionId: string;
  threadId: string;
  turnId: string | null;
  model: string;
  resultText: string;
  latestPlanText: string | null;
  latestToolOutputs: Map<string, string>;
  lastError?: string;
  usage: {
    inputTokens: number;
    cachedInputTokens: number;
    outputTokens: number;
  };
  resolve: (result: RuntimeSendResult) => void;
  reject: (error: Error) => void;
}

interface PendingQuestion {
  sessionId: string;
  threadId: string;
  turnId: string | null;
  requestId: string;
  kind: "tool" | "elicitationForm" | "elicitationUrl";
  questionIds?: string[];
  elicitationMeta?: unknown;
  resolve: (result: any) => void;
  reject: (error: Error) => void;
}

interface PendingApproval {
  sessionId: string;
  threadId: string;
  turnId: string;
  requestId: string;
  kind: "command" | "file" | "permissions" | "legacyCommand" | "legacyPatch";
  requestedPermissions?: {
    network?: { enabled: boolean | null } | null;
    fileSystem?: { read: string[] | null; write: string[] | null } | null;
  };
  resolve: (result: any) => void;
  reject: (error: Error) => void;
}

interface SessionClientContext {
  client: CodexAppServerClient;
  mcpAliases: Map<string, string>;
}

export class CodexRuntime implements ProviderRuntime {
  readonly provider = "codex" as const;
  private static readonly MCP_STATUS_SETTLE_TIMEOUT_MS = 5000;
  private static readonly MCP_STATUS_POLL_INTERVAL_MS = 250;
  private static readonly APPROVAL_POLICY = "never";
  private static readonly SANDBOX_MODE = "danger-full-access";
  private static readonly DEFAULT_PERMISSIONS_PROFILE = "odyssey_full_access";
  private static readonly THREAD_SANDBOX = "danger-full-access";
  private static readonly TURN_SANDBOX_POLICY = { type: "dangerFullAccess" } as const;

  private static readonly pricingByModel: Record<string, {
    inputUsdPerMillion: number;
    cachedInputUsdPerMillion: number;
    outputUsdPerMillion: number;
  }> = {
    "gpt-5.4": { inputUsdPerMillion: 3.0, cachedInputUsdPerMillion: 0.75, outputUsdPerMillion: 12 },
    "gpt-5.4-mini": { inputUsdPerMillion: 0.4, cachedInputUsdPerMillion: 0.1, outputUsdPerMillion: 1.6 },
  };

  private readonly clientsBySession = new Map<string, SessionClientContext>();
  private readonly threadToSessionId = new Map<string, string>();
  private readonly activeTurnsBySession = new Map<string, PendingTurn>();
  private readonly activeTurnsByTurnId = new Map<string, PendingTurn>();
  private readonly pendingQuestions = new Map<string, PendingQuestion>();
  private readonly pendingApprovals = new Map<string, PendingApproval>();

  constructor(private readonly deps: RuntimeDependencies) {}

  async createSession(sessionId: string, config: AgentConfig): Promise<void> {
    this.getClientContext(sessionId, config);
  }

  async resumeSession(sessionId: string, backendSessionId: string, config?: AgentConfig): Promise<void> {
    const resolvedConfig = config ?? this.deps.registry.getConfig(sessionId);
    if (!resolvedConfig) {
      throw new Error(`No Codex config found for session ${sessionId}`);
    }

    this.getClientContext(sessionId, resolvedConfig);
    this.threadToSessionId.set(backendSessionId, sessionId);
  }

  async forkSession(
    parentSessionId: string,
    childSessionId: string,
    _config: AgentConfig,
    parentBackendSessionId?: string,
  ): Promise<string | undefined> {
    const parentConfig = this.deps.registry.getConfig(parentSessionId);
    if (!parentConfig) {
      throw new Error(`No Codex config found for parent session ${parentSessionId}`);
    }

    const parentClientCtx = this.getClientContext(parentSessionId, parentConfig);
    await parentClientCtx.client.start();
    if (!parentBackendSessionId) {
      return undefined;
    }

    const response = await parentClientCtx.client.call("thread/fork", {
      threadId: parentBackendSessionId,
    });
    const childThreadId = response?.thread?.id as string | undefined;
    if (childThreadId) {
      this.threadToSessionId.set(childThreadId, childSessionId);
    }
    return childThreadId;
  }

  async pauseSession(sessionId: string): Promise<void> {
    const pendingTurn = this.activeTurnsBySession.get(sessionId);
    if (!pendingTurn?.turnId) {
      return;
    }

    const clientCtx = this.getExistingClientContext(sessionId);
    if (!clientCtx) {
      return;
    }

    await clientCtx.client.call("turn/interrupt", {
      threadId: pendingTurn.threadId,
      turnId: pendingTurn.turnId,
    });
  }

  async answerQuestion(
    sessionId: string,
    questionId: string,
    answer: string,
    selectedOptions?: string[],
  ): Promise<boolean> {
    const pending = this.pendingQuestions.get(questionId);
    if (!pending || pending.sessionId !== sessionId) {
      return false;
    }

    this.pendingQuestions.delete(questionId);

    if (pending.kind === "tool") {
      pending.resolve({
        answers: this.buildToolAnswers(
          (pending.questionIds ?? []).map((id) => ({ id })),
          selectedOptions && selectedOptions.length > 0 ? selectedOptions[0] ?? answer : answer,
          questionId,
          selectedOptions,
        ),
      });
      return true;
    }

    if (pending.kind === "elicitationUrl") {
      const normalized = (selectedOptions?.[0] ?? answer).trim().toLowerCase();
      const accepted = ["accept", "continue", "done", "open"].includes(normalized);
      const cancelled = ["cancel", "abort"].includes(normalized);
      pending.resolve({
        action: accepted ? "accept" : cancelled ? "cancel" : "decline",
        content: null,
        _meta: pending.elicitationMeta ?? null,
      });
      return true;
    }

    let content: unknown = null;
    if (answer.trim().length > 0) {
      try {
        content = JSON.parse(answer);
      } catch {
        content = { value: answer };
      }
    }

    pending.resolve({
      action: "accept",
      content,
      _meta: pending.elicitationMeta ?? null,
    });
    return true;
  }

  async answerConfirmation(
    sessionId: string,
    confirmationId: string,
    approved: boolean,
    modifiedAction?: string,
  ): Promise<boolean> {
    const pending = this.pendingApprovals.get(confirmationId);
    if (!pending || pending.sessionId !== sessionId) {
      return false;
    }

    const response =
      pending.kind === "command"
        ? {
            decision:
              approved && modifiedAction
                ? {
                    acceptWithExecpolicyAmendment: {
                      execpolicy_amendment: modifiedAction.split(/\s+/).filter(Boolean),
                    },
                  }
                : approved
                  ? "accept"
                  : "decline",
          }
        : pending.kind === "permissions"
          ? {
              permissions: approved
                ? {
                    ...(pending.requestedPermissions?.network ? { network: pending.requestedPermissions.network } : {}),
                    ...(pending.requestedPermissions?.fileSystem ? { fileSystem: pending.requestedPermissions.fileSystem } : {}),
                  }
                : {},
              scope: "turn",
            }
          : pending.kind === "legacyCommand"
            ? {
                decision:
                  approved && modifiedAction
                    ? {
                        approved_execpolicy_amendment: {
                          proposed_execpolicy_amendment: modifiedAction.split(/\s+/).filter(Boolean),
                        },
                      }
                    : approved
                      ? "approved"
                      : "denied",
              }
            : pending.kind === "legacyPatch"
              ? {
                  decision: approved ? "approved" : "denied",
                }
        : {
            decision: approved ? "acceptForSession" : "decline",
          };

    this.pendingApprovals.delete(confirmationId);
    pending.resolve(response);
    return true;
  }

  async sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult> {
    const clientCtx = this.getClientContext(args.sessionId, args.config);
    await clientCtx.client.start();
    const resolvedModel = this.resolveModel(args.config.model, args.planMode);

    const dynamicTools = createCodexDynamicTools(
      this.deps.toolCtx,
      args.sessionId,
      args.config.interactive ?? false,
    );

    const threadId = await this.ensureThread(
      clientCtx.client,
      args.sessionId,
      args.config,
      args.backendSessionId,
      dynamicTools.specs,
      args.planMode,
    );
    this.threadToSessionId.set(threadId, args.sessionId);

    const input = this.buildInput(args.text, args.attachments);
    return new Promise<RuntimeSendResult>((resolve, reject) => {
      const pendingTurn: PendingTurn = {
        sessionId: args.sessionId,
        threadId,
        turnId: null,
        model: resolvedModel,
        resultText: "",
        latestPlanText: null,
        latestToolOutputs: new Map(),
        usage: {
          inputTokens: 0,
          cachedInputTokens: 0,
          outputTokens: 0,
        },
        resolve,
        reject,
      };
      this.activeTurnsBySession.set(args.sessionId, pendingTurn);

      args.abortController.signal.addEventListener("abort", () => {
        this.pauseSession(args.sessionId).catch((error) => {
          logger.warn(
            "codex",
            `Failed to interrupt turn ${pendingTurn.turnId ?? "(pending)"}: ${error?.message ?? error}`,
          );
        });
      });

      clientCtx.client.call("turn/start", {
        threadId,
        input,
        cwd: args.config.workingDirectory || undefined,
        model: resolvedModel,
        approvalPolicy: CodexRuntime.APPROVAL_POLICY,
        sandboxPolicy: CodexRuntime.TURN_SANDBOX_POLICY,
      }).then((turnResponse) => {
        const turnId = turnResponse?.turn?.id as string | undefined;
        if (!turnId) {
          throw new Error("Codex app-server did not return a turn id");
        }

        if (!pendingTurn.turnId) {
          pendingTurn.turnId = turnId;
        }

        if (this.activeTurnsBySession.get(args.sessionId) === pendingTurn) {
          this.activeTurnsByTurnId.set(pendingTurn.turnId, pendingTurn);
        }
      }).catch((error: any) => {
        this.activeTurnsBySession.delete(args.sessionId);
        if (pendingTurn.turnId) {
          this.activeTurnsByTurnId.delete(pendingTurn.turnId);
        }
        reject(error instanceof Error ? error : new Error(String(error)));
      });
    });
  }

  buildTurnOptionsForTesting(
    _sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    attachmentCount: number,
    planMode?: boolean,
  ): Record<string, any> {
    const mcpAliases = new Map<string, string>();
    const developerInstructions = this.buildDeveloperInstructions(config, planMode);
    return {
      provider: "codex",
      backendSessionId,
      model: this.resolveModel(config.model, planMode),
      cwd: config.workingDirectory,
      attachmentCount,
      approvalPolicy: CodexRuntime.APPROVAL_POLICY,
      threadSandbox: CodexRuntime.THREAD_SANDBOX,
      turnSandboxPolicy: CodexRuntime.TURN_SANDBOX_POLICY,
      developerInstructions,
      mcpServerCount: config.mcpServers.length,
      appServerEnvOverrides: this.buildClientEnvOverrides(config),
      appServerConfigOverrides: this.buildClientConfigOverrides(config, mcpAliases),
    };
  }

  private async ensureThread(
    client: CodexAppServerClient,
    sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    dynamicTools: unknown[],
    planMode?: boolean,
  ): Promise<string> {
    const developerInstructions = this.buildDeveloperInstructions(config, planMode);

    if (backendSessionId) {
      const response = await client.call("thread/resume", {
        threadId: backendSessionId,
        cwd: config.workingDirectory || undefined,
        model: this.resolveModel(config.model, planMode),
        approvalPolicy: CodexRuntime.APPROVAL_POLICY,
        sandbox: CodexRuntime.THREAD_SANDBOX,
        developerInstructions,
        dynamicTools,
      });
      const threadId = response?.thread?.id ?? backendSessionId;
      await this.refreshCodexMcpInventory(sessionId, client, config, true);
      return threadId;
    }

    const response = await client.call("thread/start", {
      model: this.resolveModel(config.model, planMode),
      modelProvider: "openai",
      cwd: config.workingDirectory || undefined,
      approvalPolicy: CodexRuntime.APPROVAL_POLICY,
      sandbox: CodexRuntime.THREAD_SANDBOX,
      developerInstructions,
      serviceName: "odyssey-sidecar",
      experimentalRawEvents: false,
      persistExtendedHistory: true,
      dynamicTools,
    });
    const threadId = response?.thread?.id as string;
    await this.refreshCodexMcpInventory(sessionId, client, config, true);
    return threadId;
  }

  private buildDeveloperInstructions(config: AgentConfig, planMode?: boolean): string {
    let instructions = config.systemPrompt || "";

    instructions += buildSkillsSection(config.skills ?? []);

    if (config.interactive) {
      instructions += `\n\nUse dynamic tools for ask_user, render_content, confirm_action, show_progress, and suggest_actions instead of asking the user in plain text.`;
    }

    if (planMode === true) {
      instructions += `\n\n${PLAN_MODE_APPEND}`;
    }

    return instructions;
  }

  private buildInput(text: string, attachments?: FileAttachment[]): any[] {
    if (!attachments || attachments.length === 0) {
      return [{ type: "text", text }];
    }

    const tmpDir = join(homedir(), ".odyssey", "tmp-attachments");
    mkdirSync(tmpDir, { recursive: true });

    const inputs: any[] = [];
    const inlineTexts: string[] = [];
    const fileRefs: string[] = [];

    for (let i = 0; i < attachments.length; i++) {
      const attachment = attachments[i];
      const label = attachment.fileName || `attachment-${i + 1}`;

      if (attachment.mediaType === "text/plain" || attachment.mediaType === "text/markdown") {
        const content = Buffer.from(attachment.data, "base64").toString("utf8");
        inlineTexts.push(`--- ${label} ---\n${content}\n--- end ${label} ---`);
        continue;
      }

      const ext = this.extensionForMediaType(attachment.mediaType);
      const filename = `${randomUUID()}.${ext}`;
      const filePath = join(tmpDir, filename);
      writeFileSync(filePath, Buffer.from(attachment.data, "base64"));

      if (attachment.mediaType.startsWith("image/")) {
        inputs.push({
          type: "localImage",
          path: filePath,
        });
      } else {
        fileRefs.push(`[File: ${label}]: ${filePath}`);
      }
    }

    const parts: string[] = [];
    if (fileRefs.length > 0) {
      parts.push(`The user attached ${fileRefs.length} file(s). Use the shell or read tools as needed.`);
      parts.push(fileRefs.join("\n"));
    }
    if (inlineTexts.length > 0) {
      parts.push("The user included the following text attachment contents:");
      parts.push(inlineTexts.join("\n\n"));
    }
    if (text) {
      parts.push(text);
    }

    inputs.unshift({
      type: "text",
      text: parts.join("\n\n"),
    });
    return inputs;
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

  private resolveModel(model: string | undefined, planMode?: boolean): string {
    if (planMode === true) {
      return "gpt-5.4";
    }

    switch (model) {
      case "sonnet":
      case "opus":
      case "haiku":
      case "gpt-5-codex":
      case "gpt-5.1-codex":
      case "gpt-5.1-codex-max":
      case "gpt-5.1-codex-mini":
      case "codex-mini-latest":
      case undefined:
        return "gpt-5.4";
      default:
        return model;
    }
  }

  private handleNotification(notification: { method: string; params?: any }) {
    const params = notification.params ?? {};

    switch (notification.method) {
      case "thread/tokenUsage/updated": {
        const pendingTurn = this.resolvePendingTurn(params);
        if (pendingTurn) {
          const usage = this.extractTokenUsage(params);
          if (usage) {
            pendingTurn.usage = usage;
          }
          this.deps.registry.update(pendingTurn.sessionId, {
            tokenCount: pendingTurn.usage.inputTokens + pendingTurn.usage.outputTokens,
          });
        }
        break;
      }

      case "item/agentMessage/delta": {
        const pendingTurn = this.resolvePendingTurn(params);
        if (!pendingTurn) {
          break;
        }
        const delta = params.delta ?? params.textDelta ?? "";
        if (delta) {
          pendingTurn.resultText += delta;
          this.deps.emit({
            type: "stream.token",
            sessionId: pendingTurn.sessionId,
            text: delta,
          });
        }
        break;
      }

      case "item/reasoning/summaryTextDelta": {
        const pendingTurn = this.resolvePendingTurn(params);
        if (!pendingTurn) {
          break;
        }
        const delta = params.delta ?? params.textDelta ?? "";
        if (delta) {
          this.deps.emit({
            type: "stream.thinking",
            sessionId: pendingTurn.sessionId,
            text: delta,
          });
        }
        break;
      }

      case "item/plan/delta": {
        const pendingTurn = this.resolvePendingTurn(params);
        if (pendingTurn) {
          pendingTurn.latestPlanText = `${pendingTurn.latestPlanText ?? ""}${params.delta ?? ""}`;
        }
        break;
      }

      case "item/started":
        this.handleItemStarted(params);
        break;

      case "item/completed":
        this.handleItemCompleted(params);
        break;

      case "turn/completed":
        this.handleTurnCompleted(params);
        break;

      case "error": {
        const threadId = params.threadId as string | undefined;
        const sessionId = threadId ? this.threadToSessionId.get(threadId) : undefined;
        const pendingTurn = sessionId ? this.activeTurnsBySession.get(sessionId) : undefined;
        if (pendingTurn) {
          pendingTurn.lastError = params.error?.message ?? "Codex app-server error";
        }
        break;
      }

      default:
        break;
    }
  }

  private resolvePendingTurn(params: any): PendingTurn | undefined {
    const turnId = (params.turnId ?? params.turn?.id) as string | undefined;
    if (turnId) {
      const pendingByTurnId = this.activeTurnsByTurnId.get(turnId);
      if (pendingByTurnId) {
        return pendingByTurnId;
      }
    }

    const threadId = (params.threadId ?? params.turn?.threadId) as string | undefined;
    const sessionId = threadId ? this.threadToSessionId.get(threadId) : undefined;
    const pendingBySession = sessionId ? this.activeTurnsBySession.get(sessionId) : undefined;
    if (pendingBySession && turnId && !pendingBySession.turnId) {
      pendingBySession.turnId = turnId;
      this.activeTurnsByTurnId.set(turnId, pendingBySession);
    }
    return pendingBySession;
  }

  private handleItemStarted(params: any) {
    const pendingTurn = this.resolvePendingTurn(params);
    if (!pendingTurn) {
      return;
    }

    const item = params.item ?? {};
    switch (item.type) {
      case "commandExecution":
        this.recordToolCall(pendingTurn.sessionId);
        this.deps.emit({
          type: "stream.toolCall",
          sessionId: pendingTurn.sessionId,
          tool: "bash",
          input: JSON.stringify({
            command: item.command,
            cwd: item.cwd,
          }),
        });
        break;

      case "fileChange":
        this.recordToolCall(pendingTurn.sessionId);
        this.deps.emit({
          type: "stream.toolCall",
          sessionId: pendingTurn.sessionId,
          tool: "apply_patch",
          input: JSON.stringify(item.changes ?? []),
        });
        break;

      case "mcpToolCall":
        this.recordObservedMcpTool(
          pendingTurn.sessionId,
          this.mapMcpServerAlias(pendingTurn.sessionId, item.server),
          item.tool,
        );
        this.recordToolCall(pendingTurn.sessionId);
        this.deps.emit({
          type: "stream.toolCall",
          sessionId: pendingTurn.sessionId,
          tool: `${this.mapMcpServerAlias(pendingTurn.sessionId, item.server)}/${item.tool}`,
          input: JSON.stringify(item.arguments ?? {}),
        });
        break;

      case "dynamicToolCall":
        this.recordToolCall(pendingTurn.sessionId);
        this.deps.emit({
          type: "stream.toolCall",
          sessionId: pendingTurn.sessionId,
          tool: item.tool ?? "dynamic_tool",
          input: JSON.stringify(item.arguments ?? {}),
        });
        break;

      default:
        break;
    }
  }

  private handleItemCompleted(params: any) {
    const pendingTurn = this.resolvePendingTurn(params);
    if (!pendingTurn) {
      return;
    }

    const item = params.item ?? {};
    switch (item.type) {
      case "commandExecution": {
        const output = item.aggregatedOutput ?? JSON.stringify({
          status: item.status,
          exitCode: item.exitCode,
          durationMs: item.durationMs,
        });
        pendingTurn.latestToolOutputs.set(item.id, output);
        this.deps.emit({
          type: "stream.toolResult",
          sessionId: pendingTurn.sessionId,
          tool: "bash",
          output,
        });
        break;
      }

      case "fileChange": {
        const output = JSON.stringify({
          status: item.status,
          changes: item.changes ?? [],
        });
        pendingTurn.latestToolOutputs.set(item.id, output);
        this.deps.emit({
          type: "stream.toolResult",
          sessionId: pendingTurn.sessionId,
          tool: "apply_patch",
          output,
        });
        break;
      }

      case "mcpToolCall": {
        const toolName = `${this.mapMcpServerAlias(pendingTurn.sessionId, item.server)}/${item.tool}`;
        const output = JSON.stringify(item.result ?? item.error ?? {});
        pendingTurn.latestToolOutputs.set(item.id, output);
        this.deps.emit({
          type: "stream.toolResult",
          sessionId: pendingTurn.sessionId,
          tool: toolName,
          output,
        });
        break;
      }

      case "dynamicToolCall": {
        const output = JSON.stringify({
          success: item.success,
          contentItems: item.contentItems ?? [],
        });
        pendingTurn.latestToolOutputs.set(item.id, output);
        this.deps.emit({
          type: "stream.toolResult",
          sessionId: pendingTurn.sessionId,
          tool: item.tool ?? "dynamic_tool",
          output,
        });
        break;
      }

      case "plan":
        pendingTurn.latestPlanText = item.text ?? pendingTurn.latestPlanText;
        break;

      default:
        break;
    }
  }

  private handleTurnCompleted(params: any) {
    const turn = params.turn ?? {};
    const pendingTurn = this.resolvePendingTurn(params);
    if (!pendingTurn) {
      return;
    }

    if (pendingTurn.turnId) {
      this.activeTurnsByTurnId.delete(pendingTurn.turnId);
    }
    this.activeTurnsBySession.delete(pendingTurn.sessionId);

    if (pendingTurn.latestPlanText) {
      this.deps.emit({
        type: "session.planComplete",
        sessionId: pendingTurn.sessionId,
        plan: pendingTurn.latestPlanText,
      });
    }

    if (turn.status === "failed" || pendingTurn.lastError) {
      pendingTurn.reject(new Error(pendingTurn.lastError ?? turn.error?.message ?? "Codex turn failed"));
      return;
    }

    const completionUsage = this.extractTokenUsage(params);
    if (completionUsage) {
      pendingTurn.usage = completionUsage;
    }

    const costDelta = this.estimateCostDelta(pendingTurn.model, pendingTurn.usage);

    pendingTurn.resolve({
      backendSessionId: pendingTurn.threadId,
      resultText: pendingTurn.resultText || pendingTurn.latestPlanText || "(no text response)",
      costDelta,
      inputTokens: pendingTurn.usage.inputTokens,
      outputTokens: pendingTurn.usage.outputTokens,
      numTurns: 1,
    });
  }

  private extractTokenUsage(params: any): PendingTurn["usage"] | null {
    const usage =
      params?.tokenUsage?.last ??
      params?.tokenUsage?.total ??
      params?.turn?.usage ??
      params?.usage;

    if (!usage) {
      return null;
    }

    return {
      inputTokens: usage.inputTokens ?? usage.input_tokens ?? 0,
      cachedInputTokens: usage.cachedInputTokens ?? usage.cached_input_tokens ?? 0,
      outputTokens: usage.outputTokens ?? usage.output_tokens ?? 0,
    };
  }

  private estimateCostDelta(model: string, usage: PendingTurn["usage"]): number {
    const pricing = CodexRuntime.pricingByModel[model];
    if (!pricing) {
      return 0;
    }

    const cachedInputTokens = Math.min(usage.cachedInputTokens, usage.inputTokens);
    const uncachedInputTokens = Math.max(0, usage.inputTokens - cachedInputTokens);

    return (
      (uncachedInputTokens * pricing.inputUsdPerMillion) +
      (cachedInputTokens * pricing.cachedInputUsdPerMillion) +
      (usage.outputTokens * pricing.outputUsdPerMillion)
    ) / 1_000_000;
  }

  private async handleServerRequest(
    sessionHint: string,
    request: { id: number | string; method: string; params?: any },
  ): Promise<any> {
    switch (request.method) {
      case "item/tool/call":
        return this.handleDynamicToolCall(sessionHint, request);

      case "item/tool/requestUserInput":
        return this.handleRequestUserInput(sessionHint, request);

      case "mcpServer/elicitation/request":
        return this.handleMcpElicitationRequest(sessionHint, request);

      case "item/commandExecution/requestApproval":
        return this.handleCommandApproval(sessionHint, request);

      case "item/fileChange/requestApproval":
        return this.handleFileChangeApproval(sessionHint, request);

      case "item/permissions/requestApproval":
        return this.handlePermissionsApproval(sessionHint, request);

      case "execCommandApproval":
        return this.handleLegacyCommandApproval(sessionHint, request);

      case "applyPatchApproval":
        return this.handleLegacyPatchApproval(sessionHint, request);

      case "account/chatgptAuthTokens/refresh":
        logger.warn("codex", `Ignoring unsupported auth refresh request for session ${sessionHint}`);
        return {};

      default:
        throw new Error(`Unsupported Codex server request: ${request.method}`);
    }
  }

  private async handleDynamicToolCall(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    const dynamicTools = createCodexDynamicTools(
      this.deps.toolCtx,
      sessionId,
      this.deps.registry.getConfig(sessionId)?.interactive ?? false,
    );
    const handler = dynamicTools.handlers.get(params.tool);
    if (!handler) {
      throw new Error(`Unknown dynamic tool: ${params.tool}`);
    }

    const result = await handler.execute(params.arguments ?? {}, {
      sessionId,
    });
    return toCodexDynamicToolResponse(result);
  }

  private handleRequestUserInput(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    const firstQuestion = params.questions?.[0];
    if (!firstQuestion) {
      return { answers: {} };
    }

    if (this.isCodexToolApprovalPrompt(firstQuestion)) {
      logger.info("codex", `Auto-approving Codex MCP tool request for session ${sessionId}`, {
        question: firstQuestion.question,
        questionId: firstQuestion.id,
      });
      return {
        answers: this.buildToolAnswers(params.questions ?? [], "Accept"),
      };
    }

    return new Promise((resolve, reject) => {
      this.pendingQuestions.set(String(request.id), {
        sessionId,
        threadId: params.threadId,
        turnId: params.turnId,
        requestId: String(request.id),
        kind: "tool",
        questionIds: (params.questions ?? []).map((question: any) => question.id),
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.question",
        sessionId,
        questionId: String(request.id),
        question: firstQuestion.question,
        options: firstQuestion.options?.map((option: any) => ({
          label: option.label,
          description: option.description,
        })),
        multiSelect: false,
        private: firstQuestion.isSecret ?? true,
        inputType: firstQuestion.options?.length ? "options" : "text",
      });
    });
  }

  private handleMcpElicitationRequest(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingQuestions.set(String(request.id), {
        sessionId,
        threadId: params.threadId,
        turnId: params.turnId ?? null,
        requestId: String(request.id),
        kind: params.mode === "url" ? "elicitationUrl" : "elicitationForm",
        elicitationMeta: params._meta ?? null,
        resolve,
        reject,
      });

      const question = this.buildMcpElicitationQuestion(sessionId, String(request.id), params);
      this.deps.emit(question);
    });
  }

  private handleCommandApproval(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingApprovals.set(String(request.id), {
        sessionId,
        threadId: params.threadId,
        turnId: params.turnId,
        requestId: String(request.id),
        kind: "command",
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.confirmation",
        sessionId,
        confirmationId: String(request.id),
        action: params.command ?? "Run command",
        reason: params.reason ?? "Codex requested approval to continue.",
        riskLevel: "medium",
        details: params.cwd ? `cwd: ${params.cwd}` : undefined,
      });
    });
  }

  private handleFileChangeApproval(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingApprovals.set(String(request.id), {
        sessionId,
        threadId: params.threadId,
        turnId: params.turnId,
        requestId: String(request.id),
        kind: "file",
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.confirmation",
        sessionId,
        confirmationId: String(request.id),
        action: "Apply file changes",
        reason: params.reason ?? "Codex requested approval to apply file changes.",
        riskLevel: "medium",
        details: params.grantRoot ? `grantRoot: ${params.grantRoot}` : undefined,
      });
    });
  }

  private handlePermissionsApproval(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingApprovals.set(String(request.id), {
        sessionId,
        threadId: params.threadId,
        turnId: params.turnId,
        requestId: String(request.id),
        kind: "permissions",
        requestedPermissions: params.permissions ?? undefined,
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.confirmation",
        sessionId,
        confirmationId: String(request.id),
        action: "Grant additional permissions",
        reason: params.reason ?? "Codex requested broader sandbox permissions.",
        riskLevel: "high",
        details: this.formatPermissionsDetails(params.permissions),
      });
    });
  }

  private handleLegacyCommandApproval(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForLegacyRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingApprovals.set(String(request.id), {
        sessionId,
        threadId: params.conversationId,
        turnId: params.callId,
        requestId: String(request.id),
        kind: "legacyCommand",
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.confirmation",
        sessionId,
        confirmationId: String(request.id),
        action: Array.isArray(params.command) ? params.command.join(" ") : "Run command",
        reason: params.reason ?? "Codex requested approval to run a command.",
        riskLevel: "medium",
        details: params.cwd ? `cwd: ${params.cwd}` : undefined,
      });
    });
  }

  private handleLegacyPatchApproval(
    sessionHint: string,
    request: { id: number | string; params?: any },
  ) {
    const params = request.params ?? {};
    const sessionId = this.resolveSessionIdForLegacyRequest(params, sessionHint);

    return new Promise((resolve, reject) => {
      this.pendingApprovals.set(String(request.id), {
        sessionId,
        threadId: params.conversationId,
        turnId: params.callId,
        requestId: String(request.id),
        kind: "legacyPatch",
        resolve,
        reject,
      });

      this.deps.emit({
        type: "agent.confirmation",
        sessionId,
        confirmationId: String(request.id),
        action: "Apply file changes",
        reason: params.reason ?? "Codex requested approval to apply file changes.",
        riskLevel: "medium",
        details: params.grantRoot ? `grantRoot: ${params.grantRoot}` : undefined,
      });
    });
  }

  private resolveSessionIdForRequest(params: any, sessionHint: string): string {
    const threadId = params?.threadId as string | undefined;
    const sessionId = (threadId ? this.threadToSessionId.get(threadId) : undefined) ?? sessionHint;
    if (!sessionId) {
      throw new Error(`No session found for thread ${threadId ?? "unknown"}`);
    }
    return sessionId;
  }

  private resolveSessionIdForLegacyRequest(params: any, sessionHint: string): string {
    const threadId = params?.conversationId as string | undefined;
    const sessionId = (threadId ? this.threadToSessionId.get(threadId) : undefined) ?? sessionHint;
    if (!sessionId) {
      throw new Error(`No session found for legacy conversation ${threadId ?? "unknown"}`);
    }
    return sessionId;
  }

  private buildMcpElicitationQuestion(
    sessionId: string,
    questionId: string,
    params: any,
  ): {
    type: "agent.question";
    sessionId: string;
    questionId: string;
    question: string;
    options?: QuestionOption[];
    multiSelect: boolean;
    private: boolean;
    inputType?: "text" | "options" | "dropdown" | "form";
    inputConfig?: QuestionInputConfig;
  } {
    if (params.mode === "url") {
      return {
        type: "agent.question",
        sessionId,
        questionId,
        question: `${params.message}\n\nOpen this URL to continue: ${params.url}`,
        options: [
          { label: "Continue", description: "Complete the flow in your browser, then continue." },
          { label: "Decline", description: "Reject this request." },
        ],
        multiSelect: false,
        private: false,
        inputType: "options",
      };
    }

    const properties = Object.entries(params.requestedSchema?.properties ?? {});
    const fields = properties.map(([name, schema]) => this.mapMcpField(name, schema as Record<string, any>, params.requestedSchema?.required ?? []));

    return {
      type: "agent.question",
      sessionId,
      questionId,
      question: params.message ?? "Codex requested structured input.",
      multiSelect: false,
      private: false,
      inputType: "form",
      inputConfig: {
        fields,
      },
    };
  }

  private isCodexToolApprovalPrompt(question: any): boolean {
    const promptText = String(question?.question ?? "").trim().toLowerCase();
    const looksLikeMcpPermissionPrompt =
      promptText.includes("mcp server to run tool") ||
      (promptText.startsWith("allow the ") && promptText.includes(" to run tool "));

    return looksLikeMcpPermissionPrompt;
  }

  private buildToolAnswers(
    questions: Array<{ id?: string }>,
    answer: string,
    targetQuestionId?: string,
    selectedOptions?: string[],
  ): Record<string, { answers: string[] }> {
    const normalizedAnswer = answer.trim();
    const answers: Record<string, { answers: string[] }> = {};

    for (const question of questions) {
      const id = question.id;
      if (!id) {
        continue;
      }

      answers[id] = {
        answers:
          !targetQuestionId || id === targetQuestionId
            ? selectedOptions && selectedOptions.length > 0
              ? selectedOptions
              : normalizedAnswer.length > 0
                ? [normalizedAnswer]
                : []
            : [],
      };
    }

    return answers;
  }

  private mapMcpField(
    name: string,
    schema: Record<string, any>,
    requiredFields: string[],
  ): { name: string; label: string; type: "text" | "number" | "toggle"; placeholder?: string; required?: boolean } {
    const schemaType = schema.type;
    const title = schema.title ?? name;
    const description = schema.description ?? undefined;
    return {
      name,
      label: title,
      type:
        schemaType === "boolean"
          ? "toggle"
          : schemaType === "number" || schemaType === "integer"
            ? "number"
            : "text",
      placeholder: description,
      required: requiredFields.includes(name),
    };
  }

  private formatPermissionsDetails(permissions: any): string | undefined {
    const parts: string[] = [];
    if (permissions?.network?.enabled === true) {
      parts.push("network: enabled");
    }
    const readRoots = permissions?.fileSystem?.read ?? [];
    if (readRoots.length > 0) {
      parts.push(`read: ${readRoots.join(", ")}`);
    }
    const writeRoots = permissions?.fileSystem?.write ?? [];
    if (writeRoots.length > 0) {
      parts.push(`write: ${writeRoots.join(", ")}`);
    }
    return parts.length > 0 ? parts.join("\n") : undefined;
  }

  private mapMcpServerAlias(sessionId: string, alias: string | undefined): string {
    if (!alias) {
      return "mcp";
    }

    return this.getExistingClientContext(sessionId)?.mcpAliases.get(alias) ?? alias;
  }

  private getExistingClientContext(sessionId: string): SessionClientContext | undefined {
    return this.clientsBySession.get(sessionId);
  }

  private getClientContext(sessionId: string, config?: AgentConfig): SessionClientContext {
    const existing = this.clientsBySession.get(sessionId);
    if (existing) {
      return existing;
    }

    const resolvedConfig = config ?? this.deps.registry.getConfig(sessionId);
    if (!resolvedConfig) {
      throw new Error(`No Codex config found for session ${sessionId}`);
    }

    const mcpAliases = new Map<string, string>();
    const client = new CodexAppServerClient({
      envOverrides: this.buildClientEnvOverrides(resolvedConfig),
      configOverrides: this.buildClientConfigOverrides(resolvedConfig, mcpAliases),
    });
    client.setHandlers({
      onNotification: (notification) => {
        this.handleNotification(notification);
      },
      onRequest: async (request) => this.handleServerRequest(sessionId, request),
    });

    const clientCtx = { client, mcpAliases };
    this.clientsBySession.set(sessionId, clientCtx);
    return clientCtx;
  }

  private async refreshCodexMcpInventory(
    sessionId: string,
    client: CodexAppServerClient,
    config: AgentConfig,
    waitForSettled: boolean,
  ): Promise<void> {
    if (config.mcpServers.length === 0) {
      this.deps.registry.replaceMcpInventory(sessionId, []);
      return;
    }

    const deadline = Date.now() + CodexRuntime.MCP_STATUS_SETTLE_TIMEOUT_MS;
    let latestInventory = buildConfiguredMcpInventory(config);

    while (true) {
      latestInventory = await this.fetchCodexMcpInventory(sessionId, client, config);

      const hasPending = latestInventory.some((entry) =>
        entry.configured && (entry.availability === "configured" || entry.availability === "pending"),
      );

      if (!waitForSettled || !hasPending || Date.now() >= deadline) {
        if (hasPending && waitForSettled) {
          logger.warn("session", `Timed out waiting for configured MCPs to settle for ${sessionId}`, {
            provider: "codex",
            mcpServers: latestInventory,
          });
        }
        return;
      }

      await Bun.sleep(CodexRuntime.MCP_STATUS_POLL_INTERVAL_MS);
    }
  }

  private async fetchCodexMcpInventory(
    sessionId: string,
    client: CodexAppServerClient,
    config: AgentConfig,
  ) {
    try {
      const response = await client.call("mcpServerStatus/list", { limit: 100 });
      const rawStatuses = this.extractCodexMcpStatuses(response);
      const inventory = mergeCodexMcpInventory(
        config,
        this.deps.registry.getMcpInventory(sessionId),
        rawStatuses,
        (name) => this.mapMcpServerAlias(sessionId, name),
      );
      this.deps.registry.replaceMcpInventory(sessionId, inventory);
      logger.info("session", `Effective MCP inventory for ${sessionId}`, {
        provider: "codex",
        mcpServers: inventory,
      });
      return inventory;
    } catch (error: any) {
      const message = error?.message ?? String(error);
      const inventory = buildConfiguredMcpInventory(config).map((entry) => ({
        ...entry,
        availability: "unavailable" as const,
        error: message,
      }));
      this.deps.registry.replaceMcpInventory(sessionId, inventory);
      logger.warn("session", `Failed to read Codex MCP inventory for ${sessionId}: ${message}`, {
        provider: "codex",
        mcpServers: inventory,
      });
      return inventory;
    }
  }

  private extractCodexMcpStatuses(response: any): Array<{
    name?: string;
    status?: string;
    error?: string;
    tools?: Array<{ name?: string; description?: string }>;
  }> {
    const items = Array.isArray(response)
      ? response
      : Array.isArray(response?.servers)
        ? response.servers
        : Array.isArray(response?.items)
          ? response.items
          : Array.isArray(response?.statuses)
            ? response.statuses
            : [];

    return items.map((item: any) => ({
      name:
        item?.name ??
        item?.serverName ??
        item?.id ??
        item?.server?.name,
      status:
        item?.status ??
        item?.connectionStatus ??
        item?.state ??
        item?.authStatus,
      error:
        item?.error ??
        item?.lastError?.message ??
        item?.message,
      tools: Array.isArray(item?.tools)
        ? item.tools.map((tool: any) => ({
            name: tool?.name,
            description: tool?.description,
          }))
        : [],
    }));
  }

  private recordObservedMcpTool(sessionId: string, serverName: string, toolName: string | undefined): void {
    if (!toolName) {
      return;
    }

    const inventory = observeMcpToolUse(
      this.deps.registry.getMcpInventory(sessionId),
      normalizeMcpNamespace(serverName),
      toolName,
    );
    this.deps.registry.replaceMcpInventory(sessionId, inventory);
  }

  private buildClientConfigOverrides(config: AgentConfig, mcpAliases: Map<string, string>): string[] {
    const overrides = [
      `default_permissions=${JSON.stringify(CodexRuntime.DEFAULT_PERMISSIONS_PROFILE)}`,
      `permissions.${CodexRuntime.DEFAULT_PERMISSIONS_PROFILE}.filesystem={":project_roots"={"."="write"}}`,
      `permissions.${CodexRuntime.DEFAULT_PERMISSIONS_PROFILE}.network.enabled=true`,
      `permissions.${CodexRuntime.DEFAULT_PERMISSIONS_PROFILE}.network.mode="full"`,
      "approval_policy.granular.sandbox_approval=false",
      "approval_policy.granular.rules=false",
      "approval_policy.granular.mcp_elicitations=false",
      "approval_policy.granular.request_permissions=false",
      "approval_policy.granular.skill_approval=false",
      `sandbox_mode=${JSON.stringify(CodexRuntime.SANDBOX_MODE)}`,
      "mcp_servers={}",
    ];
    for (const [index, mcp] of config.mcpServers.entries()) {
      // Skip builtin in-process MCP servers (no command, no url) — Codex can't use them
      if (!mcp.command && !mcp.url) continue;

      const alias = `session_mcp_${index}`;
      mcpAliases.set(alias, mcp.name);

      if (mcp.command) {
        overrides.push(`mcp_servers.${alias}.command=${JSON.stringify(mcp.command)}`);
      }
      if (mcp.args && mcp.args.length > 0) {
        overrides.push(`mcp_servers.${alias}.args=${JSON.stringify(mcp.args)}`);
      }
      if (mcp.url) {
        overrides.push(`mcp_servers.${alias}.url=${JSON.stringify(mcp.url)}`);
      }
      overrides.push(`apps.${alias}.enabled=true`);
      overrides.push(`apps.${alias}.default_tools_enabled=true`);
      overrides.push(`apps.${alias}.default_tools_approval_mode="approve"`);
      overrides.push(`apps.${alias}.destructive_enabled=true`);
      overrides.push(`apps.${alias}.open_world_enabled=true`);
      for (const [envKey, envValue] of Object.entries(mcp.env ?? {})) {
        overrides.push(`mcp_servers.${alias}.env.${envKey}=${JSON.stringify(envValue)}`);
      }
    }
    return overrides;
  }

  private buildClientEnvOverrides(config: AgentConfig): Record<string, string> {
    return {
      CODEX_HOME: this.prepareIsolatedCodexHome(config),
    };
  }

  private prepareIsolatedCodexHome(config: AgentConfig): string {
    const isolatedHome = join(this.sidecarDataDir(), "codex-home");
    mkdirSync(isolatedHome, { recursive: true });

    // Keep Codex sessions isolated from unrelated user-level MCP configuration.
    writeFileSync(join(isolatedHome, "config.toml"), this.buildIsolatedCodexConfig(config));

    const sourceCodexHome = process.env.CODEX_HOME?.trim() || join(homedir(), ".codex");
    this.syncCodexAuthFile(join(sourceCodexHome, "auth.json"), join(isolatedHome, "auth.json"));

    return isolatedHome;
  }

  private buildIsolatedCodexConfig(config: AgentConfig): string {
    const lines = [
      "# Managed by Odyssey sidecar. User-level Codex config is intentionally isolated.",
      "",
    ];

    for (const projectPath of this.projectPathsToUntrust(config.workingDirectory)) {
      lines.push(`[projects.${JSON.stringify(projectPath)}]`);
      lines.push('trust_level = "untrusted"');
      lines.push("");
    }

    return `${lines.join("\n").trimEnd()}\n`;
  }

  private projectPathsToUntrust(workingDirectory: string | undefined): string[] {
    const paths = new Set<string>();
    let current = workingDirectory?.trim();
    while (current && current !== dirname(current)) {
      paths.add(current);
      current = dirname(current);
    }
    if (current) {
      paths.add(current);
    }
    return [...paths];
  }

  private sidecarDataDir(): string {
    return process.env.ODYSSEY_DATA_DIR?.trim()
      || process.env.CLAUDESTUDIO_DATA_DIR?.trim()
      || join(homedir(), ".odyssey", "instances", "default");
  }

  private syncCodexAuthFile(sourceAuthPath: string, targetAuthPath: string) {
    if (!existsSync(sourceAuthPath)) {
      logger.warn("codex", `Codex auth file not found at ${sourceAuthPath}; isolated CODEX_HOME will rely on other login methods.`);
      return;
    }

    try {
      if (existsSync(targetAuthPath)) {
        try {
          if (readlinkSync(targetAuthPath) === sourceAuthPath) {
            return;
          }
        } catch {
          // Replace regular files or stale symlinks below.
        }
        rmSync(targetAuthPath, { force: true });
      }

      symlinkSync(sourceAuthPath, targetAuthPath);
    } catch (error: any) {
      logger.warn("codex", `Failed to symlink Codex auth into isolated CODEX_HOME: ${error?.message ?? error}`);
      try {
        writeFileSync(targetAuthPath, readFileSync(sourceAuthPath));
      } catch (copyError: any) {
        logger.warn("codex", `Failed to copy Codex auth into isolated CODEX_HOME: ${copyError?.message ?? copyError}`);
      }
    }
  }
  private recordToolCall(sessionId: string) {
    const state = this.deps.registry.get(sessionId);
    this.deps.registry.update(sessionId, {
      toolCallCount: (state?.toolCallCount ?? 0) + 1,
    });
  }
}
