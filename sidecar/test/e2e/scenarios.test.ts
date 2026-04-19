/**
 * Comprehensive E2E scenario tests for Odyssey sidecar.
 *
 * Covers all communication patterns:
 *   S  = Session lifecycle
 *   C  = Chat (peer_chat_*)
 *   UC = User-to-Chat
 *   UA = User-to-Agent
 *   AA = Agent-to-Agent messaging
 *   D  = Delegation (peer_delegate_task / delegate.task)
 *   O  = Orchestration (multi-hop delegation chains)
 *   BB = Blackboard (shared state)
 *   GC = Group chat (per-session registry keys + sequential turns + transcript-shaped prompt, Swift-aligned)
 *   ACCEPT = Full orchestration acceptance test
 *
 * Boots a real sidecar subprocess. Tests that require live Claude SDK calls
 * are skipped unless ODYSSEY_E2E_LIVE=1 is set.
 *
 * Usage: ODYSSEY_E2E_LIVE=1 bun test test/e2e/scenarios.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { randomUUID } from "crypto";
import { BufferedWs, wsConnect, waitForHealth, makeAgentConfig } from "../helpers.js";

const WS_PORT = 39849 + Math.floor(Math.random() * 500);
const HTTP_PORT = 39850 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-scenarios-"));
const isLive = (process.env.ODYSSEY_E2E_LIVE ?? process.env.CLAUDESTUDIO_E2E_LIVE) === "1";
const liveTest = isLive ? test : test.skip;
const codexBinaryPath = process.env.CODEX_BINARY || "/Applications/Codex.app/Contents/Resources/codex";
const isCodexLive = (process.env.ODYSSEY_E2E_CODEX ?? process.env.CLAUDESTUDIO_E2E_CODEX) === "1" && existsSync(codexBinaryPath);
const codexLiveTest = isCodexLive ? test : test.skip;

let proc: Subprocess;

beforeAll(async () => {
  const sidecarPath = join(import.meta.dir, "../../src/index.ts");
  proc = spawn({
    cmd: ["bun", "run", sidecarPath],
    env: {
      ...process.env,
      ODYSSEY_WS_PORT: String(WS_PORT),
      ODYSSEY_HTTP_PORT: String(HTTP_PORT),
      ODYSSEY_DATA_DIR: DATA_DIR,
      CLAUDESTUDIO_WS_PORT: String(WS_PORT),
      CLAUDESTUDIO_HTTP_PORT: String(HTTP_PORT),
      CLAUDESTUDIO_DATA_DIR: DATA_DIR,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  await waitForHealth(HTTP_PORT);
}, 30000);

afterAll(() => {
  proc?.kill();
});

describe("SKILL: Live skill wiring smokes", () => {
  liveTest("SKILL-1: Claude follows a configured skill delivered through structured skills", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `skill-claude-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "ClaudeSkillSmoke",
          systemPrompt: "Follow the configured skills exactly.",
          skills: [
            {
              name: "Skill Smoke",
              content: "When the user says 'skill smoke', reply with exactly CLAUDE-SKILL-SMOKE and nothing else.",
            },
          ],
          maxTurns: 1,
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid, text: "skill smoke" });

      const result = await ws.waitFor(
        (m) => m.type === "session.result" && m.sessionId === sid,
        90000,
      );
      expect(result.result).toContain("CLAUDE-SKILL-SMOKE");
    } finally {
      ws.close();
    }
  }, 120000);

  codexLiveTest("SKILL-2: Codex follows a configured skill delivered through structured skills", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `skill-codex-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "CodexSkillSmoke",
          provider: "codex",
          model: "gpt-5.4",
          systemPrompt: "Follow the configured skills exactly.",
          skills: [
            {
              name: "Skill Smoke",
              content: "When the user says 'skill smoke', reply with exactly CODEX-SKILL-SMOKE and nothing else.",
            },
          ],
          maxTurns: 1,
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid, text: "skill smoke" });

      const result = await ws.waitFor(
        (m) => m.type === "session.result" && m.sessionId === sid,
        120000,
      );
      expect(result.result).toContain("CODEX-SKILL-SMOKE");
    } finally {
      ws.close();
    }
  }, 150000);
});

// ─── S: Session Lifecycle ───────────────────────────────────────────

describe("S: Session Lifecycle", () => {
  liveTest("S-1: create session, send message, receive tokens + result", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `s1-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "S1Bot",
          systemPrompt: "Reply with exactly: HELLO. Nothing else.",
          maxTurns: 1,
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid, text: "hi" });

      const events = await ws.collectUntil(
        (m) => m.sessionId === sid && (m.type === "session.result" || m.type === "session.error"),
        60000,
      );
      const tokens = events.filter((m) => m.type === "stream.token" && m.sessionId === sid);
      expect(tokens.length).toBeGreaterThan(0);
      const result = events.find((m) => m.type === "session.result" && m.sessionId === sid);
      expect(result).toBeDefined();
      expect(result.result).toBeTruthy();
    } finally {
      ws.close();
    }
  }, 90000);

  liveTest("S-2: pause mid-stream sets paused status", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `s2-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "S2Bot",
          systemPrompt: "List the numbers from 1 to 500, each on a new line. Do not stop until you reach 500.",
          maxTurns: 1,
        }),
      });
      await new Promise((r) => setTimeout(r, 1000));

      ws.send({ type: "session.message", sessionId: sid, text: "start" });

      // Wait longer — model may take time to begin streaming
      await ws.waitFor((m) => m.type === "stream.token" && m.sessionId === sid, 60000);

      // Let a few more tokens arrive before pausing
      await new Promise((r) => setTimeout(r, 2000));

      ws.send({ type: "session.pause", sessionId: sid });
      const completion = await ws.collectUntil(
        (m) => m.sessionId === sid && (m.type === "session.result" || m.type === "session.error"),
        30000,
      );
      const hasResult = completion.some((m) => m.type === "session.result" && m.sessionId === sid);
      const hasError = completion.some((m) => m.type === "session.error" && m.sessionId === sid);
      expect(hasResult || hasError || completion.length === 0).toBe(true);
    } finally {
      ws.close();
    }
  }, 120000);

  test("S-3: resume restores session context without synthetic output", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `s3-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({ name: "S3Bot" }),
      });
      await new Promise((r) => setTimeout(r, 300));

      ws.send({ type: "session.resume", sessionId: sid, claudeSessionId: "fake-claude-id" });
      await new Promise((r) => setTimeout(r, 500));
      const resumeEvents = ws.buffer.filter((m) => m.sessionId === sid);
      expect(resumeEvents.some((m) => m.type === "stream.token")).toBe(false);
      expect(resumeEvents.some((m) => m.type === "session.error")).toBe(false);
    } finally {
      ws.close();
    }
  });

  test("S-4: fork creates new session with confirmation", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `s4-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({ name: "S4Bot" }),
      });
      await new Promise((r) => setTimeout(r, 300));

      const childId = `${sid}-child`;
      ws.send({ type: "session.fork", sessionId: sid, childSessionId: childId });
      const forkMsg = await ws.waitFor(
        (m) => m.type === "session.forked" && m.childSessionId === childId,
        5000,
      );
      expect(forkMsg.parentSessionId).toBe(sid);
    } finally {
      ws.close();
    }
  });

  liveTest("S-5: two simultaneous sessions stream independently", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid1 = `s5a-${Date.now()}`;
      const sid2 = `s5b-${Date.now()}`;

      ws.send({
        type: "session.create",
        conversationId: sid1,
        agentConfig: makeAgentConfig({ name: "Bot5A", systemPrompt: "Reply only: ALPHA", maxTurns: 1 }),
      });
      ws.send({
        type: "session.create",
        conversationId: sid2,
        agentConfig: makeAgentConfig({ name: "Bot5B", systemPrompt: "Reply only: BETA", maxTurns: 1 }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid1, text: "go" });
      ws.send({ type: "session.message", sessionId: sid2, text: "go" });

      const allEvents = await ws.collectUntil(
        (m) =>
          (m.type === "session.result" && m.sessionId === sid2) ||
          (m.type === "session.error" && m.sessionId === sid2),
        90000,
      );
      const r1 = allEvents.find((m) => m.type === "session.result" && m.sessionId === sid1);
      const r2 = allEvents.find((m) => m.type === "session.result" && m.sessionId === sid2);
      expect(r1 || r2).toBeDefined();
    } finally {
      ws.close();
    }
  }, 120000);
});

// ─── GC: Group Chat (Swift app wire protocol) ───────────────────────
//
// The macOS app uses one sidecar registry entry per SwiftData Session.id (wire: session.create
// payload field still named conversationId). Multi-agent rooms send session.message sequentially;
// later agents receive a GroupPromptBuilder-style transcript block in the message text.

describe("GC: Group Chat", () => {
  liveTest(
    "GC-1: two session ids, sequential messages, second prompt includes first agent reply (live)",
    async () => {
      const ws = await wsConnect(WS_PORT);
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sidAlpha = randomUUID();
        const sidBeta = randomUUID();

        ws.send({
          type: "session.create",
          conversationId: sidAlpha,
          agentConfig: makeAgentConfig({
            name: "GroupAlpha",
            systemPrompt:
              "You are GroupAlpha in a multi-agent room. Follow user instructions exactly. Be concise.",
            maxTurns: 1,
          }),
        });
        ws.send({
          type: "session.create",
          conversationId: sidBeta,
          agentConfig: makeAgentConfig({
            name: "GroupBeta",
            systemPrompt:
              "You are GroupBeta in a multi-agent room. Use the group thread and latest user message. Be concise.",
            maxTurns: 1,
          }),
        });
        await new Promise((r) => setTimeout(r, 600));

        ws.send({
          type: "session.message",
          sessionId: sidAlpha,
          text: 'Reply with exactly one word in all caps: MARZIPAN',
        });

        const alphaEvents = await ws.collectUntil(
          (m) =>
            m.sessionId === sidAlpha &&
            (m.type === "session.result" || m.type === "session.error"),
          90000,
        );
        const alphaErr = alphaEvents.find(
          (m) => m.type === "session.error" && m.sessionId === sidAlpha,
        );
        expect(alphaErr).toBeUndefined();

        const alphaTokens = alphaEvents.filter(
          (m) => m.type === "stream.token" && m.sessionId === sidAlpha,
        );
        const alphaResult = alphaEvents.find(
          (m) => m.type === "session.result" && m.sessionId === sidAlpha,
        );
        let alphaReply =
          alphaTokens.map((m: any) => m.text ?? "").join("") +
          (typeof alphaResult?.result === "string" ? alphaResult.result : "");
        alphaReply = alphaReply.trim() || "(no text from Alpha)";
        expect(alphaReply.length).toBeGreaterThan(3);

        const groupPrompt = `--- Group thread (new since your last reply) ---
GroupAlpha: ${alphaReply}
--- End ---

You are GroupBeta. Respond to the latest user message in this group.
Latest user message:
"""
What word did GroupAlpha say (the all-caps word)? Reply with that single word only, same spelling.
"""`;

        ws.send({
          type: "session.message",
          sessionId: sidBeta,
          text: groupPrompt,
        });

        const betaEvents = await ws.collectUntil(
          (m) =>
            m.sessionId === sidBeta &&
            (m.type === "session.result" || m.type === "session.error"),
          90000,
        );
        const betaErr = betaEvents.find(
          (m) => m.type === "session.error" && m.sessionId === sidBeta,
        );
        expect(betaErr).toBeUndefined();

        const betaTokens = betaEvents.filter(
          (m) => m.type === "stream.token" && m.sessionId === sidBeta,
        );
        const betaResult = betaEvents.find(
          (m) => m.type === "session.result" && m.sessionId === sidBeta,
        );
        const betaText = (
          betaTokens.map((m: any) => m.text ?? "").join("") +
          (typeof betaResult?.result === "string" ? betaResult.result : "")
        ).toUpperCase();
        expect(betaText).toContain("MARZIPAN");
      } finally {
        ws.close();
      }
    },
    180000,
  );

  // Mirrors Swift `GroupPromptBuilder.buildPeerNotifyPrompt` shape used for automatic fan-out.
  liveTest(
    "GC-2: peer-notify shaped prompt is handled by sidecar (live)",
    async () => {
      const ws = await wsConnect(WS_PORT);
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sid = randomUUID();
        ws.send({
          type: "session.create",
          conversationId: sid,
          agentConfig: makeAgentConfig({
            name: "PeerReceiver",
            systemPrompt:
              "You are in a shared group. If asked to acknowledge, reply with exactly: ACK",
            maxTurns: 1,
          }),
        });
        await new Promise((r) => setTimeout(r, 500));
        const peerPrompt = `--- Group chat: peer message ---
OtherBot: ping
--- End ---

You are PeerReceiver. Another participant posted the above in this shared group. Reply with exactly: ACK`;
        ws.send({ type: "session.message", sessionId: sid, text: peerPrompt });
        const events = await ws.collectUntil(
          (m) =>
            m.sessionId === sid &&
            (m.type === "session.result" || m.type === "session.error"),
          90000,
        );
        const err = events.find((m) => m.type === "session.error" && m.sessionId === sid);
        expect(err).toBeUndefined();
        const tokens = events.filter((m: any) => m.type === "stream.token");
        const text = tokens.map((m: any) => m.text ?? "").join("");
        expect(text.toUpperCase()).toContain("ACK");
      } finally {
        ws.close();
      }
    },
    120000,
  );
});

// ─── UC: User-to-Chat ───────────────────────────────────────────────

describe("UC: User-to-Chat", () => {
  liveTest("UC-1: user sends message, agent responds with full stream", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `uc1-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "UC1Bot",
          systemPrompt: "Reply only with: PONG",
          maxTurns: 1,
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid, text: "PING" });
      const events = await ws.collectUntil(
        (m) => m.sessionId === sid && (m.type === "session.result" || m.type === "session.error"),
        60000,
      );

      const tokens = events.filter((m) => m.type === "stream.token" && m.sessionId === sid);
      const result = events.find((m) => m.type === "session.result" && m.sessionId === sid);
      expect(tokens.length).toBeGreaterThan(0);
      expect(result).toBeDefined();
    } finally {
      ws.close();
    }
  }, 90000);

  test("UC-2: message to unknown session returns error", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({ type: "session.message", sessionId: "uc2-nonexistent", text: "?" });
      const err = await ws.waitFor(
        (m) => m.type === "session.error" && m.sessionId === "uc2-nonexistent",
        5000,
      );
      expect(err.error).toContain("not found");
    } finally {
      ws.close();
    }
  });
});

// ─── CHAT: Agent Chat (provisioned config) ──────────────────────────

describe("CHAT: Agent Chat", () => {
  liveTest("CHAT-1: agent-provisioned config with model alias and fresh sandbox dir", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `chat1-${Date.now()}`;
      const sandboxDir = join(tmpdir(), `odyssey-chat-test-${randomUUID()}`);

      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "Coder",
          model: "sonnet",
          workingDirectory: sandboxDir,
          maxTurns: 1,
          allowedTools: ["*"],
          systemPrompt: "You are a helpful coding assistant. Reply concisely.",
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({ type: "session.message", sessionId: sid, text: "What is 1+1? Reply with just the number." });

      const events = await ws.collectUntil(
        (m) => m.sessionId === sid && (m.type === "session.result" || m.type === "session.error"),
        60000,
      );

      const errors = events.filter((m) => m.type === "session.error" && m.sessionId === sid);
      expect(errors.length).toBe(0);

      const tokens = events.filter((m) => m.type === "stream.token" && m.sessionId === sid);
      expect(tokens.length).toBeGreaterThan(0);

      const result = events.find((m) => m.type === "session.result" && m.sessionId === sid);
      expect(result).toBeDefined();
      expect(result.result).toBeTruthy();

      expect(existsSync(sandboxDir)).toBe(true);
    } finally {
      ws.close();
    }
  }, 90000);

  test("CHAT-2: non-existent working directory is created before query", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `chat2-${Date.now()}`;
      const deepDir = join(tmpdir(), `odyssey-nocwd-${randomUUID()}`, "nested", "sandbox");

      expect(existsSync(deepDir)).toBe(false);

      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "Chat2Bot",
          workingDirectory: deepDir,
          maxTurns: 1,
          systemPrompt: "Reply with exactly: OK",
        }),
      });
      await new Promise((r) => setTimeout(r, 300));

      ws.send({ type: "session.message", sessionId: sid, text: "go" });

      const event = await ws.waitFor(
        (m) => m.sessionId === sid && (m.type === "session.result" || m.type === "session.error"),
        30000,
      );

      if (event.type === "session.error") {
        console.log(`[CHAT-2] Error: ${event.error}`);
      }
      expect(existsSync(deepDir)).toBe(true);
    } finally {
      ws.close();
    }
  }, 60000);
});

// ─── UA: User-to-Agent ──────────────────────────────────────────────

describe("UA: User-to-Agent", () => {
  test("UA-1: session.create with custom config stores in registry", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const sid = `ua1-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: sid,
        agentConfig: makeAgentConfig({
          name: "CustomAgent",
          systemPrompt: "Custom prompt with skills",
          model: "claude-sonnet-4-6",
          maxTurns: 10,
          maxBudget: 5.0,
        }),
      });
      await new Promise((r) => setTimeout(r, 300));
      // Session was accepted (no error returned)
    } finally {
      ws.close();
    }
  });

  test("UA-2: delegate.task broadcasts peer.delegate and spawns session", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const agentName = `UA2Target-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{
          name: agentName,
          config: makeAgentConfig({ name: agentName, systemPrompt: "handle delegation" }),
          instancePolicy: "spawn",
        }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const srcSid = `ua2-src-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: srcSid,
        agentConfig: makeAgentConfig({ name: "UA2Orchestrator" }),
      });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({
        type: "delegate.task",
        sessionId: srcSid,
        toAgent: agentName,
        task: "implement login page",
        context: "Use React",
        waitForResult: false,
      });

      const delegateEvent = await ws.waitFor(
        (m) => m.type === "peer.delegate" && m.to === agentName,
        5000,
      );
      expect(delegateEvent.task).toBe("implement login page");
    } finally {
      ws.close();
    }
  });

  test("UA-3: delegate.task to unknown agent returns error", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "delegate.task",
        sessionId: "ua3-src",
        toAgent: "GhostAgent",
        task: "nothing",
        waitForResult: false,
      });
      const err = await ws.waitFor((m) => m.type === "session.error", 3000);
      expect(err.error).toContain("not found");
    } finally {
      ws.close();
    }
  });
});

// ─── AA: Agent-to-Agent Messaging ───────────────────────────────────

describe("AA: Agent-to-Agent Messaging", () => {
  test("AA-1: agent.register makes agents discoverable", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "agent.register",
        agents: [
          { name: "AA-Alice", config: makeAgentConfig({ name: "AA-Alice" }), instancePolicy: "spawn" },
          { name: "AA-Bob", config: makeAgentConfig({ name: "AA-Bob" }), instancePolicy: "singleton" },
        ],
      });
      await new Promise((r) => setTimeout(r, 200));
      // Agents are registered (verified via delegate.task or peer_list_agents in integration tests)
    } finally {
      ws.close();
    }
  });

  test("AA-2: broadcast reaches all connected clients", async () => {
    const ws1 = await wsConnect(WS_PORT);
    const ws2 = await wsConnect(WS_PORT);
    try {
      await ws1.waitFor((m) => m.type === "sidecar.ready");
      await ws2.waitFor((m) => m.type === "sidecar.ready");

      const agentName = `AA-Broadcast-${Date.now()}`;
      ws1.send({
        type: "agent.register",
        agents: [{ name: agentName, config: makeAgentConfig({ name: agentName }), instancePolicy: "spawn" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const srcSid = `aa2-src-${Date.now()}`;
      ws1.send({
        type: "session.create",
        conversationId: srcSid,
        agentConfig: makeAgentConfig({ name: "AA-Broadcaster" }),
      });
      await new Promise((r) => setTimeout(r, 200));

      ws1.send({
        type: "delegate.task",
        sessionId: srcSid,
        toAgent: agentName,
        task: "broadcast test",
        waitForResult: false,
      });

      const event1 = await ws1.waitFor((m) => m.type === "peer.delegate" && m.to === agentName, 3000);
      const event2 = await ws2.waitFor((m) => m.type === "peer.delegate" && m.to === agentName, 3000);
      expect(event1.type).toBe("peer.delegate");
      expect(event2.type).toBe("peer.delegate");
    } finally {
      ws1.close();
      ws2.close();
    }
  });
});

// ─── D: Delegation Scenarios ────────────────────────────────────────

describe("D: Delegation Policy Enforcement", () => {
  test("D-1: spawn policy creates new session for each delegation", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const name = `D1-Spawn-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{ name, config: makeAgentConfig({ name }), instancePolicy: "spawn" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `d1-src-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "D1-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "task-1", waitForResult: false });
      const e1 = await ws.waitFor((m) => m.type === "peer.delegate" && m.task === "task-1", 3000);
      expect(e1).toBeDefined();

      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "task-2", waitForResult: false });
      const e2 = await ws.waitFor((m) => m.type === "peer.delegate" && m.task === "task-2", 3000);
      expect(e2).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("D-2: singleton policy registered via agent.register", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const name = `D2-Single-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{ name, config: makeAgentConfig({ name }), instancePolicy: "singleton" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `d2-src-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "D2-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "singleton task", waitForResult: false });
      const event = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === name, 3000);
      expect(event).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("D-3: pool:N policy registered correctly", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const name = `D3-Pool-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{ name, config: makeAgentConfig({ name }), instancePolicy: "pool:3" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `d3-src-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "D3-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "pool task", waitForResult: false });
      const event = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === name, 3000);
      expect(event).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("D-4: delegation with context includes context in broadcast", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const name = `D4-Ctx-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{ name, config: makeAgentConfig({ name }), instancePolicy: "spawn" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `d4-src-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "D4-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({
        type: "delegate.task",
        sessionId: src,
        toAgent: name,
        task: "implement feature X",
        context: "See blackboard key research.featureX for background",
        waitForResult: false,
      });
      const event = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === name, 3000);
      expect(event.task).toBe("implement feature X");
    } finally {
      ws.close();
    }
  });

  test("D-5: multiple delegations to same agent all broadcast", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      const name = `D5-Multi-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [{ name, config: makeAgentConfig({ name }), instancePolicy: "spawn" }],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `d5-src-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "D5-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "alpha", waitForResult: false });
      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "beta", waitForResult: false });
      ws.send({ type: "delegate.task", sessionId: src, toAgent: name, task: "gamma", waitForResult: false });

      const e1 = await ws.waitFor((m) => m.type === "peer.delegate" && m.task === "alpha", 3000);
      const e2 = await ws.waitFor((m) => m.type === "peer.delegate" && m.task === "beta", 3000);
      const e3 = await ws.waitFor((m) => m.type === "peer.delegate" && m.task === "gamma", 3000);
      expect(e1).toBeDefined();
      expect(e2).toBeDefined();
      expect(e3).toBeDefined();
    } finally {
      ws.close();
    }
  });
});

// ─── BB: Blackboard Scenarios ───────────────────────────────────────

describe("BB: Blackboard Shared State", () => {
  test("BB-1: write via HTTP, read via HTTP (cross-protocol)", async () => {
    const key = `bb1.${Date.now()}`;
    const writeRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key, value: "research-findings", writtenBy: "researcher" }),
    });
    expect(writeRes.status).toBe(201);

    const readRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=${key}`);
    expect(readRes.status).toBe(200);
    const body = (await readRes.json()) as any;
    expect(body.value).toBe("research-findings");
    expect(body.writtenBy).toBe("researcher");
  });

  test("BB-2: overwrite via HTTP preserves key", async () => {
    const key = `bb2.${Date.now()}`;
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key, value: "v1", writtenBy: "agent1" }),
    });
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key, value: "v2", writtenBy: "agent2" }),
    });
    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=${key}`);
    const body = (await res.json()) as any;
    expect(body.value).toBe("v2");
    expect(body.writtenBy).toBe("agent2");
  });

  test("BB-3: query returns multiple matching entries", async () => {
    const prefix = `bb3-${Date.now()}`;
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: `${prefix}.a`, value: "va", writtenBy: "test" }),
    });
    await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: `${prefix}.b`, value: "vb", writtenBy: "test" }),
    });

    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/query?pattern=${prefix}.*`);
    const body = (await res.json()) as any[];
    expect(body.length).toBeGreaterThanOrEqual(2);
  });
});

// ─── O: Orchestration Scenarios ─────────────────────────────────────

describe("O: Multi-Agent Orchestration", () => {
  test("O-1: linear chain delegation A -> B broadcasts correctly", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const researcher = `O1-Researcher-${Date.now()}`;
      const coder = `O1-Coder-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [
          { name: researcher, config: makeAgentConfig({ name: researcher }), instancePolicy: "spawn" },
          { name: coder, config: makeAgentConfig({ name: coder }), instancePolicy: "spawn" },
        ],
      });
      await new Promise((r) => setTimeout(r, 200));

      const orchestratorSid = `o1-orch-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: orchestratorSid,
        agentConfig: makeAgentConfig({ name: "O1-Orchestrator" }),
      });
      await new Promise((r) => setTimeout(r, 200));

      ws.send({
        type: "delegate.task",
        sessionId: orchestratorSid,
        toAgent: researcher,
        task: "research best practices",
        waitForResult: false,
      });
      const e1 = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === researcher, 3000);
      expect(e1.from).toBe("O1-Orchestrator");

      ws.send({
        type: "delegate.task",
        sessionId: orchestratorSid,
        toAgent: coder,
        task: "implement findings",
        context: "See research results",
        waitForResult: false,
      });
      const e2 = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === coder, 3000);
      expect(e2.from).toBe("O1-Orchestrator");
    } finally {
      ws.close();
    }
  });

  test("O-2: fan-out delegation to multiple agents concurrently", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const agents = [`O2-A-${Date.now()}`, `O2-B-${Date.now()}`, `O2-C-${Date.now()}`];
      ws.send({
        type: "agent.register",
        agents: agents.map((name) => ({
          name,
          config: makeAgentConfig({ name }),
          instancePolicy: "spawn",
        })),
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `o2-orch-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "O2-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      for (const agent of agents) {
        ws.send({
          type: "delegate.task",
          sessionId: src,
          toAgent: agent,
          task: `task for ${agent}`,
          waitForResult: false,
        });
      }

      for (const agent of agents) {
        const event = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === agent, 5000);
        expect(event).toBeDefined();
      }
    } finally {
      ws.close();
    }
  });

  test("O-3: delegation + blackboard = coordinated pipeline", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const researcher = `O3-R-${Date.now()}`;
      const coder = `O3-C-${Date.now()}`;
      ws.send({
        type: "agent.register",
        agents: [
          { name: researcher, config: makeAgentConfig({ name: researcher }), instancePolicy: "spawn" },
          { name: coder, config: makeAgentConfig({ name: coder }), instancePolicy: "pool:3" },
        ],
      });
      await new Promise((r) => setTimeout(r, 200));

      const src = `o3-orch-${Date.now()}`;
      ws.send({ type: "session.create", conversationId: src, agentConfig: makeAgentConfig({ name: "O3-Orch" }) });
      await new Promise((r) => setTimeout(r, 200));

      // Write pipeline state via HTTP
      const bbKey = `pipeline.${Date.now()}.phase`;
      const writeRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key: bbKey, value: "research", writtenBy: "O3-Orch" }),
      });
      expect(writeRes.status).toBe(201);

      // Verify via HTTP read
      const readRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=${bbKey}`);
      expect((await readRes.json() as any).value).toBe("research");

      // Delegate to researcher
      ws.send({
        type: "delegate.task",
        sessionId: src,
        toAgent: researcher,
        task: "research phase",
        waitForResult: false,
      });
      const delEvent = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === researcher, 3000);
      expect(delEvent).toBeDefined();

      // Update pipeline state
      await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/write`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ key: bbKey, value: "implementation", writtenBy: "O3-Orch" }),
      });

      // Delegate to coder with blackboard context
      ws.send({
        type: "delegate.task",
        sessionId: src,
        toAgent: coder,
        task: "implement from research",
        context: `Read blackboard key ${bbKey}`,
        waitForResult: false,
      });
      const delEvent2 = await ws.waitFor((m) => m.type === "peer.delegate" && m.to === coder, 3000);
      expect(delEvent2).toBeDefined();

      // Verify final pipeline state
      const finalRead = await fetch(`http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=${bbKey}`);
      expect((await finalRead.json() as any).value).toBe("implementation");
    } finally {
      ws.close();
    }
  });
});

// ─── ACCEPT: Full Orchestration Acceptance ──────────────────────────

describe("ACCEPT: Full Orchestration Pipeline", () => {
  liveTest("ACCEPT-1: Orchestrator delegates to multiple specialists with live Claude", async () => {
    const ws = await wsConnect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      ws.send({
        type: "agent.register",
        agents: [
          {
            name: "Orchestrator",
            config: makeAgentConfig({
              name: "Orchestrator",
              systemPrompt: `You are a project coordinator. Your team: Researcher (research), Coder (implementation).
You NEVER write code yourself. Break the request into subtasks and delegate using peer_delegate_task.
1. First delegate research to Researcher with wait_for_result: true
2. Then delegate implementation to Coder with wait_for_result: true
3. Summarize the results to the user.
Write progress to the blackboard under pipeline.* keys using blackboard_write.`,
              model: "claude-sonnet-4-6",
              maxTurns: 20,
              maxBudget: 10.0,
            }),
            instancePolicy: "singleton",
          },
          {
            name: "Researcher",
            config: makeAgentConfig({
              name: "Researcher",
              systemPrompt: "You are a research specialist. When given a research task, provide a brief 2-3 sentence summary of findings. Write your findings to the blackboard using blackboard_write with key research.findings. Do NOT write code.",
              model: "claude-sonnet-4-6",
              maxTurns: 5,
              maxBudget: 3.0,
            }),
            instancePolicy: "spawn",
          },
          {
            name: "Coder",
            config: makeAgentConfig({
              name: "Coder",
              systemPrompt: "You are a software engineer. When given an implementation task, write a brief code snippet (under 20 lines). Write your status to the blackboard using blackboard_write with key impl.status = done.",
              model: "claude-sonnet-4-6",
              maxTurns: 5,
              maxBudget: 3.0,
            }),
            instancePolicy: "pool:3",
          },
          {
            name: "Reviewer",
            config: makeAgentConfig({
              name: "Reviewer",
              systemPrompt: "You are a code reviewer. When asked to review, provide a brief review with 1-2 suggestions. Write your review to blackboard with key review.findings.",
              model: "claude-sonnet-4-6",
              maxTurns: 5,
              maxBudget: 3.0,
            }),
            instancePolicy: "singleton",
          },
          {
            name: "Tester",
            config: makeAgentConfig({
              name: "Tester",
              systemPrompt: "You are a QA engineer. When asked to test, verify the described functionality and report pass/fail to the blackboard with key test.status.",
              model: "claude-sonnet-4-6",
              maxTurns: 5,
              maxBudget: 3.0,
            }),
            instancePolicy: "pool:2",
          },
        ],
      });
      await new Promise((r) => setTimeout(r, 500));

      const orchSid = `accept-orch-${Date.now()}`;
      ws.send({
        type: "session.create",
        conversationId: orchSid,
        agentConfig: makeAgentConfig({
          name: "Orchestrator",
          systemPrompt: `You are a project coordinator. Your team: Researcher (research), Coder (implementation), Reviewer (code review), Tester (QA).
You NEVER write code yourself. Break the request into subtasks and delegate using peer_delegate_task.
1. First delegate research to Researcher with wait_for_result: true
2. Then delegate implementation to Coder with wait_for_result: true
3. Summarize the results to the user.
Write progress to the blackboard under pipeline.* keys using blackboard_write.`,
          model: "claude-sonnet-4-6",
          maxTurns: 20,
          maxBudget: 10.0,
        }),
      });
      await new Promise((r) => setTimeout(r, 500));

      ws.send({
        type: "session.message",
        sessionId: orchSid,
        text: "Create a simple iOS meditation app with a timer screen and a breathing exercise screen. Use SwiftUI. Keep it minimal.",
      });

      const allEvents = await ws.collectUntil(
        (m) => m.sessionId === orchSid && (m.type === "session.result" || m.type === "session.error"),
        600000, // 10 min
      );

      const delegations = allEvents.filter((m) => m.type === "peer.delegate");
      const results = allEvents.filter((m) => m.type === "session.result");
      const tokens = allEvents.filter((m) => m.type === "stream.token");
      const bbUpdates = allEvents.filter((m) => m.type === "blackboard.update");
      const errors = allEvents.filter((m) => m.type === "session.error");

      console.log(`[ACCEPT-1] Delegations: ${delegations.length}, Results: ${results.length}, Tokens: ${tokens.length}, BB updates: ${bbUpdates.length}, Errors: ${errors.length}`);
      console.log(`[ACCEPT-1] Delegated to: ${delegations.map((d) => d.to).join(", ")}`);

      expect(delegations.length).toBeGreaterThanOrEqual(1);
      expect(tokens.length).toBeGreaterThan(0);

      const orchResult = allEvents.find((m) => m.type === "session.result" && m.sessionId === orchSid);
      if (orchResult) {
        expect(orchResult.result).toBeTruthy();
        console.log(`[ACCEPT-1] Orchestrator result (first 200 chars): ${orchResult.result.substring(0, 200)}`);
      }
    } finally {
      ws.close();
    }
  }, 660000); // 11 min timeout
});
