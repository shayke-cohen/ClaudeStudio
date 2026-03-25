import SwiftUI
import WebKit

/// Sandboxed WKWebView for rendering HTML content inline in chat messages.
struct InlineHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let maxHeight: CGFloat

    init(html: String, baseURL: URL? = nil, maxHeight: CGFloat = 400) {
        self.html = html
        self.baseURL = baseURL
        self.maxHeight = maxHeight
    }

    /// Load HTML from a local file path.
    init(filePath: String, maxHeight: CGFloat = 400) {
        let url = URL(fileURLWithPath: filePath)
        self.html = (try? String(contentsOf: url, encoding: .utf8)) ?? "<p>Failed to load file</p>"
        self.baseURL = url.deletingLastPathComponent()
        self.maxHeight = maxHeight
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Sandbox: disable JavaScript by default for security
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // No persistent data
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("inlineHTML.webView")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrapped = wrapInDocument(html)
        webView.loadHTMLString(wrapped, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Wrap raw HTML in a minimal document with dark-mode-aware styling.
    private func wrapInDocument(_ content: String) -> String {
        // If content already has <html> or <body>, use as-is
        if content.lowercased().contains("<html") || content.lowercased().contains("<!doctype") {
            return content
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                margin: 8px;
                color: #e0e0e0;
                background: transparent;
            }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
            }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 10px; text-align: left; }
            th { font-weight: 600; }
            img { max-width: 100%; border-radius: 6px; }
            pre { background: rgba(128,128,128,0.1); padding: 8px; border-radius: 6px; overflow-x: auto; }
            code { font-family: ui-monospace, monospace; font-size: 12px; }
        </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        /// Block navigation to external URLs.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other {
                return .allow // Allow initial load
            }
            return .cancel // Block all navigation
        }
    }
}

/// Container that wraps InlineHTMLView with a card-like appearance.
struct InlineHTMLCard: View {
    let title: String?
    let html: String
    let filePath: String?
    let maxHeight: CGFloat

    @State private var isExpanded = true

    init(title: String? = nil, html: String = "", filePath: String? = nil, maxHeight: CGFloat = 400) {
        self.title = title
        self.html = html
        self.filePath = filePath
        self.maxHeight = maxHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.3)
                if let filePath {
                    InlineHTMLView(filePath: filePath, maxHeight: maxHeight)
                        .frame(height: min(maxHeight, 400))
                } else {
                    InlineHTMLView(html: html, maxHeight: maxHeight)
                        .frame(height: min(maxHeight, 400))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .xrayId("inlineHTMLCard.container")
    }

    @ViewBuilder
    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
                    .font(.caption)

                Text(title ?? fileName ?? "HTML Content")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Color(.textBackgroundColor).opacity(0.4))
        .xrayId("inlineHTMLCard.header")
    }

    private var fileName: String? {
        guard let path = filePath else { return nil }
        return (path as NSString).lastPathComponent
    }
}
