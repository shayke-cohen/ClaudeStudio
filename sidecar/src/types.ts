// Commands from Swift -> Sidecar
export type SidecarCommand =
  | { type: "session.create"; conversationId: string; agentConfig: AgentConfig }
  | { type: "session.message"; sessionId: string; text: string; attachments?: FileAttachment[]; planMode?: boolean }
  | { type: "session.resume"; sessionId: string; claudeSessionId: string }
  | { type: "session.fork"; sessionId: string; childSessionId: string }
  | { type: "session.pause"; sessionId: string }
  | { type: "session.bulkResume"; sessions: BulkResumeEntry[] }
  | { type: "agent.register"; agents: AgentDefinition[] }
  | { type: "delegate.task"; sessionId: string; toAgent: string; task: string; context?: string; waitForResult: boolean }
  | { type: "peer.register"; name: string; endpoint: string; agents: PeerAgentWire[] }
  | { type: "peer.remove"; name: string }
  | { type: "generate.agent"; requestId: string; prompt: string; availableSkills: SkillCatalogEntry[]; availableMCPs: MCPCatalogEntry[] }
  | { type: "session.questionAnswer"; sessionId: string; questionId: string; answer: string; selectedOptions?: string[] }
  | { type: "session.confirmationAnswer"; sessionId: string; confirmationId: string; approved: boolean; modifiedAction?: string }
  | { type: "session.updateCwd"; sessionId: string; workingDirectory: string };

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
}

export interface AgentConfig {
  name: string;
  systemPrompt: string;
  allowedTools: string[];
  mcpServers: MCPServerConfig[];
  model: string;
  maxTurns?: number;
  maxBudget?: number;
  maxThinkingTokens?: number;
  workingDirectory: string;
  skills: SkillContent[];
  interactive?: boolean;
}

export interface MCPServerConfig {
  name: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  url?: string;
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
  | { type: "agent.question"; sessionId: string; questionId: string; question: string; options?: QuestionOption[]; multiSelect: boolean; private: boolean; inputType?: QuestionInputType; inputConfig?: QuestionInputConfig }
  | { type: "agent.confirmation"; sessionId: string; confirmationId: string; action: string; reason: string; riskLevel: "low" | "medium" | "high"; details?: string }
  | { type: "stream.richContent"; sessionId: string; format: "html" | "mermaid" | "markdown"; title?: string; content: string; height?: number }
  | { type: "stream.progress"; sessionId: string; progressId: string; title: string; steps: ProgressStep[] }
  | { type: "stream.suggestions"; sessionId: string; suggestions: SuggestionItem[] };

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
  status: "active" | "paused" | "completed" | "failed";
  claudeSessionId?: string;
  tokenCount: number;
  cost: number;
  toolCallCount: number;
  startedAt: string;
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
