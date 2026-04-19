# Internal Browser — Design Spec

**Date:** 2026-04-19  
**Status:** Draft  

---

## Context

Odyssey agents currently have no way to browse the web or display rich interactive UIs beyond the fixed widget types in `ask_user` and `render_content`. This spec adds an embedded WKWebView browser with two modes: web navigation (agents browse external sites) and agent canvas (agents render custom HTML that users interact with). Agents control it via MCP tools; users watch and can take over at any time.

---

## Decisions

| Dimension | Decision |
|---|---|
| Placement | A+B — inline card in message stream + dedicated side panel |
| Control | Collaborative / handoff — agent drives, user can take over |
| Annotations | Element highlight + action log panel (Argus-style) |
| Session persistence | Configurable per project; default = project-scoped |
| Architecture | Approach 2 (WKWebView + JS injection), designed for Approach 3 (CDP) migration |
| Modes | Mode 1: web navigation · Mode 2: agent canvas |

---

## Architecture Overview

Two-process boundary is preserved. The WKWebView lives in Swift; agents in the sidecar call MCP tools that send wire commands to Swift, which executes them and sends results back.

```
Claude Agent (sidecar)
  → MCP tool call (browser_navigate, browser_click, …)
  → BrowserCommand wire message (WebSocket, existing channel)
  → BrowserController.swift (WKWebView backend today, CDP tomorrow)
  → Result wire event → sidecar → MCP tool result → agent
```

**Migration path to Approach 3 (CDP):** `BrowserController` is a Swift protocol. The current `WKWebViewBrowserController` implementation is swapped for a `CDPBrowserController` that speaks Chrome DevTools Protocol. MCP tool signatures, wire types, and UI are unchanged.

---

## Components

### Swift (new files)

| File | Responsibility |
|---|---|
| `Odyssey/Browser/BrowserController.swift` | Protocol: `navigate`, `click`, `type`, `scroll`, `screenshot`, `readDOM`, `getConsoleLogs`, `waitFor`, `renderHTML`, `yieldToUser` |
| `Odyssey/Browser/WKWebViewBrowserController.swift` | Concrete implementation using WKWebView |
| `Odyssey/Browser/BrowserSessionStore.swift` | Manages `WKWebsiteDataStore` pool; mode: `.project` (default) or `.thread` |
| `Odyssey/Browser/BrowserOverlayCoordinator.swift` | Manages handoff state machine; bridges JS bridge events to UI |
| `Odyssey/Browser/BrowserPanelView.swift` | Side panel (B-variant): URL bar, WKWebView, action log, control bar |
| `Odyssey/Browser/InlineBrowserCard.swift` | Inline card (A-variant): compact live view in message stream, expands to panel |
| `Odyssey/Browser/Resources/browser-inspector.js` | Injected at every page load via `WKUserScript` |

### Sidecar (new/modified files)

| File | Change |
|---|---|
| `sidecar/src/tools/browser-tools.ts` | All MCP browser tools (new file) |
| `sidecar/src/tools/browser-server.ts` | New `createBrowserServer()` — standalone SDK MCP server, registered as built-in MCP `"browser"` |
| `sidecar/src/index.ts` | Register browser server alongside peerbus-server |
| `sidecar/src/types.ts` | Add `BrowserCommand` and `BrowserEvent` union types |
| `sidecar/src/ws-server.ts` | Route `BrowserEvent` from Swift to pending tool resolvers |

---

## MCP Tool Set

### Mode 1 — Web Navigation

