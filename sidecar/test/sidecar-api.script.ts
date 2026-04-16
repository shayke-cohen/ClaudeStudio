/**
 * Odyssey Sidecar API Tests
 *
 * Tests all WebSocket and HTTP APIs:
 * - session.create / session.message / session.resume / session.fork / session.pause
 * - Blackboard HTTP API (write, read, query, keys)
 * - Streaming events (stream.token, stream.toolCall, stream.toolResult, session.result, session.error)
 *
 * Usage: ODYSSEY_WS_PORT=9849 ODYSSEY_HTTP_PORT=9850 bun run test/sidecar-api.script.ts
 * Requires: sidecar listening on the same ports (defaults 9849 WS / 9850 HTTP).
 *
 * Note: this is a manual smoke script, NOT a bun:test suite. The .script.ts
 * extension keeps it out of `bun test` auto-discovery. Use scripts/run-all-tests.sh
 * for the canonical run with proper port allocation.
 */

const WS_PORT = Number(process.env.ODYSSEY_WS_PORT ?? process.env.CLAUDESTUDIO_WS_PORT ?? "9849");
const HTTP_PORT = Number(process.env.ODYSSEY_HTTP_PORT ?? process.env.CLAUDESTUDIO_HTTP_PORT ?? "9850");
const HTTP_BASE = `http://127.0.0.1:${HTTP_PORT}`;

interface TestResult {
  name: string;
  passed: boolean;
  duration: number;
  error?: string;
}

const results: TestResult[] = [];

// --- Helpers ---

