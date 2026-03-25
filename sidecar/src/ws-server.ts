import type { ServerWebSocket } from "bun";
import type { SidecarCommand, SidecarEvent } from "./types.js";
import type { SessionManager } from "./session-manager.js";
import type { ToolContext } from "./tools/tool-context.js";
import { resolveQuestion } from "./tools/ask-user-tool.js";
import Anthropic from "@anthropic-ai/sdk";

export class WsServer {
  private clients = new Set<ServerWebSocket<unknown>>();
  private sessionManager: SessionManager;
  private ctx: ToolContext;
  private server: ReturnType<typeof Bun.serve> | null = null;

  constructor(port: number, sessionManager: SessionManager, ctx: ToolContext) {
    this.sessionManager = sessionManager;
    this.ctx = ctx;

    this.server = Bun.serve({
      port,
      fetch(req, server) {
        if (server.upgrade(req)) return undefined;
        return new Response("WebSocket endpoint", { status: 426 });
      },
      websocket: {
        open: (ws) => {
          this.clients.add(ws);
          console.log(`[ws] Swift client connected (total: ${this.clients.size})`);
          const ready: SidecarEvent = {
            type: "sidecar.ready",
            port,
            version: "0.2.0",
          };
          ws.send(JSON.stringify(ready));
        },
        message: (ws, message) => {
          try {
            const data = typeof message === "string" ? message : new TextDecoder().decode(message);
            console.log("[ws] Received:", data.substring(0, 200));
            const command = JSON.parse(data) as SidecarCommand;
            this.handleCommand(command).catch((err) => {
              console.error("[ws] Command handler error:", err);
            });
          } catch (err) {
            console.error("[ws] Failed to parse command:", err);
          }
        },
        close: (ws) => {
          this.clients.delete(ws);
          console.log(`[ws] Swift client disconnected (total: ${this.clients.size})`);
        },
      },
    });

    console.log(`[ws] WebSocket server listening on ws://localhost:${port}`);
  }

  private async handleCommand(command: SidecarCommand): Promise<void> {
    switch (command.type) {
      case "session.create": {
        await this.sessionManager.createSession(
          command.conversationId,
          command.agentConfig,
        );
        break;
      }
      case "session.message":
        await this.sessionManager.sendMessage(
          command.sessionId,
          command.text,
          command.attachments,
          command.planMode,
        );
        break;
      case "session.resume":
        await this.sessionManager.resumeSession(
          command.sessionId,
          command.claudeSessionId,
        );
        break;
      case "session.fork":
        await this.sessionManager.forkSession(command.sessionId, command.childSessionId);
        break;
      case "session.pause":
        await this.sessionManager.pauseSession(command.sessionId);
        break;
      case "session.updateCwd":
        this.sessionManager.updateSessionCwd(command.sessionId, command.workingDirectory);
        console.log(`[ws] Updated cwd for ${command.sessionId} → ${command.workingDirectory}`);
        break;
      case "session.bulkResume":
        await this.sessionManager.bulkResume(command.sessions);
        break;
      case "agent.register":
        for (const def of command.agents) {
          this.ctx.agentDefinitions.set(def.name, def.config);
          console.log(`[ws] Registered agent definition: ${def.name}`);
        }
        break;

      case "delegate.task":
        await this.handleDelegateTask(command);
        break;

      case "peer.register":
        this.ctx.peerRegistry.register(
          command.name,
          command.endpoint,
          command.agents.map((a: any) => ({ name: a.name, config: a.config })),
        );
        break;
      case "peer.remove":
        this.ctx.peerRegistry.remove(command.name);
        break;

      case "generate.agent":
        this.handleGenerateAgent(command).catch((err) => {
          console.error("[ws] generate.agent handler error:", err);
          this.broadcast({
            type: "generate.agent.error",
            requestId: command.requestId,
            error: err.message ?? "Unknown error",
          });
        });
        break;

      case "session.questionAnswer": {
        const resolved = resolveQuestion(
          command.questionId,
          command.answer,
          command.selectedOptions,
        );
        if (resolved) {
          console.log(`[ws] session.questionAnswer: resolved question ${command.questionId} for session ${command.sessionId}`);
        } else {
          console.warn(`[ws] session.questionAnswer: no pending question found for ${command.questionId}`);
        }
        break;
      }

      case "session.confirmationAnswer": {
        const { resolveConfirmation } = await import("./tools/rich-display-tools.js");
        const confirmed = resolveConfirmation(
          command.confirmationId,
          command.approved,
          command.modifiedAction,
        );
        if (confirmed) {
          console.log(`[ws] session.confirmationAnswer: resolved confirmation ${command.confirmationId} approved=${command.approved}`);
        } else {
          console.warn(`[ws] session.confirmationAnswer: no pending confirmation found for ${command.confirmationId}`);
        }
        break;
      }
    }
  }

