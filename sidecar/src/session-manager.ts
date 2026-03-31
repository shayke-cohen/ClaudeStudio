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
import type { ProviderRuntime } from "./providers/runtime.js";
import { buildMCPPreflightReport } from "./mcp-preflight.js";

type EventEmitter = (event: SidecarEvent) => void;

export class SessionManager {
  private readonly activeAborts = new Map<string, AbortController>();
  private readonly autonomousResults = new Map<string, { resolve: (result: string) => void }>();
  private readonly runtimes: Record<"claude" | "codex", ProviderRuntime>;

  constructor(
    private readonly emit: EventEmitter,
    private readonly registry: SessionRegistry,
    private readonly toolCtx: ToolContext,
  ) {
    const deps = {
      emit,
      registry,
      toolCtx,
    };
    this.runtimes = {
      claude: new ClaudeRuntime(deps),
      codex: new CodexRuntime(deps),
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
    this.registry.create(conversationId, normalizedConfig);
    this.logMCPPreflight(conversationId, normalizedConfig);
    await this.runtimeFor(normalizedConfig).createSession(conversationId, normalizedConfig);
    logger.info(
      "session",
      `Created session ${conversationId} for "${normalizedConfig.name}" (provider: ${normalizedConfig.provider}, model: ${normalizedConfig.model})`,
    );
  }

  async sendMessage(
    sessionId: string,
    text: string,
    attachments?: FileAttachment[],
    planMode?: boolean,
  ): Promise<void> {
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
      const result = await runtime.sendMessage({
        sessionId,
        config,
        backendSessionId: state.claudeSessionId,
        text,
        attachments,
        planMode,
        abortController,
      });

      if (abortController.signal.aborted) {
        this.registry.update(sessionId, { status: "paused" });
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
    } catch (err: any) {
      if (abortController.signal.aborted) {
        this.registry.update(sessionId, { status: "paused" });
      } else {
        const errorMessage = err?.message ?? String(err);
        logger.error("session", `[${sessionId}] Error: ${errorMessage}`, {
          stack: err?.stack?.substring(0, 500),
        });
        this.emit({
          type: "session.error",
          sessionId,
          error: errorMessage,
        });
        this.registry.update(sessionId, { status: "failed" });

        const waiter = this.autonomousResults.get(sessionId);
        if (waiter) {
          waiter.resolve(`Error: ${errorMessage}`);
          this.autonomousResults.delete(sessionId);
        }
      }
    } finally {
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
    await this.runtimeFor(config).resumeSession(sessionId, claudeSessionId);
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
      await this.runtimeFor(normalizedConfig).resumeSession(entry.sessionId, entry.claudeSessionId);
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

    this.registry.update(sessionId, { status: "paused" });
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
