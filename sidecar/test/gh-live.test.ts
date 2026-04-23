/**
 * Live GitHub integration test.
 *
 * Requires:
 *   - `gh` CLI authenticated
 *   - An `odyssey-inbox` repo in the authed user's account
 *   - GH_LIVE_TEST=1 environment variable set
 *
 * Run with:
 *   GH_LIVE_TEST=1 bun test sidecar/test/gh-live.test.ts
 */

import { describe, it, expect, beforeAll, afterAll } from "bun:test";
import { runGh } from "../src/gh-cli.js";
import { GHPoller } from "../src/gh-poller.js";
import { GHRouter } from "../src/gh-router.js";

const SKIP = !process.env.GH_LIVE_TEST;

function makeCtx(broadcasts: any[]): any {
  return {
    broadcast: (ev: any) => broadcasts.push(ev),
    agentDefinitions: new Map(),
    sessions: {} as any,
    messages: {} as any,
    channels: {} as any,
    blackboard: {} as any,
    workspaces: {} as any,
    peerRegistry: {} as any,
    connectors: {} as any,
    relayClient: {} as any,
    conversationStore: {} as any,
    projectStore: {} as any,
    nostrTransport: {} as any,
    delegation: {} as any,
    taskBoard: {} as any,
    pendingBrowserResults: new Map(),
    pendingBrowserBlocking: new Map(),
    spawnSession: async (sessionId: string) => ({ sessionId, result: "Live test complete" }),
  };
}

describe("GitHub live integration", () => {
  let inboxRepo = "";
  let createdIssueNumber = 0;

  beforeAll(async () => {
    if (SKIP) return;
    // Determine authenticated user and inbox repo
    const whoami = await runGh(["auth", "status", "--json", "user", "-q", ".user.login"]).catch(() => "");
    if (!whoami) throw new Error("Not authenticated — run `gh auth login` first");
    inboxRepo = `${whoami.trim()}/odyssey-inbox`;
  });

  afterAll(async () => {
    if (SKIP || !createdIssueNumber || !inboxRepo) return;
    // Clean up: close the test issue
    await runGh(["issue", "close", String(createdIssueNumber), "--repo", inboxRepo]).catch(() => {});
  });

  it("creates a live issue, polls it, and emits gh.issue.triggered", async () => {
    if (SKIP) {
      console.log("Skipped — set GH_LIVE_TEST=1 to run live tests");
      return;
    }

    // 1. Create a real issue with odyssey:agent:researcher label
    const issueUrl = await runGh([
      "issue", "create",
      "--repo", inboxRepo,
      "--title", "[Odyssey live test] automated test issue",
      "--body", "This issue was created by the automated live test suite.",
      "--label", "odyssey:agent:researcher",
    ]);
    const match = issueUrl.match(/\/issues\/(\d+)/);
    expect(match).not.toBeNull();
    createdIssueNumber = parseInt(match![1], 10);
    expect(createdIssueNumber).toBeGreaterThan(0);

    // 2. Register a mock agent config so the router can find "researcher"
    const broadcasts: any[] = [];
    const ctx = makeCtx(broadcasts);
    ctx.agentDefinitions.set("researcher", {
      name: "researcher",
      systemPrompt: "You are a researcher.",
    });

    // 3. Set up poller + router, run one poll cycle
    const poller = new GHPoller();
    const router = new GHRouter();
    poller.setRouter(router);
    router.setPoller(poller);

    const config = {
      inboxRepo,
      projectRepos: [],
      trustedUsers: [inboxRepo.split("/")[0]],
      intervalSeconds: 3600,
    };

    await (poller as any).fetchNewInboxIssues(inboxRepo, config.trustedUsers, ctx);

    // 4. Verify gh.issue.triggered was broadcast
    const triggered = broadcasts.find((ev) => ev.type === "gh.issue.triggered");
    expect(triggered).toBeDefined();
    expect(triggered.issueNumber).toBe(createdIssueNumber);
    expect(triggered.repo).toBe(inboxRepo);

    // 5. Verify the issue has odyssey:in-progress label applied
    const issueJson = await runGh(["issue", "view", String(createdIssueNumber), "--repo", inboxRepo, "--json", "labels"]);
    const { labels } = JSON.parse(issueJson) as { labels: { name: string }[] };
    const labelNames = labels.map((l) => l.name);
    expect(labelNames).toContain("odyssey:in-progress");
  });
});
