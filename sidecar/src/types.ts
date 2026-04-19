import type { ConversationSummaryWire, MessageWire } from "./stores/conversation-store.js";
import type { ProjectSummaryWire } from "./stores/project-store.js";

export type { ConversationSummaryWire, MessageWire, ParticipantWire } from "./stores/conversation-store.js";
export type { ProjectSummaryWire } from "./stores/project-store.js";

// Delegation modes for agent question routing
export type DelegationMode = "off" | "by_agents" | "specific_agent" | "coordinator";

// Commands from Swift -> Sidecar
export type SidecarCommand =
  | { type: "session.create"; conversationId: string; agentConfig: AgentConfig }
  | { type: "session.message"; sessionId: string; text: string; attachments?: FileAttachment[]; planMode?: boolean }
  | { type: "session.resume"; sessionId: string; claudeSessionId: string }
  | { type: "session.fork"; sessionId: string; childSessionId: string }
  | { type: "session.pause"; sessionId: string }
  | { type: "session.updateMode"; sessionId: string; interactive: boolean; instancePolicy?: "spawn" | "singleton" | "pool"; instancePolicyPoolMax?: number }
  | { type: "session.bulkResume"; sessions: BulkResumeEntry[] }
  | { type: "agent.register"; agents: AgentDefinition[] }
  | { type: "delegate.task"; sessionId: string; toAgent: string; task: string; context?: string; waitForResult: boolean }
  | { type: "peer.register"; name: string; endpoint: string; agents: PeerAgentWire[] }
  | { type: "peer.remove"; name: string }
  | { type: "nostr.addPeer"; name: string; pubkeyHex: string; relays: string[] }
  | { type: "nostr.removePeer"; name: string }
  | { type: "generate.agent"; requestId: string; prompt: string; availableSkills: SkillCatalogEntry[]; availableMCPs: MCPCatalogEntry[] }
  | { type: "generate.skill"; requestId: string; prompt: string; availableCategories: string[]; availableMCPs: MCPCatalogEntry[] }
  | { type: "generate.template"; requestId: string; intent: string; agentName: string; agentSystemPrompt: string }
  | { type: "session.questionAnswer"; sessionId: string; questionId: string; answer: string; selectedOptions?: string[] }
  | { type: "session.confirmationAnswer"; sessionId: string; confirmationId: string; approved: boolean; modifiedAction?: string }
  | { type: "session.updateCwd"; sessionId: string; workingDirectory: string }
  | { type: "connector.list" }
  | { type: "connector.beginAuth"; connection: ConnectorConfig }
  | { type: "connector.completeAuth"; connection: ConnectorConfig; credentials?: ConnectorCredentials }
  | { type: "connector.revoke"; connectionId: string }
  | { type: "connector.test"; connectionId: string }
  | { type: "config.setOllama"; enabled: boolean; baseURL: string }
  | { type: "config.setLogLevel"; level: string }
  | { type: "conversation.sync"; conversations: ConversationSummaryWire[] }
  | { type: "conversation.messageAppend"; conversationId: string; message: MessageWire }
  | { type: "conversation.setDelegationMode"; sessionId: string; mode: DelegationMode; targetAgentName?: string }
  | { type: "conversation.evaluate"; conversationId: string; goal?: string; coordinatorSessionId?: string; sessionIds?: string[] }
  | { type: "project.sync"; projects: ProjectSummaryWire[] }
  | { type: "ios.registerPush"; apnsToken: string; appId: string }
  | { type: "conversation.clear"; conversationId: string }
  | { type: "session.updateModel"; sessionId: string; model: string }
  | { type: "session.updateEffort"; sessionId: string; effort: "low" | "medium" | "high" | "max" }
  | { type: "browser.result";      sessionId: string; commandType: string; payload: string }
  | { type: "browser.error";       sessionId: string; commandType: string; error: string }
  | { type: "browser.pageLoaded";  sessionId: string; url: string; title: string }
  | { type: "browser.userSubmit";  sessionId: string; data: string }
  | { type: "browser.stateChange"; sessionId: string; state: "agentDriving" | "userDriving" | "yieldedToUser" };

export interface PeerAgentWire {
  name: string;
  config: AgentConfig;
}

export interface BulkResumeEntry {
  sessionId: string;
  claudeSessionId: string;
  agentConfig: AgentConfig;
}

