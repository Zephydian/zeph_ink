import Observation

/// An open document in the workspace, with the editor that shows it.
struct Tab: Identifiable {
    let document: MarkdownDocument
    let editor: Editor

    var id: ObjectIdentifier { ObjectIdentifier(document) }
}

/// The documents open in one workspace window, in tab order, and which one is showing.
@Observable
final class Workspace {
    private(set) var tabs: [Tab] = []
    private(set) var selectedID: Tab.ID?

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedID }
    }

    func tab(for document: MarkdownDocument) -> Tab? {
        tabs.first { $0.document === document }
    }

    /// Adds a tab after the selected one and selects it.
    func add(_ document: MarkdownDocument) {
        guard tab(for: document) == nil else { return }
        let tab = Tab(document: document, editor: Editor(document: document))
        let index = tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        selectedID = tab.id
    }

    func select(_ document: MarkdownDocument) {
        if let tab = tab(for: document) { selectedID = tab.id }
    }

    /// Selects the tab `offset` places away, wrapping around at either end.
    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        let count = tabs.count
        selectedID = tabs[((index + offset) % count + count) % count].id
    }

    /// Removes a document's tab. When it was showing, the tab to its right (or else its left) shows next.
    func remove(_ document: MarkdownDocument) {
        guard let index = tabs.firstIndex(where: { $0.document === document }) else { return }
        let wasSelected = tabs[index].id == selectedID
        tabs.remove(at: index)
        if wasSelected {
            selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }
}
