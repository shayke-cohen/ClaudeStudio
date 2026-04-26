import type {
  AgentConfig,
  BulkResumeEntry,
  FileAttachment,
  SidecarEvent,
} from "./types.js";
import type { SessionRegistry } from "./stores/session-registry.js";
import type { ToolContext } from "./tools/tool-context.js";
import { pendingQuestions, questionsBySession } from "./tools/ask-user-tool.js";
import { logger } from "./logger.js";
import { ClaudeRuntime } from "./providers/claude-runtime.js";
import { CodexRuntime } from "./providers/codex-runtime.js";
import { LocalAgentRuntime } from "./providers/local-agent-runtime.js";
import { MockRuntime } from "./providers/mock-runtime.js";
import type { ProviderRuntime } from "./providers/runtime.js";
import { buildMCPPreflightReport } from "./mcp-preflight.js";
import { checkClaudePreflight, checkCodexPreflight } from "./providers/preflight-check.js";

type EventEmitter = (event: SidecarEvent) => void;

export interface TurnRecord {
  index: number;
  startedAt: string;
  completedAt?: string;
  durationMs?: number;
  inputPreview: string;
  tokenCount?: number;
  cost?: number;
  error?: string;
  status: "active" | "completed" | "failed" | "paused";
}

export class SessionManager {
  private readonly activeAborts = new Map<string, AbortController>();
  private readonly autonomousResults = new Map<string, { resolve: (result: string) => void }>();
  private readonly pendingCreates = new Map<string, Promise<void>>();
  private readonly runtimes: Record<"claude" | "codex" | "foundation" | "mlx" | "mock", ProviderRuntime>;
  private readonly suppressedEvalSessions = new Set<string>();
  private readonly turnHistory = new Map<string, TurnRecord[]>();
  private readonly tokenBatchers = new Map<string, { timer: ReturnType<typeof setTimeout> | null; buffer: string[] }>();
  private static readonly OLLAMA_CLAUDE_TURN_TIMEOUT_MS = 360_000;
  private static readonly OLLAMA_TURN_TIMEOUT_CODE = "OLLAMA_TURN_TIMEOUT";

  constructor(
    private readonly emit: EventEmitter,
    private readonly registry: SessionRegistry,
    private readonly toolCtx: ToolContext,
  ) {
    const suppressAwareEmit = (event: SidecarEvent) => {
      if ("sessionId" in event && typeof event.sessionId === "string" && this.suppressedEvalSessions.has(event.sessionId)) {
        return;
      }
      if (event.type === "stream.token" && "sessionId" in event && "text" in event) {
        const sid = event.sessionId as string;
        const text = (event as { text: string }).text;
        let batcher = this.tokenBatchers.get(sid);
        if (!batcher) {
          batcher = { timer: null, buffer: [] };
          this.tokenBatchers.set(sid, batcher);
        }
        batcher.buffer.push(text);
        if (batcher.timer) clearTimeout(batcher.timer);
        batcher.timer = setTimeout(() => this.flushTokenBatch(sid, emit), 50);
        return;
      }
      emit(event);
    };
    const deps = {
      emit: suppressAwareEmit,
      registry,
      toolCtx,
    };
    this.runtimes = {
      claude: new ClaudeRuntime(deps),
      codex: new CodexRuntime(deps),
      foundation: new LocalAgentRuntime("foundation", deps),
      mlx: new LocalAgentRuntime("mlx", deps),
      mock: new MockRuntime(deps),
    };
  }

  updateSessionCwd(sessionId: string, workingDirectory: string): void {
    this.registry.updateConfig(sessionId, { workingDirectory });
  }

