import SwiftUI
import AppKit
import Highlightr

struct HighlightedCodeView: NSViewRepresentable {
    let code: String
    var language: String?
    var showLineNumbers: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        applyHighlighting(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        guard let textView = coord.textView else { return }

        let isDark = colorScheme == .dark
        if code == coord.lastCode && language == coord.lastLanguage
            && showLineNumbers == coord.lastShowLineNumbers && isDark == coord.lastIsDark {
            return
        }

        applyHighlighting(to: textView, coordinator: coord)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyHighlighting(to textView: NSTextView, coordinator: Coordinator) {
        let isDark = colorScheme == .dark
        let highlightr = coordinator.highlightr
        let themeName = isDark ? "github-dark" : "github"
        highlightr.setTheme(to: themeName)
        highlightr.theme.codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let lang = language?.lowercased()
        let attributed = highlightr.highlight(code, as: lang) ?? NSAttributedString(string: code)

        if showLineNumbers {
            let numbered = addLineNumbers(to: attributed)
            textView.textStorage?.setAttributedString(numbered)
        } else {
            textView.textStorage?.setAttributedString(attributed)
        }

        coordinator.lastCode = code
        coordinator.lastLanguage = language
        coordinator.lastShowLineNumbers = showLineNumbers
        coordinator.lastIsDark = isDark
    }

    private func addLineNumbers(to text: NSAttributedString) -> NSAttributedString {
        let fullString = text.string
        let lines = fullString.components(separatedBy: "\n")
        let digitCount = max(String(lines.count).count, 2)
        let result = NSMutableAttributedString()

        let gutterAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.separatorColor
        ]

        var charIndex = 0
        for (i, line) in lines.enumerated() {
            let lineNum = String(i + 1).padding(toLength: digitCount, withPad: " ", startingAt: 0)
            result.append(NSAttributedString(string: " \(lineNum)", attributes: gutterAttrs))
            result.append(NSAttributedString(string: " │ ", attributes: separatorAttrs))

            let lineLength = line.utf16.count
            let nsRange = NSRange(location: charIndex, length: min(lineLength, max(0, text.length - charIndex)))
            if nsRange.length > 0 {
                result.append(text.attributedSubstring(from: nsRange))
            }

            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
                charIndex += lineLength + 1
            }
        }

        return result
    }

    final class Coordinator {
        let highlightr: Highlightr = Highlightr()!
        var textView: NSTextView?
        var lastCode: String?
        var lastLanguage: String?
        var lastShowLineNumbers: Bool?
        var lastIsDark: Bool?
    }
}
