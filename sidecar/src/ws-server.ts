import type { ServerWebSocket } from "bun";
import type { SidecarCommand, SidecarEvent } from "./types.js";
import type { SessionManager } from "./session-manager.js";
import type { ToolContext } from "./tools/tool-context.js";
import { resolveQuestion } from "./tools/ask-user-tool.js";
import { logger } from "./logger.js";
import { probeConnector } from "./connectors/provider-runtime.js";
import { ConversationEvaluator } from "./conversation-evaluator.js";
import { GenerationService } from "./generation-service.js";
import type { GHPoller } from "./gh-poller.js";
import type { GHRouter } from "./gh-router.js";
import { runGh } from "./gh-cli.js";


export interface WsServerOptions {
  token?: string;
  tlsCert?: string;
  tlsKey?: string;
}

export class WsServer {
  private clients = new Set<ServerWebSocket<unknown>>();
  readonly trustedIosNpubs = new Set<string>();
  private sessionManager: SessionManager;
  private ctx: ToolContext;
  private server: ReturnType<typeof Bun.serve> | null = null;
  private options: WsServerOptions = {};
  private readonly conversationEvaluator: ConversationEvaluator;
  private readonly generationService: GenerationService;
  private ghPoller?: GHPoller;
  private ghRouter?: GHRouter;

  constructor(port: number, sessionManager: SessionManager, ctx: ToolContext, options: WsServerOptions = {}) {
    this.sessionManager = sessionManager;
    this.ctx = ctx;
    this.options = options;
    this.conversationEvaluator = new ConversationEvaluator(this.sessionManager);
    this.generationService = new GenerationService();

    // Load TLS config; fall back to plain WS if the cert/key can't be parsed
    // (macOS Security.framework can produce explicit-params EC certs that Bun/BoringSSL rejects)
    let tlsConfig: { cert: ReturnType<typeof Bun.file>; key: ReturnType<typeof Bun.file> } | undefined;
    if (options.tlsCert && options.tlsKey) {
      try {
        const testServer = Bun.serve({
          port: 0,
          tls: { cert: Bun.file(options.tlsCert), key: Bun.file(options.tlsKey) },
          fetch() { return new Response("probe"); },
        });
        testServer.stop();
        tlsConfig = { cert: Bun.file(options.tlsCert), key: Bun.file(options.tlsKey) };
      } catch (err) {
        logger.warn("ws", `TLS cert/key failed to load (${err}); falling back to plain ws://`);
      }
    }

    this.server = Bun.serve({
      port,
      ...(tlsConfig ? { tls: tlsConfig } : {}),
      fetch(req, server) {
        // Enforce bearer token if configured
        if (options.token) {
          const authHeader = req.headers.get("authorization") ?? "";
          if (authHeader !== `Bearer ${options.token}`) {
            logger.warn("ws", "Rejected connection: invalid bearer token", {
              remoteAddr: (server as any).requestIP?.(req)?.address ?? "unknown",
            });
            return new Response("Unauthorized", { status: 401 });
          }
        }

        if (server.upgrade(req)) return undefined;
        return new Response("WebSocket endpoint", { status: 426 });
      },
      websocket: {
        open: (ws) => {
          this.clients.add(ws);
          logger.info("ws", `Swift client connected (total: ${this.clients.size})`);
          const ready: SidecarEvent = {
            type: "sidecar.ready",
            port,
            version: "0.2.0",
          };
          ws.send(JSON.stringify(ready));
        },
        message: (ws, message) => {
          try {
            const data = typeof message === "string" ? message : new TextDecoder().decode(message);
            const command = JSON.parse(data) as SidecarCommand;
            logger.debug("ws", this.describeCommand(command));
            this.handleCommand(command).catch((err) => {
              logger.error("ws", `Command handler error: ${err}`);
            });
          } catch (err) {
            logger.error("ws", `Failed to parse command: ${err}`);
          }
        },
        close: (ws) => {
          this.clients.delete(ws);
          logger.info("ws", `Swift client disconnected (total: ${this.clients.size})`);

          // Sweep all pending browser operations — they can never resolve now.
          if (this.ctx.pendingBrowserBlocking.size > 0) {
            logger.warn("ws", `Sweeping ${this.ctx.pendingBrowserBlocking.size} pending browser blocking calls after disconnect`);
            for (const resolver of this.ctx.pendingBrowserBlocking.values()) {
              resolver("[Browser disconnected]");
            }
            this.ctx.pendingBrowserBlocking.clear();
          }
          if (this.ctx.pendingBrowserResults.size > 0) {
            logger.warn("ws", `Sweeping ${this.ctx.pendingBrowserResults.size} pending browser results after disconnect`);
            for (const resolver of this.ctx.pendingBrowserResults.values()) {
              resolver("[Browser disconnected]");
            }
            this.ctx.pendingBrowserResults.clear();
          }
        },
      },
    });

    const protocol = tlsConfig ? "wss" : "ws";
    logger.info("ws", `WebSocket server listening on ${protocol}://localhost:${port}`);
  }