  async createSession(conversationId: string, config: AgentConfig): Promise<void> {
    if (this.registry.get(conversationId)) {
      logger.info("session", `Session ${conversationId} already exists, skipping create`);
      return;
    }

    const normalizedConfig = {
      ...config,
      provider: config.provider ?? "claude",
    };

    // Pre-flight: verify required tool is installed and authenticated before creating the session.
    const preflightResult =
      normalizedConfig.provider === "codex"
        ? checkCodexPreflight()
        : normalizedConfig.provider === "claude"
          ? checkClaudePreflight()
          : { ok: true };
    if (!preflightResult.ok) {
      const error = preflightResult.error!;
      logger.error("session", `Pre-flight check failed for ${conversationId}: ${error}`);
      this.emit({ type: "session.error", sessionId: conversationId, error });
      return;
    }
    this.registry.create(conversationId, normalizedConfig);
    this.logMCPPreflight(conversationId, normalizedConfig);
    const createPromise = this.runtimeFor(normalizedConfig)
      .createSession(conversationId, normalizedConfig)
      .then(() => {
        logger.info(
          "session",
          `Created session ${conversationId} for "${normalizedConfig.name}" (provider: ${normalizedConfig.provider}, model: ${normalizedConfig.model})`,
        );
      });
    this.pendingCreates.set(conversationId, createPromise);

    try {
      await createPromise;
    } finally {
      if (this.pendingCreates.get(conversationId) === createPromise) {
        this.pendingCreates.delete(conversationId);
      }
    }
  }

