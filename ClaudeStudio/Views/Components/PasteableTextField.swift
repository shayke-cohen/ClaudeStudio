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

    private static let lineHeight: CGFloat = 17
    static let minLines: CGFloat = 2
    static let maxLines: CGFloat = 10
    static var minHeight: CGFloat { lineHeight * minLines }
    static var maxHeight: CGFloat { lineHeight * maxLines }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ImagePasteTextView()
        textView.onImagePaste = onImagePaste
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
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
        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight(textView)
            context.coordinator.updatePlaceholder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteableTextField
        weak var textView: NSTextView?

        init(_ parent: PasteableTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight(textView)
            updatePlaceholder()
        }

        func recalcHeight(_ textView: NSTextView) {
            guard let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let inset = textView.textContainerInset
            let newHeight = usedRect.height + inset.height * 2
            let clamped = min(PasteableTextField.maxHeight, max(PasteableTextField.minHeight, newHeight))
            if abs(parent.desiredHeight - clamped) > 0.5 {
                let binding = parent.$desiredHeight
                DispatchQueue.main.async {
                    binding.wrappedValue = clamped
                }
            }
        }

        func updatePlaceholder() {
            guard let textView = textView else { return }
            // Remove existing placeholder layer
            textView.layer?.sublayers?.removeAll { $0.name == "placeholder" }

            if textView.string.isEmpty {
                textView.wantsLayer = true
                let placeholder = CATextLayer()
                placeholder.name = "placeholder"
                placeholder.string = "Message… (↩ send, ⇧↩ newline)"
                placeholder.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                placeholder.fontSize = NSFont.systemFontSize
                placeholder.foregroundColor = NSColor.placeholderTextColor.cgColor
                placeholder.contentsScale = textView.window?.backingScaleFactor ?? 2.0
                let inset = textView.textContainerInset
                let originX = inset.width + (textView.textContainer?.lineFragmentPadding ?? 5)
                placeholder.frame = CGRect(x: originX, y: inset.height, width: textView.bounds.width - originX * 2, height: 20)
                textView.layer?.addSublayer(placeholder)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                if flags.contains(.command) {
                    parent.onSubmit()
                    return true
                }
                if parent.canSubmitOnReturn() {
                    parent.onSubmit()
                    return true
                }
                return false
            }
            return false
        }
    }
}

private class ImagePasteTextView: NSTextView {
    var onImagePaste: ((Data, String) -> Void)?

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
