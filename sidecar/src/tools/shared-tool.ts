import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

export interface SharedToolExtra {
  sessionId?: string;
}

export interface SharedToolContentItem {
  type: "text";
  text: string;
}

export interface SharedToolResult {
  content: SharedToolContentItem[];
  success?: boolean;
}

export interface SharedToolDefinition<TArgs = any> {
  name: string;
  description: string;
  inputSchema: Record<string, z.ZodTypeAny>;
  execute: (args: TArgs, extra?: SharedToolExtra) => Promise<SharedToolResult>;
}

export interface CodexDynamicToolSpec {
  name: string;
  description: string;
  inputSchema: unknown;
  deferLoading?: boolean;
}

interface CodexDynamicToolContentItem {
  type: "inputText";
  text: string;
}

export function defineSharedTool<TArgs = any>(
  name: string,
  description: string,
  inputSchema: Record<string, z.ZodTypeAny>,
  execute: SharedToolDefinition<TArgs>["execute"],
): SharedToolDefinition<TArgs> {
  return { name, description, inputSchema, execute };
}

export function createTextResult(value: unknown, success = true): SharedToolResult {
  return {
    content: [
      {
        type: "text",
        text: typeof value === "string" ? value : JSON.stringify(value),
      },
    ],
    success,
  };
}

export function toClaudeTool(definition: SharedToolDefinition) {
  return tool(
    definition.name,
    definition.description,
    definition.inputSchema,
    async (args: any, extra: any) => definition.execute(args, extra),
  );
}

export function toCodexDynamicToolSpec(definition: SharedToolDefinition): CodexDynamicToolSpec {
  return {
    name: definition.name,
    description: definition.description,
    inputSchema: z.toJSONSchema(z.object(definition.inputSchema), { io: "input" }),
  };
}

export function toCodexDynamicToolResponse(result: SharedToolResult): {
  contentItems: CodexDynamicToolContentItem[];
  success: boolean;
} {
  return {
    contentItems: result.content.map((item) => ({
      type: "inputText",
      text: item.text,
    })),
    success: result.success ?? true,
  };
}