| Tool | Description |
|---|---|
| `browser_navigate(url)` | Navigate to URL. Returns `{ title, finalUrl }` after load. |
| `browser_screenshot()` | Capture viewport as base64 image. Returned as image content block (Claude vision). |
| `browser_read_dom()` | Return accessibility tree as JSON. Token-efficient alternative to raw HTML. |
| `browser_click(selector)` | Click element by CSS or aria selector. Highlights element before firing. |
| `browser_type(selector, text)` | Clear field and type text. Supports `\n`, `\t` special keys. |
| `browser_scroll(direction, px)` | Scroll `up`/`down` by pixel amount. |
| `browser_wait_for(selector, timeoutMs?)` | Block until element appears or timeout (default 10s). |
| `browser_get_console_logs()` | Return captured `console.log/warn/error` entries since page load. |
| `browser_get_network_logs()` | Return recent requests with URLs and status codes. Captured via `WKNavigationDelegate` — URL + status only, no request/response bodies (full interception is Approach 3). |
| `browser_yield_to_user(message)` | Pause agent, show message to user ("Please log in, then click Resume"). Blocks until user clicks Resume. |

All selectors follow Playwright conventions (CSS, `aria/`, `text/`) to keep signatures stable for the CDP migration.

### Mode 2 — Agent Canvas

| Tool | Description |
|---|---|
| `browser_render_html(html, title?, timeoutMs?)` | Load agent-supplied HTML into the browser. Blocks until the page calls `window.agent.submit(data)` or timeout (default 5 min). Returns `data` as a JSON object. If user closes the panel before submitting, resolves with `{ cancelled: true }`. |

The HTML the agent provides may call:
- `window.agent.submit(data)` — resolves the tool call with `data`
- `window.agent.update(html)` — replace page content without resolving (for streaming/multi-step UIs)

Canvas mode replaces `render_content` for interactive use cases. `render_content` remains for fire-and-forget display (Markdown, Mermaid, static HTML).

---

## JS Injection Bridge (`browser-inspector.js`)

Injected as a `WKUserScript` at document start on every page load. Responsibilities:

- **Selector resolution:** `resolveSelector(css)` → element + bounding rect
- **Highlight overlay:** `highlightElement(rect, label)` → green border + tooltip div; `clearHighlight()` removes it
- **Console capture:** intercepts `console.log/warn/error`, posts to Swift via `window.webkit.messageHandlers.consoleLog.postMessage`
- **DOM export:** `exportAccessibilityTree()` → JSON walk of the live DOM
- **Agent submit bridge:** `window.agent.submit(data)` posts to `window.webkit.messageHandlers.agentSubmit.postMessage`

Swift registers `WKScriptMessageHandler` for: `consoleLog`, `agentSubmit`, `elementBounds`, `pageReady`.

---

## Handoff State Machine

```
AGENT_DRIVING
  → user clicks "Take over"         → USER_DRIVING
  → agent calls browser_yield_to_user → YIELDED_TO_USER

USER_DRIVING
  → user clicks "Resume agent"      → AGENT_DRIVING

YIELDED_TO_USER
  → user clicks "Resume"            → AGENT_DRIVING
  → user clicks "Take over"         → USER_DRIVING
```

**Visual signals per state:**

| State | Control bar colour | Overlay | Buttons |
|---|---|---|---|
| `AGENT_DRIVING` | Green | Highlight + action log active | "Take over" |
| `YIELDED_TO_USER` | Amber | Agent message shown | "Resume" · "Take over" |
| `USER_DRIVING` | Blue | No highlight | "Resume agent" |

---

## Wire Protocol Additions

### Commands (Swift ← Sidecar)

```typescript
type BrowserCommand =
  | { type: "browser.navigate";    sessionId: string; url: string }
  | { type: "browser.click";       sessionId: string; selector: string }
  | { type: "browser.type";        sessionId: string; selector: string; text: string }
  | { type: "browser.scroll";      sessionId: string; direction: "up"|"down"; px: number }
  | { type: "browser.screenshot";  sessionId: string }
  | { type: "browser.readDom";     sessionId: string }
  | { type: "browser.getConsoleLogs"; sessionId: string }
  | { type: "browser.getNetworkLogs"; sessionId: string }
  | { type: "browser.waitFor";     sessionId: string; selector: string; timeoutMs: number }
  | { type: "browser.yieldToUser"; sessionId: string; message: string }
  | { type: "browser.renderHtml";  sessionId: string; html: string; title?: string }
  | { type: "browser.takeControl"; sessionId: string }  // user-initiated
  | { type: "browser.resume";      sessionId: string }  // user-initiated
```

