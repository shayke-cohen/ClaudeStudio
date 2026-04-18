import SwiftUI

struct SymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? SymbolPickerView.catalog
            : SymbolPickerView.catalog.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search symbols…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .accessibilityIdentifier("symbolPicker.searchField")

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 6), spacing: 4) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selectedSymbol = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(selectedSymbol == name ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedSymbol == name ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("symbolPicker.symbol.\(name)")
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 256, height: 320)
    }

    static let catalog: [String] = [
        // Dev actions
        "wrench.and.screwdriver.fill", "hammer.fill", "terminal.fill", "flask.fill",
        "play.fill", "stop.fill", "forward.fill", "backward.fill",
        "arrow.uturn.backward", "arrow.clockwise", "arrow.2.circlepath",
        "paperplane.fill", "checkmark.seal.fill", "bolt.fill",
        "gear", "gearshape.fill", "gearshape.2", "slider.horizontal.3",
        // Files
        "doc.fill", "doc.text.fill", "folder.fill", "folder.badge.plus",
        "archivebox.fill", "tray.fill", "externaldrive.fill",
        "arrow.down.circle.fill", "arrow.up.circle.fill",
        "square.and.arrow.up.fill", "square.and.arrow.down.fill",
        // Code
        "chevron.left.forwardslash.chevron.right", "curlybraces",
        "function", "number", "rectangle.and.pencil.and.ellipsis",
        // Communication
        "message.fill", "bubble.left.fill", "bubble.right.fill",
        "envelope.fill", "bell.fill", "megaphone.fill",
        "link", "link.badge.plus",
        // Visual
        "eye.fill", "paintpalette.fill", "paintbrush.fill",
        "photo.fill", "camera.fill", "video.fill",
        "display", "macwindow", "rectangle.on.rectangle", "square.split.2x1",
        // Status
        "star.fill", "heart.fill", "checkmark.circle.fill", "xmark.circle.fill",
        "exclamationmark.triangle.fill", "info.circle.fill",
        "questionmark.circle.fill", "clock.fill", "timer", "stopwatch.fill",
        // Navigation & misc
        "house.fill", "magnifyingglass", "scope", "map.fill",
        "location.fill", "pin.fill", "tag.fill", "bookmark.fill",
        "list.bullet", "square.grid.2x2.fill", "chart.bar.fill", "waveform",
        "cpu.fill", "memorychip.fill", "network",
        "antenna.radiowaves.left.and.right",
        "lock.fill", "key.fill",
        "person.fill", "person.2.fill",
        "text.quote", "textformat", "sparkles", "wand.and.stars",
        "lightbulb.fill", "hand.tap.fill", "hand.raised.fill",
        "scissors", "trash.fill", "plus.circle.fill", "minus.circle.fill",
        "ellipsis.circle.fill", "return", "globe",
    ]
}