  private async handleCommand(command: SidecarCommand): Promise<void> {
    switch (command.type) {
      case "session.create": {
        // Prefer the Mac-side agent definition (has correct provider/model/skills/MCPs).
        // Fall back to the wire config only if the agent isn't registered locally.
        const registeredConfig = this.ctx.agentDefinitions.get(command.agentConfig.name);
        const resolvedConfig = registeredConfig ?? command.agentConfig;
        this.ctx.conversationStore.ensureConversation(
          command.conversationId,
          resolvedConfig.name,
        );
        await this.sessionManager.createSession(
          command.conversationId,
          resolvedConfig,
        );
        break;
      }
      case "session.message": {
        // Persist the user message so iOS can read it back via REST.
        this.ctx.conversationStore.appendMessage(command.sessionId, {
          id: `user-${command.sessionId}-${Date.now()}`,
          text: command.text,
          type: "chat",
          senderParticipantId: "user",
          timestamp: new Date().toISOString(),
          isStreaming: false,
        });
        await this.sessionManager.sendMessage(
          command.sessionId,
          command.text,
          command.attachments,
          command.planMode,
        );
        break;
      }
      case "session.resume":
        await this.sessionManager.resumeSession(
          command.sessionId,
          command.claudeSessionId,
        );
        break;
      case "session.fork":
        await this.sessionManager.forkSession(command.sessionId, command.childSessionId);
        break;
      case "session.pause":
        await this.sessionManager.pauseSession(command.sessionId);
        break;
      case "session.updateMode":
        this.sessionManager.updateSessionMode(
          command.sessionId,
          command.interactive,
          command.instancePolicy,
          command.instancePolicyPoolMax,
        );
        logger.info(
          "ws",
          `Updated mode for ${command.sessionId} (interactive=${command.interactive}, instancePolicy=${command.instancePolicy ?? "default"})`,
        );
        break;
      case "session.updateCwd":
        this.sessionManager.updateSessionCwd(command.sessionId, command.workingDirectory);
        logger.info("ws", `Updated cwd for ${command.sessionId} → ${command.workingDirectory}`);
        break;
      case "session.bulkResume":
        await this.sessionManager.bulkResume(command.sessions);
        break;
      case "agent.register":
        for (const def of command.agents) {
          const configWithPolicy = { ...def.config };
          if (def.instancePolicy) {
            if (def.instancePolicy.startsWith("pool:")) {
              configWithPolicy.instancePolicy = "pool";
              configWithPolicy.instancePolicyPoolMax = parseInt(def.instancePolicy.substring(5), 10);
            } else if (def.instancePolicy === "singleton") {
              configWithPolicy.instancePolicy = "singleton";
            } else {
              configWithPolicy.instancePolicy = "spawn";
            }
          }
          this.ctx.agentDefinitions.set(def.name, configWithPolicy);
          logger.info("ws", `Registered agent definition: ${def.name}`);
        }
        break;

      case "delegate.task":
        await this.handleDelegateTask(command);
        break;

      case "peer.register":
        this.ctx.peerRegistry.register(
          command.name,
          command.endpoint,
          command.agents.map((a: any) => ({ name: a.name, config: a.config })),
        );
        break;
      case "peer.remove":
        this.ctx.peerRegistry.remove(command.name);
        break;

      case "nostr.addPeer":
        this.ctx.nostrTransport.addPeer(command.name, command.pubkeyHex, command.relays)
        logger.info("nostr", `Added Nostr peer "${command.name}" (${command.pubkeyHex.slice(0, 8)}…)`)
        break
      case "nostr.removePeer":
        this.ctx.nostrTransport.removePeer(command.name)
        logger.info("nostr", `Removed Nostr peer "${command.name}"`)
        break
      case "nostr.peerAnnounce":
        // Mac Swift sets its own identity on the transport at startup
        this.ctx.nostrTransport.setIdentity(
          process.env.ODYSSEY_NOSTR_PRIVKEY_HEX ?? "",
          command.pubkeyHex,
          command.relays,
        )
        logger.info("nostr", `Nostr identity announced: pubkey ${command.pubkeyHex.slice(0, 8)}…`)
        break

      case "nostr.injectCommand":
        // Swift NostrRelayManager decrypts a remote command and injects it here.
        // Re-dispatch the inner command as if it arrived locally.
        await this.handleCommand(command.command)
        break

      case "generate.agent":
        this.handleGenerateAgent(command).catch((err) => {
          logger.error("ws", `generate.agent handler error: ${err}`);
          this.broadcast({
            type: "generate.agent.error",
            requestId: command.requestId,
            error: err.message ?? "Unknown error",
          });
        });
        break;

      case "generate.group":
        this.handleGenerateGroup(command).catch((err) => {
          logger.error("ws", `generate.group handler error: ${err}`);
          this.broadcast({
            type: "generate.group.error",
            requestId: command.requestId,
            error: err.message ?? "Unknown error",
          });
        });
        break;

      case "generate.skill":
        this.handleGenerateSkill(command).catch((err) => {
          logger.error("ws", `generate.skill handler error: ${err}`);
          this.broadcast({
            type: "generate.skill.error",
            requestId: command.requestId,
            error: err.message ?? "Unknown error",
          });
        });
        break;

      case "generate.template":
        this.handleGenerateTemplate(command).catch((err) => {
          logger.error("ws", `generate.template handler error: ${err}`);
          this.broadcast({
            type: "generate.template.error",
            requestId: command.requestId,
            error: err.message ?? "Unknown error",
          });
        });
        break;

      case "session.questionAnswer": {
        const resolved =
          await this.sessionManager.answerQuestion?.(
            command.sessionId,
            command.questionId,
            command.answer,
            command.selectedOptions,
          ) ||
          resolveQuestion(
            command.questionId,
            command.answer,
            command.selectedOptions,
          );
        if (resolved) {
          logger.info("ws", `session.questionAnswer: resolved question ${command.questionId} for session ${command.sessionId}`);
        } else {
          logger.warn("ws", `session.questionAnswer: no pending question found for ${command.questionId}`);
        }
        break;
      }

      case "connector.list":
        this.broadcast({ type: "connector.list.result", connections: this.ctx.connectors.listConfigs() });
        break;
      case "connector.beginAuth": {
        const entry = this.ctx.connectors.markAuthorizing(command.connection);
        this.broadcast({ type: "connector.statusChanged", connection: entry.connection });
        break;
      }
      case "connector.completeAuth": {
        const entry = this.ctx.connectors.upsert(command.connection, command.credentials);
        this.broadcast({ type: "connector.statusChanged", connection: entry.connection });
        break;
      }
      case "connector.revoke": {
        const entry = this.ctx.connectors.revoke(command.connectionId);
        if (entry) {
          this.broadcast({ type: "connector.statusChanged", connection: entry.connection });
        }
        break;
      }
      case "connector.test":
        await this.handleConnectorTest(command.connectionId);
        break;

      case "config.setOllama": {
        const normalizedBaseURL = command.baseURL.trim().replace(/\/+$/, "") || "http://127.0.0.1:11434";
        process.env.ODYSSEY_OLLAMA_MODELS_ENABLED = command.enabled ? "1" : "0";
        process.env.CLAUDESTUDIO_OLLAMA_MODELS_ENABLED = command.enabled ? "1" : "0";
        process.env.ODYSSEY_OLLAMA_BASE_URL = normalizedBaseURL;
        process.env.CLAUDESTUDIO_OLLAMA_BASE_URL = normalizedBaseURL;
        logger.info("ws", `config.setOllama: enabled=${command.enabled} baseURL=${normalizedBaseURL}`);
        break;
      }

      case "session.confirmationAnswer": {
        const { resolveConfirmation } = await import("./tools/rich-display-tools.js");
        const confirmed =
          await this.sessionManager.answerConfirmation?.(
            command.sessionId,
            command.confirmationId,
            command.approved,
            command.modifiedAction,
          ) ||
          resolveConfirmation(
            command.confirmationId,
            command.approved,
            command.modifiedAction,
          );
        if (confirmed) {
          logger.info("ws", `session.confirmationAnswer: resolved confirmation ${command.confirmationId} approved=${command.approved}`);
        } else {
          logger.warn("ws", `session.confirmationAnswer: no pending confirmation found for ${command.confirmationId}`);
        }
        break;
      }

      case "config.setLogLevel": {
        const { setLogLevel } = await import("./logger.js");
        setLogLevel(command.level as any);
        logger.info("ws", `config.setLogLevel: level set to ${command.level}`);
        break;
      }

      case "conversation.sync":
        this.ctx.conversationStore.sync(command.conversations);
        logger.info("ws", `conversation.sync: synced ${command.conversations.length} conversations`);
        break;

      case "conversation.messageAppend":
        this.ctx.conversationStore.appendMessage(command.conversationId, command.message);
        logger.info("ws", `conversation.messageAppend: conv=${command.conversationId.slice(0, 8)} msg=${command.message.id.slice(0, 8)} type=${command.message.type}`);
        break;

      case "project.sync":
        this.ctx.projectStore.sync(command.projects);
        logger.info("ws", `project.sync: synced ${command.projects.length} projects`);
        break;

      case "ios.registerPush": {
        const pushCmd = command as { type: "ios.registerPush"; apnsToken: string; appId: string };
        logger.info({ category: "matrix", apnsToken: pushCmd.apnsToken.substring(0, 8) + "…", appId: pushCmd.appId }, "ios.registerPush received");
        // TODO: Phase 6 — call MatrixClient.registerPusher() on Mac side via AppState
        this.broadcast({ type: "ios.pushRegistered", apnsToken: pushCmd.apnsToken, success: true });
        break;
      }

      case "conversation.setDelegationMode": {
        this.ctx.delegation.set(command.sessionId, {
          mode: command.mode,
          targetAgentName: command.targetAgentName,
        });
        logger.info("ws", `conversation.setDelegationMode: session=${command.sessionId} mode=${command.mode} target=${command.targetAgentName ?? "none"}`);
        break;
      }

      case "conversation.clear": {
        this.ctx.conversationStore.clearMessages(command.conversationId);
        logger.info("ws", `conversation.clear: conversationId=${command.conversationId}`);
        this.broadcast({ type: "conversation.cleared", conversationId: command.conversationId });
        break;
      }

      case "session.updateModel": {
        this.ctx.sessions.updateConfig(command.sessionId, { model: command.model });
        logger.info("ws", `session.updateModel: sessionId=${command.sessionId} model=${command.model}`);
        break;
      }

      case "session.updateEffort": {
        const effortToTokens: Record<string, number> = {
          low: 0, medium: 8_000, high: 32_000, max: 100_000,
        };
        const maxThinkingTokens = effortToTokens[command.effort] ?? 32_000;
        this.ctx.sessions.updateConfig(command.sessionId, { maxThinkingTokens });
        logger.info("ws", `session.updateEffort: sessionId=${command.sessionId} effort=${command.effort} tokens=${maxThinkingTokens}`);
        break;
      }

      case "conversation.evaluate": {
        await this.conversationEvaluator.evaluate(command, this.broadcast.bind(this));
        break;
      }

      // ─── Browser event handlers ──────────────────────────────────────────────
      case "browser.result": {
        const key = `${command.sessionId}:${command.commandType}`;
        const resolver = this.ctx.pendingBrowserResults.get(key);
        if (resolver) {
          this.ctx.pendingBrowserResults.delete(key);
          resolver(command.payload);
          logger.debug("browser", `browser.result resolved: session=${command.sessionId} commandType=${command.commandType}`);
        } else {
          logger.warn("browser", `browser.result: no pending resolver for key="${key}"`);
        }
        break;
      }
      case "browser.error": {
        const key = `${command.sessionId}:${command.commandType}`;
        const resolver = this.ctx.pendingBrowserResults.get(key);
        if (resolver) {
          this.ctx.pendingBrowserResults.delete(key);
          resolver(`Error: ${command.error}`);
          logger.warn("browser", `browser.error resolved with error: session=${command.sessionId} commandType=${command.commandType} error=${command.error}`);
        } else {
          logger.warn("browser", `browser.error: no pending resolver for key="${key}"`);
        }
        break;
      }
      case "browser.pageLoaded":
        logger.info("browser", `browser.pageLoaded: session=${command.sessionId} url=${command.url} title="${command.title}"`);
        break;
      case "browser.userSubmit": {
        const blockingResolver = this.ctx.pendingBrowserBlocking.get(command.sessionId);
        if (blockingResolver) {
          this.ctx.pendingBrowserBlocking.delete(command.sessionId);
          blockingResolver(command.data);
          logger.debug("browser", `browser.userSubmit resolved blocking call: session=${command.sessionId}`);
        } else {
          logger.warn("browser", `browser.userSubmit: no pending blocking resolver for session=${command.sessionId}`);
        }
        break;
      }
      case "browser.resume": {
        const blockingResolver = this.ctx.pendingBrowserBlocking.get(command.sessionId);
        if (blockingResolver) {
          this.ctx.pendingBrowserBlocking.delete(command.sessionId);
          blockingResolver("");
          logger.debug("browser", `browser.resume resolved blocking call: session=${command.sessionId}`);
        } else {
          logger.warn("browser", `browser.resume: no pending blocking resolver for session=${command.sessionId}`);
        }
        break;
      }
      case "browser.stateChange":
        logger.info("browser", `browser.stateChange: session=${command.sessionId} state=${command.state}`);
        break;

      case "pairing.hello":
        logger.info("nostr", `pairing.hello from iOS npub=${command.iosNpub.slice(0, 8)}… displayName="${command.displayName}"`);
        this.trustedIosNpubs.add(command.iosNpub);
        this.broadcast({ type: "pairing.confirmed" });
        break;

      case "conversations.list":
        this.broadcast({
          type: "conversations.list.result",
          conversations: this.ctx.conversationStore.listConversations(),
        });
        break;

      case "agents.list": {
        const agentsList: any[] = [];
        for (const [name, config] of this.ctx.agentDefinitions) {
          agentsList.push({
            name,
            provider: config.provider ?? "claude",
            model: config.model,
            skillCount: config.skills?.length ?? 0,
            mcpServerCount: config.mcpServers?.length ?? 0,
          });
        }
        logger.info("nostr", `agents.list: returning ${agentsList.length} agents`);
        this.broadcast({ type: "agents.list.result", agents: agentsList });
        break;
      }

      case "gh.issue.create": {
        try {
          const args = ["issue", "create", "--repo", command.repo,
            "--title", command.title, "--body", command.body];
          for (const label of (command.labels ?? [])) {
            args.push("--label", label);
          }
          const output = await runGh(args);
          const issueUrl = output.trim();
          const issueMatch = issueUrl.match(/\/issues\/(\d+)$/);
          const issueNumber = issueMatch ? parseInt(issueMatch[1]) : 0;
          if (!issueMatch) {
            logger.warn("github", "Could not parse issue number from gh output", { output: issueUrl });
          }
          // Broadcast created event so Swift can link the conversation to the issue
          this.ctx.broadcast({
            type: "gh.issue.created",
            issueUrl,
            issueNumber,
            repo: command.repo,
            conversationId: command.conversationId,
          });
        } catch (err) {
          logger.error("github", "gh.issue.create failed", { error: String(err) });
        }
        break;
      }

      case "gh.poller.config":
        if (this.ghPoller && this.ghRouter) {
          this.ghPoller.start(
            {
              inboxRepo: command.inboxRepo,
              projectRepos: command.projectRepos,
              trustedUsers: command.trustedUsers,
              intervalSeconds: command.intervalSeconds,
            },
            this.ctx,
          );
        } else {
          logger.warn("github", "gh.poller.config received but GHPoller/GHRouter not initialised");
        }
        break;
    }
  }

