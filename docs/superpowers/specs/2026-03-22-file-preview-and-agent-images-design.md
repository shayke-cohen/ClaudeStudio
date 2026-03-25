# File Preview, Diff Highlighting, and Agent Image Support

**Date:** 2026-03-22
**Status:** Draft

## Overview

Three related enhancements to ClaudPeer's inspector and chat:

1. **Smart file preview** — Preview mode for HTML, PDF, JSON, and images (markdown already supported)
2. **Diff syntax highlighting** — Syntax-colored code in the diff view, not just plain monospaced text
3. **Agent image display** — Surface images returned by Claude in chat messages

## A. File Preview Expansion

### Current State

`FileContentView` has three modes: Preview (markdown only), Source (syntax-highlighted), Diff (green/red lines). Binary files (images, PDFs, zips) show a "Binary File" placeholder.

### Changes

**`FileViewMode` and `availableModes`:**

Replace `isMarkdown` with `isPreviewable` computed property. Preview is available for: markdown, HTML, JSON, PDF, and image files.

```
isPreviewable = isMarkdown || isHTML || isJSON || isPDF || isImage
```

**Available modes by file type:**

| File type | Modes | Notes |
|---|---|---|
| Markdown, HTML, JSON | Preview, Source, (Diff if changed) | Text-based, both preview and source make sense |
| PDF, Image | Preview only (+ Diff if changed) | Binary files — `fileContent` stays nil, use `fileData` |
| Unknown text | Source (+ Diff if changed) | No preview available |
| Unknown binary | Binary placeholder | Existing behavior unchanged |

**Preview dispatch in `contentArea`:**

When `viewMode == .preview`, dispatch based on file extension:

| File type | Extensions | View | Framework | Notes |
|---|---|---|---|---|
| Markdown | md, markdown, mdown | `MarkdownContent` | MarkdownUI | Existing, no change |
| HTML | html, htm, xhtml | `WKWebView` loading local file URL | WebKit | JS disabled, navigation blocked |
| JSON | json | `JSONTreeView` (new) | Pure SwiftUI | Collapsible tree, max 1000 nodes |
| PDF | pdf | `PDFView` via `PDFDocument(url:)` | PDFKit | URL-based loading (no full memory load) |
| Image (raster) | png, jpg, jpeg, gif, webp, ico | `NSImage` display | AppKit | GIF shows static first frame |
| SVG | svg | `WKWebView` loading local file | WebKit | SVG is text but renders via WebView |

**Binary file handling and `fileData` loading:**

New state: `@State private var fileData: Data?`

Updated `loadContent()` logic:
```swift
let ext = nodeURL.pathExtension.lowercased()
let isPreviewableBinary = FileSystemService.isBinaryPreviewable(ext)
let binary = isPreviewableBinary ? false : FileSystemService.isBinaryFile(at: nodeURL)

// For previewable binaries, load raw Data (capped at 50MB for PDFs, 10MB for images)
let rawData: Data? = isPreviewableBinary ? loadFileData(at: nodeURL, maxBytes: isPDF ? 50_000_000 : 10_000_000) : nil

// For text files, load as string (existing behavior, capped at 512KB)
let content = (binary || isPreviewableBinary) ? nil : FileSystemService.readFileContents(at: nodeURL)
```

Key invariants:
- `fileContent` (String?) is nil for binary-previewable files (images, PDFs)
- `fileData` (Data?) is non-nil for binary-previewable files
- Source mode is unavailable for binary-previewable files (no text to show)

### New Views

**`HTMLPreviewView`** — NSViewRepresentable wrapping WKWebView.
- `loadFileURL(node.url, allowingReadAccessTo: node.url.deletingLastPathComponent())`
- JavaScript disabled via `WKWebpagePreferences.allowsContentJavaScript = false`
- `WKNavigationDelegate` blocks all external navigation (return `.cancel` for non-file URLs)
- Coordinator holds the WKWebView for reuse across `updateNSView` calls
- Accessibility ID: `inspector.fileContent.htmlPreview`

