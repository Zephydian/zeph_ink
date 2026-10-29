import AppKit
import SwiftUI

/// Help → Markdown Guide: a few short lessons, each with an example to change. What you type shows on
/// the left, and how Zeph#Ink displays it on the right, as you type. Nothing goes online.
final class MarkdownGuideWindowController: NSWindowController {
    static let shared = MarkdownGuideWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        window.title = "Markdown Guide"
        window.contentMinSize = NSSize(width: 680, height: 440)
        window.contentViewController = NSHostingController(rootView: MarkdownGuideView())
        window.center()
        window.setFrameAutosaveName("MarkdownGuide")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func show() {
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
    }
}

/// One lesson: what it's about, and an example to try.
struct Lesson: Identifiable, Hashable {
    var id: Int
    var title: String
    /// A few sentences, in markdown (`code` shows in code type).
    var explanation: String
    var example: String

    static let all: [Lesson] = [
        Lesson(id: 1, title: "Headings",
               explanation: "Start a line with `#` and a space for a title. More `#`s make smaller headings: `##` for a heading, `###` for a subheading. Leave a blank line before the next paragraph.\n\nThe style menu in the toolbar, and ⌘1 to ⌘4, do the same.",
               example: "# My trip\n\n## Day one\n\nWe walked down to the harbor.\n\n### Lunch\n\nFish, of course.\n"),
        Lesson(id: 2, title: "Bold and italic",
               explanation: "Put `**` on both sides of words for **bold**, and `*` for *italic*. `~~` strikes words out, and `==` highlights them.\n\n⌘B and ⌘I work too.",
               example: "This is **really** important.\n\nRead it *slowly*, not ~~quickly~~.\n\nThe ==key part== is here.\n"),
        Lesson(id: 3, title: "Lists and checklists",
               explanation: "Start lines with `-` and a space for a bulleted list, or `1.` for a numbered one. `- [ ]` makes a checklist; an `x` in the brackets ticks it.\n\nIn the editor, Return continues a list and Tab nests an item.",
               example: "- Apples\n- Bread\n  - Sourdough\n\n1. Preheat the oven\n2. Bake for an hour\n\n- [x] Book the train\n- [ ] Pack\n"),
        Lesson(id: 4, title: "Links",
               explanation: "Put the words in square brackets and the address right after in round ones: `[words](address)`.\n\n⌘K adds a link for you, and ⌘-click opens one.",
               example: "Made by [Zephydian](https://zephydian.com).\n\nSee the [notes](notes.md) for more.\n"),
        Lesson(id: 5, title: "Quotes and code",
               explanation: "Start a line with `>` for a quote. Put backticks around `code` in a sentence, and three backticks on the lines before and after a block of code. `---` on a line of its own draws a divider.",
               example: "> The best way out is always through.\n\nRun `make build` first.\n\n```\nlet greeting = \"Hello\"\nprint(greeting)\n```\n\n---\n"),
        Lesson(id: 6, title: "Tables and images",
               explanation: "A table is rows of cells between `|` bars, with a line of `---` under the first row. Zeph#Ink shows tables in code type so the columns line up; other apps draw them as grids.\n\nAn image is `![description](file)`. Format → Image… or dropping a picture on the page writes it for you, and copies the picture into an `assets` folder next to the document. (The examples here have no pictures, so only the description shows.)",
               example: "| Fruit  | Price |\n| ------ | ----- |\n| Apples | 2.50  |\n| Pears  | 3.00  |\n\n![The harbor at sunset](assets/harbor.jpg)\n"),
    ]
}

struct MarkdownGuideView: View {
    @State private var lessonID = 1
    @State private var texts: [Int: String] = [:]

    private var lesson: Lesson { Lesson.all.first { $0.id == lessonID } ?? Lesson.all[0] }

    var body: some View {
        HStack(spacing: 0) {
            List(Lesson.all, selection: Binding(get: { lessonID }, set: { if let id = $0 { lessonID = id } })) { lesson in
                Text("\(lesson.id)  \(lesson.title)").tag(lesson.id)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            VStack(alignment: .leading, spacing: 14) {
                Text(lesson.title).font(.system(size: 20, weight: .semibold))
                Text((try? AttributedString(markdown: lesson.explanation,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                     ?? AttributedString(lesson.explanation))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 12) {
                    box("You type") {
                        MarkdownSourceBox(text: Binding(get: { texts[lessonID] ?? lesson.example },
                                                        set: { texts[lessonID] = $0 }))
                    }
                    box("It looks like") {
                        MarkdownPreviewBox(markdown: texts[lessonID] ?? lesson.example)
                    }
                }
                HStack {
                    Button("Reset Example") { texts[lessonID] = nil }
                        .disabled(texts[lessonID] == nil)
                    Button("Try in a New Document") { MarkdownGuideView.openDocument(with: texts[lessonID] ?? lesson.example) }
                        .help("Opens this example as a new document, to keep writing in Zeph#Ink itself.")
                    Spacer()
                    Button("Back") { lessonID -= 1 }
                        .disabled(lessonID == 1)
                    if lessonID < Lesson.all.count {
                        Button("Next Lesson") { lessonID += 1 }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Start Writing") {
                            NSApp.keyWindow?.close()
                            WorkspaceWindowController.bringForward()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 460, idealHeight: 540)
    }

    /// A new untitled document holding the example, in the frontmost workspace window. It counts as
    /// changed, so it's kept like anything else you write.
    static func openDocument(with text: String) {
        guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? MarkdownDocument else { return }
        document.storage.replaceCharacters(in: NSRange(location: 0, length: document.storage.length), with: text)
        document.updateChangeCount(.changeDone)
        document.showWindows()
    }

    private func box(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
                .frame(minHeight: 200, idealHeight: 280, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The two boxes

/// The left box: markdown as plain monospaced text, editable.
struct MarkdownSourceBox: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = Fonts.monoAsTyped(size: 12.5)
        textView.textColor = Theme.ink
        textView.backgroundColor = Theme.codeBackground
        textView.insertionPointColor = Theme.pageAccent
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.setAccessibilityLabel("Markdown to try")
        textView.delegate = context.coordinator
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// The right box: the markdown as Zeph#Ink shows it on the page, every symbol hidden.
struct MarkdownPreviewBox: NSViewRepresentable {
    var markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.preview.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.preview.show(markdown)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let preview = MarkdownPreview()
    }
}

/// A read-only page showing markdown styled like the editor in Clean mode with nothing revealed, at
/// a fixed text size.
final class MarkdownPreview: NSObject, NSTextLayoutManagerDelegate {
    let scrollView = NSScrollView()
    let textView: NSTextView
    private let contentStorage = NSTextContentStorage()
    private let storage = NSTextStorage()
    private var shown: String?

    static let bodySize: CGFloat = 13

    override init() {
        contentStorage.textStorage = storage
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        textView = NSTextView(frame: .zero, textContainer: container)
        super.init()
        layoutManager.delegate = self
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = Theme.page
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("How it looks")
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.page
    }

    func show(_ markdown: String) {
        guard markdown != shown else { return }
        shown = markdown
        Theme.withBodySize(Self.bodySize) {
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: markdown)
            MarkdownStyler.applyAll(MarkdownAnalysis(markdown), to: storage, mode: .page(.clean))
            storage.endEditing()
        }
    }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        PageLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
