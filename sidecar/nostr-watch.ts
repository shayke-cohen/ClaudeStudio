#!/usr/bin/env bun
// Watch relay for new kind-4 events addressed to Mac — shows iOS pubkey in received events

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes } from "@noble/hashes/utils.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

console.log(`[watch] Mac pubkey: ${MAC_PUBKEY_HEX}`);
console.log(`[watch] Watching for events from iOS (last 60s)...`);

const since = Math.floor(Date.now() / 1000) - 60;
const macWs = new WebSocket("wss://relay.damus.io");
const SUB_ID = `watch-${Date.now()}`;

macWs.onopen = () => {
  macWs.send(JSON.stringify(["REQ", SUB_ID, {
    kinds: [4], "#p": [MAC_PUBKEY_HEX], since
  }]));
};
macWs.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg[0] === "EOSE") {
    console.log(`[watch] Caught up. Waiting for new events from iOS...`);
  } else if (msg[0] === "EVENT") {
    const ev = msg[2];
    const pubkeyLen = ev.pubkey.length;
    console.log(`[watch] Event from ${ev.pubkey.slice(0, 16)}... (${pubkeyLen} chars = ${pubkeyLen/2} bytes) ts=${ev.created_at}`);
    // Try to decrypt
    try {
      const convKey = nip44.getConversationKey(macPrivBytes, ev.pubkey);
      const plain = nip44.decrypt(ev.content, convKey);
      console.log(`[watch] ✅ Decrypted: ${plain.slice(0, 150)}`);
    } catch (err: any) {
      console.log(`[watch] ❌ Decrypt failed: ${err.message}`);
      console.log(`[watch]    (pubkey len ${pubkeyLen} — expected 64 for 32-byte x-only)`);
    }
  }
};
macWs.onerror = (e) => console.error(`[watch] error:`, e);

setTimeout(() => { macWs.close(); console.log("[watch] timeout, no events"); process.exit(0); }, 30000);
