import AppKit

/// How markdown symbols (`**`, `## `, `- [ ]`…) look on the page.
enum MarkdownSymbols: String {
    /// Hidden, except on the lines you're editing (where they're faded).
    case clean
    /// Always visible, dimmed.
    case faded

    static var current: MarkdownSymbols {
        get { UserDefaults.standard.string(forKey: key).flatMap(MarkdownSymbols.init) ?? .clean }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static let key = "markdownSymbols"
}

/// What a line needs drawn around its text (a quote bar, a code background, a divider, a bullet or
/// a checkbox). `PageLayoutFragment` reads it from the line's first character.
nonisolated final class LineDecoration: NSObject {
    var quoteDepth = 0
    var code: MarkdownAnalysis.CodeLine?
    var isDivider = false
    /// Where the bullet goes: the offset of the `-` from the start of the line.
    var bullet: Int?
    /// Where the checkbox goes: the offset of the `[ ]` from the start of the line.
    var task: Int?
    var isChecked = false
    /// An image shown below the line, at this size.
    var image: CGImage?
    var imageSize: CGSize = .zero
    /// An image the person needs to allow Zeph#Ink to read: a prompt to click instead.
    var imageNeedsAccess = false
    /// A line of the front matter card, and whether it's the card's header (and folded).
    var frontMatter: MarkdownAnalysis.CodeLine?
    var frontMatterHeader = false
    var isCollapsed = false

    static let accessPromptHeight: CGFloat = 44

    override func copy() -> Any {
        let copy = LineDecoration()
        copy.quoteDepth = quoteDepth; copy.code = code; copy.isDivider = isDivider
        copy.bullet = bullet; copy.task = task; copy.isChecked = isChecked
        copy.image = image; copy.imageSize = imageSize; copy.imageNeedsAccess = imageNeedsAccess
        copy.frontMatter = frontMatter; copy.frontMatterHeader = frontMatterHeader; copy.isCollapsed = isCollapsed
        return copy
    }
}

nonisolated extension NSAttributedString.Key {
    /// A `LineDecoration` on every character of a decorated line.
    static let lineDecoration = NSAttributedString.Key("ZephInkLineDecoration")
}

/// Styles markdown text in place. Only attributes change: the characters, which are the file, never do.
///
/// Each line gets the look of its block (heading, quote, code…), then inline styles on top. Markdown
/// symbols are faded, or in Clean mode drawn in a font too small to see, except on `revealed` lines.
enum MarkdownStyler {
    /// How to show images: where to find them, and how wide the text column is.
    struct Images {
        var lookup: (String) -> ImageLoader.Result?
        var columnWidth: CGFloat
        /// On paper, an image is never taller than a page holds.
        var maxHeight: CGFloat = .greatestFiniteMagnitude
    }

    enum Mode: Equatable {
        case page(MarkdownSymbols)
        /// Plain monospaced text, no styling.
        case source
    }

    /// Styles the given lines (indices into `analysis.lines`).
    static func apply(_ analysis: MarkdownAnalysis, to storage: NSTextStorage, lines: ClosedRange<Int>,
                      mode: Mode, revealed: Set<Int> = [], images: Images? = nil, collapsesFrontMatter: Bool = false) {
        guard !analysis.lines.isEmpty else { return }
        let lines = lines.clamped(to: 0...(analysis.lines.count - 1))
        let first = analysis.lines[lines.lowerBound].fullRange.location
        let last = NSMaxRange(analysis.lines[lines.upperBound].fullRange)
        guard last <= storage.length else { return }
        let region = NSRange(location: first, length: last - first)

        guard case .page(let symbols) = mode else {
            storage.setAttributes(sourceAttributes, range: region)
            return
        }

        // Inline styles by line, so each line only looks at its own.
        var spansByLine: [Int: [MarkdownAnalysis.Span]] = [:]
        for span in analysis.spans where NSIntersectionRange(span.range, region).length > 0 {
            let start = analysis.lineIndex(at: span.range.location)
            let end = analysis.lineIndex(at: max(NSMaxRange(span.range) - 1, span.range.location))
            for index in max(start, lines.lowerBound)...min(end, lines.upperBound) {
                spansByLine[index, default: []].append(span)
            }
        }

        for index in lines {
            let hidesSymbols = symbols == .clean && !revealed.contains(index)
            styleLine(analysis.lines[index], spans: spansByLine[index] ?? [], in: storage, hidesSymbols: hidesSymbols, images: images,
                      collapsesFrontMatter: collapsesFrontMatter)
        }
    }