  async sendMessage(
    sessionId: string,
    text: string,
    attachments?: FileAttachment[],
    planMode?: boolean,
  ): Promise<void> {
    const turnStartedAt = Date.now();
    // Start turn record
    const sessionTurns = this.turnHistory.get(sessionId) ?? [];
    const turnRecord: TurnRecord = {
      index: sessionTurns.length,
      startedAt: new Date().toISOString(),
      inputPreview: text.slice(0, 120),
      status: "active",
    };
    sessionTurns.push(turnRecord);
    // Keep last 50 turns per session
    if (sessionTurns.length > 50) sessionTurns.shift();
    this.turnHistory.set(sessionId, sessionTurns);
    const pendingCreate = this.pendingCreates.get(sessionId);
    if (pendingCreate) {
      try {
        await pendingCreate;
      } catch {
        // Let the normal config/state checks below surface the failure.
      }
    }

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
      const runtime = this.runtimeFor(config);
      logger.info(
        "session",
        `[${sessionId}] Starting turn via ${config.provider ?? "claude"} (textLength=${text.length}, attachments=${attachments?.length ?? 0}, planMode=${planMode === true})`,
      );
      const result = await this.sendWithProviderTimeout(
        runtime,
        {
          sessionId,
          config,
          backendSessionId: state.claudeSessionId,
          text,
          attachments,
          planMode,
          abortController,
        },
      );
      logger.info(
        "session",
        `[${sessionId}] Runtime completed in ${Date.now() - turnStartedAt}ms (resultLength=${result.resultText.length}, inputTokens=${result.inputTokens}, outputTokens=${result.outputTokens})`,
      );

      if (abortController.signal.aborted) {
        this.registry.update(sessionId, { status: "paused" });
        turnRecord.status = "paused";
        turnRecord.completedAt = new Date().toISOString();
        turnRecord.durationMs = Date.now() - turnStartedAt;
        return;
      }

      if (result.backendSessionId && result.backendSessionId !== state.claudeSessionId) {
        this.registry.update(sessionId, { claudeSessionId: result.backendSessionId });
      }

      const latestState = this.registry.get(sessionId);
      this.registry.update(sessionId, {
        status: "completed",
        cost: (latestState?.cost ?? 0) + result.costDelta,
        tokenCount: result.inputTokens + result.outputTokens,
      });

      this.emit({
        type: "session.result",
        sessionId,
        result: result.resultText || "(no text response)",
        cost: (this.registry.get(sessionId)?.cost ?? 0),
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        numTurns: result.numTurns,
        toolCallCount: this.registry.get(sessionId)?.toolCallCount ?? 0,
      });

      const waiter = this.autonomousResults.get(sessionId);
      if (waiter) {
        waiter.resolve(result.resultText);
        this.autonomousResults.delete(sessionId);
      }

      // Complete turn record
      turnRecord.completedAt = new Date().toISOString();
      turnRecord.durationMs = Date.now() - turnStartedAt;
      turnRecord.tokenCount = result.inputTokens + result.outputTokens;
      turnRecord.cost = result.costDelta;
      turnRecord.status = "completed";
    } catch (err: any) {
      if (abortController.signal.aborted && !this.isOllamaTurnTimeout(abortController.signal.reason)) {
        this.registry.update(sessionId, { status: "paused" });
        turnRecord.status = "paused";
        turnRecord.completedAt = new Date().toISOString();
        turnRecord.durationMs = Date.now() - turnStartedAt;
      } else {
        const timeoutReason = this.isOllamaTurnTimeout(abortController.signal.reason)
          ? abortController.signal.reason
          : undefined;
        const errorMessage = timeoutReason?.message ?? err?.message ?? String(err);
        logger.error("session", `[${sessionId}] Error: ${errorMessage}`, {
          stack: err?.stack?.substring(0, 500),
        });
        this.emit({
          type: "session.error",
          sessionId,
          error: errorMessage,
        });
        this.registry.update(sessionId, { status: "failed" });

        // Fail turn record
        turnRecord.completedAt = new Date().toISOString();
        turnRecord.durationMs = Date.now() - turnStartedAt;
        turnRecord.error = errorMessage;
        turnRecord.status = "failed";

        const waiter = this.autonomousResults.get(sessionId);
        if (waiter) {
          waiter.resolve(`Error: ${errorMessage}`);
          this.autonomousResults.delete(sessionId);
        }
      }
    } finally {
      this.flushTokenBatch(sessionId, this.emit);
      this.tokenBatchers.delete(sessionId);
      this.activeAborts.delete(sessionId);
    }
  }

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

      this.sendMessage(sessionId, initialPrompt).catch((error) => {
        logger.error("session", `[${sessionId}] Autonomous send error: ${error}`);
      });

      return {
        sessionId,
        result: await resultPromise,
      };
    }

    this.sendMessage(sessionId, initialPrompt).catch((error) => {
      logger.error("session", `[${sessionId}] Autonomous send error: ${error}`);
    });
    return { sessionId };
  }

  private async sendWithProviderTimeout(
    runtime: ProviderRuntime,
    args: {
      sessionId: string;
      config: AgentConfig;
      backendSessionId: string | undefined;
      text: string;
      attachments?: FileAttachment[];
      planMode?: boolean;
      abortController: AbortController;
    },
  ) {
    if (!this.isOllamaClaudeConfig(args.config)) {
      return runtime.sendMessage(args);
    }

    const timeoutMs = SessionManager.OLLAMA_CLAUDE_TURN_TIMEOUT_MS;
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        runtime.sendMessage(args),
        new Promise<never>((_, reject) => {
          timeoutId = setTimeout(() => {
            const timeoutError = Object.assign(new Error(
              `Ollama-backed Claude model ${args.config.model} did not complete a Claude Code turn within ${timeoutMs}ms. This local model may not be compatible with the Claude Code tool loop on this machine.`,
            ), { code: SessionManager.OLLAMA_TURN_TIMEOUT_CODE });
            args.abortController.abort(timeoutError);
            reject(timeoutError);
          }, timeoutMs);
        }),
      ]);
    } finally {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    }
  }

  private isOllamaClaudeConfig(config: AgentConfig): boolean {
    return (config.provider ?? "claude") === "claude"
      && typeof config.model === "string"
      && config.model.startsWith("ollama:");
  }

  private isOllamaTurnTimeout(reason: unknown): reason is Error & { code: string } {
    return typeof reason === "object"
      && reason !== null
      && "code" in reason
      && (reason as { code?: unknown }).code === SessionManager.OLLAMA_TURN_TIMEOUT_CODE;
  }

  async resumeSession(sessionId: string, claudeSessionId: string): Promise<void> {
    const config = this.registry.getConfig(sessionId);
    if (!config) {
      return;
    }

    this.registry.update(sessionId, {
      claudeSessionId,
      provider: config.provider ?? "claude",
      status: "active",
    });
    await this.runtimeFor(config).resumeSession(sessionId, claudeSessionId, config);
  }

  async bulkResume(sessions: BulkResumeEntry[]): Promise<void> {
    let restored = 0;
    for (const entry of sessions) {
      const normalizedConfig = {
        ...entry.agentConfig,
        provider: entry.agentConfig.provider ?? "claude",
      };

      if (!this.registry.get(entry.sessionId)) {
        this.registry.create(entry.sessionId, normalizedConfig);
      }

      this.registry.update(entry.sessionId, {
        claudeSessionId: entry.claudeSessionId,
        provider: normalizedConfig.provider ?? "claude",
        status: "active",
      });
      await this.runtimeFor(normalizedConfig).resumeSession(entry.sessionId, entry.claudeSessionId, normalizedConfig);
      restored++;
    }

    logger.info("session", `Bulk resume: restored ${restored}/${sessions.length} sessions`);
  }

  async forkSession(parentSessionId: string, childSessionId: string): Promise<void> {
    const config = this.registry.getConfig(parentSessionId);
    const parentState = this.registry.get(parentSessionId);
    if (config) {
      this.registry.create(childSessionId, config);
      const backendSessionId = await this.runtimeFor(config).forkSession(
        parentSessionId,
        childSessionId,
        config,
        parentState?.claudeSessionId,
      );
      if (backendSessionId) {
        this.registry.update(childSessionId, { claudeSessionId: backendSessionId });
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

    const state = this.registry.get(sessionId);
    const config = this.registry.getConfig(sessionId);
    if (state && config) {
      await this.runtimeFor(config).pauseSession(sessionId);
    }

    const questionIds = questionsBySession.get(sessionId);
    if (questionIds) {
      for (const questionId of [...questionIds]) {
        const pending = pendingQuestions.get(questionId);
        if (pending) {
          clearTimeout(pending.timer);
          pending.resolve({ answer: "[Session was paused before you could answer.]" });
          pendingQuestions.delete(questionId);
        }
      }
      questionsBySession.delete(sessionId);
    }

    // spawnAutonomous(waitForResult=true) leaves a Promise resolver here.
    // sendMessage's abort branch did NOT call it, so without explicit
    // cleanup any awaited spawnAutonomous result hung forever after a pause.
    const waiter = this.autonomousResults.get(sessionId);
    if (waiter) {
      waiter.resolve("[Session paused]");
      this.autonomousResults.delete(sessionId);
    }

    this.flushTokenBatch(sessionId, this.emit);
    this.tokenBatchers.delete(sessionId);
    this.toolCtx.delegation.delete(sessionId);
    this.turnHistory.delete(sessionId);
    this.registry.update(sessionId, { status: "paused" });
  }

  updateSessionMode(
    sessionId: string,
    interactive: boolean,
    instancePolicy?: "spawn" | "singleton" | "pool",
    instancePolicyPoolMax?: number,
  ): void {
    if (!this.registry.getConfig(sessionId)) {
      logger.warn("session", `Cannot update mode for missing session ${sessionId}`);
      return;
    }

    this.registry.updateConfig(sessionId, {
      interactive,
      instancePolicy,
      instancePolicyPoolMax,
    });
    logger.info(
      "session",
      `Updated mode for ${sessionId} (interactive=${interactive}, instancePolicy=${instancePolicy ?? "default"}, poolMax=${instancePolicyPoolMax ?? 0})`,
    );
  }

  async answerQuestion(
    sessionId: string,
    questionId: string,
    answer: string,
    selectedOptions?: string[],
  ): Promise<boolean> {
    const config = this.registry.getConfig(sessionId);
    if (!config) {
      return false;
    }

    return (await this.runtimeFor(config).answerQuestion?.(sessionId, questionId, answer, selectedOptions)) ?? false;
  }

  async answerConfirmation(
    sessionId: string,
    confirmationId: string,
    approved: boolean,
    modifiedAction?: string,
  ): Promise<boolean> {
    const config = this.registry.getConfig(sessionId);
    if (!config) {
      return false;
    }

    return (await this.runtimeFor(config).answerConfirmation?.(sessionId, confirmationId, approved, modifiedAction)) ?? false;
  }

  listSessions() {
    return this.registry.list();
  }

  getTurnHistory(sessionId: string): TurnRecord[] {
    return this.turnHistory.get(sessionId) ?? [];
  }

  buildQueryOptionsForTesting(
    sessionId: string,
    attachmentCount = 0,
    planMode?: boolean,
  ): Record<string, any> {
    const config = this.registry.getConfig(sessionId);
    const state = this.registry.get(sessionId);
    if (!config || !state) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const runtime = this.runtimeFor(config);
    if (!runtime.buildTurnOptionsForTesting) {
      throw new Error(`Provider ${config.provider ?? "claude"} does not expose testing options`);
    }

    return runtime.buildTurnOptionsForTesting(
      sessionId,
      config,
      state.claudeSessionId,
      attachmentCount,
      planMode,
    );
  }

  async evaluateSession(
    sessionId: string,
    prompt: string,
  ): Promise<{ status: "complete" | "needsMore" | "failed"; reason: string } | null> {
    const config = this.registry.getConfig(sessionId);
    const state = this.registry.get(sessionId);
    if (!config || !state?.claudeSessionId) {
      logger.warn("session", `evaluateSession: no config or claudeSessionId for ${sessionId}`);
      return null;
    }

    this.suppressedEvalSessions.add(sessionId);
    try {
      const result = await this.sendWithProviderTimeout(
        this.runtimeFor(config),
        {
          sessionId,
          config,
          backendSessionId: state.claudeSessionId,
          text: prompt,
          attachments: undefined,
          planMode: false,
          abortController: new AbortController(),
        },
      );

      const text = result.resultText;
      const statusMatch = text.match(/STATUS:\s*(COMPLETE|NEEDS_MORE|FAILED)/i);
      const reasonMatch = text.match(/REASON:\s*(.+)/i);
      if (!statusMatch) return null;

      const raw = statusMatch[1].toUpperCase();
      const status: "complete" | "needsMore" | "failed" =
        raw === "COMPLETE" ? "complete" : raw === "NEEDS_MORE" ? "needsMore" : "failed";
      const reason = reasonMatch?.[1]?.trim() ?? "";
      return { status, reason };
    } catch (err) {
      logger.error("session", `evaluateSession error for ${sessionId}: ${String(err)}`);
      return null;
    } finally {
      this.suppressedEvalSessions.delete(sessionId);
    }
  }

  flushTokenBatch(sessionId: string, emitFn: EventEmitter): void {
    const batcher = this.tokenBatchers.get(sessionId);
    if (!batcher || batcher.buffer.length === 0) return;
    const combined = batcher.buffer.join("");
    batcher.buffer = [];
    if (batcher.timer) {
      clearTimeout(batcher.timer);
      batcher.timer = null;
    }
    emitFn({ type: "stream.token", sessionId, text: combined } as SidecarEvent);
  }

  private runtimeFor(config: AgentConfig): ProviderRuntime {
    return this.runtimes[config.provider ?? "claude"];
  }

  private logMCPPreflight(sessionId: string, config: AgentConfig): void {
    const report = buildMCPPreflightReport(config);
    logger.info("session", `MCP preflight for ${sessionId}`, {
      provider: report.provider,
      effectivePath: report.effectivePath,
      resolvedMCPNames: report.resolvedMCPNames,
      toolsetVisibleToSession: report.toolsetVisibleToSession,
      probes: report.probes,
    });

    if (report.appxrayTarget.checked) {
      logger.info("session", `AppXray target probe for ${sessionId}`, report.appxrayTarget);
    }
  }
}
