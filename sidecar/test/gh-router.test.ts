import { describe, it, expect, mock } from "bun:test";

// Mock runGh so no real CLI calls are made
const ghCalls: string[][] = [];
const mockRunGh = mock(async (args: string[]): Promise<string> => {
  ghCalls.push(args);
  return "";
});
mock.module("../src/gh-cli.js", () => ({ runGh: mockRunGh }));

const { GHRouter } = await import("../src/gh-router.js");

function makeIssue(overrides: {
  number?: number;
  title?: string;
  body?: string;
  url?: string;
  labels?: string[];
  author?: string;
} = {}): any {
  return {
    number: overrides.number ?? 1,
    title: overrides.title ?? "Test issue",
    body: overrides.body ?? "",
    url: overrides.url ?? "https://github.com/testuser/odyssey-inbox/issues/1",
    labels: (overrides.labels ?? []).map((name) => ({ name })),
    author: { login: overrides.author ?? "testuser" },
  };
}

function makeCtx(overrides: Partial<{ broadcast: (ev: any) => void; agentDefinitions: Map<string, any>; spawnSession: any }> = {}): any {
  return {
    broadcast: overrides.broadcast ?? (() => {}),
    agentDefinitions: overrides.agentDefinitions ?? new Map(),
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
    spawnSession: overrides.spawnSession ?? (async () => ({ sessionId: "sess-1", result: "done" })),
  };
}

// ── parseRouting ──────────────────────────────────────────────────────────────

describe("GHRouter.parseRouting", () => {
  const router = new GHRouter();

  it("returns agent target from odyssey:agent:* label", () => {
    const result = (router as any).parseRouting(
      makeIssue({ labels: ["odyssey:agent:researcher"] }),
      null,
    );
    expect(result).toEqual({ kind: "agent", name: "researcher" });
  });

  it("returns group target from odyssey:group:* label", () => {
    const result = (router as any).parseRouting(
      makeIssue({ labels: ["odyssey:group:devteam"] }),
      null,
    );
    expect(result).toEqual({ kind: "group", name: "devteam" });
  });

  it("agent label takes priority over group label", () => {
    const result = (router as any).parseRouting(
      makeIssue({ labels: ["odyssey:group:devteam", "odyssey:agent:researcher"] }),
      null,
    );
    expect(result).toEqual({ kind: "agent", name: "researcher" });
  });

  it("falls back to @mention when no label present", () => {
    const result = (router as any).parseRouting(
      makeIssue({ title: "Hey @developer fix this", body: "" }),
      null,
    );
    expect(result).toEqual({ kind: "agent", name: "developer" });
  });

  it("falls back to @mention in body", () => {
    const result = (router as any).parseRouting(
      makeIssue({ body: "Please have @researcher look at this" }),
      null,
    );
    expect(result).toEqual({ kind: "agent", name: "researcher" });
  });

  it("uses defaultAgentName when no label or mention", () => {
    const result = (router as any).parseRouting(
      makeIssue({ labels: [] }),
      "default-agent",
    );
    expect(result).toEqual({ kind: "agent", name: "default-agent" });
  });

  it("returns null when no routing info found and no default", () => {
    const result = (router as any).parseRouting(
      makeIssue({ labels: [], title: "No routing here", body: "Nothing" }),
      null,
    );
    expect(result).toBeNull();
  });
});

// ── handleNewIssue ─────────────────────────────────────────────────────────────

describe("GHRouter.handleNewIssue", () => {
  it("posts failed comment and sets failed label when routing is null", async () => {
    ghCalls.length = 0;
    const router = new GHRouter();
    const broadcasts: any[] = [];
    const ctx = makeCtx({ broadcast: (ev) => broadcasts.push(ev) });

    await router.handleNewIssue(
      makeIssue({ labels: [], title: "Random issue", body: "" }),
      "testuser/odyssey-inbox",
      null,
      ctx,
    );

    const labelCalls = ghCalls.filter((args) => args.includes("edit"));
    const failedLabel = labelCalls.some((args) => args.includes("odyssey:failed"));
    expect(failedLabel).toBe(true);
  });

  it("posts queued comment and spawns session when agent is registered", async () => {
    ghCalls.length = 0;
    const router = new GHRouter();
    const tracker = { tracked: [] as any[], closed: [] as any[] };
    router.setPoller({
      trackIssue(repo: string, num: number, convId: string, url: string) {
        tracker.tracked.push({ repo, num });
      },
      closeIssue(repo: string, num: number) {
        tracker.closed.push({ repo, num });
      },
    });

    const agentConfig = { name: "researcher", systemPrompt: "research" };
    const broadcasts: any[] = [];
    const ctx = makeCtx({
      broadcast: (ev) => broadcasts.push(ev),
      agentDefinitions: new Map([["researcher", agentConfig]]),
      spawnSession: async (sessionId: string) => ({ sessionId, result: "Research complete!" }),
    });

    await router.handleNewIssue(
      makeIssue({ labels: ["odyssey:agent:researcher"] }),
      "testuser/odyssey-inbox",
      null,
      ctx,
    );

    // Should have broadcasted gh.issue.triggered
    const triggered = broadcasts.find((ev) => ev.type === "gh.issue.triggered");
    expect(triggered).toBeDefined();

    // Issue should have been tracked
    expect(tracker.tracked.some((t) => t.num === 1)).toBe(true);
    // Issue should have been closed after completion
    expect(tracker.closed.some((t) => t.num === 1)).toBe(true);
  });
});

// ── create_github_issue agent tool ────────────────────────────────────────────

describe("createGitHubTools — create_github_issue", () => {
  it("calls gh issue create with correct args and broadcasts event", async () => {
    // Dynamically import to get mocked version
    const { createGitHubTools } = await import("../src/tools/github-tools.js");
    const issueUrl = "https://github.com/testuser/odyssey-inbox/issues/7";

    const capturedCalls: string[][] = [];
    mockRunGh.mockReset();
    mockRunGh.mockImplementation(async (args: string[]) => {
      capturedCalls.push(args);
      if (args[0] === "issue" && args[1] === "create") return issueUrl;
      return "";
    });

    const broadcasts: any[] = [];
    const ctx = makeCtx({
      broadcast: (ev) => broadcasts.push(ev),
      ghPollerConfig: { inboxRepo: "testuser/odyssey-inbox" },
    } as any);

    const tools = createGitHubTools(ctx);
    const tool = tools.find((t) => t.name === "create_github_issue");
    expect(tool).toBeDefined();

    await tool!.execute(
      { title: "Fix bug", body: "Details here", repo: "testuser/odyssey-inbox" },
      { sessionId: "sess-abc", conversationId: "conv-xyz" },
    );

    const ghCreate = capturedCalls.find((args) => args[0] === "issue" && args[1] === "create");
    expect(ghCreate).toBeDefined();
    expect(ghCreate!).toContain("testuser/odyssey-inbox");

    const created = broadcasts.find((ev: any) => ev.type === "gh.issue.created");
    expect(created).toBeDefined();
    expect(created.issueUrl).toBe(issueUrl);
  });
});
