export interface ParticipantWire {
  id: string;
  displayName: string;
  isAgent: boolean;
  isLocal: boolean;
}

export interface ConversationSummaryWire {
  id: string;
  topic: string;
  lastMessageAt: string;
  lastMessagePreview: string;
  unread: boolean;
  participants: ParticipantWire[];
  projectId: string | null;
  projectName: string | null;
  workingDirectory: string | null;
}

export interface MessageWire {
  id: string;
  text: string;
  type: string;
  senderParticipantId: string | null;
  timestamp: string;
  isStreaming: boolean;
  toolName?: string;
  toolOutput?: string;
  thinkingText?: string;
}

export class ConversationStore {
  private conversations = new Map<string, ConversationSummaryWire>();
  private messages = new Map<string, MessageWire[]>();

  sync(conversations: ConversationSummaryWire[]): void {
    this.conversations.clear();
    for (const c of conversations) {
      this.conversations.set(c.id, c);
    }
  }

  appendMessage(conversationId: string, message: MessageWire): void {
    const msgs = this.messages.get(conversationId) ?? [];
    const idx = msgs.findIndex(m => m.id === message.id);
    if (idx >= 0) {
      msgs[idx] = message;
    } else {
      msgs.push(message);
    }
    this.messages.set(conversationId, msgs);
    const conv = this.conversations.get(conversationId);
    if (conv && !message.isStreaming) {
      this.conversations.set(conversationId, {
        ...conv,
        lastMessageAt: message.timestamp,
        lastMessagePreview: message.text.slice(0, 100),
      });
    }
  }

  listConversations(): ConversationSummaryWire[] {
    return Array.from(this.conversations.values())
      .sort((a, b) => b.lastMessageAt.localeCompare(a.lastMessageAt));
  }

  getMessages(conversationId: string, limit?: number, before?: string): MessageWire[] {
    let msgs = this.messages.get(conversationId) ?? [];
    msgs = [...msgs].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    if (before) {
      msgs = msgs.filter(m => m.timestamp < before);
    }
    if (limit !== undefined && limit > 0) {
      msgs = msgs.slice(-limit);
    } else if (limit === 0) {
      msgs = [];
    }
    return msgs;
  }

  hasConversation(id: string): boolean {
    return this.conversations.has(id);
  }

  clearMessages(conversationId: string): void {
    this.messages.set(conversationId, []);
  }

  /** Create a minimal conversation entry for iOS-initiated sessions that don't originate from Mac SwiftData. */
  ensureConversation(id: string, topic: string): void {
    if (!this.conversations.has(id)) {
      this.conversations.set(id, {
        id,
        topic,
        lastMessageAt: new Date().toISOString(),
        lastMessagePreview: "",
        unread: false,
        participants: [],
        projectId: null,
        projectName: null,
        workingDirectory: null,
      });
    }
  }
}
