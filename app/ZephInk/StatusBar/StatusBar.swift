import AppKit
import SwiftUI

/// The bar along the bottom of the window, for the focused pane's document: words (or the
/// selection's words), reading time, the word-count goal's progress, and whether it's saved.
/// Hovering the count shows the characters; clicking it sets a word-count goal.
struct StatusBar: View {
    let document: MarkdownDocument
    let stats: DocumentStats

    @State private var isEditingGoal = false

    var body: some View {
        HStack(spacing: 12) {
            Button { isEditingGoal = true } label: {
                HStack(spacing: 6) {
                    if let goal = stats.goal {
                        GoalRing(progress: Double(stats.words) / Double(max(goal, 1)))
                    }
                    Text(countText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(stats.characters.formatted()) characters. Click to set a word-count goal.")
            .accessibilityLabel(countText)
            .accessibilityHint("Sets a word-count goal")
            .popover(isPresented: $isEditingGoal, arrowEdge: .top) {
                GoalEditor(goal: stats.goal) { goal in
                    isEditingGoal = false
                    stats.goal = goal
                    WordGoals.set(goal, for: document.fileURL)
                }
            }

            HStack(spacing: 5) {
                Circle().fill(saveColor).frame(width: 6, height: 6)
                Text(saveText)
            }
            .accessibilityElement(children: .combine)

            if let shown = Tips.shared.current, shown.document == ObjectIdentifier(document) {
                TipView(tip: shown.tip)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            ZoomControl()
            Rectangle().fill(Color(nsColor: Theme.chromeLine)).frame(width: 1, height: 14)

            Button {
                NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings — ⌘,")
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(Color(nsColor: Theme.chrome))
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: 0.25),
                   value: Tips.shared.current)
    }

    private var countText: String {
        let words = stats.words
        let total = "\(words.formatted()) \(words == 1 ? "word" : "words")"
        let reading = "\(stats.readingMinutes) min read"
        if let selected = stats.selectedWords {
            return "\(selected.formatted()) of \(total) · \(reading)"
        }
        if let goal = stats.goal {
            return "\(words.formatted()) of \(goal.formatted()) words · \(reading)"
        }
        return "\(total) · \(reading)"
    }

    /// A saved file saves itself a moment after typing pauses: "Saving…" until it has, then "Saved".
    /// An untitled document is kept safe too, but only becomes a file when it's saved somewhere.
    private var saveText: String {
        if document.fileURL == nil { return "Not saved yet" }
        return document.isEdited ? "Saving…" : "Saved"
    }

    private var saveColor: Color {
        document.fileURL == nil ? Color(nsColor: .systemOrange)
            : document.isEdited ? Color(nsColor: Theme.chromeInkSecondary) : Color(nsColor: .systemGreen)
    }
}

/// A learning tip: the words, with the markdown in code type. Clicking it puts it away.
private struct TipView: View {
    let tip: Tip

    var body: some View {
        let parts = tip.parts
        HStack(spacing: 5) {
            Image(systemName: "lightbulb").foregroundStyle(Color(nsColor: Theme.accent))
            (Text(parts.before) + Text(parts.syntax).font(Font(Fonts.monoAsTyped(size: 11.5))).foregroundColor(Color(nsColor: Theme.chromeInk))
                + Text(parts.after))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture { Tips.shared.dismiss() }
        .help(tip.text + " Click to hide. Settings → Markdown tips turns tips off.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tip.text)
    }
}

/// Word-style zoom: − and + buttons, a slider, and the percentage, which opens a menu of steps and
/// Fit Page Width. Every page in every window follows it.
private struct ZoomControl: View {
    @AppStorage(Preferences.Key.zoom) private var zoom = 1.0

    private var current: Double { min(max(zoom > 0 ? zoom : 1, Double(Preferences.minZoom)), Double(Preferences.maxZoom)) }

    var body: some View {
        HStack(spacing: 4) {
            Button { Preferences.setZoom(Zoom.step(from: current, up: false)) } label: {
                Image(systemName: "minus").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .help("Zoom out — ⌘−")
            .accessibilityLabel("Zoom out")
            Slider(value: Binding(get: { current }, set: { Preferences.setZoom($0) }),
                   in: Double(Preferences.minZoom)...Double(Preferences.maxZoom))
                .controlSize(.mini)
                .frame(width: 84)
                .accessibilityLabel("Zoom")
                .accessibilityValue("\(Int((current * 100).rounded())) percent")
            Button { Preferences.setZoom(Zoom.step(from: current, up: true)) } label: {
                Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .help("Zoom in — ⌘+")
            .accessibilityLabel("Zoom in")
            Menu {
                ForEach(Zoom.steps, id: \.self) { step in
                    Button("\(Int((step * 100).rounded()))%") { Preferences.setZoom(step) }
                }
                Divider()
                Button("Fit Page Width") {
                    NSApp.sendAction(#selector(WorkspaceWindowController.zoomToFitPage(_:)), to: nil, from: nil)
                }
            } label: {
                Text("\(Int((current * 100).rounded()))%").frame(minWidth: 36, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Zoom")
        }
        .buttonStyle(.plain)
    }
}

/// A small ring that fills as the document nears its word-count goal, and turns green when it's met.
private struct GoalRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color(nsColor: Theme.chromeLine), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(progress >= 1 ? Color(nsColor: .systemGreen) : Color(nsColor: Theme.accent),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// Sets or clears the word-count goal.
private struct GoalEditor: View {
    @State private var text: String
    let finish: (Int?) -> Void

    init(goal: Int?, finish: @escaping (Int?) -> Void) {
        _text = State(initialValue: goal.map(String.init) ?? "")
        self.finish = finish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Word-count goal").font(.system(size: 13, weight: .semibold))
            HStack {
                TextField("1,000", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit(set)
                Text("words").foregroundStyle(.secondary)
            }
            HStack {
                Button("Clear Goal") { finish(nil) }
                Spacer()
                Button("Set Goal", action: set).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func set() {
        finish(Int(text.filter(\.isNumber)))
    }
}
