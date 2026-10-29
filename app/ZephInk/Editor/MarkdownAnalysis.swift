import Foundation
import Markdown

/// What each line and run of a markdown text is, worked out from swift-markdown's parse.
///
/// It holds ranges only (in UTF-16 units, like `NSString`), and never changes the text.
/// `MarkdownStyler` turns it into attributes.
nonisolated struct MarkdownAnalysis {
    struct Line: Equatable {
        /// The line without its line break.
        var range: NSRange
        /// The line with its line break.
        var fullRange: NSRange
        var kind: Kind = .body
        /// How many block quotes the line is in.
        var quoteDepth = 0
        /// The list item that starts on this line.
        var list: ListMarker?
        /// Block markdown symbols on the line: `## `, `> `, a bullet's `- `, code fences, a divider.
        var markers: [NSRange] = []
        /// The top-level block the line belongs to (nil for blank lines between blocks).
        var block: Int?
        /// Set inside a `<div align="center">` (or `right`) region.
        var alignment: Alignment?

        /// The same line, `delta` characters further on.
        func moved(by delta: Int) -> Line {
            guard delta != 0 else { return self }
            let move = { (range: NSRange) in NSRange(location: range.location + delta, length: range.length) }
            var line = self
            line.range = move(range)
            line.fullRange = move(fullRange)
            line.markers = markers.map(move)
            if var list {
                list.marker = move(list.marker)
                list.bullet = list.bullet.map(move)
                list.task = list.task.map(move)
                list.contentStart += delta
                line.list = list
            }
            return line
        }

        /// Everything about the line's look except where it is, for telling which lines changed.
        var shape: Shape {
            Shape(kind: kind, quoteDepth: quoteDepth,
                  listPrefix: list.map { $0.contentStart - range.location },
                  isChecked: list?.isChecked ?? false, alignment: alignment)
        }

        struct Shape: Equatable {
            var kind: Kind
            var quoteDepth: Int
            var listPrefix: Int?
            var isChecked: Bool
            var alignment: Alignment?
        }
    }

    /// Center or right alignment, saved as HTML around the paragraphs (markdown has none of its own).
    enum Alignment: String, Equatable {
        case left, center, right
    }

    enum Kind: Equatable {
        case body
        case blank
        /// `<div align="…">` or `</div>` around aligned paragraphs: a symbol line.
        case alignTag
        /// A line of the YAML front matter at the top of a file (`---`, `title: …`, `---`).
        case frontMatter(CodeLine)
        case heading(level: Int)
        case code(CodeLine)
        case divider
        case table
    }

    /// A line of a code block. Fences are the ``` lines around a fenced block.
    struct CodeLine: Equatable {
        var isFence: Bool
        var isFirst: Bool
        var isLast: Bool
    }

    struct ListMarker: Equatable {
        /// The marker and the spaces after it: `- ` or `1. `.
        var marker: NSRange
        /// The `-`, `*` or `+` of a bulleted item (nil for numbered items).
        var bullet: NSRange?
        /// The `[ ]` or `[x]` of a checklist item.
        var task: NSRange?
        var isChecked: Bool
        /// Where the item's text starts, after the marker and its spaces.
        var contentStart: Int
    }

    struct Span: Hashable {
        var range: NSRange
        var style: InlineStyle
    }

    struct InlineStyle: OptionSet, Hashable {
        let rawValue: Int
        static let strong = InlineStyle(rawValue: 1 << 0)
        static let emphasis = InlineStyle(rawValue: 1 << 1)
        static let strikethrough = InlineStyle(rawValue: 1 << 2)
        static let code = InlineStyle(rawValue: 1 << 3)
        static let link = InlineStyle(rawValue: 1 << 4)
        /// Markdown symbols such as `**` or `](url)`: hidden or faded.
        static let marker = InlineStyle(rawValue: 1 << 5)
        /// `==text==`: not standard markdown (swift-markdown doesn't know it), found by `Builder`.
        static let highlight = InlineStyle(rawValue: 1 << 6)
    }

    var lines: [Line] = []
    /// Inline styles, in no particular order. They can overlap (bold inside a link).
    var spans: [Span] = []
    /// The next unused block number, for blocks added by `updated(afterEditing:changeInLength:in:)`.
    private var nextBlock = 0

    /// `allowsFrontMatter` is false for a piece of a document that doesn't start at its top.
    init(_ text: String, allowsFrontMatter: Bool = true) {
        let map = SourceMap(text)
        lines = map.lines.map { Line(range: $0.range, fullRange: $0.fullRange) }
        let nsText = text as NSString
        // Front matter isn't markdown: the parser would read its closing `---` as a heading underline.
        // It gets empty lines in its place, so the lines after it keep their numbers.
        let frontMatter = allowsFrontMatter ? Self.frontMatterEnd(in: nsText, lines: lines) : nil
        var parsed = text
        if let end = frontMatter {
            parsed = String(repeating: "\n", count: end + 1) + nsText.substring(from: NSMaxRange(lines[end].fullRange))
        }
        var builder = Builder(map: map, text: nsText, lines: lines)
        let document = Document(parsing: parsed, options: [.disableSmartOpts])
        for (index, child) in document.children.enumerated() {
            builder.visit(child, block: index, quoteDepth: 0)
        }
        builder.finish()
        lines = builder.lines
        spans = builder.spans
        nextBlock = document.childCount
        if let end = frontMatter {
            for index in 0...end {
                let isFence = index == 0 || index == end
                lines[index].kind = .frontMatter(CodeLine(isFence: isFence, isFirst: index == 0, isLast: index == end))
                lines[index].markers = isFence ? [lines[index].range] : []
                lines[index].block = -1
            }
        }
    }

    /// The last line of the YAML front matter, if the text starts with some: a `---` line, then
    /// lines up to the next `---` (or `...`) line.
    static func frontMatterEnd(in text: NSString, lines: [Line]) -> Int? {
        func trimmed(_ index: Int) -> String {
            text.substring(with: lines[index].range).trimmingCharacters(in: .whitespaces)
        }
        guard lines.count >= 2, trimmed(0) == "---" else { return nil }
        for index in 1..<min(lines.count, 500) {
            let line = trimmed(index)
            if line == "---" || line == "..." { return index > 1 ? index : nil }
        }
        return nil
    }

    /// The analysis of `text` after an edit, worked out by parsing only the blocks around the edit
    /// (and one neighbour on each side, which the edit may join or split). Returns the new analysis and
    /// the lines it re-parsed, or nil when the edit could reach further than that (a code fence, a link
    /// definition) and the whole text needs parsing.
    ///
    /// `edited` is the edited range in the new text; `delta` is how much longer the text got.
    func updated(afterEditing edited: NSRange, changeInLength delta: Int, in text: String) -> (MarkdownAnalysis, ClosedRange<Int>)? {
        let nsText = text as NSString
        let oldEnd = NSMaxRange(edited) - delta
        guard !lines.isEmpty, oldEnd >= edited.location, edited.location > 0 || !text.hasPrefix("--") else { return nil }

        // The old lines the edit touched, widened to whole blocks, one line further each way, and
        // to whole blocks again.
        var first = lineIndex(at: edited.location), last = lineIndex(at: oldEnd)
        func widenToBlocks() {
            if let block = lines[first].block { while first > 0, lines[first - 1].block == block { first -= 1 } }
            if let block = lines[last].block { while last + 1 < lines.count, lines[last + 1].block == block { last += 1 } }
        }
        widenToBlocks()
        first = max(first - 1, 0)
        last = min(last + 1, lines.count - 1)
        widenToBlocks()

        // Fences open or close everything after them, so they need the whole text.
        for line in lines[first...last] {
            if case .code(let code) = line.kind, code.isFence { return nil }
            // Alignment comes from tags that may be outside the region, and front matter only counts at the top.
            if line.alignment != nil || line.kind == .alignTag { return nil }
            if case .frontMatter = line.kind { return nil }
        }
        let start = lines[first].fullRange.location
        let end = NSMaxRange(lines[last].fullRange) + delta
        guard end >= start, end <= nsText.length else { return nil }
        let region = NSRange(location: start, length: end - start)
        let regionText = nsText.substring(with: region)
        if regionText.contains("```") || regionText.contains("~~~") || regionText.contains("]:") || regionText.contains("<div") || regionText.contains("</div") { return nil }

        var part = MarkdownAnalysis(regionText, allowsFrontMatter: start == 0)
        // A region that ends with a line break gets an empty last line from the split: that line is
        // really the start of the next one, which stays as it was.
        if last + 1 < lines.count, part.lines.count > 1, part.lines.last?.fullRange.length == 0 {
            part.lines.removeLast()
        }

        var result = self
        let shifted = { (range: NSRange) in NSRange(location: range.location + start, length: range.length) }
        let newLines = part.lines.map { line -> Line in
            var line = line.moved(by: start)
            line.block = line.block.map { $0 + nextBlock }   // numbers no other block uses
            return line
        }
        let following = lines[(last + 1)...].map { $0.moved(by: delta) }
        result.lines = Array(lines[..<first]) + newLines + following
        let oldRegionEnd = NSMaxRange(lines[last].fullRange)
        result.spans = spans.compactMap { span in
            if NSMaxRange(span.range) <= start { return span }
            if span.range.location >= oldRegionEnd {
                return Span(range: NSRange(location: span.range.location + delta, length: span.range.length), style: span.style)
            }
            return nil
        } + part.spans.map { Span(range: shifted($0.range), style: $0.style) }
        result.nextBlock = nextBlock + part.nextBlock
        return (result, first...(first + max(newLines.count - 1, 0)))
    }

    /// The index of the line holding a UTF-16 offset (the last line for the end of the text).
    func lineIndex(at location: Int) -> Int {
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].fullRange.location <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

// MARK: - Walking the parse

nonisolated private struct Builder {
    let map: SourceMap
    let text: NSString
    var lines: [MarkdownAnalysis.Line]
    var spans: [MarkdownAnalysis.Span] = []

    init(map: SourceMap, text: NSString, lines: [MarkdownAnalysis.Line]) {
        self.map = map
        self.text = text
        self.lines = lines
    }

    /// `actualRange` corrects the parser's range for a style nested directly in another: it reports
    /// the same range for both in `***both***`.
    mutating func visit(_ node: Markup, block: Int, quoteDepth: Int, actualRange: NSRange? = nil) {
        guard let range = actualRange ?? map.range(node.range) else { return }
        let lineSpan = map.lineSpan(node.range)
        for line in lineSpan { lines[line].block = block }

        switch node {
        case let heading as Heading:
            for line in lineSpan { lines[line].kind = .heading(level: heading.level) }
            markHeading(lineSpan)
        case is CodeBlock:
            markCode(lineSpan)
        case is ThematicBreak:
            for line in lineSpan {
                lines[line].kind = .divider
                lines[line].markers.append(contentRange(of: line))
            }
        case is Table:
            for line in lineSpan { lines[line].kind = .table }
        case is BlockQuote:
            for line in lineSpan { lines[line].quoteDepth = max(lines[line].quoteDepth, quoteDepth + 1) }
        case let item as ListItem:
            markListItem(item, at: range.location, line: lineSpan.lowerBound)
        case is Strong, is Emphasis, is Strikethrough:
            // Their symbols are a known number of characters at each end, which is surer than the
            // parser's ranges for nested styles.
            let content = delimitedContent(node, range: range)
            let style: MarkdownAnalysis.InlineStyle = node is Strong ? .strong : node is Emphasis ? .emphasis : .strikethrough
            spans.append(.init(range: content, style: style))
            spans.append(.init(range: NSRange(location: range.location, length: content.location - range.location), style: .marker))
            spans.append(.init(range: NSRange(location: NSMaxRange(content), length: NSMaxRange(range) - NSMaxRange(content)), style: .marker))
            let childDepth = quoteDepth
            for child in node.children {
                let reported = map.range(child.range)
                let isNestedStyle = child is Strong || child is Emphasis || child is Strikethrough
                let fixed = isNestedStyle && (reported == nil || reported == range || NSIntersectionRange(reported!, content).length != reported!.length)
                    ? content : nil
                visit(child, block: block, quoteDepth: childDepth, actualRange: fixed)
            }
            return
        case is InlineCode:
            spans.append(.init(range: range, style: .code))
            let ticks = backticks(at: range.location, limit: range.length / 2)
            if ticks > 0 {
                spans.append(.init(range: NSRange(location: range.location, length: ticks), style: .marker))
                spans.append(.init(range: NSRange(location: NSMaxRange(range) - ticks, length: ticks), style: .marker))
            }
        case is Link:
            addDelimited(node, range: range, style: .link)
        case is Image:
            spans.append(.init(range: range, style: .link))
        default:
            break
        }

        let childDepth = node is BlockQuote ? quoteDepth + 1 : quoteDepth
        for child in node.children {
            visit(child, block: block, quoteDepth: childDepth)
        }
    }

    /// The text inside a bold, italic or strikethrough run: its range without the symbols at each end
    /// (`**`, `*` or `_`, `~~` or `~`).
    private func delimitedContent(_ node: Markup, range: NSRange) -> NSRange {
        var length = node is Strong ? 2 : 1
        if node is Strikethrough, range.length >= 4, text.character(at: range.location + 1) == 0x7E { length = 2 }   // "~~"
        guard range.length >= length * 2 else { return NSRange(location: range.location, length: 0) }
        return NSRange(location: range.location + length, length: range.length - length * 2)
    }

    /// Styles a run like `**bold**` or `[text](url)`: the whole run gets the style, and whatever
    /// lies outside its children is a marker.
    private mutating func addDelimited(_ node: Markup, range: NSRange, style: MarkdownAnalysis.InlineStyle) {
        let childRanges = node.children.compactMap { map.range($0.range) }
        guard let first = childRanges.first, let last = childRanges.last else {
            spans.append(.init(range: range, style: style))
            return
        }
        let inner = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        spans.append(.init(range: inner, style: style))
        if inner.location > range.location {
            spans.append(.init(range: NSRange(location: range.location, length: inner.location - range.location), style: .marker))
        }
        if NSMaxRange(range) > NSMaxRange(inner) {
            spans.append(.init(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(range) - NSMaxRange(inner)), style: .marker))
        }
    }

    private mutating func markHeading(_ lineSpan: ClosedRange<Int>) {
        let first = lineSpan.lowerBound
        if lineSpan.count > 1 {
            // A heading underlined with === or ---: the underline is the marker.
            lines[lineSpan.upperBound].markers.append(contentRange(of: lineSpan.upperBound))
            return
        }
        let line = lines[first].range
        if let opening = match(Patterns.atxOpening, in: line) {
            lines[first].markers.append(opening)
            let rest = NSRange(location: NSMaxRange(opening), length: NSMaxRange(line) - NSMaxRange(opening))
            if let closing = match(Patterns.atxClosing, in: rest), closing.location > rest.location || rest.length == closing.length {
                lines[first].markers.append(closing)
            }
        }
    }

    private mutating func markCode(_ lineSpan: ClosedRange<Int>) {
        let isFenced = match(Patterns.fenceStart, in: lines[lineSpan.lowerBound].range) != nil
        for line in lineSpan {
            let isFirst = line == lineSpan.lowerBound, isLast = line == lineSpan.upperBound
            let isFence = isFenced && (isFirst || (isLast && match(Patterns.fenceLine, in: lines[line].range) != nil))
            lines[line].kind = .code(.init(isFence: isFence, isFirst: isFirst, isLast: isLast))
            if isFence { lines[line].markers.append(contentRange(of: line)) }
        }
    }

    private mutating func markListItem(_ item: ListItem, at location: Int, line: Int) {
        let rest = NSRange(location: location, length: NSMaxRange(lines[line].range) - location)
        guard let marker = match(Patterns.listMarker, in: rest) else { return }
        let isBullet = "-*+".contains(text.substring(with: NSRange(location: location, length: 1)))
        var list = MarkdownAnalysis.ListMarker(marker: marker, bullet: isBullet ? NSRange(location: location, length: 1) : nil,
                                               task: nil, isChecked: false, contentStart: NSMaxRange(marker))
        if let checkbox = item.checkbox {
            let after = NSRange(location: NSMaxRange(marker), length: NSMaxRange(rest) - NSMaxRange(marker))
            if let box = match(Patterns.taskBox, in: after) {
                list.task = NSRange(location: box.location, length: 3)
                list.isChecked = checkbox == .checked
                list.contentStart = NSMaxRange(box)
            }
        }
        lines[line].list = list
        // A bullet is a symbol; a number is part of what the person reads, so it's never hidden.
        if isBullet { lines[line].markers.append(marker) }
    }

    /// Blank lines, the `>` markers of quoted lines, alignment and highlights.
    mutating func finish() {
        defer { markAlignment() }
        markHighlights()
        for index in lines.indices {
            let line = lines[index]
            if line.kind == .body, line.list == nil,
               text.substring(with: line.range).allSatisfy({ $0 == " " || $0 == "\t" }) {
                lines[index].kind = .blank
            }
            if line.quoteDepth > 0, let quote = match(Patterns.quoteMarker, in: line.range) {
                lines[index].markers.insert(quote, at: 0)
            }
        }
    }

    /// Lines between `<div align="center">` (or `right`, `left`) and `</div>` take that alignment;
    /// the tag lines are symbols.
    private mutating func markAlignment() {
        var open: MarkdownAnalysis.Alignment?
        for index in lines.indices {
            if case .code = lines[index].kind { continue }
            let range = lines[index].range
            if open == nil, let match = Patterns.alignOpen.firstMatch(in: text as String, range: range) {
                open = MarkdownAnalysis.Alignment(rawValue: text.substring(with: match.range(at: 1)).lowercased())
                lines[index].kind = .alignTag
                lines[index].markers = [range]
            } else if open != nil, Patterns.alignClose.firstMatch(in: text as String, range: range) != nil {
                lines[index].kind = .alignTag
                lines[index].markers = [range]
                open = nil
            } else if let open {
                lines[index].alignment = open
            }
        }
    }

    /// Finds `==text==` on text lines, outside code. The parser leaves the `=` signs as plain text.
    private mutating func markHighlights() {
        let code = spans.filter { $0.style == .code }.map(\.range)
        for line in lines {
            switch line.kind {
            case .code, .table, .divider, .blank: continue
            default: break
            }
            guard line.range.length >= 5 else { continue }
            for match in Patterns.highlight.matches(in: text as String, range: line.range) {
                let whole = match.range
                guard !code.contains(where: { NSIntersectionRange($0, whole).length > 0 }) else { continue }
                spans.append(.init(range: NSRange(location: whole.location + 2, length: whole.length - 4), style: .highlight))
                spans.append(.init(range: NSRange(location: whole.location, length: 2), style: .marker))
                spans.append(.init(range: NSRange(location: NSMaxRange(whole) - 2, length: 2), style: .marker))
            }
        }
    }

    // MARK: Helpers

    private func contentRange(of line: Int) -> NSRange {
        lines[line].range
    }

    private func backticks(at location: Int, limit: Int) -> Int {
        var count = 0
        while count < limit, text.character(at: location + count) == 0x60 { count += 1 }
        return count
    }

    private func match(_ regex: NSRegularExpression, in range: NSRange) -> NSRange? {
        let found = regex.firstMatch(in: text as String, range: range)?.range
        return found.flatMap { $0.location == NSNotFound ? nil : $0 }
    }
}

