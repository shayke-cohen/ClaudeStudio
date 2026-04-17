import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";
import { logger } from "../logger.js";

export function createAskAgentTool(ctx: ToolContext, callingSessionId: string) {
  return [
    defineSharedTool(
      "ask_agent",
      "Ask another agent a question and wait for its answer. Use this when a question can be answered by a specific agent rather than requiring human input. The calling agent's session blocks until the target agent responds.",
      {
        question: z.string().describe("The question to ask the target agent"),
        to_agent: z
          .string()
          .describe(
            "Name of the agent to ask (e.g. 'Reviewer', 'PM'). The conversation's Auto-Answer mode may override this to route to a different agent.",
          ),
      },
      async (args) => {
        logger.info(
          "tools",
          `ask_agent invoked by ${callingSessionId}: asking "${args.to_agent}": "${args.question.substring(0, 80)}"`,
        );

        // Delegation mode may override to_agent (specific_agent/coordinator modes)
        const resolvedTargetName =
          ctx.delegation.resolveTarget(callingSessionId, args.to_agent) ?? args.to_agent;

        const targetConfig = ctx.agentDefinitions.get(resolvedTargetName);
        if (!targetConfig) {
          return createTextResult(
            {
              error: "agent_not_found",
              agent: resolvedTargetName,
              message: `No agent definition found for "${resolvedTargetName}". Cannot delegate question.`,
            },
            false,
          );
        }

        const questionId = randomUUID();
        ctx.broadcast({
          type: "agent.question.routing",
          sessionId: callingSessionId,
          questionId,
          targetAgentName: resolvedTargetName,
        });

        try {
          const delegateSessionId = randomUUID();
          const callerState = ctx.sessions.get(callingSessionId);
          const callerName = callerState?.agentName ?? "another agent";
          const prompt = `${callerName} has a question for you. Please answer concisely.\n\nQuestion: ${args.question}`;

          const { result: agentAnswer } = await ctx.spawnSession(
            delegateSessionId,
            targetConfig,
            prompt,
            true,
          );

          ctx.broadcast({
            type: "agent.question.resolved",
            sessionId: callingSessionId,
            questionId,
            answeredBy: resolvedTargetName,
            isFallback: false,
          });

          return createTextResult({
            answer: agentAnswer ?? "[Agent provided no answer.]",
          });
        } catch (err: any) {
          return createTextResult(
            { error: "delegation_failed", message: err.message },
            false,
          );
        }
      },
    ),
  ];
}
