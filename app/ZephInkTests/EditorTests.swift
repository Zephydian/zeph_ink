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
        #expect(font(at: bold, in: document)?.pointSize == (Theme.headingBase * 1.42))

        // Moving onto the heading's line shows its symbols, faded.
        editor.textView.setSelectedRange(NSRange(location: bold, length: 0))
        #expect(font(at: hash, in: document)?.pointSize ?? 0 > 1)
        #expect(document.storage.attribute(.foregroundColor, at: hash, effectiveRange: nil) as? NSColor == Theme.marker)
    }

    @Test func alignedTextIsCenteredAndItsTagsHide() throws {
        let previous = MarkdownSymbols.current
        defer { MarkdownSymbols.current = previous }
        MarkdownSymbols.current = .clean
        let (document, editor) = try editor("Intro\n\n<div align=\"center\">\n\nMiddle\n\n</div>\n")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let text = document.storage.string as NSString
        let style = document.storage.attribute(.paragraphStyle, at: text.range(of: "Middle").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
        #expect(font(at: text.range(of: "<div").location, in: document)?.pointSize == Fonts.hidden.pointSize)
    }

    @Test func centeringOneLineLeavesItsNeighboursAlone() throws {
        let (document, editor) = try editor("one\ntwo\nthree")
        func alignment(of word: String) -> NSTextAlignment? {
            let text = document.storage.string as NSString
            return (document.storage.attribute(.paragraphStyle, at: text.range(of: word).location, effectiveRange: nil) as? NSParagraphStyle)?.alignment
        }
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.alignCenter(nil)
        #expect(alignment(of: "two") == .center)
        #expect(alignment(of: "one") != .center)
        #expect(alignment(of: "three") != .center)
        editor.textView.alignLeft(nil)
        #expect(alignment(of: "two") != .center)
        #expect(!document.storage.string.contains("<div"))
    }

    @Test func bodyTextFollowsTheSizeAndHeadingsDont() throws {
        let previous = UserDefaults.standard.object(forKey: Preferences.Key.textSize)
        defer { UserDefaults.standard.set(previous, forKey: Preferences.Key.textSize) }
        UserDefaults.standard.set(18.0, forKey: Preferences.Key.textSize)
        let (document, editor) = try editor("# Title\n\nBody words\n")
        editor.textView.setSelectedRange(NSRange(location: (document.storage.string as NSString).length, length: 0))
        let text = document.storage.string as NSString
        #expect(font(at: text.range(of: "Body").location, in: document)?.pointSize == 18)
        #expect(font(at: text.range(of: "Title").location, in: document)?.pointSize == Theme.headingBase * 2)
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
        #expect(font(at: heading, in: document)?.pointSize == (Theme.headingBase * 1.42))
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

    @Test func returnOutsideAListStartsAParagraph() throws {
        #expect(try pressReturn(in: "Just text") == "Just text\n\n")   // a new paragraph
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

/// Line breaks and `.txt` files in the editor.
@MainActor
struct EditorFileTests {
    private func editor(_ text: String, type: String = MarkdownDocument.markdownType) throws -> (MarkdownDocument, Editor) {
        Fonts.register()
        let document = MarkdownDocument()
        document.fileType = type
        try document.read(from: Data(text.utf8), ofType: type)
        return (document, Editor(document: document))
    }

    @Test func returnUsesTheFilesLineBreaks() throws {
        let (document, editor) = try editor("one\r\ntwo")
        editor.textView.setSelectedRange(NSRange(location: 8, length: 0))
        editor.textView.insertNewline(nil)     // a new paragraph: a blank line, then the new one
        editor.textView.insertLineBreak(nil)   // Shift-Return: one more line
        #expect(document.storage.string == "one\r\ntwo\r\n\r\n\r\n")
    }

    @Test func plainTextFilesAreMonospacedWithoutMarkdown() throws {
        let (document, editor) = try editor("# not a heading\n- not a list", type: MarkdownDocument.plainTextType)
        #expect(document.isPlainText)
        let font = document.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontName.hasPrefix("JetBrainsMono") == true)
        editor.textView.setSelectedRange(NSRange(location: (document.storage.string as NSString).length, length: 0))
        editor.textView.insertNewline(nil)
        #expect(document.storage.string == "# not a heading\n- not a list\n")
    }
}

/// Undo goes back one sensible step at a time: a paste, a formatting change. (Typing a word at a time
/// needs real key presses in a window in front, so it's checked by hand.)
@MainActor
struct UndoTests {
    /// Runs one "event" (a key press, a paste) in an undo group of its own, as AppKit does. Tests have
    /// no real events, so the grouping is done by hand.
    private func event(_ undo: UndoManager, _ action: () -> Void) {
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }

    private func workspace(_ text: String) throws -> (MarkdownDocument, ZephTextView, UndoManager) {
        Fonts.register()
        let document = MarkdownDocument()
        try document.read(from: Data(text.utf8), ofType: MarkdownDocument.markdownType)
        let controller = WorkspaceWindowController.makeNew()
        controller.add(document)
        let textView = try #require(controller.workspace.selectedTab?.editor.textView)
        // The text view gets its undo manager from the window, once SwiftUI has put it there.
        controller.window?.setContentSize(NSSize(width: 900, height: 600))
        for _ in 0..<20 where textView.window == nil {
            controller.window?.layoutIfNeeded()
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let undo = try #require(textView.undoManager)
        undo.groupsByEvent = false
        return (document, textView, undo)
    }

    private func type(_ text: String, into textView: ZephTextView, _ undo: UndoManager) {
        for character in text {
            event(undo) { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
        }
    }

    @Test func undoAfterAPasteTakesOnlyThePaste() throws {
        let (document, textView, undo) = try workspace("")
        type("# Title", into: textView, undo)
        event(undo) { textView.insertNewline(nil) }
        event(undo) { textView.insertAsOneStep("Pasted paragraph.", replacing: textView.selectedRange()) }
        undo.undo()
        #expect(document.storage.string == "# Title\n\n")
    }

    @Test func aFormattingChangeIsItsOwnStep() throws {
        let (document, textView, undo) = try workspace("")
        type("word", into: textView, undo)
        event(undo) {
            textView.setSelectedRange(NSRange(location: 0, length: 4))
            textView.toggleBold(nil)
        }
        undo.undo()
        #expect(document.storage.string == "word")
    }
}
