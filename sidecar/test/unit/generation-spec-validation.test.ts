/**
 * Unit tests for generation spec validation rules.
 *
 * These are white-box tests that exercise the same validation logic
 * embedded in handleGenerateAgent (api-router.ts) and handleGenerateAgent/
 * handleGenerateSkill/handleGenerateTemplate (ws-server.ts). The logic is
 * implemented inline here as pure functions so no Anthropic API call is made.
 */
import { describe, test, expect } from "bun:test";

// ─── Pure validation helpers (mirrors production code) ───────────────────────

const VALID_ICONS = [
  "cpu", "brain", "terminal", "doc.text", "magnifyingglass", "shield",
  "wrench.and.screwdriver", "paintbrush", "chart.bar", "bubble.left.and.bubble.right",
  "network", "globe", "folder", "gear", "lightbulb", "book", "hammer",
  "ant", "ladybug", "leaf", "bolt", "wand.and.stars", "pencil.and.outline",
  "person.crop.circle", "star", "flag", "bell", "map", "eye", "lock.shield",
  "server.rack", "externaldrive", "icloud", "arrow.triangle.branch",
  "text.badge.checkmark", "checkmark.seal", "clock", "calendar",
  "exclamationmark.triangle", "play", "stop", "shuffle", "repeat",
  "square.and.pencil", "rectangle.and.text.magnifyingglass",
  "doc.on.clipboard", "tray.2", "archivebox", "shippingbox",
];

const VALID_COLORS = ["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"];

function stripCodeFences(text: string): string {
  if (!text.startsWith("```")) return text;
  return text.replace(/^```(?:json)?\s*\n?/, "").replace(/\n?```\s*$/, "");
}

function validateAgentSpec(spec: any): any {
  if (!spec.name || !spec.systemPrompt) {
    throw new Error("Generated spec missing required fields (name, systemPrompt)");
  }
  if (!VALID_ICONS.includes(spec.icon)) spec.icon = "cpu";
  if (!VALID_COLORS.includes(spec.color)) spec.color = "blue";
  if (!["sonnet", "opus", "haiku"].includes(spec.model)) spec.model = "sonnet";
  return spec;
}

function validateSkillSpec(spec: any): any {
  if (!spec.name || !spec.content) {
    throw new Error("Generated skill spec missing required fields (name, content)");
  }
  return {
    name: spec.name,
    description: spec.description ?? "",
    category: spec.category ?? "General",
    triggers: Array.isArray(spec.triggers) ? spec.triggers : [],
    matchedMCPIds: Array.isArray(spec.matchedMCPIds) ? spec.matchedMCPIds : [],
    content: spec.content,
  };
}

function validateTemplateSpec(spec: any): any {
  if (!spec.name || !spec.prompt) {
    throw new Error("Generated template spec missing required fields (name, prompt)");
  }
  return { name: spec.name, prompt: spec.prompt };
}

// ─── stripCodeFences ─────────────────────────────────────────────────────────

describe("stripCodeFences", () => {
  test("strips json code fences", () => {
    const input = "```json\n{\"name\": \"Test\"}\n```";
    expect(stripCodeFences(input)).toBe("{\"name\": \"Test\"}");
  });

  test("strips plain code fences (no language tag)", () => {
    const input = "```\n{\"name\": \"Test\"}\n```";
    expect(stripCodeFences(input)).toBe("{\"name\": \"Test\"}");
  });

  test("returns text unchanged when no fences", () => {
    const input = "{\"name\": \"Test\"}";
    expect(stripCodeFences(input)).toBe("{\"name\": \"Test\"}");
  });

  test("strips fences with no trailing newline before closing fence", () => {
    const input = "```json\n{\"name\": \"Test\"}```";
    expect(stripCodeFences(input)).toBe("{\"name\": \"Test\"}");
  });

  test("strips fences with opening fence immediately followed by content (no newline)", () => {
    const input = "```json{\"name\": \"Test\"}\n```";
    // the regex handles optional newline after opening fence
    const result = stripCodeFences(input);
    expect(result).not.toContain("```");
  });

  test("does not modify text that starts with other content", () => {
    const input = "Here is some text\n```json\n{}\n```";
    expect(stripCodeFences(input)).toBe("Here is some text\n```json\n{}\n```");
  });
});

// ─── validateAgentSpec ───────────────────────────────────────────────────────

describe("validateAgentSpec — required fields", () => {
  test("throws when name is missing", () => {
    expect(() =>
      validateAgentSpec({ systemPrompt: "You are helpful." })
    ).toThrow("missing required fields");
  });

  test("throws when systemPrompt is missing", () => {
    expect(() =>
      validateAgentSpec({ name: "My Agent" })
    ).toThrow("missing required fields");
  });

  test("throws when both name and systemPrompt are missing", () => {
    expect(() => validateAgentSpec({})).toThrow("missing required fields");
  });

  test("does not throw when both required fields are present", () => {
    expect(() =>
      validateAgentSpec({ name: "My Agent", systemPrompt: "You are helpful.", icon: "cpu", color: "blue", model: "sonnet" })
    ).not.toThrow();
  });
});

