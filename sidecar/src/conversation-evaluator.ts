import type { SidecarEvent } from "./types.js";
import type { SessionManager } from "./session-manager.js";
import { logger } from "./logger.js";

type Broadcast = (event: SidecarEvent) => void;

type EvaluateCommand = {
  conversationId: string;
  goal?: string;
  coordinatorSessionId?: string;
  sessionIds?: string[];
};

const EVAL_PROMPT = (goal: string) =>
  `Evaluate whether the team achieved the goal.\nGoal: ${goal}\n\nReply with exactly two lines:\nSTATUS: COMPLETE | NEEDS_MORE | FAILED\nREASON: <one sentence>`;

const DEFAULT_GOAL = "based on the conversation above";

function majorityStatus(
  statuses: ("complete" | "needsMore" | "failed")[],
): "complete" | "needsMore" | "failed" {
  const counts: Record<string, number> = { complete: 0, needsMore: 0, failed: 0 };
  for (const s of statuses) counts[s]++;
  return (Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0]) as "complete" | "needsMore" | "failed";
}

export class ConversationEvaluator {
  constructor(private readonly sessionManager: SessionManager) {}

  async evaluate(cmd: EvaluateCommand, broadcast: Broadcast): Promise<void> {
    const { conversationId, goal, coordinatorSessionId, sessionIds = [] } = cmd;

    broadcast({ type: "conversation.idle", conversationId });

    const targetIds = coordinatorSessionId
      ? [coordinatorSessionId]
      : sessionIds.length > 0
        ? sessionIds
        : [];

    if (targetIds.length === 0) {
      logger.warn("evaluator", `No sessions to evaluate for conversation ${conversationId}`);
      broadcast({
        type: "conversation.idleResult",
        conversationId,
        status: "failed",
        reason: "No sessions available for evaluation",
      });
      return;
    }

    const prompt = EVAL_PROMPT(goal ?? DEFAULT_GOAL);
    const results: { status: "complete" | "needsMore" | "failed"; reason: string }[] = [];

    for (const sessionId of targetIds) {
      try {
        const result = await this.sessionManager.evaluateSession(sessionId, prompt);
        if (result) {
          results.push(result);
          logger.info("evaluator", `Session ${sessionId} eval: ${result.status} — ${result.reason}`);
        }
      } catch (err) {
        logger.error("evaluator", `Eval error for session ${sessionId}: ${String(err)}`);
      }
    }

    if (results.length === 0) {
      broadcast({
        type: "conversation.idleResult",
        conversationId,
        status: "failed",
        reason: "Evaluation could not complete",
      });
      return;
    }

    const status = results.length === 1 ? results[0].status : majorityStatus(results.map(r => r.status));
    const reason = results.map(r => r.reason).filter(Boolean).join(" | ");

    broadcast({ type: "conversation.idleResult", conversationId, status, reason });
  }
}
