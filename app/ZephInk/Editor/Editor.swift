import AppKit

/// One document's text view and its scroll view, built on TextKit 2 around the document's own storage.
///
/// An editor lives as long as its tab, so switching tabs keeps each document's selection, scroll
/// position and undo history. It keeps the markdown styled as the text changes: each edit restyles
/// only the blocks it touched, unless it changed what kind of block a line is (typing `## ` or a code
/// fence), which restyles everything.
final class Editor: NSObject {
    let scrollView = NSScrollView()
    let textView: ZephTextView
    /// The layout manager only holds this weakly, so the editor keeps it.
    private let contentStorage = NSTextContentStorage()
    private let storage: NSTextStorage

    private(set) var analysis: MarkdownAnalysis
    /// Lines whose symbols show in Clean mode: the ones the selection is on.
    private var revealed: Set<Int> = []

    private weak var document: MarkdownDocument?
    /// A `.txt` document: always plain monospaced text, with no markdown styling or input rules.
    let isPlainText: Bool
    /// Called when this editor's text view takes the focus.
    var didBecomeFocused: (() -> Void)?
    /// The styles at the selection, for the toolbar and the Format menu.
    let formatting = FormattingState()

    /// The folder the document is saved in (images are found relative to it).
    var documentFolder: URL? { document?.fileURL?.deletingLastPathComponent() }
    var documentForImages: MarkdownDocument? { document }

    /// What Return inserts: the line break the file already uses.
    var lineBreak: String { document?.format.lineBreak ?? "\n" }

    /// Page view (styled) or source view (plain monospaced text). Each tab keeps its own.
    var isSourceMode = false {
        didSet {
            guard isSourceMode != oldValue else { return }
            formatting.isSourceMode = isSourceMode
            restyleAll()
        }
    }

    private var mode: MarkdownStyler.Mode {
        isSourceMode || isPlainText ? .source : .page(MarkdownSymbols.current)
    }

    /// The images this document shows, loaded once.
    private let images = ImageLoader()

    private var imageContext: MarkdownStyler.Images? {
        guard !isPlainText else { return nil }
        let folder = documentFolder
        return MarkdownStyler.Images(lookup: { [images] path in images.image(at: path, relativeTo: folder) },
                                     columnWidth: textView.textContainer?.size.width ?? Theme.pageMaxWidth)
    }

    /// Images were added, or the person allowed a folder: load them again.
    func imagesDidChange() {
        images.forget()
        restyleAll()
    }

    /// The person clicked "Click to show images from this folder".
    func requestImageAccess() {
        guard let folder = documentFolder, let window = textView.window else { return }
        FolderAccess.request(folder, reason: "Allow Zeph#Ink to show the images in this folder.", in: window) { [weak self] allowed in
            if allowed { self?.imagesDidChange() }
        }
    }

    private var imageResize: DispatchWorkItem?

