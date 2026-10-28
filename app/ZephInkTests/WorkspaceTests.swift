import AppKit
import Testing
@testable import ZephInk

/// Tabs and panes: what shows where as tabs open, close, move and split.
@MainActor
struct WorkspaceTests {
    private func workspace(tabs count: Int) -> (Workspace, [MarkdownDocument]) {
        let workspace = Workspace()
        let documents = (0..<count).map { _ in MarkdownDocument() }
        documents.forEach(workspace.add)
        return (workspace, documents)
    }

    private func shown(_ workspace: Workspace, _ documents: [MarkdownDocument]) -> [Int] {
        workspace.panes.compactMap { pane in documents.firstIndex { $0 === workspace.tab(id: pane.tabID)?.document } }
    }

    private func focused(_ workspace: Workspace, _ documents: [MarkdownDocument]) -> Int? {
        documents.firstIndex { $0 === workspace.selectedTab?.document }
    }

    @Test func newTabsOpenAfterTheSelectedOneAndShowInThePane() {
        let (workspace, documents) = workspace(tabs: 2)
        workspace.select(documents[0])
        let third = MarkdownDocument()
        workspace.add(third)
        #expect(workspace.tabs.map(\.document) == [documents[0], third, documents[1]])
        #expect(workspace.selectedTab?.document === third)
        #expect(workspace.panes.count == 1)
    }

    @Test func splitRightShowsTheNextTabAndStopsAtThree() {
        let (workspace, documents) = workspace(tabs: 4)
        workspace.select(documents[0])
        #expect(workspace.splitRight() == .split)
        #expect(shown(workspace, documents) == [0, 1])
        #expect(focused(workspace, documents) == 1)
        #expect(workspace.splitRight() == .split)
        #expect(shown(workspace, documents) == [0, 1, 2])
        #expect(workspace.splitRight() == .full)
        #expect(workspace.notice == "Up to three documents side by side")
        #expect(shown(workspace, documents) == [0, 1, 2])
    }

    @Test func splittingWithEveryTabShowingAsksForANewDocument() {
        let (workspace, _) = workspace(tabs: 1)
        #expect(workspace.splitRight() == .needsNewDocument)
        #expect(workspace.panes.count == 1)
    }

    @Test func choosingATabShownInAnotherPaneFocusesThatPane() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.select(documents[0])
        _ = workspace.splitRight()
        workspace.select(documents[0])
        #expect(focused(workspace, documents) == 0)
        #expect(shown(workspace, documents) == [0, 1])
        workspace.select(documents[2])   // not on screen: shows in the focused pane
        #expect(shown(workspace, documents) == [2, 1])
    }

    @Test func closingAPaneKeepsItsTab() {
        let (workspace, documents) = workspace(tabs: 2)
        workspace.select(documents[0])
        _ = workspace.splitRight()
        workspace.closePane(workspace.focusedPane!.id)
        #expect(workspace.panes.count == 1)
        #expect(workspace.tabs.count == 2)
        #expect(focused(workspace, documents) == 0)
    }

    @Test func closingADocumentInASplitClosesItsPane() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.select(documents[0])
        _ = workspace.splitRight()
        workspace.remove(documents[1])
        #expect(shown(workspace, documents) == [0])
        #expect(workspace.tabs.count == 2)
    }

    @Test func closingTheOnlyPanesDocumentShowsItsNeighbour() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.select(documents[1])
        workspace.remove(documents[1])
        #expect(shown(workspace, documents) == [2])   // the tab that was to its right
        workspace.remove(documents[2])
        #expect(shown(workspace, documents) == [0])
        workspace.remove(documents[0])
        #expect(workspace.panes.isEmpty)
    }

    @Test func droppingATabBesideAPaneSplitsThere() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.select(documents[0])
        let first = workspace.focusedPane!.id
        workspace.addPane(showing: workspace.tab(for: documents[2])!.id, beside: first, side: .left)
        #expect(shown(workspace, documents) == [2, 0])
        #expect(focused(workspace, documents) == 2)
        // Dropping a tab that's already in a pane moves it.
        workspace.addPane(showing: workspace.tab(for: documents[2])!.id, beside: first, side: .right)
        #expect(shown(workspace, documents) == [0, 2])
    }

    @Test func tabsReorder() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.moveTab(workspace.tab(for: documents[0])!.id, to: 2)
        #expect(workspace.tabs.map(\.document) == [documents[1], documents[2], documents[0]])
    }

    @Test func aSavedLayoutComesBack() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.restorePanes([2, 0, 2, 7], focused: 1)
        #expect(shown(workspace, documents) == [2, 0])
        #expect(focused(workspace, documents) == 0)
    }

    @Test func focusMovesBetweenPanes() {
        let (workspace, documents) = workspace(tabs: 3)
        workspace.select(documents[0])
        _ = workspace.splitRight()
        _ = workspace.splitRight()
        workspace.focusPane(offset: -1)
        #expect(focused(workspace, documents) == 1)
        workspace.focusPane(offset: -5)
        #expect(focused(workspace, documents) == 0)
    }
}
