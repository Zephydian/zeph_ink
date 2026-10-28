import SwiftUI

/// The inside of a workspace window: the tab bar (in the title bar, beside the window buttons) above
/// the selected document's editor.
struct WorkspaceView: View {
    let workspace: Workspace
    let controller: WorkspaceWindowController

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                TabBar(workspace: workspace, controller: controller)
                    .frame(height: max(proxy.safeAreaInsets.top, 42))
                Rectangle().fill(Color(.line)).frame(height: 1)
                if let tab = workspace.selectedTab {
                    EditorView(editor: tab.editor)
                        .id(tab.id)
                } else {
                    Color(.page)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(Color(.chrome))
    }
}
