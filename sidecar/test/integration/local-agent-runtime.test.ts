import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, rm, writeFile } from "fs/promises";
import { tmpdir } from "os";
import { join } from "path";
import { SessionManager } from "../../src/session-manager.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import { makeAgentConfig } from "../helpers.js";

const tempDirs = new Set<string>();
const originalHostBinary = process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY;
const originalLegacyHostBinary = process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY;

afterEach(async () => {
  if (originalHostBinary == null) {
    delete process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY;
  } else {
    process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY = originalHostBinary;
  }

  if (originalLegacyHostBinary == null) {
    delete process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY;
  } else {
    process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY = originalLegacyHostBinary;
  }

  await Promise.all(
    Array.from(tempDirs).map(async (dir) => {
      await rm(dir, { recursive: true, force: true });
      tempDirs.delete(dir);
    }),
  );
});

function makeToolContext(sessions: SessionRegistry, emit: (event: SidecarEvent) => void): ToolContext {
  return {
    blackboard: new BlackboardStore(`local-agent-runtime-${Date.now()}`),
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
    spawnSession: async (sessionId) => ({ sessionId }),
  };
}

async function writeSingleFlightHostFixture(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "odyssey-local-host-"));
  tempDirs.add(dir);
  const fixturePath = join(dir, "single-flight-host.cjs");
  await writeFile(
    fixturePath,
    `#!/usr/bin/env node
const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
let busy = false;

function write(message) {
  process.stdout.write(JSON.stringify(message) + "\\n");
}

rl.on("line", (line) => {
  if (!line.trim()) return;
  const request = JSON.parse(line);

  switch (request.method) {
    case "initialize":
      write({ id: request.id, result: { name: "single-flight-fixture", version: "1.0.0" } });
      return;
    case "provider.probe":
      write({
        id: request.id,
        result: {
          provider: request.params.provider,
          available: true,
          supportsTools: true,
          supportsTranscriptResume: true
        }
      });
      return;
    case "session.create":
      write({
        id: request.id,
        result: { backendSessionId: request.params.sessionId + "-backend" }
      });
      return;
    case "session.message":
      if (busy) {
        write({
          id: request.id,
          error: {
            code: -32001,
            message: "concurrent session.message detected"
          }
        });
        return;
      }
      busy = true;
      setTimeout(() => {
        busy = false;
        write({
          id: request.id,
          result: {
            backendSessionId: request.params.sessionId + "-backend",
            resultText: "fixture reply: " + request.params.text,
            inputTokens: 2,
            outputTokens: 3,
            numTurns: 1,
            events: [
              { type: "token", sessionId: request.params.sessionId, text: "fixture " },
              { type: "token", sessionId: request.params.sessionId, text: "reply " }
            ]
          }
        });
      }, 50);
      return;
    case "session.resume":
    case "session.pause":
    case "session.fork":
      write({
        id: request.id,
        result: { backendSessionId: (request.params.sessionId || request.params.childSessionId) + "-backend" }
      });
      return;
    default:
      write({
        id: request.id,
        error: { code: -32601, message: "Unknown method " + request.method }
      });
  }
});
`,
  );

  return fixturePath;
}

async function writeDelayedCreateHostFixture(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "odyssey-local-host-"));
  tempDirs.add(dir);
  const fixturePath = join(dir, "delayed-create-host.cjs");
  await writeFile(
    fixturePath,
    `#!/usr/bin/env node
const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
const created = new Set();

function write(message) {
  process.stdout.write(JSON.stringify(message) + "\\n");
}

rl.on("line", (line) => {
  if (!line.trim()) return;
  const request = JSON.parse(line);

  switch (request.method) {
    case "initialize":
      write({ id: request.id, result: { name: "delayed-create-fixture", version: "1.0.0" } });
      return;
    case "provider.probe":
      setTimeout(() => {
        write({
          id: request.id,
          result: {
            provider: request.params.provider,
            available: true,
            supportsTools: true,
            supportsTranscriptResume: true
          }
        });
      }, 50);
      return;
    case "session.create":
      setTimeout(() => {
        created.add(request.params.sessionId);
        write({
          id: request.id,
          result: { backendSessionId: request.params.sessionId + "-backend" }
        });
      }, 200);
      return;
    case "session.message":
      if (!created.has(request.params.sessionId)) {
        write({
          id: request.id,
          error: { code: 404, message: "Session not found: " + request.params.sessionId }
        });
        return;
      }
      write({
        id: request.id,
        result: {
          backendSessionId: request.params.sessionId + "-backend",
          resultText: "fixture reply: " + request.params.text,
          inputTokens: 2,
          outputTokens: 3,
          numTurns: 1,
          events: [
            { type: "token", sessionId: request.params.sessionId, text: "fixture " },
            { type: "token", sessionId: request.params.sessionId, text: "reply " }
          ]
        }
      });
      return;
    default:
      write({
        id: request.id,
        error: { code: -32601, message: "Unknown method " + request.method }
      });
  }
});
`,
  );

  return fixturePath;
}

