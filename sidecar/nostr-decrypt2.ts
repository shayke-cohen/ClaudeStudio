#!/usr/bin/env bun
// Fetch historical iOS events and try to decrypt + check pubkey format

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes } from "@noble/hashes/utils.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

console.log(`Mac pubkey: ${MAC_PUBKEY_HEX} (${MAC_PUBKEY_HEX.length} chars = ${MAC_PUBKEY_HEX.length/2} bytes)\n`);

const ws = new WebSocket("wss://relay.damus.io");
const SUB_ID = `fetch-${Date.now()}`;

ws.onopen = () => {
  // Fetch events from the last 4 hours
  ws.send(JSON.stringify(["REQ", SUB_ID, {
    kinds: [4],
    "#p": [MAC_PUBKEY_HEX],
    since: Math.floor(Date.now() / 1000) - 4 * 3600,
    limit: 10
  }]));
  console.log("Fetching events from last 4h...");
};

let events: any[] = [];

ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg[0] === "EOSE") {
    console.log(`Got ${events.length} events\n`);
    ws.close();

    for (const ev of events) {
      const pubkeyLen = ev.pubkey.length;
      const bytesLen = pubkeyLen / 2;
      const isXonly = pubkeyLen === 64;  // 32-byte x-only (correct Nostr format)
      const isFullxy = pubkeyLen === 128; // 64-byte x+y (iOS bug)
      const format = isXonly ? "✅ x-only 32B" : isFullxy ? "🐛 x+y 64B" : `? ${bytesLen}B`;

      const ts = new Date(ev.created_at * 1000).toISOString();
      console.log(`[event] ts=${ts} pubkey=${ev.pubkey.slice(0,16)}... (${format})`);

      // Try NIP-44 decrypt with this pubkey as peer
      try {
        const convKey = nip44.getConversationKey(macPrivBytes, ev.pubkey);
        const plain = nip44.decrypt(ev.content, convKey);
        console.log(`  ✅ DECRYPTED: ${plain.slice(0, 200)}`);
      } catch (err: any) {
        console.log(`  ❌ nip44 decrypt: ${err.message}`);
      }

      // If it's the old 64-byte format, also try with just the x-coordinate (first 64 chars)
      if (isFullxy) {
        const xOnly = ev.pubkey.slice(0, 64);
        try {
          const convKey2 = nip44.getConversationKey(macPrivBytes, xOnly);
          const plain2 = nip44.decrypt(ev.content, convKey2);
          console.log(`  ✅ DECRYPTED (x-only extracted): ${plain2.slice(0, 200)}`);
        } catch (err: any) {
          console.log(`  ❌ nip44 decrypt (x-only): ${err.message}`);
        }
      }
      console.log();
    }

    process.exit(0);
  } else if (msg[0] === "EVENT") {
    events.push(msg[2]);
  }
};
ws.onerror = (e) => { console.error("error:", e); process.exit(1); };
setTimeout(() => { ws.close(); process.exit(0); }, 15000);