  private describeCommand(command: SidecarCommand): string {
    switch (command.type) {
      case "connector.completeAuth":
        return `Received connector.completeAuth for ${command.connection.id} (${command.connection.provider}) [credentials redacted]`;
      case "connector.beginAuth":
        return `Received connector.beginAuth for ${command.connection.id} (${command.connection.provider})`;
      case "connector.revoke":
      case "connector.test":
        return `Received ${command.type} for ${command.connectionId}`;
      default:
        return `Received ${command.type}`;
    }
  }

  private async handleConnectorTest(connectionId: string): Promise<void> {
    const entry = this.ctx.connectors.get(connectionId);
    if (!entry) {
      logger.warn("ws", `connector.test: unknown connector ${connectionId}`);
      return;
    }

    if (!entry.credentials?.accessToken && !entry.credentials?.brokerReference) {
      const connection = {
        ...entry.connection,
        status: "failed" as const,
        statusMessage: "No runtime credentials are currently available.",
        lastCheckedAt: new Date().toISOString(),
      };
      this.ctx.connectors.upsert(connection, entry.credentials);
      this.broadcast({ type: "connector.statusChanged", connection });
      this.broadcast({
        type: "connector.audit",
        connectionId: connection.id,
        provider: connection.provider,
        action: "connector.test",
        outcome: "failed",
        summary: "Connector is missing runtime credentials.",
      });
      return;
    }

    try {
      const probed = await probeConnector(entry);
      this.ctx.connectors.upsert(probed.connection, entry.credentials);
      this.broadcast({ type: "connector.statusChanged", connection: probed.connection });
      this.broadcast({
        type: "connector.audit",
        connectionId: probed.connection.id,
        provider: probed.connection.provider,
        action: "connector.test",
        outcome: probed.connection.status === "connected" ? "passed" : "warning",
        summary: probed.connection.statusMessage ?? "Connector test completed.",
      });
    } catch (error) {
      const connection = {
        ...entry.connection,
        status: "failed" as const,
        statusMessage: error instanceof Error ? error.message : "Connector test failed.",
        lastCheckedAt: new Date().toISOString(),
      };
      this.ctx.connectors.upsert(connection, entry.credentials);
      this.broadcast({ type: "connector.statusChanged", connection });
      this.broadcast({
        type: "connector.audit",
        connectionId: connection.id,
        provider: connection.provider,
        action: "connector.test",
        outcome: "failed",
        summary: connection.statusMessage,
      });
    }
  }

