import AppKit

/// App-wide behavior. Documents (opening, autosave, the untitled document at launch) are handled by
/// AppKit's `NSDocumentController` and `MarkdownDocument`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
