import AppKit

/// Folders the person has let Zeph#Ink use, beyond the documents themselves: where a document's
/// images go (`assets/`) and are read from. The sandbox gives an app only the files the person opens,
/// so the first image in a folder asks once, and a bookmark remembers the answer for good.
enum FolderAccess {
    private static let key = "folderBookmarks"
    /// Folders whose access has been started this run (it lasts until the app quits).
    private static var started: Set<URL> = []

    /// Starts using a folder the person allowed before (or a folder inside one). Returns false if they haven't.
    static func open(_ folder: URL) -> Bool {
        let folder = folder.standardizedFileURL
        if started.contains(where: { folder.path.hasPrefix($0.path) }) { return true }
        let bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        for (path, bookmark) in bookmarks where folder.path == path || folder.path.hasPrefix(path + "/") {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                     bookmarkDataIsStale: &isStale), url.startAccessingSecurityScopedResource() else { continue }
            started.insert(url.standardizedFileURL)
            if isStale { remember(url) }
            return true
        }
        return false
    }

    /// Asks the person to allow a folder, with an Open panel already showing it. Calls back with
    /// whether they did (choosing the folder, or one that contains it).
    static func request(_ folder: URL, reason: String, in window: NSWindow, then done: @escaping (Bool) -> Void) {
        if open(folder) { return done(true) }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = reason
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let chosen = panel.url?.standardizedFileURL,
                  folder.standardizedFileURL.path == chosen.path || folder.standardizedFileURL.path.hasPrefix(chosen.path + "/") else {
                return done(false)
            }
            remember(chosen)
            done(open(folder))
        }
    }

    private static func remember(_ folder: URL) {
        guard let bookmark = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        bookmarks[folder.standardizedFileURL.path] = bookmark
        UserDefaults.standard.set(bookmarks, forKey: key)
    }
}
