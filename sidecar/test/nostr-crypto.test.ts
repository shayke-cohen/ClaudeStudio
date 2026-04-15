import { describe, it, expect } from 'bun:test'
import {
  generateNostrKeypair,
  privkeyHexToBytes,
  pubkeyHexToBytes,
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  verifyNostrEvent,
} from '../src/relay/nostr-crypto.js'

describe('generateNostrKeypair', () => {
  it('returns 64-char hex privkey and 64-char hex pubkey', () => {
    const kp = generateNostrKeypair()
    expect(kp.privkeyHex).toHaveLength(64)
    expect(kp.pubkeyHex).toHaveLength(64)
    expect(kp.privkeyHex).toMatch(/^[0-9a-f]+$/)
    expect(kp.pubkeyHex).toMatch(/^[0-9a-f]+$/)
  })

  it('generates different keypairs each call', () => {
    const a = generateNostrKeypair()
    const b = generateNostrKeypair()
    expect(a.privkeyHex).not.toBe(b.privkeyHex)
  })
})

describe('NIP-44 encrypt/decrypt round-trip', () => {
  it('decrypts to original plaintext', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const plaintext = '{"type":"peer.task.delegate","payload":{"task":"Review this"}}'
    const ciphertext = encryptMessage(plaintext, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const recovered = decryptMessage(ciphertext, privkeyHexToBytes(bob.privkeyHex), alice.pubkeyHex)
    expect(recovered).toBe(plaintext)
  })

  it('produces different ciphertext each call (random nonce)', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const msg = 'hello'
    const c1 = encryptMessage(msg, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const c2 = encryptMessage(msg, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    expect(c1).not.toBe(c2)
  })

  it('throws on tampered ciphertext', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const ciphertext = encryptMessage('hello', privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const tampered = ciphertext.slice(0, -4) + 'XXXX'
    expect(() => decryptMessage(tampered, privkeyHexToBytes(bob.privkeyHex), alice.pubkeyHex)).toThrow()
  })
})

describe('signNostrEvent / verifyNostrEvent', () => {
  it('verifies a signed event', () => {
    const { privkeyHex, pubkeyHex } = generateNostrKeypair()
    const event = signNostrEvent(4, 'hello', [['p', pubkeyHex]], privkeyHexToBytes(privkeyHex))
    expect(verifyNostrEvent(event)).toBe(true)
  })

  it('rejects a tampered event', () => {
    const { privkeyHex, pubkeyHex } = generateNostrKeypair()
    const event = signNostrEvent(4, 'hello', [['p', pubkeyHex]], privkeyHexToBytes(privkeyHex))
    const tampered = { ...event, content: 'tampered' }
    expect(verifyNostrEvent(tampered)).toBe(false)
  })
})
