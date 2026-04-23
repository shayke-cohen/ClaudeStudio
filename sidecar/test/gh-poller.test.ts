import { describe, it, expect, beforeEach, mock, spyOn } from "bun:test";
import { mkdtempSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

// Mock gh-cli before importing GHPoller so the real `gh` binary isn't invoked
const mockRunGh = mock(async (args: string[]): Promise<string> => {
  if (args.includes("issue") && args.includes("list")) return "[]";
  if (args.includes("view")) return JSON.stringify({ comments: [] });
  return "";
});

mock.module("../src/gh-cli.js", () => ({ runGh: mockRunGh }));

const { GHPoller } = await import("../src/gh-poller.js");

/** Create a fresh GHPoller with an isolated temp state dir per test */
function freshPoller(): InstanceType<typeof GHPoller> {
  const dir = mkdtempSync(join(tmpdir(), "odyssey-test-"));
  process.env.ODYSSEY_DATA_DIR = dir;
  return new GHPoller();
}

const defaultConfig = {
  inboxRepo: "testuser/odyssey-inbox",
  projectRepos: [],
  trustedUsers: ["testuser"],
  intervalSeconds: 3600,
};

function makeIssue(overrides: {
  number?: number;
  title?: string;
  body?: string;
  url?: string;
  labels?: string[];
  author?: string;
  createdAt?: string;
} = {}): any {
  return {
    number: overrides.number ?? 1,
    title: overrides.title ?? "Test issue",
    body: overrides.body ?? "",
    url: overrides.url ?? "https://github.com/testuser/odyssey-inbox/issues/1",
    labels: (overrides.labels ?? ["odyssey:agent:researcher"]).map((name) => ({ name })),
    author: { login: overrides.author ?? "testuser" },
    createdAt: overrides.createdAt ?? new Date().toISOString(),
  };
}

function makeCtx(overrides: { broadcast?: (ev: any) => void } = {}): any {
  return {
    broadcast: overrides.broadcast ?? (() => {}),
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
    spawnSession: async () => ({ sessionId: "test" }),
  };
}

describe("GHPoller — inbox issue filtering", () => {
  it("skips issues already in processedIssues", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string) { routerCalled.push({ issue, repo }); },
    });

    (poller as any).state.processedIssues["testuser/odyssey-inbox#1"] = new Date().toISOString();
    mockRunGh.mockImplementation(async () => JSON.stringify([makeIssue({ number: 1 })]));

    await (poller as any).fetchNewInboxIssues("testuser/odyssey-inbox", ["testuser"], makeCtx());
    expect(routerCalled).toHaveLength(0);
  });

  it("skips issues from untrusted authors", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string) { routerCalled.push({ issue, repo }); },
    });

    mockRunGh.mockImplementation(async () =>
      JSON.stringify([makeIssue({ author: "unknown-hacker" })])
    );

    await (poller as any).fetchNewInboxIssues("testuser/odyssey-inbox", ["testuser"], makeCtx());
    expect(routerCalled).toHaveLength(0);
  });

  it("skips inbox issues with no odyssey routing label", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string) { routerCalled.push({ issue, repo }); },
    });

    mockRunGh.mockImplementation(async () =>
      JSON.stringify([makeIssue({ labels: ["bug", "help wanted"] })])
    );

    await (poller as any).fetchNewInboxIssues("testuser/odyssey-inbox", ["testuser"], makeCtx());
    expect(routerCalled).toHaveLength(0);
  });

  it("calls router for new qualifying inbox issues", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string) { routerCalled.push({ issue, repo }); },
    });

    mockRunGh.mockImplementation(async () =>
      JSON.stringify([makeIssue({ labels: ["odyssey:agent:researcher"] })])
    );

    await (poller as any).fetchNewInboxIssues("testuser/odyssey-inbox", ["testuser"], makeCtx());
    expect(routerCalled).toHaveLength(1);
    expect(routerCalled[0].repo).toBe("testuser/odyssey-inbox");
  });
});

