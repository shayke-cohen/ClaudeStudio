import type {
  ApiContext,
  ApiErrorResponse,
  CreateSessionRequest,
  SendMessageRequest,
  ResumeSessionRequest,
  DelegateRequest,
  SendPeerMessageRequest,
  BroadcastRequest,
  AnswerQuestionRequest,
  RegisterWebhookRequest,
  SidecarEvent,
  AgentConfig,
} from "./types.js";
import { resolveQuestion, createQuestion, questionsBySession } from "./tools/ask-user-tool.js";
import { logger, getLogBuffer, type SidecarLogLevel } from "./logger.js";

// ─── Helpers ───

function apiError(error: string, message: string, status: number): Response {
  const body: ApiErrorResponse = { error, message, status };
  return Response.json(body, { status, headers: corsHeaders() });
}

function apiJson(data: unknown, status = 200): Response {
  return Response.json(data, { status, headers: corsHeaders() });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
  };
}

function clientIdentity(req: Request): string {
  return req.headers.get("X-Odyssey-Client")
    ?? req.headers.get("X-Odyssey-Client")
    ?? "rest-api";
}

async function parseBody<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw { error: "invalid_request", message: "Invalid or missing JSON body", status: 400 };
  }
}

/**
 * Route matcher: extracts path params from patterns like /api/v1/sessions/:id/messages
 */
function matchRoute(
  pattern: string,
  method: string,
  reqMethod: string,
  reqPath: string,
): Record<string, string> | null {
  if (reqMethod !== method) return null;

  const patternParts = pattern.split("/");
  const pathParts = reqPath.split("/");
  if (patternParts.length !== pathParts.length) return null;

  const params: Record<string, string> = {};
  for (let i = 0; i < patternParts.length; i++) {
    if (patternParts[i].startsWith(":")) {
      params[patternParts[i].slice(1)] = decodeURIComponent(pathParts[i]);
    } else if (patternParts[i] !== pathParts[i]) {
      return null;
    }
  }
  return params;
}

// ─── Router ───

/**
 * Handle REST API requests under /api/v1/.
 * Returns null if the path doesn't match any API route (fallthrough to blackboard).
 */
