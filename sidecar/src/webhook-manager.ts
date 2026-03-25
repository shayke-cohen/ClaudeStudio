import type { SidecarEvent, WebhookRegistration } from "./types.js";

const MAX_WEBHOOKS = 50;
const MAX_RETRIES = 3;
const MAX_FAILURES_BEFORE_DISABLE = 10;

/**
 * Manages webhook registrations and dispatches events to registered callback URLs.
 * Webhooks are in-memory (ephemeral) — acceptable for localhost MVP.
 */
export class WebhookManager {
  private webhooks = new Map<string, WebhookRegistration>();

  register(url: string, events: string[], sessionFilter?: string): WebhookRegistration {
    if (this.webhooks.size >= MAX_WEBHOOKS) {
      throw new Error(`Maximum webhook registrations (${MAX_WEBHOOKS}) reached`);
    }

    const id = `wh_${crypto.randomUUID().slice(0, 8)}`;
    const registration: WebhookRegistration = {
      id,
      url,
      events,
      sessionFilter,
      failureCount: 0,
      disabled: false,
      createdAt: new Date().toISOString(),
    };
    this.webhooks.set(id, registration);
    console.log(`[webhook] Registered ${id} → ${url} (events: ${events.join(", ")})`);
    return registration;
  }

  unregister(id: string): boolean {
    const deleted = this.webhooks.delete(id);
    if (deleted) console.log(`[webhook] Unregistered ${id}`);
    return deleted;
  }

  list(): WebhookRegistration[] {
    return Array.from(this.webhooks.values());
  }

  /**
   * Dispatch an event to all matching webhooks.
   * Matches by event type and optional session filter.
   * Retries on failure with exponential backoff.
   */
  dispatch(event: SidecarEvent): void {
    const sessionId = "sessionId" in event ? (event as any).sessionId : undefined;

    for (const webhook of this.webhooks.values()) {
      if (webhook.disabled) continue;
      if (!webhook.events.includes(event.type)) continue;
      if (webhook.sessionFilter && webhook.sessionFilter !== sessionId) continue;

      this.deliverWithRetry(webhook, event).catch((err) => {
        console.error(`[webhook] Final delivery failure for ${webhook.id}:`, err.message);
      });
    }
  }

  private async deliverWithRetry(webhook: WebhookRegistration, event: SidecarEvent): Promise<void> {
    const delays = [1000, 4000, 16000]; // exponential backoff

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      try {
        const response = await fetch(webhook.url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-ClaudPeer-Event": event.type,
            "X-ClaudPeer-Webhook-Id": webhook.id,
          },
          body: JSON.stringify(event),
          signal: AbortSignal.timeout(10_000),
        });

        if (response.ok) {
          // Reset failure count on success
          webhook.failureCount = 0;
          return;
        }

        throw new Error(`HTTP ${response.status}`);
      } catch (err: any) {
        if (attempt < MAX_RETRIES) {
          await new Promise((r) => setTimeout(r, delays[attempt]));
        } else {
          webhook.failureCount++;
          if (webhook.failureCount >= MAX_FAILURES_BEFORE_DISABLE) {
            webhook.disabled = true;
            console.warn(`[webhook] Disabled ${webhook.id} after ${MAX_FAILURES_BEFORE_DISABLE} consecutive failures`);
          }
        }
      }
    }
  }
}
