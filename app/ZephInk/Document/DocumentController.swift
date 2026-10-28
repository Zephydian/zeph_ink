import AppKit

/// AppKit's document controller, with one change: quitting never asks "Do you want to save?". Every
/// changed document is autosaved instead (untitled ones into the app's container), and the session
/// remembers them, so the next launch reopens everything as it was.
///
/// Closing a tab or a window still asks about unsaved untitled documents, like any Mac app.
final class DocumentController: NSDocumentController {
    /// New documents are markdown, or plain text if Settings says so.
    override var defaultType: String? {
        Preferences.defaultType == .plainText ? MarkdownDocument.plainTextType : MarkdownDocument.markdownType
    }

    override func reviewUnsavedDocuments(withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
                                         didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let edited = documents.filter(\.isDocumentEdited)
        autosave(edited) { failed in
            if failed.isEmpty {
                Session.current().save()
                Session.isFrozen = true
                Self.report(true, to: delegate, selector: didReviewAllSelector, contextInfo: contextInfo)
            } else {
                // Couldn't keep something (a file that was deleted, say): ask the usual way.
                super.reviewUnsavedDocuments(withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                                             didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
            }
        }
    }

    /// Autosaves each document in turn, then reports which ones failed.
    private func autosave(_ documents: [NSDocument], failed: [NSDocument] = [], then finish: @escaping ([NSDocument]) -> Void) {
        guard let document = documents.first else { return finish(failed) }
        document.autosave(withImplicitCancellability: false) { [weak self] error in
            DispatchQueue.main.async {
                self?.autosave(Array(documents.dropFirst()), failed: error == nil ? failed : failed + [document], then: finish)
            }
        }
    }

    /// Calls AppKit's "did review all" callback: `-documentController:didReviewAll:contextInfo:`.
    private static func report(_ shouldProceed: Bool, to delegate: Any?, selector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        guard let delegate = delegate as? NSObject, let selector, delegate.responds(to: selector) else { return }
        typealias Callback = @convention(c) (NSObject, Selector, NSDocumentController, Bool, UnsafeMutableRawPointer?) -> Void
        let callback = unsafeBitCast(delegate.method(for: selector), to: Callback.self)
        callback(delegate, selector, NSDocumentController.shared, shouldProceed, contextInfo)
    }
}
