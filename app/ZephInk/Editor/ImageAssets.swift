import AppKit

/// Adds images to a document: copies them into an `assets` folder next to it and inserts
/// `![name](assets/file.png)` for each, so the document and its images move together.
enum ImageAssets {
    static func insert(_ sources: [URL], into textView: ZephTextView) {
        guard let window = textView.window, let document = textView.editor?.documentForImages, !sources.isEmpty else { return }
        guard let fileURL = document.fileURL else {
            askToSaveFirst(document, in: window) { insert(sources, into: textView) }
            return
        }
        let folder = fileURL.deletingLastPathComponent()
        let reason = "Allow Zeph#Ink to keep images in this folder. They go in an “assets” folder next to “\(fileURL.lastPathComponent)”."
        FolderAccess.request(folder, reason: reason, in: window) { allowed in
            guard allowed else { return }
            do {
                let names = try copy(sources, into: folder.appendingPathComponent("assets", isDirectory: true))
                textView.insertBlocks(names.map { "![\(altText(for: $0))](assets/\(encoded($0)))" })
                textView.editor?.imagesDidChange()
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    /// Copies the images, never overwriting: a name that's taken gets a number (`photo 2.png`).
    private static func copy(_ sources: [URL], into assets: URL) throws -> [String] {
        let files = FileManager.default
        try files.createDirectory(at: assets, withIntermediateDirectories: true)
        return try sources.map { source in
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension.lowercased()
            var name = source.lastPathComponent
            var number = 2
            while files.fileExists(atPath: assets.appendingPathComponent(name).path) {
                name = "\(base) \(number).\(ext)"
                number += 1
            }
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            try files.copyItem(at: source, to: assets.appendingPathComponent(name))
            return name
        }
    }

    private static func altText(for name: String) -> String {
        (name as NSString).deletingPathExtension.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    }

    /// Spaces and other awkward characters in a path, written so markdown reads the path whole.
    private static func encoded(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? name
    }

    /// An untitled document has no folder for images yet: offer to save it first.
    private static func askToSaveFirst(_ document: MarkdownDocument, in window: NSWindow, then retry: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save this document first"
        alert.informativeText = "Images are kept in a folder next to the document, so it needs a place on disk first."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            SaveCallback.save(document) { saved in if saved { retry() } }
        }
    }
}

/// Runs a document's Save panel and calls back with whether it saved (AppKit reports through a selector).
private final class SaveCallback: NSObject {
    private static var pending: [SaveCallback] = []
    private let done: (Bool) -> Void

    private init(done: @escaping (Bool) -> Void) {
        self.done = done
    }

    static func save(_ document: NSDocument, then done: @escaping (Bool) -> Void) {
        let callback = SaveCallback(done: done)
        pending.append(callback)
        document.runModalSavePanel(for: .saveOperation, delegate: callback,
                                   didSave: #selector(document(_:didSave:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Self.pending.removeAll { $0 === self }
        done(didSave)
    }
}

/// Loads the images a document shows, from paths relative to its folder, and remembers them.
final class ImageLoader {
    enum Result {
        case image(CGImage)
        /// The image is there, but the sandbox needs the person's OK to read the folder.
        case needsAccess
    }

    private var cache: [String: Result?] = [:]

    func forget() {
        cache = [:]
    }

    /// The image at a markdown path, or nil if it's online, missing or not an image.
    func image(at path: String, relativeTo folder: URL?) -> Result? {
        if let cached = cache[path] { return cached }
        let result = load(path, relativeTo: folder)
        cache[path] = result
        return result
    }

    private func load(_ path: String, relativeTo folder: URL?) -> Result? {
        // Zeph#Ink never goes online, so web images stay as their markdown.
        if path.contains("://") || path.hasPrefix("data:") { return nil }
        let decoded = path.removingPercentEncoding ?? path
        let url: URL
        if decoded.hasPrefix("/") {
            url = URL(fileURLWithPath: decoded)
        } else if let folder {
            url = folder.appendingPathComponent(decoded)
        } else {
            return nil
        }
        if let image = read(url) { return .image(image) }
        guard let folder else { return nil }
        if FolderAccess.open(folder) {
            return read(url).map { .image($0) }   // allowed, but missing or not an image
        }
        // The sandbox hides the file (even whether it exists) until the person allows the folder.
        return .needsAccess
    }

    private func read(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
