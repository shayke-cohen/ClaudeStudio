import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";

export function createChatTools(ctx: ToolContext, callingSessionId: string) {
  return [
    tool(
      "peer_chat_start",
      "Start a blocking conversation with another agent. Sends the first message and BLOCKS until the other agent replies. Returns the reply or {closed: true} if the conversation ends.",
      {
        to_agent: z.string().describe("Target agent name or session ID"),
        message: z.string().describe("Opening message"),
        topic: z.string().optional().describe("Conversation topic"),
      },
      async (args) => {
        const targetId = resolveAgentTarget(ctx, args.to_agent, callingSessionId);
        if (!targetId) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "agent_not_found", to: args.to_agent }),
            }],
          };
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const senderName = senderState?.agentName ?? callingSessionId;

        const channel = ctx.channels.create(
          callingSessionId,
          senderName,
          targetId,
          args.message,
          args.topic,
        );

        ctx.broadcast({
          type: "peer.chat",
          channelId: channel.id,
          from: senderName,
          message: args.message,
        });

        ctx.messages.push(targetId, {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderName,
          to: targetId,
          text: `[Chat Request] ${args.topic ?? "New conversation"}: ${args.message}`,
          channel: channel.id,
          priority: "urgent",
          timestamp: new Date().toISOString(),
          read: false,
        });

        const reply = await ctx.channels.waitForReply(channel.id, callingSessionId);
        if ("closed" in reply) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ closed: true, summary: reply.summary, channel_id: channel.id }),
            }],
          };
        }

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              channel_id: channel.id,
              reply: reply.text,
              from_agent: reply.fromAgent,
            }),
          }],
        };
      },
    ),

    tool(
      "peer_chat_reply",
      "Reply to an ongoing conversation. BLOCKS until the other participant responds or the conversation closes.",
      {
        channel_id: z.string().describe("Channel ID from peer_chat_start or peer_receive_messages"),
        message: z.string().describe("Reply message"),
      },
      async (args) => {
        const channel = ctx.channels.get(args.channel_id);
        if (!channel) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "channel_not_found", channel_id: args.channel_id }),
            }],
          };
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const senderName = senderState?.agentName ?? callingSessionId;

        const msg = ctx.channels.addMessage(args.channel_id, callingSessionId, senderName, args.message);
        if (!msg) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ closed: true, channel_id: args.channel_id }),
            }],
          };
        }

        ctx.broadcast({
          type: "peer.chat",
          channelId: args.channel_id,
          from: senderName,
          message: args.message,
        });

        const reply = await ctx.channels.waitForReply(args.channel_id, callingSessionId);
        if ("closed" in reply) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ closed: true, summary: reply.summary, channel_id: args.channel_id }),
            }],
          };
        }

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              channel_id: args.channel_id,
              reply: reply.text,
              from_agent: reply.fromAgent,
            }),
          }],
        };
      },
    ),

    tool(
      "peer_chat_listen",
      "Wait for an incoming chat request from another agent. BLOCKS until a request arrives or timeout.",
      {
        timeout_ms: z.number().optional().describe("Timeout in milliseconds (default: 30000)"),
      },
      async (args) => {
        const channel = await ctx.channels.waitForIncoming(
          callingSessionId,
          args.timeout_ms ?? 30000,
        );

        if (!channel) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ timeout: true, message: "No incoming chat requests within timeout" }),
            }],
          };
        }

        const lastMsg = channel.messages[channel.messages.length - 1];
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({
              channel_id: channel.id,
              from_agent: lastMsg.fromAgent,
              message: lastMsg.text,
              topic: channel.topic,
            }),
          }],
        };
      },
    ),

    tool(
      "peer_chat_close",
      "End a conversation. All participants waiting for replies will receive {closed: true}.",
      {
        channel_id: z.string().describe("Channel ID to close"),
        summary: z.string().optional().describe("Summary of the conversation outcome"),
      },
      async (args) => {
        ctx.channels.close(args.channel_id, args.summary);

        const senderState = ctx.sessions.get(callingSessionId);
        ctx.broadcast({
          type: "peer.chat",
          channelId: args.channel_id,
          from: senderState?.agentName ?? callingSessionId,
          message: `[closed] ${args.summary ?? "Conversation ended"}`,
        });

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ closed: true, channel_id: args.channel_id }),
          }],
        };
      },
    ),

    tool(
      "peer_chat_invite",
      "Invite another agent into an existing conversation (group chat).",
      {
        channel_id: z.string().describe("Channel ID of the existing conversation"),
        agent: z.string().describe("Agent name or session ID to invite"),
        context: z.string().optional().describe("Context to provide to the invited agent"),
      },
      async (args) => {
        const targetId = resolveAgentTarget(ctx, args.agent, callingSessionId);
        if (!targetId) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "agent_not_found", agent: args.agent }),
            }],
          };
        }

        const added = ctx.channels.addParticipant(args.channel_id, targetId);
        if (!added) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "channel_not_found_or_closed", channel_id: args.channel_id }),
            }],
          };
        }

        const senderState = ctx.sessions.get(callingSessionId);
        ctx.messages.push(targetId, {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          to: targetId,
          text: `[Chat Invite] You've been invited to channel ${args.channel_id}${args.context ? `: ${args.context}` : ""}`,
          channel: args.channel_id,
          priority: "urgent",
          timestamp: new Date().toISOString(),
          read: false,
        });

        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ invited: true, agent: args.agent, channel_id: args.channel_id }),
          }],
        };
      },
    ),
  ];
}

function resolveAgentTarget(
  ctx: ToolContext,
  nameOrId: string,
  excludeSessionId: string,
): string | undefined {
  if (ctx.sessions.get(nameOrId) && nameOrId !== excludeSessionId) return nameOrId;

  const sessions = ctx.sessions.list();
  const match = sessions.find(
    (s) => s.agentName.toLowerCase() === nameOrId.toLowerCase() && s.id !== excludeSessionId,
  );
  return match?.id;
}
