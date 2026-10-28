import AppKit
import SwiftUI

/// Colors, fonts and spacing. Every color is a light/dark pair in `Assets.xcassets`.
enum Theme {
    // MARK: Colors

    /// The title bar, tab bar, toolbar and status bar.
    static let chrome = NSColor(resource: .chrome)
    /// Behind the page.
    static let desk = NSColor(resource: .desk)
    static let page = NSColor(resource: .page)
    static let ink = NSColor(resource: .ink)
    static let inkSecondary = NSColor(resource: .inkSecondary)
    /// Markdown symbols when they're shown faded.
    static let marker = NSColor(resource: .marker)
    static let line = NSColor(resource: .line)
    static let hover = NSColor(resource: .hover)
    static let codeBackground = NSColor(resource: .codeBackground)
    /// Zephydian Ink, the fixed accent.
    static let accent = NSColor(resource: .accent)
    static let accentSoft = NSColor(resource: .accentSoft)

    // MARK: Fonts

    /// The page's body text. Placeholder until the page typeface (Literata) is bundled.
    static let bodyFont = NSFont.systemFont(ofSize: 17)

    // MARK: Spacing

    /// Leaves room for the window's close, minimize and zoom buttons before the first tab.
    static let trafficLightsWidth: CGFloat = 78
    /// Space between the page's edges and its text.
    static let pageInset = NSSize(width: 64, height: 48)
}