async function writePauseAwareHostFixture(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "odyssey-local-host-"));
  tempDirs.add(dir);
  const fixturePath = join(dir, "pause-aware-host.cjs");
  await writeFile(
    fixturePath,
    `#!/usr/bin/env node
const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
const pendingMessages = new Map();

function write(message) {
  process.stdout.write(JSON.stringify(message) + "\\n");
}

rl.on("line", (line) => {
  if (!line.trim()) return;
  const request = JSON.parse(line);

  switch (request.method) {
    case "initialize":
      write({ id: request.id, result: { name: "pause-aware-fixture", version: "1.0.0" } });
      return;
    case "provider.probe":
      write({
        id: request.id,
        result: {
          provider: request.params.provider,
          available: true,
          supportsTools: true,
          supportsTranscriptResume: true
        }
      });
      return;
    case "session.create":
      write({
        id: request.id,
        result: { backendSessionId: request.params.sessionId + "-backend" }
      });
      return;
    case "session.message":
      pendingMessages.set(request.params.sessionId, request.id);
      return;
    case "session.pause": {
      const pendingId = pendingMessages.get(request.params.sessionId);
      if (pendingId != null) {
        pendingMessages.delete(request.params.sessionId);
        write({
          id: pendingId,
          error: {
            code: -32000,
            message: "cancelled"
          }
        });
      }
      write({
        id: request.id,
        result: { backendSessionId: request.params.sessionId + "-backend" }
      });
      return;
    }
    default:
      write({
        id: request.id,
        error: { code: -32601, message: "Unknown method " + request.method }
      });
  }
});
`,
  );

  return fixturePath;
}

describe("LocalAgentRuntime", () => {
  test("serializes concurrent MLX sends through the shared runtime client", async () => {
    const fixturePath = await writeSingleFlightHostFixture();
    process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY = fixturePath;
    process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY = fixturePath;

    const events: SidecarEvent[] = [];
    const sessions = new SessionRegistry();
    const manager = new SessionManager(
      (event) => events.push(event),
      sessions,
      makeToolContext(sessions, (event) => events.push(event)),
    );

    const ids = ["mlx-a", "mlx-b", "mlx-c"];
    for (const id of ids) {
      await manager.createSession(id, makeAgentConfig({
        name: id,
        provider: "mlx",
        model: "mlx-fixture",
        workingDirectory: "/tmp",
      }));
    }

    await Promise.all(ids.map((id, index) => manager.sendMessage(id, `hello ${index + 1}`)));

    expect(events.filter((event) => event.type === "session.error")).toEqual([]);
    expect(
      events
        .filter((event) => event.type === "session.result")
        .map((event) => ({ sessionId: event.sessionId, result: event.result })),
    ).toEqual([
      { sessionId: "mlx-a", result: "fixture reply: hello 1" },
      { sessionId: "mlx-b", result: "fixture reply: hello 2" },
      { sessionId: "mlx-c", result: "fixture reply: hello 3" },
    ]);
  });

  test("waits for local session creation before sending the first MLX turn", async () => {
    const fixturePath = await writeDelayedCreateHostFixture();
    process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY = fixturePath;
    process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY = fixturePath;

    const events: SidecarEvent[] = [];
    const sessions = new SessionRegistry();
    const manager = new SessionManager(
      (event) => events.push(event),
      sessions,
      makeToolContext(sessions, (event) => events.push(event)),
    );

    const config = makeAgentConfig({
      name: "mlx-race",
      provider: "mlx",
      model: "mlx-fixture",
      workingDirectory: "/tmp",
    });

    const createPromise = manager.createSession("mlx-race", config);
    const sendPromise = manager.sendMessage("mlx-race", "hi");

    await Promise.all([createPromise, sendPromise]);

    expect(events.filter((event) => event.type === "session.error")).toEqual([]);
    expect(events).toContainEqual(expect.objectContaining({
      type: "session.result",
      sessionId: "mlx-race",
      result: "fixture reply: hi",
    }));
  });

  test("pause cancels an in-flight MLX local-host turn", async () => {
    const fixturePath = await writePauseAwareHostFixture();
    process.env.ODYSSEY_LOCAL_AGENT_HOST_BINARY = fixturePath;
    process.env.CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY = fixturePath;

    const events: SidecarEvent[] = [];
    const sessions = new SessionRegistry();
    const manager = new SessionManager(
      (event) => events.push(event),
      sessions,
      makeToolContext(sessions, (event) => events.push(event)),
    );

    await manager.createSession("mlx-pause", makeAgentConfig({
      name: "mlx-pause",
      provider: "mlx",
      model: "mlx-fixture",
      workingDirectory: "/tmp",
    }));

    const sendPromise = manager.sendMessage("mlx-pause", "hello");
    await Bun.sleep(50);
    await manager.pauseSession("mlx-pause");
    await sendPromise;

    expect(events.filter((event) => event.type === "session.result" && event.sessionId === "mlx-pause")).toEqual([]);
    expect(events.filter((event) => event.type === "session.error" && event.sessionId === "mlx-pause")).toEqual([]);
    expect(sessions.get("mlx-pause")?.status).toBe("paused");
  });
});
