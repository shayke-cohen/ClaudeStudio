import type { AgentConfig } from "../types.js";
import type { RuntimeDependencies, RuntimeSendArgs, RuntimeSendResult, ProviderRuntime } from "./runtime.js";

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export class MockRuntime implements ProviderRuntime {
  readonly provider = "mock" as const;

  constructor(private readonly deps: RuntimeDependencies) {}

  async createSession(_sessionId: string, _config: AgentConfig): Promise<void> {}

  /**
   * Streams a fake response.
   *
   * Recognizes a few magic prefixes in the user message so smoke tests can
   * reproduce different streaming shapes without changing the runtime:
   *
   *   - "STREAM:<chars>:<rate>"  — emit `<chars>` characters, ~`<rate>`
   *     tokens/sec (defaults: 4000, 40). Used to reproduce the "app gets
   *     stuck during a long stream" symptom.
   *   - "THINK:<chars>:<rate>"   — same shape, but emits `stream.thinking`
   *     events.
   *
   * Anything else falls back to the legacy single-token echo.
   */
  async sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult> {
    const stream = parseStreamMagic(args.text);
    if (stream) {
      const tokens = generateTokens(stream.chars);
      const intervalMs = Math.max(1, Math.round(1000 / stream.rate));
      const eventType = stream.kind === "think" ? "stream.thinking" : "stream.token";
      let totalChars = 0;
      for (const tok of tokens) {
        this.deps.emit({ type: eventType, sessionId: args.sessionId, text: tok });
        totalChars += tok.length;
        await sleep(intervalMs);
      }
      const resultText = `mock-stream: ${totalChars} chars over ~${(totalChars / stream.rate).toFixed(1)}s`;
      return {
        resultText,
        costDelta: 0,
        inputTokens: 1,
        outputTokens: tokens.length,
        numTurns: 1,
      };
    }

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

interface StreamMagic {
  kind: "token" | "think";
  chars: number;
  rate: number;
}

function parseStreamMagic(text: string): StreamMagic | null {
  const trimmed = text.trim();
  const match = /^(STREAM|THINK):(\d+)(?::(\d+))?$/i.exec(trimmed);
  if (!match) return null;
  const kind = match[1].toUpperCase() === "THINK" ? "think" : "token";
  const chars = Math.max(1, parseInt(match[2], 10));
  const rate = match[3] ? Math.max(1, parseInt(match[3], 10)) : 40;
  return { kind, chars, rate };
}

/**
 * Split `total` chars into pseudo-token chunks that look like real LLM output —
 * average ~5 chars per token, occasional newlines, mostly latin letters so a
 * SwiftUI Text() lays it out the way it would lay out a real reply.
 */
function generateTokens(total: number): string[] {
  const out: string[] = [];
  const words = [
    "Sure", "let", "me", "explain", "the", "approach", "in", "more", "detail",
    "first", "we", "look", "at", "the", "structure", "and", "then", "iterate",
    "across", "every", "case", "we", "need", "to", "handle", "carefully",
  ];
  let written = 0;
  let i = 0;
  while (written < total) {
    const word = words[i % words.length];
    const piece = (i % 17 === 0 && i > 0 ? "\n" : i === 0 ? "" : " ") + word;
    out.push(piece);
    written += piece.length;
    i++;
  }
  return out;
}
