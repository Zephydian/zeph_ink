import AppKit
import UniformTypeIdentifiers

/// File → Export as PDF…: asks where to save, then writes the document's pages (`PrintLayout`) on the
/// paper from Settings → PDF.
enum PDFExport {
    static func run(_ document: MarkdownDocument, in window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.name + ".pdf"
        panel.canCreateDirectories = true
        if let folder = document.fileURL?.deletingLastPathComponent() { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let data = PrintLayout(document: document, paper: Preferences.paperSize.size).pdfData()
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }
}

extension MarkdownDocument {
    /// File → Print… prints the same pages as Export as PDF, on the paper chosen in Page Setup.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.dictionary().addEntries(from: printSettings)
        // The pages carry their own margins.
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        let view = PrintView(layout: PrintLayout(document: self, paper: info.paperSize))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = name
        return operation
    }
}
