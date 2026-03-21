import SwiftUI

enum TubeColor: String, CaseIterable, Identifiable {
    case blue
    case cyan
    case green
    case orange
    case purple
    case rainbow

    var id: String { rawValue }

    /// Returns the primary, secondary, and glow colors for a tube digit.
    /// The `digitIndex` parameter allows rainbow mode to vary color per digit.
    func colors(for digitIndex: Int) -> (primary: Color, secondary: Color, glow: Color) {
        switch self {
        case .blue:
            return (
                primary: Color(red: 0.3, green: 0.6, blue: 1.0),
                secondary: Color(red: 0.2, green: 0.4, blue: 0.8),
                glow: Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.6)
            )
        case .cyan:
            return (
                primary: Color(red: 0.0, green: 0.9, blue: 0.9),
                secondary: Color(red: 0.0, green: 0.6, blue: 0.7),
                glow: Color(red: 0.0, green: 0.9, blue: 0.9).opacity(0.6)
            )
        case .green:
            return (
                primary: Color(red: 0.2, green: 1.0, blue: 0.3),
                secondary: Color(red: 0.1, green: 0.7, blue: 0.2),
                glow: Color(red: 0.2, green: 1.0, blue: 0.3).opacity(0.6)
            )
        case .orange:
            return (
                primary: Color(red: 1.0, green: 0.6, blue: 0.1),
                secondary: Color(red: 0.8, green: 0.4, blue: 0.0),
                glow: Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.6)
            )
        case .purple:
            return (
                primary: Color(red: 0.7, green: 0.3, blue: 1.0),
                secondary: Color(red: 0.5, green: 0.2, blue: 0.8),
                glow: Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.6)
            )
        case .rainbow:
            let hue = Double(digitIndex) / 8.0
            let primary = Color(hue: hue, saturation: 0.9, brightness: 1.0)
            let secondary = Color(hue: hue, saturation: 0.8, brightness: 0.7)
            let glow = Color(hue: hue, saturation: 0.9, brightness: 1.0).opacity(0.6)
            return (primary: primary, secondary: secondary, glow: glow)
        }
    }
}
