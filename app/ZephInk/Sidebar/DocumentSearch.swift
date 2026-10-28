import AppKit
import Observation

/// Find in All Documents: searches every open document, in every window, as you type.
@Observable
final class DocumentSearch {
    struct Match: Identifiable {
        let id = UUID()
        weak var document: MarkdownDocument?
        var range: NSRange
        /// The line around the match, and where the match is in it.
        var snippet: String
        var highlight: Range<String.Index>?
    }

    struct Group: Identifiable {
        let id: ObjectIdentifier
        var name: String
        var matches: [Match]
    }

    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var groups: [Group] = []
    private(set) var total = 0

    /// Stop counting after this many matches in one document.
    static let limitPerDocument = 200

    @ObservationIgnored private var pending: DispatchWorkItem?

    private func scheduleSearch() {
        pending?.cancel()
        let search = DispatchWorkItem { [weak self] in self?.run() }
        pending = search
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: search)
    }

    /// Searches again (also when documents change while the panel is open).
    func run() {
        let documents = WorkspaceWindowController.all.flatMap { $0.workspace.tabs.map(\.document) }
        let found = Self.search(query, in: documents.map { ($0, $0.storage.string as NSString) })
        groups = found.groups
        total = found.total
    }

    /// Case- and accent-insensitive matches of `query` in each text.
    static func search(_ query: String, in texts: [(MarkdownDocument, NSString)]) -> (groups: [Group], total: Int) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ([], 0) }
        var groups: [Group] = []
        var total = 0
        for (document, text) in texts {
            var matches: [Match] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while matches.count < limitPerDocument {
                let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                guard found.location != NSNotFound else { break }
                matches.append(match(found, in: text, document: document))
                let next = NSMaxRange(found)
                searchRange = NSRange(location: next, length: text.length - next)
            }
            if !matches.isEmpty {
                groups.append(Group(id: ObjectIdentifier(document), name: document.name + document.fileExtension, matches: matches))
                total += matches.count
            }
        }
        return (groups, total)
    }

    private static func match(_ range: NSRange, in text: NSString, document: MarkdownDocument) -> Match {
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
        let line = NSRange(location: lineStart, length: max(contentsEnd, NSMaxRange(range)) - lineStart)
        // Up to 40 characters before the match and 60 after, on its line.
        let start = max(line.location, range.location - 40)
        let end = min(NSMaxRange(line), NSMaxRange(range) + 60)
        var snippet = text.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let prefix = start > line.location ? "…" : ""
        snippet = prefix + snippet
        let offset = (prefix as NSString).length + range.location - start
        let lower = snippet.utf16.index(snippet.startIndex, offsetBy: offset, limitedBy: snippet.endIndex)
        let upper = lower.flatMap { snippet.utf16.index($0, offsetBy: range.length, limitedBy: snippet.endIndex) }
        let highlight = lower.flatMap { lower in upper.map { lower..<$0 } }
        return Match(document: document, range: range, snippet: snippet, highlight: highlight)
    }
}
