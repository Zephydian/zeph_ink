import SwiftUI

/// The inside of a workspace window: the tab bar (in the title bar, beside the window buttons) above
/// the editors, side by side when the window is split.
struct WorkspaceView: View {
    let workspace: Workspace
    let controller: WorkspaceWindowController
    @AppStorage(Toolbar.isShownKey) private var showsToolbar = true

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                TabBar(workspace: workspace, controller: controller, height: max(proxy.safeAreaInsets.top, 42))
                Rectangle().fill(Color(.line)).frame(height: 1)
                if showsToolbar, let tab = workspace.selectedTab {
                    Toolbar(editor: tab.editor, controller: controller)
                    Rectangle().fill(Color(.line)).frame(height: 1)
                }
                if workspace.panes.isEmpty {
                    Color(.desk)
                } else {
                    PaneSplitRepresentable(splitView: controller.splitView, panes: panes, focused: workspace.focusedPaneID)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(.chrome))
        .overlay(alignment: .bottom) {
            if let notice = workspace.notice {
                NoticeView(text: notice)
                    .padding(.bottom, 24)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(2.5))
                        if workspace.notice == notice { workspace.notice = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: workspace.notice)
    }

    private var panes: [(pane: Workspace.Pane, editor: Editor)] {
        workspace.panes.compactMap { pane in workspace.tab(id: pane.tabID).map { (pane, $0.editor) } }
    }
}

/// A short message that floats over the window for a moment.
private struct NoticeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color(.page))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.ink)))
            .transition(.opacity.combined(with: .offset(y: 8)))
            .accessibilityAddTraits(.isStaticText)
    }
}
