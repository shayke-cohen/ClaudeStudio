import type { SidecarEvent } from "./types.js";

// Stub relay client — replaced by NostrTransport for WAN relay.
// LAN peer messaging still flows through direct WebSocket connections.
// This stub satisfies type-checker until call sites are migrated to NostrTransport.
export class RelayClient {
  constructor(_onEvent: (event: SidecarEvent) => void) {}

  isConnected(_peerName: string): boolean {
    return false;
  }

  async connect(_peerName: string, _endpoint: string): Promise<void> {}

  async sendCommand(
    _peerName: string,
    _command: unknown,
  ): Promise<{ result: string }> {
    throw new Error("RelayClient is a stub — use NostrTransport for WAN relay");
  }
}
