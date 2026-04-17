/**
 * Unit tests for ConversationEvaluator.
 *
 * Tests routing (coordinator vs all sessions), majority voting,
 * edge cases (no sessions, all-null results, throws), goal injection,
 * and reason aggregation — using an inline mock for SessionManager.evaluateSession.
 */
import { describe, test, expect } from "bun:test";
import { ConversationEvaluator } from "../../src/conversation-evaluator.js";
import type { SidecarEvent } from "../../src/types.js";

function makeEvaluator(
  evalImpl: (
    sessionId: string,
    prompt: string,
  ) => Promise<{ status: "complete" | "needsMore" | "failed"; reason: string } | null>,
) {
  const mockSM = { evaluateSession: evalImpl } as any;
  return new ConversationEvaluator(mockSM);
}

function collector(): { events: SidecarEvent[]; broadcast: (e: SidecarEvent) => void } {
  const events: SidecarEvent[] = [];
  return { events, broadcast: (e) => events.push(e) };
}

// ─── Routing ────────────────────────────────────────────────────────

describe("ConversationEvaluator — routing", () => {
  test("uses only coordinator session when coordinatorSessionId is present", async () => {
    const called: string[] = [];
    const ev = makeEvaluator(async (sid) => { called.push(sid); return { status: "complete", reason: "done" }; });
    const { broadcast } = collector();

    await ev.evaluate(
      { conversationId: "c1", coordinatorSessionId: "coord", sessionIds: ["sess-a", "sess-b"] },
      broadcast,
    );

    expect(called).toEqual(["coord"]);
  });

  test("uses all sessionIds when no coordinatorSessionId", async () => {
    const called: string[] = [];
    const ev = makeEvaluator(async (sid) => { called.push(sid); return { status: "complete", reason: "done" }; });
    const { broadcast } = collector();

    await ev.evaluate({ conversationId: "c2", sessionIds: ["s-a", "s-b"] }, broadcast);

    expect(called.sort()).toEqual(["s-a", "s-b"]);
  });
});

// ─── Event sequence ──────────────────────────────────────────────────

describe("ConversationEvaluator — event sequence", () => {
  test("emits conversation.idle before conversation.idleResult", async () => {
    const ev = makeEvaluator(async () => ({ status: "complete", reason: "goal achieved" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "seq-1", sessionIds: ["s1"] }, broadcast);

    const types = events.map((e) => e.type);
    expect(types[0]).toBe("conversation.idle");
    expect(types[1]).toBe("conversation.idleResult");
  });

  test("idleResult carries correct conversationId, status, and reason", async () => {
    const ev = makeEvaluator(async () => ({ status: "needsMore", reason: "not done yet" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "seq-xyz", sessionIds: ["s1"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.conversationId).toBe("seq-xyz");
    expect(result.status).toBe("needsMore");
    expect(result.reason).toBe("not done yet");
  });
});

// ─── Edge cases ──────────────────────────────────────────────────────

describe("ConversationEvaluator — edge cases", () => {
  test("emits failed idleResult when no sessions provided", async () => {
    const ev = makeEvaluator(async () => ({ status: "complete", reason: "done" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "edge-empty" }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
    expect(result.reason).toMatch(/No sessions/i);
  });

  test("emits failed idleResult when sessionIds is empty array", async () => {
    const ev = makeEvaluator(async () => ({ status: "complete", reason: "done" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "edge-arr", sessionIds: [] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
  });

  test("emits failed idleResult when all sessions return null", async () => {
    const ev = makeEvaluator(async () => null);
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "edge-null", sessionIds: ["s1", "s2"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
    expect(result.reason).toMatch(/could not complete/i);
  });

  test("continues evaluating remaining sessions after one throws", async () => {
    let callCount = 0;
    const ev = makeEvaluator(async (sid) => {
      callCount++;
      if (sid === "bad-session") throw new Error("boom");
      return { status: "complete", reason: "ok" };
    });
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "edge-throw", sessionIds: ["bad-session", "good-session"] }, broadcast);

    expect(callCount).toBe(2);
    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("complete");
  });

  test("still emits conversation.idle even with no sessions", async () => {
    const ev = makeEvaluator(async () => null);
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "edge-idle-always" }, broadcast);

    const types = events.map((e) => e.type);
    expect(types).toContain("conversation.idle");
  });
});

// ─── Majority vote ───────────────────────────────────────────────────

describe("ConversationEvaluator — majority vote", () => {
  test("complete wins 2-vs-1 over needsMore", async () => {
    const statuses = ["complete", "complete", "needsMore"] as const;
    let i = 0;
    const ev = makeEvaluator(async () => ({ status: statuses[i++], reason: "r" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "vote-1", sessionIds: ["s1", "s2", "s3"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("complete");
  });

  test("needsMore wins 2-vs-1 over complete", async () => {
    const statuses = ["needsMore", "needsMore", "complete"] as const;
    let i = 0;
    const ev = makeEvaluator(async () => ({ status: statuses[i++], reason: "r" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "vote-2", sessionIds: ["s1", "s2", "s3"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("needsMore");
  });

  test("failed wins 2-vs-1 over complete", async () => {
    const statuses = ["failed", "failed", "complete"] as const;
    let i = 0;
    const ev = makeEvaluator(async () => ({ status: statuses[i++], reason: "r" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "vote-3", sessionIds: ["s1", "s2", "s3"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
  });

  test("single coordinator result is used directly without majority vote", async () => {
    const ev = makeEvaluator(async () => ({ status: "failed", reason: "single result" }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "vote-single", coordinatorSessionId: "only-sess" }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.status).toBe("failed");
    expect(result.reason).toBe("single result");
  });
});

// ─── Goal injection ───────────────────────────────────────────────────

describe("ConversationEvaluator — goal injection", () => {
  test("includes explicit goal in eval prompt", async () => {
    let capturedPrompt = "";
    const ev = makeEvaluator(async (_, prompt) => {
      capturedPrompt = prompt;
      return { status: "complete", reason: "done" };
    });
    const { broadcast } = collector();

    await ev.evaluate({ conversationId: "g1", sessionIds: ["s1"], goal: "write a working test suite" }, broadcast);

    expect(capturedPrompt).toContain("write a working test suite");
  });

  test("uses default goal phrase when goal is omitted", async () => {
    let capturedPrompt = "";
    const ev = makeEvaluator(async (_, prompt) => {
      capturedPrompt = prompt;
      return { status: "complete", reason: "done" };
    });
    const { broadcast } = collector();

    await ev.evaluate({ conversationId: "g2", sessionIds: ["s1"] }, broadcast);

    expect(capturedPrompt).toContain("based on the conversation above");
  });
});

// ─── Reason aggregation ───────────────────────────────────────────────

describe("ConversationEvaluator — reason aggregation", () => {
  test("joins multi-session reasons with pipe separator", async () => {
    const reasons = ["Objective A met", "Objective B met"];
    let i = 0;
    const ev = makeEvaluator(async () => ({ status: "complete", reason: reasons[i++] }));
    const { events, broadcast } = collector();

    await ev.evaluate({ conversationId: "r1", sessionIds: ["s1", "s2"] }, broadcast);

    const result = events.find((e) => e.type === "conversation.idleResult") as any;
    expect(result.reason).toBe("Objective A met | Objective B met");
  });
});
