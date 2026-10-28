import Foundation
import Observation

/// What the toolbar and the Format menu show for the selection: the paragraph style, and which
/// styles and lists are on. The editor updates it whenever the selection or the text changes.
@Observable
final class FormattingState {
    var paragraph: MarkdownCommands.Paragraph = .body
    var inline: Set<MarkdownCommands.Inline> = []
    var list: MarkdownCommands.ListKind?
    var isInLink = false
    var alignment: MarkdownCommands.Alignment = .left
    /// The pane shows the markdown source rather than the page.
    var isSourceMode = false

    func update(text: NSString, selection: NSRange, analysis: MarkdownAnalysis) {
        let paragraph = MarkdownCommands.paragraph(at: selection.location, in: text, analysis: analysis)
        let inline = Set(MarkdownCommands.Inline.allCases.filter {
            MarkdownCommands.span(of: $0, at: selection, in: text, analysis: analysis) != nil
        })
        let list = MarkdownCommands.list(at: selection.location, in: text)
        let isInLink = MarkdownCommands.link(at: selection, in: text, analysis: analysis) != nil
        let alignment = MarkdownCommands.alignment(at: selection.location, analysis: analysis)
        if self.alignment != alignment { self.alignment = alignment }
        // Only assign what changed, so SwiftUI redraws only what it must.
        if self.paragraph != paragraph { self.paragraph = paragraph }
        if self.inline != inline { self.inline = inline }
        if self.list != list { self.list = list }
        if self.isInLink != isInLink { self.isInLink = isInLink }
    }
}
