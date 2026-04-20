#!/usr/bin/env bun
// E2E test: full chat round-trip via Nostr relay
// iOS simulates: session.create → session.message → receives streaming tokens + session.result

import { schnorr } from "@noble/curves/secp256k1.js";
import { bytesToHex, hexToBytes, randomBytes } from "@noble/hashes/utils.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { nip44 } from "nostr-tools";

const MAC_PRIVKEY_HEX = "182c4a296ce4280301211f2485d6baf07767922fae9330889ad7ed2e3398b8ba";
const macPrivBytes = hexToBytes(MAC_PRIVKEY_HEX);
const MAC_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(macPrivBytes));

const iosPrivBytes = randomBytes(32);
const IOS_PUBKEY_HEX = bytesToHex(schnorr.getPublicKey(iosPrivBytes));
const CONV_ID = crypto.randomUUID();

console.log(`[chat-e2e] Mac pubkey: ${MAC_PUBKEY_HEX}`);
console.log(`[chat-e2e] iOS pubkey: ${IOS_PUBKEY_HEX} (ephemeral)`);
console.log(`[chat-e2e] conversationId: ${CONV_ID}\n`);

function signEvent(kind: number, content: string, tags: string[][], privBytes: Uint8Array, pubHex: string) {
  const ts = Math.floor(Date.now() / 1000);
  const canonical = JSON.stringify([0, pubHex, ts, kind, tags, content]);
  const hashBytes = sha256(new TextEncoder().encode(canonical));
  const id = bytesToHex(hashBytes);
  const sig = bytesToHex(schnorr.sign(hashBytes, privBytes));
  return { kind, created_at: ts, tags, content, pubkey: pubHex, id, sig };
}

function sendToMac(ws: WebSocket, payload: object) {
  const convKey = nip44.getConversationKey(iosPrivBytes, MAC_PUBKEY_HEX);
  const encrypted = nip44.encrypt(JSON.stringify(payload), convKey);
  const ev = signEvent(4, encrypted, [["p", MAC_PUBKEY_HEX]], iosPrivBytes, IOS_PUBKEY_HEX);
  ws.send(JSON.stringify(["EVENT", ev]));
}

async function run(): Promise<boolean> {
  return new Promise((resolve) => {
    let sessionCreated = false;
    let tokenCount = 0;
    let gotResult = false;
    let toolCallsSeen: string[] = [];
    let fullText = "";

    const ws = new WebSocket("wss://relay.damus.io");

    ws.onopen = () => {
      console.log("[ws] connected");
      // Subscribe for all Mac→iOS events addressed to us
      ws.send(JSON.stringify(["REQ", "chat-sub", {
        kinds: [4],
        authors: [MAC_PUBKEY_HEX],
        "#p": [IOS_PUBKEY_HEX],
        since: Math.floor(Date.now() / 1000) - 5,
      }]));
    };

    ws.onmessage = (e) => {
      const msg = JSON.parse(e.data);

      if (msg[0] === "EOSE") {
        console.log("[ws] EOSE — sending session.create\n");
        sendToMac(ws, {
          type: "session.create",
          conversationId: CONV_ID,
          agentConfig: {
            name: "E2E Test Agent",
            systemPrompt: "You are a helpful assistant. Be concise.",
            allowedTools: [],
            mcpServers: [],
            model: "claude-haiku-4-5-20251001",
            workingDirectory: "/tmp",
            skills: [],
          },
        });
        sessionCreated = true;

        // Give Mac ~3s to set up the session, then send message
        setTimeout(() => {
          console.log("[ws] sending session.message\n");
          sendToMac(ws, {
            type: "session.message",
            sessionId: CONV_ID,
            text: "Reply with exactly: NOSTR_WORKS",
          });
        }, 3000);
        return;
      }

      if (msg[0] === "OK") {
        const accepted = msg[2] === true;
        if (!accepted) console.log(`[ws] event rejected: ${msg[3]}`);
        return;
      }

      if (msg[0] !== "EVENT") return;
      const ev = msg[2];
      if (ev.pubkey !== MAC_PUBKEY_HEX) return;

      // Decrypt
      let plain: string;
      try {
        const convKey = nip44.getConversationKey(iosPrivBytes, MAC_PUBKEY_HEX);
        plain = nip44.decrypt(ev.content, convKey);
      } catch (err: any) {
        console.log(`[ws] decrypt failed: ${err.message}`);
        return;
      }

      let event: any;
      try { event = JSON.parse(plain); } catch { return; }

      switch (event.type) {
        case "stream.token":
          tokenCount++;
          fullText += event.text;
          process.stdout.write(event.text);
          break;
        case "stream.thinking":
          process.stdout.write(`[think: ${event.text.slice(0, 30)}...]`);
          break;
        case "stream.toolCall":
          toolCallsSeen.push(event.tool);
          console.log(`\n[tool] ${event.tool}: ${event.input.slice(0, 80)}`);
          break;
        case "stream.toolResult":
          console.log(`[tool result] ${event.tool}: ${event.output.slice(0, 80)}`);
          break;
        case "session.result":
          console.log(`\n\n[session.result] cost=$${event.cost.toFixed(4)} tokens=${event.inputTokens}+${event.outputTokens} turns=${event.numTurns}`);
          gotResult = true;
          ws.close();
          resolve(fullText.includes("NOSTR_WORKS"));
          break;
        case "session.error":
          console.log(`\n[session.error] ${event.error}`);
          ws.close();
          resolve(false);
          break;
        default:
          console.log(`\n[event] ${event.type}`);
      }
    };

    ws.onerror = (e) => { console.error("[ws] error:", e); resolve(false); };

    setTimeout(() => {
      if (!gotResult) {
        console.log(`\n❌ TIMEOUT after 60s (tokens received: ${tokenCount}, sessionCreated: ${sessionCreated})`);
        ws.close();
        resolve(false);
      }
    }, 60000);
  });
}

const ok = await run();
console.log(ok
  ? "\n✅ CHAT E2E PASS: full iOS↔Mac Nostr chat round-trip works!"
  : "\n❌ CHAT E2E FAIL");
process.exit(ok ? 0 : 1);
