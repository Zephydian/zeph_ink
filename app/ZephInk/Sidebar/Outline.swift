import Foundation
import Observation

/// A document's headings, for the outline sidebar, and which one the cursor is under.
@Observable
final class Outline {
    struct Heading: Identifiable, Equatable {
        /// Where the heading's line starts in the text.
        var location: Int
        var level: Int
        var title: String
        var id: Int { location }
    }

    private(set) var headings: [Heading] = []
    /// The heading the cursor is under (the last one above it).
    private(set) var current: Heading.ID?

    /// The headings in an analysis, without their `#` symbols.
    static func headings(in analysis: MarkdownAnalysis, text: NSString) -> [Heading] {
        analysis.lines.compactMap { line in
            guard case .heading(let level) = line.kind, line.range.length > 0 else { return nil }
            var title = text.substring(with: line.range)
            // Take away the symbols, last first so the earlier ranges stay right.
            for marker in line.markers.sorted(by: { $0.location > $1.location })
            where NSIntersectionRange(marker, line.range).length == marker.length {
                let local = NSRange(location: marker.location - line.range.location, length: marker.length)
                title = (title as NSString).replacingCharacters(in: local, with: "")
            }
            title = title.replacingOccurrences(of: #"[*_`~]|==|\[|\]\([^)]*\)"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            // A setext heading's underline is its own line: only the text line counts.
            guard !title.isEmpty, !title.allSatisfy({ $0 == "=" || $0 == "-" }) else { return nil }
            return Heading(location: line.range.location, level: level, title: title)
        }
    }

    func update(from analysis: MarkdownAnalysis, text: NSString, cursor: Int) {
        let headings = Self.headings(in: analysis, text: text)
        if headings != self.headings { self.headings = headings }
        updateCurrent(cursor: cursor)
    }

    func updateCurrent(cursor: Int) {
        let current = headings.last { $0.location <= cursor }?.id
        if current != self.current { self.current = current }
    }
}
