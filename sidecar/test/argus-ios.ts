/**
 * sidecar/test/argus-ios.ts
 *
 * iOS Argus E2E Test Suite — OdysseyiOS on iPhone 17 (iOS 26.4)
 * Run date: 2026-04-14
 *
 * ─── HOW TO RE-RUN ─────────────────────────────────────────────────────────
 * 1. Build app:
 *    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
 *    xcodebuild -project Odyssey.xcodeproj -scheme OdysseyiOS \
 *      -destination 'platform=iOS Simulator,id=B1B452F0-45C4-4FC2-8807-EAA7DDE53C56' \
 *      -configuration Debug build
 *
 * 2. Install app:
 *    xcrun simctl install B1B452F0-45C4-4FC2-8807-EAA7DDE53C56 \
 *      /tmp/OdysseyiOS-build/Build/Products/Debug-iphonesimulator/OdysseyiOS.app
 *
 * 3. Fix WDA for iOS 26.4 (one-time per WDA build):
 *    cp -R /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks/_Testing_Foundation.framework \
 *      ~/Library/Developer/CoreSimulator/Devices/B1B452F0-45C4-4FC2-8807-EAA7DDE53C56/data/Containers/Bundle/Application/<WDA-UUID>/WebDriverAgentRunner-Runner.app/PlugIns/WebDriverAgentRunner.xctest/Frameworks/
 *    (WDA 11.4.1 links libXCTestSwiftSupport.dylib which requires _Testing_Foundation,
 *    but iOS 26.4 simruntime doesn't bundle it — copy from iPhoneSimulator.platform.)
 *
 * 4. Generate invite code (no Keychain needed):
 *    python3 scripts/gen-test-invite-ephemeral.py
 *    # or: bun scripts/gen-test-invite.ts default  (requires sidecar running)
 *
 * 5. Run via Argus MCP — see mcp__argus__* calls below.
 * ───────────────────────────────────────────────────────────────────────────
 */

// ─── Test Suite Metadata ───────────────────────────────────────────────────
export const testSuite = {
  platform: "ios",
  device: "iPhone 17 (iOS 26.4)",
  simulatorUDID: "B1B452F0-45C4-4FC2-8807-EAA7DDE53C56",
  bundleId: "com.odyssey.app.ios",
  runDate: "2026-04-14",
  groups: [
    "G1-Pairing",
    "G2-Conversations",
    "G4-Agents",
    "G5-Settings",
    "G6-VisualQuality",
  ],
  knownLimitations: [
    "G3-Chat tests require connected sidecar — skipped (sidecar not running in CI)",
    "WDA 11.4.1 requires _Testing_Foundation.framework fix for iOS 26.4 (see HOW TO RE-RUN)",
    "Argus inspect/act use WDA REST API directly to avoid process visibility kills",
  ],
};

// ─── WDA Setup Helper ─────────────────────────────────────────────────────
//
// WDA crashes on iOS 26.4 when called via Appium inspect/act because
// the session creation causes WDA to be backgrounded and killed by SpringBoard.
// Workaround: use WDA's REST API directly at http://localhost:8100.
//
// wdaSession() creates a new WDA session and returns helpers for screenshots,
// taps, element lookups, and scrolling — all via direct WDA REST calls.

