import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";

export function createMessagingTools(ctx: ToolContext, callingSessionId: string) {
  return [
    tool(
      "peer_send_message",
      "Send a direct async message to another agent. Returns immediately without waiting for a reply. The target agent will see this in their inbox when they call peer_receive_messages.",
      {
        to_agent: z.string().describe("Target agent session ID or agent name"),
        message: z.string().describe("Message text to send"),
        priority: z.enum(["normal", "urgent"]).optional().describe("Message priority (default: normal)"),
      },
      async (args) => {
        const targetId = resolveAgentId(ctx, args.to_agent);
        if (!targetId) {
          return { content: [{ type: "text" as const, text: JSON.stringify({ error: "agent_not_found", to: args.to_agent }) }] };
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const msg = {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          to: targetId,
          text: args.message,
          priority: args.priority ?? "normal" as const,
          timestamp: new Date().toISOString(),
          read: false,
        };
        ctx.messages.push(targetId, msg);

        ctx.broadcast({
          type: "peer.chat",
          channelId: `dm-${callingSessionId}-${targetId}`,
          from: senderState?.agentName ?? callingSessionId,
          message: args.message,
        });

        return { content: [{ type: "text" as const, text: JSON.stringify({ sent: true, to: args.to_agent }) }] };
      },
    ),

    tool(
      "peer_broadcast",
      "Broadcast a message to all active agents on a named channel. All agents will receive this in their inbox.",
      {
        channel: z.string().describe("Channel name (e.g. 'status', 'findings')"),
        message: z.string().describe("Message to broadcast"),
      },
      async (args) => {
        const senderState = ctx.sessions.get(callingSessionId);
        const activeIds = ctx.sessions.listActive().map((s) => s.id);
        const msg = {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          text: args.message,
          channel: args.channel,
          priority: "normal" as const,
          timestamp: new Date().toISOString(),
          read: false,
        };
        ctx.messages.pushToAll(msg, activeIds);

        ctx.broadcast({
          type: "peer.chat",
          channelId: `broadcast-${args.channel}`,
          from: senderState?.agentName ?? callingSessionId,
          message: args.message,
        });

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ broadcast: true, channel: args.channel, recipients: activeIds.length - 1 }),
          }],
        };
      },
    ),

    tool(
      "peer_receive_messages",
      "Check your inbox for async messages and chat requests from other agents. Returns unread messages.",
      {
        since: z.string().optional().describe("ISO timestamp - only return messages after this time"),
      },
      async (args) => {
        const messages = ctx.messages.drain(callingSessionId, args.since);
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ messages, count: messages.length }),
          }],
        };
      },
    ),

    tool(
      "peer_list_agents",
      "List all running and available agent sessions. Returns each agent's name, status, and session ID.",
      {},
      async () => {
        const sessions = ctx.sessions.list();
        const agents = sessions.map((s) => ({
          sessionId: s.id,
          name: s.agentName,
          status: s.status,
          isSelf: s.id === callingSessionId,
        }));

        const registered = Array.from(ctx.agentDefinitions.entries()).map(([name]) => ({
          name,
          type: "registered_definition",
          location: "local",
        }));

        const remoteAgents = ctx.peerRegistry.listConnected().flatMap((peer) =>
          peer.agents.map((a) => ({
            name: a.name,
            type: "remote_agent",
            location: "remote",
            peer: peer.name,
          }))
        );

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ activeSessions: agents, registeredAgents: registered, remoteAgents }),
          }],
        };
      },
    ),

    tool(
      "peer_delegate_task",
      "Delegate a task to another agent. Spawns a new session for the delegate. If wait_for_result is true, blocks until the delegate finishes and returns the result.",
      {
        to_agent: z.string().describe("Agent definition name to delegate to (e.g. 'Coder', 'Reviewer')"),
        task: z.string().describe("Task description - what the agent should do"),
        context: z.string().optional().describe("Relevant context data to pass along"),
        wait_for_result: z.boolean().optional().describe("If true, block until the delegate finishes (default: false)"),
      },
      async (args) => {
        const config = ctx.agentDefinitions.get(args.to_agent);
        if (!config) {
          const existingSession = resolveAgentId(ctx, args.to_agent);
          if (existingSession) {
            const senderState = ctx.sessions.get(callingSessionId);
            ctx.messages.push(existingSession, {
              id: randomUUID(),
              from: callingSessionId,
              fromAgent: senderState?.agentName ?? callingSessionId,
              to: existingSession,
              text: `[Delegated Task] ${args.task}${args.context ? `\n\nContext: ${args.context}` : ""}`,
              priority: "urgent",
              timestamp: new Date().toISOString(),
              read: false,
            });
            return {
              content: [{
                type: "text" as const,
                text: JSON.stringify({ delegated: true, method: "inbox", sessionId: existingSession }),
              }],
            };
          }
          // Check remote peers before giving up
          const remotePeer = ctx.peerRegistry.findAgentOwner(args.to_agent);
          if (remotePeer) {
            try {
              if (!ctx.relayClient.isConnected(remotePeer.peer.name)) {
                await ctx.relayClient.connect(remotePeer.peer.name, remotePeer.peer.endpoint);
              }
              const result = await ctx.relayClient.sendCommand(remotePeer.peer.name, {
                type: "delegate.task",
                sessionId: callingSessionId,
                toAgent: args.to_agent,
                task: args.task,
                context: args.context,
                waitForResult: args.wait_for_result ?? false,
              });
              return {
                content: [{
                  type: "text" as const,
                  text: JSON.stringify({ delegated: true, method: "remote_relay", peer: remotePeer.peer.name, result }),
                }],
              };
            } catch (err: any) {
              return {
                content: [{
                  type: "text" as const,
                  text: JSON.stringify({ error: "remote_relay_failed", peer: remotePeer.peer.name, message: err.message }),
                }],
              };
            }
          }
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "agent_not_found", agent: args.to_agent, hint: "Use peer_list_agents to see available agents" }),
            }],
          };
        }

        const prompt = args.context
          ? `${args.task}\n\n## Context\n${args.context}`
          : args.task;

        const senderState = ctx.sessions.get(callingSessionId);
        const waitForResult = args.wait_for_result ?? false;

        ctx.broadcast({
          type: "peer.delegate",
          from: senderState?.agentName ?? callingSessionId,
          to: args.to_agent,
          task: args.task,
        });

        const delegateSessionId = randomUUID();
        try {
          const result = await ctx.spawnSession(
            delegateSessionId,
            config,
            prompt,
            waitForResult,
          );
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({
                delegated: true,
                method: "spawned",
                sessionId: result.sessionId,
                waitedForResult: waitForResult,
                result: result.result,
              }),
            }],
          };
        } catch (err: any) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "delegation_failed", message: err.message }),
            }],
          };
        }
      },
    ),
  ];
}

function resolveAgentId(ctx: ToolContext, nameOrId: string): string | undefined {
  if (ctx.sessions.get(nameOrId)) return nameOrId;

  const sessions = ctx.sessions.list();
  const match = sessions.find(
    (s) => s.agentName.toLowerCase() === nameOrId.toLowerCase(),
  );
  return match?.id;
}
