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
        static let pageStyle = "pageStyle"
        static let paperSize = "paperSize"
        static let customPageWidth = "customPageWidth"
        static let customPageHeight = "customPageHeight"
        static let focusMode = "focusMode"
        static let typewriterMode = "typewriterMode"
        static let syncedScrolling = "syncedScrolling"
        static let whitePage = "whitePage"
        static let textScale = "textScale"
    }

    /// How the page looks: one page that grows, or separate pages with breaks between them.
    enum PageStyle: String, CaseIterable, Identifiable {
        case continuous, paper, square, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .continuous: "Continuous"
            case .paper: "Paper"
            case .square: "Square"
            case .custom: "Custom Size"
            }
        }
    }

    /// The paper for the Paper page style (and, later, PDF export).
    enum PaperSize: String, CaseIterable, Identifiable {
        case automatic, letter, a4
        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .letter: "Letter"
            case .a4: "A4"
            }
        }

        /// The size in points (72 to the inch). Automatic is Letter in the US and Canada, A4 elsewhere.
        var size: NSSize {
            switch self {
            case .letter: NSSize(width: 612, height: 792)
            case .a4: NSSize(width: 595, height: 842)
            case .automatic:
                ["US", "CA", "MX", "PH"].contains(Locale.current.region?.identifier ?? "") ? PaperSize.letter.size : PaperSize.a4.size
            }
        }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, sepia, dark, midnight
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        /// The Mac appearance the theme's controls use: light for Light and Sepia, dark for Dark and Midnight.
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light, .sepia: NSAppearance(named: .aqua)
            case .dark, .midnight: NSAppearance(named: .darkAqua)
            }
        }

        /// Whether White Page can apply (every theme but Light).
        var hasWhitePageOption: Bool { self != .light }
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
    static var pageStyle: PageStyle { value(Key.pageStyle, default: .continuous) }
    static var paperSize: PaperSize { value(Key.paperSize, default: .automatic) }

    /// The Custom Size page, in points. Defaults to 6 × 9 inches, a common book size.
    static var customPageSize: NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Key.customPageWidth)
        let height = defaults.double(forKey: Key.customPageHeight)
        return NSSize(width: width >= 144 ? width : 432, height: height >= 144 ? height : 648)
    }

    private static func value<Value: RawRepresentable>(_ key: String, default fallback: Value) -> Value where Value.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
    }

    /// How big the page's text is, from View → Bigger Text and Smaller Text (1 is normal).
    static var textScale: CGFloat {
        let scale = UserDefaults.standard.double(forKey: Key.textScale)
        return scale > 0 ? min(max(scale, 0.7), 2) : 1
    }

    /// The Mac's Increase Contrast setting, kept here so colors drawn on TextKit's threads can read it.
    nonisolated(unsafe) static var increaseContrast = false

    /// Keeps the page white (with the light page's text colors) in Sepia, Dark and Midnight.
    static var whitePage: Bool { UserDefaults.standard.bool(forKey: Key.whitePage) }

    /// Dims everything but the paragraph you're writing, and hides the toolbar.
    static var focusMode: Bool { UserDefaults.standard.bool(forKey: Key.focusMode) }
    /// Keeps the line you're typing in the middle of the window.
    static var typewriterMode: Bool { UserDefaults.standard.bool(forKey: Key.typewriterMode) }
    /// Panes side by side scroll together.
    static var syncedScrolling: Bool { UserDefaults.standard.bool(forKey: Key.syncedScrolling) }

    static func toggle(_ key: String) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    static func set<Value: RawRepresentable>(_ value: Value, for key: String) where Value.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}
