import AppKit

/// One document's text view and its scroll view, built on TextKit 2 around the document's own storage.
///
/// An editor lives as long as its tab, so switching tabs keeps each document's selection, scroll
/// position and undo history.
final class Editor {
    let scrollView = NSScrollView()
    let textView: ZephTextView
    /// The layout manager only holds this weakly, so the editor keeps it.
    private let contentStorage = NSTextContentStorage()

    init(document: MarkdownDocument) {
        contentStorage.textStorage = document.storage
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        textView = ZephTextView(frame: .zero, textContainer: container)

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        // Markdown is plain text: smart quotes, dashes and replacements would change what the person typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.font = Theme.bodyFont
        textView.textColor = Theme.ink
        textView.backgroundColor = Theme.page
        textView.insertionPointColor = Theme.accent
        textView.textContainerInset = Theme.pageInset
        textView.typingAttributes = [.font: Theme.bodyFont, .foregroundColor: Theme.ink]
        textView.setAccessibilityLabel("Document")

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.page

        // Text read from disk has no attributes yet; give it the page's look.
        let storage = document.storage
        storage.addAttributes([.font: Theme.bodyFont, .foregroundColor: Theme.ink],
                              range: NSRange(location: 0, length: storage.length))
    }
}
