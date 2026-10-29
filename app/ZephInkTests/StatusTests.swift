import Foundation
import Testing
@testable import ZephInk

/// The status bar's numbers, and word-count goals.
@MainActor
struct StatusTests {
    @Test func wordsLeaveOutMarkdownSymbolsAndLinkAddresses() {
        let (words, _) = DocumentStats.measure("## A heading\n\n- **Bold** item and [a link](https://zephydian.com/long/path).\n")
        #expect(words == 7)   // A, heading, Bold, item, and, a, link
    }

    @Test func charactersLeaveOutSpaces() {
        #expect(DocumentStats.measure("ab c\nd").characters == 4)
    }

    @Test func readingTimeIsAtLeastAMinute() {
        let stats = DocumentStats()
        stats.count("one two")
        #expect(stats.readingMinutes == 1)
        stats.count(Array(repeating: "word", count: 690).joined(separator: " "))
        #expect(stats.readingMinutes == 3)
    }

    @Test func theSelectionHasItsOwnCount() {
        let stats = DocumentStats()
        stats.selectionDidChange("two words")
        #expect(stats.selectedWords == 2)
        stats.selectionDidChange(nil)
        #expect(stats.selectedWords == nil)
    }

    @Test func goalsAreKeptPerFile() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("goal-test-\(UUID().uuidString).md")
        WordGoals.set(500, for: url)
        #expect(WordGoals.goal(for: url) == 500)
        WordGoals.set(nil, for: url)
        #expect(WordGoals.goal(for: url) == nil)
    }
}
