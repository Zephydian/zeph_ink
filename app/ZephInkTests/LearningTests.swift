import AppKit
import Testing
@testable import ZephInk

/// Learning mode: tips after a style is applied, retiring after three showings, and the cheat sheet.
@MainActor
struct LearningTests {
    /// Runs with fresh tip counts and tips on, then puts the person's settings back.
    private func withFreshTips(_ body: () throws -> Void) rethrows {
        let keys = [Tips.countsKey, Preferences.Key.showsTips]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) { UserDefaults.standard.set(value, forKey: key) }
            Tips.shared.dismiss()
        }
        UserDefaults.standard.removeObject(forKey: Tips.countsKey)
        UserDefaults.standard.removeObject(forKey: Preferences.Key.showsTips)
        Tips.shared.dismiss()
        try body()
    }

    private func editor(_ text: String) throws -> (MarkdownDocument, Editor) {
        Fonts.register()
        let document = MarkdownDocument()
        try document.read(from: Data(text.utf8), ofType: "net.daringfireball.markdown")
        return (document, Editor(document: document))
    }

    @Test func applyingAStyleShowsItsTip() throws {
        try withFreshTips {
            let (document, editor) = try editor("hello world")
            editor.textView.setSelectedRange(NSRange(location: 0, length: 5))
            editor.textView.toggleBold(nil)
            #expect(document.storage.string == "**hello** world")
            #expect(Tips.shared.current == Tips.Shown(tip: .bold, document: ObjectIdentifier(document)))
        }
    }

    @Test func removingAStyleShowsNoTip() throws {
        try withFreshTips {
            let (_, editor) = try editor("## Title")
            editor.textView.setSelectedRange(NSRange(location: 4, length: 0))
            editor.textView.setHeadingStyle(nil)     // already a heading: turns it off
            #expect(Tips.shared.current == nil)
        }
    }

    @Test func aTipRetiresAfterThreeShowings() {
        withFreshTips {
            let document = MarkdownDocument()
            for _ in 0..<Tips.timesShown {
                Tips.shared.offer(.heading, in: document)
                #expect(Tips.shared.current?.tip == .heading)
                Tips.shared.dismiss()
            }
            Tips.shared.offer(.heading, in: document)
            #expect(Tips.shared.current == nil)
            #expect(Tips.counts["heading"] == Tips.timesShown)
            // Other tips still show.
            Tips.shared.offer(.quote, in: document)
            #expect(Tips.shared.current?.tip == .quote)
        }
    }

    @Test func aTipOnScreenDoesNotCountTwice() {
        withFreshTips {
            let document = MarkdownDocument()
            Tips.shared.offer(.italic, in: document)
            Tips.shared.offer(.italic, in: document)
            #expect(Tips.counts["italic"] == 1)
        }
    }

    @Test func tipsCanBeTurnedOff() {
        withFreshTips {
            UserDefaults.standard.set(false, forKey: Preferences.Key.showsTips)
            Tips.shared.offer(.bold, in: MarkdownDocument())
            #expect(Tips.shared.current == nil)
        }
    }

    @Test func everyStyleHasATip() {
        for inline in MarkdownCommands.Inline.allCases { #expect(Tip(inline) != nil) }
        for list in MarkdownCommands.ListKind.allCases { #expect(Tip(list) != nil) }
        for paragraph in MarkdownCommands.Paragraph.allCases where paragraph != .body { #expect(Tip(paragraph) != nil) }
        #expect(Tip(.body) == nil)
    }

    @Test func theCheatSheetMatchesTheMenus() {
        // Each shortcut in the cheat sheet is the one the Format menu uses.
        let menu = MainMenu.make()
        let format = menu.items.first { $0.title == "Format" }?.submenu
        for (_, rows) in CheatSheet.sections {
            for row in rows where !row.shortcut.isEmpty {
                let item = format?.items.first { $0.title.replacingOccurrences(of: "…", with: "").lowercased() == row.name.lowercased() }
                #expect(item != nil, "\(row.name) is in the Format menu")
                if let item {
                    let key = row.shortcut.replacingOccurrences(of: "⌘", with: "").replacingOccurrences(of: "⇧", with: "")
                    #expect(item.keyEquivalent.lowercased() == key.lowercased(), "\(row.name)")
                }
            }
        }
    }
}
