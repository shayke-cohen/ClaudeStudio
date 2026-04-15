import SwiftUI

// MARK: - xrayId (Release stub)

#if !DEBUG
extension View {
    /// No-op stub for Release builds — delegates to `.accessibilityIdentifier()`.
    /// In DEBUG builds the real implementation is provided by the AppXray SDK.
    func xrayId(_ id: String) -> some View {
        self.accessibilityIdentifier(id)
    }
}
#endif

// MARK: - stableXrayId

extension View {
    /// Assign an AppXray test-ID to a view, with reliable frame reporting on macOS.
    ///
    /// In DEBUG builds delegates to the AppXray SDK's `.xrayId()` which registers
    /// the view in `XrayViewRegistry` and attaches an invisible `NSView` frame
    /// reporter so `@testId("...")` selectors resolve correctly inside SwiftUI/AppKit
    /// hosting containers.
    ///
    /// In Release builds falls back to `.stableXrayId()` so VoiceOver and
    /// other accessibility tooling keeps working.
    @ViewBuilder
    func stableXrayId(_ id: String) -> some View {
        #if DEBUG
        self.xrayId(id)
        #else
        self.accessibilityIdentifier(id)
        #endif
    }
}

// MARK: - appXrayTapProxy

#if DEBUG
#if os(macOS)
import AppKit

private struct AppXrayTapProxy: NSViewRepresentable {
    let id: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> ProxyButton {
        let button = ProxyButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.invoke)
        button.isBordered = false
        button.title = ""
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.alphaValue = 0.01
        button.focusRingType = .none
        button.configure(id: id)
        return button
    }

    func updateNSView(_ nsView: ProxyButton, context: Context) {
        context.coordinator.action = action
        nsView.configure(id: id)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }

    final class ProxyButton: NSButton {
        override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()
        }
        func configure(id: String) {
            setAccessibilityIdentifier(id)
            setAccessibilityLabel(id)
            toolTip = id
        }
    }
}
#endif

extension View {
    func appXrayTapProxy(id: String, action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.background { AppXrayTapProxy(id: id, action: action) }
        #else
        self
        #endif
    }
}

#else

extension View {
    func appXrayTapProxy(id: String, action: @escaping () -> Void) -> some View { self }
}

#endif
