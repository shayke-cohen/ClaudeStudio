# File Preview, Diff Highlighting, and Agent Image Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add smart file previews (HTML/PDF/JSON/Image) in the inspector, syntax highlighting in diff view, and inline display of agent-generated images/files in chat.

**Architecture:** Inspector file preview extends `FileContentView` with new preview views dispatched by file type. Agent images flow through a new `stream.image` sidecar event into existing `MessageAttachment` rendering. Tool-generated files are detected by scanning tool result text for file paths.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, WebKit (WKWebView), PDFKit, Highlightr, TypeScript / Bun (sidecar)

**Spec:** `docs/superpowers/specs/2026-03-22-file-preview-and-agent-images-design.md`

**Important notes for implementers:**
- After creating any new `.swift` file, run `xcodegen generate` to update the Xcode project.
- `AttachmentStore.save(data:mediaType:fileName:)` returns a `MessageAttachment` — use the returned object, don't create a duplicate.
- `IncomingWireMessage` does NOT have a `fileName` field — it must be added along with `imageData`, `mediaType`, `filePath`, `fileType`.
- Use `viewMode = availableModes.first ?? .source` when setting default view mode to prevent mode/picker mismatch.

---

## File Structure

| File | Responsibility | Status |
|---|---|---|
| `ClaudPeer/Services/FileSystemService.swift` | File type classification helpers | Modify |
| `ClaudPeer/Views/MainWindow/FileContentView.swift` | Preview dispatch, `fileData`, diff highlighting | Modify |
| `ClaudPeer/Views/MainWindow/HTMLPreviewView.swift` | WKWebView wrapper (JS disabled) | Create |
| `ClaudPeer/Views/MainWindow/JSONTreeView.swift` | Collapsible JSON tree | Create |
| `ClaudPeer/Views/MainWindow/PDFPreviewView.swift` | PDFKit wrapper | Create |
| `ClaudPeer/Views/MainWindow/ImagePreviewView.swift` | Inline image + info overlay | Create |
| `ClaudPeer/Models/MessageAttachment.swift` | Add `localFilePath` field | Modify |
| `ClaudPeer/Services/SidecarProtocol.swift` | `streamImage` + `streamFileCard` events | Modify |
| `ClaudPeer/App/AppState.swift` | Image/fileCard accumulators + event handlers | Modify |
| `ClaudPeer/Views/MainWindow/ChatView.swift` | Finalize images/fileCards into attachments | Modify |
| `ClaudPeer/Views/Components/AttachmentThumbnail.swift` | File card rendering for HTML/PDF | Modify |
| `sidecar/src/types.ts` | New event types | Modify |
| `sidecar/src/session-manager.ts` | Handle image blocks + tool file path scanning | Modify |
| `ClaudPeerTests/FileClassificationTests.swift` | File type helper tests | Create |
| `ClaudPeerTests/JSONTreeParsingTests.swift` | JSON parsing + truncation tests | Create |
| `ClaudPeerTests/DiffLineStyleTests.swift` | Diff line classification tests | Create |
| `ClaudPeerTests/AppStateEventTests.swift` | Extend with image/fileCard event tests | Modify |
| `ClaudPeerTests/SidecarProtocolTests.swift` | Extend with new event encoding/decoding | Modify |
| `sidecar/test/file-path-extraction.test.ts` | File path regex tests | Create |

---

### Task 1: File Type Classification Helpers

