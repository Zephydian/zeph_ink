import AppKit

/// The bundled typefaces: Literata for the page and JetBrains Mono for code, source view and `.txt`
/// files. Both are variable fonts (SIL Open Font License), so any weight comes from one file.
enum Fonts {
    /// Registers the bundled fonts for this app only. Call once, before any text is shown.
    static func register() {
        for name in ["Literata", "Literata-Italic", "JetBrainsMono"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Literata at a size and weight. Its optical size follows the point size, so headings get
    /// Literata's display cut and body text its text cut.
    static func serif(size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> NSFont {
        variable(italic ? "Literata-Italic" : "Literata-Regular", size: size, weight: weight, opticalSize: true)
            ?? .systemFont(ofSize: size, weight: weight >= 600 ? .bold : .regular)
    }

    static func mono(size: CGFloat, weight: CGFloat = 400) -> NSFont {
        variable("JetBrainsMono-Regular", size: size, weight: weight, opticalSize: false)
            ?? .monospacedSystemFont(ofSize: size, weight: weight >= 600 ? .bold : .regular)
    }

    /// JetBrains Mono without its code ligatures, so `==`, `~~` and `---` show as the characters you
    /// type (for the cheat sheet and tips, which teach exactly that).
    static func monoAsTyped(size: CGFloat) -> NSFont {
        let font = mono(size: size)
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kContextualAlternatesType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kContextualAlternatesOffSelector],
        ]])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// The app's interface font (SF), used on the page only for small headings.
    static func ui(size: CGFloat, weight: NSFont.Weight = .regular, smallCaps: Bool = false) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard smallCaps else { return font }
        // Shows lowercase letters as small capitals without changing the text.
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector],
        ]])
        return NSFont(descriptor: descriptor, size: size) ?? font
    }

    /// A font so small its characters take no visible space: how hidden markdown symbols are drawn.
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    private static let weightAxis = 0x7767_6874        // 'wght'
    private static let opticalSizeAxis = 0x6F70_737A   // 'opsz'

    private static func variable(_ name: String, size: CGFloat, weight: CGFloat, opticalSize: Bool) -> NSFont? {
        var axes: [Int: CGFloat] = [weightAxis: weight]
        if opticalSize { axes[opticalSizeAxis] = min(max(size, 7), 72) }
        let descriptor = NSFontDescriptor(name: name, size: size).addingAttributes([.variation: axes])
        guard let font = NSFont(descriptor: descriptor, size: size), font.fontName.hasPrefix(name.prefix(5)) else {
            return nil
        }
        return font
    }
}
