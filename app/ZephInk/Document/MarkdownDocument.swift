import AppKit
import Observation

/// A markdown (or plain text) file. Its text storage *is* the file: the editor shows and edits it
/// directly, and saving writes it back. A document you open and save without changing it is written back
/// byte for byte, and an edited one keeps its encoding and line breaks (`FileText`).
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
    /// How the file stores its text, kept so saving stores it the same way.
    @ObservationIgnored private(set) var format = FileText.standard

    /// A file reopened after a relaunch, which the sandbox lets Zeph#Ink use until the document closes.
    @ObservationIgnored var securityScopedURL: URL?
    /// A file made by Convert to Markdown, which the sandbox lets Zeph#Ink use while this presenter is
    /// registered (until the document closes).
    @ObservationIgnored var relatedFileAccess: RelatedFilePresenter?

    static let markdownType = "net.daringfireball.markdown"
    static let plainTextType = "public.plain-text"

    /// A `.txt` file: shown as plain text, without markdown styling or formatting tools.
    var isPlainText: Bool { fileType == Self.plainTextType }

    nonisolated override class var autosavesInPlace: Bool { true }

    // AppKit reads and writes documents on the main thread unless a document opts into doing it in the
    // background (`canConcurrentlyReadDocuments`, `canAsynchronouslyWrite`), which this one doesn't.

    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let (text, format) = try FileText.decode(data)
        MainActor.assumeIsolated {
            savedData = data
            savedText = text
            self.format = format
            // Replace in place (rather than swapping the storage) so an open editor follows a revert.
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = storage.string
        if text == savedText, let savedData {
            return savedData
        }
        let (data, format) = format.encode(text)
        self.format = format
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
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        if let relatedFileAccess { NSFileCoordinator.removeFilePresenter(relatedFileAccess) }
        relatedFileAccess = nil
    }

    /// Saving, renaming and moving change the file's URL, and with it the tab's name.
    @ObservationIgnored nonisolated override var fileURL: URL? {
        didSet {
            DispatchQueue.main.async { [self] in refreshName() }
        }
    }

    // MARK: - Changes made by other apps

    /// Another app changed the file. AppKit tells the document, but only reloads documents that have
    /// windows of their own, so Zeph#Ink does it: a document without unsaved changes reloads quietly,
    /// and one with changes asks whether to reload or keep its version.
    nonisolated override func presentedItemDidChange() {
        super.presentedItemDidChange()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.fileDidChangeOnDisk() }
        }
    }

    @ObservationIgnored private var isAskingAboutOutsideChange = false

    private func fileDidChangeOnDisk() {
        guard let fileURL, let fileType, !isAskingAboutOutsideChange,
              let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let known = fileModificationDate, modified > known else { return }
        // Touched but not changed (or changed back): nothing to do.
        if let onDisk = try? Data(contentsOf: fileURL), onDisk == savedData {
            fileModificationDate = modified
            return
        }
        guard isDocumentEdited else {
            try? revert(toContentsOf: fileURL, ofType: fileType)
            return
        }
        guard let window = windowForSheet else { return }
        isAskingAboutOutsideChange = true
        let alert = NSAlert()
        alert.messageText = "“\(fileURL.lastPathComponent)” was changed by another app."
        alert.informativeText = "Reload it to see those changes, or keep your version. Keeping your version replaces theirs the next time it saves."
        alert.addButton(withTitle: "Keep My Version")
        alert.addButton(withTitle: "Reload")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isAskingAboutOutsideChange = false
            if response == .alertSecondButtonReturn {
                try? self.revert(toContentsOf: fileURL, ofType: fileType)
            } else {
                self.fileModificationDate = modified   // so saving doesn't warn about the other app's change
            }
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
            fileExtension = isPlainText ? ".txt" : ".md"
        }
    }
}
