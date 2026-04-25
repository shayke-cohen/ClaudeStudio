import type { AgentConfig } from "../types.js";
import { createPeerBusToolDefinitions } from "../tools/peerbus-server.js";
import { logger } from "../logger.js";
import type {
  ProviderRuntime,
  RuntimeDependencies,
  RuntimeSendArgs,
  RuntimeSendResult,
} from "./runtime.js";
import { LocalAgentHostClient } from "./local-agent-host-client.js";

type LocalAgentProvider = "foundation" | "mlx";

interface LocalAgentEvent {
  type: "token" | "thinking" | "toolCall" | "toolResult" | "error";
  sessionId: string;
  text?: string;
  tool?: string;
  input?: string;
  output?: string;
}

export class LocalAgentRuntime implements ProviderRuntime {
  readonly provider: LocalAgentProvider;
  private readonly client: LocalAgentHostClient;
  private turnQueue: Promise<void> = Promise.resolve();

  constructor(
    provider: LocalAgentProvider,
    private readonly deps: RuntimeDependencies,
  ) {
    this.provider = provider;
    this.client = new LocalAgentHostClient();
    this.client.registerHandler("stream.token", async (params) => {
      const { sessionId, text } = params as { sessionId: string; text: string };
      if (sessionId && text) {
        this.deps.emit({ type: "stream.token", sessionId, text });
      }
      return { ok: true };
    });

    this.client.registerHandler("tool.call", async (params) => {
      const handlers = this.toolHandlers(params.sessionId);
      const handler = handlers.get(params.toolName);
      if (!handler) {
        throw new Error(`Unknown Odyssey callback tool: ${params.toolName}`);
      }

      const result = await handler.execute(
        this.coerceArguments(params.arguments ?? {}),
        { sessionId: params.sessionId },
      );
      const output = result.content.map((item) => item.text).join("\n");
      return {
        success: result.success ?? true,
        output,
      };
    });
  }

  async createSession(sessionId: string, config: AgentConfig): Promise<void> {
    const probe = await this.client.call("provider.probe", { provider: this.provider });
    if (!probe?.available) {
      throw new Error(probe?.reason ?? `${this.provider} provider is unavailable`);
    }

    logger.info(
      "local-agent",
      `[${sessionId}] createSession provider=${this.provider} model=${config.model} toolDefs=${this.hostToolDefinitions(sessionId, config).length}`,
    );
    await this.client.call("session.create", {
      sessionId,
      config: this.toHostConfig(sessionId, config),
    });
  }

  async sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult> {
    if ((args.attachments?.length ?? 0) > 0) {
      throw new Error(`Provider ${this.provider} does not support attachments yet`);
    }

    const abortHandler = () => {
      this.pauseSession(args.sessionId).catch((error) => {
        logger.warn(
          "local-agent",
          `[${args.sessionId}] Failed to interrupt local ${this.provider} turn: ${error?.message ?? error}`,
        );
      });
    };
    args.abortController.signal.addEventListener("abort", abortHandler, { once: true });

    try {
      return await this.enqueueTurn(async () => {
        if (args.abortController.signal.aborted) {
          throw new Error(`Local ${this.provider} turn was aborted before reaching the host`);
        }
        const startedAt = Date.now();
        logger.info(
          "local-agent",
          `[${args.sessionId}] session.message -> host provider=${this.provider} textLength=${args.text.length}`,
        );
        const result = await this.client.call("session.message", {
          sessionId: args.sessionId,
          text: args.text,
        });
        logger.info(
          "local-agent",
          `[${args.sessionId}] host response in ${Date.now() - startedAt}ms events=${result.events?.length ?? 0} resultLength=${result.resultText?.length ?? 0}`,
        );
        this.emitEvents(result.events ?? []);

        return {
          backendSessionId: result.backendSessionId,
          resultText: result.resultText ?? "",
          costDelta: 0,
          inputTokens: result.inputTokens ?? 0,
          outputTokens: result.outputTokens ?? 0,
          numTurns: result.numTurns ?? 1,
        };
      });
    } finally {
      args.abortController.signal.removeEventListener("abort", abortHandler);
    }
  }

  async resumeSession(sessionId: string, backendSessionId: string, config?: AgentConfig): Promise<void> {
    const resolvedConfig = config ?? this.deps.registry.getConfig(sessionId);
    await this.client.call("session.resume", {
      sessionId,
      backendSessionId,
      ...(resolvedConfig ? { config: this.toHostConfig(sessionId, resolvedConfig) } : {}),
    });
  }

