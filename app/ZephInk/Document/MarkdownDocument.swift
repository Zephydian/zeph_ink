import AppKit
import Observation

/// A markdown file. Its text storage *is* the file: the editor shows and edits it directly, and saving
/// writes it back. A document you open and save without changing it is written back byte for byte.
///
/// AppKit's `NSDocument` provides autosave, Versions, crash recovery and the "Edited" state. Instead of
/// a window of its own, each document is a tab in a `WorkspaceWindowController`.
@Observable
final class MarkdownDocument: NSDocument {
    /// The document's text, shared with its editor's text view.
    @ObservationIgnored let storage = NSTextStorage()

    /// Whether there are unsaved changes (mirrors `isDocumentEdited`, which SwiftUI can't watch).
    private(set) var isEdited = false
    /// The file name without its extension, or "Untitled" for a new document.
    private(set) var name = ""
    /// The file's extension with its dot, shown dimmed after the name in the tab.
    private(set) var fileExtension = ".md"

    /// The file as last read or written, and the text it holds. While the text still matches,
    /// saving writes these exact bytes, so nothing the person didn't change is ever rewritten.
    @ObservationIgnored private var savedData: Data?
    @ObservationIgnored private var savedText: String?
    /// Whether the file starts with a UTF-8 byte order mark. It isn't part of the text, so it's kept
    /// aside and written back.
    @ObservationIgnored private var hasByteOrderMark = false

    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    nonisolated override class var autosavesInPlace: Bool { true }

    // AppKit reads and writes documents on the main thread unless a document opts into doing it in the
    // background (`canConcurrentlyReadDocuments`, `canAsynchronouslyWrite`), which this one doesn't.

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        // Foundation would drop the mark silently while decoding, so take it off first and remember it.
        let hasByteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        guard let text = String(data: hasByteOrderMark ? data.dropFirst(3) : data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        MainActor.assumeIsolated {
            savedData = data
            savedText = text
            self.hasByteOrderMark = hasByteOrderMark
            // Replace in place (rather than swapping the storage) so an open editor follows a revert.
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = storage.string
        if text == savedText, let savedData {
            return savedData
        }
        let data = (hasByteOrderMark ? Self.byteOrderMark : Data()) + Data(text.utf8)
        savedData = data
        savedText = text
        return data
    }

    // MARK: - Living in the workspace

    override func makeWindowControllers() {
        refreshName()
        WorkspaceWindowController.forNewDocument().add(self)
    }

    override func showWindows() {
        WorkspaceWindowController.containing(self)?.show(self)
    }

    override var windowForSheet: NSWindow? {
        WorkspaceWindowController.containing(self)?.window ?? super.windowForSheet
    }

    override func close() {
        WorkspaceWindowController.containing(self)?.remove(self)
        super.close()
    }

    /// Saving, renaming and moving change the file's URL, and with it the tab's name.
    @ObservationIgnored nonisolated override var fileURL: URL? {
        didSet {
            DispatchQueue.main.async { [self] in refreshName() }
        }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        isEdited = isDocumentEdited
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        isEdited = isDocumentEdited
    }

    private func refreshName() {
        if let fileURL {
            name = fileURL.deletingPathExtension().lastPathComponent
            fileExtension = fileURL.pathExtension.isEmpty ? "" : "." + fileURL.pathExtension
        } else {
            name = displayName
            fileExtension = ".md"
        }
    }
}
