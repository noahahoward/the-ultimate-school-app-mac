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
    /// Set from settings at launch and whenever it is changed. A stored
    /// property rather than an environment value because the theme is read from
    /// plain functions all over the app, not only from inside a view body.
    static var accentHex = Accent.default.hex
    static var accent: Color { Color(hex: accentHex) }

    /// The accents on offer. Named, because "Grape" is easier to pick than a
    /// hex code and this is the part people change first. Fifteen of them, so
    /// they and the custom well fill their rows exactly.
    enum Accent: String, CaseIterable, Identifiable, Sendable {
        case blue, indigo, grape, plum, rose
        case red, sunset, amber, gold, lime
        case forest, teal, cyan, slate, ink

        static let `default` = Accent.blue
        var id: String { rawValue }

        var hex: String {
            switch self {
            case .blue: "2F6FED"
            case .indigo: "4F46E5"
            case .grape: "8B5CF6"
            case .plum: "A21CAF"
            case .rose: "E8437E"
            case .red: "E5484D"
            case .sunset: "F2751A"
            case .amber: "F59E0B"
            case .gold: "D9A215"
            case .lime: "65A30D"
            case .forest: "2E9E5B"
            case .teal: "17A2B8"
            case .cyan: "0EA5E9"
            case .slate: "64748B"
            case .ink: "3F4A5A"
            }
        }

        var label: String {
            switch self {
            case .blue: "Blue"
            case .indigo: "Indigo"
            case .grape: "Grape"
            case .plum: "Plum"
            case .rose: "Rose"
            case .red: "Red"
            case .sunset: "Sunset"
            case .amber: "Amber"
            case .gold: "Gold"
            case .lime: "Lime"
            case .forest: "Forest"
            case .teal: "Teal"
            case .cyan: "Cyan"
            case .slate: "Slate"
            case .ink: "Ink"
            }
        }
    }

    /// How the headings and the big numbers are cut.
    enum TypeStyle: String, CaseIterable, Identifiable, Sendable {
        case rounded, plain, serif

        static let `default` = TypeStyle.rounded
        var id: String { rawValue }

        var design: Font.Design {
            switch self {
            case .rounded: .rounded
            case .plain: .default
            case .serif: .serif
            }
        }

        var label: String {
            switch self {
            case .rounded: "Rounded"
            case .plain: "Plain"
            case .serif: "Serif"
            }
        }
    }

    static var typeStyle = TypeStyle.default
    static let overdue = Color(hex: "E5484D")
    static let done = Color(hex: "3BA55D")

    static func classColor(_ hex: String) -> Color { Color(hex: hex) }

    // MARK: - Type

    /// Rounded numerals for the human-scale numbers: counts, streaks, timers.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: typeStyle.design)
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
