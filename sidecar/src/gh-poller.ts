import { join } from "path";
import { homedir } from "os";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { logger } from "./logger.js";
import { runGh } from "./gh-cli.js";
import type { ToolContext } from "./tools/tool-context.js";
import type { GHProjectRepo } from "./types.js";

export interface GHPollerConfig {
  inboxRepo: string;           // "owner/repo"
  projectRepos: GHProjectRepo[];
  trustedUsers: string[];
  intervalSeconds: number;
}

interface GHIssue {
  number: number;
  title: string;
  body: string;
  url: string;
  labels: Array<{ name: string }>;
  author: { login: string };
  createdAt: string;
}

interface GHComment {
  id: number;
  body: string;
  author: { login: string };
  createdAt: string;
}

interface ActiveIssue {
  repo: string;
  number: number;
  conversationId: string;
  issueUrl: string;
  lastCommentAt: string;  // ISO timestamp
}

interface PollerState {
  processedIssues: Record<string, string>; // "owner/repo#N" → ISO timestamp
  activeIssues: ActiveIssue[];
  lastPollAt: string;
}

interface IssueHandler {
  handleNewIssue(issue: any, repo: string, defaultAgentName: string | null, ctx: any, workingDirectory?: string): Promise<void>;
}

export class GHPoller {
  private timer?: ReturnType<typeof setInterval>;
  private state: PollerState;
  private statePath: string;
  private router?: IssueHandler;
  private pollRunning = false;

  constructor() {
    const baseDir = process.env.ODYSSEY_DATA_DIR ?? join(homedir(), ".odyssey");
    if (!existsSync(baseDir)) mkdirSync(baseDir, { recursive: true });
    this.statePath = join(baseDir, "gh-poller-state.json");
    this.state = this.loadState();
  }

  setRouter(router: IssueHandler): void {
    this.router = router;
  }

