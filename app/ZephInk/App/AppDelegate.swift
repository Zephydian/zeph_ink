import AppKit

/// App-wide behavior. Documents (opening, autosave, the untitled document at launch) are handled by
/// AppKit's `NSDocumentController` and `MarkdownDocument`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Whether the last session's documents came back, in which case no new untitled document opens.
    private var restoredSession = false

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Reopens the windows, tabs and splits that were open last time, before any file the app was
    /// asked to open joins them.
    func applicationWillFinishLaunching(_ notification: Notification) {
        restoredSession = Session.load()?.restore() ?? false
    }

    /// Quitting: saves the session before the windows close (closing them would otherwise save an
    /// empty one), then keeps it as it is.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !Session.isFrozen {
            Session.current().save()
            Session.isFrozen = true
        }
        return .terminateNow
    }

    /// At launch, a new untitled document only when nothing was restored. Later (clicking the Dock
    /// icon with no windows open) always.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        defer { restoredSession = false }
        return !restoredSession
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
