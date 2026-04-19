/**
 * Shared test helpers for Odyssey sidecar tests.
 *
 * Provides BufferedWs (race-free WebSocket wrapper), wsConnect (connect with retry),
 * and waitForHealth (HTTP health poll). Used by ws-protocol, full-flow, and scenarios tests.
 */

export class BufferedWs {
  ws: WebSocket;
  buffer: any[] = [];
  private listeners: Array<(msg: any) => void> = [];

  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.onmessage = (event: MessageEvent) => {
      const msg = JSON.parse(typeof event.data === "string" ? event.data : "{}");
      this.buffer.push(msg);
      for (const fn of this.listeners) fn(msg);
    };
  }

  send(data: any) {
    this.ws.send(JSON.stringify(data));
  }

  close() {
    this.ws.close();
  }

  waitFor(predicate: (msg: any) => boolean, timeoutMs = 10000): Promise<any> {
    const existing = this.buffer.find(predicate);
    if (existing) return Promise.resolve(existing);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        reject(new Error("waitFor timeout"));
      }, timeoutMs);

      const listener = (msg: any) => {
        if (predicate(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(msg);
        }
      };
      this.listeners.push(listener);
    });
  }

  collectNew(count: number, timeoutMs = 5000): Promise<any[]> {
    const startIdx = this.buffer.length;
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve(this.buffer.slice(startIdx)), timeoutMs);
      const listener = () => {
        if (this.buffer.length - startIdx >= count) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(this.buffer.slice(startIdx, startIdx + count));
        }
      };
      this.listeners.push(listener);
    });
  }

  collectUntil(predicate: (msg: any) => boolean, timeoutMs = 30000): Promise<any[]> {
    const startIdx = this.buffer.length;
    for (let i = startIdx; i < this.buffer.length; i++) {
      if (predicate(this.buffer[i])) return Promise.resolve(this.buffer.slice(startIdx, i + 1));
    }
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        resolve(this.buffer.slice(startIdx));
      }, timeoutMs);
      const listener = (msg: any) => {
        if (predicate(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(this.buffer.slice(startIdx));
        }
      };
      this.listeners.push(listener);
    });
  }

  /** Collect all events matching a filter until a stop predicate fires. */
  collectAllMatching(
    filter: (msg: any) => boolean,
    stopWhen: (msg: any) => boolean,
    timeoutMs = 60000,
  ): Promise<any[]> {
    const collected: any[] = [];
    const startIdx = this.buffer.length;

    for (let i = 0; i < this.buffer.length; i++) {
      if (filter(this.buffer[i])) collected.push(this.buffer[i]);
      if (stopWhen(this.buffer[i])) return Promise.resolve(collected);
    }

    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.listeners = this.listeners.filter((fn) => fn !== listener);
        resolve(collected);
      }, timeoutMs);
      const listener = (msg: any) => {
        if (filter(msg)) collected.push(msg);
        if (stopWhen(msg)) {
          clearTimeout(timer);
          this.listeners = this.listeners.filter((fn) => fn !== listener);
          resolve(collected);
        }
      };
      this.listeners.push(listener);
    });
  }
}

/**
 * Connect to a WS server with retry logic (useful when sidecar is still booting).
 */
export function wsConnect(port: number, timeoutMs = 10000): Promise<BufferedWs> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("WS connect timeout")), timeoutMs);
    const tryConnect = () => {
      try {
        const ws = new WebSocket(`ws://localhost:${port}`);
        ws.onopen = () => {
          clearTimeout(timer);
          resolve(new BufferedWs(ws));
        };
        ws.onerror = () => {
          setTimeout(tryConnect, 300);
        };
      } catch {
        setTimeout(tryConnect, 300);
      }
    };
    tryConnect();
  });
}

/**
 * Connect to a WS server without retry (fails immediately on error).
 */
export function wsConnectDirect(port: number, timeoutMs = 5000): Promise<BufferedWs> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const timer = setTimeout(() => reject(new Error("connect timeout")), timeoutMs);
    ws.onopen = () => {
      clearTimeout(timer);
      resolve(new BufferedWs(ws));
    };
    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error("connect failed"));
    };
  });
}

/**
 * Poll the HTTP /health endpoint until it responds 200.
 */
export async function waitForHealth(httpPort: number, maxRetries = 30): Promise<void> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${httpPort}/health`);
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("Sidecar HTTP did not become ready");
}

/** Standard agent config for tests. */
export function makeAgentConfig(overrides: Partial<{
  name: string;
  systemPrompt: string;
  provider: string;
  model: string;
  maxTurns: number;
  maxBudget: number;
  allowedTools: string[];
  mcpServers: any[];
  skills: any[];
  workingDirectory: string;
  interactive: boolean;
  instancePolicy: string;
  instancePolicyPoolMax: number;
}> = {}): any {
  return {
    name: overrides.name ?? "TestAgent",
    systemPrompt: overrides.systemPrompt ?? "You are a test agent.",
    provider: overrides.provider ?? "claude",
    allowedTools: overrides.allowedTools ?? [],
    mcpServers: overrides.mcpServers ?? [],
    model: overrides.model ?? (overrides.provider === "codex"
      ? "gpt-5.4"
      : overrides.provider === "foundation"
        ? "foundation.system"
        : overrides.provider === "mlx"
          ? "mlx-default"
          : "claude-sonnet-4-6"),
    maxTurns: overrides.maxTurns ?? 3,
    workingDirectory: overrides.workingDirectory ?? "/tmp",
    skills: overrides.skills ?? [],
    ...(overrides.interactive != null ? { interactive: overrides.interactive } : {}),
    ...(overrides.maxBudget != null ? { maxBudget: overrides.maxBudget } : {}),
    ...(overrides.instancePolicy != null ? { instancePolicy: overrides.instancePolicy } : {}),
    ...(overrides.instancePolicyPoolMax != null ? { instancePolicyPoolMax: overrides.instancePolicyPoolMax } : {}),
  };
}
