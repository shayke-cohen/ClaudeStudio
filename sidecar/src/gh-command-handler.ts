import { runGh } from "./gh-cli.js";
import { logger } from "./logger.js";

export interface GHCommandContext {
  broadcast: (event: object) => void;
}

export async function dispatchGHCommand(
  command: { type: string; repo?: string; number?: number },
  ctx: GHCommandContext
): Promise<void> {
  if (command.type === "gh.issue.close") {
    if (!command.repo || command.number === undefined) return;
    try {
      await runGh(["issue", "close", String(command.number), "--repo", command.repo]);
      ctx.broadcast({ type: "gh.issue.closed", repo: command.repo, number: command.number });
    } catch (err) {
      logger.error("github", "gh.issue.close failed", { error: String(err) });
    }
  }
}