  private async handleDelegateTask(command: Extract<SidecarCommand, { type: "delegate.task" }>): Promise<void> {
    const config = this.ctx.agentDefinitions.get(command.toAgent);
    if (!config) {
      logger.error("ws", `delegate.task: agent definition not found for "${command.toAgent}"`);
      this.broadcast({
        type: "session.error",
        sessionId: command.sessionId,
        error: `Agent definition not found: ${command.toAgent}`,
      });
      return;
    }

    // Inherit the source session's working directory so delegated agents
    // work in the same place as the group (e.g. shared workspace).
    const sourceConfig = this.ctx.sessions.getConfig(command.sessionId);
    const effectiveConfig = sourceConfig?.workingDirectory
      ? { ...config, workingDirectory: sourceConfig.workingDirectory }
      : config;

    const prompt = command.context
      ? `${command.task}\n\n## Context\n${command.context}`
      : command.task;

    this.broadcast({
      type: "peer.delegate",
      from: this.ctx.sessions.get(command.sessionId)?.agentName ?? command.sessionId,
      to: command.toAgent,
      task: command.task,
    });

    // Instance policy routing: singleton reuses existing session, pool routes when at capacity
    const existingSessions = this.ctx.sessions.findByAgentName(config.name);
    if (config.instancePolicy === "singleton" && existingSessions.length > 0) {
      const target = existingSessions[0];
      this.ctx.messages.push(target.id, {
        id: crypto.randomUUID(),
        from: command.sessionId,
        fromAgent: this.ctx.sessions.get(command.sessionId)?.agentName ?? command.sessionId,
        to: target.id,
        text: `[Delegated Task] ${command.task}${command.context ? `\n\nContext: ${command.context}` : ""}`,
        priority: "urgent",
        timestamp: new Date().toISOString(),
        read: false,
      });
      logger.info("ws", `delegate.task: reused singleton session ${target.id} for ${command.toAgent}`);
      return;
    }

    if (config.instancePolicy === "pool") {
      const poolMax = config.instancePolicyPoolMax ?? 1;
      if (existingSessions.length >= poolMax) {
        let leastBusy = existingSessions[0];
        for (const s of existingSessions) {
          if (this.ctx.messages.peek(s.id) < this.ctx.messages.peek(leastBusy.id)) {
            leastBusy = s;
          }
        }
        this.ctx.messages.push(leastBusy.id, {
          id: crypto.randomUUID(),
          from: command.sessionId,
          fromAgent: this.ctx.sessions.get(command.sessionId)?.agentName ?? command.sessionId,
          to: leastBusy.id,
          text: `[Delegated Task] ${command.task}${command.context ? `\n\nContext: ${command.context}` : ""}`,
          priority: "urgent",
          timestamp: new Date().toISOString(),
          read: false,
        });
        logger.info("ws", `delegate.task: pool routed to ${leastBusy.id} for ${command.toAgent}`);
        return;
      }
    }

    const newSessionId = crypto.randomUUID();
    try {
      await this.ctx.spawnSession(newSessionId, effectiveConfig, prompt, command.waitForResult);
      logger.info("ws", `delegate.task: spawned new session ${newSessionId} for ${command.toAgent}`);
    } catch (err: any) {
      logger.error("ws", `delegate.task: spawn failed: ${err}`);
      this.broadcast({
        type: "session.error",
        sessionId: command.sessionId,
        error: `Delegation to ${command.toAgent} failed: ${err.message}`,
      });
    }
  }


