import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Format menu's actions. The toolbar calls the same ones, and both only insert or remove markdown
/// characters, each change undoable in one step.
extension ZephTextView {
    // MARK: Inline

    @objc func toggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.italic) }
    @objc func toggleStrikethrough(_ sender: Any?) { toggle(.strikethrough) }
    @objc func toggleInlineCode(_ sender: Any?) { toggle(.code) }
    @objc func toggleHighlight(_ sender: Any?) { toggle(.highlight) }

    /// Format → Clear Formatting: the words stay, the markdown around them goes.
    @objc func clearFormatting(_ sender: Any?) {
        guard let editor else { return }
        apply(MarkdownCommands.clearFormatting(text: string as NSString, selection: selectedRange(), analysis: editor.analysis))
    }

    private func toggle(_ inline: MarkdownCommands.Inline) {
        guard let editor else { return }
        apply(MarkdownCommands.toggle(inline, text: string as NSString, selection: selectedRange(), analysis: editor.analysis))
    }

    // MARK: Paragraphs

    @objc func setTitleStyle(_ sender: Any?) { setParagraph(.title) }
    @objc func setHeadingStyle(_ sender: Any?) { setParagraph(.heading) }
    @objc func setSubheadingStyle(_ sender: Any?) { setParagraph(.subheading) }
    @objc func setSmallHeadingStyle(_ sender: Any?) { setParagraph(.smallHeading) }
    @objc func setBodyStyle(_ sender: Any?) { setParagraph(.body) }
    @objc func toggleQuote(_ sender: Any?) { setParagraph(.quote) }
    @objc func toggleCodeBlock(_ sender: Any?) { setParagraph(.codeBlock) }

    func setParagraph(_ style: MarkdownCommands.Paragraph) {
        guard let editor else { return }
        apply(MarkdownCommands.setParagraph(style, text: string as NSString, selection: selectedRange(),
                                            analysis: editor.analysis, lineBreak: editor.lineBreak))
    }

    // MARK: Alignment (the standard Format menu actions, writing markdown instead of attributes)

    override func alignLeft(_ sender: Any?) { setAlignment(.left) }
    override func alignCenter(_ sender: Any?) { setAlignment(.center) }
    override func alignRight(_ sender: Any?) { setAlignment(.right) }

    private func setAlignment(_ alignment: MarkdownCommands.Alignment) {
        guard let editor, editor.handlesMarkdownInput else { return }
        apply(MarkdownCommands.setAlignment(alignment, text: string as NSString, selection: selectedRange(),
                                            analysis: editor.analysis, lineBreak: editor.lineBreak))
    }

    // MARK: Text size

    /// Sets the selection's (or the cursor's line's) text size; the default size takes its own size away.
    func setTextSize(_ size: CGFloat) {
        guard let editor else { return }
        apply(MarkdownCommands.setTextSize(size, defaultSize: Preferences.textSize, text: string as NSString,
                                           selection: selectedRange(), analysis: editor.analysis))
    }

    /// Format → Bigger Text and Smaller Text: one size up or down, for the selection.
    @objc func makeTextBigger(_ sender: Any?) { stepTextSize(bigger: true) }
    @objc func makeTextSmaller(_ sender: Any?) { stepTextSize(bigger: false) }

    private func stepTextSize(bigger: Bool) {
        guard let editor else { return }
        let current = editor.formatting.textSize ?? Preferences.textSize
        setTextSize(Preferences.textSize(after: current, bigger: bigger))
    }

    // MARK: Lists and blocks

    @objc func toggleBulletedList(_ sender: Any?) { toggleList(.bulleted) }
    @objc func toggleNumberedList(_ sender: Any?) { toggleList(.numbered) }
    @objc func toggleChecklist(_ sender: Any?) { toggleList(.checklist) }

    private func toggleList(_ kind: MarkdownCommands.ListKind) {
        apply(MarkdownCommands.toggleList(kind, text: string as NSString, selection: selectedRange()))
    }

    @objc func insertDivider(_ sender: Any?) {
        guard let editor else { return }
        apply(MarkdownCommands.insertBlock("---", text: string as NSString, selection: selectedRange(), lineBreak: editor.lineBreak))
    }

    /// Format → Image…: picks images, copies them into `assets/` next to the document and links them.
    @objc func insertImage(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images to add. They're copied into an “assets” folder next to the document."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            ImageAssets.insert(panel.urls, into: self)
        }
    }

    /// Inserts markdown blocks (images) at the cursor, each on a line of its own.
    func insertBlocks(_ blocks: [String]) {
        guard let editor, !blocks.isEmpty else { return }
        let joined = blocks.joined(separator: editor.lineBreak + editor.lineBreak)
        apply(MarkdownCommands.insertBlock(joined, text: string as NSString, selection: selectedRange(), lineBreak: editor.lineBreak))
    }

    // MARK: Links

    /// Format → Link… (⌘K): a small popover to add a link, or change the one the cursor is in.
    @objc func editLink(_ sender: Any?) {
        guard let editor else { return }
        let text = string as NSString
        let selection = selectedRange()
        let existing = MarkdownCommands.link(at: selection, in: text, analysis: editor.analysis)
        let range = existing?.range ?? selection
        let popover = NSPopover()
        popover.behavior = .transient
        let editorView = LinkEditor(text: existing?.text ?? text.substring(with: selection),
                                    url: existing?.url ?? "",
                                    isEditing: existing != nil) { [weak self, weak popover] linkText, url in
            popover?.close()
            guard let self, let url else { return }
            self.apply(MarkdownCommands.setLink(text: linkText, url: url, replacing: range))
        }
        popover.contentViewController = NSHostingController(rootView: editorView)
        popover.show(relativeTo: anchorRect(for: range), of: self, preferredEdge: .maxY)
    }

    /// Where a range of text sits in this view, for anchoring a popover.
    private func anchorRect(for range: NSRange) -> NSRect {
        let screen = firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
        guard let window, screen != .zero else { return NSRect(x: bounds.midX, y: visibleRect.minY + 40, width: 1, height: 1) }
        let inWindow = window.convertFromScreen(screen)
        let local = convert(inWindow, from: nil)
        return NSRect(x: local.minX, y: local.minY, width: max(local.width, 1), height: max(local.height, 1))
    }

    /// ⌘-click on a link opens it in the browser (or wherever its address goes).
    func openLink(at index: Int) -> Bool {
        guard let editor else { return false }
        guard let link = MarkdownCommands.link(at: NSRange(location: index, length: 0), in: string as NSString, analysis: editor.analysis),
              let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)), url.scheme != nil else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: Applying

    /// Applies a command's edits as one undoable change, then selects what it says.
    func apply(_ result: MarkdownCommands.Result) {
        let edits = result.edits.sorted { $0.range.location > $1.range.location }
        guard !edits.isEmpty else {
            setSelectedRange(result.selection)
            return
        }
        let ranges = edits.map { NSValue(range: $0.range) }
        guard shouldChangeText(inRanges: ranges, replacementStrings: edits.map(\.replacement)), let textStorage else { return }
        textStorage.beginEditing()
        for edit in edits { textStorage.replaceCharacters(in: edit.range, with: edit.replacement) }
        textStorage.endEditing()
        didChangeText()
        setSelectedRange(result.selection)
        scrollRangeToVisible(result.selection)
    }

    // MARK: Menus

    /// The formatting actions, the state each shows in the menu, and when they're off: in `.txt` files.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        guard let editor, Self.formattingActions.contains(action) else {
            return super.validateMenuItem(menuItem)
        }
        let state = editor.formatting
        let isOn: Bool
        switch action {
        case #selector(toggleBold(_:)): isOn = state.inline.contains(.bold)
        case #selector(toggleItalic(_:)): isOn = state.inline.contains(.italic)
        case #selector(toggleStrikethrough(_:)): isOn = state.inline.contains(.strikethrough)
        case #selector(toggleInlineCode(_:)): isOn = state.inline.contains(.code)
        case #selector(toggleHighlight(_:)): isOn = state.inline.contains(.highlight)
        case #selector(setTitleStyle(_:)): isOn = state.paragraph == .title
        case #selector(setHeadingStyle(_:)): isOn = state.paragraph == .heading
        case #selector(setSubheadingStyle(_:)): isOn = state.paragraph == .subheading
        case #selector(setSmallHeadingStyle(_:)): isOn = state.paragraph == .smallHeading
        case #selector(setBodyStyle(_:)): isOn = state.paragraph == .body
        case #selector(toggleQuote(_:)): isOn = state.paragraph == .quote
        case #selector(toggleCodeBlock(_:)): isOn = state.paragraph == .codeBlock
        case #selector(toggleBulletedList(_:)): isOn = state.list == .bulleted
        case #selector(toggleNumberedList(_:)): isOn = state.list == .numbered
        case #selector(toggleChecklist(_:)): isOn = state.list == .checklist
        case #selector(alignLeft(_:)): isOn = state.alignment == .left
        case #selector(alignCenter(_:)): isOn = state.alignment == .center
        case #selector(alignRight(_:)): isOn = state.alignment == .right
        default: isOn = false
        }
        menuItem.state = isOn ? .on : .off
        return editor.handlesMarkdownInput
    }

    static let formattingActions: Set<Selector> = [
        #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)), #selector(toggleInlineCode(_:)),
        #selector(toggleHighlight(_:)), #selector(clearFormatting(_:)),
        #selector(setTitleStyle(_:)), #selector(setHeadingStyle(_:)), #selector(setSubheadingStyle(_:)),
        #selector(setSmallHeadingStyle(_:)), #selector(setBodyStyle(_:)), #selector(toggleQuote(_:)), #selector(toggleCodeBlock(_:)),
        #selector(toggleBulletedList(_:)), #selector(toggleNumberedList(_:)), #selector(toggleChecklist(_:)),
        #selector(insertDivider(_:)), #selector(insertImage(_:)), #selector(editLink(_:)),
        #selector(alignLeft(_:)), #selector(alignCenter(_:)), #selector(alignRight(_:)),
        #selector(makeTextBigger(_:)), #selector(makeTextSmaller(_:)),
    ]
}

/// The link popover: the text to show and the address.
private struct LinkEditor: View {
    @State var text: String
    @State var url: String
    let isEditing: Bool
    /// Called with the text and address, or a nil address when cancelled.
    let finish: (String, String?) -> Void
    @FocusState private var focus: Field?

    private enum Field { case text, url }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("", text: $text).focused($focus, equals: .text)
            Text("Link").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("https://", text: $url).focused($focus, equals: .url)
                .onSubmit(apply)
            HStack {
                Spacer()
                Button("Cancel") { finish(text, nil) }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Update Link" : "Add Link", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .frame(width: 300)
        .onAppear { focus = text.isEmpty ? .text : .url }
    }

    private func apply() {
        let address = url.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        finish(text.trimmingCharacters(in: .whitespacesAndNewlines), address)
    }
}
