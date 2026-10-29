import AppKit

/// Turns formatted text from the clipboard (a web page, Word, Google Docs, Pages) into clean markdown:
/// headings, bold, italic, strikethrough, code, links, lists, quotes and dividers. Everything else
/// (fonts, colors, sizes) is left behind.
nonisolated enum RichPaste {
    /// Markdown for the clipboard's formatted text, or nil when it has none worth keeping (plain
    /// text, or text from apps like code editors that only add colors). `lineBreak` is the document's.
    static func markdown(from pasteboard: NSPasteboard, lineBreak: String) -> String? {
        if let html = pasteboard.string(forType: .html), let markdown = markdown(fromHTML: html) {
            return normalize(markdown, lineBreak: lineBreak)
        }
        // RTF only (TextEdit, some older apps): go through HTML.
        for type in [NSPasteboard.PasteboardType.rtf, .rtfd] {
            guard let data = pasteboard.data(forType: type),
                  let text = NSAttributedString(rtf: data, documentAttributes: nil) ?? NSAttributedString(rtfd: data, documentAttributes: nil),
                  let html = try? text.data(from: NSRange(location: 0, length: text.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
                  let string = String(data: html, encoding: .utf8) else { continue }
            if let markdown = markdown(fromHTML: string) { return normalize(markdown, lineBreak: lineBreak) }
        }
        return nil
    }

    /// Markdown for an HTML fragment, or nil if it has no structure or styles markdown can keep.
    static func markdown(fromHTML html: String) -> String? {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement() else { return nil }
        let body = root.elements(forName: "body").first ?? root
        var converter = Converter()
        let blocks = converter.blocks(of: body, list: nil)
        guard converter.foundFormatting else { return nil }
        let text = blocks.map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private static func normalize(_ markdown: String, lineBreak: String) -> String {
        FileText(encoding: .utf8, byteOrderMark: Data(), lineBreak: lineBreak).normalizingLineBreaks(markdown)
    }

    // MARK: - Walking the HTML

    private struct Converter {
        /// Whether anything markdown can show turned up (otherwise plain text is the better paste).
        var foundFormatting = false

        enum List {
            case bulleted(depth: Int)
            case numbered(depth: Int)
        }

        private static let blockTags: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li",
                                                     "blockquote", "pre", "hr", "table", "tr", "section", "article", "header", "footer"]

        /// The blocks inside an element, each one paragraph of markdown.
        mutating func blocks(of element: XMLNode, list: List?) -> [String] {
            var blocks: [String] = []
            var inline = ""
            func flush() {
                let text = inline.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { blocks.append(text) }
                inline = ""
            }
            for child in element.children ?? [] {
                guard let element = child as? XMLElement, let name = element.name?.lowercased(), Self.blockTags.contains(name) else {
                    inline += self.inline(child)
                    continue
                }
                flush()
                blocks += block(element, name: name, list: list)
            }
            flush()
            return blocks
        }

        private mutating func block(_ element: XMLElement, name: String, list: List?) -> [String] {
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                foundFormatting = true
                let level = min(Int(name.dropFirst()) ?? 1, 4)
                let text = inline(element).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + stripBold(text)]
            case "ul", "ol":
                foundFormatting = true
                let depth: Int
                switch list { case .bulleted(let d), .numbered(let d): depth = d + 1; case nil: depth = 0 }
                var number = 0
                var items: [String] = []
                for child in element.children ?? [] {
                    guard let item = child as? XMLElement, item.name?.lowercased() == "li" else { continue }
                    number += 1
                    let marker = name == "ol" ? "\(number). " : "- "
                    let nested = blocks(of: item, list: name == "ol" ? .numbered(depth: depth) : .bulleted(depth: depth))
                    let indent = String(repeating: "  ", count: depth)
                    if let first = nested.first {
                        items.append(indent + marker + first.replacingOccurrences(of: "\n", with: " "))
                        items += nested.dropFirst()
                    }
                }
                return [items.joined(separator: "\n")]
            case "li":
                return blocks(of: element, list: list)
            case "blockquote":
                foundFormatting = true
                return [blocks(of: element, list: nil).joined(separator: "\n\n")
                    .components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")]
            case "pre":
                foundFormatting = true
                let code = element.stringValue ?? ""
                return ["```\n" + code.trimmingCharacters(in: .newlines) + "\n```"]
            case "hr":
                foundFormatting = true
                return ["---"]
            default:
                return blocks(of: element, list: list)
            }
        }

        /// Text with inline styles as markdown.
        private mutating func inline(_ node: XMLNode) -> String {
            guard let element = node as? XMLElement, let name = element.name?.lowercased() else {
                // Runs of whitespace (including line breaks in the source) are one space in HTML.
                return (node.stringValue ?? "").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            }
            let inner = (element.children ?? []).map { inline($0) }.joined()
            let style = (element.attribute(forName: "style")?.stringValue ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            switch name {
            case "br": return "\n"
            case "script", "style", "head", "title", "meta": return ""
            case "code", "kbd", "samp":
                foundFormatting = true
                let code = element.stringValue ?? ""
                return code.isEmpty ? "" : "`" + code + "`"
            case "a":
                guard let href = element.attribute(forName: "href")?.stringValue, !href.isEmpty, !href.hasPrefix("#"),
                      !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return inner }
                foundFormatting = true
                return "[" + inner.trimmingCharacters(in: .whitespaces) + "](" + href.replacingOccurrences(of: " ", with: "%20") + ")"
            case "img":
                let alt = element.attribute(forName: "alt")?.stringValue ?? ""
                guard let source = element.attribute(forName: "src")?.stringValue, source.hasPrefix("http") else { return alt }
                foundFormatting = true
                return "![" + alt + "](" + source + ")"
            default:
                break
            }
            // Google Docs wraps everything in <b style="font-weight:normal">, and styles spans instead.
            let isBold = (["strong", "b"].contains(name) && !style.contains("font-weight:normal") && !style.contains("font-weight:400"))
                || style.contains("font-weight:bold") || style.range(of: #"font-weight:[6-9]00"#, options: .regularExpression) != nil
            let isItalic = ["em", "i"].contains(name) || style.contains("font-style:italic")
            let isStruck = ["del", "s", "strike"].contains(name) || style.contains("line-through")
            return wrap(inner, bold: isBold, italic: isItalic, struck: isStruck)
        }

        /// Wraps text in markdown symbols, keeping its outer spaces outside them (`** bold**` isn't bold).
        private mutating func wrap(_ text: String, bold: Bool, italic: Bool, struck: Bool) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, bold || italic || struck else { return text }
            foundFormatting = true
            var marked = trimmed
            if struck { marked = "~~" + marked + "~~" }
            if italic { marked = "*" + marked + "*" }
            if bold { marked = "**" + marked + "**" }
            let leading = text.prefix { $0 == " " }, trailing = String(text.reversed().prefix { $0 == " " })
            return leading + marked + trailing
        }

        /// Headings are bold already: drop bold that covers a whole heading.
        private func stripBold(_ text: String) -> String {
            text.hasPrefix("**") && text.hasSuffix("**") && text.count > 4 ? String(text.dropFirst(2).dropLast(2)) : text
        }
    }
}