  private async handleGenerateAgent(
    command: Extract<SidecarCommand, { type: "generate.agent" }>
  ): Promise<void> {

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

    const skillsCatalog = command.availableSkills.length > 0
      ? command.availableSkills
          .map((s) => `- ID: ${s.id} | Name: ${s.name} | Category: ${s.category} | Description: ${s.description}`)
          .join("\n")
      : "(no skills available)";

    const mcpsCatalog = command.availableMCPs.length > 0
      ? command.availableMCPs
          .map((m) => `- ID: ${m.id} | Name: ${m.name} | Description: ${m.description}`)
          .join("\n")
      : "(no MCP servers available)";

    const systemPrompt = `You are an agent designer. Given a user's description of an AI agent they want to create, generate a complete agent definition as JSON.

## Output Format
Return ONLY valid JSON (no markdown, no code fences) with this exact schema:
{
  "name": "string (short, 2-4 words)",
  "description": "string (one sentence describing what the agent does)",
  "systemPrompt": "string (detailed system prompt for the agent, 200-800 words, written in second person addressing the agent)",
  "model": "sonnet" | "opus" | "haiku",
  "icon": "string (SF Symbol name from the allowed list)",
  "color": "string (from the allowed list)",
  "matchedSkillIds": ["array of skill ID strings that are relevant"],
  "matchedMCPIds": ["array of MCP server ID strings that are relevant"],
  "maxTurns": null,
  "maxBudget": null
}

## Constraints
- icon must be one of: ${JSON.stringify(validIcons)}
- color must be one of: ${JSON.stringify(validColors)}
- model: use "sonnet" for most agents, "opus" for agents that need deep reasoning or complex analysis, "haiku" for simple/fast agents
- matchedSkillIds: only include IDs from the available skills catalog below. Pick skills that are directly relevant.
- matchedMCPIds: only include IDs from the available MCPs catalog below. Pick MCPs that are directly relevant.
- The systemPrompt should be focused, actionable, and specific to the agent's purpose. Write it as instructions to the AI agent.

## Available Skills
${skillsCatalog}

## Available MCP Servers
${mcpsCatalog}`;

    logger.info("ws", `generate.agent: generating agent from prompt: "${command.prompt.substring(0, 100)}..."`);

    const rawText = await this.generationService.generate(systemPrompt, command.prompt, command.model);
    const jsonText = this.generationService.extractJSON(rawText);
    const spec = JSON.parse(jsonText);

    // Validate required fields
    if (!spec.name || !spec.systemPrompt) {
      throw new Error("Generated spec missing required fields (name, systemPrompt)");
    }

    // Ensure valid icon and color
    if (!validIcons.includes(spec.icon)) spec.icon = "cpu";
    if (!validColors.includes(spec.color)) spec.color = "blue";
    if (!["sonnet", "opus", "haiku"].includes(spec.model)) spec.model = "sonnet";

    logger.info("ws", `generate.agent: generated "${spec.name}" with ${spec.matchedSkillIds?.length ?? 0} skills, ${spec.matchedMCPIds?.length ?? 0} MCPs`);

    this.broadcast({
      type: "generate.agent.result",
      requestId: command.requestId,
      spec: {
        name: spec.name,
        description: spec.description ?? "",
        systemPrompt: spec.systemPrompt,
        model: spec.model ?? "sonnet",
        icon: spec.icon ?? "cpu",
        color: spec.color ?? "blue",
        matchedSkillIds: Array.isArray(spec.matchedSkillIds) ? spec.matchedSkillIds : [],
        matchedMCPIds: Array.isArray(spec.matchedMCPIds) ? spec.matchedMCPIds : [],
        maxTurns: spec.maxTurns ?? 30,
        maxBudget: spec.maxBudget ?? undefined,
      },
    });
  }

