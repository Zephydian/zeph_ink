import AppKit

/// The text view every editor uses: draws the page on its desk and handles markdown input (lists
/// continue on Return, Tab indents them, checkboxes tick on click).
///
/// Every change goes through `replace(_:with:)`, so it can be undone like typing.
final class ZephTextView: NSTextView {
    /// The editor this view belongs to, for the markdown it has worked out.
    weak var editor: Editor?

    // MARK: - The page

    /// The page's rectangle in this view: centered, at most `Theme.pageMaxWidth` wide, and at least as
    /// tall as the visible area.
    private var pageRect: NSRect {
        let isNarrow = bounds.width < Theme.narrowWidth
        let desk = isNarrow ? Theme.narrowDeskMargin : Theme.deskMargin
        let width = min(Theme.pageMaxWidth, bounds.width - desk.width * 2)
        return NSRect(x: ((bounds.width - width) / 2).rounded(), y: desk.height,
                      width: width, height: max(bounds.height - desk.height * 2, 0))
    }

    /// Places the text inside the page whenever the view's width changes.
    private func updateTextInset() {
        let isNarrow = bounds.width < Theme.narrowWidth
        let padding = isNarrow ? Theme.narrowPagePadding : Theme.pagePadding
        let desk = isNarrow ? Theme.narrowDeskMargin : Theme.deskMargin
        let inset = NSSize(width: pageRect.minX + padding.width, height: desk.height + padding.height)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextInset()
    }

    override func drawBackground(in rect: NSRect) {
        Theme.desk.setFill()
        rect.fill()
        let page = pageRect
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(effectiveAppearance.isDark ? 0.35 : 0.08)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        Theme.page.setFill()
        NSBezierPath(roundedRect: page, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let task = editor?.drawnCheckbox(near: characterIndexForInsertion(at: point)) {
            toggleCheckbox(task)
            return
        }
        super.mouseDown(with: event)
    }

    /// Ticks or unticks the `[ ]` at `range` by changing the one character inside it.
    private func toggleCheckbox(_ range: NSRange) {
        let inside = NSRange(location: range.location + 1, length: 1)
        let isChecked = (string as NSString).substring(with: inside).lowercased() == "x"
        replace(inside, with: isChecked ? " " : "x")
    }

    // MARK: - Lists

    /// A list item at the start of a line: its indent, marker (with its number) and checkbox.
    private struct ListLine {
        var range: NSRange
        var indent: String
        var bullet: String?
        var number: Int?
        var delimiter = ""
        var spacing: String
        var hasTask: Bool
        var contentStart: Int

        /// How far a nested item sits under this one: the marker's width.
        var nestingWidth: Int { (bullet?.count ?? "\(number ?? 1)\(delimiter)".count) + spacing.count }
    }

    private static let listPattern = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)

    private func listLine(at location: Int) -> ListLine? {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        let content = NSRange(location: line.location, length: line.length - trailingBreakLength(of: line))
        guard let match = Self.listPattern.firstMatch(in: string, range: content) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        return ListLine(range: content, indent: group(1) ?? "", bullet: group(2), number: group(3).flatMap { Int($0) },
                        delimiter: group(4) ?? "", spacing: group(5) ?? " ", hasTask: group(6) != nil,
                        contentStart: NSMaxRange(match.range))
    }

    private func trailingBreakLength(of line: NSRange) -> Int {
        let text = string as NSString
        guard line.length > 0 else { return 0 }
        let last = text.character(at: NSMaxRange(line) - 1)
        if last == 0x0A {
            return line.length > 1 && text.character(at: NSMaxRange(line) - 2) == 0x0D ? 2 : 1
        }
        return last == 0x0D ? 1 : 0
    }

    /// Return in a list item starts the next item. Return in an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard editor?.handlesMarkdownInput == true, let item = listLine(at: selection.location),
              selection.location >= item.contentStart else {
            super.insertNewline(sender)
            return
        }
        let rest = NSRange(location: item.contentStart, length: NSMaxRange(item.range) - item.contentStart)
        let isEmpty = (string as NSString).substring(with: rest).trimmingCharacters(in: .whitespaces).isEmpty
        if isEmpty && selection.length == 0 {
            replace(NSRange(location: item.range.location, length: item.range.length), with: "")
            return
        }
        var next = item.indent
        if let bullet = item.bullet { next += bullet } else { next += "\((item.number ?? 0) + 1)\(item.delimiter)" }
        next += item.spacing
        if item.hasTask { next += "[ ] " }
        replace(selection, with: lineBreak + next)
    }

    /// The line break the document already uses, so a new line matches its neighbours.
    private var lineBreak: String {
        let text = string as NSString
        let found = text.range(of: "\n")
        if found.location != NSNotFound, found.location > 0, text.character(at: found.location - 1) == 0x0D { return "\r\n" }
        if found.location == NSNotFound, text.range(of: "\r").location != NSNotFound { return "\r" }
        return "\n"
    }

    override func insertTab(_ sender: Any?) {
        if !indentListLines(outdent: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !indentListLines(outdent: true) { super.insertBacktab(sender) }
    }

    /// Tab and Shift-Tab on list items nest them one level deeper or bring them back out, for every
    /// selected line that's a list item. Returns false when no selected line is.
    private func indentListLines(outdent: Bool) -> Bool {
        guard editor?.handlesMarkdownInput == true else { return false }
        let text = string as NSString
        let lines = text.lineRange(for: selectedRange())
        var items: [ListLine] = []
        var location = lines.location
        repeat {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            if let item = listLine(at: location) { items.append(item) }
            location = NSMaxRange(line)
        } while location < NSMaxRange(lines)
        guard !items.isEmpty else { return false }

        var edits: [(NSRange, String)] = []
        for item in items {
            let start = item.range.location
            if outdent {
                let removable = item.indent.hasPrefix("\t") ? 1 : min(item.indent.prefix { $0 == " " }.count, item.nestingWidth)
                if removable > 0 { edits.append((NSRange(location: start, length: removable), "")) }
            } else {
                edits.append((NSRange(location: start, length: 0), String(repeating: " ", count: item.nestingWidth)))
            }
        }
        guard !edits.isEmpty else { return true }
        undoManager?.beginUndoGrouping()
        for (range, replacement) in edits.reversed() { replace(range, with: replacement) }
        undoManager?.endUndoGrouping()
        return true
    }

    // MARK: - Editing

    /// Changes text the way typing does: undoable, and the selection follows.
    func replace(_ range: NSRange, with replacement: String) {
        guard shouldChangeText(in: range, replacementString: replacement), let textStorage else { return }
        textStorage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