**`JSONTreeView`** — Pure SwiftUI recursive view.
- Parse `fileContent` string with `JSONSerialization`
- `JSONTreeNode` renders each key-value pair
- Objects and arrays are `DisclosureGroup` (collapsed by default, first level expanded)
- Value styling: strings green, numbers blue, booleans orange, null gray, keys bold
- **Node limit:** Max 1000 rendered nodes. Beyond that, show "... N more items" truncation label.
- **Invalid JSON:** Show `ContentUnavailableView("Invalid JSON", ...)` instead of crashing
- Accessibility IDs: `inspector.fileContent.jsonTree` on container, `inspector.fileContent.jsonTree.node.\(depth).\(index)` on disclosure groups
- Accessibility ID: `inspector.fileContent.jsonTree`

**`PDFPreviewView`** — NSViewRepresentable wrapping PDFKit's PDFView.
- `pdfView.document = PDFDocument(url: node.url)` — URL-based loading avoids reading entire PDF into memory
- `autoScales = true`
- Accessibility ID: `inspector.fileContent.pdfPreview`

**`ImagePreviewView`** — SwiftUI view displaying NSImage.
- Load via `NSImage(data: fileData)` for raster formats
- Scale image to fit available width, maintain aspect ratio
- Overlay at bottom: dimensions (W × H), file size, format
- Click to open in default app
- GIF displays as static first frame (NSImage does not animate; acceptable limitation)
- WebP supported natively on macOS 14+ (project minimum target)
- Accessibility ID: `inspector.fileContent.imagePreview`

### File Classification Helpers

Add to `FileSystemService`:

```swift
static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]
static let jsonExtensions: Set<String> = ["json"]
static let pdfExtensions: Set<String> = ["pdf"]
static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "ico"]
static let svgExtensions: Set<String> = ["svg"]

static func isHTMLFile(_ name: String) -> Bool
static func isJSONFile(_ name: String) -> Bool
static func isPDFFile(_ name: String) -> Bool
static func isImageFile(_ name: String) -> Bool      // raster images only
static func isSVGFile(_ name: String) -> Bool         // text-based, renders via WebView
static func isPreviewableFile(_ name: String) -> Bool // any of the above + markdown
static func isBinaryPreviewable(_ ext: String) -> Bool // image (not SVG) + PDF
```

Note: SVG is a text format (no null bytes) and loads into `fileContent` as a string. It renders via WKWebView like HTML. It is NOT treated as binary-previewable.

## B. Diff Syntax Highlighting

### Current State

`DiffTextView` renders each line as a SwiftUI `Text` with green/red/blue backgrounds but no syntax coloring of the code itself.

### Changes

**`HighlightedDiffView`** replaces `DiffTextView`. Uses `Highlightr` (already a dependency) to colorize the code portion of each diff line. Retains the existing `inspector.fileContent.diffView` accessibility identifier.

Algorithm:
1. Detect the file language from `node.fileExtension` via `FileSystemService.languageForExtension()`
2. Collect all diff lines, strip the leading `+`/`-`/` ` prefix character (skip header/hunk lines)
3. Join stripped code lines into a single string, pass through `Highlightr.highlight()` to get an `NSAttributedString`
4. Split the highlighted result back into per-line attributed strings
5. **Line count guard:** If highlighted line count differs from input line count, fall back to unhighlighted plain text rendering
6. Re-add the prefix character and apply the diff background color (green/red/blue) to each line
7. Render via NSViewRepresentable with NSScrollView + NSTextView (like `HighlightedCodeView`)

**Fallback:** If the language is unknown, Highlightr fails, or line count mismatches, fall back to the current plain `DiffTextView` rendering.

**Pass language from `FileContentView`:** `diffView` already has access to `node` — pass `node.fileExtension` through to the diff view as a `language` parameter.

## C. Agent Image Support

### Current State

- **User → Agent:** Users can attach images. The sidecar writes them to temp files for the agent.
- **Agent → User:** The Claude Agent SDK (v0.2.71) can return `image` content blocks, but `handleSDKMessage()` in `session-manager.ts` only processes `text` and `thinking` blocks. Image blocks are silently dropped.
- **Chat UI:** `MessageBubble` renders `MessageAttachment` images with thumbnails and full-screen preview. This works for user attachments only.

### Changes

#### Sidecar (TypeScript)

