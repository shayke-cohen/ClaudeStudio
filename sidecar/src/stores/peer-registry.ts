import type { AgentConfig } from "../types.js";

export interface RemotePeer {
  name: string;
  endpoint: string; // e.g., "ws://192.168.1.5:9849"
  agents: RemotePeerAgent[];
  lastSeen: Date;
  status: "connected" | "disconnected";
}

export interface RemotePeerAgent {
  name: string;
  config: AgentConfig;
}

export class PeerRegistry {
  private peers = new Map<string, RemotePeer>();

  register(name: string, endpoint: string, agents: RemotePeerAgent[]): void {
    this.peers.set(name, {
      name,
      endpoint,
      agents,
      lastSeen: new Date(),
      status: "connected",
    });
    console.log(`[peer-registry] Registered peer "${name}" with ${agents.length} agents at ${endpoint}`);
  }

  remove(name: string): void {
    this.peers.delete(name);
    console.log(`[peer-registry] Removed peer "${name}"`);
  }

  get(name: string): RemotePeer | undefined {
    return this.peers.get(name);
  }

  /** Find which peer owns an agent by name. */
  findAgentOwner(agentName: string): { peer: RemotePeer; agent: RemotePeerAgent } | undefined {
    for (const peer of this.peers.values()) {
      if (peer.status !== "connected") continue;
      const agent = peer.agents.find((a) => a.name === agentName);
      if (agent) return { peer, agent };
    }
    return undefined;
  }

  list(): RemotePeer[] {
    return Array.from(this.peers.values());
  }

  listConnected(): RemotePeer[] {
    return this.list().filter((p) => p.status === "connected");
  }
}
