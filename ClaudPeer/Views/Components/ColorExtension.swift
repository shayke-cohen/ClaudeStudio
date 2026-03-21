import SwiftUI

extension Color {
    static func fromAgentColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "gray": return .gray
        default: return .accentColor
        }
    }
}
