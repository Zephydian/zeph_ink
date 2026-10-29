import Foundation

/// Which words the spell checker may mark (and autocorrect): words of writing, never markdown.
///
/// macOS's checker (`NSSpellChecker`) finds misspelled words and the text view underlines them, offers
/// suggestions, Ignore and Learn Spelling. It doesn't know markdown, so each word it flags is checked
/// here first. A word is left alone when it's in code (a block or `inline`), front matter, a link or
/// image address (`](address)`, a `[name]: address` definition, a bare `https://…`), an HTML tag, or
/// touches a markdown symbol (`**`, `## `, `- [ ]`).
nonisolated enum Spelling {
    static func allows(_ range: NSRange, in text: NSString, analysis: MarkdownAnalysis) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= text.length, !analysis.lines.isEmpty else { return true }
        func overlaps(_ other: NSRange) -> Bool { NSIntersectionRange(range, other).length > 0 }

        let first = analysis.lineIndex(at: range.location)
        let last = analysis.lineIndex(at: NSMaxRange(range) - 1)
        for line in analysis.lines[first...last] {
            switch line.kind {
            case .code, .frontMatter, .alignTag: return false
            default: break
            }
            if line.markers.contains(where: overlaps) { return false }
            if let list = line.list, overlaps(NSRange(location: list.marker.location, length: list.contentStart - list.marker.location)) {
                return false
            }
            let content = text.substring(with: line.range)
            for pattern in notWriting {
                for match in pattern.matches(in: content, range: NSRange(location: 0, length: (content as NSString).length))
                where overlaps(NSRange(location: line.range.location + match.range.location, length: match.range.length)) {
                    return false
                }
            }
        }
        return !analysis.spans.contains { ($0.style.contains(.code) || $0.style.contains(.marker)) && overlaps($0.range) }
    }

    /// Parts of a line that aren't writing.
    private static let notWriting: [NSRegularExpression] = [
        #"\]\([^)\n]*\)"#,                         // a link or image address: ](address)
        #"^\s{0,3}\[[^\]\n]+\]:\s*\S+.*$"#,          // a link definition: [name]: address
        #"[A-Za-z][A-Za-z0-9+.-]*://[^\s)>]+"#,      // a bare web address
        #"[^\s@<(]+@[^\s@>)]+\.[A-Za-z]{2,}"#,       // an email address
        #"</?[A-Za-z][^>\n]*>"#,                     // an HTML tag
    ].map { try! NSRegularExpression(pattern: $0) }
}