export interface AgentDefinition {
  name: string;
  config: AgentConfig;
  instancePolicy?: string; // "spawn" | "singleton" | "pool:N"
}

export interface AgentConfig {
  name: string;
  systemPrompt: string;
  allowedTools: string[];
  mcpServers: MCPServerConfig[];
  provider?: AgentProvider;
  model: string;
  maxTurns?: number;
  maxBudget?: number;
  maxThinkingTokens?: number;
  workingDirectory: string;
  skills: SkillContent[];
  interactive?: boolean;
  instancePolicy?: "spawn" | "singleton" | "pool";
  instancePolicyPoolMax?: number;
}

export type AgentProvider = "claude" | "codex" | "foundation" | "mlx" | "mock";

export interface MCPServerConfig {
  name: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  url?: string;
}

export type SessionMCPAvailability =
  | "configured"
  | "loaded"
  | "failed"
  | "needs-auth"
  | "pending"
  | "disabled"
  | "unavailable";

export type SessionMCPSource = "configured" | "sdk" | "dynamic";

export interface SessionMCPToolInfo {
  name: string;
  description?: string;
}

export interface SessionMCPServerState {
  name: string;
  namespace: string;
  source: SessionMCPSource;
  transport: "stdio" | "sse" | "sdk" | "dynamic";
  configured: boolean;
  availability: SessionMCPAvailability;
  providerStatus?: string;
  error?: string;
  tools?: SessionMCPToolInfo[];
}

export interface SkillContent {
  name: string;
  content: string;
}

export interface FileAttachment {
  data: string;
  mediaType: string;
  fileName?: string;
}

export interface SkillCatalogEntry {
  id: string;
  name: string;
  description: string;
  category: string;
}

export interface MCPCatalogEntry {
  id: string;
  name: string;
  description: string;
}

export type ConnectorProvider = "slack" | "linkedin" | "x" | "facebook" | "whatsapp";
export type ConnectorInstallScope = "system";
export type ConnectorAuthMode = "pkce-native" | "brokered";
export type ConnectionWritePolicy = "require-approval" | "autonomous" | "read-only";
export type ConnectorStatus =
  | "disconnected"
  | "authorizing"
  | "connected"
  | "needs-attention"
  | "revoked"
  | "failed";

export interface ConnectorConfig {
  id: string;
  provider: ConnectorProvider;
  installScope: ConnectorInstallScope;
  displayName: string;
  accountId?: string;
  accountHandle?: string;
  accountMetadataJSON?: string;
  grantedScopes: string[];
  authMode: ConnectorAuthMode;
  writePolicy: ConnectionWritePolicy;
  status: ConnectorStatus;
  statusMessage?: string;
  brokerReference?: string;
  auditSummary?: string;
  lastAuthenticatedAt?: string;
  lastCheckedAt?: string;
}

export interface ConnectorCredentials {
  accessToken?: string;
  refreshToken?: string;
  tokenType?: string;
  expiresAt?: string;
  brokerReference?: string;
}

export interface ConnectorCapability {
  toolName: string;
  provider: ConnectorProvider;
  title: string;
  description: string;
  access: "read" | "write";
  requiredScopes: string[];
}

export interface GeneratedAgentSpec {
  name: string;
  description: string;
  systemPrompt: string;
  model: string;
  icon: string;
  color: string;
  matchedSkillIds: string[];
  matchedMCPIds: string[];
  maxTurns?: number;
  maxBudget?: number;
}

export interface GeneratedSkillSpec {
  name: string;
  description: string;
  category: string;
  triggers: string[];
  matchedMCPIds: string[];
  content: string;
}

export interface GeneratedTemplateSpec {
  name: string;
  prompt: string;
}