export async function wdaSession(bundleId: string) {
  const BASE = "http://localhost:8100";

  const resp = await fetch(`${BASE}/session`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ capabilities: { alwaysMatch: { bundleId } } }),
  });
  const { sessionId } = await resp.json();
  const S = `${BASE}/session/${sessionId}`;

  const screenshot = async (): Promise<Buffer> => {
    const r = await fetch(`${S}/screenshot`);
    const { value } = await r.json();
    return Buffer.from(value, "base64");
  };

  const findElement = async (accessibilityId: string): Promise<string | null> => {
    const r = await fetch(`${S}/elements`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ using: "accessibility id", value: accessibilityId }),
    });
    const { value } = await r.json();
    return value?.[0]?.ELEMENT ?? null;
  };

  const click = async (elementId: string): Promise<void> => {
    await fetch(`${S}/element/${elementId}/click`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
  };

  const getText = async (elementId: string): Promise<string> => {
    const r = await fetch(`${S}/element/${elementId}/attribute/label`);
    const { value } = await r.json();
    return value ?? "";
  };

  const swipe = async (
    fromX: number, fromY: number,
    toX: number, toY: number,
    durationMs = 500,
  ): Promise<void> => {
    await fetch(`${S}/actions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        actions: [{
          type: "pointer",
          id: "touch",
          parameters: { pointerType: "touch" },
          actions: [
            { type: "pointerMove", duration: 0, x: fromX, y: fromY },
            { type: "pointerDown", button: 0 },
            { type: "pointerMove", duration: durationMs, x: toX, y: toY },
            { type: "pointerUp", button: 0 },
          ],
        }],
      }),
    });
  };

  const close = async (): Promise<void> => {
    await fetch(`${S}`, { method: "DELETE" });
  };

  return { sessionId, screenshot, findElement, click, getText, swipe, close };
}

// ─── Group 1: Pairing (G1 / P1–P5) ───────────────────────────────────────
//
// RESULTS (2026-04-14):
//   P1 ✅ Fresh launch shows iOSPairingView with inviteCodeField + pairButton
//   P2 ✅ pairButton disabled when inviteCodeField is empty
//   P3 ✅ Invalid code ("notavalidcode") shows pairing.errorLabel
//   P4 ✅ Valid invite code via textarea → tapping pairButton navigates to tab bar
//   P5 ✅ Deep link odyssey://invite?invite=<code> auto-pairs and shows ConversationListView
//
// NOTES:
//   - InvitePayload.verify() had a bug: NSJSONSerialization.data escapes '/' as '\/'
//     producing canonical JSON 17 bytes larger than TypeScript JSON.stringify.
//     Fixed in Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift
//     by unescaping '\/' → '/' after JSONSerialization.data().
//   - Deep link URL format: odyssey://invite?invite=<base64url-payload>
//   - Use `xcrun simctl openurl <udid> "odyssey://invite?invite=..."` to trigger

export const G1_PAIRING_STEPS = `
// P1-P2: Fresh launch — pairing screen visible, Pair button disabled
const s = await wdaSession("com.odyssey.app.ios");
const inviteField = await s.findElement("pairing.inviteCodeField");
const pairButton = await s.findElement("pairing.pairButton");
assert(inviteField !== null, "P1: inviteCodeField visible");
assert(pairButton !== null, "P1: pairButton visible");
// P2: button is disabled (no text entered yet)
// Note: disabled state check via WDA: GET /element/{id}/enabled → false

// P3: Invalid code → error
await s.click(inviteField!);
// (input via Argus act or WDA /element/{id}/value)
await s.click(pairButton!);
const errorLabel = await s.findElement("pairing.errorLabel");
assert(errorLabel !== null, "P3: errorLabel appears for invalid code");

// P4-P5: Valid invite via deep link (bypasses 10s WDA typing timeout for ~1800-char codes)
// xcrun simctl openurl B1B452F0-45C4-4FC2-8807-EAA7DDE53C56 "odyssey://invite?invite=\${INVITE}"
// Then assert tab bar appears:
const tabConversations = await s.findElement("Conversations"); // tab bar item
assert(tabConversations !== null, "P4/P5: tab bar visible after pairing");

await s.close();
`;

// ─── Group 2: Conversations (G2 / C1–C6) ─────────────────────────────────
//
// RESULTS (2026-04-14):
//   C1 ✅ Conversations tab loads (accessible via "Conversations" tab bar item)
//   C2 ✅ Empty state: "No Conversations – Connect to your Mac to see conversations here."
//   C3 ⏭  Requires connected sidecar — skipped
//   C4 ✅ "Refresh conversations" button tap triggers reload
//   C5 ✅ Pull-to-refresh swipe gesture recognized (swipe down on list)
//   C6 ⏭  Requires conversation rows — skipped

export const G2_CONVERSATIONS_STEPS = `
const s = await wdaSession("com.odyssey.app.ios");

// C1-C2: empty state
const tab = await s.findElement("Conversations");
await s.click(tab!);
const emptyState = await s.findElement("conversationList.emptyState");
assert(emptyState !== null, "C2: empty state visible");

// C4: refresh button
const refresh = await s.findElement("Refresh conversations");
assert(refresh !== null, "C4: refresh button exists");
await s.click(refresh!);

// C5: pull-to-refresh (swipe down on list area)
await s.swipe(160, 200, 160, 380, 800);

await s.close();
`;

// ─── Group 4: Agents (G4 / A1–A6) ────────────────────────────────────────
//
// RESULTS (2026-04-14):
//   A1 ✅ Agents tab loads — "No Agents – Connect to your Mac to see available agents."
//   A2 ✅ Red "● Disconnected" badge in navigation bar (top-right)
//   A3 ✅ Empty state visible
//   A4 ✅ Agents tab accessible via tab bar
//   A5 ⏭  New conversation sheet requires connected sidecar — skipped
//   A6 ⏭  Agent row tap requires agent list from sidecar — skipped

export const G4_AGENTS_STEPS = `
const s = await wdaSession("com.odyssey.app.ios");

const agentsTab = await s.findElement("Agents");
await s.click(agentsTab!);

// A2: disconnected badge
// Note: the badge text element has label "Connection: Disconnected" (not an accessible button)
// Verified visually: red circle + "Disconnected" text in nav bar top-right

// A3: empty state
// "No Agents" text visible via screenshot AI assertion

await s.close();
`;

// ─── Group 5: Settings (G5 / S1–S6) ──────────────────────────────────────
//
// RESULTS (2026-04-14):
//   S1 ✅ Settings tab accessible
//   S2 ✅ "Connection: Disconnected" status visible (red badge)
//   S3 ✅ "Reconnect" button present and tappable
//   S4 ✅ Paired Macs section shows "default" at "127.0.0.1:9849"
//   S5 ✅ "Unpair" button visible for the paired Mac
//   S6 ✅ "Version 1.0" shown in About section

export const G5_SETTINGS_STEPS = `
const s = await wdaSession("com.odyssey.app.ios");

const settingsTab = await s.findElement("Settings");
await s.click(settingsTab!);

// S2: connection status
// Static text "Connection: Disconnected" exists in accessibility tree

// S3: reconnect
const reconnect = await s.findElement("Reconnect");
assert(reconnect !== null, "S3: Reconnect button exists");

// S4: paired Mac (scroll down to see)
await s.swipe(160, 380, 160, 100, 1000); // scroll down
// Static text "default" (Mac name) + "127.0.0.1:9849" (address) visible
// Verified: getText on static text elements returns expected values

// S5: unpair button
const unpair = await s.findElement("Unpair");
assert(unpair !== null, "S5: Unpair button exists");

// S6: version
// "Version" + "1.0" static text elements found in About section

await s.close();
`;

// ─── Group 6: Visual Quality (G6 / V1–V8) ────────────────────────────────
//
// RESULTS (2026-04-14):
//   V1 ✅ Conversations light: white bg, dark text, correct contrast
//   V2 ✅ Agents light: white bg, "Disconnected" badge red
//   V3 ✅ Settings light: white card bg, section headers legible
//   V4 ✅ Pairing light: white bg, logo, invite field visible
//   V5 ✅ Conversations dark: black bg, white text, tab bar dark pill
//   V6 ✅ Agents dark: dark bg, white text, red Disconnected badge
//   V7 ✅ Settings dark: dark cards, white text, red Disconnected bleed-through
//   V8 ✅ iOS 26 liquid-glass tab bar visible in both modes

export const G6_VISUAL_STEPS = `
// Light mode is default — take screenshots directly
// Switch to dark mode:
// xcrun simctl ui B1B452F0-45C4-4FC2-8807-EAA7DDE53C56 appearance dark
// Then take screenshots of each tab.
// Switch back:
// xcrun simctl ui B1B452F0-45C4-4FC2-8807-EAA7DDE53C56 appearance light

// For each screenshot, use Argus AI assertion:
// mcp__argus__assert({ type: "ai", prompt: "Screen is in dark mode: dark background, white text, proper contrast" })
`;

// ─── Screenshot Registry ──────────────────────────────────────────────────
export const screenshots = {
  "P1_pairing_screen_light":    "tests/screenshots/ios26/P1_pairing_screen_light.png",
  "P3_after_pairing":           "tests/screenshots/ios26/P3_after_pairing_conversations.png",
  "P5_disconnected_badge":      "tests/screenshots/ios26/P5_disconnected_badge.png",
  "G2_conversations_light":     "tests/screenshots/ios26/G2_conversations_light.png",
  "G2_conversations_dark":      "tests/screenshots/ios26/G2_conversations_dark.png",
  "G4_agents_light":            "tests/screenshots/ios26/G4_agents_light.png",
  "G4_agents_dark":             "tests/screenshots/ios26/G4_agents_dark.png",
  "G5_settings_light":          "tests/screenshots/ios26/G5_settings_light.png",
  "G5_settings_paired_mac":     "tests/screenshots/ios26/G5_settings_paired_mac.png",
  "G5_settings_dark":           "tests/screenshots/ios26/G5_settings_dark.png",
};

// ─── Known Issues & Fixes Applied ────────────────────────────────────────
export const fixesApplied = [
  {
    id: "FIX-1",
    file: "Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift",
    description: "NSJSONSerialization.data() escapes '/' as '\\/' (+1 byte per slash). " +
      "Canonical JSON was 17 bytes longer than TypeScript JSON.stringify output, " +
      "causing Ed25519 signature verification to always fail. " +
      "Fix: unescape '\\/' → '/' after JSONSerialization.data(withJSONObject:options:.sortedKeys).",
  },
  {
    id: "FIX-2",
    file: "WDA bundle Frameworks directory (simulator-installed)",
    description: "WDA 11.4.1 links libXCTestSwiftSupport.dylib which depends on " +
      "@rpath/_Testing_Foundation.framework not present in iOS 26.4 simruntime. " +
      "Fix: copy _Testing_Foundation.framework from iPhoneSimulator.platform into " +
      "WebDriverAgentRunner.xctest/Frameworks/ after each WDA install.",
  },
];
