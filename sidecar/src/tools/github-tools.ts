import { runGh } from "../gh-cli.js";
import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";
import { logger } from "../logger.js";

export function createGitHubTools(ctx: ToolContext) {
  return [
    defineSharedTool(
      "create_github_issue",
      "Create a GitHub issue in the inbox repo or a connected project repo. Use this to track tasks, bugs, or follow-up work on GitHub.",
      {
        title: z.string().describe("Issue title"),
        body: z.string().describe("Issue body (markdown supported)"),
        repo: z.string().optional().describe("Repository in 'owner/repo' format. Defaults to the configured inbox repo."),
        labels: z.array(z.string()).optional().describe("Labels to apply (e.g. ['bug', 'odyssey:agent:researcher'])"),
        linkToConversation: z.boolean().optional().describe("Whether to link this issue back to the current conversation (default: true)"),
      },
      async (args, extra: any) => {
        const sessionId = extra?.sessionId ?? "unknown";
        

        // Determine target repo
        const targetRepo = args.repo ?? ctx.ghPollerConfig?.inboxRepo ?? "";
        if (!targetRepo) {
          return createTextResult({ error: "no_repo", message: "No repo specified and no inbox repo configured. Pass 'repo' parameter." }, false);
        }

        try {
          const ghArgs = ["issue", "create", "--repo", targetRepo, "--title", args.title, "--body", args.body];
          for (const label of (args.labels ?? [])) {
            ghArgs.push("--label", label);
          }
          const output = await runGh(ghArgs);
          const issueUrl = output.trim();
          const issueMatch = issueUrl.match(/\/issues\/(\d+)$/);
          const issueNumber = issueMatch ? parseInt(issueMatch[1]) : 0;
          if (!issueMatch) {
            logger.warn("github", "create_github_issue: could not parse issue number from URL", { issueUrl });
          }

          // Broadcast so Swift links the conversation if requested.
          // In this codebase, conversationId == sessionId (session.create passes conversationId as sessionId).
          const linkToConversation = args.linkToConversation !== false;
          if (linkToConversation) {
            ctx.broadcast({
              type: "gh.issue.created",
              issueUrl,
              issueNumber,
              repo: targetRepo,
              conversationId: sessionId !== "unknown" ? sessionId : undefined,
            });
          }

          return createTextResult({ issueUrl, issueNumber, repo: targetRepo });
        } catch (err) {
          return createTextResult({ error: "gh_failed", message: String(err) }, false);
        }
      },
    ),
  ];
}