function wsConnect(): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${WS_PORT}`);
    ws.onopen = () => resolve(ws);
    ws.onerror = (e: any) => reject(new Error(`WS connect failed: ${e.message ?? "unknown"}`));
    const timeout = setTimeout(() => reject(new Error("WS connect timeout")), 5000);
    ws.onopen = () => { clearTimeout(timeout); resolve(ws); };
  });
}

function wsSend(ws: WebSocket, msg: any): void {
  ws.send(JSON.stringify(msg));
}

function wsCollectUntil(
  ws: WebSocket,
  predicate: (msg: any) => boolean,
  timeoutMs: number = 30000,
): Promise<any[]> {
  return new Promise((resolve, reject) => {
    const msgs: any[] = [];
    const timer = setTimeout(() => {
      resolve(msgs); // resolve with what we have on timeout
    }, timeoutMs);

    ws.onmessage = (event: MessageEvent) => {
      const msg = JSON.parse(typeof event.data === "string" ? event.data : "{}");
      msgs.push(msg);
      if (predicate(msg)) {
        clearTimeout(timer);
        resolve(msgs);
      }
    };
  });
}

async function runTest(name: string, fn: () => Promise<void>): Promise<void> {
  const start = Date.now();
  try {
    await fn();
    results.push({ name, passed: true, duration: Date.now() - start });
    console.log(`  ✓ ${name} (${Date.now() - start}ms)`);
  } catch (err: any) {
    results.push({ name, passed: false, duration: Date.now() - start, error: err.message });
    console.log(`  ✗ ${name} (${Date.now() - start}ms) — ${err.message}`);
  }
}

function assert(condition: boolean, msg: string): void {
  if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

// --- Tests ---

async function testHealthEndpoint() {
  const res = await fetch(`${HTTP_BASE}/health`);
  assert(res.ok, "health should return 200");
  const body = await res.json() as any;
  assert(body.status === "ok", "status should be 'ok'");
  assert(typeof body.version === "string", "version should be a string");
}

async function testSessionCreateAndMessage() {
  const ws = await wsConnect();
  try {
    // Skip sidecar.ready event
    const readyPromise = wsCollectUntil(ws, (m) => m.type === "sidecar.ready", 3000);
    await readyPromise;

    // Create session
    wsSend(ws, {
      type: "session.create",
      conversationId: "test-create-msg",
      agentConfig: {
        name: "TestBot",
        systemPrompt: "You are a test bot. Reply only with the exact text: PONG",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        maxTurns: 1,
        workingDirectory: "/tmp",
        skills: [],
      },
    });

    // createSession only registers state; streaming starts on session.message.

    // Send a message
    wsSend(ws, {
      type: "session.message",
      sessionId: "test-create-msg",
      text: "PING",
    });

    // Collect until session.result or session.error
    const msgResults = await wsCollectUntil(ws, (m) =>
      m.sessionId === "test-create-msg" &&
      (m.type === "session.result" || m.type === "session.error"), 45000);

    const resultMsg = msgResults.find((m: any) => m.type === "session.result");
    const errorMsg = msgResults.find((m: any) => m.type === "session.error");
    assert(!errorMsg, `should not error: ${errorMsg?.error ?? ""}`);
    assert(!!resultMsg, "should receive session.result");

    // Check that we got streaming tokens
    const tokens = msgResults.filter((m: any) => m.type === "stream.token" && m.sessionId === "test-create-msg");
    assert(tokens.length > 0, "should receive at least one stream.token");
  } finally {
    ws.close();
  }
}

async function testSessionMessageToUnknownSession() {
  const ws = await wsConnect();
  try {
    await wsCollectUntil(ws, (m) => m.type === "sidecar.ready", 3000);

    wsSend(ws, {
      type: "session.message",
      sessionId: "nonexistent-session",
      text: "hello",
    });

    const msgs = await wsCollectUntil(ws, (m) => m.type === "session.error", 5000);
    const err = msgs.find((m: any) => m.type === "session.error");
    assert(!!err, "should receive session.error for unknown session");
    assert(err.error.includes("not found"), "error should mention 'not found'");
  } finally {
    ws.close();
  }
}

async function testSessionPause() {
  const ws = await wsConnect();
  try {
    await wsCollectUntil(ws, (m) => m.type === "sidecar.ready", 3000);

    wsSend(ws, {
      type: "session.create",
      conversationId: "test-pause",
      agentConfig: {
        name: "PauseBot",
        systemPrompt:
          "List the numbers from 1 to 500, each on a new line. Do not stop until you reach 500.",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        maxTurns: 1,
        workingDirectory: "/tmp",
        skills: [],
      },
    });

    wsSend(ws, {
      type: "session.message",
      sessionId: "test-pause",
      text: "start",
    });

    const started = await wsCollectUntil(
      ws,
      (m) => m.type === "stream.token" && m.sessionId === "test-pause",
      60000,
    );
    assert(started.length > 0, "should see stream tokens before pause");

    await new Promise((r) => setTimeout(r, 2000));

    wsSend(ws, {
      type: "session.pause",
      sessionId: "test-pause",
    });

    // After abort, SessionManager may emit nothing (matches e2e S-2).
    const after = await wsCollectUntil(
      ws,
      (m) =>
        m.sessionId === "test-pause" &&
        (m.type === "session.result" || m.type === "session.error"),
      8000,
    );
    const hasDone = after.some(
      (m: any) => m.type === "session.result" || m.type === "session.error",
    );
    assert(hasDone || after.length === 0, "pause should complete (optional result/error after abort)");
  } finally {
    ws.close();
  }
}

async function testSessionFork() {
  const ws = await wsConnect();
  try {
    await wsCollectUntil(ws, (m) => m.type === "sidecar.ready", 3000);

    wsSend(ws, {
      type: "session.create",
      conversationId: "test-fork-parent",
      agentConfig: {
        name: "ForkBot",
        systemPrompt: "Reply briefly.",
        allowedTools: [],
        mcpServers: [],
        model: "claude-sonnet-4-6",
        maxTurns: 1,
        workingDirectory: "/tmp",
        skills: [],
      },
    });

    wsSend(ws, {
      type: "session.fork",
      sessionId: "test-fork-parent",
      childSessionId: "test-fork-child",
    });

    const forkMsgs = await wsCollectUntil(ws, (m) =>
      m.type === "session.forked" && m.childSessionId === "test-fork-child", 5000);
    assert(forkMsgs.length > 0, "should receive session.forked");
  } finally {
    ws.close();
  }
}

async function testBlackboardWrite() {
  const res = await fetch(`${HTTP_BASE}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key: "test.key1", value: "hello world", writtenBy: "test-suite" }),
  });
  assert(res.status === 201, `write should return 201, got ${res.status}`);
  const body = await res.json() as any;
  assert(body.key === "test.key1", "key should match");
  assert(body.value === "hello world", "value should match");
  assert(body.writtenBy === "test-suite", "writtenBy should match");
}

