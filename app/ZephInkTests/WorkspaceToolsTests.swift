import Foundation
import Testing
@testable import ZephInk

/// Front matter, the outline, search across documents and Quick Open's ranking.
@MainActor
struct WorkspaceToolsTests {
    @Test func frontMatterIsACardNotAHeading() {
        let text = "---\ntitle: Essay\ntags: [a, b]\n---\n\n# Real heading\n"
        let lines = MarkdownAnalysis(text).lines
        guard case .frontMatter(let first) = lines[0].kind, case .frontMatter(let last) = lines[3].kind else {
            Issue.record("front matter not found"); return
        }
        #expect(first.isFirst && first.isFence)
        #expect(last.isLast && last.isFence)
        #expect(lines[5].kind == .heading(level: 1))
        // Without the parser's view of it, "tags" would be a setext heading.
        #expect(!lines.contains { $0.kind == .heading(level: 2) })
    }

    @Test func aDividerIsNotFrontMatter() {
        #expect(MarkdownAnalysis.frontMatterEnd(in: "Text\n---\nmore\n---\n" as NSString, lines: MarkdownAnalysis("Text\n---\nmore\n---\n").lines) == nil)
        #expect(MarkdownAnalysis.frontMatterEnd(in: "---\n---\n" as NSString, lines: MarkdownAnalysis("---\n---\n").lines) == nil)
    }

    @Test func theOutlineListsHeadingsWithoutSymbols() {
        let text = "---\ntitle: x\n---\n# Title\n\nBody\n\n## A **bold** heading ##\n\nSetext\n---\n" as NSString
        let headings = Outline.headings(in: MarkdownAnalysis(text as String), text: text)
        #expect(headings.map(\.title) == ["Title", "A bold heading", "Setext"])
        #expect(headings.map(\.level) == [1, 2, 2])
    }

    @Test func searchFindsMatchesInEveryDocument() throws {
        let one = MarkdownDocument(), two = MarkdownDocument()
        try one.read(from: Data("Café and cafe\n".utf8), ofType: MarkdownDocument.markdownType)
        try two.read(from: Data("No match here\n".utf8), ofType: MarkdownDocument.markdownType)
        let (groups, total) = DocumentSearch.search("CAFE", in: [(one, one.storage.string as NSString), (two, two.storage.string as NSString)])
        #expect(total == 2)
        #expect(groups.count == 1)
        #expect(groups[0].matches.first?.snippet == "Café and cafe")
    }

    @Test func quickOpenPrefersTheStartsOfWords() {
        #expect(QuickOpen.score("Project ideas.md", query: "pi") != nil)
        #expect(QuickOpen.score("notes.md", query: "xyz") == nil)
        let start = QuickOpen.score("plan.md", query: "pl") ?? 0
        let middle = QuickOpen.score("example.md", query: "pl") ?? 0
        #expect(start > middle)
    }
}
