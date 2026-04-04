import { afterEach, describe, expect, test } from "bun:test";
import { ClaudeRuntime } from "../../src/providers/claude-runtime.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import { makeAgentConfig } from "../helpers.js";

const originalEnv = { ...process.env };

afterEach(() => {
  for (const key of ["ODYSSEY_OLLAMA_MODELS_ENABLED", "CLAUDESTUDIO_OLLAMA_MODELS_ENABLED", "ODYSSEY_OLLAMA_BASE_URL", "CLAUDESTUDIO_OLLAMA_BASE_URL"]) {
    if (originalEnv[key] == null) {
      delete process.env[key];
    } else {
      process.env[key] = originalEnv[key];
    }
  }
});

function makeToolContext(sessions: SessionRegistry, emit: (event: SidecarEvent) => void): ToolContext {
  return {
    blackboard: new BlackboardStore(`claude-runtime-${Date.now()}`),
    taskBoard: new TaskBoardStore(`claude-runtime-${Date.now()}`),
    sessions,
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: emit,
    agentDefinitions: new Map(),
    spawnSession: async (sessionId, _config, _initialPrompt, _waitForResult) => ({ sessionId }),
  };
}

function makeRuntime() {
  const sessions = new SessionRegistry();
  const emit = (_event: SidecarEvent) => {};
  return new ClaudeRuntime({
    emit,
    registry: sessions,
    toolCtx: makeToolContext(sessions, emit),
  });
}

describe("ClaudeRuntime Ollama routing", () => {
  test("strips the ollama prefix and injects Anthropic-compatible env overrides", () => {
    process.env.ODYSSEY_OLLAMA_MODELS_ENABLED = "1";
    process.env.ODYSSEY_OLLAMA_BASE_URL = "http://127.0.0.1:22434";

    const runtime = makeRuntime();
    const options = runtime.buildTurnOptionsForTesting(
      "session-1",
      makeAgentConfig({ model: "ollama:qwen3-coder:latest" }),
      undefined,
      0,
      false,
    );

    expect(options.model).toBe("qwen3-coder:latest");
    expect(options.env.ANTHROPIC_BASE_URL).toBe("http://127.0.0.1:22434");
    expect(options.env.ANTHROPIC_AUTH_TOKEN).toBe("ollama");
    expect(options.env.ANTHROPIC_API_KEY).toBe("");
  });

  test("plan mode keeps the selected ollama model instead of forcing opus", () => {
    process.env.ODYSSEY_OLLAMA_MODELS_ENABLED = "1";

    const runtime = makeRuntime();
    const options = runtime.buildTurnOptionsForTesting(
      "session-2",
      makeAgentConfig({ model: "ollama:qwen3-coder:latest", maxTurns: 4 }),
      undefined,
      0,
      true,
    );

    expect(options.model).toBe("qwen3-coder:latest");
    expect(options.maxTurns).toBe(4);
  });

  test("plan mode still upgrades native Claude sessions to Opus", () => {
    const runtime = makeRuntime();
    const options = runtime.buildTurnOptionsForTesting(
      "session-3",
      makeAgentConfig({ model: "claude-sonnet-4-6", maxTurns: 4 }),
      undefined,
      0,
      true,
    );

    expect(options.model).toBe("claude-opus-4-6");
    expect(options.maxTurns).toBe(30);
  });

  test("disabled ollama-backed models fail fast", () => {
    process.env.ODYSSEY_OLLAMA_MODELS_ENABLED = "0";

    const runtime = makeRuntime();

    expect(() => runtime.buildTurnOptionsForTesting(
      "session-4",
      makeAgentConfig({ model: "ollama:qwen3-coder:latest" }),
      undefined,
      0,
      false,
    )).toThrow("Ollama-backed Claude models are disabled");
  });
});
