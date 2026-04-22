import SwiftUI
import AppKit

/// Transparent NSView overlay that fires callbacks on mouse down/up.
/// SwiftUI's onLongPressGesture doesn't fire for static holds on macOS
/// (it requires mouse movement), so we drop down to AppKit directly.
///
/// Usage: `.overlay(HoldDetector(onPress: { ... }, onRelease: { ... }))`
struct HoldDetector: NSViewRepresentable {
    var isEnabled: Bool = true
    var onPress: () -> Void
    var onRelease: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onPress: onPress, onRelease: onRelease)
    }

    func makeNSView(context: Context) -> HoldNSView {
        let v = HoldNSView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: HoldNSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPress = onPress
        context.coordinator.onRelease = onRelease
    }

    final class Coordinator {
        var isEnabled: Bool
        var onPress: () -> Void
        var onRelease: () -> Void

        init(isEnabled: Bool, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onPress = onPress
            self.onRelease = onRelease
        }
    }

    final class HoldNSView: NSView {
        weak var coordinator: Coordinator?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard coordinator?.isEnabled == true else { return }
            let cb = coordinator?.onPress
            Task { @MainActor in cb?() }
        }

        override func mouseUp(with event: NSEvent) {
            let cb = coordinator?.onRelease
            Task { @MainActor in cb?() }
        }
    }
}