// Events from Sidecar -> Swift
export type SidecarEvent =
  | { type: "stream.token"; sessionId: string; text: string }
  | { type: "stream.thinking"; sessionId: string; text: string }
  | { type: "stream.toolCall"; sessionId: string; tool: string; input: string }
  | { type: "stream.toolResult"; sessionId: string; tool: string; output: string }
  | { type: "session.result"; sessionId: string; result: string; cost: number;
      inputTokens: number; outputTokens: number; numTurns: number; toolCallCount: number }
  | { type: "session.error"; sessionId: string; error: string }
  | { type: "session.forked"; parentSessionId: string; childSessionId: string }
  | { type: "peer.chat"; channelId: string; from: string; message: string }
  | { type: "peer.delegate"; from: string; to: string; task: string }
  | { type: "blackboard.update"; key: string; value: string; writtenBy: string }
  | { type: "stream.image"; sessionId: string; imageData: string; mediaType: string; fileName?: string }
  | { type: "stream.fileCard"; sessionId: string; filePath: string; fileType: "html" | "pdf"; fileName: string }
  | { type: "session.reused"; originalSessionId: string; reusedSessionId: string }
  | { type: "sidecar.ready"; port: number; version: string }
  | { type: "generate.agent.result"; requestId: string; spec: GeneratedAgentSpec }
  | { type: "generate.agent.error"; requestId: string; error: string }
  | { type: "generate.skill.result"; requestId: string; spec: GeneratedSkillSpec }
  | { type: "generate.skill.error"; requestId: string; error: string }
  | { type: "generate.template.result"; requestId: string; spec: GeneratedTemplateSpec }
  | { type: "generate.template.error"; requestId: string; error: string }
  | { type: "agent.question"; sessionId: string; questionId: string; question: string; options?: QuestionOption[]; multiSelect: boolean; private: boolean; inputType?: QuestionInputType; inputConfig?: QuestionInputConfig; timeoutSeconds?: number; autoRouting?: boolean }
  | { type: "agent.confirmation"; sessionId: string; confirmationId: string; action: string; reason: string; riskLevel: "low" | "medium" | "high"; details?: string }
  | { type: "agent.question.routing"; sessionId: string; questionId: string; targetAgentName: string }
  | { type: "agent.question.resolved"; sessionId: string; questionId: string; answeredBy: string; isFallback: boolean; answer?: string }
  | { type: "stream.richContent"; sessionId: string; format: "html" | "mermaid" | "markdown"; title?: string; content: string; height?: number }
  | { type: "stream.progress"; sessionId: string; progressId: string; title: string; steps: ProgressStep[] }
  | { type: "stream.suggestions"; sessionId: string; suggestions: SuggestionItem[] }
  | { type: "conversation.inviteAgent"; sessionId: string; agentName: string }
  | { type: "session.planComplete"; sessionId: string; plan: string | null; allowedPrompts?: { tool: string; prompt: string }[] }
  | { type: "conversation.idle"; conversationId: string }
  | { type: "conversation.idleResult"; conversationId: string; status: "complete" | "needsMore" | "failed"; reason: string }
  | { type: "connector.list.result"; connections: ConnectorConfig[] }
  | { type: "connector.statusChanged"; connection: ConnectorConfig }
  | { type: "connector.audit"; sessionId?: string; connectionId: string; provider: ConnectorProvider; action: string; outcome: string; summary: string }
  | { type: "ios.pushRegistered"; apnsToken: string; success: boolean; error?: string }
  | { type: "nostr.status"; connectedRelays: number; totalRelays: number }
  | { type: "conversation.cleared"; conversationId: string }
  | { type: "browser.navigate";        sessionId: string; url: string }
  | { type: "browser.click";           sessionId: string; selector: string }
  | { type: "browser.type";            sessionId: string; selector: string; text: string }
  | { type: "browser.scroll";          sessionId: string; direction: "up" | "down"; px: number }
  | { type: "browser.screenshot";      sessionId: string }
  | { type: "browser.readDom";         sessionId: string }
  | { type: "browser.getConsoleLogs";  sessionId: string }
  | { type: "browser.getNetworkLogs";  sessionId: string }
  | { type: "browser.waitFor";         sessionId: string; selector: string; timeoutMs: number }
  | { type: "browser.yieldToUser";     sessionId: string; message: string }
  | { type: "browser.renderHtml";      sessionId: string; html: string; title?: string }
  | { type: "browser.takeControl";     sessionId: string }
  | { type: "browser.resume";          sessionId: string };

export interface QuestionOption {
  label: string;
  description?: string;
}

export type QuestionInputType = "text" | "options" | "rating" | "slider" | "toggle" | "dropdown" | "form";

export interface QuestionInputConfig {
  // rating
  maxRating?: number;        // default 5
  ratingLabels?: string[];   // e.g. ["Poor", "Fair", "Good", "Great", "Excellent"]
  // slider
  min?: number;
  max?: number;
  step?: number;
  unit?: string;             // e.g. "%" or "ms"
  // form
  fields?: FormField[];
}

