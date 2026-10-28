import Foundation
import Testing
@testable import ZephInk

/// Which parts of a markdown text are headings, lists, code and symbols.
@MainActor
struct MarkdownAnalysisTests {
    /// The text a range covers.
    private func text(_ range: NSRange, in source: String) -> String {
        (source as NSString).substring(with: range)
    }

    private func spans(_ style: MarkdownAnalysis.InlineStyle, in source: String) -> [String] {
        MarkdownAnalysis(source).spans.filter { $0.style == style }
            .sorted { $0.range.location < $1.range.location }
            .map { text($0.range, in: source) }
    }

    @Test func linesSplitLikeTheParser() {
        let source = "one\r\ntwo\rthree\nfour"
        let lines = MarkdownAnalysis(source).lines
        #expect(lines.map { text($0.range, in: source) } == ["one", "two", "three", "four"])
        #expect(lines.map { text($0.fullRange, in: source) } == ["one\r\n", "two\r", "three\n", "four"])
    }

    @Test func headings() {
        let source = "# Title\n\n## Heading ##\n\nSetext\n===\n"
        let lines = MarkdownAnalysis(source).lines
        #expect(lines[0].kind == .heading(level: 1))
        #expect(lines[0].markers.map { text($0, in: source) } == ["# "])
        #expect(lines[1].kind == .blank)
        #expect(lines[2].markers.map { text($0, in: source) } == ["## ", " ##"])
        #expect(lines[4].kind == .heading(level: 1))
        #expect(lines[5].markers.map { text($0, in: source) } == ["==="])
    }

    @Test func inlineStylesAndTheirSymbols() {
        let source = "Some **bold**, *italic*, ~~gone~~, `code` and [a link](https://zephydian.com).\n"
        #expect(spans(.strong, in: source) == ["bold"])
        #expect(spans(.emphasis, in: source) == ["italic"])
        #expect(spans(.strikethrough, in: source) == ["gone"])
        #expect(spans(.code, in: source) == ["`code`"])
        #expect(spans(.link, in: source) == ["a link"])
        #expect(spans(.marker, in: source) == ["**", "**", "*", "*", "~~", "~~", "`", "`", "[", "](https://zephydian.com)"])
    }

    @Test func nestedStylesFindTheirOwnSymbols() {
        let source = "***both***\n"
        #expect(spans(.strong, in: source).contains("both") || spans(.emphasis, in: source).contains("both"))
        #expect(spans(.marker, in: source).joined() == "******")
        #expect(MarkdownAnalysis(source).spans.filter { $0.style == .marker }.allSatisfy { $0.range.length <= 2 })
    }

    @Test func positionsAfterWideCharacters() {
        let source = "日本 🖋️ **bold**\n"
        #expect(spans(.strong, in: source) == ["bold"])
        #expect(spans(.marker, in: source) == ["**", "**"])
    }

    @Test func lists() {
        let source = "- one\n  - nested\n1. first\n- [ ] todo\n- [x] done\n"
        let lines = MarkdownAnalysis(source).lines
        #expect(lines[0].list?.bullet.map { text($0, in: source) } == "-")
        #expect(lines[0].markers.map { text($0, in: source) } == ["- "])
        #expect(lines[1].list?.contentStart == (source as NSString).range(of: "nested").location)
        #expect(lines[2].list?.bullet == nil)
        #expect(lines[2].markers.isEmpty)
        #expect(lines[2].list.map { text($0.marker, in: source) } == "1. ")
        #expect(lines[3].list?.task.map { text($0, in: source) } == "[ ]")
        #expect(lines[3].list?.isChecked == false)
        #expect(lines[4].list?.isChecked == true)
        #expect(lines[4].list?.contentStart == (source as NSString).range(of: "done").location)
    }

    @Test func codeBlocks() {
        let source = "```swift\nlet a = 1\n```\n\n    indented\n"
        let lines = MarkdownAnalysis(source).lines
        #expect(lines[0].kind == .code(.init(isFence: true, isFirst: true, isLast: false)))
        #expect(lines[1].kind == .code(.init(isFence: false, isFirst: false, isLast: false)))
        #expect(lines[2].kind == .code(.init(isFence: true, isFirst: false, isLast: true)))
        #expect(lines[4].kind == .code(.init(isFence: false, isFirst: true, isLast: true)))
        #expect(spans(.strong, in: "```\n**not bold**\n```\n").isEmpty)
    }

    @Test func quotesAndDividers() {
        let source = "> quoted\n> > deeper\n\n---\n"
        let lines = MarkdownAnalysis(source).lines
        #expect(lines[0].quoteDepth == 1)
        #expect(lines[1].quoteDepth == 2)
        #expect(lines[1].markers.map { text($0, in: source) } == ["> > "])
        #expect(lines[3].kind == .divider)
    }

    @Test(arguments: ["welcome.md", "crlf.md", "no-trailing-newline.md", "bom-unicode.md"])
    func everyFixtureAnalyzes(_ name: String) throws {
        let url = try #require(Bundle(for: AnalysisBundleToken.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        let source = try String(contentsOf: url, encoding: .utf8)
        let analysis = MarkdownAnalysis(source)
        let length = (source as NSString).length
        #expect(analysis.lines.last.map { NSMaxRange($0.fullRange) } == length)
        for span in analysis.spans { #expect(NSMaxRange(span.range) <= length) }
    }
}

private final class AnalysisBundleToken {}

/// Editing re-parses only the blocks around the edit. Whatever the edit, the result must match
/// parsing the whole text again.
@MainActor
struct IncrementalAnalysisTests {
    /// Lines and spans without block numbers, which differ between the two ways by design.
    private func summary(_ analysis: MarkdownAnalysis) -> [String] {
        analysis.lines.map { "\($0.fullRange) \($0.shape) \($0.markers) \(String(describing: $0.list))" }
            + analysis.spans.map { "\($0.range) \($0.style.rawValue)" }.sorted()
    }

    private static let base = """
    # Title

    A paragraph with **bold** and *italic*,
    running onto a second line with `code`.

    - one
    - two
      - nested **item**
    - [ ] task

    > A quote
    > on two lines

    1. First
    2. Second

    Last paragraph.
    """

    private static let insertions = ["a", " ", "\n", "\n\n", "**", "*", "`", "# ", "## ", "- ", "> ", "1. ", "- [ ] ", "---", "===", "x\ny", "[link](url)", "  ", "=="]

    @Test(arguments: 0..<300)
    func randomEditMatchesAFullParse(_ seed: Int) throws {
        var generator = SeededGenerator(seed: UInt64(seed + 1))
        var text = Self.base
        var analysis = MarkdownAnalysis(text)
        for _ in 0..<4 {
            let ns = text as NSString
            let location = Int.random(in: 0...ns.length, using: &generator)
            let length = Bool.random(using: &generator) ? 0 : min(Int.random(in: 0...6, using: &generator), ns.length - location)
            let insertion = Self.insertions.randomElement(using: &generator)!
            text = ns.replacingCharacters(in: NSRange(location: location, length: length), with: insertion)
            let edited = NSRange(location: location, length: (insertion as NSString).length)
            let delta = (insertion as NSString).length - length
            let full = MarkdownAnalysis(text)
            if let (updated, _) = analysis.updated(afterEditing: edited, changeInLength: delta, in: text) {
                #expect(summary(updated) == summary(full), "edit at \(location) (\(length) replaced with \(insertion.debugDescription)) in:\n\(text)")
                analysis = updated
            } else {
                analysis = full
            }
        }
    }
}

/// A small repeatable random number generator (SplitMix64), so a failing case can be replayed.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
