#!/usr/bin/env bun
import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes } from "@noble/hashes/utils.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));
const since = Math.floor(Date.now() / 1000) - 10;

console.log(`[watch] Mac pubkey: ${MAC_PUBKEY_HEX}`);
console.log(`[watch] Monitoring relay.damus.io for iOS events (90s)...`);

const ws = new WebSocket("wss://relay.damus.io");
ws.onopen = () => ws.send(JSON.stringify(["REQ", "w1", { kinds: [4], "#p": [MAC_PUBKEY_HEX], since }]));
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg[0] === "EOSE") { console.log("[watch] Live — waiting for iOS events..."); return; }
  if (msg[0] === "EVENT") {
    const ev = msg[2];
    const len = ev.pubkey.length;
    const isFixed = len === 64; // 32-byte x-only = correct
    const isOld = len === 128; // 64-byte = old buggy format
    const label = isFixed ? "✅ FIXED 32-byte" : isOld ? "🐛 OLD 64-byte" : `? (${len/2}B)`;
    console.log(`\n[event] ${label} pubkey ${ev.pubkey.slice(0,16)}... ts=${ev.created_at}`);
    try {
      const plain = nip44.decrypt(ev.content, nip44.getConversationKey(macPrivBytes, ev.pubkey));
      console.log(`✅ decrypted: ${plain.slice(0, 200)}`);
    } catch(err: any) {
      console.log(`❌ decrypt failed: ${err.message}`);
    }
  }
};
ws.onerror = (e) => console.error("[watch] WS error:", e);

setTimeout(() => {
  ws.close();
  console.log("[watch] 90s timeout, exiting");
  process.exit(0);
}, 90000);
