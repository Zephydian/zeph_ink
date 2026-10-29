import AppKit

/// A document laid out on paper, for Export as PDF and Print.
///
/// It's a copy of the text with its own TextKit 2 layout, so the open editor is never touched. The page
/// looks like the editor's page in the Light theme with every markdown symbol hidden, whatever the theme,
/// White Page, zoom or focus mode. Page size and margins match the Paper page style (`PageGeometry`).
/// The text is laid out as one long column, then cut into pages by `Pagination`.
final class PrintLayout: NSObject {
    let pageSize: NSSize
    let padding: NSEdgeInsets
    let title: String
    let showsPageNumbers: Bool
    private(set) var pages: [Pagination.Page] = []

    private let storage: NSTextStorage
    private let contentStorage = NSTextContentStorage()
    private let layoutManager = NSTextLayoutManager()
    /// Every laid-out line of the column, top to bottom.
    private var fragments: [NSTextLayoutFragment] = []

    /// The document as it is now, on `paper` (Export as PDF uses the PDF paper size setting; Print uses
    /// the paper chosen in Page Setup).
    convenience init(document: MarkdownDocument, paper: NSSize) {
        self.init(text: document.storage.string, isPlainText: document.isPlainText,
                  folder: document.fileURL?.deletingLastPathComponent(), title: document.name, paper: paper)
    }

