import { beforeEach, describe, expect, test } from "bun:test";
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

describe("Session recovery integration", () => {
  let registry: SessionRegistry;
  let events: SidecarEvent[];
  let manager: SessionManager;

  beforeEach(() => {
    registry = new SessionRegistry();
    events = [];

    const ctx: ToolContext = {
      blackboard: new BlackboardStore(`recovery-int-${Date.now()}`),
      sessions: registry,
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
      broadcast: (event) => events.push(event),
      spawnSession: async (sessionId) => ({ sessionId }),
      agentDefinitions: new Map(),
    };

    manager = new SessionManager((event) => events.push(event), registry, ctx);
  });

  test("bulkResume recreates missing registry entries with supplied config", async () => {
    const config = makeAgentConfig({
      name: "RecoveredBot",
      workingDirectory: "/tmp/recovered-bot",
      maxTurns: 7,
    });

    await manager.bulkResume([
      {
        sessionId: "missing-session",
        claudeSessionId: "claude-missing",
        agentConfig: config,
      },
    ]);

    const state = registry.get("missing-session");
    const restoredConfig = registry.getConfig("missing-session");
    expect(state).toBeDefined();
    expect(state?.status).toBe("active");
    expect(state?.claudeSessionId).toBe("claude-missing");
    expect(restoredConfig?.name).toBe("RecoveredBot");
    expect(restoredConfig?.workingDirectory).toBe("/tmp/recovered-bot");
    expect(restoredConfig?.maxTurns).toBe(7);
  });

  test("bulkResume updates existing entries without duplicating registry state", async () => {
    await manager.createSession("existing-session", makeAgentConfig({
      name: "ExistingBot",
      workingDirectory: "/tmp/existing-before",
    }));

    const originalCount = registry.list().length;
    await manager.bulkResume([
      {
        sessionId: "existing-session",
        claudeSessionId: "claude-existing",
        agentConfig: makeAgentConfig({
          name: "ExistingBotUpdated",
          workingDirectory: "/tmp/existing-after",
        }),
      },
      {
        sessionId: "new-session",
        claudeSessionId: "claude-new",
        agentConfig: makeAgentConfig({
          name: "NewBot",
          workingDirectory: "/tmp/new-session",
        }),
      },
    ]);

    expect(registry.list()).toHaveLength(originalCount + 1);
    expect(registry.get("existing-session")?.claudeSessionId).toBe("claude-existing");
    expect(registry.get("existing-session")?.status).toBe("active");
    // Existing configs are preserved; bulkResume should not duplicate or recreate them.
    expect(registry.getConfig("existing-session")?.workingDirectory).toBe("/tmp/existing-before");
    expect(registry.getConfig("new-session")?.workingDirectory).toBe("/tmp/new-session");
  });

  test("resumeSession restores context without emitting synthetic stream output", async () => {
    await manager.createSession("resume-session", makeAgentConfig({ name: "ResumeBot" }));

    await manager.resumeSession("resume-session", "claude-resume");

    expect(registry.get("resume-session")?.claudeSessionId).toBe("claude-resume");
    expect(registry.get("resume-session")?.status).toBe("active");
    expect(events).toEqual([]);
    expect(events.some((event) => event.type === "stream.token")).toBe(false);
    expect(events.some((event) => event.type === "session.result")).toBe(false);
  });

  test("query options after recovery use the restored Claude session ID", async () => {
    await manager.createSession("fresh-session", makeAgentConfig({ name: "FreshBot" }));
    const freshOptions = manager.buildQueryOptionsForTesting("fresh-session");
    expect(freshOptions.resume).toBeUndefined();
    expect(typeof freshOptions.sessionId).toBe("string");

    await manager.bulkResume([
      {
        sessionId: "restored-session",
        claudeSessionId: "claude-restored",
        agentConfig: makeAgentConfig({
          name: "RestoredBot",
          workingDirectory: "/tmp/restored-bot",
        }),
      },
    ]);

    const restoredOptions = manager.buildQueryOptionsForTesting("restored-session");
    expect(restoredOptions.resume).toBe("claude-restored");
    expect(restoredOptions.sessionId).toBeUndefined();
    expect(restoredOptions.cwd).toBe("/tmp/restored-bot");
  });

  test("query options normalize missing auth-related environment variables", async () => {
    await manager.createSession("env-session", makeAgentConfig({ name: "EnvBot" }));

    const originalHome = process.env.HOME;
    const originalUser = process.env.USER;
    const originalLogname = process.env.LOGNAME;
    const originalShell = process.env.SHELL;
    const originalPath = process.env.PATH;
    const originalClaudeCode = process.env.CLAUDECODE;

    process.env.HOME = "";
    process.env.USER = "";
    process.env.LOGNAME = "";
    process.env.SHELL = "";
    process.env.PATH = "";
    process.env.CLAUDECODE = "1";

    try {
      const options = manager.buildQueryOptionsForTesting("env-session");
      expect(options.env.HOME).toBeTruthy();
      expect(options.env.USER).toBeTruthy();
      expect(options.env.USER).not.toBe("unknown");
      expect(options.env.LOGNAME).toBe(options.env.USER);
      expect(options.env.SHELL).toBe("/bin/zsh");
      expect(options.env.PATH).toContain("/usr/bin");
      expect(options.env.CLAUDECODE).toBeUndefined();
    } finally {
      if (originalHome === undefined) delete process.env.HOME;
      else process.env.HOME = originalHome;
      if (originalUser === undefined) delete process.env.USER;
      else process.env.USER = originalUser;
      if (originalLogname === undefined) delete process.env.LOGNAME;
      else process.env.LOGNAME = originalLogname;
      if (originalShell === undefined) delete process.env.SHELL;
      else process.env.SHELL = originalShell;
      if (originalPath === undefined) delete process.env.PATH;
      else process.env.PATH = originalPath;
      if (originalClaudeCode === undefined) delete process.env.CLAUDECODE;
      else process.env.CLAUDECODE = originalClaudeCode;
    }
  });

  test("updateSessionMode changes next-turn runtime config without recreating the session", () => {
    registry.create("mode-session", makeAgentConfig({
      name: "ModeBot",
      provider: "foundation",
      interactive: true,
      instancePolicy: "pool",
      instancePolicyPoolMax: 2,
    }));

    const interactiveOptions = manager.buildQueryOptionsForTesting("mode-session");
    expect(interactiveOptions.toolDefinitionCount).toBeGreaterThan(0);
    expect(registry.getConfig("mode-session")?.interactive).toBe(true);
    expect(registry.getConfig("mode-session")?.instancePolicy).toBe("pool");

    manager.updateSessionMode("mode-session", false, "spawn");

    const autonomousOptions = manager.buildQueryOptionsForTesting("mode-session");
    expect(autonomousOptions.toolDefinitionCount).toBeLessThan(interactiveOptions.toolDefinitionCount);
    expect(registry.getConfig("mode-session")?.interactive).toBe(false);
    expect(registry.getConfig("mode-session")?.instancePolicy).toBe("spawn");
    expect(registry.getConfig("mode-session")?.instancePolicyPoolMax).toBeUndefined();
  });
});