/// The line patterns the parse doesn't give positions for (where a heading's `#`s or a list's marker end).
nonisolated private enum Patterns {
    static let atxOpening = regex(#"^ {0,3}#{1,6}(?:[ \t]+|$)"#)
    static let atxClosing = regex(#"(?:^|[ \t]+)#+[ \t]*$"#)
    static let fenceStart = regex(#"^[ \t>]*(?:```|~~~)"#)
    static let fenceLine = regex(#"^[ \t>]*(?:```|~~~)[ \t]*$"#)
    static let listMarker = regex(#"^(?:[-*+]|\d{1,9}[.)])(?:[ \t]+|$)"#)
    static let taskBox = regex(#"^\[[ xX]\][ \t]?"#)
    static let highlight = regex(#"==(?=[^\s=])(?:[^=]|=(?!=))*?(?<=[^\s=])=="#)
    static let alignOpen = try! NSRegularExpression(pattern: #"^[ \t]*<div[ \t]+align=["']?(left|center|right)["']?[ \t]*>[ \t]*$"#,
                                                   options: [.caseInsensitive])
    static let alignClose = try! NSRegularExpression(pattern: #"^[ \t]*</div>[ \t]*$"#, options: [.caseInsensitive])
    static let quoteMarker = regex(#"^(?:[ \t]*>[ \t]?)+"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Searches cover one line or the rest of one, and `^` and `$` match at the search's edges.
        try! NSRegularExpression(pattern: pattern)
    }
}

// MARK: - Source positions

/// Converts swift-markdown's positions (line, and column in UTF-8 bytes) into UTF-16 offsets, and
/// splits the text into lines the way the parser does (`\n`, `\r\n` or `\r`).
nonisolated private struct SourceMap {
    struct LineRange {
        var range: NSRange
        var fullRange: NSRange
    }

    /// The UTF-16 offset of each UTF-8 byte offset (one more entry for the end of the text).
    private var utf16Offsets: [Int] = []
    /// The UTF-8 offset where each line starts.
    private var lineStartsUTF8: [Int] = []
    private(set) var lines: [LineRange] = []

    init(_ text: String) {
        let bytes = Array(text.utf8)
        utf16Offsets.reserveCapacity(bytes.count + 1)
        var utf16 = 0
        for scalar in text.unicodeScalars {
            let width = scalar.utf16.count
            for _ in 0..<scalar.utf8.count { utf16Offsets.append(utf16) }
            utf16 += width
        }
        utf16Offsets.append(utf16)

        var start = 0, index = 0
        while index <= bytes.count {
            var breakLength = 0
            if index == bytes.count {
                breakLength = -1
            } else if bytes[index] == 0x0A {
                breakLength = 1
            } else if bytes[index] == 0x0D {
                breakLength = index + 1 < bytes.count && bytes[index + 1] == 0x0A ? 2 : 1
            }
            if breakLength != 0 {
                let end = index, fullEnd = index + max(breakLength, 0)
                lineStartsUTF8.append(start)
                lines.append(LineRange(
                    range: NSRange(location: utf16Offsets[start], length: utf16Offsets[end] - utf16Offsets[start]),
                    fullRange: NSRange(location: utf16Offsets[start], length: utf16Offsets[fullEnd] - utf16Offsets[start])))
                if breakLength < 0 { break }
                start = fullEnd
                index = fullEnd
            } else {
                index += 1
            }
        }
    }

    func offset(_ location: SourceLocation) -> Int? {
        let line = location.line - 1
        guard lines.indices.contains(line) else { return nil }
        let byte = min(lineStartsUTF8[line] + location.column - 1, utf16Offsets.count - 1)
        return utf16Offsets[max(byte, 0)]
    }

    func range(_ sourceRange: SourceRange?) -> NSRange? {
        guard let sourceRange, let start = offset(sourceRange.lowerBound), let end = offset(sourceRange.upperBound),
              end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The lines a node covers (0-based).
    func lineSpan(_ sourceRange: SourceRange?) -> ClosedRange<Int> {
        guard let sourceRange else { return 0...0 }
        let first = max(sourceRange.lowerBound.line - 1, 0)
        var last = sourceRange.upperBound.line - 1
        if sourceRange.upperBound.column == 1, last > first { last -= 1 }
        return first...min(max(last, first), lines.count - 1)
    }
}
