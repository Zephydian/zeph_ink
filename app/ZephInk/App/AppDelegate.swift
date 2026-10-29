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
        followAccessibilitySettings()
        applyTheme()
        // Settings can change on any thread (macOS and other frameworks change some of their own), so
        // these always run on the main thread.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followAccessibilitySettings() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTheme() }
        }
        restoredSession = Session.load()?.restore() ?? false
    }

    /// The first time Zeph#Ink opens (or after a big update), the welcome window, in front of the document.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { WelcomeWindowController.showAtLaunch() }
    }

    /// Help → Welcome to Zeph#Ink.
    @objc func showWelcome(_ sender: Any?) { WelcomeWindowController.show() }

    /// Help → Markdown Guide.
    @objc func showMarkdownGuide(_ sender: Any?) { MarkdownGuideWindowController.show() }

    /// Increase Contrast: faded markdown symbols get darker. Editors restyle when told a setting changed.
    @objc private func followAccessibilitySettings() {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        guard contrast != Preferences.increaseContrast else { return }
        Preferences.increaseContrast = contrast
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }

    /// View → Zoom In (⌘+), Zoom Out (⌘−) and Actual Size (⌥⌘0), in the steps the status bar's
    /// zoom menu offers.
    @objc func zoomIn(_ sender: Any?) { Preferences.setZoom(Zoom.step(from: Preferences.zoom, up: true)) }
    @objc func zoomOut(_ sender: Any?) { Preferences.setZoom(Zoom.step(from: Preferences.zoom, up: false)) }
    @objc func zoomToActualSize(_ sender: Any?) { Preferences.setZoom(1) }

    /// Light, dark, or following the Mac (Settings → Theme).
    @objc private func applyTheme() {
        let appearance = Preferences.theme.appearance
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
    }

    /// Zeph#Ink → Settings… (⌘,), and the gear in the status bar.
    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }

    /// View → Margins → Narrow, Normal or Wide.
    @objc func setMargins(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let margins = Preferences.Margins(rawValue: raw) else { return }
        Preferences.set(margins, for: Preferences.Key.margins)
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

    /// View → Hide Toolbar (⌘⌥T), for every window.
    @objc func toggleToolbar(_ sender: Any?) {
        UserDefaults.standard.set(!Toolbar.isShown, forKey: Toolbar.isShownKey)
    }

    /// View → Page Style → Continuous, Paper, Square or Custom Size (set in Settings).
    @objc func setPageStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = Preferences.PageStyle(rawValue: raw) else { return }
        Preferences.set(style, for: Preferences.Key.pageStyle)
    }

    /// View → Focus Mode (⌘⇧F), Typewriter Mode and Synced Scrolling: switches that stay on until
    /// switched off.
    @objc func toggleFocusMode(_ sender: Any?) { Preferences.toggle(Preferences.Key.focusMode) }
    @objc func toggleTypewriterMode(_ sender: Any?) { Preferences.toggle(Preferences.Key.typewriterMode) }
    @objc func toggleSyncedScrolling(_ sender: Any?) { Preferences.toggle(Preferences.Key.syncedScrolling) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFocusMode(_:)): menuItem.state = Preferences.focusMode ? .on : .off
        case #selector(toggleTypewriterMode(_:)): menuItem.state = Preferences.typewriterMode ? .on : .off
        case #selector(toggleSyncedScrolling(_:)): menuItem.state = Preferences.syncedScrolling ? .on : .off
        default: break
        }
        if menuItem.action == #selector(setPageStyle(_:)) {
            menuItem.state = menuItem.representedObject as? String == Preferences.pageStyle.rawValue ? .on : .off
        }
        if menuItem.action == #selector(setMargins(_:)) {
            menuItem.state = menuItem.representedObject as? String == Preferences.margins.rawValue ? .on : .off
        }
        if menuItem.action == #selector(toggleToolbar(_:)) {
            menuItem.title = Toolbar.isShown ? "Hide Toolbar" : "Show Toolbar"
        }
        if menuItem.action == #selector(setMarkdownSymbols(_:)) {
            menuItem.state = menuItem.representedObject as? String == MarkdownSymbols.current.rawValue ? .on : .off
        }
        return true
    }
}