**Files:**
- Modify: `ClaudPeer/Services/FileSystemService.swift:11` (after `markdownExtensions`)
- Create: `ClaudPeerTests/FileClassificationTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClaudPeerTests/FileClassificationTests.swift
import XCTest
@testable import ClaudPeer

final class FileClassificationTests: XCTestCase {
    func testHTMLDetection() {
        XCTAssertTrue(FileSystemService.isHTMLFile("page.html"))
        XCTAssertTrue(FileSystemService.isHTMLFile("index.htm"))
        XCTAssertTrue(FileSystemService.isHTMLFile("app.xhtml"))
        XCTAssertFalse(FileSystemService.isHTMLFile("style.css"))
    }

    func testJSONDetection() {
        XCTAssertTrue(FileSystemService.isJSONFile("data.json"))
        XCTAssertFalse(FileSystemService.isJSONFile("data.jsonl"))
    }

    func testPDFDetection() {
        XCTAssertTrue(FileSystemService.isPDFFile("doc.pdf"))
        XCTAssertFalse(FileSystemService.isPDFFile("doc.pdf.bak"))
    }

    func testImageDetection() {
        XCTAssertTrue(FileSystemService.isImageFile("photo.png"))
        XCTAssertTrue(FileSystemService.isImageFile("photo.jpg"))
        XCTAssertTrue(FileSystemService.isImageFile("photo.jpeg"))
        XCTAssertTrue(FileSystemService.isImageFile("photo.gif"))
        XCTAssertTrue(FileSystemService.isImageFile("photo.webp"))
        XCTAssertFalse(FileSystemService.isImageFile("icon.svg")) // SVG is separate
    }

    func testSVGDetection() {
        XCTAssertTrue(FileSystemService.isSVGFile("icon.svg"))
        XCTAssertFalse(FileSystemService.isSVGFile("icon.png"))
    }

    func testPreviewableFile() {
        XCTAssertTrue(FileSystemService.isPreviewableFile("readme.md"))
        XCTAssertTrue(FileSystemService.isPreviewableFile("page.html"))
        XCTAssertTrue(FileSystemService.isPreviewableFile("data.json"))
        XCTAssertTrue(FileSystemService.isPreviewableFile("doc.pdf"))
        XCTAssertTrue(FileSystemService.isPreviewableFile("photo.png"))
        XCTAssertTrue(FileSystemService.isPreviewableFile("icon.svg"))
        XCTAssertFalse(FileSystemService.isPreviewableFile("code.swift"))
    }

    func testBinaryPreviewable() {
        XCTAssertTrue(FileSystemService.isBinaryPreviewable("png"))
        XCTAssertTrue(FileSystemService.isBinaryPreviewable("jpg"))
        XCTAssertTrue(FileSystemService.isBinaryPreviewable("pdf"))
        XCTAssertFalse(FileSystemService.isBinaryPreviewable("svg")) // text, not binary
        XCTAssertFalse(FileSystemService.isBinaryPreviewable("html"))
        XCTAssertFalse(FileSystemService.isBinaryPreviewable("swift"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing ClaudPeerTests/FileClassificationTests 2>&1 | tail -20`
Expected: FAIL — methods don't exist yet

- [ ] **Step 3: Implement file classification helpers**

Add after line 11 in `FileSystemService.swift` (after `markdownExtensions`):

```swift
static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]
static let jsonExtensions: Set<String> = ["json"]
static let pdfExtensions: Set<String> = ["pdf"]
static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "ico"]
static let svgExtensions: Set<String> = ["svg"]

static func isHTMLFile(_ name: String) -> Bool {
    htmlExtensions.contains((name as NSString).pathExtension.lowercased())
}

static func isJSONFile(_ name: String) -> Bool {
    jsonExtensions.contains((name as NSString).pathExtension.lowercased())
}

static func isPDFFile(_ name: String) -> Bool {
    pdfExtensions.contains((name as NSString).pathExtension.lowercased())
}

static func isImageFile(_ name: String) -> Bool {
    imageExtensions.contains((name as NSString).pathExtension.lowercased())
}

static func isSVGFile(_ name: String) -> Bool {
    svgExtensions.contains((name as NSString).pathExtension.lowercased())
}

static func isPreviewableFile(_ name: String) -> Bool {
    isMarkdownFile(name) || isHTMLFile(name) || isJSONFile(name) || isPDFFile(name) || isImageFile(name) || isSVGFile(name)
}

static func isBinaryPreviewable(_ ext: String) -> Bool {
    let e = ext.lowercased()
    return imageExtensions.contains(e) || pdfExtensions.contains(e)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing ClaudPeerTests/FileClassificationTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ClaudPeer/Services/FileSystemService.swift ClaudPeerTests/FileClassificationTests.swift
git commit -m "feat: add file type classification helpers for preview support"
```

---

### Task 2: Image Preview View

**Files:**
- Create: `ClaudPeer/Views/MainWindow/ImagePreviewView.swift`

- [ ] **Step 1: Create ImagePreviewView**

