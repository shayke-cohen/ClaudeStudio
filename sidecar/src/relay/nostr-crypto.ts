import { generateSecretKey, getPublicKey, nip44, finalizeEvent, getEventHash } from 'nostr-tools'
import type { Event } from 'nostr-tools'
import { schnorr } from '@noble/curves/secp256k1.js'
import { hexToBytes, bytesToHex } from '@noble/hashes/utils.js'

export interface NostrKeypair {
  privkeyHex: string
  pubkeyHex: string
}

export function generateNostrKeypair(): NostrKeypair {
  const privkeyBytes = generateSecretKey()
  return {
    privkeyHex: bytesToHex(privkeyBytes),
    pubkeyHex: getPublicKey(privkeyBytes),
  }
}

export function privkeyHexToBytes(hex: string): Uint8Array {
  return hexToBytes(hex)
}

export function pubkeyHexToBytes(hex: string): Uint8Array {
  return hexToBytes(hex)
}

export function encryptMessage(
  plaintext: string,
  senderPrivBytes: Uint8Array,
  recipientPubHex: string,
): string {
  const conversationKey = nip44.getConversationKey(senderPrivBytes, recipientPubHex)
  return nip44.encrypt(plaintext, conversationKey)
}

export function decryptMessage(
  ciphertext: string,
  recipientPrivBytes: Uint8Array,
  senderPubHex: string,
): string {
  const conversationKey = nip44.getConversationKey(recipientPrivBytes, senderPubHex)
  return nip44.decrypt(ciphertext, conversationKey)
}

export function signNostrEvent(
  kind: number,
  content: string,
  tags: string[][],
  privkeyBytes: Uint8Array,
): Event {
  return finalizeEvent({ kind, created_at: Math.floor(Date.now() / 1000), tags, content }, privkeyBytes)
}

export function verifyNostrEvent(event: Event): boolean {
  try {
    // Always recompute — do not use nostr-tools verifyEvent which caches on the object
    const hash = getEventHash(event)
    if (hash !== event.id) return false
    return schnorr.verify(hexToBytes(event.sig), hexToBytes(hash), hexToBytes(event.pubkey))
  } catch {
    return false
  }
}

