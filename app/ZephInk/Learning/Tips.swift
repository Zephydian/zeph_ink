import Foundation
import Observation

/// What to type for a style, shown in the status bar after the style is applied with the toolbar, a
/// menu or a shortcut, so markdown is learned along the way: "Tip: you can also type `## ` at the
/// start of a line."
enum Tip: String, CaseIterable {
    case bold, italic, strikethrough, highlight, inlineCode, link
    case title, heading, subheading, smallHeading, quote, codeBlock
    case bulletedList, numberedList, checklist, divider, image

    /// The tip in three parts: the words before the markdown, the markdown (shown in code type), and
    /// the words after it.
    var parts: (before: String, syntax: String, after: String) {
        switch self {
        case .bold: ("Tip: you can also type ", "**", " on both sides of words to make them bold.")
        case .italic: ("Tip: you can also type ", "*", " on both sides of words to make them italic.")
        case .strikethrough: ("Tip: you can also type ", "~~", " on both sides of words to strike them through.")
        case .highlight: ("Tip: you can also type ", "==", " on both sides of words to highlight them.")
        case .inlineCode: ("Tip: you can also type a backtick ", "`", " on both sides of code.")
        case .link: ("Tip: you can also type ", "[words](address)", " to make a link.")
        case .title: ("Tip: you can also type ", "# ", " at the start of a line.")
        case .heading: ("Tip: you can also type ", "## ", " at the start of a line.")
        case .subheading: ("Tip: you can also type ", "### ", " at the start of a line.")
        case .smallHeading: ("Tip: you can also type ", "#### ", " at the start of a line.")
        case .quote: ("Tip: you can also type ", "> ", " at the start of a line.")
        case .codeBlock: ("Tip: you can also type ", "```", " on the lines before and after the code.")
        case .bulletedList: ("Tip: you can also type ", "- ", " at the start of a line.")
        case .numberedList: ("Tip: you can also type ", "1. ", " at the start of a line.")
        case .checklist: ("Tip: you can also type ", "- [ ] ", " at the start of a line.")
        case .divider: ("Tip: you can also type ", "---", " on a line of its own.")
        case .image: ("Tip: images are written ", "![description](assets/file.png)", ", so you can type them too.")
        }
    }

    var text: String { parts.before + parts.syntax + parts.after }

    var inline: MarkdownCommands.Inline? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .strikethrough: .strikethrough
        case .highlight: .highlight
        case .inlineCode: .code
        default: nil
        }
    }

    var paragraph: MarkdownCommands.Paragraph? {
        switch self {
        case .title: .title
        case .heading: .heading
        case .subheading: .subheading
        case .smallHeading: .smallHeading
        case .quote: .quote
        case .codeBlock: .codeBlock
        default: nil
        }
    }

    var list: MarkdownCommands.ListKind? {
        switch self {
        case .bulletedList: .bulleted
        case .numberedList: .numbered
        case .checklist: .checklist
        default: nil
        }
    }

    init?(_ inline: MarkdownCommands.Inline) {
        guard let tip = Tip.allCases.first(where: { $0.inline == inline }) else { return nil }
        self = tip
    }

    init?(_ paragraph: MarkdownCommands.Paragraph) {
        guard let tip = Tip.allCases.first(where: { $0.paragraph == paragraph }) else { return nil }
        self = tip
    }

    init?(_ list: MarkdownCommands.ListKind) {
        guard let tip = Tip.allCases.first(where: { $0.list == list }) else { return nil }
        self = tip
    }
}

/// Which tip the status bar shows, and how many times each has been shown. A tip shows up to three
/// times, then retires; Settings → Writing → Markdown tips turns them off.
@Observable
final class Tips {
    static let shared = Tips()

    /// A tip on show, in the status bar of the window showing `document`.
    struct Shown: Equatable {
        var tip: Tip
        var document: ObjectIdentifier
    }

    private(set) var current: Shown?

    static let timesShown = 3
    static let countsKey = "tipsShown"
    /// How long a tip stays.
    static let duration: TimeInterval = 7

    @ObservationIgnored private var hide: DispatchWorkItem?

    /// A style was just applied in `document`: show its tip, unless it has retired or tips are off.
    func offer(_ tip: Tip, in document: AnyObject) {
        guard Preferences.showsTips else { return }
        var counts = Self.counts
        guard counts[tip.rawValue, default: 0] < Self.timesShown else { return }
        let shown = Shown(tip: tip, document: ObjectIdentifier(document))
        guard current != shown else { return }   // already on screen: doesn't count again
        counts[tip.rawValue, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: Self.countsKey)
        current = shown
        hide?.cancel()
        let hide = DispatchWorkItem { [weak self] in self?.dismiss() }
        self.hide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: hide)
    }

    func dismiss() {
        hide?.cancel()
        if current != nil { current = nil }
    }

    static var counts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }
}
