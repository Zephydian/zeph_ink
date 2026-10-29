import AppKit
import Markdown
import UniformTypeIdentifiers

/// Edit → Copy as Rich Text: puts the selected markdown on the clipboard as formatted text (HTML and
/// RTF), so it pastes into Mail, Pages or Google Docs with its headings, bold, lists and links, and no
/// markdown symbols. Plain-text places get the words without symbols.
enum RichCopy {
    /// Copies `markdown`. Images are found relative to `folder` and copied along when Zeph#Ink can read them.
    static func copy(_ markdown: String, folder: URL?, to pasteboard: NSPasteboard = .general) {
        let html = html(for: markdown, folder: folder)
        let rich = try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html,
                                                                             .characterEncoding: String.Encoding.utf8.rawValue],
                                           documentAttributes: nil)
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        if let rich {
            if let rtf = rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]) {
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(rich.string.trimmingCharacters(in: .newlines), forType: .string)
        } else {
            pasteboard.setString(markdown, forType: .string)
        }
    }

    /// The markdown as a small HTML document.
    static func html(for markdown: String, folder: URL?) -> String {
        var body = HTMLFormatter.format(PrintLayout.withoutFrontMatter(markdown))
        body = outsideCode(body) { part in
            var part = highlight.stringByReplacingMatches(in: part, range: NSRange(location: 0, length: (part as NSString).length),
                                                          withTemplate: "<mark>$1</mark>")
            // Checkboxes as characters: form controls don't survive pasting.
            part = part.replacingOccurrences(of: #"<input type="checkbox" disabled="" checked="" /> "#, with: "☑ ")
            part = part.replacingOccurrences(of: #"<input type="checkbox" disabled="" /> "#, with: "☐ ")
            // A list item of one paragraph is just its text, so it pastes as one tight line.
            return listParagraph.stringByReplacingMatches(in: part, range: NSRange(location: 0, length: (part as NSString).length),
                                                          withTemplate: "<li>$1$2</li>")
        }
        body = embeddingImages(body, folder: folder)
        return """
        <html><head><meta charset="utf-8"><style>
        body { font-family: Helvetica, Arial, sans-serif; }
        code, pre { font-family: Menlo, monospace; }
        mark { background-color: #FFF0A3; }
        </style></head><body>
        \(body)</body></html>
        """
    }

    private static let highlight = try! NSRegularExpression(pattern: #"==([^=\n](?:[^\n]*?[^=\n])?)=="#)
    private static let code = try! NSRegularExpression(pattern: #"<pre>[\s\S]*?</pre>|<code>[\s\S]*?</code>"#)
    private static let listParagraph = try! NSRegularExpression(pattern: #"<li>((?:☑ |☐ )?)<p>((?:(?!</?p>)[\s\S])*)</p>\n</li>"#)
    private static let image = try! NSRegularExpression(pattern: #"<img src="([^"]+)""#)

    /// Changes the HTML outside `<pre>` and `<code>`, where `==` and the like are just text.
    private static func outsideCode(_ html: String, _ change: (String) -> String) -> String {
        let ns = html as NSString
        var result = "", location = 0
        for match in code.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += change(ns.substring(with: NSRange(location: location, length: match.range.location - location)))
            result += ns.substring(with: match.range)
            location = NSMaxRange(match.range)
        }
        return result + change(ns.substring(from: location))
    }

    /// Images next to the document go into the HTML itself, since the place it's pasted can't see the folder.
    private static func embeddingImages(_ html: String, folder: URL?) -> String {
        guard let folder else { return html }
        let ns = html as NSString
        var result = html
        for match in image.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let source = ns.substring(with: match.range(at: 1))
            guard !source.contains("://"), !source.hasPrefix("data:") else { continue }
            let path = (source.removingPercentEncoding ?? source).replacingOccurrences(of: "&amp;", with: "&")
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
            _ = FolderAccess.open(folder)
            guard let data = try? Data(contentsOf: url),
                  let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else { continue }
            let range = Range(match.range(at: 1), in: result)!
            result.replaceSubrange(range, with: "data:\(type);base64,\(data.base64EncodedString())")
        }
        return result
    }
}
