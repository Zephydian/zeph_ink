import AppKit
import Testing
@testable import ZephInk

/// The editor's styling and markdown input: what you see changes, the file only changes where you type.
@MainActor
struct EditorTests {
    private static let markdown = "net.daringfireball.markdown"

    private func editor(_ text: String) throws -> (MarkdownDocument, Editor) {
        Fonts.register()
        let document = MarkdownDocument()
        try document.read(from: Data(text.utf8), ofType: Self.markdown)
        return (document, Editor(document: document))
    }

    private func font(at location: Int, in document: MarkdownDocument) -> NSFont? {
        document.storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    // MARK: Styling

    @Test(arguments: ["welcome.md", "crlf.md", "no-trailing-newline.md", "bom-unicode.md"])
    func stylingNeverChangesTheFile(_ name: String) throws {
        let url = try #require(Bundle(for: EditorBundleToken.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        let original = try Data(contentsOf: url)
        let document = MarkdownDocument()
        try document.read(from: original, ofType: Self.markdown)
        let editor = Editor(document: document)
        editor.isSourceMode = true
        editor.isSourceMode = false
        #expect(try document.data(ofType: Self.markdown) == original)
    }

    @Test func cleanModeHidesSymbolsAwayFromTheSelection() throws {
        let previous = MarkdownSymbols.current
        defer { MarkdownSymbols.current = previous }
        MarkdownSymbols.current = .clean
        let (document, editor) = try editor("Intro\n\n## Heading with **bold**\n")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let text = document.storage.string as NSString
        let hash = text.range(of: "##").location
        let stars = text.range(of: "**").location
        let bold = text.range(of: "bold").location
        #expect(font(at: hash, in: document)?.pointSize == Fonts.hidden.pointSize)
        #expect(font(at: stars, in: document)?.pointSize == Fonts.hidden.pointSize)
        #expect(font(at: bold, in: document)?.pointSize == (Theme.bodySize * 1.42))

        // Moving onto the heading's line shows its symbols, faded.
        editor.textView.setSelectedRange(NSRange(location: bold, length: 0))
        #expect(font(at: hash, in: document)?.pointSize ?? 0 > 1)
        #expect(document.storage.attribute(.foregroundColor, at: hash, effectiveRange: nil) as? NSColor == Theme.marker)
    }

    @Test func fadedModeAlwaysShowsSymbols() throws {
        let previous = MarkdownSymbols.current
        defer { MarkdownSymbols.current = previous }
        MarkdownSymbols.current = .faded
        let (document, _) = try editor("Intro\n\n**bold**\n")
        let stars = (document.storage.string as NSString).range(of: "**").location
        #expect(font(at: stars, in: document)?.pointSize ?? 0 > 1)
        #expect(document.storage.attribute(.foregroundColor, at: stars, effectiveRange: nil) as? NSColor == Theme.marker)
    }

    @Test func sourceViewIsPlainMonospacedText() throws {
        let (document, editor) = try editor("# Title\n\n**bold**\n")
        editor.isSourceMode = true
        var fonts = Set<String>()
        document.storage.enumerateAttribute(.font, in: NSRange(location: 0, length: document.storage.length)) { value, _, _ in
            if let font = value as? NSFont { fonts.insert(font.fontName) }
        }
        #expect(fonts.count == 1)
        #expect(fonts.first?.hasPrefix("JetBrainsMono") == true)
    }

    @Test func typingKeepsStylingCurrent() throws {
        let (document, editor) = try editor("Intro\n\nplain\n")
        let end = (document.storage.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: end, length: 0))
        editor.textView.insertText("## New heading", replacementRange: editor.textView.selectedRange())
        let heading = (document.storage.string as NSString).range(of: "New").location
        #expect(font(at: heading, in: document)?.pointSize == (Theme.bodySize * 1.42))
    }

    // MARK: Lists

    private func pressReturn(in text: String, at location: Int? = nil) throws -> String {
        let (document, editor) = try editor(text)
        editor.textView.setSelectedRange(NSRange(location: location ?? (text as NSString).length, length: 0))
        editor.textView.insertNewline(nil)
        return document.storage.string
    }

    @Test func returnContinuesALists() throws {
        #expect(try pressReturn(in: "- one") == "- one\n- ")
        #expect(try pressReturn(in: "* one") == "* one\n* ")
        #expect(try pressReturn(in: "1. one") == "1. one\n2. ")
        #expect(try pressReturn(in: "9) one") == "9) one\n10) ")
        #expect(try pressReturn(in: "  - nested") == "  - nested\n  - ")
        #expect(try pressReturn(in: "- [x] done") == "- [x] done\n- [ ] ")
        #expect(try pressReturn(in: "- one\r\n- two") == "- one\r\n- two\r\n- ")
    }

    @Test func returnInTheMiddleOfAnItemSplitsIt() throws {
        #expect(try pressReturn(in: "- onetwo", at: 5) == "- one\n- two")
    }

    @Test func returnOnAnEmptyItemEndsTheList() throws {
        #expect(try pressReturn(in: "- one\n- ") == "- one\n")
        #expect(try pressReturn(in: "- one\n- [ ] ") == "- one\n")
    }

    @Test func returnOutsideAListIsAPlainLineBreak() throws {
        #expect(try pressReturn(in: "Just text") == "Just text\n")
        #expect(try pressReturn(in: "- one", at: 0) == "\n- one")
    }

    @Test func tabNestsListItemsAndShiftTabBringsThemBack() throws {
        let (document, editor) = try editor("- one\n- two\n1. three")
        let text = { document.storage.string }
        editor.textView.setSelectedRange(NSRange(location: 8, length: 0))
        editor.textView.insertTab(nil)
        #expect(text() == "- one\n  - two\n1. three")
        editor.textView.insertBacktab(nil)
        #expect(text() == "- one\n- two\n1. three")
        editor.textView.setSelectedRange(NSRange(location: 0, length: (text() as NSString).length))
        editor.textView.insertTab(nil)
        #expect(text() == "  - one\n  - two\n   1. three")
    }

    @Test func tabOutsideAListInsertsATab() throws {
        let (document, editor) = try editor("text")
        editor.textView.setSelectedRange(NSRange(location: 4, length: 0))
        editor.textView.insertTab(nil)
        #expect(document.storage.string == "text\t")
    }

    // MARK: Checkboxes

    @Test func checkboxesAreClickableOnlyWhereTheyAreDrawn() throws {
        let previous = MarkdownSymbols.current
        defer { MarkdownSymbols.current = previous }
        MarkdownSymbols.current = .clean
        let (document, editor) = try editor("Intro\n\n- [ ] task\n")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let box = (document.storage.string as NSString).range(of: "[ ]")
        #expect(editor.drawnCheckbox(near: box.location + 1) == box)
        #expect(editor.drawnCheckbox(near: 0) == nil)

        // On the line being edited the raw `[ ]` shows, and clicking it just places the cursor.
        editor.textView.setSelectedRange(NSRange(location: box.location + 5, length: 0))
        #expect(editor.drawnCheckbox(near: box.location + 1) == nil)
    }
}

private final class EditorBundleToken {}
