import AppKit
import Observation
import SwiftUI

/// A workspace window: a tab bar in the title bar and up to three editors side by side below it.
///
/// Documents don't own this window (they aren't in its `windowControllers`). The controller points its
/// `document` at the focused pane's document, which puts that document in the responder chain, so File
/// menu actions such as Save and Revert act on the document you're in.
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private(set) static var all: [WorkspaceWindowController] = []

    let workspace = Workspace()
    let splitView = PaneSplitView()
    /// Find in All Documents, for this window's sidebar.
    let search = DocumentSearch()
    /// Set while the window's close button works through its tabs one by one.
    private var isClosingAllTabs = false

    /// The workspace a new or newly opened document joins: the frontmost one, or a new window.
    static func forNewDocument() -> WorkspaceWindowController {
        all.first { $0.window?.isKeyWindow == true } ?? all.first { $0.window?.isMainWindow == true } ?? all.first ?? makeNew()
    }

    /// A new, empty workspace window, placed a little below and right of the frontmost one.
    static func makeNew() -> WorkspaceWindowController {
        let controller = WorkspaceWindowController()
        if let front = all.first(where: { $0.window?.isMainWindow == true }) ?? all.last, let frontWindow = front.window {
            controller.window?.setFrame(frontWindow.frame, display: false)
            controller.window?.cascadeTopLeft(from: NSPoint(x: frontWindow.frame.minX + 24, y: frontWindow.frame.maxY - 24))
        }
        all.append(controller)
        return controller
    }

    static func containing(_ document: MarkdownDocument) -> WorkspaceWindowController? {
        all.first { $0.workspace.tab(for: document) != nil }
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.chrome
        window.minSize = NSSize(width: 480, height: 320)
        window.isRestorable = false        // the session reopens windows instead (see Session)
        window.tabbingMode = .disallowed   // Zeph#Ink draws its own tabs
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WorkspaceView(workspace: workspace, controller: self))
        window.center()
        observeWorkspace()
        // The focus line and drop highlight are layer colors: redraw them in a new accent.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.splitView.containers.forEach { $0.needsLayout = true }
                self?.window?.contentView?.needsDisplay = true
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tabs

    func add(_ document: MarkdownDocument) {
        workspace.add(document)
        if let tab = workspace.tab(for: document) { connect(tab) }
    }

    /// Typing in an editor focuses its pane.
    private func connect(_ tab: Tab) {
        tab.editor.didBecomeFocused = { [weak self, weak document = tab.document] in
            guard let self, let document, let tab = self.workspace.tab(for: document),
                  let pane = self.workspace.pane(showing: tab.id) else { return }
            self.workspace.focus(pane.id)
        }
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

    /// ⌘W: closes the focused pane when the window is split (its tab stays open), otherwise the tab.
    @objc func closeTab(_ sender: Any?) {
        if workspace.isSplit, let pane = workspace.focusedPane {
            workspace.closePane(pane.id)
        } else if let tab = workspace.selectedTab {
            close(tab.document)
        }
    }

    @objc func selectNextTab(_ sender: Any?) {
        workspace.selectTab(offset: 1)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        workspace.selectTab(offset: -1)
    }

    // MARK: - Views and panes

    /// View → Show Markdown Source (⌘/): the focused pane switches between page and source view.
    @objc func toggleSourceView(_ sender: Any?) {
        guard let editor = workspace.selectedTab?.editor, !editor.isPlainText else { return }
        editor.isSourceMode.toggle()
        window?.makeFirstResponder(editor.textView)
        saveSessionSoon()
    }

    /// View → Split Right (⌘\): the next tab opens beside the focused one (a new document if every tab
    /// is already showing).
    @objc func splitRight(_ sender: Any?) {
        guard workspace.splitRight() == .needsNewDocument, let focused = workspace.focusedPane else { return }
        guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(false) as? MarkdownDocument else { return }
        if WorkspaceWindowController.containing(document) == nil { add(document) }
        if let tab = workspace.tab(for: document) {
            workspace.addPane(showing: tab.id, beside: focused.id, side: .right)
        }
    }

    @objc func closeSplit(_ sender: Any?) {
        if workspace.isSplit, let pane = workspace.focusedPane { workspace.closePane(pane.id) }
    }

    @objc func focusNextPane(_ sender: Any?) {
        workspace.focusPane(offset: 1)
    }

    @objc func focusPreviousPane(_ sender: Any?) {
        workspace.focusPane(offset: -1)
    }

    /// Format → Bigger Text and Smaller Text: the body text size, one step at a time.
    @objc func makeTextBigger(_ sender: Any?) {
        BodyTextSize.change(to: Preferences.textSize(after: Preferences.textSize, bigger: true), for: workspace.selectedTab?.editor, in: window)
    }

    @objc func makeTextSmaller(_ sender: Any?) {
        BodyTextSize.change(to: Preferences.textSize(after: Preferences.textSize, bigger: false), for: workspace.selectedTab?.editor, in: window)
    }

    /// View → Fit Page Width: zooms so the page (with a little desk around it) fills the focused pane.
    @objc func zoomToFitPage(_ sender: Any?) {
        guard let editor = workspace.selectedTab?.editor else { return }
        let page = PageGeometry.current(viewWidth: 100_000).pageSize.width
        Preferences.setZoom(Zoom.fitting(pageWidth: page, desk: Theme.deskMargin.width, in: editor.scrollView.frame.width))
    }

    /// File → Quick Open (⌘⇧O).
    @objc func quickOpen(_ sender: Any?) {
        if let window { QuickOpen.show(in: window) }
    }

    /// View → Show Outline (⌥⌘O): the focused document's headings in the sidebar.
    @objc func toggleOutline(_ sender: Any?) {
        workspace.sidebar = workspace.sidebar == .outline ? nil : .outline
    }

    /// Edit → Find → Find in All Documents (⌥⇧⌘F): search every open document from the sidebar.
    @objc func findInAllDocuments(_ sender: Any?) {
        if let selected = workspace.selectedTab?.editor.textView, selected.selectedRange().length > 0, selected.selectedRange().length < 100 {
            search.query = (selected.string as NSString).substring(with: selected.selectedRange())
        }
        workspace.sidebar = .search
        search.run()
    }

    /// Shows a match: brings its window forward, its tab into the focused pane, and selects it.
    static func reveal(_ range: NSRange, in document: MarkdownDocument) {
        guard let controller = containing(document), let tab = controller.workspace.tab(for: document) else { return }
        controller.workspace.select(document)
        controller.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { tab.editor.reveal(range) }   // after the tab is in its pane
    }

    /// File → Convert to Markdown: saves a `.md` copy of the focused `.txt` file and opens it in its place.
    @objc func convertToMarkdown(_ sender: Any?) {
        guard let document = workspace.selectedTab?.document, document.isPlainText else { return }
        MarkdownConversion.convert(document, in: self)
    }

    /// Opens `replacement` in the tab and pane that showed `document`, then closes `document`.
    func replace(_ document: MarkdownDocument, with replacement: MarkdownDocument) {
        guard let index = workspace.tabs.firstIndex(where: { $0.document === document }) else { return }
        let pane = workspace.pane(showing: workspace.tabs[index].id)
        if WorkspaceWindowController.containing(replacement) == nil {
            let tab = Tab(document: replacement, editor: Editor(document: replacement))
            workspace.insert(tab, at: index + 1)
            connect(tab)
        }
        if let pane, let tab = workspace.tab(for: replacement) {
            workspace.focus(pane.id)
            workspace.select(tab.document)
        }
        document.close()
    }

    /// Help → Markdown Cheat Sheet (⌘?): under the toolbar's ? button, or at the top of the page
    /// when the toolbar is hidden.
    @objc func showCheatSheet(_ sender: Any?) {
        guard let editor = workspace.selectedTab?.editor else { return }
        if Toolbar.isShown, !Preferences.focusMode {
            workspace.showsCheatSheet.toggle()
        } else {
            CheatSheet.show(over: editor.textView)
        }
    }

    /// File → Export as PDF… (⌘⇧E): the selected tab's document.
    @objc func exportAsPDF(_ sender: Any?) {
        guard let document = workspace.selectedTab?.document, let window else { return }
        PDFExport.run(document, in: window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let selected = workspace.selectedTab
        switch menuItem.action {
        case #selector(toggleSourceView(_:)):
            menuItem.state = selected?.editor.isSourceMode == true ? .on : .off
            return selected.map { !$0.editor.isPlainText } ?? false
        case #selector(closeTab(_:)):
            menuItem.title = workspace.isSplit ? "Close Split" : "Close Tab"
            return selected != nil
        case #selector(closeSplit(_:)):
            return workspace.isSplit
        case #selector(focusNextPane(_:)), #selector(focusPreviousPane(_:)):
            return workspace.isSplit
        case #selector(toggleOutline(_:)):
            menuItem.title = workspace.sidebar == .outline ? "Hide Outline" : "Show Outline"
            return true
        case #selector(convertToMarkdown(_:)):
            return selected?.document.isPlainText == true && selected?.document.fileURL != nil
        case #selector(exportAsPDF(_:)), #selector(showCheatSheet(_:)):
            return selected != nil
        default:
            return true
        }
    }

    // MARK: - Dragging tabs

    /// While a tab is dragged below the tab bar: highlights the half of the pane it would open beside.
    func tabDragMoved(_ document: MarkdownDocument, to screenPoint: NSPoint) {
        for controller in Self.all { controller.splitView.containers.forEach { $0.dropSide = nil } }
        if let (_, container, side) = Self.dropTarget(at: screenPoint, for: document) {
            container.dropSide = side
        }
    }

    /// A tab dropped outside the tab bar: beside a pane (in this window or another), into another
    /// window, or anywhere else into a window of its own.
    func tabDragEnded(_ document: MarkdownDocument, at screenPoint: NSPoint) {
        for controller in Self.all { controller.splitView.containers.forEach { $0.dropSide = nil } }
        if let (target, container, side) = Self.dropTarget(at: screenPoint, for: document) {
            target.take(document, from: self)
            if let tab = target.workspace.tab(for: document) {
                target.workspace.addPane(showing: tab.id, beside: container.paneID, side: side)
            }
            target.window?.makeKeyAndOrderFront(nil)
            return
        }
        if let target = Self.controller(at: screenPoint) {
            if target !== self {
                target.take(document, from: self)
                target.window?.makeKeyAndOrderFront(nil)
            }
            return
        }
        // Dropped outside every window: tear the tab off into its own window, under the pointer.
        guard workspace.tabs.count > 1 else { return }
        let target = Self.makeNew()
        target.take(document, from: self)
        if let window = target.window {
            window.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 120, y: screenPoint.y + 14))
            target.showWindow(nil)
        }
    }

    /// Moves a document's tab (with its editor, selection and undo history) here from another window.
    private func take(_ document: MarkdownDocument, from source: WorkspaceWindowController) {
        guard source !== self else { return }
        guard let tab = source.workspace.remove(document) else { return }
        source.workspaceDidChange()
        workspace.insert(tab)
        connect(tab)
        if source.workspace.tabs.isEmpty { source.window?.close() }
    }

    /// The pane under a screen point, in whichever window is there, and the half the point is in.
    /// Nil over a tab bar, or over the pane already showing the dragged document.
    private static func dropTarget(at screenPoint: NSPoint, for document: MarkdownDocument)
        -> (WorkspaceWindowController, PaneContainer, Workspace.Side)? {
        guard let target = controller(at: screenPoint), let window = target.window else { return nil }
        let point = window.convertPoint(fromScreen: screenPoint)
        guard let (container, side) = target.splitView.pane(at: point) else { return nil }
        if let pane = target.workspace.panes.first(where: { $0.id == container.paneID }),
           target.workspace.tab(id: pane.tabID)?.document === document { return nil }
        return (target, container, side)
    }

    private static func controller(at screenPoint: NSPoint) -> WorkspaceWindowController? {
        let number = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
        return all.first { $0.window?.windowNumber == number }
    }

    // MARK: - Synced scrolling

    /// Watched clip views, by the editor they belong to.
    private var scrollObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var isSyncingScroll = false

    /// Keeps watching the scrolling of exactly the editors on screen.
    private func watchPaneScrolling() {
        let editors = workspace.panes.compactMap { workspace.tab(id: $0.tabID)?.editor }
        let ids = Set(editors.map(ObjectIdentifier.init))
        for (id, observer) in scrollObservers where !ids.contains(id) {
            NotificationCenter.default.removeObserver(observer)
            scrollObservers[id] = nil
        }
        for editor in editors where scrollObservers[ObjectIdentifier(editor)] == nil {
            let clip = editor.scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            scrollObservers[ObjectIdentifier(editor)] = NotificationCenter.default.addObserver(
                // Delivered at once (not queued), so the other panes move in the same frame.
                forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self, weak editor] _ in
                MainActor.assumeIsolated {
                    if let editor { self?.paneDidScroll(editor) }
                }
            }
        }
    }

    /// View → Synced Scrolling: the other panes follow, each to the same point in its own document
    /// (halfway down one is halfway down the others).
    private func paneDidScroll(_ source: Editor) {
        guard Preferences.syncedScrolling, workspace.isSplit, !isSyncingScroll else { return }
        isSyncingScroll = true
        defer { isSyncingScroll = false }
        let fraction = Self.scrollFraction(of: source.scrollView)
        for pane in workspace.panes {
            guard let editor = workspace.tab(id: pane.tabID)?.editor, editor !== source else { continue }
            let clip = editor.scrollView.contentView
            let range = max((editor.scrollView.documentView?.frame.height ?? 0) - clip.bounds.height, 0)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: (fraction * range).rounded()))
            editor.scrollView.reflectScrolledClipView(clip)
        }
    }

    private static func scrollFraction(of scrollView: NSScrollView) -> CGFloat {
        let clip = scrollView.contentView
        let range = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
        return range > 0 ? min(max(clip.bounds.origin.y / range, 0), 1) : 0
    }

    // MARK: - Session

    /// This window as the session saves it.
    var sessionWindow: Session.Window? {
        guard let window else { return nil }
        var tabs: [Session.Tab] = []
        var indices: [Tab.ID: Int] = [:]
        for tab in workspace.tabs {
            guard let saved = Session.tab(for: tab.document, isSourceMode: tab.editor.isSourceMode) else { continue }
            indices[tab.id] = tabs.count
            tabs.append(saved)
        }
        guard !tabs.isEmpty else { return nil }
        let panes = workspace.panes.compactMap { indices[$0.tabID] }
        let focused = workspace.panes.firstIndex { $0.id == workspace.focusedPaneID } ?? 0
        return Session.Window(frame: NSStringFromRect(window.frame), tabs: tabs, panes: panes,
                              paneWidths: splitView.fractions.map(Double.init), focusedPane: focused)
    }

    func restoreLayout(panes: [Int], widths: [CGFloat], focused: Int, frame: String) {
        let rect = NSRectFromString(frame)
        if rect.width >= 200, rect.height >= 200 { window?.setFrame(rect, display: false) }
        workspace.restorePanes(panes, focused: focused)
        if widths.count == workspace.panes.count { splitView.pendingFractions = widths }
    }

    private var sessionSave: DispatchWorkItem?

    /// Saves the session shortly after a change, so even a crash reopens what was open.
    func saveSessionSoon() {
        sessionSave?.cancel()
        let save = DispatchWorkItem { if !Session.isFrozen { Session.current().save() } }
        sessionSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: save)
    }

    // MARK: - Following the workspace

    /// Keeps the window (its document, title, edited dot and focus) in step with the focused pane.
    private func observeWorkspace() {
        withObservationTracking {
            _ = workspace.panes
            _ = workspace.focusedPaneID
            _ = workspace.tabs.map(\.id)
            _ = workspace.selectedTab?.document.name
            _ = workspace.tabs.map(\.document.isEdited)
        } onChange: { [weak self] in
            // onChange runs before the change lands; act on the new state on the next turn.
            DispatchQueue.main.async {
                self?.workspaceDidChange()
                self?.saveSessionSoon()
                self?.observeWorkspace()
            }
        }
        workspaceDidChange()
    }

    private var focusedEditor: ObjectIdentifier?

    func workspaceDidChange() {
        guard let window else { return }
        watchPaneScrolling()
        let selected = workspace.selectedTab
        if document !== selected?.document {
            document = selected?.document
        }
        window.title = selected?.document.displayName ?? "Zeph#Ink"
        window.isDocumentEdited = workspace.tabs.contains { $0.document.isEdited }
        if let selected, ObjectIdentifier(selected.editor) != focusedEditor {
            focusedEditor = ObjectIdentifier(selected.editor)
            DispatchQueue.main.async {   // after SwiftUI has put the editor in the window
                window.makeFirstResponder(selected.editor.textView)
            }
        }
    }

    // MARK: - NSWindowDelegate

    /// Each pane's typing goes to its own document's undo history, which also drives its "Edited" state.
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

    func windowDidResize(_ notification: Notification) {
        saveSessionSoon()
    }

    func windowDidMove(_ notification: Notification) {
        saveSessionSoon()
    }

    func windowWillClose(_ notification: Notification) {
        Self.all.removeAll { $0 === self }
        if !Session.isFrozen { Session.current().save() }
    }
}
