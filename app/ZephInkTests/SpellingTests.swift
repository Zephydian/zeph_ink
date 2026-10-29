import AppKit
import Testing
@testable import ZephInk

/// The spell checker marks words of writing only, never markdown.
@MainActor
struct SpellingTests {
    /// Whether the word `word` (its first appearance after `after`) may be marked in `text`.
    private func allows(_ word: String, in text: String, after: String = "") -> Bool {
        let ns = text as NSString
        let start = after.isEmpty ? 0 : NSMaxRange(ns.range(of: after))
        let range = ns.range(of: word, range: NSRange(location: start, length: ns.length - start))
        precondition(range.location != NSNotFound, "\(word) is in the text")
        return Spelling.allows(range, in: ns, analysis: MarkdownAnalysis(text))
    }

    @Test func wordsOfWritingAreChecked() {
        #expect(allows("wrold", in: "Hello wrold."))
        #expect(allows("wrold", in: "Some **wrold** in bold."))     // the word, not the stars
        #expect(allows("wrold", in: "## A wrold heading"))
        #expect(allows("wrold", in: "- [ ] a wrold task"))
        #expect(allows("wrold", in: "[the wrold](https://zephydian.com)"))    // a link's words
        #expect(allows("wrold", in: "| a wrold | cell |\n| --- | --- |\n| x | y |"))
    }

    @Test func codeIsNotChecked() {
        #expect(!allows("wrold", in: "Run `wrold` now."))
        #expect(!allows("wrold", in: "```\nlet wrold = 1\n```"))
        #expect(!allows("wrold", in: "    indented wrold code"))
    }

    @Test func addressesAreNotChecked() {
        #expect(!allows("zephydian", in: "[site](https://zephydian.com/wrold)"))
        #expect(!allows("wrold", in: "[site](https://zephydian.com/wrold)"))
        #expect(!allows("harbr", in: "![A picture](assets/harbr.jpg)"))
        #expect(!allows("wrold", in: "[site]: https://wrold.com"))
        #expect(!allows("wrold", in: "Go to https://wrold.example.com today."))
        #expect(!allows("wrold", in: "Write to me@wrold.com today."))
    }

    @Test func frontMatterAndHTMLAreNotChecked() {
        #expect(!allows("wrold", in: "---\ntitle: wrold\n---\nBody"))
        #expect(!allows("div", in: "<div align=\"center\">\n\nText\n\n</div>"))
        #expect(!allows("spn", in: "Some <spn class=\"x\">text</spn> here."))
        #expect(allows("txet", in: "Some <span>txet</span> here."))     // the words inside a tag pair are writing
    }

    @Test func theEditorVetoesUnderlinesOutsideWriting() throws {
        Fonts.register()
        let document = MarkdownDocument()
        try document.read(from: Data("Hello wrold.\n\nRun `wrold` now.".utf8), ofType: "net.daringfireball.markdown")
        let editor = Editor(document: document)
        let flag = 1   // NSSpellingStateSpellingFlag
        #expect(editor.textView(editor.textView, shouldSetSpellingState: flag, range: NSRange(location: 6, length: 5)) == flag)
        #expect(editor.textView(editor.textView, shouldSetSpellingState: flag, range: NSRange(location: 19, length: 5)) == 0)
    }

    /// A system-wide default can stop every text view checking as you type (it did on the owner's Mac,
    /// so Zeph#Ink never underlined anything). Zeph#Ink's own setting must win.
    @Test func checkingWhileTypingIsOnInTheEditor() throws {
        let previous = UserDefaults.standard.object(forKey: Preferences.Key.checksSpelling)
        defer { UserDefaults.standard.set(previous, forKey: Preferences.Key.checksSpelling) }
        UserDefaults.standard.removeObject(forKey: Preferences.Key.checksSpelling)
        let document = MarkdownDocument()
        try document.read(from: Data("Hello".utf8), ofType: "net.daringfireball.markdown")
        #expect(Editor(document: document).textView.isContinuousSpellCheckingEnabled)
    }

    @Test func appKitFindsTheEditorsSpellingMethods() throws {
        let document = MarkdownDocument()
        let editor = Editor(document: document)
        #expect(editor.responds(to: NSSelectorFromString("textView:didCheckTextInRange:types:options:results:orthography:wordCount:")))
        #expect(editor.responds(to: NSSelectorFromString("textView:shouldSetSpellingState:range:")))
    }

    @Test func macOSResultsAreFilteredForTheEditor() throws {
        Fonts.register()
        let text = "Hello wrold.\n\nRun `wrold` now, see [x](https://wrold.com)."
        let document = MarkdownDocument()
        try document.read(from: Data(text.utf8), ofType: "net.daringfireball.markdown")
        let editor = Editor(document: document)
        let ns = text as NSString
        let results = NSSpellChecker.shared.check(text, range: NSRange(location: 0, length: ns.length),
                                                  types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                                  options: nil, inSpellDocumentWithTag: 0, orthography: nil, wordCount: nil)
        let kept = editor.textView(editor.textView, didCheckTextIn: NSRange(location: 0, length: ns.length),
                                   types: NSTextCheckingResult.CheckingType.spelling.rawValue, results: results,
                                   orthography: NSOrthography.defaultOrthography(forLanguage: "en"), wordCount: 0)
        #expect(results.count >= 2)       // macOS flags "wrold" in the code and the address too
        #expect(kept.map { ns.substring(with: $0.range) } == ["wrold"])
        #expect(kept.first?.range.location == 6)
    }
}
