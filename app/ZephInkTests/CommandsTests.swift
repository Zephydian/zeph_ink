import Foundation
import Testing
@testable import ZephInk

/// The formatting commands: the markdown they write, and where the selection ends up.
@MainActor
struct CommandsTests {
    /// Runs a command on text whose selection is marked with `|` (a cursor) or `[` and `]` (a range),
    /// and returns the result marked the same way.
    private func run(_ marked: String, _ command: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result) -> String {
        var text = marked
        var selection = NSRange(location: 0, length: 0)
        if let cursor = text.range(of: "|") {
            selection.location = text.distance(from: text.startIndex, to: cursor.lowerBound)
            text.removeSubrange(cursor)
        } else if let open = text.range(of: "["), let close = text.range(of: "]", range: open.upperBound..<text.endIndex) {
            let start = (text as NSString).range(of: "[").location
            let end = (text as NSString).range(of: "]", options: [], range: NSRange(location: start, length: (text as NSString).length - start)).location
            text.removeSubrange(close)
            text.removeSubrange(open)
            selection = NSRange(location: start, length: end - start - 1)
        }
        let ns = NSMutableString(string: text)
        let result = command(text as NSString, selection, MarkdownAnalysis(text))
        for edit in result.edits { ns.replaceCharacters(in: edit.range, with: edit.replacement) }
        let out = NSMutableString(string: ns)
        if result.selection.length == 0 {
            out.insert("|", at: result.selection.location)
        } else {
            out.insert("]", at: NSMaxRange(result.selection))
            out.insert("[", at: result.selection.location)
        }
        return out as String
    }

