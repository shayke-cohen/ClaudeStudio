import SwiftUI

struct StreamingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { animating = true }
        .accessibilityIdentifier("streamingIndicator")
        .accessibilityLabel("Loading")
        .accessibilityElement(children: .ignore)
    }
}