    static func applyAll(_ analysis: MarkdownAnalysis, to storage: NSTextStorage, mode: Mode, revealed: Set<Int> = [],
                         images: Images? = nil, collapsesFrontMatter: Bool = false) {
        apply(analysis, to: storage, lines: 0...max(analysis.lines.count - 1, 0), mode: mode, revealed: revealed, images: images,
              collapsesFrontMatter: collapsesFrontMatter)
    }

    private static let imageLine = try! NSRegularExpression(pattern: #"^[ \t]*!\[[^\]]*\]\(<?([^)\s>]+)>?(?:[ \t]+"[^"]*")?\)[ \t]*$"#)

    /// The path of an image that's alone on its line (the only kind shown on the page).
    static func imagePath(in line: String) -> String? {
        let ns = line as NSString
        guard let match = imageLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// What typing on an empty line should look like: that line's own style. (NSTextView would
    /// otherwise copy the line above, so typing under a centered line would come out centered.)
    static func typingAttributes(for line: MarkdownAnalysis.Line, mode: Mode) -> [NSAttributedString.Key: Any] {
        guard case .page = mode else { return sourceAttributes }
        var attributes = BlockStyle(line, hidesSymbols: false).attributes
        attributes[.lineDecoration] = nil
        return attributes
    }

    // MARK: - One line

    private static let frontMatterKey = try! NSRegularExpression(pattern: #"^[ \t]*[^:#\s][^:]*:"#)

    private static func styleLine(_ line: MarkdownAnalysis.Line, spans: [MarkdownAnalysis.Span],
                                  in storage: NSTextStorage, hidesSymbols: Bool, images: Images?, collapsesFrontMatter: Bool) {
        var block = BlockStyle(line, hidesSymbols: hidesSymbols, collapsesFrontMatter: collapsesFrontMatter)
        // An image alone on its line shows below it, and in Clean mode stands in for its markdown.
        var showsImage = false
        if let images, line.kind == .body, let path = imagePath(in: (storage.string as NSString).substring(with: line.range)),
           let result = images.lookup(path) {
            showsImage = block.showImage(result, columnWidth: images.columnWidth, maxHeight: images.maxHeight)
        }
        storage.setAttributes(block.attributes, range: line.fullRange)

        // Every boundary where an inline style starts or stops, then each run between two boundaries.
        var runs: [Run] = spans.map { Run(range: $0.range, kind: .inline($0.style)) }
        if showsImage && hidesSymbols { runs.append(Run(range: line.range, kind: .inline(.marker))) }
        if case .frontMatter(let part) = line.kind {
            if hidesSymbols && collapsesFrontMatter && !part.isFirst {
                runs.append(Run(range: line.range, kind: .inline(.marker)))   // folded away
            } else if !part.isFence,
                      let key = frontMatterKey.firstMatch(in: storage.string, range: line.range)?.range {
                runs.append(Run(range: key, kind: .inline(.strong)))
            }
        }
        runs += line.markers.map { Run(range: $0, kind: .inline(.marker)) }
        if let list = line.list {
            if list.bullet == nil { runs.append(Run(range: list.marker, kind: .number)) }
            // A drawn bullet or checkbox stands in for the symbol, which keeps its width (and the
            // space after it) but is clear.
            if hidesSymbols {
                let start = list.task?.location ?? list.bullet?.location
                if let start { runs.append(Run(range: NSRange(location: start, length: list.contentStart - start), kind: .drawn)) }
            }
        }
        if let list = line.list, list.isChecked {
            let done = NSRange(location: list.contentStart, length: NSMaxRange(line.range) - list.contentStart)
            runs.append(Run(range: done, kind: .done))
        }

        let limit = line.fullRange
        var cuts = Set([limit.location, NSMaxRange(limit)])
        for run in runs {
            let clipped = NSIntersectionRange(run.range, limit)
            guard clipped.length > 0 else { continue }
            cuts.insert(clipped.location)
            cuts.insert(NSMaxRange(clipped))
        }
        let sorted = cuts.sorted()
        for (start, end) in zip(sorted, sorted.dropFirst()) where end > start {
            let piece = NSRange(location: start, length: end - start)
            let covering = runs.filter { NSIntersectionRange($0.range, piece).length == piece.length }
            guard !covering.isEmpty else { continue }
            storage.addAttributes(block.attributes(for: covering), range: piece)
        }

        // A nested item's leading spaces are only a few points wide in the page font; widen them
        // so each level sits under the text of the item above it.
        if let list = line.list, list.marker.location > line.range.location {
            let indent = NSRange(location: line.range.location, length: list.marker.location - line.range.location)
            if (storage.string as NSString).substring(with: indent).allSatisfy({ $0 == " " }) {
                storage.addAttribute(.kern, value: Theme.bodySize * 0.33, range: indent)
            }
        }

        // A drawn bullet or checkbox needs more room than its symbol: widen the symbol's last
        // character so the text starts where the prototype's lists do.
        if hidesSymbols, let list = line.list, let start = list.task?.location ?? list.bullet?.location,
           list.contentStart > start {
            let symbol = NSRange(location: start, length: list.contentStart - start)
            let room = Theme.bodySize * (list.task != nil ? 1.55 : 1.15)
            let extra = room - storage.attributedSubstring(from: symbol).size().width
            if extra > 0 { storage.addAttribute(.kern, value: extra, range: NSRange(location: NSMaxRange(symbol) - 1, length: 1)) }
        }

        // A list item's wrapped lines line up with its text, after the marker as it's drawn.
        if let list = line.list, list.contentStart > line.range.location {
            let prefix = storage.attributedSubstring(from: NSRange(location: line.range.location,
                                                                   length: list.contentStart - line.range.location))
            let style = (block.attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            if let style {
                style.headIndent = style.firstLineHeadIndent + ceil(prefix.size().width)
                storage.addAttribute(.paragraphStyle, value: style, range: line.fullRange)
            }
        }
    }

    private struct Run {
        enum Kind {
            case inline(MarkdownAnalysis.InlineStyle)
            /// A bullet or checkbox symbol that a drawing stands in for.
            case drawn
            /// The text of a ticked checklist item.
            case done
            /// A numbered item's number.
            case number
        }

        var range: NSRange
        var kind: Kind
    }

    // MARK: - Block look

    /// The look a line gets from its block, and how inline styles change it.
    private struct BlockStyle {
        var font: FontSpec
        var color: NSColor
        var paragraph: NSMutableParagraphStyle
        var kern: CGFloat = 0
        var decoration: LineDecoration?
        let hidesSymbols: Bool

        init(_ line: MarkdownAnalysis.Line, hidesSymbols: Bool, collapsesFrontMatter: Bool = false) {
            self.hidesSymbols = hidesSymbols
            font = FontSpec(family: .serif, size: Theme.bodySize)
            color = Theme.ink
            paragraph = NSMutableParagraphStyle()
            var lineHeight = Theme.bodySize * Theme.bodyLineHeight
            let decoration = LineDecoration()
            var isDecorated = false

            switch line.kind {
            case .heading(let level):
                switch level {
                // Headings keep their sizes whatever the body text size is.
                case 1: font = FontSpec(family: .serif, size: Theme.headingBase * 2, weight: 700); lineHeight = font.size * 1.2
                case 2: font = FontSpec(family: .serif, size: Theme.headingBase * 1.42, weight: 700); lineHeight = font.size * 1.3
                case 3: font = FontSpec(family: .serif, size: Theme.headingBase * 1.14, weight: 600); lineHeight = font.size * 1.35
                default:
                    font = FontSpec(family: .smallCaps, size: Theme.headingBase * 0.82, weight: 600)
                    lineHeight = Theme.headingBase * 1.4
                    color = Theme.inkSecondary
                    kern = font.size * 0.06
                }
                paragraph.paragraphSpacingBefore = level == 1 ? 0 : font.size * 0.35
            case .code(let code):
                font = FontSpec(family: .mono, size: Theme.bodySize * 0.8)
                lineHeight = font.size * 1.6
                if code.isFence && hidesSymbols { lineHeight = 10 }   // a little padding inside the box
                paragraph.firstLineHeadIndent = 16
                paragraph.headIndent = 16
                paragraph.tailIndent = -16
                decoration.code = code
                isDecorated = true
            case .table:
                font = FontSpec(family: .mono, size: Theme.sourceSize)
                lineHeight = Theme.sourceSize * Theme.sourceLineHeight
            case .divider:
                if hidesSymbols {
                    decoration.isDivider = true
                    isDecorated = true
                }
            case .blank:
                lineHeight = Theme.bodySize * 0.9   // blank lines space blocks apart without a full line's gap
                if hidesSymbols && line.alignment != nil { lineHeight = 2 }   // the blank lines alignment tags need
            case .alignTag:
                if hidesSymbols { lineHeight = 2 }
            case .frontMatter(let part):
                // A card: small interface type, a header in place of the opening `---`.
                font = FontSpec(family: .ui, size: Theme.bodySize * 0.76)
                color = Theme.inkSecondary
                lineHeight = Theme.bodySize * 1.25
                paragraph.firstLineHeadIndent = 16
                paragraph.headIndent = 16
                paragraph.tailIndent = -16
                decoration.frontMatter = part
                if hidesSymbols {
                    decoration.isCollapsed = collapsesFrontMatter
                    if part.isFirst {
                        lineHeight = Theme.bodySize * 1.8
                        decoration.frontMatterHeader = true
                    } else if part.isLast || collapsesFrontMatter {
                        lineHeight = part.isLast ? 8 : 0.5
                    }
                }
                isDecorated = true
            case .body:
                break
            }

            if line.quoteDepth > 0 {
                font.italic = true
                color = Theme.inkSecondary
                let indent = CGFloat(line.quoteDepth) * Theme.bodySize * 1.1
                paragraph.firstLineHeadIndent += indent
                paragraph.headIndent += indent
                decoration.quoteDepth = line.quoteDepth
                isDecorated = true
            }
            if hidesSymbols, let list = line.list {
                if let task = list.task {
                    decoration.task = task.location - line.range.location
                    decoration.isChecked = list.isChecked
                    isDecorated = true
                } else if let bullet = list.bullet {
                    decoration.bullet = bullet.location - line.range.location
                    isDecorated = true
                }
            }

            switch line.alignment {
            case .center: paragraph.alignment = .center
            case .right: paragraph.alignment = .right
            default: break
            }
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            self.decoration = isDecorated ? decoration : nil
        }

        /// Shows an image below the line: room for it after the line, and the drawing in the decoration.
        /// Returns whether there's something to show.
        mutating func showImage(_ result: ImageLoader.Result, columnWidth: CGFloat, maxHeight: CGFloat) -> Bool {
            let decoration = self.decoration ?? LineDecoration()
            let height: CGFloat
            switch result {
            case .image(let image):
                let width = CGFloat(image.width), natural = CGFloat(image.height)
                let scale = width > 0 && natural > 0 ? min(1, max(columnWidth, 1) / width, max(maxHeight, 1) / natural) : 1
                decoration.image = image
                decoration.imageSize = CGSize(width: (width * scale).rounded(), height: (natural * scale).rounded())
                height = decoration.imageSize.height
            case .needsAccess:
                decoration.imageNeedsAccess = true
                height = LineDecoration.accessPromptHeight
            }
            if hidesSymbols {
                paragraph.minimumLineHeight = 2
                paragraph.maximumLineHeight = 2
            }
            paragraph.paragraphSpacing = height + 14
            self.decoration = decoration
            return true
        }

        var attributes: [NSAttributedString.Key: Any] {
            let nsFont = font.font
            var attributes: [NSAttributedString.Key: Any] = [
                .font: nsFont,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .baselineOffset: Self.centeringOffset(for: nsFont, lineHeight: paragraph.maximumLineHeight),
            ]
            if kern != 0 { attributes[.kern] = kern }
            if let decoration { attributes[.lineDecoration] = decoration }
            return attributes
        }

        func attributes(for runs: [Run]) -> [NSAttributedString.Key: Any] {
            var style = MarkdownAnalysis.InlineStyle()
            var isDrawn = false, isDone = false, isNumber = false
            for run in runs {
                switch run.kind {
                case .inline(let inline): style.formUnion(inline)
                case .drawn: isDrawn = true
                case .done: isDone = true
                case .number: isNumber = true
                }
            }

            var spec = font
            var attributes: [NSAttributedString.Key: Any] = [:]
            if style.contains(.strong) { spec.weight = 700 }
            if style.contains(.emphasis) { spec.italic.toggle() }
            if style.contains(.code), spec.family != .mono {
                spec.family = .mono
                spec.size *= 0.84
                spec.italic = false
                attributes[.backgroundColor] = Theme.codeBackground
            }
            if style.contains(.highlight) { attributes[.backgroundColor] = Theme.highlight }
            if style.contains(.strikethrough) || isDone {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = isDone ? Theme.marker : Theme.inkSecondary
            }
            if isDone || isNumber { attributes[.foregroundColor] = Theme.inkSecondary }
            if style.contains(.link) {
                attributes[.foregroundColor] = Theme.pageAccent
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if style.contains(.marker) {
                attributes[.underlineStyle] = 0
                attributes[.strikethroughStyle] = 0
                attributes[.backgroundColor] = nil
                if hidesSymbols && !isDrawn {
                    attributes[.font] = Fonts.hidden
                    attributes[.foregroundColor] = NSColor.clear
                    attributes[.kern] = 0
                    return attributes
                }
                attributes[.foregroundColor] = Theme.marker
            }
            if isDrawn {
                attributes[.foregroundColor] = NSColor.clear
                attributes[.strikethroughStyle] = 0
            }
            attributes[.font] = spec.font
            return attributes
        }

        /// Raises text so it sits in the middle of a line taller than the font, instead of at the bottom.
        static func centeringOffset(for font: NSFont, lineHeight: CGFloat) -> CGFloat {
            let natural = font.ascender - font.descender
            return max(0, (lineHeight - natural) / 2).rounded(.down)
        }
    }

    // MARK: - Source view

    private static var sourceAttributes: [NSAttributedString.Key: Any] {
        let font = FontSpec(family: .mono, size: Theme.sourceSize).font
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = Theme.sourceSize * Theme.sourceLineHeight
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: Theme.ink, .paragraphStyle: paragraph,
                .baselineOffset: BlockStyle.centeringOffset(for: font, lineHeight: lineHeight)]
    }
}

/// A font described by what it's for, so inline styles can adjust it (bold, italic, code) and the
/// result can be cached.
private struct FontSpec: Hashable {
    enum Family { case serif, mono, smallCaps, ui }

    var family: Family
    var size: CGFloat
    var weight: CGFloat = 400
    var italic = false

    private static var cache: [FontSpec: NSFont] = [:]

    var font: NSFont {
        if let cached = Self.cache[self] { return cached }
        let font: NSFont
        switch family {
        case .serif: font = Fonts.serif(size: size, weight: weight, italic: italic)
        case .mono: font = Fonts.mono(size: size, weight: weight)
        case .smallCaps: font = Fonts.ui(size: size, weight: weight >= 700 ? .bold : .semibold, smallCaps: true)
        case .ui: font = Fonts.ui(size: size, weight: weight >= 700 ? .semibold : .regular)
        }
        Self.cache[self] = font
        return font
    }
}
