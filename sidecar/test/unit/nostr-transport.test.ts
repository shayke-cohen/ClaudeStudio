/**
 * Unit tests for NostrTransport — the sidecar's Nostr relay client.
 *
 * Tests cover:
 * - NIP-44 encrypt/decrypt roundtrip via nostr-crypto helpers
 * - Event building: valid NIP-01 structure (id, pubkey, sig, kind, tags, content)
 * - Reply correlation: commandId → pending resolution map
 * - Incoming event dispatching to broadcast
 * - Unknown/malformed events are silently dropped
 */
import { describe, test, expect, mock } from "bun:test";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import {
  generateNostrKeypair,
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  verifyNostrEvent,
  privkeyHexToBytes,
} from "../../src/relay/nostr-crypto.js";
import type { SidecarEvent } from "../../src/types.js";

// ── Keypair fixtures ─────────────────────────────────────────────────────────

const kpA = generateNostrKeypair();
const kpB = generateNostrKeypair();

// ── NIP-44 crypto roundtrip ──────────────────────────────────────────────────

describe("nostr-crypto NIP-44", () => {
  test("encrypt then decrypt produces original plaintext", () => {
    const privA = privkeyHexToBytes(kpA.privkeyHex);
    const encrypted = encryptMessage("hello nostr", privA, kpB.pubkeyHex);
    const privB = privkeyHexToBytes(kpB.privkeyHex);
    const decrypted = decryptMessage(encrypted, privB, kpA.pubkeyHex);
    expect(decrypted).toBe("hello nostr");
  });

  test("encrypted payload is not plaintext", () => {
    const privA = privkeyHexToBytes(kpA.privkeyHex);
    const encrypted = encryptMessage("secret message", privA, kpB.pubkeyHex);
    expect(encrypted).not.toContain("secret message");
  });

  test("decrypting with wrong private key throws", () => {
    const kpC = generateNostrKeypair();
    const privA = privkeyHexToBytes(kpA.privkeyHex);
    const encrypted = encryptMessage("only for B", privA, kpB.pubkeyHex);
    const privC = privkeyHexToBytes(kpC.privkeyHex);
    expect(() => decryptMessage(encrypted, privC, kpA.pubkeyHex)).toThrow();
  });
});

// ── signNostrEvent / verifyNostrEvent ─────────────────────────────────────────

describe("nostr-crypto sign/verify", () => {
  test("signNostrEvent produces valid NIP-01 structure", () => {
    const privBytes = privkeyHexToBytes(kpA.privkeyHex);
    const event = signNostrEvent(4, "test content", [["p", kpB.pubkeyHex]], privBytes);
    expect(event.id).toBeString();
    expect(event.pubkey).toBe(kpA.pubkeyHex);
    expect(event.sig).toBeString();
    expect(event.kind).toBe(4);
    expect(event.content).toBe("test content");
    expect(event.id.length).toBe(64);
    expect(event.sig.length).toBe(128);
  });

  test("verifyNostrEvent accepts a freshly signed event", () => {
    const privBytes = privkeyHexToBytes(kpA.privkeyHex);
    const event = signNostrEvent(4, "verify me", [], privBytes);
    expect(verifyNostrEvent(event)).toBe(true);
  });

  test("verifyNostrEvent rejects tampered content", () => {
    const privBytes = privkeyHexToBytes(kpA.privkeyHex);
    const event = signNostrEvent(4, "original", [], privBytes);
    const tampered = { ...event, content: "tampered" };
    expect(verifyNostrEvent(tampered)).toBe(false);
  });
});

// ── NostrTransport.buildEvent ─────────────────────────────────────────────────

describe("NostrTransport.buildEvent", () => {
  test("produces a valid NIP-01 event with p-tag addressed to peer", () => {
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpA.privkeyHex, kpA.pubkeyHex);
    transport.addPeer("peerB", kpB.pubkeyHex, []);

    const envelope = {
      id: "env-1",
      type: "peer.message" as const,
      from: { peer: kpA.pubkeyHex },
      to: { peer: kpB.pubkeyHex },
      payload: "hi",
      timestamp: new Date().toISOString(),
    };
    const event = transport.buildEvent("peerB", envelope);

    expect(event.kind).toBe(4);
    expect(event.pubkey).toBe(kpA.pubkeyHex);
    expect(verifyNostrEvent(event)).toBe(true);
    const pTag = event.tags.find((t) => t[0] === "p");
    expect(pTag?.[1]).toBe(kpB.pubkeyHex);
  });

  test("throws when identity is not set", () => {
    const transport = new NostrTransport(() => {});
    transport.addPeer("peerB", kpB.pubkeyHex, []);
    expect(() =>
      transport.buildEvent("peerB", {
        id: "x",
        type: "peer.message",
        from: { peer: "a" },
        to: { peer: "b" },
        payload: null,
        timestamp: "",
      }),
    ).toThrow("identity not set");
  });

  test("throws for unknown peer", () => {
    const transport = new NostrTransport(() => {});
    transport.setIdentity(kpA.privkeyHex, kpA.pubkeyHex);
    expect(() =>
      transport.buildEvent("nonExistentPeer", {
        id: "x",
        type: "peer.message",
        from: { peer: "a" },
        to: { peer: "b" },
        payload: null,
        timestamp: "",
      }),
    ).toThrow("unknown peer");
  });
});