```swift
// ClaudPeer/Views/MainWindow/ImagePreviewView.swift
import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let fileData: Data
    let fileName: String
    let fileSize: Int64
    let fileURL: URL

    @State private var nsImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            if let nsImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                imageInfoBar(nsImage: nsImage)
            } else {
                ContentUnavailableView("Unable to Load Image", systemImage: "photo.badge.exclamationmark", description: Text("Could not decode image data."))
            }
        }
        .accessibilityIdentifier("inspector.fileContent.imagePreview")
        .task { nsImage = NSImage(data: fileData) }
    }

    private func imageInfoBar(nsImage: NSImage) -> some View {
        HStack(spacing: 8) {
            let size = nsImage.size
            Text("\(Int(size.width)) × \(Int(size.height))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Text(FileSystemService.formatFileSize(fileSize))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Text(fileName.components(separatedBy: ".").last?.uppercased() ?? "IMG")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .accessibilityIdentifier("inspector.fileContent.imagePreview.openButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/MainWindow/ImagePreviewView.swift
git commit -m "feat: add ImagePreviewView for inline image display with info overlay"
```

---

### Task 3: HTML Preview View

**Files:**
- Create: `ClaudPeer/Views/MainWindow/HTMLPreviewView.swift`

- [ ] **Step 1: Create HTMLPreviewView**

```swift
// ClaudPeer/Views/MainWindow/HTMLPreviewView.swift
import SwiftUI
import WebKit

struct HTMLPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        context.coordinator.webView = webView
        webView.setAccessibilityIdentifier("inspector.fileContent.htmlPreview")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != fileURL {
            webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
            context.coordinator.lastURL = fileURL
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var lastURL: URL?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other || navigationAction.request.url?.isFileURL == true {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/MainWindow/HTMLPreviewView.swift
git commit -m "feat: add HTMLPreviewView with WKWebView, JS disabled, navigation blocked"
```

---

### Task 4: PDF Preview View

**Files:**
- Create: `ClaudPeer/Views/MainWindow/PDFPreviewView.swift`

- [ ] **Step 1: Create PDFPreviewView**

```swift
// ClaudPeer/Views/MainWindow/PDFPreviewView.swift
import SwiftUI
import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: fileURL)
        pdfView.setAccessibilityIdentifier("inspector.fileContent.pdfPreview")
        context.coordinator.lastURL = fileURL
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if context.coordinator.lastURL != fileURL {
            pdfView.document = PDFDocument(url: fileURL)
            context.coordinator.lastURL = fileURL
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/MainWindow/PDFPreviewView.swift
git commit -m "feat: add PDFPreviewView using PDFKit with URL-based loading"
```

---

### Task 5: JSON Tree View

**Files:**
- Create: `ClaudPeer/Views/MainWindow/JSONTreeView.swift`
- Create: `ClaudPeerTests/JSONTreeParsingTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClaudPeerTests/JSONTreeParsingTests.swift
import XCTest
@testable import ClaudPeer

final class JSONTreeParsingTests: XCTestCase {
    func testSimpleObject() {
        let nodes = JSONTreeParser.parse("{\"key\": \"value\"}")
        XCTAssertEqual(nodes.count, 1) // root object
        XCTAssertEqual(nodes[0].children?.count, 1)
    }

    func testNestedObject() {
        let nodes = JSONTreeParser.parse("{\"a\": {\"b\": 1}}")
        XCTAssertEqual(nodes.count, 1)
        let inner = nodes[0].children?[0]
        XCTAssertNotNil(inner?.children) // nested object has children
    }

    func testArrayOfPrimitives() {
        let nodes = JSONTreeParser.parse("[1, 2, 3]")
        XCTAssertEqual(nodes.count, 1) // root array
        XCTAssertEqual(nodes[0].children?.count, 3)
    }

    func testEmptyObjectAndArray() {
        let objNodes = JSONTreeParser.parse("{}")
        XCTAssertEqual(objNodes[0].children?.count, 0)
        let arrNodes = JSONTreeParser.parse("[]")
        XCTAssertEqual(arrNodes[0].children?.count, 0)
    }

    func testInvalidJSON() {
        let nodes = JSONTreeParser.parse("not json")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].isError)
    }

    func testNodeCountLimit() {
        // Create JSON with 1500 keys
        let keys = (0..<1500).map { "\"\($0)\": \($0)" }.joined(separator: ", ")
        let nodes = JSONTreeParser.parse("{\(keys)}")
        let totalRendered = nodes[0].children?.count ?? 0
        XCTAssertLessThanOrEqual(totalRendered, 1000)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing ClaudPeerTests/JSONTreeParsingTests 2>&1 | tail -20`
Expected: FAIL — `JSONTreeParser` doesn't exist

- [ ] **Step 3: Implement JSONTreeView and JSONTreeParser**

Create `ClaudPeer/Views/MainWindow/JSONTreeView.swift` with both the parser and the view. The parser is a testable standalone enum. The view uses recursive `DisclosureGroup`. See spec Section A "JSONTreeView" for full details.

