#!/usr/bin/env bun
// Diagnostic: subscribe as Mac, publish as iOS, verify relay routes events end-to-end
// Uses Bun's native WebSocket (browser API) to match Swift URLSessionWebSocketTask behavior

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes, randomBytes } from "@noble/hashes/utils.js";
import { sha256 } from "@noble/hashes/sha2.js";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

const iosPrivBytes = randomBytes(32);
const IOS_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(iosPrivBytes));

console.log(`[diag] Mac pubkey:  ${MAC_PUBKEY_HEX}`);
console.log(`[diag] iOS pubkey:  ${IOS_PUBKEY_HEX} (ephemeral)`);

function signEvent(kind: number, content: string, tags: string[][], privBytes: Uint8Array, pubHex: string) {
  const ts = Math.floor(Date.now() / 1000);
  const canonical = JSON.stringify([0, pubHex, ts, kind, tags, content]);
  const hashBytes = sha256(new TextEncoder().encode(canonical));
  const id = bytesToHex(hashBytes);
  const sig = bytesToHex(schnorr.sign(hashBytes, privBytes));
  return { kind, created_at: ts, tags, content, pubkey: pubHex, id, sig };
}

const MAC_RELAY = "wss://relay.damus.io";
const IOS_RELAY = "wss://relay.nostr.band"; // different relay to avoid HTTP/2 reuse issue
const SUB_ID = `diag-${Date.now()}`;

// Use a Promise-based approach with browser-style WebSocket
async function run(): Promise<boolean> {
  return new Promise((resolve) => {
    let macReceivedEvent = false;

    // iOS publisher — uses relay.nostr.band which cross-posts to relay.damus.io
    const iosWs = new WebSocket(IOS_RELAY);
    let iosReady = false;
    iosWs.onopen = () => { console.log(`[ios-pub] connected`); iosReady = true; };
    iosWs.onmessage = (e) => {
      console.log(`[ios-pub] raw msg: ${e.data.slice(0, 200)}`);
      const msg = JSON.parse(e.data);
      if (msg[0] === "OK") console.log(`[ios-pub] relay ACK: accepted=${msg[2]} ${msg[3] || ""}`);
    };
    iosWs.onerror = (e) => console.error(`[ios-pub] ERROR:`, e);

    function publishFromiOS() {
      if (!iosReady) { setTimeout(publishFromiOS, 200); return; }
      const ev = signEvent(4, "diag:conversations.list", [["p", MAC_PUBKEY_HEX]], iosPrivBytes, IOS_PUBKEY_HEX);
      iosWs.send(JSON.stringify(["EVENT", ev]));
      console.log(`[ios-pub] published event id=${ev.id.slice(0,8)}...`);
    }

    // Mac subscriber
    const macWs = new WebSocket(MAC_RELAY);
    macWs.onopen = () => {
      console.log(`[mac-sub] connected to ${MAC_RELAY}`);
      macWs.send(JSON.stringify(["REQ", SUB_ID, { kinds: [4], "#p": [MAC_PUBKEY_HEX] }]));
      console.log(`[mac-sub] subscribed kind-4 for ${MAC_PUBKEY_HEX.slice(0,8)}...`);
    };
    macWs.onmessage = (e) => {
      console.log(`[mac-sub] raw msg: ${e.data.slice(0, 200)}`);
      const msg = JSON.parse(e.data);
      if (msg[0] === "EOSE") {
        console.log(`[mac-sub] EOSE — publishing iOS test event in 500ms`);
        setTimeout(publishFromiOS, 500);
      } else if (msg[0] === "EVENT") {
        const ev = msg[2];
        if (ev.pubkey === IOS_PUBKEY_HEX) {
          console.log(`✅ [mac-sub] Got iOS event! id=${ev.id.slice(0,8)} content="${ev.content}"`);
          macReceivedEvent = true;
          macWs.close();
          iosWs.close();
          resolve(true);
        }
      }
    };
    macWs.onerror = (e) => { console.error(`[mac-sub] ERROR:`, e); resolve(false); };
    macWs.onclose = () => {
      if (!macReceivedEvent) {
        console.log(`[mac-sub] closed without receiving event`);
      }
    };

    // Timeout
    setTimeout(() => {
      if (!macReceivedEvent) {
        console.log(`❌ TIMEOUT: relay did NOT deliver event to Mac subscriber after 20s`);
        macWs.close();
        iosWs.close();
        resolve(false);
      }
    }, 20000);
  });
}

const success = await run();
console.log(success ? "\n✅ Relay E2E path works!" : "\n❌ Relay E2E path FAILED");
process.exit(success ? 0 : 1);
