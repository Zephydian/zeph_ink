import AppKit
import SwiftUI

/// The one-row formatting bar under the tabs: the paragraph style menu, inline styles, lists and
/// blocks, then (on the right) the source view switch. Every button does what a Format menu item does,
/// on the focused pane, and lights up when its style is on at the cursor.
///
/// In a `.txt` file the formatting buttons are dimmed (their tooltip says why) and a Convert to
/// Markdown button appears instead of the source switch.
struct Toolbar: View {
    static let isShownKey = "showsToolbar"
    static var isShown: Bool { UserDefaults.standard.object(forKey: isShownKey) as? Bool ?? true }

    let editor: Editor
    let controller: WorkspaceWindowController

    private var state: FormattingState { editor.formatting }
    private var isOff: Bool { editor.isPlainText }

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    plainButton("arrow.uturn.backward", "Undo", "⌘Z") { $0.undoManager?.undo() }
                    plainButton("arrow.uturn.forward", "Redo", "⌘⇧Z") { $0.undoManager?.redo() }
                    Separator()
                    StyleMenuButton(editor: editor, isOff: isOff, run: run)
                    TextSizeMenu(size: state.textSize, isOff: isOff) { size in run { $0.setTextSize(size) } }
                    Separator()
                    button("text.alignleft", .symbol, "Align left", "⌘{", "the normal alignment", on: state.alignment == .left) { $0.alignLeft(nil) }
                    button("text.aligncenter", .symbol, "Center", "⌘|", "<div align=\"center\"> around the paragraph",
                           on: state.alignment == .center) { $0.alignCenter(nil) }
                    button("text.alignright", .symbol, "Align right", "⌘}", "<div align=\"right\"> around the paragraph",
                           on: state.alignment == .right) { $0.alignRight(nil) }
                    Separator()
                    button("B", .serif(.bold), "Bold", "⌘B", "**text**", on: state.inline.contains(.bold)) { $0.toggleBold(nil) }
                    button("I", .serif(.italic), "Italic", "⌘I", "*text*", on: state.inline.contains(.italic)) { $0.toggleItalic(nil) }
                    button("S", .serif(.strikethrough), "Strikethrough", "⌘⇧X", "~~text~~", on: state.inline.contains(.strikethrough)) { $0.toggleStrikethrough(nil) }
                    button("highlighter", .symbol, "Highlight", "⌘⇧H", "==text== (a markdown extension: some apps show the = signs)",
                           on: state.inline.contains(.highlight)) { $0.toggleHighlight(nil) }
                    button("</>", .mono, "Inline code", "⌘E", "`code`", on: state.inline.contains(.code)) { $0.toggleInlineCode(nil) }
                    button("link", .symbol, "Link", "⌘K", "[text](url)", on: state.isInLink) { $0.editLink(nil) }
                    button("eraser", .symbol, "Clear formatting", nil, "removes the markdown, keeps the words", on: false) { $0.clearFormatting(nil) }
                    Separator()
                    button("list.bullet", .symbol, "Bulleted list", "⌘⇧8", "- item", on: state.list == .bulleted) { $0.toggleBulletedList(nil) }
                    button("list.number", .symbol, "Numbered list", "⌘⇧7", "1. item", on: state.list == .numbered) { $0.toggleNumberedList(nil) }
                    button("checklist", .symbol, "Checklist", "⌘⇧9", "- [ ] task", on: state.list == .checklist) { $0.toggleChecklist(nil) }
                    button("text.quote", .symbol, "Quote", "⌘⇧.", "> text", on: state.paragraph == .quote) { $0.toggleQuote(nil) }
                    button("minus", .symbol, "Divider", nil, "---", on: false) { $0.insertDivider(nil) }
                    button("photo", .symbol, "Image", nil, "![alt](assets/file.png)", on: false) { $0.insertImage(nil) }
                    plainButton("face.smiling", "Emoji & symbols", "⌃⌘Space") { _ in NSApp.orderFrontCharacterPalette(nil) }
                }
            }
            Spacer(minLength: 12)
            if isOff {
                Button("Convert to Markdown") { controller.convertToMarkdown(nil) }
                    .buttonStyle(ProminentButtonStyle())
                    .help("Saves a .md copy of this file next to it, and opens it here. The .txt file stays as it is.")
            } else {
                Button("MD") { controller.toggleSourceView(nil) }
                    .buttonStyle(MarkdownToggleStyle(isOn: state.isSourceMode))
                    .help(state.isSourceMode ? "Back to page view — ⌘/" : "Show the markdown source — ⌘/")
                    .accessibilityLabel(state.isSourceMode ? "Page view" : "Markdown source")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(Color(nsColor: Theme.chrome))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatting")
    }

    private static let offHelp = "Formatting is available in Markdown documents. Convert this file to use it."

    /// Runs a formatting action on the focused text view, then gives it the focus back.
    private func run(_ action: (ZephTextView) -> Void) {
        guard !isOff else { return }
        action(editor.textView)
        editor.textView.window?.makeFirstResponder(editor.textView)
    }

    /// A button that works in every document, `.txt` included (undo, redo, emoji).
    private func plainButton(_ symbol: String, _ name: String, _ shortcut: String, action: @escaping (ZephTextView) -> Void) -> some View {
        Button {
            action(editor.textView)
            editor.textView.window?.makeFirstResponder(editor.textView)
        } label: {
            Image(systemName: symbol).font(.system(size: 14))
        }
        .buttonStyle(ToolbarButtonStyle(isOn: false, isOff: false))
        .help("\(name) — \(shortcut)")
        .accessibilityLabel(name)
    }

    private func button(_ label: String, _ look: ButtonLook, _ name: String, _ shortcut: String?, _ syntax: String,
                        on: Bool, action: @escaping (ZephTextView) -> Void) -> some View {
        Button { run(action) } label: {
            switch look {
            case .symbol: Image(systemName: label).font(.system(size: 14, weight: .regular))
            case .mono: Text(label).font(.custom("JetBrains Mono", size: 12))
            case .serif(let style):
                Text(label)
                    .font(.custom("Literata", size: 15).weight(style == .bold ? .heavy : .regular))
                    .italic(style == .italic)
                    .strikethrough(style == .strikethrough)
            }
        }
        .buttonStyle(ToolbarButtonStyle(isOn: on && !isOff, isOff: isOff))
        .help(isOff ? Self.offHelp : [name, shortcut, syntax].compactMap { $0 }.joined(separator: " — "))
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    enum ButtonLook {
        enum Serif { case bold, italic, strikethrough }
        case symbol, mono, serif(Serif)
    }
}