    private func toggle(_ inline: MarkdownCommands.Inline) -> (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result {
        { MarkdownCommands.toggle(inline, text: $0, selection: $1, analysis: $2) }
    }

    private func paragraph(_ style: MarkdownCommands.Paragraph) -> (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result {
        { MarkdownCommands.setParagraph(style, text: $0, selection: $1, analysis: $2, lineBreak: "\n") }
    }

    private func list(_ kind: MarkdownCommands.ListKind) -> (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result {
        { text, selection, _ in MarkdownCommands.toggleList(kind, text: text, selection: selection) }
    }

    // MARK: Inline

    @Test func boldWrapsTheSelectedWords() {
        #expect(run("Some [bold ]words", toggle(.bold)) == "Some **[bold]** words")
        #expect(run("Some |", toggle(.bold)) == "Some **|**")
        #expect(run("x [code] y", toggle(.code)) == "x `[code]` y")
        #expect(run("x [gone] y", toggle(.strikethrough)) == "x ~~[gone]~~ y")
    }

    @Test func boldComesOffWhenTheSelectionIsInIt() {
        #expect(run("Some **bo|ld** words", toggle(.bold)) == "Some bo|ld words")
        #expect(run("Some **[bold]** words", toggle(.bold)) == "Some [bold] words")
        #expect(run("x `co|de` y", toggle(.code)) == "x co|de y")
        #expect(run("an *ita|lic* word", toggle(.italic)) == "an ita|lic word")
    }

    // MARK: Paragraphs

    @Test func headingsReplaceWhateverStartedTheLine() {
        #expect(run("Hel|lo", paragraph(.title)) == "# Hel|lo")
        #expect(run("## Hel|lo", paragraph(.subheading)) == "### Hel|lo")
        #expect(run("- Hel|lo", paragraph(.heading)) == "## Hel|lo")
        #expect(run("### Hel|lo", paragraph(.body)) == "Hel|lo")
        #expect(run("|", paragraph(.heading)) == "## |")
    }

    @Test func quoteTogglesOnEveryLine() {
        #expect(run("[one\ntwo]", paragraph(.quote)) == "> [one\n> two]")
        #expect(run("> [one\n> two]", paragraph(.quote)) == "[one\ntwo]")
    }

    @Test func codeBlockFencesTheLinesOrTakesTheFencesAway() {
        #expect(run("a\n[let x = 1]\nb", paragraph(.codeBlock)) == "a\n```\n[let x = 1]\n```\nb")
        #expect(run("|", paragraph(.codeBlock)) == "```\n|\n```")
        #expect(run("```\nlet |x = 1\n```\n", paragraph(.codeBlock)) == "let |x = 1\n")
    }

    @Test func theStyleMenuShowsTheLinesStyle() {
        let text = "# T\n\n## H\n\n> q\n\n```\nc\n```\n\nbody" as NSString
        let analysis = MarkdownAnalysis(text as String)
        func at(_ word: String) -> MarkdownCommands.Paragraph {
            MarkdownCommands.paragraph(at: text.range(of: word).location, in: text, analysis: analysis)
        }
        #expect(at("T") == .title)
        #expect(at("H") == .heading)
        #expect(at("q") == .quote)
        #expect(at("c\n") == .codeBlock)
        #expect(at("body") == .body)
    }

    // MARK: Lists

    @Test func listsAddAndRemoveMarkers() {
        #expect(run("[one\ntwo]", list(.bulleted)) == "- [one\n- two]")
        #expect(run("- [one\n- two]", list(.bulleted)) == "[one\ntwo]")
        #expect(run("[one\ntwo]", list(.numbered)) == "1. [one\n2. two]")
        #expect(run("- [one\n- two]", list(.checklist)) == "- [ ] [one\n- [ ] two]")
        #expect(run("|", list(.bulleted)) == "- |")
        #expect(run("1. one\nt|wo", list(.numbered)) == "1. one\n2. t|wo")
    }

    @Test func blankLinesInASelectionStayBlank() {
        #expect(run("[one\n\ntwo]", list(.bulleted)) == "- [one\n\n- two]")
    }

    // MARK: Blocks and links

    @Test func dividersGoOnALineOfTheirOwn() {
        let divider: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result = {
            text, selection, _ in MarkdownCommands.insertBlock("---", text: text, selection: selection, lineBreak: "\n")
        }
        #expect(run("Para|graph", divider) == "Paragraph\n\n---\n|")
        #expect(run("one\n|\ntwo", divider) == "one\n---\n|two")
        #expect(run("one\n|", divider) == "one\n---\n|")
    }

    @Test func linksAreWrittenAndFoundAgain() {
        let insert: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result = { _, selection, _ in
            MarkdownCommands.setLink(text: "Zephydian", url: "https://zephydian.com", replacing: selection)
        }
        #expect(run("By [Zephydian].", insert) == "By [Zephydian](https://zephydian.com)|.")
        let text = "By [Zephydian](https://zephydian.com)." as NSString
        let found = MarkdownCommands.link(at: NSRange(location: 6, length: 0), in: text, analysis: MarkdownAnalysis(text as String))
        #expect(found?.text == "Zephydian")
        #expect(found?.url == "https://zephydian.com")
        #expect(found.map { text.substring(with: $0.range) } == "[Zephydian](https://zephydian.com)")
    }

    @Test func inlineStylesAreFoundForTheToolbar() {
        let text = "a **b** c" as NSString
        let analysis = MarkdownAnalysis(text as String)
        #expect(MarkdownCommands.span(of: .bold, at: NSRange(location: 5, length: 0), in: text, analysis: analysis) != nil)
        #expect(MarkdownCommands.span(of: .bold, at: NSRange(location: 0, length: 0), in: text, analysis: analysis) == nil)
        #expect(MarkdownCommands.span(of: .italic, at: NSRange(location: 5, length: 0), in: text, analysis: analysis) == nil)
    }

    // MARK: Highlight and clearing

    @Test func highlightIsFoundAndToggled() {
        #expect(run("a [word] b", toggle(.highlight)) == "a ==[word]== b")
        #expect(run("a ==wo|rd== b", toggle(.highlight)) == "a wo|rd b")
        let text = "x ==yes== `==no==` =not=" as NSString
        let highlights = MarkdownAnalysis(text as String).spans.filter { $0.style == .highlight }.map { text.substring(with: $0.range) }
        #expect(highlights == ["yes"])
    }

    @Test func clearFormattingKeepsTheWords() {
        let clear: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result = {
            MarkdownCommands.clearFormatting(text: $0, selection: $1, analysis: $2)
        }
        #expect(run("## A **bo|ld** [link](https://x.com)", clear) == "A bo|ld link")
        #expect(run("- [one *two*\n> three]", clear) == "[one two\nthree]")
    }

    // MARK: Return inside a style

    @Test func returnInsideAStyleClosesItAtTheCursor() {
        let close: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result = { text, selection, analysis in
            MarkdownCommands.closeInlineStyles(at: selection.location, text: text, analysis: analysis)
                ?? .init(edits: [], selection: selection)
        }
        #expect(run("*hello|*", close) == "*hello*|")
        #expect(run("say *hel|lo* now", close) == "say *hel*|lo now")
        #expect(run("**|bold**", close) == "|bold")
        #expect(run("***both|***", close) == "***both***|")
        #expect(run("plain| text", close) == "plain| text")
    }

    // MARK: Alignment

    private func align(_ alignment: MarkdownCommands.Alignment) -> (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result {
        { MarkdownCommands.setAlignment(alignment, text: $0, selection: $1, analysis: $2, lineBreak: "\n") }
    }

    @Test func centeringWrapsTheParagraphInHTML() {
        #expect(run("Hel|lo", align(.center)) == "<div align=\"center\">\n\nHel|lo\n\n</div>")
        #expect(run("a\n\nb|c\nd\n\ne", align(.center)) == "a\n\n<div align=\"center\">\n\nb|c\nd\n\n</div>\n\ne")
        #expect(run("a|\nnext", align(.right)) == "<div align=\"right\">\n\na|\nnext\n\n</div>")
    }

    @Test func alignmentChangesOrComesOff() {
        let centered = "<div align=\"center\">\n\nHel|lo\n\n</div>"
        #expect(run(centered, align(.right)) == "<div align=\"right\">\n\nHel|lo\n\n</div>")
        #expect(run(centered, align(.left)) == "Hel|lo")
        #expect(run(centered + "\n\nmore", align(.left)) == "Hel|lo\n\nmore")
        #expect(run("plain|", align(.left)) == "plain|")
    }

    @Test func alignedLinesAreFound() {
        let text = "<div align=\"center\">\n\nMiddle\n\n</div>\n\nAfter"
        let lines = MarkdownAnalysis(text).lines
        #expect(lines[0].kind == .alignTag)
        #expect(lines[2].alignment == .center)
        #expect(lines[4].kind == .alignTag)
        #expect(lines[6].alignment == nil)
    }

    @Test func leftWorksFromTheHiddenTagLines() {
        #expect(run("<div align=\"center\">|\n\nHello\n\n</div>", align(.left)) == "|Hello")
        #expect(run("<div align=\"center\">\n\nHello\n\n</div>|", align(.left)) == "Hello|")
        #expect(run("<div align=\"center\">\n|\nHello\n\n</div>", align(.left)) == "|Hello")
    }

    @Test func returnOnAnEmptyLineLeavesTheAlignment() {
        let leave: (NSString, NSRange, MarkdownAnalysis) -> MarkdownCommands.Result = { text, selection, analysis in
            MarkdownCommands.leaveAlignment(at: selection.location, text: text, analysis: analysis, lineBreak: "\n")
                ?? .init(edits: [], selection: selection)
        }
        #expect(run("<div align=\"center\">\n\nHello\n|\n\n</div>", leave) == "<div align=\"center\">\n\nHello\n\n</div>\n\n|")
        #expect(run("<div align=\"center\">\n\nHel|lo\n\n</div>", leave) == "<div align=\"center\">\n\nHel|lo\n\n</div>")
    }
}