  private async handleGenerateGroup(
    command: Extract<SidecarCommand, { type: "generate.group" }>
  ): Promise<void> {

    const validColors = ["blue", "red", "green", "purple", "orange", "yellow", "pink", "teal", "indigo", "gray"];

    const agentsCatalog = command.availableAgents.length > 0
      ? command.availableAgents
          .map((a) => `- ID: ${a.id} | Name: ${a.name} | Description: ${a.description}`)
          .join("\n")
      : "(no agents available)";

    const systemPrompt = `You are a group designer for an AI agent collaboration system. Given a user's description of a group they want to create, generate a complete group definition as JSON.

## Output Format
Return ONLY valid JSON (no markdown, no code fences) with this exact schema:
{
  "name": "string (short, 2-4 words)",
  "description": "string (one sentence describing the group's purpose)",
  "icon": "string (single emoji representing the group)",
  "color": "string (from the allowed list)",
  "groupInstruction": "string (instructions injected at the start of each group conversation, 100-400 words)",
  "defaultMission": "string or null (optional pre-filled mission prompt for the group)",
  "matchedAgentIds": ["array of agent ID strings to include in this group"]
}

## Constraints
- icon must be a single emoji character (e.g. "🔧", "📊", "🛡️")
- color must be one of: ${JSON.stringify(validColors)}
- matchedAgentIds: only include IDs from the available agents catalog below. Pick agents that are directly relevant to the group's purpose.
- The groupInstruction should describe how the agents should collaborate, their roles, and the group's working methodology.

## Available Agents
${agentsCatalog}`;

    logger.info("ws", `generate.group: generating group from prompt: "${command.prompt.substring(0, 100)}..."`);

    const rawText = await this.generationService.generate(systemPrompt, command.prompt, command.model);
    const jsonText = this.generationService.extractJSON(rawText);
    const spec = JSON.parse(jsonText);

    if (!spec.name || !spec.groupInstruction) {
      throw new Error("Generated spec missing required fields (name, groupInstruction)");
    }

    if (!validColors.includes(spec.color)) spec.color = "blue";

    logger.info("ws", `generate.group: generated "${spec.name}" with ${spec.matchedAgentIds?.length ?? 0} agents`);

    this.broadcast({
      type: "generate.group.result",
      requestId: command.requestId,
      groupSpec: {
        name: spec.name,
        description: spec.description ?? "",
        icon: spec.icon ?? "👥",
        color: spec.color ?? "blue",
        groupInstruction: spec.groupInstruction,
        defaultMission: spec.defaultMission ?? undefined,
        matchedAgentIds: Array.isArray(spec.matchedAgentIds) ? spec.matchedAgentIds : [],
      },
    });
  }