describe("GHPoller — project issue routing", () => {
  it("auto-routes project-repo issues with odyssey trigger label", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string, defaultAgentName: string | null) {
        routerCalled.push({ issue, repo, defaultAgentName });
      },
    });

    mockRunGh.mockImplementation(async () =>
      JSON.stringify([makeIssue({ labels: ["odyssey"], number: 5 })])
    );

    await (poller as any).fetchNewProjectIssues(
      { repo: "testuser/my-app", defaultAgentName: "developer", trustedUsers: ["testuser"] },
      makeCtx(),
    );

    expect(routerCalled).toHaveLength(1);
    expect(routerCalled[0].defaultAgentName).toBe("developer");
  });

  it("skips project-repo issues without odyssey trigger label", async () => {
    const poller = freshPoller();
    const routerCalled: any[] = [];
    poller.setRouter({
      async handleNewIssue(issue: any, repo: string) { routerCalled.push(issue); },
    });

    mockRunGh.mockImplementation(async () =>
      JSON.stringify([makeIssue({ labels: ["bug"] })])
    );

    await (poller as any).fetchNewProjectIssues(
      { repo: "testuser/my-app", defaultAgentName: "developer", trustedUsers: ["testuser"] },
      makeCtx(),
    );

    expect(routerCalled).toHaveLength(0);
  });
});

describe("GHPoller — active issue tracking", () => {
  it("trackIssue adds to activeIssues", () => {
    const poller = freshPoller();
    poller.trackIssue("testuser/odyssey-inbox", 42, "conv-123", "https://github.com/testuser/odyssey-inbox/issues/42");
    const active = (poller as any).state.activeIssues as any[];
    expect(active.some((i: any) => i.number === 42)).toBe(true);
  });

  it("closeIssue removes from activeIssues", () => {
    const poller = freshPoller();
    poller.trackIssue("testuser/odyssey-inbox", 42, "conv-123", "https://github.com/testuser/odyssey-inbox/issues/42");
    poller.closeIssue("testuser/odyssey-inbox", 42);
    const active = (poller as any).state.activeIssues as any[];
    expect(active.some((i: any) => i.number === 42)).toBe(false);
  });
});

describe("GHPoller — comment deduplication", () => {
  it("does not broadcast comments older than lastCommentAt", async () => {
    const poller = freshPoller();
    const broadcasts: any[] = [];
    const ctx = makeCtx({ broadcast: (ev) => broadcasts.push(ev) });

    const past = new Date(Date.now() - 60_000).toISOString();
    const older = new Date(Date.now() - 120_000).toISOString();

    poller.trackIssue("testuser/odyssey-inbox", 1, "conv-id", "https://github.com/testuser/odyssey-inbox/issues/1");
    const active = (poller as any).state.activeIssues as any[];
    active[0].lastCommentAt = past;

    mockRunGh.mockImplementation(async () =>
      JSON.stringify({ comments: [{ id: 1, body: "old", author: { login: "testuser" }, createdAt: older }] })
    );

    await (poller as any).pollActiveIssueComments(["testuser"], ctx);
    expect(broadcasts).toHaveLength(0);
  });

  it("broadcasts new comments from trusted users", async () => {
    const poller = freshPoller();
    const broadcasts: any[] = [];
    const ctx = makeCtx({ broadcast: (ev) => broadcasts.push(ev) });

    const past = new Date(Date.now() - 60_000).toISOString();
    const future = new Date(Date.now() + 5_000).toISOString();

    poller.trackIssue("testuser/odyssey-inbox", 1, "conv-id", "https://github.com/testuser/odyssey-inbox/issues/1");
    const active = (poller as any).state.activeIssues as any[];
    active[0].lastCommentAt = past;

    mockRunGh.mockImplementation(async () =>
      JSON.stringify({ comments: [{ id: 2, body: "new comment", author: { login: "testuser" }, createdAt: future }] })
    );

    await (poller as any).pollActiveIssueComments(["testuser"], ctx);
    expect(broadcasts).toHaveLength(1);
    expect(broadcasts[0].type).toBe("gh.issue.comment");
  });
});
