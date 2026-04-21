/**
 * Unit tests for GenerationService.
 * Mocks @anthropic-ai/claude-agent-sdk so no real LLM calls are made.
 */
import { mock, describe, test, expect, beforeEach } from "bun:test";

// ─── Mock Agent SDK before imports ───────────────────────────────────────────

type QueryFn = (opts: any) => AsyncIterable<any>;
let mockQuery: QueryFn = async function* () {
  yield {
    type: "assistant",
    message: { content: [{ type: "text", text: '{"name":"Test","prompt":"Do the thing"}' }] },
  };
};

mock.module("@anthropic-ai/claude-agent-sdk", () => ({
  query: (opts: any) => mockQuery(opts),
}));

// ─── Imports (after mock) ─────────────────────────────────────────────────────

import { GenerationService } from "../../src/generation-service.js";

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("GenerationService.generate", () => {
  let svc: GenerationService;

  beforeEach(() => {
    svc = new GenerationService();
  });

  test("returns assistant text from stream", async () => {
    mockQuery = async function* () {
      yield {
        type: "assistant",
        message: { content: [{ type: "text", text: '{"name":"Review PR"}' }] },
      };
    };
    const result = await svc.generate("system", "user");
    expect(result).toBe('{"name":"Review PR"}');
  });

  test("concatenates multiple text blocks", async () => {
    mockQuery = async function* () {
      yield {
        type: "assistant",
        message: { content: [
          { type: "text", text: '{"name":' },
          { type: "text", text: '"Foo"}' },
        ] },
      };
    };
    const result = await svc.generate("system", "user");
    expect(result).toBe('{"name":"Foo"}');
  });

  test("throws when stream yields no assistant content", async () => {
    mockQuery = async function* () {
      yield { type: "system", message: {} };
    };
    await expect(svc.generate("system", "user")).rejects.toThrow("no output");
  });

  test("skips non-assistant messages", async () => {
    mockQuery = async function* () {
      yield { type: "tool_result", message: {} };
      yield {
        type: "assistant",
        message: { content: [{ type: "text", text: '{"ok":true}' }] },
      };
    };
    const result = await svc.generate("system", "user");
    expect(result).toBe('{"ok":true}');
  });

  test("handles empty content array without crashing", async () => {
    mockQuery = async function* () {
      yield { type: "assistant", message: { content: [] } };
      yield { type: "assistant", message: { content: [{ type: "text", text: '{"done":true}' }] } };
    };
    const result = await svc.generate("system", "user");
    expect(result).toBe('{"done":true}');
  });

  test("passes systemPrompt and model to SDK options", async () => {
    let capturedOptions: any;
    mockQuery = function (opts: any) {
      capturedOptions = opts;
      return (async function* () {
        yield { type: "assistant", message: { content: [{ type: "text", text: '{"x":1}' }] } };
      })();
    };
    await svc.generate("my system", "my request");
    expect(capturedOptions.options.systemPrompt).toEqual({
      type: "preset",
      preset: "claude_code",
      append: "my system",
    });
    expect(capturedOptions.options.model).toBe("claude-sonnet-4-6");
    expect(capturedOptions.options.maxTurns).toBe(1);
  });
});

describe("GenerationService.extractJSON", () => {
  let svc: GenerationService;

  beforeEach(() => {
    svc = new GenerationService();
  });

  test("returns bare JSON unchanged", () => {
    const json = '{"name":"Test","prompt":"hello"}';
    expect(svc.extractJSON(json)).toBe(json);
  });

  test("strips json code fence", () => {
    const input = "```json\n{\"name\":\"Test\"}\n```";
    const result = svc.extractJSON(input);
    expect(JSON.parse(result)).toEqual({ name: "Test" });
  });

  test("strips plain code fence", () => {
    const input = "```\n{\"name\":\"Test\"}\n```";
    const result = svc.extractJSON(input);
    expect(JSON.parse(result)).toEqual({ name: "Test" });
  });

  test("extracts object from surrounding prose", () => {
    const input = 'Here is the JSON:\n{"name":"Test","prompt":"do it"}\nDone.';
    const result = svc.extractJSON(input);
    expect(JSON.parse(result)).toEqual({ name: "Test", prompt: "do it" });
  });

  test("returns text as-is when no valid JSON found", () => {
    const input = "not json at all";
    expect(svc.extractJSON(input)).toBe("not json at all");
  });

  test("handles leading/trailing whitespace around code fence", () => {
    const input = "  ```json\n{\"name\":\"Test\"}\n```  ";
    // trim() in extractJSON handles the outer whitespace before fence detection
    const result = svc.extractJSON(input);
    expect(JSON.parse(result)).toEqual({ name: "Test" });
  });

  test("returns raw string when two JSON objects appear in prose", () => {
    // Two objects: firstBrace=0, lastBrace spans both → extracted text isn't valid JSON → fallthrough
    const input = '{"name":"First"} and then {"name":"Second"}';
    const result = svc.extractJSON(input);
    expect(typeof result).toBe("string");
  });
});