**`types.ts`** — Add new event:
```typescript
| { type: "stream.image"; sessionId: string; imageData: string; mediaType: string; fileName?: string }
```

**`session-manager.ts`** — In `handleSDKMessage()`, detect image blocks:
```typescript
if (block.type === "image" && block.source?.type === "base64") {
    this.emit("stream.image", {
        sessionId: this.sessionId,
        imageData: block.source.data,      // base64
        mediaType: block.source.media_type, // e.g. "image/png"
    });
}
```

Guard: Only handle `block.source.type === "base64"`. If the SDK ever returns URL-based images, log a warning and skip (future enhancement).

**`ws-server.ts`** — No changes needed. The `emit()` callback already broadcasts all events generically over WebSocket.

#### Wire Protocol (Swift)

**`SidecarProtocol.swift`** — Add `SidecarEvent` case:
```swift
case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
```

Add to `IncomingWireMessage` struct:
```swift
var imageData: String?
var mediaType: String?  // Note: distinct from WireAttachment.mediaType (different type)
var fileName: String?   // reuses existing optional field
```

Add decoding in `IncomingWireMessage.toEvent()` for `"stream.image"`.

#### AppState (Swift)

Add accumulator:
```swift
@Published var streamingImages: [String: [(data: String, mediaType: String)]] = [:]
```

In `handleEvent()`:
```swift
case .streamImage(let sessionId, let imageData, let mediaType, _):
    let key = sessionId
    streamingImages[key, default: []].append((data: imageData, mediaType: mediaType))
```

**Cleanup on error:** In the `sessionError` handler, also clear `streamingImages[key]` to prevent memory leaks for failed sessions.

#### Message Finalization

`finalizeAssistantStreamIntoMessage()` lives in **`ChatView.swift`** (not AppState).

After creating the `ConversationMessage`:
1. Check `appState.streamingImages[key]` for accumulated images
2. For each image: decode base64 → `Data`, save to `AttachmentStore`
3. Create `MessageAttachment` records linked to the message (with `isImage` media type)
4. Clear `appState.streamingImages[key]`
5. Handle base64 decode failures gracefully (log warning, skip that image)

#### WebSocket Message Size

Bun.serve's WebSocket default max message size is 16MB. A 5MB image encodes to ~6.67MB base64, well within limits. For images exceeding 10MB base64, the sidecar should log a warning and skip. This covers the vast majority of agent-generated images (typically screenshots, diagrams, charts).

#### UI

No changes needed — `MessageBubble` already renders `MessageAttachment` images via `AttachmentThumbnail` and `ImagePreviewOverlay`.

## C2. Tool-Generated File Display

### Problem

Agents frequently produce files via tools (screenshots, HTML apps, PDFs) and mention the file path in their text response. The SDK does NOT return these as `image` content blocks — the file is just saved to disk and the text says "Saved at /path/to/file.png". No inline preview appears in the chat.

### Approach

Scan tool result text for absolute file paths pointing to known file types. For images, read the file, base64-encode, and emit `stream.image` (reusing the Section C pipeline). For HTML/PDF, emit a new `stream.fileCard` event that the Swift side renders as a clickable card.

### Sidecar: File Path Detection

In `session-manager.ts`, after receiving a tool result from the SDK, scan the output text for file paths:

```typescript
const FILE_PATH_REGEX = /(?:^|\s)(\/[\w./-]+\.(?:png|jpe?g|gif|webp|svg|ico|html?|pdf))(?:\s|$|[.,;)}\]])/gim;

function extractFilePaths(text: string): { path: string; type: "image" | "html" | "pdf" }[] {
    const matches = [...text.matchAll(FILE_PATH_REGEX)];
    return matches.map(m => {
        const path = m[1];
        const ext = path.split(".").pop()?.toLowerCase() ?? "";
        if (["png","jpg","jpeg","gif","webp","svg","ico"].includes(ext)) return { path, type: "image" };
        if (["html","htm"].includes(ext)) return { path, type: "html" };
        if (ext === "pdf") return { path, type: "pdf" };
        return null;
    }).filter(Boolean);
}
```

In `handleSDKMessage()`, when processing tool results:

