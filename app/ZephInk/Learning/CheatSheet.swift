import AppKit
import SwiftUI

/// Help → Markdown Cheat Sheet (⌘?), and the toolbar's ? button: every style, its shortcut and what
/// to type for it.
struct CheatSheet: View {
    struct Row: Identifiable {
        var name: String
        var shortcut: String
        var syntax: String
        var id: String { name }
    }

    static let sections: [(String, [Row])] = [
        ("Text", [
            Row(name: "Bold", shortcut: "⌘B", syntax: "**words**"),
            Row(name: "Italic", shortcut: "⌘I", syntax: "*words*"),
            Row(name: "Strikethrough", shortcut: "⌘⇧X", syntax: "~~words~~"),
            Row(name: "Highlight", shortcut: "⌘⇧H", syntax: "==words=="),
            Row(name: "Inline code", shortcut: "⌘E", syntax: "`code`"),
            Row(name: "Link", shortcut: "⌘K", syntax: "[words](address)"),
        ]),
        ("Paragraphs", [
            Row(name: "Title", shortcut: "⌘1", syntax: "# Title"),
            Row(name: "Heading", shortcut: "⌘2", syntax: "## Heading"),
            Row(name: "Subheading", shortcut: "⌘3", syntax: "### Subheading"),
            Row(name: "Small heading", shortcut: "⌘4", syntax: "#### Small heading"),
            Row(name: "Quote", shortcut: "⌘⇧.", syntax: "> words"),
            Row(name: "Code block", shortcut: "", syntax: "``` on the lines around it"),
        ]),
        ("Lists and more", [
            Row(name: "Bulleted list", shortcut: "⌘⇧8", syntax: "- item"),
            Row(name: "Numbered list", shortcut: "⌘⇧7", syntax: "1. item"),
            Row(name: "Checklist", shortcut: "⌘⇧9", syntax: "- [ ] task"),
            Row(name: "Divider", shortcut: "", syntax: "---"),
            Row(name: "Image", shortcut: "", syntax: "![description](file.png)"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Markdown cheat sheet").font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(Self.sections, id: \.0) { title, rows in
                    GridRow {
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .gridCellColumns(3)
                            .padding(.top, 4)
                    }
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.name)
                            Text(row.shortcut).foregroundStyle(.secondary).monospacedDigit()
                            Text(row.syntax).font(Font(Fonts.monoAsTyped(size: 11.5)))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .font(.system(size: 12))
            Text("Type the markdown or use the shortcut: both do the same.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(14)
        .fixedSize()
    }

    /// Shows the cheat sheet as a popover at the top of a text view (when the toolbar's ? button
    /// isn't there to show it under).
    static func show(over textView: NSTextView) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: CheatSheet())
        let visible = textView.visibleRect
        let anchor = NSRect(x: visible.midX, y: visible.minY + 8, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
    }
}
