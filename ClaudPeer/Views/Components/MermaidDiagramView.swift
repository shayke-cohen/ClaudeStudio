import SwiftUI
import WebKit

/// Renders a Mermaid diagram source string as a visual diagram via WKWebView + mermaid.js.
struct MermaidDiagramView: NSViewRepresentable {
    let source: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("mermaidDiagram.webView")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        <style>
            body {
                margin: 0;
                padding: 8px;
                background: transparent;
                display: flex;
                justify-content: center;
                align-items: flex-start;
            }
            .mermaid {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            .mermaid svg {
                max-width: 100%;
                height: auto;
            }
            .error-msg {
                color: #ff6b6b;
                font-family: -apple-system, sans-serif;
                font-size: 12px;
                padding: 8px;
            }
        </style>
        </head>
        <body>
        <div class="mermaid" id="diagram">
        \(escaped)
        </div>
        <script>
            mermaid.initialize({
                startOnLoad: true,
                theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
                securityLevel: 'strict',
                fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
                fontSize: 13
            });
        </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}
