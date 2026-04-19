import SwiftUI
import WebKit

/// The browser side panel: URL bar, handoff control bar, embedded WKWebView, and action log.
@MainActor
struct BrowserPanelView: View {
    let sessionId: String
    @Environment(AppState.self) private var appState

    // MARK: - Computed helpers

    private var controller: WKWebViewBrowserController? {
        appState.browserControllers[sessionId]
    }

    private var coordinator: BrowserOverlayCoordinator? {
        appState.browserCoordinators[sessionId]
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            controlBar
            Divider()
            HStack(spacing: 0) {
                if let ctrl = controller {
                    BrowserWebViewRepresentable(controller: ctrl)
                        .accessibilityIdentifier("browserPanel.webView")
                } else {
                    emptyState
                }
                if let coord = coordinator, !coord.actionLog.isEmpty {
                    Divider()
                    actionLogView(coordinator: coord)
                        .frame(width: 200)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("browserPanel.container")
    }

    // MARK: - URL bar

    /// Shows the current URL. Read-only display — the agent drives navigation.
    private var urlBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.caption)
            let urlString = controller?.currentURL?.absoluteString ?? ""
            let displayURL = urlString.isEmpty ? "about:blank" : urlString
            let isDriving = coordinator?.state == .userDriving
            Text(displayURL)
                .font(.caption)
                .foregroundStyle(isDriving ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityIdentifier("browserPanel.urlBar")
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            stateIndicator
            stateLabel
            Spacer()
            controlButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(controlBarBackground)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        let (color, symbol) = stateAppearance
        Image(systemName: symbol)
            .foregroundStyle(color)
            .font(.caption)
            .accessibilityIdentifier("browserPanel.stateIndicator")
    }

    @ViewBuilder
    private var stateLabel: some View {
        let label: String = {
            guard let coord = coordinator else { return "No session" }
            switch coord.state {
            case .agentDriving:
                return "Agent driving"
            case .yieldedToUser(let msg):
                return msg.isEmpty ? "Waiting for you" : msg
            case .userDriving:
                return "You're driving"
            }
        }()
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var stateAppearance: (Color, String) {
        guard let coord = coordinator else { return (.gray, "circle") }
        switch coord.state {
        case .agentDriving:    return (.green, "circle.fill")
        case .yieldedToUser:   return (.orange, "circle.lefthalf.filled")
        case .userDriving:     return (.blue, "circle.fill")
        }
    }

    private var controlBarBackground: Color {
        guard let coord = coordinator else { return .clear }
        switch coord.state {
        case .agentDriving:   return .green.opacity(0.06)
        case .yieldedToUser:  return .orange.opacity(0.08)
        case .userDriving:    return .blue.opacity(0.06)
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        if let coord = coordinator {
            switch coord.state {
            case .agentDriving:
                Button("Take over") {
                    _ = coord.userTookOver()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("browserPanel.takeOverButton")

            case .yieldedToUser:
                Button("Resume") {
                    if let ctrl = controller {
                        _ = coord.userResumed(controller: ctrl)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("browserPanel.resumeButton")

                Button("Take over") {
                    _ = coord.userTookOver()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("browserPanel.takeOverButton")

            case .userDriving:
                Button("Resume agent") {
                    coord.agentTookControl()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("browserPanel.resumeButton")
            }
        }
    }

    // MARK: - Action log sidebar

    private func actionLogView(coordinator: BrowserOverlayCoordinator) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(coordinator.actionLog) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.formattedTime)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(entry.action)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("browserPanel.actionLog")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No active browser session")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
