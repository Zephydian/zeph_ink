import AppKit

/// Zeph#Ink's settings, stored in the user defaults. The Settings window edits them with
/// `@AppStorage` under these keys; the rest of the app reads them here and listens for
/// `UserDefaults.didChangeNotification` to follow changes live.
nonisolated enum Preferences {
    enum Key {
        static let theme = "theme"
        static let accent = "accentColor"
        static let margins = "margins"
        static let defaultType = "defaultDocumentType"
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    /// The accent: the Mac's own accent color by default, or a fixed one.
    enum Accent: String, CaseIterable, Identifiable {
        case system, ink, blue, purple, pink, red, orange, green, graphite
        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .ink: "Zephydian Ink"
            default: rawValue.capitalized
            }
        }

        var color: NSColor {
            switch self {
            case .system: .controlAccentColor
            case .ink: NSColor(named: "AccentColor") ?? .systemBlue
            case .blue: .systemBlue
            case .purple: .systemPurple
            case .pink: .systemPink
            case .red: .systemRed
            case .orange: .systemOrange
            case .green: .systemGreen
            case .graphite: .systemGray
            }
        }
    }

    /// The page's side padding, and with it the line length.
    enum Margins: String, CaseIterable, Identifiable {
        case narrow, normal, wide
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        var padding: CGFloat {
            switch self {
            case .narrow: 36
            case .normal: 72
            case .wide: 120
            }
        }
    }

    enum DocumentType: String, CaseIterable, Identifiable {
        case markdown, plainText
        var id: String { rawValue }
        var title: String { self == .markdown ? "Markdown (.md)" : "Plain text (.txt)" }
    }

    static var theme: Theme { value(Key.theme, default: .system) }
    static var accent: Accent { value(Key.accent, default: .system) }
    static var margins: Margins { value(Key.margins, default: .normal) }
    static var defaultType: DocumentType { value(Key.defaultType, default: .markdown) }

    private static func value<Value: RawRepresentable>(_ key: String, default fallback: Value) -> Value where Value.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
    }

    static func set<Value: RawRepresentable>(_ value: Value, for key: String) where Value.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}
