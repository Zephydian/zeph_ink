import AppKit
import PDFKit
import Testing
@testable import ZephInk

/// Settings the export depends on, pinned for a test and put back (the tests share the app's settings).
@MainActor
func withExportSettings<Result>(_ values: [String: Any], _ body: () throws -> Result) rethrows -> Result {
    let keys = [Preferences.Key.textSize, Preferences.Key.margins, Preferences.Key.theme, Preferences.Key.whitePage] + values.keys
    var previous: [String: Any?] = [:]
    for key in keys { previous[key] = UserDefaults.standard.object(forKey: key) }
    defer { for (key, value) in previous { UserDefaults.standard.set(value, forKey: key) } }
    UserDefaults.standard.set(12.0, forKey: Preferences.Key.textSize)
    UserDefaults.standard.set(Preferences.Margins.normal.rawValue, forKey: Preferences.Key.margins)
    for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
    return try body()
}

/// Draws one page of a print layout into a bitmap, the way the PDF draws it.
@MainActor
func renderPage(_ layout: PrintLayout, _ index: Int, scale: CGFloat = 1) -> NSBitmapImageRep {
    let size = layout.pageSize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    layout.drawPage(index, in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Where printed pages break.
struct PaginationTests {
    private func block(_ top: CGFloat, _ bottom: CGFloat, breaks: [CGFloat] = [], heading: Bool = false, blank: Bool = false) -> Pagination.Block {
        Pagination.Block(top: top, bottom: bottom, breaks: breaks, keepsWithNext: heading, isBlank: blank)
    }

    @Test func blocksThatFitShareAPage() {
        let pages = Pagination.pages(for: [block(0, 40), block(40, 80)], height: 100)
        #expect(pages == [Pagination.Page(top: 0, bottom: 80)])
    }

    @Test func aBlockThatDoesNotFitMovesToTheNextPage() {
        let pages = Pagination.pages(for: [block(0, 60), block(60, 120)], height: 100)
        #expect(pages == [Pagination.Page(top: 0, bottom: 60), Pagination.Page(top: 60, bottom: 120)])
    }

    @Test func aParagraphBreaksBetweenItsLines() {
        let pages = Pagination.pages(for: [block(0, 60), block(60, 160, breaks: [80, 100, 120])], height: 100)
        #expect(pages.first == Pagination.Page(top: 0, bottom: 100))
        #expect(pages.last == Pagination.Page(top: 100, bottom: 160))
    }

    @Test func aHeadingIsNeverLeftAtTheBottomOfAPage() {
        let blocks = [block(0, 50), block(50, 60, blank: true), block(60, 80, heading: true), block(80, 90, blank: true), block(90, 140)]
        let pages = Pagination.pages(for: blocks, height: 100)
        #expect(pages.count == 2)
        #expect(pages[0].bottom == 50)
        #expect(pages[1].top == 60)    // the heading starts the next page
    }

    @Test func blankLinesNeverStartAPage() {
        let pages = Pagination.pages(for: [block(0, 90), block(90, 110, blank: true), block(110, 150)], height: 100)
        #expect(pages.count == 2)
        #expect(pages[1].top == 110)
    }

    @Test func somethingTallerThanAPageIsCut() {
        let pages = Pagination.pages(for: [block(0, 250)], height: 100)
        #expect(pages.map(\.top) == [0, 100, 200])
    }

    @Test func noWidowsOrOrphans() {
        #expect(Pagination.breaks(lineBottoms: [10, 20, 30]).isEmpty)
        #expect(Pagination.breaks(lineBottoms: [10, 20, 30, 40, 50]) == [20, 30])
    }

    @Test func anEmptyDocumentIsOnePage() {
        #expect(Pagination.pages(for: [], height: 100).count == 1)
    }
}

/// Export as PDF and printing.
@MainActor
struct PrintLayoutTests {
    private let letter = NSSize(width: 612, height: 792)
    private let a4 = NSSize(width: 595, height: 842)

    private var longDocument: String {
        var text = "# Report\n\n"
        for section in 1...6 {
            text += "## Section \(section)\n\n"
            for _ in 0..<4 {
                text += String(repeating: "Some **bold** words and some plain ones that fill a line. ", count: 6) + "\n\n"
            }
            text += "```\nlet x = \(section)\nprint(x)\n```\n\n"
        }
        return text
    }

    private func layout(_ text: String, paper: NSSize = NSSize(width: 612, height: 792), plain: Bool = false,
                        folder: URL? = nil) -> PrintLayout {
        PrintLayout(text: text, isPlainText: plain, folder: folder, title: "Report", paper: paper, margins: .normal, pageNumbers: true)
    }

    @Test func pagesAreThePaperSizeWithTheMargins() {
        withExportSettings([:]) {
            let page = layout("Hello", paper: a4)
            #expect(page.pageSize == a4)
            #expect(page.padding.top == 72 && page.padding.left == 72)
            #expect(layout("Hello").pageSize == letter)
        }
    }

    @Test func aLongDocumentFillsSeveralPagesThatEachFit() {
        withExportSettings([:]) {
            let print = layout(longDocument)
            #expect(print.pageCount > 2)
            let contentHeight = print.pageSize.height - print.padding.top - print.padding.bottom
            for page in print.pages {
                #expect(page.bottom - page.top <= contentHeight + 0.5)
            }
        }
    }

    @Test func thePDFHasEveryPageAndTheTitle() throws {
        try withExportSettings([:]) {
            let print = layout(longDocument)
            let pdf = try #require(PDFDocument(data: print.pdfData()))
            #expect(pdf.pageCount == print.pageCount)
            #expect(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Report")
            let page = try #require(pdf.page(at: 0))
            #expect(page.bounds(for: .mediaBox).size == letter)
            // Symbols are hidden: the text holds the words, not the markdown.
            let words = page.string ?? ""
            #expect(words.contains("Report"))
            #expect(words.contains("Some bold words"))
            #expect(!words.contains("**"))
            #expect(!words.contains("#"))
        }
    }

    @Test func frontMatterIsLeftOut() throws {
        try withExportSettings([:]) {
            #expect(PrintLayout.withoutFrontMatter("---\ntitle: X\n---\n# Hi\n") == "# Hi\n")
            let pdf = try #require(PDFDocument(data: layout("---\ntitle: Secret\n---\n# Hi\n").pdfData()))
            #expect(pdf.string?.contains("Secret") == false)
        }
    }

    @Test func pagesAreLightInADarkTheme() {
        withExportSettings([Preferences.Key.theme: Preferences.Theme.midnight.rawValue]) {
            let rep = renderPage(layout("# Title\n\nSome text on the page."), 0)
            let paper = rep.colorAt(x: 10, y: 10)!.usingColorSpace(.sRGB)!
            #expect(paper.brightnessComponent > 0.98)
            // Somewhere in the text area, dark ink.
            var darkest: CGFloat = 1
            for x in stride(from: 72, to: 400, by: 2) {
                for y in stride(from: 72, to: 140, by: 2) {
                    darkest = min(darkest, rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.brightnessComponent)
                }
            }
            #expect(darkest < 0.3)
        }
    }

    @Test func plainTextIsMonospaced() throws {
        try withExportSettings([:]) {
            let pdf = try #require(PDFDocument(data: layout("# not a heading\n**not bold**", plain: true).pdfData()))
            #expect(pdf.string?.contains("**not bold**") == true)
            #expect(pdf.string?.contains("# not a heading") == true)
        }
    }

    @Test func printingUsesThePrintView() throws {
        let view = PrintView(layout: layout("Hello"))
        var range = NSRange()
        #expect(view.knowsPageRange(&range))
        #expect(range == NSRange(location: 1, length: 1))
        #expect(view.rectForPage(1).size == letter)
    }
}

/// Edit → Copy as Rich Text.
@MainActor
struct RichCopyTests {
    @Test func markdownBecomesHTMLWithoutSymbols() {
        let html = RichCopy.html(for: "# Title\n\nSome **bold**, ==marked== and `==code==`.\n\n- [x] done\n- [ ] todo\n", folder: nil)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<mark>marked</mark>"))
        #expect(html.contains("<code>==code==</code>"))
        #expect(html.contains("<li>☑ done</li>"))
        #expect(html.contains("<li>☐ todo</li>"))
        #expect(!html.contains("**"))
    }

    @Test func theClipboardGetsHTMLRichTextAndPlainWords() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ZephInkRichCopyTest"))
        defer { pasteboard.releaseGlobally() }
        RichCopy.copy("Some **bold** text", folder: nil, to: pasteboard)
        #expect(pasteboard.string(forType: .html)?.contains("<strong>bold</strong>") == true)
        #expect(pasteboard.data(forType: .rtf) != nil)
        #expect(pasteboard.string(forType: .string) == "Some bold text")
    }
}
