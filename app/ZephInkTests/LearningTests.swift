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

    // MARK: Welcome and guide

    @Test func theWelcomeWindowNeverOpensInTests() {
        let previous = UserDefaults.standard.object(forKey: WelcomeWindowController.hasBeenShownKey)
        defer { UserDefaults.standard.set(previous, forKey: WelcomeWindowController.hasBeenShownKey) }
        UserDefaults.standard.removeObject(forKey: WelcomeWindowController.hasBeenShownKey)
        WelcomeWindowController.showAtLaunch()
        #expect(!UserDefaults.standard.bool(forKey: WelcomeWindowController.hasBeenShownKey))
    }

    @Test func theWelcomeShowsOnceThenAfterBigUpdatesWithNotes() {
        let notes = ["1.1": ["Tables you can edit"]]
        typealias W = WelcomeWindowController
        #expect(W.showing(hasSeen: false, lastVersion: nil, current: "1.0", notes: notes) == .welcome)
        #expect(W.showing(hasSeen: true, lastVersion: "1.0", current: "1.0", notes: notes) == nil)
        #expect(W.showing(hasSeen: true, lastVersion: "1.0", current: "1.1", notes: notes) == .whatsNew(["Tables you can edit"]))
        #expect(W.showing(hasSeen: true, lastVersion: "1.1", current: "1.2", notes: notes) == nil)   // no notes: nothing
        #expect(W.showing(hasSeen: true, lastVersion: nil, current: "1.1", notes: notes) == nil)     // version not known yet
    }

    @Test func everyLessonExampleShowsItsStyle() {
        let kinds = Lesson.all.map { MarkdownAnalysis($0.example) }
        #expect(kinds[0].lines.contains { $0.kind == .heading(level: 1) })
        #expect(kinds[1].spans.contains { $0.style.contains(.strong) })
        #expect(kinds[2].lines.contains { $0.list?.task != nil })
        #expect(kinds[3].spans.contains { $0.style.contains(.link) })
        #expect(kinds[4].lines.contains { $0.quoteDepth > 0 })
        #expect(kinds[5].lines.contains { $0.kind == .table })
        #expect(Lesson.all.count == 6)
    }

    @Test func thePreviewHidesSymbolsAtAFixedSize() {
        Fonts.register()
        let previous = UserDefaults.standard.object(forKey: Preferences.Key.textSize)
        defer { UserDefaults.standard.set(previous, forKey: Preferences.Key.textSize) }
        UserDefaults.standard.set(36.0, forKey: Preferences.Key.textSize)
        let preview = MarkdownPreview()
        preview.show("Some **bold** words")
        let storage = preview.textView.textStorage!
        let symbol = storage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont    // the first *
        let word = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect((symbol?.pointSize ?? 1) < 0.1)
        #expect(word?.pointSize == MarkdownPreview.bodySize)
        #expect(Theme.bodySize == 36)    // the setting itself is untouched
    }
}
