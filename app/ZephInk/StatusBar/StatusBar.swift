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

            Spacer(minLength: 8)

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

    private var saveText: String {
        if document.isEdited { return "Edited" }
        return document.fileURL == nil ? "Not saved yet" : "Saved"
    }

    private var saveColor: Color {
        document.isEdited || document.fileURL == nil ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen)
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
