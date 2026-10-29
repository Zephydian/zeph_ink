import Foundation

/// The formatting commands the toolbar, the Format menu and the shortcuts share. Each one works out the
/// markdown to insert or remove, as edits to the text plus the selection afterwards, the same
/// characters you could type yourself. `ZephTextView` applies them as one undoable change.
///
/// They work on plain text and an analysis, with no AppKit, so they're easy to test.
nonisolated enum MarkdownCommands {
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
    }

    struct Result: Equatable {
        /// Non-overlapping edits, in the coordinates of the text before any of them.
        var edits: [Edit]
        /// The selection after the edits.
        var selection: NSRange
    }

    // MARK: - Inline styles

    enum Inline: CaseIterable {
        case bold, italic, strikethrough, highlight, code

        var marker: String {
            switch self {
            case .bold: "**"
            case .italic: "*"
            case .strikethrough: "~~"
            case .highlight: "=="
            case .code: "`"
            }
        }

        var style: MarkdownAnalysis.InlineStyle {
            switch self {
            case .bold: .strong
            case .italic: .emphasis
            case .strikethrough: .strikethrough
            case .highlight: .highlight
            case .code: .code
            }
        }
    }

    /// The styled run the selection is in (or exactly covers), if any: its text and the symbols around it.
    static func span(of inline: Inline, at selection: NSRange, in text: NSString, analysis: MarkdownAnalysis)
        -> (content: NSRange, opening: NSRange, closing: NSRange)? {
        for span in analysis.spans where span.style == inline.style {
            var content = span.range
            let markerLength: Int
            if inline == .code {
                // A code span's range includes its backticks.
                var ticks = 0
                while ticks < content.length / 2, text.character(at: content.location + ticks) == 0x60 { ticks += 1 }
                content = NSRange(location: content.location + ticks, length: content.length - ticks * 2)
                markerLength = ticks
            } else {
                markerLength = (inline.marker as NSString).length
            }
            let outer = NSRange(location: content.location - markerLength, length: content.length + markerLength * 2)
            guard outer.location >= 0, NSMaxRange(outer) <= text.length else { continue }
            let inside = selection.location >= outer.location && NSMaxRange(selection) <= NSMaxRange(outer)
            guard inside else { continue }
            return (content, NSRange(location: outer.location, length: markerLength),
                    NSRange(location: NSMaxRange(content), length: markerLength))
        }
        return nil
    }

    /// Bold, italic, strikethrough or code: removes the style if the selection is in it, otherwise
    /// wraps the selection in it (or, with nothing selected, inserts the symbols with the cursor between).
    static func toggle(_ inline: Inline, text: NSString, selection: NSRange, analysis: MarkdownAnalysis) -> Result {
        if let (content, opening, closing) = span(of: inline, at: selection, in: text, analysis: analysis) {
            let start = max(selection.location, content.location) - opening.length
            let end = min(NSMaxRange(selection), NSMaxRange(content)) - opening.length
            return Result(edits: [Edit(range: closing, replacement: ""), Edit(range: opening, replacement: "")],
                          selection: NSRange(location: max(start, opening.location), length: max(end - max(start, opening.location), 0)))
        }
        let marker = inline.marker
        let length = (marker as NSString).length
        // Wrap the words, not the spaces around them (`** bold**` isn't bold in markdown).
        let trimmed = trimmingWhitespace(selection, in: text)
        if trimmed.length == 0 {
            return Result(edits: [Edit(range: selection, replacement: marker + marker)],
                          selection: NSRange(location: selection.location + length, length: 0))
        }
        return Result(edits: [Edit(range: NSRange(location: NSMaxRange(trimmed), length: 0), replacement: marker),
                              Edit(range: NSRange(location: trimmed.location, length: 0), replacement: marker)],
                      selection: NSRange(location: trimmed.location + length, length: trimmed.length))
    }

    // MARK: - Alignment

    typealias Alignment = MarkdownAnalysis.Alignment

    /// The `<div align>` and `</div>` lines around a line, if it's in an aligned region (the tag lines
    /// themselves count, since the cursor can be on them).
    static func alignedRegion(around index: Int, in analysis: MarkdownAnalysis) -> (opening: Int, closing: Int)? {
        let lines = analysis.lines
        guard lines.indices.contains(index) else { return nil }
        if lines[index].kind != .alignTag && lines[index].alignment == nil { return nil }
        // A tag line is the opening one if the line after it is inside the region.
        var opening = index, closing = index
        if lines[index].kind == .alignTag {
            if index + 1 < lines.count, lines[index + 1].alignment != nil || lines[index + 1].kind == .alignTag {
                closing = index + 1
            } else {
                opening = index - 1
            }
        }
        while opening >= 0, lines[opening].kind != .alignTag { opening -= 1 }
        while closing < lines.count, lines[closing].kind != .alignTag { closing += 1 }
        guard opening >= 0, closing < lines.count, opening < closing else { return nil }
        return (opening, closing)
    }

    /// Return on an empty line at the end of an aligned region: steps out of the region, so the new
    /// line starts at the left (like Return on an empty list item). Nil when that's not the case.
    static func leaveAlignment(at cursor: Int, text: NSString, analysis: MarkdownAnalysis, lineBreak: String) -> Result? {
        guard !analysis.lines.isEmpty else { return nil }
        let index = analysis.lineIndex(at: cursor)
        let line = analysis.lines[index]
        guard line.alignment != nil, line.range.length == 0, let (_, closing) = alignedRegion(around: index, in: analysis) else { return nil }
        // Only from the last line with text, or the blank lines after it.
        guard analysis.lines[(index + 1)..<closing].allSatisfy({ $0.kind == .blank }) else { return nil }
        let tag = analysis.lines[closing]
        let breakLength = (lineBreak as NSString).length
        // Remove the empty line, and start a new paragraph after `</div>`.
        let afterTag = NSMaxRange(tag.range)
        let insertion = lineBreak + lineBreak
        let edits = [Edit(range: NSRange(location: afterTag, length: 0), replacement: insertion),
                     Edit(range: line.fullRange.length > 0 ? line.fullRange : NSRange(location: line.range.location - breakLength, length: breakLength),
                          replacement: "")]
        let removed = edits[1].range.length
        return Result(edits: edits, selection: NSRange(location: afterTag + (insertion as NSString).length - removed, length: 0))
    }

    static func alignment(at location: Int, analysis: MarkdownAnalysis) -> Alignment {
        guard !analysis.lines.isEmpty else { return .left }
        return analysis.lines[analysis.lineIndex(at: location)].alignment ?? .left
    }

    /// Aligns the selected lines (or the cursor's line), leaving the lines around them as they were.
    /// Markdown has no alignment, so center and right wrap lines in `<div align="…">` with blank lines
    /// inside it (the form GitHub and others render), and left takes them out. Changing some lines of
    /// an aligned block splits the block, so its other lines keep their alignment.
    static func setAlignment(_ alignment: Alignment, text: NSString, selection: NSRange, analysis: MarkdownAnalysis,
                             lineBreak: String) -> Result {
        let lines = analysis.lines
        guard !lines.isEmpty else { return Result(edits: [], selection: selection) }
        let firstSelected = analysis.lineIndex(at: selection.location)
        let lastSelected = analysis.lineIndex(at: NSMaxRange(selection))

        // The lines to rewrite: a whole aligned block when the selection is in one, else the selection.
        var first = firstSelected, last = lastSelected
        var selected = Set(firstSelected...lastSelected)
        if let (opening, closing) = alignedRegion(around: firstSelected, in: analysis) {
            first = opening
            last = max(closing, alignedRegion(around: lastSelected, in: analysis)?.closing ?? closing)
            // On a tag or a blank line of the block: the whole block.
            if (firstSelected...lastSelected).allSatisfy({ lines[$0].kind == .alignTag || lines[$0].kind == .blank }) {
                selected = Set(first...last)
            }
        } else if let region = alignedRegion(around: lastSelected, in: analysis) {
            last = region.closing
        }

        // Each line with text, and the alignment it should end up with.
        struct Item { var index: Int; var alignment: Alignment }
        var items: [Item] = []
        for index in first...last where lines[index].kind != .alignTag {
            let current = lines[index].alignment ?? .left
            items.append(Item(index: index, alignment: selected.contains(index) && lines[index].kind != .blank ? alignment : current))
        }
        // Blank lines go with the run they sit in; at a change of alignment they're dropped.
        var runs: [(alignment: Alignment, items: [Item])] = []
        for item in items {
            if lines[item.index].kind == .blank {
                if let last = runs.last, !last.items.isEmpty { runs[runs.count - 1].items.append(item) }
                continue
            }
            if runs.last?.alignment == item.alignment { runs[runs.count - 1].items.append(item) }
            else { runs.append((item.alignment, [item])) }
        }
        guard !runs.isEmpty else { return Result(edits: [], selection: selection) }

        var output = ""
        var cursor: Int?
        let blank = lineBreak + lineBreak
        for (number, run) in runs.enumerated() {
            var body = run.items
            while let last = body.last, lines[last.index].kind == .blank { body.removeLast() }
            if number > 0 { output += blank }
            if run.alignment != .left { output += "<div align=\"\(run.alignment.rawValue)\">" + blank }
            for (position, item) in body.enumerated() {
                if position > 0 { output += lineBreak }
                let range = lines[item.index].range
                if cursor == nil, selection.location >= range.location, selection.location <= NSMaxRange(range) {
                    cursor = (output as NSString).length + selection.location - range.location
                }
                output += text.substring(with: range)
            }
            if run.alignment != .left { output += blank + "</div>" }
        }
        // Keep a blank line between an aligned block and text right next to it.
        let replaced = NSRange(location: lines[first].fullRange.location, length: NSMaxRange(lines[last].range) - lines[first].fullRange.location)
        var prefix = "", suffix = ""
        if runs.first?.alignment != .left, first > 0, lines[first - 1].kind != .blank { prefix = lineBreak }
        if runs.last?.alignment != .left, last + 1 < lines.count, lines[last + 1].kind != .blank { suffix = lineBreak }
        let replacement = prefix + output + suffix
        guard replacement != text.substring(with: replaced) else { return Result(edits: [], selection: selection) }
        // A cursor that was on a tag or blank line goes to the start, or the end if it was after the text.
        let firstText = items.first { lines[$0.index].kind != .blank }.map { lines[$0.index].range.location } ?? 0
        let fallback = selection.location <= firstText ? 0 : (output as NSString).length
        let location = replaced.location + (prefix as NSString).length + (cursor ?? fallback)
        return Result(edits: [Edit(range: replaced, replacement: replacement)], selection: NSRange(location: location, length: 0))
    }

    // MARK: - Return inside a style

    /// Return pressed inside bold, italic and the like: closes each style at the cursor, so the text
    /// before it keeps its look and the text after it starts plain. (`*hel|lo*` becomes `*hel*|lo`, and
    /// `*hello|*` becomes `*hello*|`.) A style the cursor is at the very start of comes off entirely.
    /// Returns nil when the cursor isn't inside a style on its line.
    static func closeInlineStyles(at cursor: Int, text: NSString, analysis: MarkdownAnalysis) -> Result? {
        let line = lines(touching: NSRange(location: cursor, length: 0), in: text)[0]
        var closers: [(opening: NSRange, closing: NSRange)] = []
        for inline in Inline.allCases {
            guard let (content, opening, closing) = span(of: inline, at: NSRange(location: cursor, length: 0), in: text, analysis: analysis),
                  cursor >= content.location, cursor <= NSMaxRange(content),
                  opening.location >= line.location, NSMaxRange(closing) <= NSMaxRange(line) else { continue }
            closers.append((opening, closing))
        }
        guard !closers.isEmpty else { return nil }
        var deleted: [NSRange] = []
        var insertion = ""
        // Innermost first: the style that opened last closes first.
        for (opening, closing) in closers.sorted(by: { $0.opening.location > $1.opening.location }) {
            deleted.append(closing)
            if NSMaxRange(opening) == cursor {
                deleted.append(opening)   // nothing styled before the cursor: drop the style
            } else {
                insertion += text.substring(with: closing)
            }
        }
        func keep(_ range: NSRange) -> String {
            var result = ""
            var position = range.location
            for cut in deleted.sorted(by: { $0.location < $1.location }) where cut.location >= range.location && NSMaxRange(cut) <= NSMaxRange(range) {
                if cut.location > position { result += text.substring(with: NSRange(location: position, length: cut.location - position)) }
                position = max(position, NSMaxRange(cut))
            }
            if NSMaxRange(range) > position { result += text.substring(with: NSRange(location: position, length: NSMaxRange(range) - position)) }
            return result
        }
        let before = keep(NSRange(location: line.location, length: cursor - line.location)) + insertion
        let after = keep(NSRange(location: cursor, length: NSMaxRange(line) - cursor))
        return Result(edits: [Edit(range: line, replacement: before + after)],
                      selection: NSRange(location: line.location + (before as NSString).length, length: 0))
    }

    // MARK: - Clearing

    /// Takes the markdown off the selected lines (or the line the cursor is on): heading, quote and
    /// list markers, and the symbols of bold, italic, links and the rest. The words stay.
    static func clearFormatting(text: NSString, selection: NSRange, analysis: MarkdownAnalysis) -> Result {
        let lines = lines(touching: selection, in: text)
        guard let first = lines.first, let last = lines.last else { return Result(edits: [], selection: selection) }
        let region = selection.length > 0 ? selection : NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var edits: [Edit] = []
        for line in lines {
            let prefix = prefix(of: text.substring(with: line))
            if prefix.contentStart > prefix.indent.utf16.count {
                edits.append(Edit(range: NSRange(location: line.location + prefix.indent.utf16.count,
                                                 length: prefix.contentStart - prefix.indent.utf16.count), replacement: ""))
            }
        }
        let prefixes = edits.map(\.range)
        let markers = analysis.spans.filter { span in
            span.style == .marker && NSIntersectionRange(span.range, region).length == span.range.length
                && !prefixes.contains { NSIntersectionRange($0, span.range).length > 0 }
        }
        edits += Set(markers.map(\.range)).map { Edit(range: $0, replacement: "") }
        func map(_ position: Int) -> Int {
            var mapped = position
            for edit in edits {
                if position >= NSMaxRange(edit.range) { mapped -= edit.range.length }
                else if position > edit.range.location { mapped -= position - edit.range.location }
            }
            return mapped
        }
        let start = map(selection.location), end = map(NSMaxRange(selection))
        return Result(edits: edits.sorted { $0.range.location > $1.range.location },
                      selection: NSRange(location: start, length: max(end - start, 0)))
    }

    // MARK: - Lines

    /// What starts a line: indentation, quote markers, a list marker (with its checkbox) and heading `#`s.
    struct LinePrefix: Equatable {
        enum List: Equatable {
            case bullet
            case numbered(Int)
            case checklist(checked: Bool)
        }

        var indent = ""
        var quote = ""
        var list: List?
        var heading = 0
        /// Where the line's own text starts, relative to the line.
        var contentStart = 0
    }

    private static let prefixPattern = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)*)(?:([-*+])[ \t]+(?:\[([ xX])\][ \t]+)?|(\d{1,9})[.)][ \t]+)?(#{1,6}(?:[ \t]+|$))?"#)

    static func prefix(of line: String) -> LinePrefix {
        let ns = line as NSString
        guard let match = prefixPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return LinePrefix() }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        var prefix = LinePrefix(indent: group(1) ?? "", quote: group(2) ?? "", contentStart: NSMaxRange(match.range))
        if group(3) != nil {
            if let box = group(4) { prefix.list = .checklist(checked: box != " ") } else { prefix.list = .bullet }
        } else if let number = group(5).flatMap({ Int($0) }) {
            prefix.list = .numbered(number)
        }
        if let hashes = group(6) { prefix.heading = hashes.prefix { $0 == "#" }.count }
        return prefix
    }

    /// The lines (content ranges, without line breaks) that the selection touches. A selection that
    /// ends at the very start of a line doesn't take that line.
    static func lines(touching selection: NSRange, in text: NSString) -> [NSRange] {
        var lines: [NSRange] = []
        var location = selection.location
        let end = NSMaxRange(selection)
        while true {
            var start = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&start, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: min(location, text.length), length: 0))
            lines.append(NSRange(location: start, length: contentsEnd - start))
            if lineEnd >= end || lineEnd >= text.length || lineEnd <= location { break }
            location = lineEnd
        }
        return lines
    }

    /// Rewrites the start of each selected line. The selection stays on the same text; a cursor that
    /// was inside a replaced prefix ends up after the new one.
    private static func rewriteLines(_ lines: [NSRange], in text: NSString, selection: NSRange,
                                     _ rewrite: (_ index: Int, _ line: String, _ prefix: LinePrefix) -> String?) -> Result {
        var edits: [Edit] = []
        for (index, line) in lines.enumerated() {
            let content = text.substring(with: line)
            let prefix = prefix(of: content)
            guard let newPrefix = rewrite(index, content, prefix) else { continue }
            let old = NSRange(location: line.location, length: prefix.contentStart)
            guard text.substring(with: old) != newPrefix else { continue }
            edits.append(Edit(range: old, replacement: newPrefix))
        }
        func map(_ position: Int) -> Int {
            var mapped = position
            for edit in edits {
                let newLength = (edit.replacement as NSString).length
                if position >= NSMaxRange(edit.range) {
                    mapped += newLength - edit.range.length
                } else if position >= edit.range.location {
                    mapped += edit.range.location + newLength - position
                }
            }
            return mapped
        }
        let start = map(selection.location)
        let end = map(NSMaxRange(selection))
        return Result(edits: edits.reversed(), selection: NSRange(location: start, length: max(end - start, 0)))
    }

    // MARK: - Paragraph styles

    enum Paragraph: CaseIterable {
        case title, heading, subheading, smallHeading, body, quote, codeBlock

        var headingLevel: Int {
            switch self {
            case .title: 1
            case .heading: 2
            case .subheading: 3
            case .smallHeading: 4
            default: 0
            }
        }
    }

    /// The paragraph style of the line holding a location, for the style menu.
    static func paragraph(at location: Int, in text: NSString, analysis: MarkdownAnalysis) -> Paragraph {
        guard !analysis.lines.isEmpty else { return .body }
        let line = analysis.lines[analysis.lineIndex(at: location)]
        switch line.kind {
        case .heading(let level): return [.title, .heading, .subheading, .smallHeading][min(level, 4) - 1]
        case .code: return .codeBlock
        default: return line.quoteDepth > 0 ? .quote : .body
        }
    }

    /// Title, headings and body replace a line's heading, quote and list markers. Quote adds or removes
    /// `> `. Code block puts ``` fences around the lines, or takes them away when already in a block.
    static func setParagraph(_ style: Paragraph, text: NSString, selection: NSRange, analysis: MarkdownAnalysis,
                             lineBreak: String) -> Result {
        let lines = lines(touching: selection, in: text)
        switch style {
        case .codeBlock:
            return toggleCodeBlock(lines, text: text, selection: selection, analysis: analysis, lineBreak: lineBreak)
        case .quote:
            let quoted = lines.allSatisfy { prefix(of: text.substring(with: $0)).quote.isEmpty == false }
            return rewriteLines(lines, in: text, selection: selection) { _, _, prefix in
                let list = listMarker(prefix.list, number: nil)
                let heading = prefix.heading > 0 ? String(repeating: "#", count: prefix.heading) + " " : ""
                return prefix.indent + (quoted ? "" : "> ") + list + heading
            }
        default:
            let level = style.headingLevel
            return rewriteLines(lines, in: text, selection: selection) { _, content, prefix in
                if level == 0 && prefix.heading == 0 && prefix.quote.isEmpty && prefix.list == nil { return nil }
                if content.trimmingCharacters(in: .whitespaces).isEmpty && level > 0 && lines.count > 1 { return nil }
                return prefix.indent + (level > 0 ? String(repeating: "#", count: level) + " " : "")
            }
        }
    }

    private static func toggleCodeBlock(_ lines: [NSRange], text: NSString, selection: NSRange,
                                        analysis: MarkdownAnalysis, lineBreak: String) -> Result {
        // Already in a fenced block: take its fences away.
        let index = analysis.lineIndex(at: selection.location)
        if case .code = analysis.lines[index].kind {
            var first = index, last = index
            while first > 0, case .code(let code) = analysis.lines[first].kind, !code.isFirst { first -= 1 }
            while last + 1 < analysis.lines.count, case .code(let code) = analysis.lines[last].kind, !code.isLast { last += 1 }
            var edits: [Edit] = []
            var removedBefore = 0
            if case .code(let code) = analysis.lines[last].kind, code.isFence, last != first {
                edits.append(Edit(range: analysis.lines[last].fullRange, replacement: ""))
            }
            if case .code(let code) = analysis.lines[first].kind, code.isFence {
                edits.append(Edit(range: analysis.lines[first].fullRange, replacement: ""))
                removedBefore = analysis.lines[first].fullRange.length
            }
            return Result(edits: edits, selection: NSRange(location: max(selection.location - removedBefore, 0), length: selection.length))
        }
        guard let first = lines.first, let last = lines.last else { return Result(edits: [], selection: selection) }
        let opening = "```" + lineBreak
        let closing = lineBreak + "```"
        let isEmptyLine = lines.count == 1 && first.length == 0
        if isEmptyLine {
            return Result(edits: [Edit(range: first, replacement: opening + closing)],
                          selection: NSRange(location: first.location + (opening as NSString).length, length: 0))
        }
        return Result(edits: [Edit(range: NSRange(location: NSMaxRange(last), length: 0), replacement: closing),
                              Edit(range: NSRange(location: first.location, length: 0), replacement: opening)],
                      selection: NSRange(location: selection.location + (opening as NSString).length, length: selection.length))
    }

    // MARK: - Lists

    enum ListKind: CaseIterable {
        case bulleted, numbered, checklist
    }

    /// The list a line belongs to, for the toolbar's active state.
    static func list(at location: Int, in text: NSString) -> ListKind? {
        let line = text.substring(with: lines(touching: NSRange(location: location, length: 0), in: text)[0])
        switch prefix(of: line).list {
        case .bullet: return .bulleted
        case .numbered: return .numbered
        case .checklist: return .checklist
        case nil: return nil
        }
    }

    /// Turns the selected lines into a list of this kind, or back into paragraphs when they already
    /// are one. Numbered lists count up from the item just above, or from 1.
    static func toggleList(_ kind: ListKind, text: NSString, selection: NSRange) -> Result {
        let lines = lines(touching: selection, in: text)
        let filled = lines.filter { !text.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty }
        let isAlready = !filled.isEmpty && filled.allSatisfy { line in
            switch (prefix(of: text.substring(with: line)).list, kind) {
            case (.bullet, .bulleted), (.numbered, .numbered), (.checklist, .checklist): true
            default: false
            }
        }
        var number = 1
        if let first = lines.first, first.location > 0 {
            let above = text.substring(with: Self.lines(touching: NSRange(location: first.location - 1, length: 0), in: text)[0])
            if case .numbered(let previous) = prefix(of: above).list { number = previous + 1 }
        }
        return rewriteLines(lines, in: text, selection: selection) { _, content, prefix in
            if lines.count > 1 && content.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            if isAlready { return prefix.indent + prefix.quote }
            let marker: String
            switch kind {
            case .bulleted: marker = "- "
            case .numbered: marker = "\(number). "; number += 1
            case .checklist:
                if case .checklist(let checked) = prefix.list { marker = checked ? "- [x] " : "- [ ] " } else { marker = "- [ ] " }
            }
            return prefix.indent + prefix.quote + marker
        }
    }

    private static func listMarker(_ list: LinePrefix.List?, number: Int?) -> String {
        switch list {
        case .bullet: "- "
        case .numbered(let n): "\(number ?? n). "
        case .checklist(let checked): checked ? "- [x] " : "- [ ] "
        case nil: ""
        }
    }

    // MARK: - Inserting blocks

    /// Puts a block (a divider, an image) on a line of its own: replaces an empty line, or goes after
    /// the current line with a blank line before it, so it never joins the paragraph above.
    static func insertBlock(_ block: String, text: NSString, selection: NSRange, lineBreak: String) -> Result {
        let line = lines(touching: NSRange(location: selection.location, length: 0), in: text)[0]
        let lineText = text.substring(with: line)
        if lineText.trimmingCharacters(in: .whitespaces).isEmpty {
            let isLastLine = NSMaxRange(line) == text.length
            let replacement = block + (isLastLine ? lineBreak : "")
            return Result(edits: [Edit(range: line, replacement: replacement)],
                          selection: NSRange(location: line.location + (replacement as NSString).length + (isLastLine ? 0 : (lineBreak as NSString).length), length: 0))
        }
        let insertion = lineBreak + lineBreak + block + lineBreak
        return Result(edits: [Edit(range: NSRange(location: NSMaxRange(line), length: 0), replacement: insertion)],
                      selection: NSRange(location: NSMaxRange(line) + (insertion as NSString).length, length: 0))
    }

    // MARK: - Links

    /// The link the selection is in: its whole `[text](url)` range, its text and its address.
    static func link(at selection: NSRange, in text: NSString, analysis: MarkdownAnalysis) -> (range: NSRange, text: String, url: String)? {
        for span in analysis.spans where span.style == .link {
            let content = span.range
            guard content.location >= 1, text.character(at: content.location - 1) == 0x5B else { continue }   // "["
            let after = NSMaxRange(content)
            guard after + 1 < text.length, text.character(at: after) == 0x5D, text.character(at: after + 1) == 0x28 else { continue }   // "]("
            let close = text.range(of: ")", options: [], range: NSRange(location: after + 2, length: text.length - after - 2))
            guard close.location != NSNotFound else { continue }
            let whole = NSRange(location: content.location - 1, length: NSMaxRange(close) - content.location + 1)
            guard selection.location >= whole.location, NSMaxRange(selection) <= NSMaxRange(whole) else { continue }
            let url = text.substring(with: NSRange(location: after + 2, length: close.location - after - 2))
            return (whole, text.substring(with: content), url)
        }
        return nil
    }

    /// Writes `[text](url)` over `range` (the selection, or the link being edited).
    static func setLink(text linkText: String, url: String, replacing range: NSRange) -> Result {
        let shown = linkText.isEmpty ? url : linkText
        let markdown = "[\(escapeBrackets(shown))](\(url.replacingOccurrences(of: " ", with: "%20")))"
        return Result(edits: [Edit(range: range, replacement: markdown)],
                      selection: NSRange(location: range.location + (markdown as NSString).length, length: 0))
    }

    private static func escapeBrackets(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    private static func trimmingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        let spaces = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(text.character(at: start)), spaces.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(text.character(at: end - 1)), spaces.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