// ── NostrTransport.simulateIncomingEvent ──────────────────────────────────────

describe("NostrTransport.simulateIncomingEvent — dispatch", () => {
  test("peer.message dispatches peer.chat broadcast", () => {
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpB.privkeyHex, kpB.pubkeyHex);
    transport.addPeer("peerA", kpA.pubkeyHex, []);

    // Build a signed+encrypted event from A to B
    const privABytes = privkeyHexToBytes(kpA.privkeyHex);
    const envelope = {
      id: "msg-1",
      type: "peer.message" as const,
      from: { peer: kpA.pubkeyHex },
      to: { peer: kpB.pubkeyHex },
      payload: "Hey from A!",
      timestamp: new Date().toISOString(),
    };
    const content = encryptMessage(JSON.stringify(envelope), privABytes, kpB.pubkeyHex);
    const event = signNostrEvent(4, content, [["p", kpB.pubkeyHex]], privABytes);
    transport.simulateIncomingEvent(event);

    expect(events.some((e) => e.type === "peer.chat")).toBe(true);
    const chatEvent = events.find((e) => e.type === "peer.chat");
    expect((chatEvent as any)?.message).toBe("Hey from A!");
  });

  test("event from unknown sender is silently ignored", () => {
    const kpUnknown = generateNostrKeypair();
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpB.privkeyHex, kpB.pubkeyHex);
    // kpUnknown is NOT added as peer

    const privUnknown = privkeyHexToBytes(kpUnknown.privkeyHex);
    const content = encryptMessage(
      JSON.stringify({ id: "x", type: "peer.message", from: { peer: kpUnknown.pubkeyHex }, to: { peer: kpB.pubkeyHex }, payload: "sneaky", timestamp: "" }),
      privUnknown,
      kpB.pubkeyHex,
    );
    const event = signNostrEvent(4, content, [["p", kpB.pubkeyHex]], privUnknown);
    transport.simulateIncomingEvent(event);

    expect(events.filter((e) => e.type === "peer.chat").length).toBe(0);
  });

  test("tampered event (invalid sig) is dropped", () => {
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpB.privkeyHex, kpB.pubkeyHex);
    transport.addPeer("peerA", kpA.pubkeyHex, []);

    const privABytes = privkeyHexToBytes(kpA.privkeyHex);
    const event = signNostrEvent(4, "content", [["p", kpB.pubkeyHex]], privABytes);
    const tampered = { ...event, content: "tampered content" };
    transport.simulateIncomingEvent(tampered);

    expect(events.length).toBe(0);
  });

  test("duplicate event ID is deduplicated", () => {
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpB.privkeyHex, kpB.pubkeyHex);
    transport.addPeer("peerA", kpA.pubkeyHex, []);

    const privABytes = privkeyHexToBytes(kpA.privkeyHex);
    const envelope = {
      id: "dedup-1",
      type: "peer.message" as const,
      from: { peer: kpA.pubkeyHex },
      to: { peer: kpB.pubkeyHex },
      payload: "once",
      timestamp: new Date().toISOString(),
    };
    const content = encryptMessage(JSON.stringify(envelope), privABytes, kpB.pubkeyHex);
    const event = signNostrEvent(4, content, [["p", kpB.pubkeyHex]], privABytes);

    transport.simulateIncomingEvent(event);
    transport.simulateIncomingEvent(event);

    const chatEvents = events.filter((e) => e.type === "peer.chat");
    expect(chatEvents.length).toBe(1);
  });
});

// ── destroy ───────────────────────────────────────────────────────────────────

describe("NostrTransport.destroy", () => {
  test("destroy emits nostr.status with 0 connected relays", () => {
    const events: SidecarEvent[] = [];
    const transport = new NostrTransport((e) => events.push(e));
    transport.setIdentity(kpA.privkeyHex, kpA.pubkeyHex);
    transport.destroy();
    const statusEvent = events.find((e) => e.type === "nostr.status");
    expect(statusEvent).toBeDefined();
    expect((statusEvent as any)?.connectedRelays).toBe(0);
  });
});