/// The paragraph style menu: shows the style at the cursor, and lists every style drawn in its own look.
private struct StyleMenuButton: View {
    let editor: Editor
    let isOff: Bool
    let run: ((ZephTextView) -> Void) -> Void
    @State private var isOpen = false

    private static let styles: [(MarkdownCommands.Paragraph, String, String)] = [
        (.title, "Title", "⌘1"), (.heading, "Heading", "⌘2"), (.subheading, "Subheading", "⌘3"),
        (.smallHeading, "Small heading", "⌘4"), (.body, "Body", "⌘0"), (.quote, "Quote", "⌘⇧."), (.codeBlock, "Code block", ""),
    ]

    private var current: String {
        isOff ? "Plain text" : Self.styles.first { $0.0 == editor.formatting.paragraph }?.1 ?? "Body"
    }

    var body: some View {
        Button {
            if !isOff { isOpen.toggle() }
        } label: {
            HStack {
                Text(current).font(.system(size: 13))
                Spacer(minLength: 6)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
            }
            .padding(.horizontal, 10)
            .frame(width: 148, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: Theme.chromeSurface)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: Theme.chromeLine)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: Theme.chromeInk))
        .opacity(isOff ? 0.35 : 1)
        .help(isOff ? "Formatting is available in Markdown documents. Convert this file to use it." : "Paragraph style — ⌘0 to ⌘4")
        .accessibilityLabel("Paragraph style, \(current)")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.styles, id: \.1) { style, name, shortcut in
                    StyleRow(style: style, name: name, shortcut: shortcut, isCurrent: style == editor.formatting.paragraph) {
                        isOpen = false
                        run { $0.setParagraph(style) }
                    }
                }
            }
            .padding(6)
            .frame(width: 240)
        }
    }
}

