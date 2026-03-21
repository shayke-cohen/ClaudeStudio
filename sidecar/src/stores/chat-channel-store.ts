import { randomUUID } from "crypto";

export interface ChatChannel {
  id: string;
  topic?: string;
  participants: string[];
  messages: ChannelMessage[];
  status: "open" | "closed";
  summary?: string;
  createdAt: string;
}

export interface ChannelMessage {
  from: string;
  fromAgent: string;
  text: string;
  timestamp: string;
}

interface WaitingResolver {
  sessionId: string;
  resolve: (value: ChannelMessage | { closed: true; summary?: string }) => void;
}

export class ChatChannelStore {
  private channels = new Map<string, ChatChannel>();
  private waiters = new Map<string, WaitingResolver[]>();
  /** Tracks which session is blocked on which channel (for deadlock detection) */
  private blockedOn = new Map<string, string>();

  create(
    initiator: string,
    initiatorAgent: string,
    target: string,
    firstMessage: string,
    topic?: string,
  ): ChatChannel {
    const id = randomUUID();
    const msg: ChannelMessage = {
      from: initiator,
      fromAgent: initiatorAgent,
      text: firstMessage,
      timestamp: new Date().toISOString(),
    };
    const channel: ChatChannel = {
      id,
      topic,
      participants: [initiator, target],
      messages: [msg],
      status: "open",
      createdAt: new Date().toISOString(),
    };
    this.channels.set(id, channel);
    this.waiters.set(id, []);
    return channel;
  }

  get(channelId: string): ChatChannel | undefined {
    return this.channels.get(channelId);
  }

  addParticipant(channelId: string, sessionId: string): boolean {
    const channel = this.channels.get(channelId);
    if (!channel || channel.status === "closed") return false;
    if (!channel.participants.includes(sessionId)) {
      channel.participants.push(sessionId);
    }
    return true;
  }

  addMessage(
    channelId: string,
    from: string,
    fromAgent: string,
    text: string,
  ): ChannelMessage | undefined {
    const channel = this.channels.get(channelId);
    if (!channel || channel.status === "closed") return undefined;

    const msg: ChannelMessage = {
      from,
      fromAgent,
      text,
      timestamp: new Date().toISOString(),
    };
    channel.messages.push(msg);

    const waiters = this.waiters.get(channelId) ?? [];
    const toNotify = waiters.filter((w) => w.sessionId !== from);
    for (const w of toNotify) {
      w.resolve(msg);
      this.blockedOn.delete(w.sessionId);
    }
    this.waiters.set(
      channelId,
      waiters.filter((w) => !toNotify.includes(w)),
    );

    return msg;
  }

  /**
   * Block until a message arrives on this channel from someone other than `sessionId`.
   * Returns the message, or `{ closed: true }` if the channel is closed while waiting.
   */
  waitForReply(
    channelId: string,
    sessionId: string,
    timeoutMs: number = 120_000,
  ): Promise<ChannelMessage | { closed: true; summary?: string }> {
    const channel = this.channels.get(channelId);
    if (!channel || channel.status === "closed") {
      return Promise.resolve({ closed: true, summary: channel?.summary });
    }

    if (this.wouldDeadlock(sessionId, channelId)) {
      return Promise.resolve({
        closed: true,
        summary: "deadlock_detected: circular wait between agents",
      });
    }

    this.blockedOn.set(sessionId, channelId);

    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.blockedOn.delete(sessionId);
        const waiters = this.waiters.get(channelId) ?? [];
        this.waiters.set(channelId, waiters.filter((w) => w.sessionId !== sessionId));
        resolve({ closed: true, summary: "timeout" });
      }, timeoutMs);

      const wrappedResolve = (val: ChannelMessage | { closed: true; summary?: string }) => {
        clearTimeout(timer);
        this.blockedOn.delete(sessionId);
        resolve(val);
      };

      const waiters = this.waiters.get(channelId) ?? [];
      waiters.push({ sessionId, resolve: wrappedResolve });
      this.waiters.set(channelId, waiters);
    });
  }

  /**
   * Wait for any incoming chat request directed at `sessionId`.
   */
  waitForIncoming(
    sessionId: string,
    timeoutMs: number = 30_000,
  ): Promise<ChatChannel | null> {
    return new Promise((resolve) => {
      const timer = setTimeout(() => resolve(null), timeoutMs);

      const check = () => {
        for (const channel of this.channels.values()) {
          if (
            channel.status === "open" &&
            channel.participants.includes(sessionId) &&
            channel.messages.length > 0 &&
            channel.messages[0].from !== sessionId
          ) {
            const lastMsg = channel.messages[channel.messages.length - 1];
            if (lastMsg.from !== sessionId) {
              clearTimeout(timer);
              resolve(channel);
              return;
            }
          }
        }
      };

      check();
      if (timeoutMs > 0) {
        const interval = setInterval(() => {
          check();
        }, 500);
        setTimeout(() => clearInterval(interval), timeoutMs);
      }
    });
  }

  close(channelId: string, summary?: string): void {
    const channel = this.channels.get(channelId);
    if (!channel) return;

    channel.status = "closed";
    channel.summary = summary;

    const waiters = this.waiters.get(channelId) ?? [];
    for (const w of waiters) {
      w.resolve({ closed: true, summary });
      this.blockedOn.delete(w.sessionId);
    }
    this.waiters.set(channelId, []);
  }

  list(): ChatChannel[] {
    return Array.from(this.channels.values());
  }

  listOpen(): ChatChannel[] {
    return this.list().filter((c) => c.status === "open");
  }

  private wouldDeadlock(sessionId: string, channelId: string): boolean {
    const channel = this.channels.get(channelId);
    if (!channel) return false;

    const visited = new Set<string>();
    const queue = channel.participants.filter((p) => p !== sessionId);

    while (queue.length > 0) {
      const current = queue.shift()!;
      if (visited.has(current)) continue;
      visited.add(current);

      const blockedChannel = this.blockedOn.get(current);
      if (!blockedChannel) continue;

      const bc = this.channels.get(blockedChannel);
      if (!bc) continue;

      if (bc.participants.includes(sessionId)) return true;

      for (const p of bc.participants) {
        if (!visited.has(p)) queue.push(p);
      }
    }
    return false;
  }
}
