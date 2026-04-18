import type { AgentConfig } from "../types.js";
import type { RuntimeDependencies, RuntimeSendArgs, RuntimeSendResult, ProviderRuntime } from "./runtime.js";

export class MockRuntime implements ProviderRuntime {
  readonly provider = "mock" as const;

  constructor(private readonly deps: RuntimeDependencies) {}

  async createSession(_sessionId: string, _config: AgentConfig): Promise<void> {}

  async sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult> {
    const response = `mock: ${args.text.slice(0, 120)}`;
    this.deps.emit({ type: "stream.token", sessionId: args.sessionId, text: response });
    return {
      resultText: response,
      costDelta: 0,
      inputTokens: 1,
      outputTokens: 1,
      numTurns: 1,
    };
  }

  async resumeSession(_sessionId: string, _backendSessionId: string, _config?: AgentConfig): Promise<void> {}

  async forkSession(
    _parentSessionId: string,
    _childSessionId: string,
    _config: AgentConfig,
    _parentBackendSessionId?: string,
  ): Promise<string | undefined> {
    return undefined;
  }

  async pauseSession(_sessionId: string): Promise<void> {}
}