  private async handleDelegateTask(command: Extract<SidecarCommand, { type: "delegate.task" }>): Promise<void> {
    const config = this.ctx.agentDefinitions.get(command.toAgent);
    if (!config) {
      console.error(`[ws] delegate.task: agent definition not found for "${command.toAgent}"`);
      this.broadcast({
        type: "session.error",
        sessionId: command.sessionId,
        error: `Agent definition not found: ${command.toAgent}`,
      });
      return;
    }

    const prompt = command.context
      ? `${command.task}\n\n## Context\n${command.context}`
      : command.task;

    this.broadcast({
      type: "peer.delegate",
      from: this.ctx.sessions.get(command.sessionId)?.agentName ?? command.sessionId,
      to: command.toAgent,
      task: command.task,
    });

    const newSessionId = crypto.randomUUID();
    try {
      await this.ctx.spawnSession(newSessionId, config, prompt, command.waitForResult);
      console.log(`[ws] delegate.task: spawned new session ${newSessionId} for ${command.toAgent}`);
    } catch (err: any) {
      console.error(`[ws] delegate.task: spawn failed:`, err);
      this.broadcast({
        type: "session.error",
        sessionId: command.sessionId,
        error: `Delegation to ${command.toAgent} failed: ${err.message}`,
      });
    }
  }

  private async handleGenerateAgent(
    command: Extract<SidecarCommand, { type: "generate.agent" }>
  ): Promise<void> {
    const anthropic = new Anthropic();

    const validIcons = [
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
    const validColors = ["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"];

    const skillsCatalog = command.availableSkills.length > 0
      ? command.availableSkills
          .map((s) => `- ID: ${s.id} | Name: ${s.name} | Category: ${s.category} | Description: ${s.description}`)
          .join("\n")
      : "(no skills available)";

    const mcpsCatalog = command.availableMCPs.length > 0
      ? command.availableMCPs
          .map((m) => `- ID: ${m.id} | Name: ${m.name} | Description: ${m.description}`)
          .join("\n")
      : "(no MCP servers available)";

    const systemPrompt = `You are an agent designer. Given a user's description of an AI agent they want to create, generate a complete agent definition as JSON.

## Output Format
Return ONLY valid JSON (no markdown, no code fences) with this exact schema:
{
  "name": "string (short, 2-4 words)",
  "description": "string (one sentence describing what the agent does)",
  "systemPrompt": "string (detailed system prompt for the agent, 200-800 words, written in second person addressing the agent)",
  "model": "sonnet" | "opus" | "haiku",
  "icon": "string (SF Symbol name from the allowed list)",
  "color": "string (from the allowed list)",
  "matchedSkillIds": ["array of skill ID strings that are relevant"],
  "matchedMCPIds": ["array of MCP server ID strings that are relevant"],
  "maxTurns": null,
  "maxBudget": null
}

## Constraints
- icon must be one of: ${JSON.stringify(validIcons)}
- color must be one of: ${JSON.stringify(validColors)}
- model: use "sonnet" for most agents, "opus" for agents that need deep reasoning or complex analysis, "haiku" for simple/fast agents
- matchedSkillIds: only include IDs from the available skills catalog below. Pick skills that are directly relevant.
- matchedMCPIds: only include IDs from the available MCPs catalog below. Pick MCPs that are directly relevant.
- The systemPrompt should be focused, actionable, and specific to the agent's purpose. Write it as instructions to the AI agent.

## Available Skills
${skillsCatalog}

## Available MCP Servers
${mcpsCatalog}`;

    console.log(`[ws] generate.agent: generating agent from prompt: "${command.prompt.substring(0, 100)}..."`);

    const response = await anthropic.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 4096,
      system: systemPrompt,
      messages: [{ role: "user", content: command.prompt }],
    });

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new Error("No text response from Claude");
    }

    let jsonText = textBlock.text.trim();
    // Strip markdown code fences if present
    if (jsonText.startsWith("```")) {
      jsonText = jsonText.replace(/^```(?:json)?\s*\n?/, "").replace(/\n?```\s*$/, "");
    }

    const spec = JSON.parse(jsonText);

    // Validate required fields
    if (!spec.name || !spec.systemPrompt) {
      throw new Error("Generated spec missing required fields (name, systemPrompt)");
    }

    // Ensure valid icon and color
    if (!validIcons.includes(spec.icon)) spec.icon = "cpu";
    if (!validColors.includes(spec.color)) spec.color = "blue";
    if (!["sonnet", "opus", "haiku"].includes(spec.model)) spec.model = "sonnet";

    console.log(`[ws] generate.agent: generated "${spec.name}" with ${spec.matchedSkillIds?.length ?? 0} skills, ${spec.matchedMCPIds?.length ?? 0} MCPs`);

    this.broadcast({
      type: "generate.agent.result",
      requestId: command.requestId,
      spec: {
        name: spec.name,
        description: spec.description ?? "",
        systemPrompt: spec.systemPrompt,
        model: spec.model ?? "sonnet",
        icon: spec.icon ?? "cpu",
        color: spec.color ?? "blue",
        matchedSkillIds: Array.isArray(spec.matchedSkillIds) ? spec.matchedSkillIds : [],
        matchedMCPIds: Array.isArray(spec.matchedMCPIds) ? spec.matchedMCPIds : [],
        maxTurns: spec.maxTurns ?? undefined,
        maxBudget: spec.maxBudget ?? undefined,
      },
    });
  }

  broadcast(event: SidecarEvent): void {
    const data = JSON.stringify(event);
    for (const client of this.clients) {
      try {
        client.send(data);
      } catch {
        this.clients.delete(client);
      }
    }
  }

  close(): void {
    this.server?.stop();
  }
}
