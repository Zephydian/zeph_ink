import Foundation
import Testing
@testable import ZephInk

/// Formatted text pasted from other apps becomes markdown.
@MainActor
struct RichPasteTests {
    @Test func stylesBecomeMarkdown() {
        let html = "<p>Some <strong>bold</strong>, <em>italic</em>, <del>gone</del> and <code>code</code> with <a href=\"https://zephydian.com\">a link</a>.</p>"
        #expect(RichPaste.markdown(fromHTML: html) == "Some **bold**, *italic*, ~~gone~~ and `code` with [a link](https://zephydian.com).")
    }

    @Test func headingsListsAndQuotes() {
        let html = "<h1>Title</h1><h2><b>Heading</b></h2><ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul><ol><li>first</li><li>second</li></ol><blockquote><p>Quoted</p></blockquote><hr>"
        #expect(RichPaste.markdown(fromHTML: html)
                == "# Title\n\n## Heading\n\n- one\n- two\n  - nested\n\n1. first\n2. second\n\n> Quoted\n\n---")
    }

    @Test func googleDocsStylesAreRead() {
        let html = "<b style=\"font-weight:normal;\"><span style=\"font-weight:700\">Bold</span> and <span style=\"font-style:italic\">italic</span></b>"
        #expect(RichPaste.markdown(fromHTML: html) == "**Bold** and *italic*")
    }

    @Test func spacesStayOutsideTheSymbols() {
        #expect(RichPaste.markdown(fromHTML: "<p>a<b> bold </b>word</p>") == "a **bold** word")
    }

    @Test func textWithNothingToKeepPastesPlain() {
        // Code editors copy colored spans: no markdown styles, so the plain text is pasted instead.
        #expect(RichPaste.markdown(fromHTML: "<div><span style=\"color:#569cd6\">let</span> x = 1</div>") == nil)
    }
}