export interface FormField {
  name: string;
  label: string;
  type: "text" | "number" | "toggle";
  placeholder?: string;
  required?: boolean;
}

export interface ProgressStep {
  label: string;
  status: "pending" | "running" | "done" | "error" | "skipped";
}

export interface SuggestionItem {
  label: string;
  message?: string;
}

// Session state
export interface SessionState {
  id: string;
  agentName: string;
  provider: AgentProvider;
  status: "active" | "paused" | "completed" | "failed";
  claudeSessionId?: string;
  tokenCount: number;
  cost: number;
  toolCallCount: number;
  startedAt: string;
  effectiveMcpServers: SessionMCPServerState[];
  mcpInventoryUpdatedAt?: string;
}

// Blackboard entry
export interface BlackboardEntry {
  key: string;
  value: string;
  writtenBy: string;
  workspaceId?: string;
  createdAt: string;
  updatedAt: string;
}

// ─── REST API Types ───

import type { SessionManager } from "./session-manager.js";
import type { ToolContext } from "./tools/tool-context.js";
import type { SseManager } from "./sse-manager.js";
import type { WebhookManager } from "./webhook-manager.js";

export interface ApiContext {
  sessionManager: SessionManager;
  toolCtx: ToolContext;
  sseManager: SseManager;
  webhookManager: WebhookManager;
}

// Request bodies

export interface CreateSessionRequest {
  agentName: string;
  message: string;
  workingDirectory?: string;
  attachments?: FileAttachment[];
  waitForResult?: boolean;
}

export interface SendMessageRequest {
  text: string;
  attachments?: FileAttachment[];
}

export interface ResumeSessionRequest {
  claudeSessionId?: string;
}

export interface DelegateRequest {
  toAgent: string;
  task: string;
  context?: string;
  waitForResult?: boolean;
}

export interface SendPeerMessageRequest {
  toAgent: string;
  message: string;
  priority?: "normal" | "urgent";
}

export interface BroadcastRequest {
  channel: string;
  message: string;
}

export interface AnswerQuestionRequest {
  answer: string;
  selectedOptions?: string[];
}

export interface RegisterWebhookRequest {
  url: string;
  events: string[];
  sessionFilter?: string;
}

// Response bodies

export interface ApiErrorResponse {
  error: string;
  message: string;
  status: number;
}

export interface WebhookRegistration {
  id: string;
  url: string;
  events: string[];
  sessionFilter?: string;
  failureCount: number;
  disabled: boolean;
  createdAt: string;
}

export type { OdysseyP2PEnvelope } from './relay/nostr-transport.js'

// ─── Browser wire types ─────────────────────────────────────────────────────

// Named aliases for browser-tools.ts — BrowserCommand is Sidecar→Swift, BrowserEvent is Swift→Sidecar
export type BrowserCommand =
  | { type: 'browser.navigate';        sessionId: string; url: string }
  | { type: 'browser.click';           sessionId: string; selector: string }
  | { type: 'browser.type';            sessionId: string; selector: string; text: string }
  | { type: 'browser.scroll';          sessionId: string; direction: 'up' | 'down'; px: number }
  | { type: 'browser.screenshot';      sessionId: string }
  | { type: 'browser.readDom';         sessionId: string }
  | { type: 'browser.getConsoleLogs';  sessionId: string }
  | { type: 'browser.getNetworkLogs';  sessionId: string }
  | { type: 'browser.waitFor';         sessionId: string; selector: string; timeoutMs: number }
  | { type: 'browser.yieldToUser';     sessionId: string; message: string }
  | { type: 'browser.renderHtml';      sessionId: string; html: string; title?: string }
  | { type: 'browser.takeControl';     sessionId: string }
  | { type: 'browser.resume';          sessionId: string }

export type BrowserEvent =
  | { type: 'browser.result';      sessionId: string; commandType: string; payload: string }
  | { type: 'browser.error';       sessionId: string; commandType: string; error: string }
  | { type: 'browser.pageLoaded';  sessionId: string; url: string; title: string }
  | { type: 'browser.userSubmit';  sessionId: string; data: string }
  | { type: 'browser.stateChange'; sessionId: string; state: 'agentDriving' | 'userDriving' | 'yieldedToUser' }
