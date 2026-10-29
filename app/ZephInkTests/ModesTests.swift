import AppKit
import Testing
@testable import ZephInk

/// Focus Mode, Typewriter Mode and Synced Scrolling. They're switches in the real app's settings
/// (shared with the test copy), so each test puts them back.
@MainActor
struct ModesTests {
    private func withSetting(_ key: String, _ body: () throws -> Void) rethrows {
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        try body()
    }

    private func editor(_ text: String) throws -> (MarkdownDocument, Editor) {
        Fonts.register()
        let document = MarkdownDocument()
        try document.read(from: Data(text.utf8), ofType: MarkdownDocument.markdownType)
        return (document, Editor(document: document))
    }

    /// Whether text at a location is drawn faded by Focus Mode.
    private func isFaded(_ location: Int, in editor: Editor) -> Bool {
        guard let layout = editor.textView.textLayoutManager,
              let start = layout.location(layout.documentRange.location, offsetBy: location) else { return false }
        var faded = false
        layout.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            faded = range.contains(start) && attributes[.foregroundColor] != nil
            return false
        }
        return faded
    }

    @Test func focusModeFadesEverythingButTheCurrentBlock() throws {
        try withSetting(Preferences.Key.focusMode) {
            let (document, editor) = try editor("First paragraph.\n\nSecond paragraph.\n\nThird.")
            let text = document.storage.string as NSString
            editor.textView.setSelectedRange(NSRange(location: text.range(of: "Second").location, length: 0))
            editor.updateFocus()
            #expect(isFaded(text.range(of: "First").location, in: editor))
            #expect(!isFaded(text.range(of: "Second").location, in: editor))
            #expect(isFaded(text.range(of: "Third").location, in: editor))
        }
    }

    @Test func typewriterModeLeavesRoomToCenterTheFirstAndLastLines() throws {
        try withSetting(Preferences.Key.typewriterMode) {
            let (_, editor) = try editor("One line")
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = editor.scrollView
            window.layoutIfNeeded()
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            #expect(editor.scrollView.contentInsets.bottom == (editor.scrollView.contentSize.height / 2).rounded())
        }
    }

    @Test func syncedPanesScrollTogether() throws {
        try withSetting(Preferences.Key.syncedScrolling) {
            Fonts.register()
            let long = (1...200).map { "Line \($0) with a few words on it." }.joined(separator: "\n\n")
            let controller = WorkspaceWindowController.makeNew()
            let documents = try (0..<2).map { _ in
                let document = MarkdownDocument()
                try document.read(from: Data(long.utf8), ofType: MarkdownDocument.markdownType)
                controller.add(document)
                return document
            }
            controller.select(documents[0])
            _ = controller.workspace.splitRight()
            let window = try #require(controller.window)
            window.setContentSize(NSSize(width: 1200, height: 700))
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let first = try #require(controller.workspace.tab(for: documents[0])?.editor)
            let second = try #require(controller.workspace.tab(for: documents[1])?.editor)
            // Lay both documents out in full, so their heights are real rather than TextKit's estimates.
            for editor in [first, second] {
                let layout = try #require(editor.textView.textLayoutManager)
                layout.ensureLayout(for: layout.documentRange)
                layout.textViewportLayoutController.layoutViewport()
                let height = layout.usageBoundsForTextContainer.height + editor.textView.textContainerInset.height * 2
                editor.textView.setFrameSize(NSSize(width: editor.textView.frame.width, height: height))
            }
            window.layoutIfNeeded()
            controller.workspaceDidChange()   // what the app does on its next turn, after the split
            let clip = first.scrollView.contentView
            let range = (first.scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
            clip.scroll(to: NSPoint(x: 0, y: range / 2))
            first.scrollView.reflectScrolledClipView(clip)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let other = second.scrollView.contentView.bounds.origin.y
            let otherRange = (second.scrollView.documentView?.frame.height ?? 0) - second.scrollView.contentView.bounds.height
            #expect(abs(other / otherRange - 0.5) < 0.05)
            window.close()
        }
    }
}
