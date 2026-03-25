import SwiftUI

struct WorkshopEntityRow: View {
    let icon: String
    let color: String
    let name: String
    let subtitle: String
    let isEnabled: Bool
    let badges: [String]
    var entityId: String = ""
    var onToggleEnabled: (() -> Void)?
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.fromAgentColor(color))
                    .frame(width: 28, height: 28)
                    .background(Color.fromAgentColor(color).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if !isEnabled {
                            Text("disabled")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let toggle = onToggleEnabled {
                    Button {
                        toggle()
                    } label: {
                        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isEnabled ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isEnabled ? "Disable" : "Enable")
                    .xrayId("workshop.toggleEnabled.\(entityId)")
                }

                HStack(spacing: 6) {
                    ForEach(badges.filter { !$0.isEmpty }, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1.0 : 0.55)
    }
}