  private async handleGenerateSkill(
    command: Extract<SidecarCommand, { type: "generate.skill" }>
  ): Promise<void> {

    const validCategories = command.availableCategories.length > 0
      ? command.availableCategories.join(", ")
      : "General, Security, Code Review, Architecture, Testing, DevOps";

    const mcpsCatalog = command.availableMCPs.length > 0
      ? command.availableMCPs
          .map((m) => `- ID: ${m.id} | Name: ${m.name} | Description: ${m.description}`)
          .join("\n")
      : "(no MCP servers available)";

    const systemPrompt = `You are a skill designer for an AI agent system. Given a user's description of a skill they want to create, generate a complete skill definition as JSON.

## Output Format
Return ONLY valid JSON (no markdown, no code fences) with this exact schema:
{
  "name": "string (short, 2-4 words)",
  "description": "string (one sentence describing what this skill teaches the agent)",
  "category": "string (one of the available categories)",
  "triggers": ["array of keyword strings that cause this skill to activate"],
  "matchedMCPIds": ["array of MCP server ID strings that are relevant"],
  "content": "string (markdown body shown to the agent at runtime, 200-600 words)"
}

## Constraints
- category must be one of: ${validCategories}
- triggers: 3-6 short keyword phrases
- matchedMCPIds: only include IDs from the available MCPs catalog below
- content: write as detailed instructions/knowledge the agent should apply. Use markdown headings and bullet points.

## Available MCP Servers
${mcpsCatalog}`;

    logger.info("ws", `generate.skill: generating skill from prompt: "${command.prompt.substring(0, 100)}..."`);

    const rawText = await this.generationService.generate(systemPrompt, command.prompt, command.model);
    const jsonText = this.generationService.extractJSON(rawText);
    const spec = JSON.parse(jsonText);

    if (!spec.name || !spec.content) {
      throw new Error("Generated skill spec missing required fields (name, content)");
    }

    logger.info("ws", `generate.skill: generated "${spec.name}" in category "${spec.category}"`);

    this.broadcast({
      type: "generate.skill.result",
      requestId: command.requestId,
      skillSpec: {
        name: spec.name,
        description: spec.description ?? "",
        category: spec.category ?? "General",
        triggers: Array.isArray(spec.triggers) ? spec.triggers : [],
        matchedMCPIds: Array.isArray(spec.matchedMCPIds) ? spec.matchedMCPIds : [],
        content: spec.content,
      },
    });
  }

