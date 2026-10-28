import AppKit

/// The open windows, their tabs and their split layout, saved whenever they change and reopened at
/// the next launch, even after a crash.
///
/// Saved files are remembered with security-scoped bookmarks, which let the sandboxed app open them
/// again. Untitled documents are remembered by their autosave, which macOS keeps in the app's container.
struct Session: Codable, Equatable {
    struct Window: Codable, Equatable {
        var frame: String
        var tabs: [Tab]
        /// The tabs the panes show, left to right, as indices into `tabs`.
        var panes: [Int]
        var paneWidths: [Double]
        var focusedPane: Int
    }

    struct Tab: Codable, Equatable {
        /// A bookmark to the document's file, if it has one.
        var bookmark: Data?
        /// Where an untitled document's autosave is.
        var autosavePath: String?
        var fileType: String
        var isSourceMode: Bool
    }

    var windows: [Window]

    private static let key = "session"

    /// Set once quitting has saved the session, so windows closing on the way out don't overwrite it.
    /// Always set while unit tests run: the test copy of the app shares the real app's settings, and
    /// must neither reopen nor overwrite the person's session.
    static var isFrozen = isRunningTests

    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    static func load() -> Session? {
        guard !isRunningTests, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? PropertyListDecoder().decode(Session.self, from: data)
    }

    func save() {
        guard !Session.isRunningTests, let data = try? PropertyListEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    // MARK: - Capturing

    /// The session as it is now, from every workspace window.
    @MainActor
    static func current() -> Session {
        Session(windows: WorkspaceWindowController.all.compactMap(\.sessionWindow))
    }

    /// How to reopen a document, or nil for an untitled document that was never changed (or not yet
    /// autosaved), which isn't worth reopening.
    @MainActor
    static func tab(for document: MarkdownDocument, isSourceMode: Bool) -> Tab? {
        if let url = document.fileURL {
            let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            guard let bookmark else { return nil }
            return Tab(bookmark: bookmark, autosavePath: nil, fileType: document.fileType ?? MarkdownDocument.markdownType,
                       isSourceMode: isSourceMode)
        }
        guard document.isDocumentEdited, let autosave = document.autosavedContentsFileURL else { return nil }
        return Tab(bookmark: nil, autosavePath: autosave.path, fileType: document.fileType ?? MarkdownDocument.markdownType,
                   isSourceMode: isSourceMode)
    }

    // MARK: - Reopening

    /// Reopens the saved windows. Returns whether any document came back.
    @MainActor
    func restore() -> Bool {
        var restoredAny = false
        let controller = NSDocumentController.shared
        for saved in windows {
            var opened: [(MarkdownDocument, Bool)] = []
            var indexMap: [Int: Int] = [:]
            for (index, tab) in saved.tabs.enumerated() {
                guard let document = Self.open(tab, with: controller) else { continue }
                indexMap[index] = opened.count
                opened.append((document, tab.isSourceMode))
            }
            guard !opened.isEmpty else { continue }
            let workspace = WorkspaceWindowController.makeNew()
            for (document, isSourceMode) in opened {
                controller.addDocument(document)
                workspace.add(document)
                workspace.workspace.tab(for: document)?.editor.isSourceMode = isSourceMode
            }
            let panes = saved.panes.compactMap { indexMap[$0] }
            workspace.restoreLayout(panes: panes, widths: saved.paneWidths.map { CGFloat($0) },
                                    focused: min(saved.focusedPane, max(panes.count - 1, 0)), frame: saved.frame)
            workspace.showWindow(nil)
            restoredAny = true
        }
        return restoredAny
    }

    @MainActor
    private static func open(_ tab: Tab, with controller: NSDocumentController) -> MarkdownDocument? {
        if let bookmark = tab.bookmark {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                     bookmarkDataIsStale: &isStale) else { return nil }
            if let open = controller.document(for: url) as? MarkdownDocument { return open }
            let isAccessing = url.startAccessingSecurityScopedResource()
            guard let document = try? controller.makeDocument(withContentsOf: url, ofType: tab.fileType) as? MarkdownDocument else {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
                return nil
            }
            if isAccessing { document.securityScopedURL = url }
            return document
        }
        if let path = tab.autosavePath, FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            return try? controller.makeDocument(for: nil, withContentsOf: url, ofType: tab.fileType) as? MarkdownDocument
        }
        return nil
    }
}
