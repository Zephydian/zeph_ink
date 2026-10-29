import AppKit
import UniformTypeIdentifiers

/// The text view every editor uses: draws the page on its desk and handles markdown input (lists
/// continue on Return, Tab indents them, checkboxes tick on click).
///
/// Every change goes through `replace(_:with:)`, so it can be undone like typing.
final class ZephTextView: NSTextView {
    /// The editor this view belongs to, for the markdown it has worked out.
    weak var editor: Editor?

    // MARK: - Undo in sensible steps

    /// When the last character was typed, to start a new undo step after a pause.
    private var lastTyped = Date.distantPast

    /// Typing is undone a word at a time (and after a pause), like a word processor, instead of
    /// everything typed since the cursor last moved.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if Date().timeIntervalSince(lastTyped) > 1.5 { breakUndoCoalescing() }
        super.insertText(string, replacementRange: replacementRange)
        lastTyped = Date()
        if let last = typed.last, typed.count == 1, last.isWhitespace || ".,;:!?".contains(last) {
            breakUndoCoalescing()   // the word just finished is one step
        }
    }

    /// Inserts text as a step of its own (a paste, a line break, a formatting change).
    func insertAsOneStep(_ text: String, replacing range: NSRange) {
        breakUndoCoalescing()
        super.insertText(text, replacementRange: range)
        breakUndoCoalescing()
        lastTyped = .distantPast
    }

    // MARK: - The page

    /// The pages for this view's width and the current settings.
    private(set) var geometry = PageGeometry.current(viewWidth: 900)
    /// How many pages the text fills (always 1 for Continuous).
    private(set) var pageCount = 1

    /// Lays the text out on the pages again: after resizing, a settings change, or an edit.
    func updatePages() {
        let geometry = PageGeometry.current(viewWidth: bounds.width)
        let inset = geometry.textInset(viewWidth: bounds.width)
        let geometryChanged = geometry != self.geometry
        self.geometry = geometry
        if textContainerInset != inset {
            textContainerInset = inset
            editor?.textColumnDidResize()
        }
        updatePageBreaks(force: geometryChanged)
        if geometryChanged { needsDisplay = true }
    }

    /// Keeps an exclusion band at every page break the text reaches, plus one more for text about to
    /// flow onto a new page. Each change lays the text out again, so it only changes when needed.
    private func updatePageBreaks(force: Bool = false) {
        guard let container = textContainer else { return }
        guard geometry.isPaged else {
            if !container.exclusionPaths.isEmpty { container.exclusionPaths = [] }
            if pageCount != 1 { pageCount = 1; needsDisplay = true }
            visibleHeightDidChange()
            return
        }
        let used = textLayoutManager?.usageBoundsForTextContainer.height ?? 0
        let pages = geometry.pageCount(forTextHeight: used)
        let bands = geometry.breaks(pages: pages, width: container.size.width)
        let current = container.exclusionPaths.map(\.bounds)
        if force || current != bands {
            container.exclusionPaths = bands.map { NSBezierPath(rect: $0) }
            // TextKit 2 keeps the lines it already placed, so place them again from the first band that
            // changed (or the top), and the text flows around the new breaks.
            let firstChange = Array(zip(current, bands)).firstIndex { $0 != $1 } ?? min(current.count, bands.count)
            let top = firstChange < bands.count ? bands[firstChange].minY - geometry.contentHeight : 0
            if let layout = textLayoutManager {
                let start = layout.textLayoutFragment(for: CGPoint(x: 0, y: max(top, 0)))?.rangeInElement.location ?? layout.documentRange.location
                if let range = NSTextRange(location: start, end: layout.documentRange.endLocation) {
                    layout.invalidateLayout(for: range)
                }
                layout.textViewportLayoutController.layoutViewport()
            }
        }
        if pages != pageCount {
            pageCount = pages
            needsDisplay = true
        }
        visibleHeightDidChange()
    }

    /// The window got taller or shorter: a Continuous page reaches the bottom of it, and paged views
    /// stay tall enough for every page.
    func visibleHeightDidChange() {
        // In page points: at 50% zoom twice as much page shows as the window is tall.
        guard let clip = enclosingScrollView?.contentView.bounds.height else { return }
        let height = geometry.isPaged ? max(geometry.viewHeight(pages: pageCount), clip) : clip
        guard minSize.height != height else { return }
        minSize = NSSize(width: 0, height: height)
        if frame.height < height { setFrameSize(NSSize(width: frame.width, height: height)) }
    }

    /// The margins or page style changed.
    func pageMetricsDidChange() {
        updatePages()
        needsDisplay = true
    }

    /// The text changed: it may need more pages, or fewer.
    func textDidChangeLength() {
        guard geometry.isPaged else { return }
        updatePageBreaks()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePages()
    }

    override func drawBackground(in rect: NSRect) {
        Theme.desk.setFill()
        rect.fill()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(effectiveAppearance.isDark ? 0.35 : 0.08)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        Theme.page.setFill()
        for page in geometry.pageRects(count: pageCount, viewWidth: bounds.width, viewHeight: bounds.height)
        where page.intersects(rect.insetBy(dx: 0, dy: -40)) {
            NSBezierPath(roundedRect: page, xRadius: geometry.isPaged ? 2 : 4, yRadius: geometry.isPaged ? 2 : 4).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if event.modifierFlags.contains(.command), openLink(at: index) { return }
        if editor?.toggleFrontMatter(ifHeaderAt: index) == true { return }
        if isOnImageAccessPrompt(point) {
            editor?.requestImageAccess()
            return
        }
        if let task = editor?.drawnCheckbox(near: index) {
            toggleCheckbox(task)
            return
        }
        super.mouseDown(with: event)
    }

    private func isOnImageAccessPrompt(_ point: NSPoint) -> Bool {
        let inContainer = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard let fragment = textLayoutManager?.textLayoutFragment(for: inContainer) as? PageLayoutFragment else { return false }
        let local = CGPoint(x: inContainer.x - fragment.layoutFragmentFrame.minX, y: inContainer.y - fragment.layoutFragmentFrame.minY)
        return fragment.isOnAccessPrompt(local)
    }

    // MARK: - Dropping images

    /// Images dropped on a markdown document are copied into its `assets` folder and linked.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                              .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        guard editor?.handlesMarkdownInput == true, editor?.isSourceMode == false,
              let images = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !images.isEmpty else {
            return super.performDragOperation(sender)
        }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        ImageAssets.insert(images, into: self)
        return true
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

    /// Return in a list item starts the next item. Return in an empty item ends the list. Return inside
    /// bold, italic and the like closes them first, so the new line starts plain.
    override func insertNewline(_ sender: Any?) {
        if editor?.handlesMarkdownInput == true, selectedRange().length == 0, let editor,
           let closed = MarkdownCommands.closeInlineStyles(at: selectedRange().location, text: string as NSString, analysis: editor.analysis) {
            undoManager?.beginUndoGrouping()
            apply(closed)
            breakLine()
            undoManager?.endUndoGrouping()
            return
        }
        if editor?.handlesMarkdownInput == true, selectedRange().length == 0, let editor,
           let leave = MarkdownCommands.leaveAlignment(at: selectedRange().location, text: string as NSString,
                                                       analysis: editor.analysis, lineBreak: lineBreak) {
            apply(leave)
            return
        }
        breakLine()
    }

    private func breakLine() {
        let selection = selectedRange()
        guard editor?.handlesMarkdownInput == true, let item = listLine(at: selection.location),
              selection.location >= item.contentStart else {
            insertAsOneStep(startsParagraph(at: selection) ? lineBreak + lineBreak : lineBreak, replacing: selection)
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
    private var lineBreak: String { editor?.lineBreak ?? "\n" }

    /// Whether Return here starts a new paragraph (with a blank line before it, which is what spaces
    /// paragraphs apart in markdown): at the end of, or inside, a line of text, but not in code, a
    /// table, front matter, or on a line that's already empty.
    private func startsParagraph(at selection: NSRange) -> Bool {
        guard let editor, editor.handlesMarkdownInput, !editor.analysis.lines.isEmpty else { return false }
        let line = editor.analysis.lines[editor.analysis.lineIndex(at: selection.location)]
        guard line.range.length > 0, selection.location > line.range.location else { return false }
        switch line.kind {
        case .body, .heading: return line.quoteDepth == 0
        default: return false
        }
    }

    /// Shift-Return sends the same command as Return (insertNewline), so it's caught as a key here.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76   // Return, or Enter on the keypad
        if isReturn, event.modifierFlags.contains(.shift), !hasMarkedText() {
            insertLineBreak(nil)
            return
        }
        super.keyDown(with: event)
    }

    /// Shift-Return: a new line in the same paragraph, with no space before it. (NSTextView would insert
    /// a Unicode line separator, which markdown doesn't know.)
    override func insertLineBreak(_ sender: Any?) {
        insertAsOneStep(lineBreak, replacing: selectedRange())
    }

    /// Paste: formatted text (from a web page, Word, Google Docs…) arrives as markdown, so bold stays
    /// bold and headings stay headings. Plain text arrives as it is. Either way it takes the document's
    /// line breaks, so a file never ends up with a mix.
    override func paste(_ sender: Any?) {
        guard let editor else { return super.paste(sender) }
        let pasteboard = NSPasteboard.general
        if editor.handlesMarkdownInput, !editor.isSourceMode,
           let markdown = RichPaste.markdown(from: pasteboard, lineBreak: editor.lineBreak) {
            insertAsOneStep(markdown, replacing: selectedRange())
            return
        }
        pasteAsPlainText(sender)
    }

    /// Edit → Paste as Plain Text (⌘⇧V): the clipboard's words only, no formatting.
    override func pasteAsPlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), let editor else {
            super.pasteAsPlainText(sender)
            return
        }
        let normalized = FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: editor.lineBreak).normalizingLineBreaks(text)
        insertAsOneStep(normalized, replacing: selectedRange())
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { editor?.didBecomeFocused?() }
        return accepted
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

    // MARK: - Spelling

    /// Edit → Spelling and Grammar → Check Document Now (⌘;): selects the next misspelled word after
    /// the selection, skipping code, addresses and markdown, like the underlines do.
    override func checkSpelling(_ sender: Any?) {
        guard let editor, editor.handlesMarkdownInput else { return super.checkSpelling(sender) }
        let checker = NSSpellChecker.shared
        let text = string as NSString
        var start = NSMaxRange(selectedRange())
        var seen = Set<Int>()
        while true {
            let found = checker.checkSpelling(of: string, startingAt: start, language: nil, wrap: true,
                                              inSpellDocumentWithTag: spellCheckerDocumentTag, wordCount: nil)
            guard found.location != NSNotFound, seen.insert(found.location).inserted else { break }
            if Spelling.allows(found, in: text, analysis: editor.analysis) {
                setSelectedRange(found)
                scrollRangeToVisible(found)
                showFindIndicator(for: found)
                checker.updateSpellingPanel(withMisspelledWord: text.substring(with: found))
                return
            }
            start = NSMaxRange(found)
        }
        // Nothing left to correct.
        checker.updateSpellingPanel(withMisspelledWord: "")
    }

    /// Check Spelling While Typing applies to every document, and is remembered.
    override func toggleContinuousSpellChecking(_ sender: Any?) {
        UserDefaults.standard.set(!Preferences.checksSpelling, forKey: Preferences.Key.checksSpelling)
    }

    // MARK: - Editing

    /// Changes text the way typing does: undoable, and the selection follows.
    func replace(_ range: NSRange, with replacement: String) {
        breakUndoCoalescing()
        defer { breakUndoCoalescing() }
        guard shouldChangeText(in: range, replacementString: replacement), let textStorage else { return }
        textStorage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
