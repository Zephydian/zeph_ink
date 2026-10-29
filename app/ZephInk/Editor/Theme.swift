import AppKit

/// Colors, type and spacing.
///
/// Colors come from the theme (Settings → Theme): Light, Sepia, Dark or Midnight, or System, which is
/// Light or Dark with the Mac. Each color is resolved when it's drawn, so changing the theme only
/// needs a redraw. The window's chrome (tabs, toolbar, status bar, desk) always follows the theme;
/// the page's own colors do too, unless White Page keeps the page white in a darker theme.
nonisolated enum Theme {
    // MARK: Chrome colors

    /// The title bar, tab bar, toolbar and status bar.
    static let chrome = chromeColor(\.chrome)
    /// Text and icons on the chrome.
    static let chromeInk = chromeColor(\.ink)
    static let chromeInkSecondary = chromeColor(\.inkSecondary)
    static let chromeMarker = chromeColor(\.marker)
    /// Lines between parts of the window.
    static let chromeLine = chromeColor(\.line)
    /// Raised surfaces on the chrome: the selected tab, the style menu button.
    static let chromeSurface = chromeColor(\.page)
    static let hover = chromeColor(\.hover)
    /// Behind the page.
    static let desk = chromeColor(\.desk)

    // MARK: Page colors

    static let page = pageColor(\.page)
    static let ink = pageColor(\.ink)
    static let inkSecondary = pageColor(\.inkSecondary)
    /// Markdown symbols when they're shown faded (stronger with Increase Contrast on).
    static let marker = NSColor(name: nil) { appearance in
        let palette = usesWhitePage(for: appearance) ? Palette.light : palette(for: appearance)
        return Preferences.increaseContrast ? palette.inkSecondary : palette.marker
    }
    /// Lines on the page: dividers.
    static let rule = pageColor(\.line)
    static let codeBackground = pageColor(\.code)
    /// Behind `==highlighted==` text, like a marker pen.
    static let highlight = pageColor(\.highlight)

    /// The accent: the Mac's own accent color, or the one chosen in Settings.
    static var accent: NSColor { Preferences.accent.color }
    /// A light wash of the accent, for selections and active buttons.
    static var accentSoft: NSColor { accent.withAlphaComponent(0.18) }
    /// The accent as it should look on the page: its light version on a white page in a dark theme.
    static let pageAccent = NSColor(name: nil) { appearance in
        let look = usesWhitePage(for: appearance) ? NSAppearance(named: .aqua) ?? appearance : appearance
        var resolved = NSColor.systemBlue
        look.performAsCurrentDrawingAppearance { resolved = accent.usingColorSpace(.sRGB) ?? accent }
        return resolved
    }

    // MARK: Palettes

    /// One theme's colors.
    struct Palette {
        var chrome, desk, page, ink, inkSecondary, marker, line, hover, code, highlight: NSColor

        static let light = Palette(chrome: 0xF1F2F6, desk: 0xE8EAF1, page: 0xFFFFFF, ink: 0x1B1F30, inkSecondary: 0x4A5068,
                                   marker: 0xA5ABC0, line: 0xD9DCE6, hover: 0xDFE3EE, code: 0xF1F2F7, highlight: 0xFFF0A3)
        /// Warm, almost-white tan, like old paper.
        static let sepia = Palette(chrome: 0xEDE4D3, desk: 0xE3D8C3, page: 0xF8F1E3, ink: 0x3B2F22, inkSecondary: 0x6B5B47,
                                   marker: 0xB3A38A, line: 0xDACDB5, hover: 0xE2D6BF, code: 0xEFE5D1, highlight: 0xF3D98A)
        /// A neutral charcoal.
        static let dark = Palette(chrome: 0x252526, desk: 0x1A1A1B, page: 0x1F1F20, ink: 0xE4E4E4, inkSecondary: 0xA8A8A8,
                                  marker: 0x6B6B6E, line: 0x353537, hover: 0x2F2F31, code: 0x2B2B2D, highlight: 0x5C4D12)
        /// Deep blue: the original dark look.
        static let midnight = Palette(chrome: 0x151A30, desk: 0x0D1123, page: 0x161B31, ink: 0xE3E6F2, inkSecondary: 0xAAB0C8,
                                      marker: 0x5B6280, line: 0x262D49, hover: 0x232A46, code: 0x1D2340, highlight: 0x5C4D12)

        private init(chrome: Int, desk: Int, page: Int, ink: Int, inkSecondary: Int, marker: Int, line: Int, hover: Int,
                     code: Int, highlight: Int) {
            func color(_ hex: Int) -> NSColor {
                NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
            self.chrome = color(chrome); self.desk = color(desk); self.page = color(page); self.ink = color(ink)
            self.inkSecondary = color(inkSecondary); self.marker = color(marker); self.line = color(line)
            self.hover = color(hover); self.code = color(code); self.highlight = color(highlight)
        }
    }

    /// The palette for a view drawn in this appearance (System picks Light or Dark from it).
    static func palette(for appearance: NSAppearance) -> Palette {
        switch Preferences.theme {
        case .light: .light
        case .sepia: .sepia
        case .dark: .dark
        case .midnight: .midnight
        case .system: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }
    }

    /// Whether the page stays white in this appearance (White Page, in a theme that isn't light, and
    /// always on paper).
    static func usesWhitePage(for appearance: NSAppearance) -> Bool {
        if isPrinting { return true }
        guard Preferences.whitePage else { return false }
        switch Preferences.theme {
        case .light: return false
        case .system: return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        default: return true
        }
    }

    // MARK: Printing

    private static let printingKey = "ZephInkPrinting"

    /// Whether this thread is drawing a printed or exported page, which always has the Light theme's
    /// page colors. It's per thread, so editors drawing on other threads keep their theme.
    static var isPrinting: Bool { Thread.current.threadDictionary[printingKey] != nil }

    /// Lays out or draws paper: page colors are the Light theme's while `body` runs.
    static func printing<Result>(_ body: () -> Result) -> Result {
        let dictionary = Thread.current.threadDictionary
        let outer = dictionary[printingKey] != nil
        dictionary[printingKey] = true
        defer { if !outer { dictionary.removeObject(forKey: printingKey) } }
        guard let light = NSAppearance(named: .aqua) else { return body() }
        var result: Result?
        light.performAsCurrentDrawingAppearance { result = body() }
        return result!
    }

    private static func chromeColor(_ token: KeyPath<Palette, NSColor> & Sendable) -> NSColor {
        NSColor(name: nil) { appearance in palette(for: appearance)[keyPath: token] }
    }

    private static func pageColor(_ token: KeyPath<Palette, NSColor> & Sendable) -> NSColor {
        NSColor(name: nil) { appearance in
            (usesWhitePage(for: appearance) ? Palette.light : palette(for: appearance))[keyPath: token]
        }
    }

    // MARK: Type

    /// The body text size (the toolbar's size box, 12 points by default). Body text, lists, quotes and
    /// code are sized from it; headings aren't. Zoom scales the whole page on top of this.
    static var bodySize: CGFloat { Thread.current.threadDictionary[bodySizeKey] as? CGFloat ?? Preferences.textSize }

    private static let bodySizeKey = "ZephInkBodySize"

    /// Styles text at a fixed body size while `body` runs, whatever the setting (the markdown guide's
    /// small examples).
    static func withBodySize<Result>(_ size: CGFloat, _ body: () -> Result) -> Result {
        let dictionary = Thread.current.threadDictionary
        let outer = dictionary[bodySizeKey]
        dictionary[bodySizeKey] = size
        defer { dictionary[bodySizeKey] = outer }
        return body()
    }
    /// What heading sizes are worked out from: fixed, so titles and headings stay the same size when
    /// the body text size changes.
    static let headingBase: CGFloat = 12
    /// Line height as a multiple of the font size.
    static let bodyLineHeight: CGFloat = 1.68
    /// Source view and code: the size and line height of JetBrains Mono.
    static var sourceSize: CGFloat { (bodySize * 0.85 * 2).rounded() / 2 }
    static let sourceLineHeight: CGFloat = 1.75

    // MARK: Spacing

    /// Leaves room for the window's close, minimize and zoom buttons before the first tab.
    static let trafficLightsWidth: CGFloat = 78
    /// The Continuous page's width: it grows with the text size, so lines stay a comfortable length
    /// (612 points at 12-point text, the width of a Letter page).
    static var pageMaxWidth: CGFloat { (bodySize * 51).rounded() }
    static let deskMargin = NSSize(width: 28, height: 36)
    /// Space between the page's edges and its text: the Margins setting sets the sides.
    static var pagePadding: NSSize { NSSize(width: Preferences.margins.padding, height: 64) }
    /// On a narrow window the desk and padding shrink, so the text keeps a usable width.
    static let narrowWidth: CGFloat = 640
    static let narrowDeskMargin = NSSize(width: 10, height: 16)
    static let narrowPagePadding = NSSize(width: 22, height: 32)
}
