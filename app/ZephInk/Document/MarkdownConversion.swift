import AppKit
import UniformTypeIdentifiers

/// File → Convert to Markdown: saves a copy of a `.txt` file as `name.md` next to it and opens the copy
/// in the same tab. The `.txt` file is never changed or deleted.
enum MarkdownConversion {
    static func convert(_ document: MarkdownDocument, in controller: WorkspaceWindowController) {
        guard let source = document.fileURL else { return }
        // Keep any edits made to the .txt itself before closing it.
        document.autosave(withImplicitCancellability: false) { _ in
            DispatchQueue.main.async {
                let data = document.format.encode(document.storage.string).data
                let target = source.deletingPathExtension().appendingPathExtension("md")
                if !FileManager.default.fileExists(atPath: target.path), let access = writeBeside(source, to: target, data: data) {
                    open(target, replacing: document, in: controller, keeping: access)
                } else {
                    askWhereToSave(data, suggesting: target, replacing: document, in: controller)
                }
            }
        }
    }

    /// Writes the copy next to the original. The sandbox allows this because markdown is declared a
    /// related type (`NSIsRelatedItemType`) and the write is coordinated with the original as the
    /// primary file. The access lasts while the returned presenter is registered, so the converted
    /// document keeps it until it closes.
    private static func writeBeside(_ source: URL, to target: URL, data: Data) -> RelatedFilePresenter? {
        let presenter = RelatedFilePresenter(primary: source, item: target)
        NSFileCoordinator.addFilePresenter(presenter)
        var coordinationError: NSError?
        var written = false
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: target, options: [], error: &coordinationError) { url in
            written = (try? data.write(to: url, options: .withoutOverwriting)) != nil
        }
        guard written, coordinationError == nil else {
            NSFileCoordinator.removeFilePresenter(presenter)
            return nil
        }
        return presenter
    }

    /// When the copy can't go next to the original (a file with that name exists, or the folder is
    /// read-only), asks where to save it.
    private static func askWhereToSave(_ data: Data, suggesting target: URL, replacing document: MarkdownDocument,
                                       in controller: WorkspaceWindowController) {
        guard let window = controller.window else { return }
        let panel = NSSavePanel()
        panel.directoryURL = target.deletingLastPathComponent()
        panel.nameFieldStringValue = target.lastPathComponent
        panel.allowedContentTypes = [UTType(MarkdownDocument.markdownType) ?? .plainText]
        panel.message = "Save a markdown copy of this text file. The .txt file stays as it is."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                open(url, replacing: document, in: controller, keeping: nil)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    private static func open(_ url: URL, replacing document: MarkdownDocument, in controller: WorkspaceWindowController,
                             keeping access: RelatedFilePresenter?) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { opened, _, error in
            if let opened = opened as? MarkdownDocument {
                opened.relatedFileAccess = access
                controller.replace(document, with: opened)
            } else {
                if let access { NSFileCoordinator.removeFilePresenter(access) }
                if let error, let window = controller.window { NSAlert(error: error).beginSheetModal(for: window) }
            }
        }
    }
}

/// Presents a file related to another (`name.md` beside `name.txt`) so the sandbox lets the app write it.
nonisolated final class RelatedFilePresenter: NSObject, NSFilePresenter {
    let primaryPresentedItemURL: URL?
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main

    init(primary: URL, item: URL) {
        primaryPresentedItemURL = primary
        presentedItemURL = item
    }
}
