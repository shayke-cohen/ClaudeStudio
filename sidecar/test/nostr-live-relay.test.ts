/**
 * Live Nostr relay integration test
 *
 * This test connects to real public Nostr relays and validates the full
 * end-to-end path: keypair generation → encryption → relay delivery → decryption.
 *
 * SKIP BEHAVIOR
 * Set SKIP_LIVE_TESTS=1 to skip this file entirely (offline / CI without outbound
 * internet access). Without that variable the test runs by default.
 *
 *   SKIP_LIVE_TESTS=1 bun test test/nostr-live-relay.test.ts   # skips
 *   bun test test/nostr-live-relay.test.ts                     # runs (needs internet)
 */

import { describe, it, expect } from 'bun:test'
import { NostrTransport } from '../src/relay/nostr-transport.js'
import { generateNostrKeypair } from '../src/relay/nostr-crypto.js'

const SKIP = process.env.SKIP_LIVE_TESTS === '1'
const LIVE_RELAYS = ['wss://relay.damus.io', 'wss://nos.lol']

describe.skipIf(SKIP)('NostrTransport live relay round-trip', () => {
  it(
    'delivers an encrypted envelope from alice to bob via public relays',
    async () => {
      const alice = generateNostrKeypair()
      const bob = generateNostrKeypair()

      const bobReceived: any[] = []
      const bobTransport = new NostrTransport((event) => bobReceived.push(event))
      bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, LIVE_RELAYS)
      bobTransport.addPeer('alice', alice.pubkeyHex, LIVE_RELAYS)

      const aliceTransport = new NostrTransport((_event) => {})
      aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, LIVE_RELAYS)
      aliceTransport.addPeer('bob', bob.pubkeyHex, LIVE_RELAYS)

      try {
        // Give subscriptions time to connect to relays before publishing
        await new Promise((resolve) => setTimeout(resolve, 3000))

        // Alice sends to Bob
        await aliceTransport.sendMessage('bob', {
          id: `live-${Date.now()}-${Math.random().toString(36).slice(2)}`,
          type: 'peer.message',
          from: { peer: 'alice' },
          to: { peer: 'bob' },
          payload: 'hello from alice via real relays',
          timestamp: new Date().toISOString(),
        })

        // Poll for delivery — relays can be slow, allow up to 15 s
        const timeoutMs = 15_000
        const start = Date.now()
        while (Date.now() - start < timeoutMs) {
          const peerChat = bobReceived.find((e) => e.type === 'peer.chat')
          if (peerChat) break
          await new Promise((resolve) => setTimeout(resolve, 500))
        }

        const peerChat = bobReceived.find((e) => e.type === 'peer.chat')
        if (peerChat === undefined) {
          throw new Error(
            `Timed out after ${timeoutMs}ms waiting for message via live relays. ` +
            'All relays may be down or rate-limiting new pubkeys.',
          )
        }

        expect(peerChat.type).toBe('peer.chat')
        expect(peerChat.from).toBe('alice')
        expect(peerChat.message).toContain('hello from alice via real relays')
        expect(peerChat.channelId).toBe('nostr:alice')
      } finally {
        aliceTransport.destroy()
        bobTransport.destroy()
      }
    },
    30_000, // 30 s test timeout — relays can be slow
  )
})