```typescript
if (block.type === "tool_result" && typeof block.content === "string") {
    const files = extractFilePaths(block.content);
    for (const file of files) {
        if (file.type === "image") {
            // Read file, base64-encode, emit stream.image
            const data = await Bun.file(file.path).arrayBuffer();
            const base64 = Buffer.from(data).toString("base64");
            const mediaType = extensionToMediaType(file.path);
            if (base64.length < 10_000_000) { // 10MB base64 limit
                this.emit("stream.image", {
                    sessionId: this.sessionId,
                    imageData: base64,
                    mediaType,
                    fileName: file.path.split("/").pop(),
                });
            }
        } else {
            // HTML or PDF — emit lightweight file card
            this.emit("stream.fileCard", {
                sessionId: this.sessionId,
                filePath: file.path,
                fileType: file.type,
                fileName: file.path.split("/").pop() ?? "file",
            });
        }
    }
}
```

### Wire Protocol: `stream.fileCard` Event

**`types.ts`:**
```typescript
| { type: "stream.fileCard"; sessionId: string; filePath: string; fileType: "html" | "pdf"; fileName: string }
```

**`SidecarProtocol.swift`:**
```swift
case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
```

Add to `IncomingWireMessage`: `filePath: String?`, `fileType: String?` (reuse existing `fileName`).

### AppState: File Card Accumulation

```swift
@Published var streamingFileCards: [String: [(path: String, type: String, name: String)]] = [:]
```

In `handleEvent()`:
```swift
case .streamFileCard(let sessionId, let filePath, let fileType, let fileName):
    let key = sessionId
    streamingFileCards[key, default: []].append((path: filePath, type: fileType, name: fileName))
```

Clean up on session error (same as `streamingImages`).

### Message Finalization

In `finalizeAssistantStreamIntoMessage()` (in `ChatView.swift`), after handling images:

1. Check `appState.streamingFileCards[key]`
2. For each file card, create a `MessageAttachment` with:
   - `mediaType`: `"text/html"` or `"application/pdf"`
   - `fileName`: the file name
   - Store the `filePath` — use a new optional field on `MessageAttachment` or encode in `fileName`
3. Clear `appState.streamingFileCards[key]`

### UI: File Card in Chat

**`MessageBubble`** already renders attachments via `AttachmentThumbnail`. Extend `AttachmentThumbnail` to detect HTML/PDF attachments that have a local file path and render them as a clickable card:

- **Card appearance:** File icon (HTML/PDF), file name, file type badge, "Preview" button
- **Tap action:** Navigate to the file in the inspector's Files tab with Preview mode active. This requires:
  - Setting `appState.inspectorFileRequest = (path, viewMode: .preview)` (new published property)
  - `FileExplorerView` observes this and navigates to the file
- **Accessibility ID:** `messageBubble.fileCard.\(attachment.id)`

### MessageAttachment Model Change

Add to `MessageAttachment`:
```swift
var localFilePath: String?  // absolute path for tool-generated files
```

This field is nil for user-uploaded attachments and SDK image blocks (which store data in AttachmentStore). It is set for tool-generated HTML/PDF file cards where the file already exists on disk.

## D. Tests

### Swift (XCTest)

**`FileViewModeTests.swift`:**
- `availableModes` returns `[.preview, .source]` for markdown
- `availableModes` returns `[.preview, .source]` for HTML, JSON
- `availableModes` returns `[.preview, .source, .diff]` for modified HTML
- `availableModes` returns `[.source]` for unknown text file
- `availableModes` returns `[.preview]` for PDF, image (binary previewable)
- `isPreviewable` returns correct values for each extension
- SVG is previewable but NOT binary-previewable

**`DiffLineStyleTests.swift`:**
- Lines starting with `+` (not `+++`) → `.added`
- Lines starting with `-` (not `---`) → `.removed`
- Lines starting with `@@` → `.hunk`
- Lines starting with `diff `, `index `, `---`, `+++` → `.header`
- All other lines → `.context`
- Empty lines → `.context`

