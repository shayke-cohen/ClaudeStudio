#!/usr/bin/env bun
// Full E2E test: simulate iOS → Mac → iOS round trip via relay.damus.io only
// Uses single WS connection (full-duplex) to avoid HTTP/2 reuse issue

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes, randomBytes } from "@noble/hashes/utils.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

const iosPrivBytes = randomBytes(32);
const IOS_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(iosPrivBytes));

console.log(`[e2e] Mac pubkey: ${MAC_PUBKEY_HEX}`);
console.log(`[e2e] iOS pubkey: ${IOS_PUBKEY_HEX} (ephemeral)\n`);

function signEvent(kind: number, content: string, tags: string[][], privBytes: Uint8Array, pubHex: string) {
  const ts = Math.floor(Date.now() / 1000);
  const canonical = JSON.stringify([0, pubHex, ts, kind, tags, content]);
  const hashBytes = sha256(new TextEncoder().encode(canonical));
  const id = bytesToHex(hashBytes);
  const sig = bytesToHex(schnorr.sign(hashBytes, privBytes));
  return { kind, created_at: ts, tags, content, pubkey: pubHex, id, sig };
}

async function run(): Promise<boolean> {
  return new Promise((resolve) => {
    let gotResult = false;
    let eoseDone = false;
    let phase = "init";

    // Single WS connection — subscribe as iOS, then also publish the iOS→Mac event
    const ws = new WebSocket("wss://relay.damus.io");
    ws.onopen = () => {
      console.log("[ws] connected to relay.damus.io");
      // Subscribe for Mac's response to iOS
      ws.send(JSON.stringify(["REQ", "ios-sub", {
        kinds: [4],
        authors: [MAC_PUBKEY_HEX],
        "#p": [IOS_PUBKEY_HEX],
        since: Math.floor(Date.now() / 1000) - 5
      }]));
      console.log("[ws] subscribed for Mac→iOS responses");
      phase = "subscribed";
    };

    ws.onmessage = (e) => {
      const msg = JSON.parse(e.data);
      if (msg[0] === "EOSE" && !eoseDone) {
        eoseDone = true;
        console.log("[ws] EOSE — publishing iOS→Mac conversations.list\n");
        // Now publish the iOS event TO the Mac
        const convKey = nip44.getConversationKey(iosPrivBytes, MAC_PUBKEY_HEX);
        const payload = JSON.stringify({ type: "conversations.list" });
        const encrypted = nip44.encrypt(payload, convKey);
        const ev = signEvent(4, encrypted, [["p", MAC_PUBKEY_HEX]], iosPrivBytes, IOS_PUBKEY_HEX);
        ws.send(JSON.stringify(["EVENT", ev]));
        console.log(`[ws] published conversations.list event id=${ev.id.slice(0,8)}...`);
        phase = "published";
      } else if (msg[0] === "OK") {
        console.log(`[ws] event accepted: ${msg[2]} ${msg[3]||""}`);
      } else if (msg[0] === "EVENT") {
        const ev = msg[2];
        if (ev.pubkey === MAC_PUBKEY_HEX) {
          console.log(`\n[ws] ✅ Got event FROM Mac! id=${ev.id.slice(0,8)}...`);
          // Decrypt with iOS privkey
          try {
            const convKey = nip44.getConversationKey(iosPrivBytes, MAC_PUBKEY_HEX);
            const plain = nip44.decrypt(ev.content, convKey);
            console.log(`[ws] ✅ Decrypted Mac→iOS: ${plain.slice(0, 500)}`);
            gotResult = true;
            resolve(true);
          } catch (err: any) {
            console.log(`[ws] ❌ Decrypt failed: ${err.message}`);
          }
        }
      }
    };
    ws.onerror = (e) => { console.error("[ws] error:", e); resolve(false); };

    setTimeout(() => {
      if (!gotResult) {
        console.log(`\n❌ TIMEOUT: No Mac response after 30s`);
        if (phase === "subscribed") console.log("   (Never received EOSE — relay subscription failed)");
        else if (phase === "published") console.log("   Mac received the event but did not publish a response");
        ws.close();
        resolve(false);
      }
    }, 30000);
  });
}

const ok = await run();
console.log(ok
  ? "\n✅ E2E PASS: Full iOS↔Mac Nostr relay round-trip works!"
  : "\n❌ E2E FAIL: Mac did not complete the round-trip");
process.exit(ok ? 0 : 1);