Key points:
- `JSONTreeParser.parse(_ text: String) -> [JSONNode]` — returns parsed tree
- `JSONNode` has `key: String?`, `value: JSONValue`, `children: [JSONNode]?`, `isError: Bool`
- `JSONValue` enum: `.string`, `.number`, `.bool`, `.null`, `.object`, `.array`
- Max 1000 nodes; beyond that, add a truncation node
- Invalid JSON returns a single error node

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing ClaudPeerTests/JSONTreeParsingTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ClaudPeer/Views/MainWindow/JSONTreeView.swift ClaudPeerTests/JSONTreeParsingTests.swift
git commit -m "feat: add JSONTreeView with collapsible tree and 1000 node limit"
```

---

### Task 6: Wire FileContentView to New Preview Views

**Files:**
- Modify: `ClaudPeer/Views/MainWindow/FileContentView.swift`

This task connects Tasks 1-5 to the existing `FileContentView`. Changes:
1. Replace `isMarkdown` gate with `isPreviewable`
2. Add `@State private var fileData: Data?`
3. Update `loadContent()` to handle binary-previewable files
4. Expand `contentArea` preview dispatch to route by file type

- [ ] **Step 1: Update `availableModes` (line 32-38)**

Replace `isMarkdown` with `isPreviewable`. For binary-previewable files (image/PDF), only offer `.preview` (no `.source`).

```swift
private var isPreviewable: Bool {
    FileSystemService.isPreviewableFile(node.name)
}

private var isBinaryPreviewable: Bool {
    FileSystemService.isBinaryPreviewable(node.fileExtension)
}

private var availableModes: [FileViewMode] {
    var modes: [FileViewMode] = []
    if isPreviewable { modes.append(.preview) }
    if !isBinaryPreviewable { modes.append(.source) }
    if hasDiff { modes.append(.diff) }
    return modes
}
```

- [ ] **Step 2: Add `fileData` state and update `loadContent()`**

Add `@State private var fileData: Data?` (after line 22).

In `loadContent()`, update the `Task.detached` block to handle binary-previewable files:

```swift
let ext = nodeURL.pathExtension.lowercased()
let isPreviewableBin = FileSystemService.isBinaryPreviewable(ext)
let binary = isPreviewableBin ? false : FileSystemService.isBinaryFile(at: nodeURL)
let content = (binary || isPreviewableBin) ? nil : FileSystemService.readFileContents(at: nodeURL)
let rawData: Data? = isPreviewableBin ? try? Data(contentsOf: nodeURL) : nil
```

After the Task.detached, set `fileData = rawData`.

Update the default viewMode selection:

```swift
viewMode = availableModes.first ?? .source
```

- [ ] **Step 3: Expand preview dispatch in `contentArea` (around line 165)**

Replace the single `markdownPreview` case with a dispatch:

```swift
case .preview:
    previewView