/// The text size box, like Word's: shows the size at the cursor and sets the selection's size (or the
/// cursor's line's). Choosing the default size takes a size away.
private struct TextSizeMenu: View {
    /// The selection's own size, if it has one.
    let size: CGFloat?
    let isOff: Bool
    let set: (CGFloat) -> Void
    @AppStorage(Preferences.Key.textSize) private var defaultSize = 12.0
    @State private var isOpen = false

    private var shown: Double { Double(size ?? CGFloat(defaultSize)) }

    var body: some View {
        Button {
            if !isOff { isOpen.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(CGFloat(shown).formatted()).font(.system(size: 13).monospacedDigit())
                Spacer(minLength: 2)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
            }
            .padding(.horizontal, 8)
            .frame(width: 58, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: Theme.chromeSurface)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: Theme.chromeLine)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: Theme.chromeInk))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Preferences.textSizes, id: \.self) { step in
                    SizeRow(size: step, isCurrent: abs(Double(step) - shown) < 0.01,
                            isDefault: abs(Double(step) - defaultSize) < 0.01) {
                        isOpen = false
                        set(step)
                    }
                }
            }
            .padding(6)
            .frame(width: 130)
        }
        .padding(.leading, 4)
        .disabled(isOff)
        .opacity(isOff ? 0.35 : 1)
        .help("Text size of the selection, in points — ⌥⌘> / ⌥⌘<. Saved as HTML (<span style=\"font-size:…\">), which GitHub shows at normal size.")
        .accessibilityLabel("Text size, \(CGFloat(shown).formatted()) points")
    }
}

private struct SizeRow: View {
    let size: CGFloat
    let isCurrent: Bool
    let isDefault: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(size.formatted()).font(.system(size: 13).monospacedDigit())
                Spacer()
                if isDefault { Text("default").font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.chromeInkSecondary)) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovered || isCurrent ? Color(nsColor: Theme.accentSoft) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: Theme.chromeInk))
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(size.formatted()) points" + (isDefault ? ", default" : ""))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct StyleRow: View {
    let style: MarkdownCommands.Paragraph
    let name: String
    let shortcut: String
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                preview
                Spacer()
                Text(shortcut).font(.custom("JetBrains Mono", size: 11)).foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovered || isCurrent ? Color(nsColor: Theme.accentSoft) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: Theme.chromeInk))
        .onHover { isHovered = $0 }
        .accessibilityLabel(name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Each style's name, drawn in that style.
    @ViewBuilder private var preview: some View {
        switch style {
        case .title: Text(name).font(.custom("Literata", size: 21).weight(.bold))
        case .heading: Text(name).font(.custom("Literata", size: 17).weight(.bold))
        case .subheading: Text(name).font(.custom("Literata", size: 15).weight(.semibold))
        case .smallHeading: Text(name.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6)
        case .body: Text(name).font(.custom("Literata", size: 14))
        case .quote:
            Text(name).font(.custom("Literata", size: 14)).italic()
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(Color(nsColor: Theme.accent)).frame(width: 2) }
        case .codeBlock: Text(name).font(.custom("JetBrains Mono", size: 12))
        }
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: Theme.chromeLine)).frame(width: 1, height: 20).padding(.horizontal, 6)
    }
}

/// A toolbar button: a hover background, and the accent when its style is on.
private struct ToolbarButtonStyle: ButtonStyle {
    let isOn: Bool
    let isOff: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Color(nsColor: Theme.accent) : Color(nsColor: Theme.chromeInk))
            .frame(minWidth: 32, minHeight: 30)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                isOn ? Color(nsColor: Theme.accentSoft) : (isHovered && !isOff) || configuration.isPressed ? Color(nsColor: Theme.hover) : .clear))
            .contentShape(Rectangle())
            .opacity(isOff ? 0.35 : 1)
            .onHover { isHovered = $0 }
    }
}

/// The MD switch: outlined for page view, filled with the accent for source view.
private struct MarkdownToggleStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("JetBrains Mono", size: 12).weight(.medium))
            .foregroundStyle(isOn ? Color(nsColor: Theme.chromeSurface) : Color(nsColor: Theme.chromeInk))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Color(nsColor: Theme.accent) : Color(nsColor: Theme.chromeSurface)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isOn ? Color(nsColor: Theme.accent) : Color(nsColor: Theme.chromeLine)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A filled accent button for the one call to action (Convert to Markdown).
private struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: Theme.chromeSurface))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: Theme.accent)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
