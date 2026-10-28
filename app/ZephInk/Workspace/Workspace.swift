import Foundation
import Observation

/// An open document in the workspace, with the editor that shows it.
struct Tab: Identifiable {
    let document: MarkdownDocument
    let editor: Editor

    var id: ObjectIdentifier { ObjectIdentifier(document) }
}

/// The documents open in one workspace window: the tabs in order, and the panes (up to three, side by
/// side) that show them. Each pane shows a different tab. The focused pane is the one you're typing in,
/// and its tab is the selected one.
@Observable
final class Workspace {
    struct Pane: Identifiable, Equatable {
        let id = UUID()
        var tabID: Tab.ID
    }

    /// Where a dragged tab goes when it's dropped on an editor: beside a pane.
    enum Side { case left, right }

    static let maxPanes = 3

    private(set) var tabs: [Tab] = []
    private(set) var panes: [Pane] = []
    private(set) var focusedPaneID: Pane.ID?
    /// A short message shown over the window for a moment ("Up to three documents side by side").
    var notice: String?
    /// The sidebar beside the editors, if it's open: the outline, or search across documents.
    var sidebar: Sidebar.Mode?

    var focusedPane: Pane? { panes.first { $0.id == focusedPaneID } }
    var selectedID: Tab.ID? { focusedPane?.tabID }
    var selectedTab: Tab? { selectedID.flatMap(tab(id:)) }
    var isSplit: Bool { panes.count > 1 }

    func tab(id: Tab.ID) -> Tab? {
        tabs.first { $0.id == id }
    }

    func tab(for document: MarkdownDocument) -> Tab? {
        tabs.first { $0.document === document }
    }

    /// The pane showing a tab, if one does.
    func pane(showing id: Tab.ID) -> Pane? {
        panes.first { $0.tabID == id }
    }

    // MARK: - Tabs

    /// Adds a tab after the selected one and shows it in the focused pane.
    func add(_ document: MarkdownDocument) {
        guard tab(for: document) == nil else { return }
        insert(Tab(document: document, editor: Editor(document: document)))
    }

    /// Adds an existing tab (one moved from another window), after the selected one or at `index`.
    func insert(_ tab: Tab, at index: Int? = nil) {
        let position = index ?? tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: min(max(position, 0), tabs.endIndex))
        show(tab.id)
    }

    /// Shows a tab: focuses the pane it's in, or puts it in the focused pane.
    func select(_ document: MarkdownDocument) {
        if let tab = tab(for: document) { show(tab.id) }
    }

    private func show(_ id: Tab.ID) {
        if let pane = pane(showing: id) {
            focusedPaneID = pane.id
        } else if let index = panes.firstIndex(where: { $0.id == focusedPaneID }) {
            panes[index].tabID = id
        } else {
            let pane = Pane(tabID: id)
            panes = [pane]
            focusedPaneID = pane.id
        }
    }

    /// Selects the tab `offset` places away, wrapping around at either end.
    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        let count = tabs.count
        show(tabs[((index + offset) % count + count) % count].id)
    }

    /// Moves a tab to a new place in the tab order.
    func moveTab(_ id: Tab.ID, to index: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: min(max(index, 0), tabs.endIndex))
    }

    /// Takes a tab out of the workspace without closing its document (closing, or moving it to another
    /// window). A pane that showed it shows a neighbouring tab instead, or closes when others are open.
    @discardableResult
    func remove(_ document: MarkdownDocument) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0.document === document }) else { return nil }
        let tab = tabs.remove(at: index)
        guard let paneIndex = panes.firstIndex(where: { $0.tabID == tab.id }) else { return tab }
        if panes.count > 1 {
            closePane(panes[paneIndex].id)
        } else if let next = nextUnshownTab(near: index) {
            panes[paneIndex].tabID = next
        } else {
            panes = []
            focusedPaneID = nil
        }
        return tab
    }

    /// The tab nearest a removed tab's place that no pane shows: the one that was to its right, then
    /// the one to its left, and so on outwards.
    private func nextUnshownTab(near index: Int) -> Tab.ID? {
        for distance in 0..<max(tabs.count, 1) {
            for candidate in [index + distance, index - 1 - distance] where tabs.indices.contains(candidate) {
                if pane(showing: tabs[candidate].id) == nil { return tabs[candidate].id }
            }
        }
        return nil
    }

    // MARK: - Panes

    /// Opens a pane to the right of the focused one, showing the next tab that isn't on screen. With
    /// three panes open it shows a notice instead (`.full`). When every tab is already on screen it
    /// returns `.needsNewDocument`, and the caller opens a new document in the split.
    func splitRight() -> SplitResult {
        guard panes.count < Self.maxPanes else {
            notice = "Up to three documents side by side"
            return .full
        }
        guard let focused = focusedPane, let index = tabs.firstIndex(where: { $0.id == focused.tabID }) else {
            return .full
        }
        let after = tabs[(index + 1)...] + tabs[..<index]
        guard let next = after.first(where: { pane(showing: $0.id) == nil }) else { return .needsNewDocument }
        addPane(showing: next.id, beside: focused.id, side: .right)
        return .split
    }

    enum SplitResult { case split, needsNewDocument, full }

    /// Shows a tab in a new pane beside another. A tab already in a pane moves out of it.
    @discardableResult
    func addPane(showing id: Tab.ID, beside paneID: Pane.ID, side: Side) -> Bool {
        if let shown = pane(showing: id) {
            guard shown.id != paneID, panes.count > 1 else { return false }
            panes.removeAll { $0.id == shown.id }
        } else if panes.count >= Self.maxPanes {
            notice = "Up to three documents side by side"
            return false
        }
        guard let index = panes.firstIndex(where: { $0.id == paneID }) else { return false }
        let pane = Pane(tabID: id)
        panes.insert(pane, at: side == .left ? index : index + 1)
        focusedPaneID = pane.id
        return true
    }

    /// Closes a pane; its tab stays open. The pane to its left (or right) takes the focus.
    func closePane(_ id: Pane.ID) {
        guard panes.count > 1, let index = panes.firstIndex(where: { $0.id == id }) else { return }
        panes.remove(at: index)
        if focusedPaneID == id { focusedPaneID = panes[max(index - 1, 0)].id }
    }

    func focus(_ id: Pane.ID) {
        if panes.contains(where: { $0.id == id }) { focusedPaneID = id }
    }

    /// Moves the focus to the pane `offset` places away (no wrapping).
    func focusPane(offset: Int) {
        guard let index = panes.firstIndex(where: { $0.id == focusedPaneID }) else { return }
        focusedPaneID = panes[min(max(index + offset, 0), panes.count - 1)].id
    }

    /// Restores a saved layout: which tabs the panes show, and which is focused.
    func restorePanes(_ tabIndices: [Int], focused: Int) {
        let ids = tabIndices.compactMap { tabs.indices.contains($0) ? tabs[$0].id : nil }
        var seen = Set<Tab.ID>()
        let unique = ids.filter { seen.insert($0).inserted }.prefix(Self.maxPanes)
        guard !unique.isEmpty else { return }
        panes = unique.map { Pane(tabID: $0) }
        focusedPaneID = panes[min(max(focused, 0), panes.count - 1)].id
    }
}
