#!/usr/bin/env bun
// Decrypt historical events received from iOS device and show what was sent

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes } from "@noble/hashes/utils.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

console.log(`[diag] Mac pubkey: ${MAC_PUBKEY_HEX}`);

// Historical events received in the diagnostic run (from the raw log)
// These are the encrypted payloads from the iOS device
const historicalEvents = [
  {
    content: "AhYHnbhPww8jZrvQU2OrfOJXlFQ5YkKdw+FvuWOiG8AsmBV7WCsDd5cYJUSyiAfJg2aLnsXjLCHg+ceTnMrgI3o7jfSLFj8FLw0B7Oy6fxibG9dfHovwt9LNwn+q8iQyHCVM",
    created_at: 1776690266,
    pubkey: "?" // unknown iOS pubkey
  },
  {
    content: "AsPiuSuhZzoSGH33u9fk6mnVJ75uhJXLjg+qQej6UaBHS5icrtQnRhu488kG3hDNLEbowOZwYyMePIKYqHEJ975nk61q6ZEhw1pKAmoi0d+bt4I89oTf07Pk5SBwWoQ0YpCy",
    created_at: 1776689736,
    pubkey: "?"
  },
  {
    content: "Anm1Bj269a3KIYrUhgGeXPmE7ifc8DuMRKVfwvrXps5qx8etPTL+A8D6P68zfS2gMLcce89PM2t+Qwvn7uKoQHWD3AdfFfGVFsyY9gIbPekOETdcegFWfvxhWa3ZNJmSv+iN",
    created_at: 1776689297,
    pubkey: "?"
  },
  {
    content: "AmcB+dm0FtRCDOTA2Oo3oDmHz4VJGCwwQU72u8hAImI1xxgf4sx6kwfmVMpzEW0tf6vtdkl8VjrTbA6aFpPLQTA9VqOGLxuXDJ49UlPSq6LzqKx1YZVSdQ5Q2RO7Hv06XgzH",
    created_at: 1776688666,
    pubkey: "?"
  }
];

// Subscribe to relay to get the full events (with sender pubkeys)
const macWs = new WebSocket("wss://relay.damus.io");
const SUB_ID = `decrypt-${Date.now()}`;
let count = 0;

macWs.onopen = () => {
  console.log("[sub] connected, fetching events...");
  macWs.send(JSON.stringify(["REQ", SUB_ID, {
    kinds: [4],
    "#p": [MAC_PUBKEY_HEX],
    since: 1776688000,
    until: 1776691000
  }]));
};

macWs.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg[0] === "EOSE") {
    console.log(`[sub] EOSE, got ${count} events`);
    macWs.close();
    process.exit(0);
  } else if (msg[0] === "EVENT") {
    const ev = msg[2];
    count++;
    console.log(`\n[event ${count}] ts=${ev.created_at} pubkey=${ev.pubkey.slice(0,16)}...`);
    // Try to decrypt with NIP-44 using the sender's pubkey
    try {
      const convKey = nip44.getConversationKey(macPrivBytes, ev.pubkey);
      const plaintext = nip44.decrypt(ev.content, convKey);
      console.log(`[event ${count}] ✅ DECRYPTED: ${plaintext.slice(0, 200)}`);
    } catch (err) {
      console.log(`[event ${count}] ❌ decrypt failed: ${err}`);
      console.log(`[event ${count}] raw content: ${ev.content.slice(0, 100)}`);
    }
  }
};
macWs.onerror = (e) => { console.error("error:", e); process.exit(1); };

setTimeout(() => { console.log("timeout"); process.exit(1); }, 15000);