```

Add new `previewView` computed property:

```swift
@ViewBuilder
private var previewView: some View {
    if FileSystemService.isMarkdownFile(node.name), let content = fileContent {
        ScrollView {
            MarkdownContent(text: content)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inspector.fileContent.markdownPreview")
    } else if FileSystemService.isHTMLFile(node.name) || FileSystemService.isSVGFile(node.name) {
        HTMLPreviewView(fileURL: node.url)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
    } else if FileSystemService.isJSONFile(node.name), let content = fileContent {
        JSONTreeView(jsonString: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if FileSystemService.isPDFFile(node.name) {
        PDFPreviewView(fileURL: node.url)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
    } else if FileSystemService.isImageFile(node.name), let data = fileData {
        ImagePreviewView(fileData: data, fileName: node.name, fileSize: node.size, fileURL: node.url)
    } else {
        emptyContentPlaceholder
    }
}
```

- [ ] **Step 4: Build and run to verify previews work**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Then launch the app and test with HTML, JSON, PDF, and image files.

- [ ] **Step 5: Commit**

```bash
git add ClaudPeer/Views/MainWindow/FileContentView.swift
git commit -m "feat: wire file preview dispatch for HTML, JSON, PDF, Image, SVG"
```

---

### Task 7: Diff Syntax Highlighting

**Files:**
- Modify: `ClaudPeer/Views/MainWindow/FileContentView.swift` (replace `DiffTextView` at line 339-403)
- Create: `ClaudPeerTests/DiffLineStyleTests.swift`

- [ ] **Step 1: Write failing tests for diff line classification**

```swift
// ClaudPeerTests/DiffLineStyleTests.swift
import XCTest
@testable import ClaudPeer

final class DiffLineStyleTests: XCTestCase {
    func testAddedLine() {
        XCTAssertEqual(DiffLineClassifier.classify("+ added line"), .added)
    }

    func testRemovedLine() {
        XCTAssertEqual(DiffLineClassifier.classify("- removed line"), .removed)
    }

    func testHunkHeader() {
        XCTAssertEqual(DiffLineClassifier.classify("@@ -1,3 +1,5 @@"), .hunk)
    }

    func testDiffHeaders() {
        XCTAssertEqual(DiffLineClassifier.classify("diff --git a/file b/file"), .header)
        XCTAssertEqual(DiffLineClassifier.classify("index abc..def 100644"), .header)
        XCTAssertEqual(DiffLineClassifier.classify("--- a/file"), .header)
        XCTAssertEqual(DiffLineClassifier.classify("+++ b/file"), .header)
    }

    func testContextLine() {
        XCTAssertEqual(DiffLineClassifier.classify(" context line"), .context)
        XCTAssertEqual(DiffLineClassifier.classify(""), .context)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `DiffLineClassifier` doesn't exist

- [ ] **Step 3: Extract `DiffLineClassifier` and implement `HighlightedDiffView`**

Replace the `DiffTextView`, `DiffLine`, and `DiffLineStyle` at the bottom of `FileContentView.swift` with:

1. `DiffLineClassifier` — testable enum with `classify(_ line: String) -> DiffLineType`
2. `HighlightedDiffView` — NSViewRepresentable using Highlightr for syntax coloring with diff backgrounds
3. Keep existing `DiffTextView` as the fallback (renamed to `PlainDiffView`)

The `HighlightedDiffView` algorithm:
- Strip `+`/`-`/` ` prefixes from code lines
- Join into single string, highlight with `Highlightr.highlight()`
- **Line count guard:** If highlighted line count != input line count, fall back to `PlainDiffView`
- Split back, re-add prefixes and diff background colors
- Render in NSScrollView + NSTextView

Pass `language: String?` from `diffView` to `HighlightedDiffView` via `FileSystemService.languageForExtension(node.fileExtension)`.

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS

- [ ] **Step 5: Build, run, and verify diff highlighting works**

Open a modified file in the inspector, switch to Diff tab. Code should be syntax-colored with green/red backgrounds.

- [ ] **Step 6: Commit**

```bash
git add ClaudPeer/Views/MainWindow/FileContentView.swift ClaudPeerTests/DiffLineStyleTests.swift
git commit -m "feat: add syntax highlighting to diff view with Highlightr"
```

---

### Task 8: Wire Protocol — `stream.image` and `stream.fileCard` Events

**Files:**
- Modify: `sidecar/src/types.ts:52-63`
- Modify: `ClaudPeer/Services/SidecarProtocol.swift:134-207`
- Modify: `ClaudPeerTests/SidecarProtocolTests.swift`

- [ ] **Step 1: Add event types to `types.ts` (after line 62)**

```typescript
  | { type: "stream.image"; sessionId: string; imageData: string; mediaType: string; fileName?: string }
  | { type: "stream.fileCard"; sessionId: string; filePath: string; fileType: "html" | "pdf"; fileName: string }
```

- [ ] **Step 2: Add Swift event cases (after line 144 in SidecarProtocol.swift)**

```swift
case streamImage(sessionId: String, imageData: String, mediaType: String, fileName: String?)
case streamFileCard(sessionId: String, filePath: String, fileType: String, fileName: String)
```

- [ ] **Step 3: Add IncomingWireMessage fields (after line 169)**

```swift
let imageData: String?
let mediaType: String?
let filePath: String?
let fileType: String?
let fileName: String?
```

- [ ] **Step 4: Add decoding cases in `toEvent()` (before `default:` at line 203)**

```swift
case "stream.image":
    guard let sid = sessionId, let img = imageData, let mt = mediaType else { return nil }
    return .streamImage(sessionId: sid, imageData: img, mediaType: mt, fileName: fileName)
case "stream.fileCard":
    guard let sid = sessionId, let fp = filePath, let ft = fileType, let fn = fileName else { return nil }
    return .streamFileCard(sessionId: sid, filePath: fp, fileType: ft, fileName: fn)
```

- [ ] **Step 5: Add protocol encoding/decoding tests**

Extend `SidecarProtocolTests.swift` with tests for the new event types. Test that JSON with `type: "stream.image"` and `type: "stream.fileCard"` decode correctly.

- [ ] **Step 6: Build and run tests**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' -only-testing ClaudPeerTests/SidecarProtocolTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add sidecar/src/types.ts ClaudPeer/Services/SidecarProtocol.swift ClaudPeerTests/SidecarProtocolTests.swift
git commit -m "feat: add stream.image and stream.fileCard wire protocol events"
```

---

### Task 9: Sidecar — Handle SDK Image Blocks + Tool File Path Scanning

**Files:**
- Modify: `sidecar/src/session-manager.ts:355-361`
- Create: `sidecar/test/file-path-extraction.test.ts`

- [ ] **Step 1: Write file path extraction tests**

```typescript
// sidecar/test/file-path-extraction.test.ts
import { describe, test, expect } from "bun:test";
import { extractFilePaths } from "../src/session-manager.js";

describe("extractFilePaths", () => {
  test("extracts image path", () => {
    const result = extractFilePaths("Saved at /Users/test/screenshot.png");
    expect(result).toHaveLength(1);
    expect(result[0]).toEqual({ path: "/Users/test/screenshot.png", type: "image" });
  });

  test("extracts HTML path", () => {
    const result = extractFilePaths("Created /tmp/output/index.html");
    expect(result).toHaveLength(1);
    expect(result[0]).toEqual({ path: "/tmp/output/index.html", type: "html" });
  });

  test("extracts PDF path", () => {
    const result = extractFilePaths("Report at /tmp/report.pdf");
    expect(result).toHaveLength(1);
    expect(result[0]).toEqual({ path: "/tmp/report.pdf", type: "pdf" });
  });

  test("extracts multiple paths", () => {
    const result = extractFilePaths("Files: /a/b.png and /c/d.html");
    expect(result).toHaveLength(2);
  });

  test("ignores non-matching extensions", () => {
    const result = extractFilePaths("Wrote /src/main.swift");
    expect(result).toHaveLength(0);
  });

  test("ignores relative paths", () => {
    const result = extractFilePaths("See ./relative/path.png");
    expect(result).toHaveLength(0);
  });

  test("handles path at end of sentence", () => {
    const result = extractFilePaths("Saved to /tmp/file.png.");
    expect(result).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Implement `extractFilePaths` and export it**

Add to `session-manager.ts`:

```typescript
const FILE_PATH_REGEX = /(?:^|\s)(\/[\w.\-/]+\.(?:png|jpe?g|gif|webp|svg|ico|html?|pdf))(?:\s|$|[.,;)}\]])/gi;

export function extractFilePaths(text: string): { path: string; type: "image" | "html" | "pdf" }[] {
  const results: { path: string; type: "image" | "html" | "pdf" }[] = [];
  for (const match of text.matchAll(FILE_PATH_REGEX)) {
    const path = match[1];
    const ext = path.split(".").pop()?.toLowerCase() ?? "";
    if (["png","jpg","jpeg","gif","webp","svg","ico"].includes(ext)) {
      results.push({ path, type: "image" });
    } else if (["html","htm"].includes(ext)) {
      results.push({ path, type: "html" });
    } else if (ext === "pdf") {
      results.push({ path, type: "pdf" });
    }
  }
  return results;
}
```

- [ ] **Step 3: Add SDK image block handling in `handleSDKMessage` (after line 361)**

In the `for (const block of message.message.content)` loop, after the existing `text` check:

```typescript
} else if (block.type === "image" && block.source?.type === "base64") {
  this.emit({
    type: "stream.image",
    sessionId,
    imageData: block.source.data,
    mediaType: block.source.media_type,
  });
}
```

- [ ] **Step 4: Add tool result file scanning in `handleSDKMessage` (in `tool_result` case)**

In the `tool_result` handler, after emitting `stream.toolResult`, scan the output for file paths:

```typescript
// Scan tool result for file paths
const output = typeof message.content === "string" ? message.content : JSON.stringify(message.content ?? "");
const files = extractFilePaths(output);
for (const file of files) {
  try {
    if (file.type === "image") {
      const data = await Bun.file(file.path).arrayBuffer();
      const base64 = Buffer.from(data).toString("base64");
      if (base64.length < 10_000_000) {
        const ext = file.path.split(".").pop()?.toLowerCase() ?? "png";
        const mediaTypes: Record<string, string> = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", svg: "image/svg+xml", ico: "image/x-icon" };
        this.emit({
          type: "stream.image",
          sessionId,
          imageData: base64,
          mediaType: mediaTypes[ext] ?? "image/png",
          fileName: file.path.split("/").pop(),
        });
      }
    } else {
      this.emit({
        type: "stream.fileCard",
        sessionId,
        filePath: file.path,
        fileType: file.type,
        fileName: file.path.split("/").pop() ?? "file",
      });
    }
  } catch { /* file doesn't exist or can't be read — skip silently */ }
}
```

Note: The `tool_result` handler needs to become `async`. Update the method signature if needed.

- [ ] **Step 5: Run tests**

Run: `cd sidecar && bun test test/file-path-extraction.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add sidecar/src/session-manager.ts sidecar/test/file-path-extraction.test.ts
git commit -m "feat: handle SDK image blocks and scan tool results for file paths"
```

---

### Task 10: AppState — Image and FileCard Accumulators

**Files:**
- Modify: `ClaudPeer/App/AppState.swift:23-24` (add properties) and `186-258` (handleEvent)
- Modify: `ClaudPeerTests/AppStateEventTests.swift`

- [ ] **Step 1: Write failing tests**

Extend `AppStateEventTests.swift`:

```swift
func testStreamImageAccumulates() {
    appState.handleEvent(.streamImage(sessionId: "s1", imageData: "base64data", mediaType: "image/png", fileName: "test.png"))
    XCTAssertEqual(appState.streamingImages["s1"]?.count, 1)
    appState.handleEvent(.streamImage(sessionId: "s1", imageData: "more", mediaType: "image/jpeg", fileName: nil))
    XCTAssertEqual(appState.streamingImages["s1"]?.count, 2)
}

func testStreamFileCardAccumulates() {
    appState.handleEvent(.streamFileCard(sessionId: "s1", filePath: "/tmp/index.html", fileType: "html", fileName: "index.html"))
    XCTAssertEqual(appState.streamingFileCards["s1"]?.count, 1)
}

func testSessionErrorClearsAccumulators() {
    appState.handleEvent(.streamImage(sessionId: "s1", imageData: "data", mediaType: "image/png", fileName: nil))
    appState.handleEvent(.streamFileCard(sessionId: "s1", filePath: "/tmp/f.html", fileType: "html", fileName: "f.html"))
    appState.handleEvent(.sessionError(sessionId: "s1", error: "boom"))
    XCTAssertNil(appState.streamingImages["s1"])
    XCTAssertNil(appState.streamingFileCards["s1"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — properties and event cases don't exist

- [ ] **Step 3: Add accumulators and event handling**

In `AppState.swift`, after line 24 (after `thinkingText`):

```swift
@Published var streamingImages: [String: [(data: String, mediaType: String)]] = [:]
@Published var streamingFileCards: [String: [(path: String, type: String, name: String)]] = [:]
```

In `handleEvent()`, add cases before the `default` (or after existing cases):

```swift
case .streamImage(let sessionId, let imageData, let mediaType, _):
    streamingImages[sessionId, default: []].append((data: imageData, mediaType: mediaType))

case .streamFileCard(let sessionId, let filePath, let fileType, let fileName):
    streamingFileCards[sessionId, default: []].append((path: filePath, type: fileType, name: fileName))
```

In the `.sessionError` case (around line 222), add cleanup:

```swift
streamingImages.removeValue(forKey: sessionId)
streamingFileCards.removeValue(forKey: sessionId)
```

- [ ] **Step 4: Run tests to verify they pass**

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ClaudPeer/App/AppState.swift ClaudPeerTests/AppStateEventTests.swift
git commit -m "feat: add streaming image and fileCard accumulators to AppState"
```

---

### Task 11: MessageAttachment — Add `localFilePath` Field

**Files:**
- Modify: `ClaudPeer/Models/MessageAttachment.swift`

- [ ] **Step 1: Add `localFilePath` property**

After line 9 (`var fileSize: Int`):

```swift
var localFilePath: String?
```

- [ ] **Step 2: Build to verify schema change compiles**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Note: SwiftData handles schema migration automatically for additive changes (new optional field).

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Models/MessageAttachment.swift
git commit -m "feat: add localFilePath to MessageAttachment for tool-generated files"
```

---

### Task 12: Message Finalization — Convert Images and FileCards to Attachments

**Files:**
- Modify: `ClaudPeer/Views/MainWindow/ChatView.swift:1389` (after `convo.messages.append(response)`)

- [ ] **Step 1: Add image finalization after line 1391**

After `GroupPromptBuilder.advanceWatermark(...)` and before `try? modelContext.save()`:

```swift
// Finalize accumulated images — AttachmentStore.save returns a MessageAttachment
if let images = appState.streamingImages[sidecarKey] {
    for img in images {
        guard let data = Data(base64Encoded: img.data) else { continue }
        let ext = img.mediaType.components(separatedBy: "/").last ?? "png"
        let name = "agent-image-\(UUID().uuidString.prefix(8)).\(ext)"
        let attachment = AttachmentStore.save(data: data, mediaType: img.mediaType, fileName: name)
        attachment.message = response
        modelContext.insert(attachment)
        response.attachments.append(attachment)
    }
    appState.streamingImages.removeValue(forKey: sidecarKey)
}

// Finalize accumulated file cards
if let cards = appState.streamingFileCards[sidecarKey] {
    for card in cards {
        let mediaType = card.type == "html" ? "text/html" : "application/pdf"
        let attachment = MessageAttachment(
            mediaType: mediaType,
            fileName: card.name,
            fileSize: 0,
            message: response
        )
        attachment.localFilePath = card.path
        modelContext.insert(attachment)
        response.attachments.append(attachment)
    }
    appState.streamingFileCards.removeValue(forKey: sidecarKey)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/MainWindow/ChatView.swift
git commit -m "feat: finalize streaming images and file cards into MessageAttachment records"
```

---

### Task 13: AttachmentThumbnail — File Card Rendering

**Files:**
- Modify: `ClaudPeer/Views/Components/AttachmentThumbnail.swift`

- [ ] **Step 1: Add file card variant for HTML/PDF with `localFilePath`**

In the `body` (line 8-24), add a third branch for file cards:

```swift
var body: some View {
    Group {
        if attachment.isImage {
            imageThumbnail
        } else if attachment.localFilePath != nil {
            fileCardThumbnail
        } else {
            documentThumbnail
        }
    }
    // ... existing modifiers
}
```

Add the file card view:

```swift
@ViewBuilder
private var fileCardThumbnail: some View {
    HStack(spacing: 8) {
        Image(systemName: attachment.mediaType == "text/html" ? "globe" : "doc.richtext")
            .font(.title2)
            .foregroundStyle(attachment.mediaType == "text/html" ? .blue : .red)
            .frame(width: 32)
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.fileName)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(attachment.mediaType == "text/html" ? "HTML" : "PDF")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "eye")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    .accessibilityIdentifier("messageBubble.fileCard.\(attachment.id.uuidString)")
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add ClaudPeer/Views/Components/AttachmentThumbnail.swift
git commit -m "feat: add file card rendering for HTML/PDF tool-generated attachments"
```

---

### Task 14: Doc Updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `TESTING.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to the wire protocol event list: `stream.image`, `stream.fileCard`.
Add `IncomingWireMessage` fields: `imageData`, `mediaType`, `filePath`, `fileType`.
Add new accessibility identifiers under `inspector.fileContent.*` prefix.
Add `messageBubble.fileCard.*` prefix.

- [ ] **Step 2: Update TESTING.md**

Add new test files to coverage table.
Add file preview controls to screen inventory.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md TESTING.md
git commit -m "docs: update CLAUDE.md and TESTING.md with new events and test coverage"
```

---

### Task 15: Integration Test — End-to-End Verification

- [ ] **Step 1: Build the full project**

Run: `xcodebuild -scheme ClaudPeer -destination 'platform=macOS' build 2>&1 | tail -5`

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -scheme ClaudPeer -destination 'platform=macOS' 2>&1 | grep -E 'Test Suite|Tests|PASS|FAIL' | tail -20`

- [ ] **Step 3: Manual verification checklist**

Launch the app and verify:
- [ ] HTML file → Preview tab shows rendered page (JS disabled)
- [ ] JSON file → Preview tab shows collapsible tree
- [ ] PDF file → Preview tab shows rendered pages
- [ ] Image file (PNG/JPG) → Preview tab shows image with dimensions
- [ ] SVG file → Preview tab renders via WebView
- [ ] Modified file → Diff tab shows syntax-highlighted diff
- [ ] Source tab still works for all text files
- [ ] Binary files (zip, exe) still show "Binary File" placeholder
- [ ] Mode picker shows correct tabs per file type

- [ ] **Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "fix: integration test fixes"
```
