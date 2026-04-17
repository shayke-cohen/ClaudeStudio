import SwiftUI
import AppKit

extension Color {
    static func fromAgentColor(_ name: String) -> Color {
        switch name {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        case "pink":   return .pink
        case "teal":   return .teal
        case "indigo": return .indigo
        case "gray":   return .gray
        default:       return .accentColor
        }
    }

    /// Returns this color with brightness reduced by `fraction` (0–1).
    /// Used to compute gradient end-stops for the hero header.
    func darkened(by fraction: Double = 0.25) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return self }
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(brightness) * (1.0 - fraction),
            opacity: Double(alpha)
        )
    }
}