    /// The text column changed width: images scale to fit it, so restyle the lines that show one.
    func textColumnDidResize() {
        guard !isPlainText, !isSourceMode, storage.string.contains("![") else { return }
        imageResize?.cancel()
        let resize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = storage.string as NSString
            storage.beginEditing()
            for (index, line) in analysis.lines.enumerated() where MarkdownStyler.imagePath(in: text.substring(with: line.range)) != nil {
                MarkdownStyler.apply(analysis, to: storage, lines: index...index, mode: mode, revealed: revealed, images: imageContext)
            }
            storage.endEditing()
        }
        imageResize = resize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: resize)
    }

    /// Whether Return, Tab and clicks act on markdown (lists, checkboxes).
    var handlesMarkdownInput: Bool { !isPlainText }

    init(document: MarkdownDocument) {
        storage = document.storage
        self.document = document
        isPlainText = document.isPlainText
        analysis = MarkdownAnalysis("")   // worked out by restyleAll() below
        contentStorage.textStorage = storage
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0   // the page's padding is the only margin
        layoutManager.textContainer = container
        textView = ZephTextView(frame: .zero, textContainer: container)
        super.init()

        layoutManager.delegate = self
        storage.delegate = self
        textView.delegate = self
        textView.editor = self

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = !isPlainText
        // Markdown is plain text: smart quotes, dashes and replacements would change what the person typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.drawsBackground = true
        textView.insertionPointColor = Theme.accent
        textView.selectedTextAttributes = [.backgroundColor: Theme.accentSoft]
        textView.setAccessibilityLabel("Document")

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.desk

        // The page fills the window even when the document is short.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidResize),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(symbolsDidChange),
                                               name: MarkdownSymbols.didChange, object: nil)
        restyleAll()
    }

    // MARK: - Styling

    private func restyleAll() {
        analysis = MarkdownAnalysis(storage.string)
        storage.beginEditing()
        MarkdownStyler.applyAll(analysis, to: storage, mode: mode, revealed: revealed, images: imageContext)
        storage.endEditing()
    }

    /// After an edit: works out the markdown again and restyles what the edit could have changed.
    private func restyle(afterEditing edited: NSRange, changeInLength delta: Int) {
        if let (updated, lines) = analysis.updated(afterEditing: edited, changeInLength: delta, in: storage.string) {
            analysis = updated
            revealed = linesTouching(edited)
            MarkdownStyler.apply(analysis, to: storage, lines: lines, mode: mode, revealed: revealed, images: imageContext)
            scheduleFullCheck()
            return
        }

        let old = analysis
        analysis = MarkdownAnalysis(storage.string)
        let lines = analysis.lines
        revealed = linesTouching(edited)
        let firstEdited = analysis.lineIndex(at: edited.location)
        let lastEdited = analysis.lineIndex(at: NSMaxRange(edited))

        // Did any line outside the edit change shape? Lines before it keep their index; lines after it
        // move by however many lines the edit added or removed.
        let shift = lines.count - old.lines.count
        var isLocal = firstEdited < old.lines.count
        for index in 0..<min(firstEdited, old.lines.count) where lines[index].shape != old.lines[index].shape {
            isLocal = false
            break
        }
        if isLocal, lastEdited + 1 < lines.count {
            for index in (lastEdited + 1)..<lines.count {
                let oldIndex = index - shift
                guard old.lines.indices.contains(oldIndex), lines[index].shape == old.lines[oldIndex].shape else {
                    isLocal = false
                    break
                }
            }
        }

        guard isLocal else {
            MarkdownStyler.applyAll(analysis, to: storage, mode: mode, revealed: revealed, images: imageContext)
            return
        }
        MarkdownStyler.apply(analysis, to: storage, lines: blockLines(around: firstEdited...lastEdited),
                             mode: mode, revealed: revealed, images: imageContext)
    }

    private func linesTouching(_ range: NSRange) -> Set<Int> {
        Set(analysis.lineIndex(at: range.location)...analysis.lineIndex(at: NSMaxRange(range)))
    }

    private var fullCheck: DispatchWorkItem?

    /// Half a second after typing stops, parses the whole text once and restyles any line the
    /// block-by-block updates got wrong (a link defined elsewhere, a paragraph that joined another).
    private func scheduleFullCheck() {
        fullCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in self?.runFullCheck() }
        fullCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
    }

    private func runFullCheck() {
        let full = MarkdownAnalysis(storage.string)
        defer { analysis = full }
        guard full.lines.count == analysis.lines.count else {
            analysis = full
            restyleAll()
            return
        }
        var changed = Set<Int>()
        for (index, (new, old)) in zip(full.lines, analysis.lines).enumerated()
        where new.shape != old.shape || new.markers != old.markers || new.list != old.list {
            changed.insert(index)
        }
        for span in Set(full.spans).symmetricDifference(Set(analysis.spans)) {
            changed.formUnion(full.lineIndex(at: span.range.location)...full.lineIndex(at: NSMaxRange(span.range)))
        }
        guard !changed.isEmpty else { return }
        analysis = full
        storage.beginEditing()
        for line in changed {
            MarkdownStyler.apply(full, to: storage, lines: blockLines(around: line...line), mode: mode, revealed: revealed, images: imageContext)
        }
        storage.endEditing()
    }

    /// The lines of the blocks that `lines` touch: inline styles can run across a block's lines.
    private func blockLines(around lines: ClosedRange<Int>) -> ClosedRange<Int> {
        let all = analysis.lines
        var first = lines.lowerBound, last = lines.upperBound
        if let block = all[first].block {
            while first > 0, all[first - 1].block == block { first -= 1 }
        }
        if let block = all[last].block {
            while last + 1 < all.count, all[last + 1].block == block { last += 1 }
        }
        return first...last
    }

    /// In Clean mode, shows the symbols of the lines the selection is on and hides the ones it left.
    private func updateRevealedLines() {
        guard mode == .page(.clean) else { return }
        let selection = textView.selectedRange()
        let now = Set(analysis.lineIndex(at: selection.location)...analysis.lineIndex(at: NSMaxRange(selection)))
        guard now != revealed else { return }
        let changed = now.symmetricDifference(revealed)
        revealed = now
        storage.beginEditing()
        for line in changed {
            MarkdownStyler.apply(analysis, to: storage, lines: line...line, mode: mode, revealed: revealed, images: imageContext)
        }
        storage.endEditing()
    }

    @objc private func symbolsDidChange() {
        guard !isSourceMode else { return }
        restyleAll()
    }

    @objc private func clipViewDidResize() {
        let height = scrollView.contentSize.height
        guard textView.minSize.height != height else { return }
        textView.minSize = NSSize(width: 0, height: height)
        if textView.frame.height < height { textView.setFrameSize(NSSize(width: textView.frame.width, height: height)) }
    }

    // MARK: - Checkboxes

    /// The `[ ]` of a checkbox drawn on the page at or next to a character index, if there is one.
    func drawnCheckbox(near index: Int) -> NSRange? {
        guard mode == .page(.clean), !analysis.lines.isEmpty else { return nil }
        let lineIndex = analysis.lineIndex(at: index)
        guard !revealed.contains(lineIndex), let task = analysis.lines[lineIndex].list?.task,
              index >= task.location, index <= NSMaxRange(task) else { return nil }
        return task
    }
}

// MARK: - Delegates

extension Editor: NSTextStorageDelegate {
    /// Runs inside the edit, before layout, so new text never shows unstyled.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(afterEditing: editedRange, changeInLength: delta)
    }
}

extension Editor: NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        updateRevealedLines()
        formatting.update(text: storage.string as NSString, selection: textView.selectedRange(), analysis: analysis)
        let selection = textView.selectedRange()
        if selection.length == 0, !analysis.lines.isEmpty {
            let line = analysis.lines[analysis.lineIndex(at: selection.location)]
            if line.range.length == 0 { textView.typingAttributes = MarkdownStyler.typingAttributes(for: line, mode: mode) }
        }
    }
}

extension Editor: NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        PageLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
