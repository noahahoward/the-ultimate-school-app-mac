import SwiftUI

/// Locker's visual vocabulary.
///
/// The app leans on native materials for chrome and spends its color on two
/// things only: the class you're looking at, and what needs attention right now.
enum Theme {

    // MARK: - Color

    /// The "now" marker, the streak, the thing your eye should land on. Borrowed
    /// from the highlighter every student already owns.
    static let highlighter = Color(hex: "FFD84D")
    static let highlighterDeep = Color(hex: "E8B923")
    static let accent = Color(hex: "2F6FED")
    static let overdue = Color(hex: "E5484D")
    static let done = Color(hex: "3BA55D")

    static func classColor(_ hex: String) -> Color { Color(hex: hex) }

    // MARK: - Type

    /// Rounded numerals for the human-scale numbers: counts, streaks, timers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Monospaced, tabular figures for anything that should line up in a column:
    /// clock times on the spine, percentages in the grade table.
    static func data(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let eyebrow = Font.system(size: 11, weight: .semibold).width(.expanded)

    // MARK: - Metrics

    static let corner: CGFloat = 10
    static let cardCorner: CGFloat = 14
    static let gutter: CGFloat = 20
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Hex string for persisting a picked color.
    var hexString: String {
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((native.redComponent * 255).rounded())
        let g = Int((native.greenComponent * 255).rounded())
        let b = Int((native.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
