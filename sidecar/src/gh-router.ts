import { logger } from "./logger.js";
import { runGh } from "./gh-cli.js";
import type { ToolContext } from "./tools/tool-context.js";

interface GHIssue {
  number: number;
  title: string;
  body: string;
  url: string;
  labels: Array<{ name: string }>;
  author: { login: string };
}

type RouteTarget =
  | { kind: "agent"; name: string }
  | { kind: "group"; name: string }
  | null;

export class GHRouter {
  private poller?: import("./gh-poller.js").GHPoller;

  setPoller(poller: import("./gh-poller.js").GHPoller): void {
    this.poller = poller;
  }

  /**
   * Called by GHPoller when a new qualifying issue is found.
   * @param issue The GitHub issue
   * @param repo "owner/repo"
   * @param defaultAgentName For project repos — agent name to use if no routing label. null for inbox.
   */
  async handleNewIssue(
    issue: GHIssue,
    repo: string,
    defaultAgentName: string | null,
    ctx: ToolContext,
  ): Promise<void> {
    logger.info("github", "Handling new issue", { repo, number: issue.number, title: issue.title });

    // Add odyssey:queued label and post pickup comment
    await this.setLabel(repo, issue.number, "odyssey:queued");
    await this.postStatusComment(repo, issue.number,
      `🤖 **Odyssey** picked up this issue and is routing it...`);

    const target = this.parseRouting(issue, defaultAgentName);

    if (!target) {
      logger.warn("github", "No routing target found", { repo, number: issue.number });
      await this.setLabel(repo, issue.number, "odyssey:failed", "odyssey:queued");
      await this.postStatusComment(repo, issue.number,
        `❌ **Odyssey** could not route this issue — no matching agent or group found.\n\n` +
        `Add a label like \`odyssey:agent:my-agent\` or mention \`@agent-name\` in the issue body.`);
      return;
    }

    // Look up agent config from registered definitions
    const agentName = target.name;
    const agentConfig = ctx.agentDefinitions.get(agentName);

    if (!agentConfig) {
      logger.warn("github", "Agent not found in registry", { agentName });
      await this.setLabel(repo, issue.number, "odyssey:failed", "odyssey:queued");
      await this.postStatusComment(repo, issue.number,
        `❌ **Odyssey** could not find agent \`${agentName}\` in the registry.`);
      return;
    }

    // Create session and conversation
    const conversationId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();

    await this.setLabel(repo, issue.number, "odyssey:in-progress", "odyssey:queued");
    await this.postStatusComment(repo, issue.number,
      `⚡ **Odyssey** is working on this with **${agentName}**...`);

    // Broadcast the triggered event to Swift so it creates the SwiftData thread
    ctx.broadcast({
      type: "gh.issue.triggered",
      issueUrl: issue.url,
      issueNumber: issue.number,
      repo,
      title: issue.title,
      conversationId,
    });

    // Track it in the poller so incoming comments get relayed
    this.poller?.trackIssue(repo, issue.number, conversationId, issue.url);

    // Spawn the agent session
    try {
      const result = await ctx.spawnSession(
        sessionId,
        { ...agentConfig, workingDirectory: agentConfig.workingDirectory || process.env.HOME || "/" },
        `${issue.title}\n\n${issue.body}`,
        true,
      );

      const resultText = result.result ?? "(no output)";
      await this.setLabel(repo, issue.number, "odyssey:done", "odyssey:in-progress");
      await this.postStatusComment(repo, issue.number,
        `✅ **Odyssey** finished.\n\n${resultText}`);

      logger.info("github", "Issue handled successfully", { repo, number: issue.number });
    } catch (err) {
      logger.error("github", "Session failed for issue", { repo, number: issue.number, error: String(err) });
      await this.setLabel(repo, issue.number, "odyssey:failed", "odyssey:in-progress");
      await this.postStatusComment(repo, issue.number,
        `❌ **Odyssey** encountered an error:\n\n\`\`\`\n${String(err)}\n\`\`\``);
    }
  }

  /** Parse routing from labels and @mentions */
  parseRouting(issue: GHIssue, defaultAgentName: string | null): RouteTarget {
    // Check labels first
    for (const label of issue.labels) {
      if (label.name.startsWith("odyssey:agent:")) {
        const name = label.name.slice("odyssey:agent:".length).trim();
        if (name) return { kind: "agent", name };
      }
      if (label.name.startsWith("odyssey:group:")) {
        const name = label.name.slice("odyssey:group:".length).trim();
        if (name) return { kind: "group", name };
      }
    }

    // @mention fallback: scan title + body
    const text = `${issue.title} ${issue.body}`;
    const mentionMatch = text.match(/@([\w-]+)/);
    if (mentionMatch) {
      return { kind: "agent", name: mentionMatch[1] };
    }

    // Default agent for project repos
    if (defaultAgentName) {
      return { kind: "agent", name: defaultAgentName };
    }

    return null;
  }

  async postStatusComment(repo: string, issueNumber: number, body: string): Promise<void> {
    try {
      await runGh(["issue", "comment", String(issueNumber), "--repo", repo, "--body", body]);
    } catch (err) {
      logger.warn("github", "Failed to post comment", { repo, issueNumber, error: String(err) });
    }
  }

  async setLabel(repo: string, issueNumber: number, addLabel: string, removeLabel?: string): Promise<void> {
    try {
      await runGh(["issue", "edit", String(issueNumber), "--repo", repo, "--add-label", addLabel]);
    } catch (err) {
      logger.warn("github", "Failed to add label", { repo, issueNumber, addLabel, error: String(err) });
    }
    if (removeLabel) {
      try {
        await runGh(["issue", "edit", String(issueNumber), "--repo", repo, "--remove-label", removeLabel]);
      } catch (err) {
        logger.warn("github", "Failed to remove label", { repo, issueNumber, removeLabel, error: String(err) });
      }
    }
  }
}
