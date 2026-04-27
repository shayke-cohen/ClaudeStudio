import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var desiredHeight: CGFloat
    var onImagePaste: (Data, String) -> Void
    var onSubmit: () -> Void
    /// When plain Return should submit (Shift+Return always inserts a newline).
    var canSubmitOnReturn: () -> Bool = { true }
    /// Called for ↑ (−1), ↓ (+1), Esc (0). Return true to consume the event.
    var onNavigationKey: ((Int) -> Bool)? = nil
    /// Bumped by the parent (e.g. via `⌘L`) to programmatically grab keyboard
    /// focus on the underlying NSTextView. SwiftUI's `@FocusState` doesn't
    /// reach into `NSViewRepresentable`, so we reconcile via this counter
    /// in `updateNSView`. Pass the same value every render and only change
    /// it when you actually want to request focus.
    var focusRequestTick: Int = 0
    @Environment(\.appTextScale) private var appTextScale

    private static let baseLineHeight: CGFloat = 17
    static let minLines: CGFloat = 2
    static let maxLines: CGFloat = 10
    static var minHeight: CGFloat { baseLineHeight * minLines }
    static var maxHeight: CGFloat { baseLineHeight * maxLines }

    private var fontSize: CGFloat {
        NSFont.systemFontSize * appTextScale
    }

    private var scaledMinHeight: CGFloat {
        Self.baseLineHeight * appTextScale * Self.minLines
    }

    private var scaledMaxHeight: CGFloat {
        Self.baseLineHeight * appTextScale * Self.maxLines
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ImagePasteTextView()
        textView.onImagePaste = onImagePaste
        textView.onSubmit = onSubmit
        textView.canSubmitOnReturn = canSubmitOnReturn
        textView.onNavigationKey = onNavigationKey
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: fontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.setAccessibilityIdentifier("pasteableTextField.input")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Set up placeholder
        context.coordinator.textView = textView
        context.coordinator.updatePlaceholder()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.font = .systemFont(ofSize: fontSize)
        if let imagePasteTextView = textView as? ImagePasteTextView {
            imagePasteTextView.onSubmit = onSubmit
            imagePasteTextView.canSubmitOnReturn = canSubmitOnReturn
            imagePasteTextView.onNavigationKey = onNavigationKey
        }
        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight(textView)
        }
        context.coordinator.recalcHeight(textView)
        context.coordinator.updatePlaceholder()
        // Apply a focus request only when the tick advances. Using `!=`
        // rather than `>` so a wraparound doesn't strand the field.
        if context.coordinator.lastFocusTick != focusRequestTick {
            context.coordinator.lastFocusTick = focusRequestTick
            DispatchQueue.main.async {
                guard let window = textView.window else { return }
                window.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField
        weak var textView: NSTextView?
        /// Tracks the last `focusRequestTick` we acted on so a re-render with
        /// the same value doesn't re-grab focus on every body update.
        var lastFocusTick: Int = 0

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight(textView)
            updatePlaceholder()
        }

        @MainActor
        func recalcHeight(_ textView: NSTextView) {
            guard let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let inset = textView.textContainerInset
            let newHeight = usedRect.height + inset.height * 2
            let clamped = min(parent.scaledMaxHeight, max(parent.scaledMinHeight, newHeight))
            if abs(parent.desiredHeight - clamped) > 0.5 {
                let binding = parent.$desiredHeight
                DispatchQueue.main.async {
                    binding.wrappedValue = clamped
                }
            }
        }

        @MainActor
        func updatePlaceholder() {
            guard let textView = textView else { return }
            // Remove existing placeholder layer
            textView.layer?.sublayers?.removeAll { $0.name == "placeholder" }

            if textView.string.isEmpty {
                textView.wantsLayer = true
                let placeholder = CATextLayer()
                placeholder.name = "placeholder"
                placeholder.string = "Message… (↩ send, ⇧↩ newline)"
                placeholder.font = NSFont.systemFont(ofSize: parent.fontSize)
                placeholder.fontSize = parent.fontSize
                placeholder.foregroundColor = NSColor.placeholderTextColor.cgColor
                placeholder.contentsScale = textView.window?.backingScaleFactor ?? 2.0
                let inset = textView.textContainerInset
                let originX = inset.width + (textView.textContainer?.lineFragmentPadding ?? 5)
                placeholder.frame = CGRect(
                    x: originX,
                    y: inset.height,
                    width: textView.bounds.width - originX * 2,
                    height: max(20, parent.fontSize * 1.5)
                )
                textView.layer?.addSublayer(placeholder)
            }
        }
    }
}

private class ImagePasteTextView: NSTextView {
    var onImagePaste: ((Data, String) -> Void)?
    var onSubmit: (() -> Void)?
    var canSubmitOnReturn: (() -> Bool)?
    /// Called for ↑ (−1), ↓ (+1), Esc (0). Return true to consume the event.
    var onNavigationKey: ((Int) -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Arrow/Esc handling for slash typeahead
        if let handler = onNavigationKey {
            switch event.keyCode {
            case 126: // ↑
                if handler(-1) { return }
            case 125: // ↓
                if handler(1) { return }
            case 53:  // Esc
                if handler(0) { return }
            default: break
            }
        }

        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        if isReturnKey {
            if hasMarkedText() {
                super.keyDown(with: event)
                return
            }

            let flags = event.modifierFlags.intersection([.shift, .command])
            if flags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
                return
            }

            if flags.contains(.command) || (canSubmitOnReturn?() ?? true) {
                onSubmit?()
                return
            }
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            if pasteImageFromPasteboard() {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteImageFromPasteboard() -> Bool {
        let pb = NSPasteboard.general
        let imageTypes: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "image/png"),
            (.tiff, "image/png"),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "image/jpeg"),
            (NSPasteboard.PasteboardType(UTType.gif.identifier), "image/gif"),
        ]

        for (pbType, mediaType) in imageTypes {
            if let data = pb.data(forType: pbType) {
                let finalData: Data
                let finalMediaType: String
                if pbType == .tiff, let rep = NSBitmapImageRep(data: data),
                   let pngData = rep.representation(using: .png, properties: [:]) {
                    finalData = pngData
                    finalMediaType = "image/png"
                } else {
                    finalData = data
                    finalMediaType = mediaType
                }
                onImagePaste?(finalData, finalMediaType)
                return true
            }
        }
        return false
    }
}