async function testBlackboardRead() {
  // Write first
  await fetch(`${HTTP_BASE}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key: "test.read1", value: '{"num":42}', writtenBy: "test" }),
  });

  const res = await fetch(`${HTTP_BASE}/blackboard/read?key=test.read1`);
  assert(res.ok, "read should return 200");
  const body = await res.json() as any;
  assert(body.key === "test.read1", "key should match");
  assert(body.value === '{"num":42}', "value should match");
}

async function testBlackboardReadNotFound() {
  const res = await fetch(`${HTTP_BASE}/blackboard/read?key=does.not.exist`);
  assert(res.status === 404, "should return 404 for missing key");
}

async function testBlackboardQuery() {
  await fetch(`${HTTP_BASE}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key: "query.alpha", value: "a", writtenBy: "test" }),
  });
  await fetch(`${HTTP_BASE}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key: "query.beta", value: "b", writtenBy: "test" }),
  });

  const res = await fetch(`${HTTP_BASE}/blackboard/query?pattern=query.*`);
  assert(res.ok, "query should return 200");
  const body = await res.json() as any[];
  assert(Array.isArray(body), "query result should be array");
  assert(body.length >= 2, `should find at least 2 entries, found ${body.length}`);
  const keys = body.map((e: any) => e.key);
  assert(keys.includes("query.alpha"), "should include query.alpha");
  assert(keys.includes("query.beta"), "should include query.beta");
}

async function testBlackboardKeys() {
  const res = await fetch(`${HTTP_BASE}/blackboard/keys`);
  assert(res.ok, "keys should return 200");
  const body = await res.json() as any;
  assert(Array.isArray(body.keys), "should return keys array");
  assert(body.keys.length > 0, "should have at least some keys");
}

async function testBlackboardWriteValidation() {
  const res = await fetch(`${HTTP_BASE}/blackboard/write`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ key: "missing-value" }),
  });
  assert(res.status === 400, "should return 400 for missing value");
}

// --- Runner ---

async function main() {
  console.log("\nOdyssey Sidecar API Tests\n");
  console.log("═══════════════════════════\n");

  // Health
  console.log("HTTP Health:");
  await runTest("GET /health returns ok", testHealthEndpoint);

  // Blackboard HTTP API
  console.log("\nBlackboard HTTP API:");
  await runTest("POST /blackboard/write creates entry", testBlackboardWrite);
  await runTest("GET /blackboard/read returns entry", testBlackboardRead);
  await runTest("GET /blackboard/read returns 404 for missing", testBlackboardReadNotFound);
  await runTest("GET /blackboard/query returns matching entries", testBlackboardQuery);
  await runTest("GET /blackboard/keys returns key list", testBlackboardKeys);
  await runTest("POST /blackboard/write rejects missing value", testBlackboardWriteValidation);

  // Session WebSocket API
  console.log("\nSession WebSocket API:");
  await runTest("session.message to unknown session returns error", testSessionMessageToUnknownSession);
  await runTest("session.create + session.message round-trip", testSessionCreateAndMessage);
  await runTest("session.fork creates forked session", testSessionFork);
  await runTest("session.pause stops running session", testSessionPause);

  // Summary
  console.log("\n═══════════════════════════");
  const passed = results.filter((r) => r.passed).length;
  const failed = results.filter((r) => !r.passed).length;
  const total = results.length;
  console.log(`\nResults: ${passed}/${total} passed, ${failed} failed\n`);

  if (failed > 0) {
    console.log("Failed tests:");
    for (const r of results.filter((r) => !r.passed)) {
      console.log(`  ✗ ${r.name}: ${r.error}`);
    }
    console.log("");
  }

  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error("Test runner failed:", err);
  process.exit(2);
});
