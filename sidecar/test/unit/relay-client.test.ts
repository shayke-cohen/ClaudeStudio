/**
 * Unit tests for RelayClient stub.
 *
 * RelayClient is intentionally stubbed out — WAN relay has been replaced by
 * NostrTransport. These tests document the stub contract so callers don't
 * accidentally rely on the old behaviour.
 */
import { describe, test, expect } from "bun:test";
import { RelayClient } from "../../src/relay-client.js";

describe("RelayClient (stub)", () => {
  test("isConnected always returns false", () => {
    const client = new RelayClient(() => {});
    expect(client.isConnected("any-peer")).toBe(false);
  });

  test("connect resolves without throwing (no-op)", async () => {
    const client = new RelayClient(() => {});
    await expect(client.connect("peer-a", "ws://localhost:9999")).resolves.toBeUndefined();
  });

  test("sendCommand throws stub error directing callers to NostrTransport", async () => {
    const client = new RelayClient(() => {});
    await expect(client.sendCommand("peer-a", { type: "session.pause", sessionId: "x" }))
      .rejects.toThrow("RelayClient is a stub");
  });
});