    init(text: String, isPlainText: Bool, folder: URL?, title: String, paper: NSSize,
         margins: Preferences.Margins = Preferences.margins, pageNumbers: Bool = Preferences.pageNumbers) {
        let geometry = PageGeometry.make(style: .paper, margins: margins, paper: paper, custom: paper, viewWidth: .greatestFiniteMagnitude)
        pageSize = geometry.pageSize
        padding = geometry.padding
        self.title = title
        showsPageNumbers = pageNumbers
        storage = NSTextStorage(string: isPlainText ? text : Self.withoutFrontMatter(text))
        super.init()

        let width = pageSize.width - padding.left - padding.right
        let contentHeight = geometry.contentHeight
        contentStorage.textStorage = storage
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        layoutManager.delegate = self
        contentStorage.delegate = self

        Theme.printing {
            let analysis = MarkdownAnalysis(storage.string)
            let loader = ImageLoader()
            // Images the folder hasn't been allowed for are left out, rather than drawn as a prompt.
            let images = MarkdownStyler.Images(lookup: { path in
                if case .image(let image)? = loader.image(at: path, relativeTo: folder) { return .image(image) }
                return nil
            }, columnWidth: width, maxHeight: contentHeight - 40)
            storage.beginEditing()
            MarkdownStyler.applyAll(analysis, to: storage, mode: isPlainText ? .source : .page(.clean), images: isPlainText ? nil : images)
            storage.endEditing()

            layoutManager.ensureLayout(for: layoutManager.documentRange)
            layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: [.ensuresLayout]) { fragment in
                fragments.append(fragment)
                return true
            }
            pages = Pagination.pages(for: blocks(analysis: analysis, isPlainText: isPlainText, pageHeight: contentHeight), height: contentHeight)
        }
    }

    var pageCount: Int { pages.count }

    /// Front matter (the YAML block at the top) is information about the document, not part of it.
    static func withoutFrontMatter(_ text: String) -> String {
        let lines = MarkdownAnalysis(text).lines
        var end = 0
        for line in lines {
            guard case .frontMatter = line.kind else { break }
            end = NSMaxRange(line.fullRange)
        }
        return end == 0 ? text : (text as NSString).substring(from: end)
    }

    // MARK: - Blocks

    /// The column as blocks for `Pagination`: one per line of markdown, except that a short code block
    /// is one block, so it isn't split across pages.
    private func blocks(analysis: MarkdownAnalysis, isPlainText: Bool, pageHeight: CGFloat) -> [Pagination.Block] {
        let text = storage.string as NSString
        var blocks: [Pagination.Block] = []
        var index = 0
        while index < fragments.count {
            let fragment = fragments[index]
            let frame = fragment.layoutFragmentFrame
            var block = Pagination.Block(top: frame.minY, bottom: frame.maxY)
            let lineBottoms = fragment.textLineFragments.map { frame.minY + $0.typographicBounds.maxY }
            guard !isPlainText, !analysis.lines.isEmpty else {
                block.breaks = Array(lineBottoms.dropLast())
                blocks.append(block)
                index += 1
                continue
            }
            let line = analysis.lines[analysis.lineIndex(at: offset(of: fragment))]
            switch line.kind {
            case .blank, .alignTag:
                block.isBlank = true
            case .heading:
                block.keepsWithNext = true
            case .code(let code) where code.isFirst:
                // The whole code block, if it's short enough to keep together.
                var last = index
                while last + 1 < fragments.count, !isLastCodeLine(fragments[last], analysis: analysis) { last += 1 }
                let bottom = fragments[last].layoutFragmentFrame.maxY
                if bottom - frame.minY <= pageHeight / 3 {
                    blocks.append(Pagination.Block(top: frame.minY, bottom: bottom))
                    index = last + 1
                    continue
                }
                block.keepsWithNext = code.isFence   // a fence never ends a page on its own
            case .divider:
                break
            default:
                // An image stays whole; a paragraph may break between its lines.
                if MarkdownStyler.imagePath(in: text.substring(with: line.range)) == nil {
                    block.breaks = Pagination.breaks(lineBottoms: lineBottoms)
                }
            }
            blocks.append(block)
            index += 1
        }
        return blocks
    }

    private func isLastCodeLine(_ fragment: NSTextLayoutFragment, analysis: MarkdownAnalysis) -> Bool {
        guard case .code(let code) = analysis.lines[analysis.lineIndex(at: offset(of: fragment))].kind else { return true }
        return code.isLast
    }

    private func offset(of fragment: NSTextLayoutFragment) -> Int {
        contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location)
    }

    // MARK: - Drawing

    /// Draws one page (0-based) into a flipped context whose origin is the page's top-left corner, with
    /// a matching flipped `NSGraphicsContext` current.
    func drawPage(_ index: Int, in context: CGContext) {
        guard pages.indices.contains(index) else { return }
        let page = pages[index]
        Theme.printing {
            context.saveGState()
            context.setFillColor(Theme.page.cgColor)
            context.fill(CGRect(origin: .zero, size: pageSize))
            // Lines a little outside the slice (a quote bar, a descender) can't show on two pages.
            context.clip(to: CGRect(x: 0, y: padding.top, width: pageSize.width, height: page.bottom - page.top))
            context.translateBy(x: padding.left, y: padding.top - page.top)
            for fragment in fragments {
                let frame = fragment.layoutFragmentFrame
                guard frame.maxY > page.top, frame.minY < page.bottom else { continue }
                fragment.draw(at: frame.origin, in: context)
            }
            context.restoreGState()
            if showsPageNumbers { drawPageNumber(index + 1) }
        }
    }

    private func drawPageNumber(_ number: Int) {
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular), .foregroundColor: Theme.inkSecondary,
        ])
        let size = text.size()
        let y = pageSize.height - min(padding.bottom, 72) / 2 - size.height / 2
        text.draw(at: NSPoint(x: ((pageSize.width - size.width) / 2).rounded(), y: y.rounded()))
    }

    /// The pages as a PDF, titled with the document's name.
    func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        let info = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Zeph#Ink"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }
        for index in pages.indices {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            drawPage(index, in: context)
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

extension PrintLayout: NSTextContentStorageDelegate {
    /// Each line is laid out without its hidden symbols, so they aren't in the PDF's text either
    /// (copying from the PDF, or searching it, finds the words, not `**` or `##`). Nothing edits this
    /// copy, so the text and what's laid out don't need to match.
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let storage = textContentStorage.textStorage else { return nil }
        let line = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var hidden: [NSRange] = []
        line.enumerateAttribute(.font, in: NSRange(location: 0, length: line.length)) { font, run, _ in
            if let font = font as? NSFont, font.pointSize < 0.1 { hidden.append(run) }
        }
        // A line that's all symbols keeps them: its look (an image, a fence's height) lives on its characters.
        let visible = NSMutableString(string: line.string)
        for run in hidden.reversed() { visible.deleteCharacters(in: run) }
        guard !hidden.isEmpty, !visible.trimmingCharacters(in: .newlines).isEmpty else { return nil }
        if let decoration = line.attribute(.lineDecoration, at: 0, effectiveRange: nil) as? LineDecoration,
           decoration.bullet != nil || decoration.task != nil {
            // Bullets and checkboxes are drawn at an offset into the line, which moves with what's removed.
            let moved = decoration.copy() as! LineDecoration
            func shift(_ offset: Int?) -> Int? {
                offset.map { offset in offset - hidden.filter { NSMaxRange($0) <= offset }.reduce(0) { $0 + $1.length } }
            }
            moved.bullet = shift(decoration.bullet)
            moved.task = shift(decoration.task)
            line.addAttribute(.lineDecoration, value: moved, range: NSRange(location: 0, length: line.length))
        }
        for run in hidden.reversed() { line.deleteCharacters(in: run) }
        return NSTextParagraph(attributedString: line)
    }
}

extension PrintLayout: NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        PageLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}

/// The view an `NSPrintOperation` prints (File → Print): the pages one under another.
final class PrintView: NSView {
    let layout: PrintLayout

    init(layout: PrintLayout) {
        self.layout = layout
        super.init(frame: NSRect(x: 0, y: 0, width: layout.pageSize.width, height: layout.pageSize.height * CGFloat(layout.pageCount)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: layout.pageCount)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: layout.pageSize.height * CGFloat(page - 1), width: layout.pageSize.width, height: layout.pageSize.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for index in 0..<layout.pageCount where rectForPage(index + 1).intersects(dirtyRect) {
            context.saveGState()
            context.translateBy(x: 0, y: rectForPage(index + 1).minY)
            layout.drawPage(index, in: context)
            context.restoreGState()
        }
    }
}