  async forkSession(
    parentSessionId: string,
    childSessionId: string,
    _config: AgentConfig,
    _parentBackendSessionId?: string,
  ): Promise<string | undefined> {
    const result = await this.client.call("session.fork", {
      parentSessionId,
      childSessionId,
    });
    return result?.backendSessionId;
  }

  async pauseSession(sessionId: string): Promise<void> {
    await this.client.call("session.pause", { sessionId });
  }

  buildTurnOptionsForTesting(
    sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    attachmentCount: number,
    planMode?: boolean,
  ): Record<string, any> {
    return {
      provider: this.provider,
      model: config.model,
      cwd: config.workingDirectory,
      attachmentCount,
      planMode: planMode === true,
      backendSessionId,
      packagePath:
        process.env.ODYSSEY_LOCAL_AGENT_PACKAGE_PATH
        ?? process.env.CLAUDESTUDIO_LOCAL_AGENT_PACKAGE_PATH
        ?? this.defaultPackagePath(),
      toolDefinitionCount: this.hostToolDefinitions(sessionId, config).length,
    };
  }

  private toHostConfig(sessionId: string, config: AgentConfig) {
    return {
      name: config.name,
      provider: this.provider,
      model: config.model,
      systemPrompt: config.systemPrompt,
      workingDirectory: config.workingDirectory,
      maxTurns: config.maxTurns,
      maxThinkingTokens: config.maxThinkingTokens,
      maxTokensPerStep: config.maxTokensPerStep,
      allowedTools: config.allowedTools,
      mcpServers: config.mcpServers,
      skills: config.skills,
      toolDefinitions: this.hostToolDefinitions(sessionId, config),
    };
  }

  private hostToolDefinitions(sessionId: string, config: AgentConfig) {
    return createPeerBusToolDefinitions(
      this.deps.toolCtx,
      sessionId,
      config.interactive ?? false,
    ).map((definition) => ({
      name: definition.name,
      description: definition.description,
      inputSchema: Object.fromEntries(
        Object.entries(definition.inputSchema).map(([key, schema]) => [key, this.zodTypeName(schema)]),
      ),
    }));
  }

  private toolHandlers(sessionId: string) {
    const config = this.deps.registry.getConfig(sessionId);
    return new Map(
      createPeerBusToolDefinitions(
        this.deps.toolCtx,
        sessionId,
        config?.interactive ?? false,
      ).map((definition) => [definition.name, definition] as const),
    );
  }

  private coerceArguments(value: any): any {
    if (value === null || value === undefined) {
      return value;
    }

    if (Array.isArray(value)) {
      return value.map((entry) => this.coerceArguments(entry));
    }

    if (typeof value === "object") {
      return Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [key, this.coerceArguments(entry)]),
      );
    }

    return value;
  }

  private zodTypeName(schema: any): string {
    const typeName = schema?._def?.typeName;
    switch (typeName) {
      case "ZodNumber":
      case "ZodInt":
        return "number";
      case "ZodBoolean":
        return "bool";
      case "ZodArray":
        return "array";
      case "ZodObject":
        return "object";
      default:
        return "string";
    }
  }

  private emitEvents(events: LocalAgentEvent[]) {
    for (const event of events) {
      switch (event.type) {
        case "token":
          this.deps.emit({ type: "stream.token", sessionId: event.sessionId, text: event.text ?? "" });
          break;
        case "thinking":
          this.deps.emit({ type: "stream.thinking", sessionId: event.sessionId, text: event.text ?? "" });
          break;
        case "toolCall":
          this.deps.emit({
            type: "stream.toolCall",
            sessionId: event.sessionId,
            tool: event.tool ?? "unknown",
            input: event.input ?? "{}",
          });
          break;
        case "toolResult":
          this.deps.emit({
            type: "stream.toolResult",
            sessionId: event.sessionId,
            tool: event.tool ?? "unknown",
            output: event.output ?? "",
          });
          break;
        case "error":
          this.deps.emit({
            type: "session.error",
            sessionId: event.sessionId,
            error: event.text ?? "Local agent error",
          });
          break;
      }
    }
  }

  private defaultPackagePath(): string {
    return process.env.ODYSSEY_LOCAL_AGENT_PACKAGE_PATH?.trim()
      || process.env.CLAUDESTUDIO_LOCAL_AGENT_PACKAGE_PATH?.trim()
      || `${import.meta.dir}/../../../Packages/OdysseyLocalAgent`;
  }

  private enqueueTurn<T>(work: () => Promise<T>): Promise<T> {
    const prior = this.turnQueue;
    let release!: () => void;
    this.turnQueue = new Promise<void>((resolve) => {
      release = resolve;
    });

    return prior
      .catch(() => undefined)
      .then(work)
      .finally(() => {
        release();
      });
  }
}
