import AppKit
import SwiftUI

/// The panel beside the editors: the focused document's outline, or search across every open document.
struct Sidebar: View {
    enum Mode: String, CaseIterable, Identifiable {
        case outline, search
        var id: String { rawValue }
        var title: String { self == .outline ? "Outline" : "Search" }
    }

    let workspace: Workspace
    let controller: WorkspaceWindowController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { workspace.sidebar ?? .outline }, set: { workspace.sidebar = $0 })) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button {
                    workspace.sidebar = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
                .help("Hide the sidebar")
                .accessibilityLabel("Hide the sidebar")
            }
            .padding(10)
            Rectangle().fill(Color(nsColor: Theme.chromeLine)).frame(height: 1)
            switch workspace.sidebar ?? .outline {
            case .outline:
                if let editor = workspace.selectedTab?.editor {
                    OutlineList(outline: editor.outline) { editor.reveal(NSRange(location: $0, length: 0)) }
                } else {
                    Spacer()
                }
            case .search:
                SearchPanel(search: controller.search)
            }
        }
        .frame(width: 250)
        .background(Color(nsColor: Theme.chrome))
    }
}

/// The document's headings, indented by level; the one the cursor is under is highlighted.
private struct OutlineList: View {
    let outline: Outline
    let jump: (Int) -> Void

    var body: some View {
        if outline.headings.isEmpty {
            VStack(spacing: 6) {
                Text("No headings yet").font(.system(size: 13, weight: .medium))
                Text("Titles and headings show up here.").font(.system(size: 12))
            }
            .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(outline.headings) { heading in
                        OutlineRow(heading: heading, isCurrent: heading.id == outline.current) { jump(heading.location) }
                    }
                }
                .padding(8)
            }
            .accessibilityLabel("Outline")
        }
    }
}

private struct OutlineRow: View {
    let heading: Outline.Heading
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(heading.title)
                .font(.system(size: heading.level == 1 ? 13 : 12.5, weight: heading.level <= 2 ? .semibold : .regular))
                .foregroundStyle(Color(nsColor: isCurrent ? Theme.accent : heading.level <= 2 ? Theme.chromeInk : Theme.chromeInkSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 12 + 8)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(
                    isCurrent ? Color(nsColor: Theme.accentSoft) : isHovered ? Color(nsColor: Theme.hover) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Heading level \(heading.level), \(heading.title)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A search box and the matches in every open document, grouped by document.
private struct SearchPanel: View {
    @Bindable var search: DocumentSearch
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search all documents", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .padding(10)
                .onSubmit { search.run() }
            if !search.query.isEmpty {
                Text(search.total == 0 ? "No matches" :
                        "\(search.total.formatted()) \(search.total == 1 ? "match" : "matches") in \(search.groups.count) \(search.groups.count == 1 ? "document" : "documents")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(search.groups) { group in
                        Section {
                            ForEach(group.matches) { match in
                                MatchRow(match: match)
                            }
                        } header: {
                            Text(group.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: Theme.chromeInk))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: Theme.chrome))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onAppear { isFocused = true }
    }
}

private struct MatchRow: View {
    let match: DocumentSearch.Match
    @State private var isHovered = false

    var body: some View {
        Button {
            if let document = match.document { WorkspaceWindowController.reveal(match.range, in: document) }
        } label: {
            Text(snippet)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? Color(nsColor: Theme.hover) : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    /// The line, with the match in bold accent color.
    private var snippet: AttributedString {
        var text = AttributedString(match.snippet)
        if let range = match.highlight, let lower = AttributedString.Index(range.lowerBound, within: text),
           let upper = AttributedString.Index(range.upperBound, within: text) {
            text[lower..<upper].foregroundColor = Color(nsColor: Theme.chromeInk)
            text[lower..<upper].font = .system(size: 12, weight: .semibold)
        }
        return text
    }
}
