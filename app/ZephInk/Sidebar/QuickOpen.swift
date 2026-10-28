import AppKit
import SwiftUI

/// File → Quick Open (⌘⇧O): type part of a file's name to jump to an open document or a recent file.
enum QuickOpen {
    struct Item: Identifiable, Equatable {
        /// The file's path, or for an untitled document, the document itself.
        let id: String
        var name: String
        /// Where it is, shortened (`~/Documents/Notes`).
        var folder: String
        var url: URL?
        weak var document: MarkdownDocument?

        static func == (a: Item, b: Item) -> Bool { a.id == b.id }
    }

    /// Open documents first (in every window), then recent files that aren't open.
    @MainActor
    static func candidates() -> [Item] {
        let open = WorkspaceWindowController.all.flatMap { $0.workspace.tabs.map(\.document) }
        var seen = Set<String>()
        var items: [Item] = []
        for document in open {
            let url = document.fileURL
            if let path = url?.standardizedFileURL.path { seen.insert(path) }
            items.append(Item(id: url?.standardizedFileURL.path ?? "untitled-\(ObjectIdentifier(document).hashValue)",
                              name: document.name + document.fileExtension, folder: url.map { folderName($0) } ?? "Open, not saved yet",
                              url: url, document: document))
        }
        for url in NSDocumentController.shared.recentDocumentURLs where !seen.contains(url.standardizedFileURL.path) {
            seen.insert(url.standardizedFileURL.path)
            items.append(Item(id: url.standardizedFileURL.path, name: url.lastPathComponent, folder: folderName(url), url: url, document: nil))
        }
        return items
    }

    private static func folderName(_ url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// How well a name matches what's typed: its letters must appear in order. Matches at the start,
    /// after a space or dash, and in a row score higher. Nil for no match.
    nonisolated static func score(_ name: String, query: String) -> Int? {
        let query = query.lowercased().filter { !$0.isWhitespace }
        guard !query.isEmpty else { return 0 }
        let letters = Array(name.lowercased())
        var score = 0, position = 0, previous = -2
        for wanted in query {
            guard let found = letters[position...].firstIndex(of: wanted) else { return nil }
            score += 1
            if found == previous + 1 { score += 5 }                                           // in a row
            if found == 0 || " -_.".contains(letters[found - 1]) { score += 8 }               // start of a word
            previous = found
            position = found + 1
        }
        return score - letters.count / 10   // shorter names win ties
    }

    @MainActor
    static func ranked(_ items: [Item], query: String) -> [Item] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.compactMap { item in score(item.name, query: query).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Showing it

    @MainActor
    static func show(in window: NSWindow) {
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380), styleMask: [.titled, .fullSizeContentView],
                             backing: .buffered, defer: false)
        sheet.titleVisibility = .hidden
        sheet.titlebarAppearsTransparent = true
        sheet.contentViewController = NSHostingController(rootView: QuickOpenView(items: candidates()) { [weak window, weak sheet] item in
            if let sheet { window?.endSheet(sheet) }
            guard let item else { return }
            open(item)
        })
        window.beginSheet(sheet)
    }

    @MainActor
    private static func open(_ item: Item) {
        if let document = item.document, let controller = WorkspaceWindowController.containing(document) {
            controller.show(document)
        } else if let url = item.url {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }
}

private struct QuickOpenView: View {
    let items: [QuickOpen.Item]
    let finish: (QuickOpen.Item?) -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private var shown: [QuickOpen.Item] { Array(QuickOpen.ranked(items, query: query).prefix(50)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Open quickly", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($isFocused)
                    .onSubmit { finish(shown.indices.contains(selection) ? shown[selection] : nil) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(shown.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                    .onKeyPress(.escape) { finish(nil); return .handled }
                    .onChange(of: query) { selection = 0 }
            }
            .padding(14)
            Divider()
            if shown.isEmpty {
                Text(items.isEmpty ? "No recent files yet" : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == selection)
                                    .id(index)
                                    .onTapGesture { finish(item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
            HStack {
                Text("↑↓ to choose · Return to open · Esc to close").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 520, height: 380)
        .onAppear { isFocused = true }
    }

    private func row(_ item: QuickOpen.Item, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.document != nil ? "doc.text.fill" : "doc.text")
                .foregroundStyle(isSelected ? Color.white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium))
                Text(item.folder).font(.system(size: 11)).foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
            Spacer()
            if item.document != nil {
                Text("Open").font(.system(size: 10, weight: .semibold)).foregroundStyle(isSelected ? Color.white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color(nsColor: Theme.accent) : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