  start(config: GHPollerConfig, ctx: ToolContext): void {
    this.stop();
    logger.info("github", "GHPoller starting", { inboxRepo: config.inboxRepo, intervalSeconds: config.intervalSeconds });
    this.timer = setInterval(() => this.poll(config, ctx).catch(err => {
      logger.error("github", "Poll error", { error: String(err) });
    }), config.intervalSeconds * 1000);
    // Poll immediately on start
    this.poll(config, ctx).catch(err => {
      logger.error("github", "Initial poll error", { error: String(err) });
    });
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  /** Remove a completed/failed issue from activeIssues so it stops being polled */
  closeIssue(repo: string, issueNumber: number): void {
    this.state.activeIssues = this.state.activeIssues.filter(
      a => !(a.repo === repo && a.number === issueNumber)
    );
    this.saveState();
  }

  /** Register a newly-created Odyssey thread so incoming comments get relayed */
  trackIssue(repo: string, issueNumber: number, conversationId: string, issueUrl: string): void {
    const key = `${repo}#${issueNumber}`;
    this.state.processedIssues[key] = new Date().toISOString();
    this.state.activeIssues.push({
      repo,
      number: issueNumber,
      conversationId,
      issueUrl,
      lastCommentAt: new Date().toISOString(),
    });
    this.saveState();
  }

  private async poll(config: GHPollerConfig, ctx: ToolContext): Promise<void> {
    if (this.pollRunning) {
      logger.debug("github", "Poll skipped — previous still running");
      return;
    }
    this.pollRunning = true;
    try {
      logger.debug("github", "Polling", { inboxRepo: config.inboxRepo });

      // 1. Fetch new issues from inbox repo
      if (config.inboxRepo) {
        await this.fetchNewInboxIssues(config.inboxRepo, config.trustedUsers, ctx);
      }

      // 2. Fetch new issues from project repos
      for (const projectRepo of config.projectRepos) {
        await this.fetchNewProjectIssues(projectRepo, ctx);
      }

      // 3. Check for new comments on active issues
      await this.pollActiveIssueComments(config.trustedUsers, ctx);

      this.state.lastPollAt = new Date().toISOString();
      this.saveState();
    } finally {
      this.pollRunning = false;
    }
  }

  private async fetchNewInboxIssues(repo: string, trustedUsers: string[], ctx: ToolContext): Promise<void> {
    let issues: GHIssue[];
    try {
      issues = await this.ghIssueList(repo);
    } catch (err) {
      logger.warn("github", "Failed to list inbox issues", { repo, error: String(err) });
      return;
    }

    for (const issue of issues) {
      const key = `${repo}#${issue.number}`;
      if (this.state.processedIssues[key]) continue;
      // Empty trustedUsers means all authors are trusted (repo owner scenario)
      if (trustedUsers.length > 0 && !trustedUsers.includes(issue.author.login)) {
        logger.debug("github", "Skipping issue from untrusted user", { repo, number: issue.number, author: issue.author.login });
        continue;
      }
      // Must have a routing label (odyssey:agent:* or odyssey:group:*)
      const hasRoutingLabel = issue.labels.some(l =>
        l.name.startsWith("odyssey:agent:") || l.name.startsWith("odyssey:group:")
      );
      if (!hasRoutingLabel) {
        logger.debug("github", "Skipping inbox issue with no routing label", { repo, number: issue.number });
        continue;
      }
      // Mark as processed immediately to prevent duplicate handling
      this.state.processedIssues[key] = new Date().toISOString();
      this.saveState();

      if (this.router) {
        await this.router.handleNewIssue(issue, repo, null, ctx);
      }
    }
  }

  private async fetchNewProjectIssues(projectRepo: GHProjectRepo, ctx: ToolContext): Promise<void> {
    let issues: GHIssue[];
    try {
      issues = await this.ghIssueList(projectRepo.repo);
    } catch (err) {
      logger.warn("github", "Failed to list project issues", { repo: projectRepo.repo, error: String(err) });
      return;
    }

    for (const issue of issues) {
      const key = `${projectRepo.repo}#${issue.number}`;
      if (this.state.processedIssues[key]) continue;
      // Empty trustedUsers means all authors are trusted (for public/open repos)
      if (projectRepo.trustedUsers.length > 0 && !projectRepo.trustedUsers.includes(issue.author.login)) {
        continue;
      }
      // Project repos: trigger label "odyssey" required
      const hasTriggerLabel = issue.labels.some(l => l.name === "odyssey");
      if (!hasTriggerLabel) continue;

      this.state.processedIssues[key] = new Date().toISOString();
      this.saveState();

      if (this.router) {
        await this.router.handleNewIssue(issue, projectRepo.repo, projectRepo.defaultAgentName ?? null, ctx, projectRepo.workingDirectory);
      }
    }
  }

  private async pollActiveIssueComments(trustedUsers: string[], ctx: ToolContext): Promise<void> {
    for (const active of this.state.activeIssues) {
      const since = active.lastCommentAt;
      let comments: GHComment[];
      try {
        comments = await this.ghIssueComments(active.repo, active.number, since);
      } catch (err) {
        logger.warn("github", "Failed to fetch comments", { repo: active.repo, number: active.number, error: String(err) });
        continue;
      }
      for (const comment of comments) {
        if (!trustedUsers.includes(comment.author.login)) continue;
        // Emit event to Swift so it can relay into the Odyssey thread
        ctx.broadcast({
          type: "gh.issue.comment",
          issueUrl: active.issueUrl,
          commentBody: comment.body,
          author: comment.author.login,
          conversationId: active.conversationId,
        });
        active.lastCommentAt = comment.createdAt;
      }
      // Save progress after each active issue so a crash doesn't lose state
      this.saveState();
    }
  }

  /** Run `gh issue list` and return open issues */
  private async ghIssueList(repo: string): Promise<GHIssue[]> {
    const output = await runGh(["issue", "list", "--repo", repo, "--state", "open", "--limit", "50",
      "--json", "number,title,body,url,labels,author,createdAt"]);
    return JSON.parse(output) as GHIssue[];
  }

  /** Run `gh issue view` and get comments since a given ISO timestamp */
  private async ghIssueComments(repo: string, issueNumber: number, since: string): Promise<GHComment[]> {
    const output = await runGh(["issue", "view", String(issueNumber), "--repo", repo, "--json", "comments"]);
    const data = JSON.parse(output) as { comments: GHComment[] };
    const sinceDate = new Date(since);
    return data.comments.filter(c => new Date(c.createdAt) > sinceDate);
  }

  private loadState(): PollerState {
    if (existsSync(this.statePath)) {
      try {
        return JSON.parse(readFileSync(this.statePath, "utf8")) as PollerState;
      } catch {
        // corrupt state — start fresh
      }
    }
    return { processedIssues: {}, activeIssues: [], lastPollAt: new Date(0).toISOString() };
  }

  private saveState(): void {
    writeFileSync(this.statePath, JSON.stringify(this.state, null, 2), "utf8");
  }
}

