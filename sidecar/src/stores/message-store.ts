export interface PeerMessage {
  id: string;
  from: string;
  fromAgent: string;
  to: string;
  text: string;
  channel?: string;
  priority: "normal" | "urgent";
  timestamp: string;
  read: boolean;
}

export class MessageStore {
  private inboxes = new Map<string, PeerMessage[]>();

  push(to: string, message: PeerMessage): void {
    const inbox = this.inboxes.get(to) ?? [];
    inbox.push(message);
    this.inboxes.set(to, inbox);
  }

  pushToAll(message: Omit<PeerMessage, "to">, sessionIds: string[]): void {
    for (const sid of sessionIds) {
      if (sid === message.from) continue;
      this.push(sid, { ...message, to: sid });
    }
  }

  drain(sessionId: string, since?: string): PeerMessage[] {
    const inbox = this.inboxes.get(sessionId) ?? [];
    if (!since) {
      const messages = inbox.filter((m) => !m.read);
      for (const m of messages) m.read = true;
      return messages;
    }
    const sinceTime = new Date(since).getTime();
    const messages = inbox.filter(
      (m) => !m.read && new Date(m.timestamp).getTime() > sinceTime,
    );
    for (const m of messages) m.read = true;
    return messages;
  }

  peek(sessionId: string): number {
    const inbox = this.inboxes.get(sessionId) ?? [];
    return inbox.filter((m) => !m.read).length;
  }
}
