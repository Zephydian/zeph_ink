import AppKit

/// App-wide behavior. Documents (opening, autosave, the untitled document at launch) are handled by
/// AppKit's `NSDocumentController` and `MarkdownDocument`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// View → Markdown Symbols → Clean or Faded, for every document.
    @objc func setMarkdownSymbols(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let symbols = MarkdownSymbols(rawValue: raw) else { return }
        MarkdownSymbols.current = symbols
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setMarkdownSymbols(_:)) {
            menuItem.state = menuItem.representedObject as? String == MarkdownSymbols.current.rawValue ? .on : .off
        }
        return true
    }
}
