import AppKit

/// Changing the body text size. Markdown can't store sizes, so it's one size for the body text of every
/// document (titles and headings keep theirs). When the document already has body text, a message
/// says so first, with a "Don't ask again" box.
enum BodyTextSize {
    private static let skipKey = "skipBodyTextSizeMessage"

    static func change(to size: CGFloat, for editor: Editor?, in window: NSWindow?) {
        let size = min(max(size, Preferences.textSizes.first!), Preferences.textSizes.last!)
        guard abs(size - Preferences.textSize) > 0.01 else { return }
        let hasBodyText = editor?.analysis.lines.contains { $0.kind == .body && $0.range.length > 0 } ?? false
        guard hasBodyText, !UserDefaults.standard.bool(forKey: skipKey), let window else {
            Preferences.setTextSize(size)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Change body text to \(size.formatted()) pt?"
        alert.informativeText = "This changes the size of all body text, in every document. Titles and headings stay the same size."
        alert.addButton(withTitle: "Change")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
            Preferences.setTextSize(size)
        }
    }
}
