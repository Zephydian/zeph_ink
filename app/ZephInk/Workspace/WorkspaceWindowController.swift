import AppKit
import Observation
import SwiftUI

/// A workspace window: a tab bar in the title bar and the selected document's editor below it.
///
/// Documents don't own this window (they aren't in its `windowControllers`). The controller points its
/// `document` at the selected tab, which puts that document in the responder chain, so File menu
/// actions such as Save and Revert act on the tab you're in.
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private static var all: [WorkspaceWindowController] = []

    let workspace = Workspace()
    /// Set while the window's close button works through its tabs one by one.
    private var isClosingAllTabs = false

    /// The workspace a new or newly opened document joins: the frontmost one, or a new window.
    static func forNewDocument() -> WorkspaceWindowController {
        if let key = all.first(where: { $0.window?.isKeyWindow == true }) ?? all.first {
            return key
        }
        let controller = WorkspaceWindowController()
        all.append(controller)
        return controller
    }

    static func containing(_ document: MarkdownDocument) -> WorkspaceWindowController? {
        all.first { $0.workspace.tab(for: document) != nil }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.chrome
        window.minSize = NSSize(width: 480, height: 320)
        window.isRestorable = false
        window.tabbingMode = .disallowed   // Zeph#Ink draws its own tabs
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WorkspaceView(workspace: workspace, controller: self))
        window.center()
        window.setFrameAutosaveName("Workspace")
        observeWorkspace()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tabs

    func add(_ document: MarkdownDocument) {
        workspace.add(document)
    }

    func show(_ document: MarkdownDocument) {
        workspace.select(document)
        showWindow(nil)
    }

    func select(_ document: MarkdownDocument) {
        workspace.select(document)
    }

    /// Takes away a closed document's tab, and closes the window after its last tab.
    func remove(_ document: MarkdownDocument) {
        workspace.remove(document)
        workspaceDidChange()   // right away, so the window never points at the closed document
        if workspace.tabs.isEmpty {
            window?.close()
        }
    }

    /// Closes a tab, first asking to save its changes if macOS needs to.
    func close(_ document: MarkdownDocument) {
        document.canClose(withDelegate: self,
                          shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard shouldClose else {
            isClosingAllTabs = false
            return
        }
        document.close()
        if isClosingAllTabs, let next = workspace.tabs.first {
            close(next.document)
        }
    }

    @objc func closeTab(_ sender: Any?) {
        if let tab = workspace.selectedTab { close(tab.document) }
    }

    @objc func selectNextTab(_ sender: Any?) {
        workspace.selectTab(offset: 1)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        workspace.selectTab(offset: -1)
    }

    /// View → Show Markdown Source (⌘/): the selected tab switches between page and source view.
    @objc func toggleSourceView(_ sender: Any?) {
        guard let editor = workspace.selectedTab?.editor else { return }
        editor.isSourceMode.toggle()
        window?.makeFirstResponder(editor.textView)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSourceView(_:)) {
            menuItem.state = workspace.selectedTab?.editor.isSourceMode == true ? .on : .off
            return workspace.selectedTab != nil
        }
        return true
    }

    // MARK: - Following the workspace

    /// Keeps the window (its document, title, edited dot and focus) in step with the selected tab.
    private func observeWorkspace() {
        withObservationTracking {
            _ = workspace.selectedTab?.document.name
            _ = workspace.tabs.map(\.document.isEdited)
        } onChange: { [weak self] in
            // onChange runs before the change lands; act on the new state on the next turn.
            DispatchQueue.main.async {
                self?.workspaceDidChange()
                self?.observeWorkspace()
            }
        }
        workspaceDidChange()
    }

    private var focusedTabID: Tab.ID?

    private func workspaceDidChange() {
        guard let window else { return }
        let selected = workspace.selectedTab
        if document !== selected?.document {
            document = selected?.document
        }
        window.title = selected?.document.displayName ?? "Zeph#Ink"
        window.isDocumentEdited = workspace.tabs.contains { $0.document.isEdited }
        if let selected, selected.id != focusedTabID {
            focusedTabID = selected.id
            window.makeFirstResponder(selected.editor.textView)
        }
    }

    // MARK: - NSWindowDelegate

    /// Each tab's typing goes to its own document's undo history, which also drives its "Edited" state.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        workspace.selectedTab?.document.undoManager
    }

    /// The close button closes every tab, asking about unsaved changes one document at a time.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let first = workspace.tabs.first else { return true }
        isClosingAllTabs = true
        close(first.document)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.all.removeAll { $0 === self }
    }
}