  private async handleGenerateTemplate(
    command: Extract<SidecarCommand, { type: "generate.template" }>
  ): Promise<void> {

    const agentContext = command.agentSystemPrompt
      ? `\n\n## Agent System Prompt\n${command.agentSystemPrompt.substring(0, 500)}`
      : "";

    const systemPrompt = `You are a prompt template designer. Given a user's intent description, generate a concise prompt template for an AI agent named "${command.agentName}".

## Output Format
Return ONLY valid JSON (no markdown, no code fences) with this exact schema:
{
  "name": "string (short action phrase, 3-6 words, e.g. 'Review PR for Security')",
  "prompt": "string (the prompt text the user will send to the agent, 1-4 sentences)"
}

## Constraints
- name: imperative phrase, title-cased, under 50 chars
- prompt: clear, actionable, specific to the agent's capabilities. May include {{placeholder}} for values the user fills in at runtime.
- Write the prompt as if the user is sending it — not as a system instruction.${agentContext}`;

    logger.info("ws", `generate.template: generating template for agent "${command.agentName}"`);

    const rawTemplateText = await this.generationService.generate(systemPrompt, command.intent, command.model);
    const jsonText = this.generationService.extractJSON(rawTemplateText);

    const spec = JSON.parse(jsonText);

    if (!spec.name || !spec.prompt) {
      throw new Error("Generated template spec missing required fields (name, prompt)");
    }

    logger.info("ws", `generate.template: generated "${spec.name}"`);

    this.broadcast({
      type: "generate.template.result",
      requestId: command.requestId,
      templateSpec: {
        name: spec.name,
        prompt: spec.prompt,
      },
    });
  }

  setGHBridge(poller: GHPoller, router: GHRouter): void {
    this.ghPoller = poller;
    this.ghRouter = router;
  }

  broadcast(event: SidecarEvent): void {
    const data = JSON.stringify(event);
    for (const client of this.clients) {
      try {
        client.send(data);
      } catch {
        this.clients.delete(client);
      }
    }
  }

  close(): void {
    this.server?.stop(true);
    this.server = null;
  }
}
