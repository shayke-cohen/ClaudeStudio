import type { BlackboardStore } from "../stores/blackboard-store.js";
import type { SessionRegistry } from "../stores/session-registry.js";
import type { MessageStore } from "../stores/message-store.js";
import type { ChatChannelStore } from "../stores/chat-channel-store.js";
import type { WorkspaceStore } from "../stores/workspace-store.js";
import type { PeerRegistry } from "../stores/peer-registry.js";
import type { RelayClient } from "../relay-client.js";
import type { SidecarEvent, AgentConfig } from "../types.js";

export interface ToolContext {
  blackboard: BlackboardStore;
  sessions: SessionRegistry;
  messages: MessageStore;
  channels: ChatChannelStore;
  workspaces: WorkspaceStore;
  peerRegistry: PeerRegistry;
  relayClient: RelayClient;
  broadcast: (event: SidecarEvent) => void;

  /**
   * Spawn a new autonomous session for delegation.
   * Returns a promise that resolves when the session completes (if waitForResult)
   * or immediately with the session ID.
   */
  spawnSession: (
    sessionId: string,
    config: AgentConfig,
    initialPrompt: string,
    waitForResult: boolean,
  ) => Promise<{ sessionId: string; result?: string }>;

  /** Agent definitions registered from Swift for delegation lookup */
  agentDefinitions: Map<string, AgentConfig>;
}
