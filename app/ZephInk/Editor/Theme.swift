import AppKit

/// Colors, type and spacing. Every color is a light/dark pair in `Assets.xcassets`.
nonisolated enum Theme {
    // MARK: Colors

    /// The title bar, tab bar, toolbar and status bar.
    static let chrome = named("Chrome")
    /// Behind the page.
    static let desk = named("Desk")
    static let page = named("Page")
    static let ink = named("Ink")
    static let inkSecondary = named("InkSecondary")
    /// Markdown symbols when they're shown faded.
    static let marker = named("Marker")
    static let line = named("Line")
    static let hover = named("Hover")
    static let codeBackground = named("CodeBackground")
    /// Behind `==highlighted==` text, like a marker pen.
    static let highlight = named("Highlight")
    /// Zephydian Ink, the fixed accent.
    static let accent = named("AccentColor")
    static let accentSoft = named("AccentSoft")

    /// Colors load by name rather than through Xcode's generated symbols, which only the main thread
    /// may use: the page also draws on TextKit's own threads.
    private static func named(_ name: String) -> NSColor {
        NSColor(named: name) ?? .textColor
    }

    // MARK: Type

    /// The page's body text size. Everything else on the page is sized from it.
    static let bodySize: CGFloat = 17
    /// Line height as a multiple of the font size.
    static let bodyLineHeight: CGFloat = 1.68
    /// Source view and code: the size and line height of JetBrains Mono.
    static let sourceSize: CGFloat = 14
    static let sourceLineHeight: CGFloat = 1.75

    // MARK: Spacing

    /// Leaves room for the window's close, minimize and zoom buttons before the first tab.
    static let trafficLightsWidth: CGFloat = 78
    /// The page's widest size, and the desk around it.
    static let pageMaxWidth: CGFloat = 720
    static let deskMargin = NSSize(width: 28, height: 36)
    /// Space between the page's edges and its text (Normal margins).
    static let pagePadding = NSSize(width: 72, height: 64)
    /// On a narrow window the desk and padding shrink, so the text keeps a usable width.
    static let narrowWidth: CGFloat = 640
    static let narrowDeskMargin = NSSize(width: 10, height: 16)
    static let narrowPagePadding = NSSize(width: 22, height: 32)
}
