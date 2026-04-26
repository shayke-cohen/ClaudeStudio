/**
 * long-stream-smoke.ts — Drives a long mock-streaming session against a
 * running sidecar to reproduce the "app feels stuck during streaming" symptom
 * without spending real Claude credits.
 *
 * Run with: bun run sidecar/test/feedback/long-stream-smoke.ts
 *
 * Env vars:
 *   ODYSSEY_HTTP_PORT  — HTTP port (default 9850)
 *   ODYSSEY_WS_PORT    — WebSocket port (default 9849)
 *   ODYSSEY_WS_TOKEN   — required by macOS app sidecars
 *   STREAM_CHARS       — total chars to emit (default 4000)
 *   STREAM_RATE        — tokens/sec (default 40)
 *   STREAM_KIND        — "token" or "think" (default "token")
 *
 * Usage shape: kicks the message `STREAM:<chars>:<rate>` (or `THINK:...`)
 * which the MockRuntime recognizes and turns into a sustained stream of
 * `stream.token` / `stream.thinking` events. Run while the macOS DEBUG app is
 * connected to the same sidecar to load the UI; watch the `perf` os_log
 * category for stall warnings.
 */

import { waitForHealth, wsConnect } from "../helpers.js";

const HTTP_PORT = parseInt(process.env.ODYSSEY_HTTP_PORT ?? "9850");
const WS_PORT = parseInt(process.env.ODYSSEY_WS_PORT ?? "9849");
const STREAM_CHARS = parseInt(process.env.STREAM_CHARS ?? "4000");
const STREAM_RATE = parseInt(process.env.STREAM_RATE ?? "40");
const STREAM_KIND = (process.env.STREAM_KIND ?? "token").toLowerCase();
const MAGIC = (STREAM_KIND === "think" ? "THINK" : "STREAM") + `:${STREAM_CHARS}:${STREAM_RATE}`;

interface TokenStats {
  totalEvents: number;
  totalChars: number;
  firstTokenAtMs: number | null;
  lastTokenAtMs: number | null;
  maxGapMs: number;
  gapHistogram: Map<number, number>; // bucketed by 5ms
}

function emptyStats(): TokenStats {
  return {
    totalEvents: 0,
    totalChars: 0,
    firstTokenAtMs: null,
    lastTokenAtMs: null,
    maxGapMs: 0,
    gapHistogram: new Map(),
  };
}

async function main(): Promise<void> {
  const startMs = Date.now();

  await waitForHealth(HTTP_PORT);
  const ws = await wsConnect(WS_PORT);

  const agentName = `long-stream-${Date.now()}`;
  ws.send({
    type: "agent.register",
    agents: [
      {
        name: agentName,
        config: {
          name: agentName,
          systemPrompt: "Mock streamer.",
          provider: "mock",
          model: "mock",
          allowedTools: [],
          mcpServers: [],
          skills: [],
          workingDirectory: "/tmp",
          maxTurns: 1,
        },
      },
    ],
  });
  await new Promise((r) => setTimeout(r, 200));

  const stats = emptyStats();
  let lastEventAtMs = 0;

  const tokenEventName = STREAM_KIND === "think" ? "stream.thinking" : "stream.token";
  ws.ws.addEventListener("message", (event: MessageEvent) => {
    const msg: any = JSON.parse(typeof event.data === "string" ? event.data : "{}");
    if (msg.type !== tokenEventName) return;
    const now = Date.now();
    if (stats.firstTokenAtMs === null) stats.firstTokenAtMs = now - startMs;
    if (lastEventAtMs > 0) {
      const gap = now - lastEventAtMs;
      if (gap > stats.maxGapMs) stats.maxGapMs = gap;
      const bucket = Math.floor(gap / 5) * 5;
      stats.gapHistogram.set(bucket, (stats.gapHistogram.get(bucket) ?? 0) + 1);
    }
    lastEventAtMs = now;
    stats.lastTokenAtMs = now - startMs;
    stats.totalEvents += 1;
    stats.totalChars += (msg.text ?? "").length;
  });

  const createRes = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/sessions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ agentName, message: MAGIC }),
  });
  if (!createRes.ok) {
    throw new Error(`POST /sessions failed (${createRes.status}): ${await createRes.text()}`);
  }
  const session: any = await createRes.json();
  const sessionId: string = session.id ?? session.sessionId;
  if (!sessionId) throw new Error(`Missing session id in response: ${JSON.stringify(session)}`);

  // Generous timeout: chars/rate plus a 2s safety margin.
  const expectedMs = (STREAM_CHARS / STREAM_RATE) * 1000 + 2000;
  const deadline = Date.now() + expectedMs * 2;
  let final: any | null = null;
  while (Date.now() < deadline && !final) {
    const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/sessions/${sessionId}/turns`);
    if (res.ok) {
      const data: any = await res.json();
      const terminal = (data.turns ?? []).find(
        (t: any) => t.status === "completed" || t.status === "failed",
      );
      if (terminal) final = terminal;
    }
    if (!final) await new Promise((r) => setTimeout(r, 250));
  }

  await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/sessions/${sessionId}`, { method: "DELETE" });
  ws.close();

  if (!final) {
    console.error("Stream did not complete in time");
    process.exit(1);
  }

  const wallMs = Date.now() - startMs;
  const streamMs = (stats.lastTokenAtMs ?? 0) - (stats.firstTokenAtMs ?? 0);
  const observedRate = streamMs > 0 ? (stats.totalEvents / streamMs) * 1000 : 0;
  const observedChars = streamMs > 0 ? (stats.totalChars / streamMs) * 1000 : 0;

  // Top 5 gap buckets to surface jitter in the sidecar->client path itself
  // (which would mask UI-side stalls in the analysis).
  const buckets = [...stats.gapHistogram.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);

  const summary = {
    config: { chars: STREAM_CHARS, rate: STREAM_RATE, kind: STREAM_KIND },
    sessionStatus: final.status,
    wallMs,
    streamMs,
    totalEvents: stats.totalEvents,
    totalChars: stats.totalChars,
    firstTokenAtMs: stats.firstTokenAtMs,
    observedTokensPerSec: Number(observedRate.toFixed(1)),
    observedCharsPerSec: Number(observedChars.toFixed(1)),
    maxGapMs: stats.maxGapMs,
    topGapBucketsMs: buckets,
  };
  console.log(JSON.stringify(summary, null, 2));
}

main().then(() => process.exit(0)).catch((err: unknown) => {
  console.error(err instanceof Error ? err.stack ?? err.message : String(err));
  process.exit(1);
});
