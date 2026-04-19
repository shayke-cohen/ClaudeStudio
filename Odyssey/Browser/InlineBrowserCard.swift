import SwiftUI
import WebKit

/// Inline browser card in the message stream.
/// Active sessions show the live WKWebView at a fixed height with a toolbar
/// offering "Open in Safari" and "Open in Panel" actions.
/// Ended sessions collapse to a compact status row.
struct InlineBrowserCard: View {
    let message: ConversationMessage
    @Environment(AppState.self) private var appState

    @State private var displayURL: String = ""

    private var sessionId: String? { message.toolOutput }

    private var isActive: Bool {
        guard let sid = sessionId else { return false }
        return appState.activeBrowserSessionId == sid
    }

    private var controller: WKWebViewBrowserController? {
        guard let sid = sessionId else { return nil }
        return appState.browserControllers[sid]
    }

    private var coordinator: BrowserOverlayCoordinator? {
        guard let sid = sessionId else { return nil }
        return appState.browserCoordinators[sid]
    }

    // MARK: - Body

    var body: some View {
        if isActive {
            activeBrowser
        } else {
            endedCard
        }
    }

    // MARK: - Active inline browser

    private var activeBrowser: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let ctrl = controller {
                BrowserWebViewRepresentable(controller: ctrl)
                    .frame(height: 380)
                    .accessibilityIdentifier("inlineBrowser.webView")
            } else {
                Color(.windowBackgroundColor)
                    .frame(height: 380)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            displayURL = controller?.currentURL?.absoluteString ?? ""
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .default).autoconnect()) { _ in
            displayURL = controller?.currentURL?.absoluteString ?? ""
        }
        .accessibilityIdentifier("inlineBrowser.card")
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            stateIndicator

            Text(displayURL.isEmpty ? "about:blank" : displayURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let urlStr = controller?.currentURL?.absoluteString ?? (displayURL.isEmpty ? nil : displayURL),
                   let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in Safari")
            .accessibilityIdentifier("inlineBrowser.safariButton")
            .accessibilityLabel("Open in Safari")

            Button {
                appState.activeBrowserPanelVisible = true
            } label: {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(appState.activeBrowserPanelVisible ? .blue : .secondary)
            .help("Open in panel")
            .accessibilityIdentifier("inlineBrowser.expandButton")
            .accessibilityLabel("Open in panel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - State indicator dot

    @ViewBuilder
    private var stateIndicator: some View {
        let color: Color = {
            switch coordinator?.state {
            case .agentDriving: return .green
            case .yieldedToUser: return .orange
            case .userDriving: return .blue
            case nil: return .secondary
            }
        }()
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    // MARK: - Ended card

    private var endedCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Text("Browser session ended")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "xmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .accessibilityIdentifier("inlineBrowser.card")
    }
}