### Events (Swift → Sidecar)

```typescript
type BrowserEvent =
  | { type: "browser.result";      sessionId: string; commandType: string; payload: unknown }
  | { type: "browser.error";       sessionId: string; commandType: string; error: string }
  | { type: "browser.pageLoaded";  sessionId: string; url: string; title: string }
  | { type: "browser.userSubmit";  sessionId: string; data: unknown }  // window.agent.submit
  | { type: "browser.stateChange"; sessionId: string; state: "agentDriving"|"userDriving"|"yieldedToUser" }
```

---

## Session Management

`BrowserSessionStore` maintains a map of `WKWebsiteDataStore` instances:

- **Project mode (default):** one store per `Project.id`. All threads in the project share cookies, localStorage, and auth.
- **Thread mode:** one store per `Conversation.id`. Clean slate per thread.

Configurable in project settings: `browserSessionMode: "project" | "thread"`. Default: `"project"`.

Store lifecycle: created on first browser use, persisted for the app session, cleared on explicit "Clear browser data" user action (added to project settings).

---

## UI Details

### InlineBrowserCard (A-variant)

- Appears in the message stream when `browser_navigate` or `browser_render_html` is first called in a session
- Compact: shows URL bar + live WKWebView snapshot (not interactive in compact state)
- Expand button → opens BrowserPanelView (B-variant)
- Collapses automatically when agent session ends
- Accessibility prefix: `inlineBrowser.*`

### BrowserPanelView (B-variant)

- Right-side panel, resizable (mirrors existing inspector split)
- **URL bar:** current URL (read-only when agent driving, editable when user driving)
- **Control bar:** state indicator (●/◐/○) + action buttons ("Take over" / "Resume")
- **WKWebView:** full interactive view; `isUserInteractionEnabled` toggled by handoff state
- **Action log sidebar:** scrollable list of completed agent actions with timestamps
- Accessibility prefix: `browserPanel.*`

---

## Accessibility Identifiers

| Element | Identifier |
|---|---|
| Inline card container | `inlineBrowser.card` |
| Inline expand button | `inlineBrowser.expandButton` |
| Panel container | `browserPanel.container` |
| URL bar | `browserPanel.urlBar` |
| State indicator | `browserPanel.stateIndicator` |
| Take over button | `browserPanel.takeOverButton` |
| Resume button | `browserPanel.resumeButton` |
| Action log | `browserPanel.actionLog` |
| WKWebView | `browserPanel.webView` |

---

## What's Out of Scope (Approach 3 / future)

- Multi-tab management
- Network request interception and mocking
- JS breakpoint / step debugging
- Full Chrome DevTools Protocol
- Browser extensions
- Video recording
- Hover, drag-and-drop, file upload interactions
- Cross-browser (Firefox, Chromium) — WebKit only today

---

## Verification

1. **Build check:** `make build-check` passes with all new Swift files added to `project.yml`
2. **Sidecar smoke:** `make sidecar-smoke` — mock provider calls `browser_navigate`, `browser_screenshot`, `browser_click`, `browser_read_dom`, `browser_render_html` and verifies wire round-trips
3. **Manual — Mode 1:** ask an agent to search GitHub, confirm inline card appears, element highlights shown before each click, action log populated, "Take over" hands control, "Resume" returns it
4. **Manual — Mode 2:** ask an agent to render a data table, confirm user can select rows, `window.agent.submit` resolves the tool call, agent receives selected data
5. **Session persistence:** log into a site in project browser mode, start a new thread, confirm session is retained
6. **AppXray:** use `@testId("browserPanel.takeOverButton")` and `@testId("browserPanel.resumeButton")` to drive handoff state transitions in automated tests