export async function handleApiRequest(
  req: Request,
  ctx: ApiContext,
): Promise<Response | null> {
  const url = new URL(req.url);
  const path = url.pathname;

  if (!path.startsWith("/api/v1/")) return null;

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-Odyssey-Client, X-Odyssey-Client",
      },
    });
  }

  try {
    // ─── Agents ───

    if (matchRoute("/api/v1/agents", "GET", req.method, path)) {
      return handleListAgents(ctx);
    }

    let params = matchRoute("/api/v1/agents/generate", "POST", req.method, path);
    if (params) {
      return await handleGenerateAgent(req, ctx);
    }

    params = matchRoute("/api/v1/agents/:name", "GET", req.method, path);
    if (params) {
      return handleGetAgent(params.name, ctx);
    }

    // ─── Sessions ───

    if (matchRoute("/api/v1/sessions", "POST", req.method, path)) {
      return await handleCreateSession(req, ctx);
    }

    if (matchRoute("/api/v1/sessions", "GET", req.method, path)) {
      return handleListSessions(ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/events", "GET", req.method, path);
    if (params) {
      return handleSessionEvents(params.id, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/messages", "POST", req.method, path);
    if (params) {
      return await handleSendMessage(params.id, req, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/pause", "POST", req.method, path);
    if (params) {
      return await handlePauseSession(params.id, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/resume", "POST", req.method, path);
    if (params) {
      return await handleResumeSession(params.id, req, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/fork", "POST", req.method, path);
    if (params) {
      return await handleForkSession(params.id, ctx);
    }

    // Must check questions routes before generic session GET
    params = matchRoute("/api/v1/sessions/:id/questions", "POST", req.method, path);
    if (params) {
      return await handleCreateQuestion(params.id, req, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/questions/:qid/answer", "POST", req.method, path);
    if (params) {
      return await handleAnswerQuestion(params.id, params.qid, req);
    }

    params = matchRoute("/api/v1/sessions/:id", "GET", req.method, path);
    if (params) {
      return handleGetSession(params.id, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id", "DELETE", req.method, path);
    if (params) {
      return handleDeleteSession(params.id, ctx);
    }

    // ─── Messaging ───

    if (matchRoute("/api/v1/messages/send", "POST", req.method, path)) {
      return await handleSendPeerMessage(req, ctx);
    }

    if (matchRoute("/api/v1/messages/broadcast", "POST", req.method, path)) {
      return await handleBroadcast(req, ctx);
    }

    params = matchRoute("/api/v1/messages/inbox/:sessionId", "GET", req.method, path);
    if (params) {
      return handleDrainInbox(params.sessionId, url, ctx);
    }

    // ─── Delegation ───

    if (matchRoute("/api/v1/delegate", "POST", req.method, path)) {
      return await handleDelegate(req, ctx);
    }

    // ─── Webhooks ───

    if (matchRoute("/api/v1/webhooks", "POST", req.method, path)) {
      return await handleRegisterWebhook(req, ctx);
    }

    if (matchRoute("/api/v1/webhooks", "GET", req.method, path)) {
      return handleListWebhooks(ctx);
    }

    params = matchRoute("/api/v1/webhooks/:id", "DELETE", req.method, path);
    if (params) {
      return handleDeleteWebhook(params.id, ctx);
    }

    // ─── Peers & Workspaces ───

    if (matchRoute("/api/v1/peers", "GET", req.method, path)) {
      return handleListPeers(ctx);
    }

    if (matchRoute("/api/v1/workspaces", "GET", req.method, path)) {
      return handleListWorkspaces(ctx);
    }

    if (matchRoute("/api/v1/workspaces", "POST", req.method, path)) {
      return await handleCreateWorkspace(req, ctx);
    }

    // ─── Conversations (iOS data bridge) ───

    if (matchRoute("/api/v1/conversations", "GET", req.method, path)) {
      return handleListConversations(ctx);
    }

    params = matchRoute("/api/v1/conversations/:id/messages", "GET", req.method, path);
    if (params) {
      return handleGetConversationMessages(params.id, url, ctx);
    }

    // ─── Projects (iOS data bridge) ───

    if (matchRoute("/api/v1/projects", "GET", req.method, path)) {
      return handleListProjects(ctx);
    }

    // ─── Debug / Observability ───

    if (matchRoute("/api/v1/debug/state", "GET", req.method, path)) {
      return handleDebugState(ctx);
    }

    if (matchRoute("/api/v1/debug/logs", "GET", req.method, path)) {
      return handleDebugLogs(url, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/turns", "GET", req.method, path);
    if (params) {
      return handleSessionTurns(params.id, ctx);
    }

    params = matchRoute("/api/v1/sessions/:id/events/history", "GET", req.method, path);
    if (params) {
      return handleSessionEventHistory(params.id, url, ctx);
    }

    return apiError("not_found", `No route matches ${req.method} ${path}`, 404);
  } catch (err: any) {
    if (err.error && err.status) {
      return apiError(err.error, err.message, err.status);
    }
    logger.error("api", `Unhandled error: ${err}`);
    return apiError("internal_error", err.message ?? "Internal error", 500);
  }
}

// ─── Handlers ───

function handleListAgents(ctx: ApiContext): Response {
  const agents: any[] = [];
  for (const [name, config] of ctx.toolCtx.agentDefinitions) {
    agents.push({
      name,
      provider: config.provider ?? "claude",
      model: config.model,
      workingDirectory: config.workingDirectory,
      skillCount: config.skills?.length ?? 0,
      mcpServerCount: config.mcpServers?.length ?? 0,
    });
  }
  return apiJson({ agents });
}

function handleGetAgent(name: string, ctx: ApiContext): Response {
  const config = ctx.toolCtx.agentDefinitions.get(name);
  if (!config) return apiError("agent_not_found", `No agent registered with name '${name}'`, 404);
  return apiJson({
    name: config.name,
    provider: config.provider ?? "claude",
    model: config.model,
    systemPrompt: config.systemPrompt,
    allowedTools: config.allowedTools,
    mcpServers: config.mcpServers.map((m) => ({ name: m.name, hasCommand: !!m.command, hasUrl: !!m.url })),
    skills: config.skills.map((s) => s.name),
    workingDirectory: config.workingDirectory,
    maxTurns: config.maxTurns,
    maxBudget: config.maxBudget,
  });
}

async function handleGenerateAgent(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<{ prompt: string }>(req);
  if (!body.prompt) return apiError("invalid_request", "prompt is required", 400);

  // Use the WS server's generate flow by broadcasting a request and waiting for the event.
  // For simplicity in the REST API, we re-implement the generation inline using the Anthropic SDK.
  const Anthropic = (await import("@anthropic-ai/sdk")).default;
  const anthropic = new Anthropic();

  const validIcons = [
    "cpu", "brain", "terminal", "doc.text", "magnifyingglass", "shield",
    "wrench.and.screwdriver", "paintbrush", "chart.bar", "bubble.left.and.bubble.right",
    "network", "globe", "folder", "gear", "lightbulb", "book", "hammer",
    "ant", "ladybug", "leaf", "bolt", "wand.and.stars", "pencil.and.outline",
    "person.crop.circle", "star", "flag", "bell", "map", "eye", "lock.shield",
    "server.rack", "externaldrive", "icloud", "arrow.triangle.branch",
    "text.badge.checkmark", "checkmark.seal", "clock", "calendar",
    "exclamationmark.triangle", "play", "stop", "shuffle", "repeat",
    "square.and.pencil", "rectangle.and.text.magnifyingglass",
    "doc.on.clipboard", "tray.2", "archivebox", "shippingbox",
  ];
  const validColors = ["blue", "red", "green", "purple", "orange", "teal", "pink", "indigo", "gray"];

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 4096,
    system: `You are an agent designer. Given a user's description of an AI agent, generate a complete agent definition as JSON.\n\nReturn ONLY valid JSON with: name, description, systemPrompt, model ("sonnet"|"opus"|"haiku"), icon (SF Symbol from ${JSON.stringify(validIcons)}), color (from ${JSON.stringify(validColors)}), matchedSkillIds (empty array), matchedMCPIds (empty array).`,
    messages: [{ role: "user", content: body.prompt }],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    return apiError("internal_error", "No text response from Claude", 500);
  }

  let jsonText = textBlock.text.trim();
  if (jsonText.startsWith("```")) {
    jsonText = jsonText.replace(/^```(?:json)?\s*\n?/, "").replace(/\n?```\s*$/, "");
  }

  const spec = JSON.parse(jsonText);
  if (!validIcons.includes(spec.icon)) spec.icon = "cpu";
  if (!validColors.includes(spec.color)) spec.color = "blue";

  return apiJson(spec, 201);
}

async function handleCreateSession(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<CreateSessionRequest>(req);
  if (!body.agentName) return apiError("invalid_request", "agentName is required", 400);
  if (!body.message) return apiError("invalid_request", "message is required", 400);

  const config = ctx.toolCtx.agentDefinitions.get(body.agentName);
  if (!config) return apiError("agent_not_found", `No agent registered with name '${body.agentName}'`, 404);

  // Apply working directory override if provided
  const sessionConfig: AgentConfig = body.workingDirectory
    ? { ...config, workingDirectory: body.workingDirectory }
    : config;

  const sessionId = crypto.randomUUID();
  const waitForResult = body.waitForResult ?? false;

  // Always spawn a new session
  const result = await ctx.sessionManager.spawnAutonomous(
    sessionId,
    sessionConfig,
    body.message,
    waitForResult,
  );

  return apiJson({
    sessionId: result.sessionId,
    agentName: body.agentName,
    provider: sessionConfig.provider ?? "claude",
    status: "active",
    method: "spawned",
    ...(result.result != null ? { result: result.result } : {}),
  }, 201);
}

function handleListSessions(ctx: ApiContext): Response {
  const sessions = ctx.sessionManager.listSessions();
  return apiJson({ sessions });
}

function handleGetSession(id: string, ctx: ApiContext): Response {
  const state = ctx.toolCtx.sessions.get(id);
  if (!state) return apiError("session_not_found", `No session with ID ${id}`, 404);
  return apiJson(state);
}

function handleDeleteSession(id: string, ctx: ApiContext): Response {
  const state = ctx.toolCtx.sessions.get(id);
  if (!state) return apiError("session_not_found", `No session with ID ${id}`, 404);
  if (state.status === "active") {
    return apiError("session_not_active", "Cannot delete an active session — pause it first", 409);
  }
  ctx.toolCtx.sessions.remove(id);
  ctx.toolCtx.delegation.delete(id);
  return apiJson({ deleted: true, sessionId: id });
}

async function handleSendMessage(sessionId: string, req: Request, ctx: ApiContext): Promise<Response> {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) return apiError("session_not_found", `No session with ID ${sessionId}`, 404);

  const body = await parseBody<SendMessageRequest>(req);
  if (!body.text) return apiError("invalid_request", "text is required", 400);

  // Note: sendMessage aborts any in-progress query for this session
  ctx.sessionManager.sendMessage(sessionId, body.text, body.attachments).catch((err) => {
    logger.error("api", `sendMessage error for ${sessionId}: ${err}`);
  });

  return apiJson({ accepted: true }, 202);
}

async function handlePauseSession(sessionId: string, ctx: ApiContext): Promise<Response> {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) return apiError("session_not_found", `No session with ID ${sessionId}`, 404);

  await ctx.sessionManager.pauseSession(sessionId);
  return apiJson({ sessionId, status: "paused" });
}

async function handleResumeSession(sessionId: string, req: Request, ctx: ApiContext): Promise<Response> {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) return apiError("session_not_found", `No session with ID ${sessionId}`, 404);

  let claudeSessionId = state.claudeSessionId;
  try {
    const body = await req.json() as ResumeSessionRequest;
    if (body.claudeSessionId) claudeSessionId = body.claudeSessionId;
  } catch { /* empty body is fine — use stored claudeSessionId */ }

  if (!claudeSessionId) {
    return apiError("invalid_request", "No claudeSessionId available — provide one in the request body", 400);
  }

  await ctx.sessionManager.resumeSession(sessionId, claudeSessionId);
  return apiJson({ sessionId, status: "active", restored: true });
}

async function handleForkSession(sessionId: string, ctx: ApiContext): Promise<Response> {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) return apiError("session_not_found", `No session with ID ${sessionId}`, 404);

  const childSessionId = crypto.randomUUID();
  await ctx.sessionManager.forkSession(sessionId, childSessionId);
  return apiJson({ parentSessionId: sessionId, childSessionId }, 201);
}

function handleSessionEvents(sessionId: string, ctx: ApiContext): Response {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) {
    return apiError("session_not_found", `No session with ID ${sessionId}`, 404);
  }

  const stream = ctx.sseManager.subscribe(sessionId);

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

async function handleCreateQuestion(
  sessionId: string,
  req: Request,
  ctx: ApiContext,
): Promise<Response> {
  const body = await parseBody<{
    question: string;
    options?: { label: string; description?: string }[];
    multiSelect?: boolean;
    private?: boolean;
  }>(req);
  if (!body.question) return apiError("invalid_request", "question is required", 400);

  const { questionId, promise } = createQuestion(sessionId);

  ctx.toolCtx.broadcast({
    type: "agent.question",
    sessionId,
    questionId,
    question: body.question,
    options: body.options,
    multiSelect: body.multiSelect ?? false,
    private: body.private ?? true,
  });

  logger.info("api", `ask_user: session=${sessionId} questionId=${questionId}`);

  // Long-poll: block until answered or timeout (the createQuestion timeout handles the latter)
  const result = await promise;
  return apiJson({ questionId, answer: result.answer, selectedOptions: result.selectedOptions });
}

async function handleAnswerQuestion(
  sessionId: string,
  questionId: string,
  req: Request,
): Promise<Response> {
  const body = await parseBody<AnswerQuestionRequest>(req);
  if (!body.answer) return apiError("invalid_request", "answer is required", 400);

  const resolved = resolveQuestion(questionId, body.answer, body.selectedOptions);
  if (!resolved) {
    return apiError("question_not_found", `No pending question with ID ${questionId}`, 404);
  }

  return apiJson({ resolved: true, questionId });
}

// ─── Messaging ───

async function handleSendPeerMessage(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<SendPeerMessageRequest>(req);
  if (!body.toAgent || !body.message) {
    return apiError("invalid_request", "toAgent and message are required", 400);
  }

  const from = clientIdentity(req);

  // Resolve target: try as session ID first, then as agent name
  let targetId = body.toAgent;
  const targetState = ctx.toolCtx.sessions.get(body.toAgent);
  if (!targetState) {
    const byName = ctx.toolCtx.sessions.findByAgentName(body.toAgent);
    if (byName.length === 0) {
      return apiError("agent_not_found", `No active session for '${body.toAgent}'`, 404);
    }
    targetId = byName[0].id;
  }

  ctx.toolCtx.messages.push(targetId, {
    id: crypto.randomUUID(),
    from,
    fromAgent: from,
    to: targetId,
    text: body.message,
    priority: body.priority ?? "normal",
    timestamp: new Date().toISOString(),
    read: false,
  });

  ctx.toolCtx.broadcast({
    type: "peer.chat",
    channelId: `dm:${from}→${targetId}`,
    from,
    message: body.message,
  });

  return apiJson({ delivered: true, targetSessionId: targetId });
}

async function handleBroadcast(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<BroadcastRequest>(req);
  if (!body.channel || !body.message) {
    return apiError("invalid_request", "channel and message are required", 400);
  }

  const from = clientIdentity(req);
  const activeSessions = ctx.toolCtx.sessions.listActive();

  const msg = {
    id: crypto.randomUUID(),
    from,
    fromAgent: from,
    text: body.message,
    channel: body.channel,
    priority: "normal" as const,
    timestamp: new Date().toISOString(),
    read: false,
  };

  ctx.toolCtx.messages.pushToAll(msg, activeSessions.map((s) => s.id));

  ctx.toolCtx.broadcast({
    type: "peer.chat",
    channelId: `broadcast:${body.channel}`,
    from,
    message: body.message,
  });

  return apiJson({ broadcast: true, recipientCount: activeSessions.length });
}

function handleDrainInbox(sessionId: string, url: URL, ctx: ApiContext): Response {
  const state = ctx.toolCtx.sessions.get(sessionId);
  if (!state) return apiError("session_not_found", `No session with ID ${sessionId}`, 404);

  const since = url.searchParams.get("since") ?? undefined;
  const messages = ctx.toolCtx.messages.drain(sessionId, since);
  return apiJson({ messages, count: messages.length });
}

// ─── Delegation ───

async function handleDelegate(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<DelegateRequest>(req);
  if (!body.toAgent || !body.task) {
    return apiError("invalid_request", "toAgent and task are required", 400);
  }

  const from = clientIdentity(req);
  const config = ctx.toolCtx.agentDefinitions.get(body.toAgent);
  if (!config) {
    // Check remote peers
    const remote = ctx.toolCtx.peerRegistry.findAgentOwner(body.toAgent);
    if (remote) {
      try {
        if (!ctx.toolCtx.relayClient.isConnected(remote.peer.name)) {
          await ctx.toolCtx.relayClient.connect(remote.peer.name, remote.peer.endpoint);
        }
        const result = await ctx.toolCtx.relayClient.sendCommand(remote.peer.name, {
          type: "delegate.task",
          sessionId: from,
          toAgent: body.toAgent,
          task: body.task,
          context: body.context,
          waitForResult: body.waitForResult ?? false,
        });
        return apiJson({ method: "remote_relay", peer: remote.peer.name, result }, 200);
      } catch (err: any) {
        return apiError("internal_error", `Remote delegation failed: ${err.message}`, 502);
      }
    }
    return apiError("agent_not_found", `No agent definition for '${body.toAgent}'`, 404);
  }

  const prompt = body.context ? `${body.task}\n\n## Context\n${body.context}` : body.task;
  const waitForResult = body.waitForResult ?? false;

  // Always spawn a new session
  ctx.toolCtx.broadcast({
    type: "peer.delegate",
    from,
    to: body.toAgent,
    task: body.task,
  });

  const sessionId = crypto.randomUUID();
  const result = await ctx.toolCtx.spawnSession(sessionId, config, prompt, waitForResult);

  return apiJson({
    sessionId: result.sessionId,
    method: "spawned",
    ...(result.result != null ? { result: result.result } : {}),
  }, waitForResult ? 200 : 202);
}

// ─── Webhooks ───

async function handleRegisterWebhook(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<RegisterWebhookRequest>(req);
  if (!body.url || !body.events || body.events.length === 0) {
    return apiError("invalid_request", "url and events are required", 400);
  }

  try {
    const registration = ctx.webhookManager.register(body.url, body.events, body.sessionFilter);
    return apiJson(registration, 201);
  } catch (err: any) {
    return apiError("invalid_request", err.message, 400);
  }
}

function handleListWebhooks(ctx: ApiContext): Response {
  return apiJson({ webhooks: ctx.webhookManager.list() });
}

function handleDeleteWebhook(id: string, ctx: ApiContext): Response {
  const deleted = ctx.webhookManager.unregister(id);
  if (!deleted) return apiError("not_found", `No webhook with ID ${id}`, 404);
  return apiJson({ deleted: true, id });
}

// ─── Peers & Workspaces ───

function handleListPeers(ctx: ApiContext): Response {
  const peers = ctx.toolCtx.peerRegistry.listConnected().map((p) => ({
    name: p.name,
    endpoint: p.endpoint,
    agentCount: p.agents.length,
    agents: p.agents.map((a) => a.name),
    lastSeen: p.lastSeen.toISOString(),
  }));
  return apiJson({ peers });
}

function handleListWorkspaces(ctx: ApiContext): Response {
  return apiJson({ workspaces: ctx.toolCtx.workspaces.list() });
}

async function handleCreateWorkspace(req: Request, ctx: ApiContext): Promise<Response> {
  const body = await parseBody<{ name: string }>(req);
  if (!body.name) return apiError("invalid_request", "name is required", 400);

  const from = clientIdentity(req);
  const workspace = ctx.toolCtx.workspaces.create(body.name, from);
  return apiJson(workspace, 201);
}

// ─── Conversations (iOS data bridge) ───

function handleListConversations(ctx: ApiContext): Response {
  const conversations = ctx.toolCtx.conversationStore.listConversations();
  return apiJson({ conversations });
}

function handleGetConversationMessages(conversationId: string, url: URL, ctx: ApiContext): Response {
  if (!ctx.toolCtx.conversationStore.hasConversation(conversationId)) {
    return apiError("not_found", `No conversation with ID ${conversationId}`, 404);
  }
  const limitParam = url.searchParams.get("limit");
  const before = url.searchParams.get("before") ?? undefined;
  const limit = limitParam ? parseInt(limitParam, 10) : undefined;
  const messages = ctx.toolCtx.conversationStore.getMessages(conversationId, limit, before);
  return apiJson({ messages });
}

// ─── Projects (iOS data bridge) ───

function handleListProjects(ctx: ApiContext): Response {
  const projects = ctx.toolCtx.projectStore.list();
  return apiJson({ projects });
}

// ─── Debug handlers ───

function handleDebugState(ctx: ApiContext): Response {
  const sessions = ctx.sessionManager.listSessions();
  const uptime = process.uptime();
  return apiJson({
    uptime: `${Math.floor(uptime)}s`,
    sessions: sessions.map((s) => ({
      id: s.id,
      agentName: s.agentName,
      status: s.status,
      tokenCount: s.tokenCount,
      cost: s.cost,
    })),
    sseConnections: ctx.sseManager.connectionCount,
    sessionCount: sessions.length,
    activeSessionCount: sessions.filter((s) => s.status === "active").length,
  });
}

function handleDebugLogs(url: URL, _ctx: ApiContext): Response {
  const tail = parseInt(url.searchParams.get("tail") ?? "50", 10);
  const category = url.searchParams.get("category") ?? undefined;
  const VALID_LOG_LEVELS = new Set<string>(["debug", "info", "warn", "error"]);
  const rawLevel = url.searchParams.get("level") ?? undefined;
  const level: SidecarLogLevel | undefined = rawLevel && VALID_LOG_LEVELS.has(rawLevel)
    ? (rawLevel as SidecarLogLevel)
    : undefined;
  const entries = getLogBuffer({ tail, category, level });
  return apiJson({ logs: entries, total: entries.length, returned: entries.length });
}

function handleSessionTurns(sessionId: string, ctx: ApiContext): Response {
  const session = ctx.toolCtx.sessions.get(sessionId);
  if (!session) return apiError("not_found", `Session '${sessionId}' not found`, 404);
  const turns = ctx.sessionManager.getTurnHistory(sessionId);
  return apiJson({ sessionId, turns });
}

function handleSessionEventHistory(sessionId: string, url: URL, ctx: ApiContext): Response {
  const session = ctx.toolCtx.sessions.get(sessionId);
  if (!session) return apiError("not_found", `Session '${sessionId}' not found`, 404);
  const limit = parseInt(url.searchParams.get("limit") ?? "100", 10);
  const events = ctx.sseManager.getEventHistory(sessionId, limit);
  return apiJson({ sessionId, events, buffered: events.length });
}