**`JSONTreeParsingTests.swift`:**
- Parse simple object `{"key": "value"}`
- Parse nested object
- Parse array of primitives
- Parse mixed nested structure
- Handle empty object/array
- Handle invalid JSON gracefully (returns error node, doesn't crash)
- Handle large JSON (> 1000 nodes) — verifies truncation

**`AppStateEventTests.swift`** (extend existing):
- `stream.image` event accumulates in `streamingImages`
- `stream.fileCard` event accumulates in `streamingFileCards`
- Multiple images for same session accumulate correctly
- Session error clears both `streamingImages` and `streamingFileCards`
- Base64 decode failure is handled gracefully (skipped, not crash)

**`FilePathExtractionTests.swift`** (sidecar logic, test in Swift or TS):
- Extracts `/path/to/screenshot.png` from tool result text
- Extracts multiple file paths from single text block
- Ignores non-matching extensions (`.swift`, `.ts`, etc.)
- Handles paths with spaces (quoted paths)
- Does not match relative paths (only absolute)
- Handles paths at end of sentence (`/path/to/file.png.`)

### TypeScript (sidecar/test/)

- `handleSDKMessage` emits `stream.image` for base64 image blocks
- `handleSDKMessage` skips URL-type image blocks with warning
- `handleSDKMessage` ignores non-image, non-text blocks gracefully
- `extractFilePaths` correctly extracts image/HTML/PDF paths from tool result text
- Tool result with image path reads file and emits `stream.image`
- Tool result with HTML path emits `stream.fileCard`
- Tool result with non-existent file path is skipped gracefully

## E. Spec and Doc Updates

**`CLAUDE.md`:**
- Add new views to the `inspector.fileContent.*` prefix section (not as separate top-level prefixes): `htmlPreview`, `jsonTree`, `pdfPreview`, `imagePreview`
- Add `stream.image` and `stream.fileCard` to the wire protocol event list
- Add `IncomingWireMessage` fields: `imageData`, `mediaType`, `filePath`, `fileType`
- Add `messageBubble.fileCard.*` to accessibility prefix map

**`TESTING.md`:**
- Add new test files to the coverage table
- Add file preview controls to the screen-by-screen inventory
- Add file card rendering to MessageBubble test coverage

## Dependencies

No new external dependencies. All frameworks used are system-provided:
- `WebKit` (WKWebView) — system framework, macOS 14+
- `PDFKit` (PDFView) — system framework, macOS 14+
- `Highlightr` — already a project dependency (used in HighlightedCodeView)
- `MarkdownUI` — already a project dependency

Note: `project.yml` does not need explicit framework entries for WebKit and PDFKit — they are auto-linked when imported.

## File Changes Summary

| File | Change |
|---|---|
| `FileContentView.swift` | Add preview dispatch, `fileData` state, `isPreviewable` logic, pass language to diff |
| `FileSystemService.swift` | Add file type classification helpers |
| `Views/MainWindow/HTMLPreviewView.swift` | New — WKWebView wrapper with JS disabled |
| `Views/MainWindow/JSONTreeView.swift` | New — collapsible JSON tree (max 1000 nodes) |
| `Views/MainWindow/PDFPreviewView.swift` | New — PDFKit wrapper (URL-based loading) |
| `Views/MainWindow/ImagePreviewView.swift` | New — inline image display with info overlay |
| `DiffTextView` → `HighlightedDiffView` (in FileContentView.swift) | Add syntax highlighting via Highlightr with line-count guard fallback |
| `sidecar/src/types.ts` | Add `stream.image` and `stream.fileCard` event types |
| `sidecar/src/session-manager.ts` | Handle SDK image blocks + scan tool results for file paths |
| `SidecarProtocol.swift` | Add `streamImage`, `streamFileCard` event cases + `IncomingWireMessage` fields + decoding |
| `ChatView.swift` | Update `finalizeAssistantStreamIntoMessage()` to convert accumulated images and file cards → `MessageAttachment` |
| `AppState.swift` | Add `streamingImages` + `streamingFileCards` accumulators, handle events, cleanup on error |
| `MessageAttachment.swift` | Add `localFilePath: String?` field |
| `Views/Components/AttachmentThumbnail.swift` | Extend to render file cards (HTML/PDF) with "Preview" tap action |
| Tests: 5 new/extended test files | FileViewMode, DiffLineStyle, JSONTreeParsing, FilePathExtraction, AppStateEvent |
| `CLAUDE.md`, `TESTING.md` | Doc updates |