describe("validateAgentSpec — icon validation", () => {
  test("keeps valid icon unchanged", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "brain", color: "blue", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.icon).toBe("brain");
  });

  test("defaults invalid icon to 'cpu'", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "not-a-real-icon", color: "blue", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.icon).toBe("cpu");
  });

  test("defaults missing icon to 'cpu'", () => {
    const spec = { name: "A", systemPrompt: "S", color: "blue", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.icon).toBe("cpu");
  });

  test("accepts every valid icon without defaulting", () => {
    for (const icon of VALID_ICONS) {
      const spec = { name: "A", systemPrompt: "S", icon, color: "blue", model: "sonnet" };
      const result = validateAgentSpec({ ...spec });
      expect(result.icon).toBe(icon);
    }
  });
});

describe("validateAgentSpec — color validation", () => {
  test("keeps valid color unchanged", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "purple", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.color).toBe("purple");
  });

  test("defaults invalid color to 'blue'", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "magenta", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.color).toBe("blue");
  });

  test("defaults missing color to 'blue'", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", model: "sonnet" };
    const result = validateAgentSpec(spec);
    expect(result.color).toBe("blue");
  });

  test("accepts every valid color without defaulting", () => {
    for (const color of VALID_COLORS) {
      const spec = { name: "A", systemPrompt: "S", icon: "cpu", color, model: "sonnet" };
      const result = validateAgentSpec({ ...spec });
      expect(result.color).toBe(color);
    }
  });
});

describe("validateAgentSpec — model normalization", () => {
  test("keeps 'sonnet' unchanged", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "blue", model: "sonnet" };
    expect(validateAgentSpec(spec).model).toBe("sonnet");
  });

  test("keeps 'opus' unchanged", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "blue", model: "opus" };
    expect(validateAgentSpec(spec).model).toBe("opus");
  });

  test("keeps 'haiku' unchanged", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "blue", model: "haiku" };
    expect(validateAgentSpec(spec).model).toBe("haiku");
  });

  test("defaults invalid model to 'sonnet'", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "blue", model: "gpt-4" };
    expect(validateAgentSpec(spec).model).toBe("sonnet");
  });

  test("defaults missing model to 'sonnet'", () => {
    const spec = { name: "A", systemPrompt: "S", icon: "cpu", color: "blue" };
    expect(validateAgentSpec(spec).model).toBe("sonnet");
  });
});

// ─── validateSkillSpec ───────────────────────────────────────────────────────

describe("validateSkillSpec — required fields", () => {
  test("throws when name is missing", () => {
    expect(() =>
      validateSkillSpec({ content: "# Security\nCheck for issues." })
    ).toThrow("missing required fields");
  });

  test("throws when content is missing", () => {
    expect(() =>
      validateSkillSpec({ name: "Security Audit" })
    ).toThrow("missing required fields");
  });

  test("does not throw when both required fields are present", () => {
    expect(() =>
      validateSkillSpec({ name: "Security Audit", content: "# Check\nDo stuff." })
    ).not.toThrow();
  });
});

describe("validateSkillSpec — defaults", () => {
  test("defaults missing description to empty string", () => {
    const spec = validateSkillSpec({ name: "S", content: "C" });
    expect(spec.description).toBe("");
  });

  test("defaults missing category to 'General'", () => {
    const spec = validateSkillSpec({ name: "S", content: "C" });
    expect(spec.category).toBe("General");
  });

  test("defaults missing triggers to empty array", () => {
    const spec = validateSkillSpec({ name: "S", content: "C" });
    expect(spec.triggers).toEqual([]);
  });

  test("defaults non-array triggers to empty array", () => {
    const spec = validateSkillSpec({ name: "S", content: "C", triggers: "security" });
    expect(spec.triggers).toEqual([]);
  });

  test("defaults missing matchedMCPIds to empty array", () => {
    const spec = validateSkillSpec({ name: "S", content: "C" });
    expect(spec.matchedMCPIds).toEqual([]);
  });

  test("preserves provided triggers array", () => {
    const spec = validateSkillSpec({ name: "S", content: "C", triggers: ["audit", "security"] });
    expect(spec.triggers).toEqual(["audit", "security"]);
  });
});

// ─── validateTemplateSpec ────────────────────────────────────────────────────

describe("validateTemplateSpec — required fields", () => {
  test("throws when name is missing", () => {
    expect(() =>
      validateTemplateSpec({ prompt: "Review this PR." })
    ).toThrow("missing required fields");
  });

  test("throws when prompt is missing", () => {
    expect(() =>
      validateTemplateSpec({ name: "Review PR" })
    ).toThrow("missing required fields");
  });

  test("does not throw when both fields are present", () => {
    expect(() =>
      validateTemplateSpec({ name: "Review PR", prompt: "Review this PR for security issues." })
    ).not.toThrow();
  });

  test("returns only name and prompt fields", () => {
    const spec = validateTemplateSpec({ name: "Review PR", prompt: "Review this PR.", extra: "ignored" });
    expect(spec).toEqual({ name: "Review PR", prompt: "Review this PR." });
  });
});
